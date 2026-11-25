#!/usr/bin/env python3
"""Destructive checks run ONLY in uniquely named disposable Compose projects."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
env = dict(os.environ, DB_PASSWORD=secrets.token_hex(24), DB_USER="check", DB_NAME="check",
           HTTP_PORT="0", APP_REVISION="check-v1", APP_TAG="check-" + secrets.token_hex(6))
project = "music-check-" + secrets.token_hex(6)
restore_project = project + "-restore"


def run(args, **kwargs):
    return subprocess.run(args, env=env, check=True, **kwargs)


def compose(*args, project_name=project, capture=False, **kwargs):
    result = run(["docker", "compose", "-p", project_name, *args],
                 stdout=kwargs.pop("stdout", subprocess.PIPE if capture else None), **kwargs)
    return result.stdout.decode().strip() if capture else None


def sql(statement, project_name=project):
    return compose("exec", "-T", "db", "psql", "-U", "check", "-d", "check", "-v",
                   "ON_ERROR_STOP=1", "-Atc", statement, project_name=project_name, capture=True)


def inspect(cid):
    return json.loads(run(["docker", "inspect", cid], capture_output=True).stdout)[0]


def policy():
    cfg = json.loads(compose("config", "--format", "json", capture=True))
    for name, service in cfg["services"].items():
        image = service["image"]
        assert ":latest" not in image and ":" in image, f"{name}: unpinned image"
        if name in ("db", "nginx"):
            assert "@sha256:" in image, f"{name}: missing digest"
        assert service.get("user", "").split(":")[0] not in ("", "0", "root"), f"{name}: root"
        assert not service.get("privileged") and service.get("network_mode") != "host"
        assert service.get("mem_limit") and float(service.get("cpus", 0)) > 0
        assert service.get("pids_limit", 0) > 0
        health = service.get("healthcheck", {})
        assert not health.get("disable") and health.get("test", [""])[0] != "NONE"
        assert not service.get("ports") or name == "nginx", f"{name}: forbidden port"
        assert set(service.get("build", {}).get("args", {})) <= {"APP_REVISION"}, "Forbidden build argument"
    ports = cfg["services"]["nginx"]["ports"]
    assert len(ports) == 1 and ports[0]["target"] == 8080
    assert cfg["networks"]["backend"]["internal"]
    assert cfg["services"]["db"]["volumes"][0]["type"] == "volume"
    dockerfile = Path("Dockerfile").read_text()
    assert "@sha256:" in dockerfile and "npm ci --omit=dev" in dockerfile
    assert 'CMD ["node", "src/index.js"]' in dockerfile
    # Build context is an allowlist; extending it requires policy review.
    assert Path(".dockerignore").read_text().splitlines() == [
        "*", "!package.json", "!package-lock.json", "!src/", "!src/**", "!public/",
        "!public/**", "!migrations/", "!migrations/**", "!knexfile.js", "!Dockerfile"]
    print("Container policy OK", flush=True)


if "--policy-only" in sys.argv:
    env = dict(os.environ)
    policy()
    sys.exit(0)

try:
    policy()
    compose("build")
    image_info = json.loads(run(["docker", "image", "inspect", "music-store:" + env["APP_TAG"]], capture_output=True).stdout)[0]
    assert image_info["Config"]["User"].split(":")[0] not in ("", "0", "root")
    assert image_info["Config"]["Healthcheck"]["Test"][0] != "NONE"
    assert not any(item.startswith("DB_PASSWORD=") for item in image_info["Config"]["Env"])
    compose("up", "-d", "--wait", "--wait-timeout", "180")
    for name in ("db", "app1", "app2", "nginx"):
        cid = compose("ps", "-q", name, capture=True)
        info = inspect(cid)
        assert info["State"]["Health"]["Status"] == "healthy"
        assert info["Config"]["User"].split(":")[0] not in ("", "root", "0")
        uid = compose("exec", "-T", name, "id", "-u", capture=True)
        assert uid != "0"
        if name != "nginx":
            assert not any(info["NetworkSettings"]["Ports"].values())
    endpoint = compose("port", "nginx", "8080", capture=True)
    url = "http://" + endpoint + "/health/ready"

    def request(timeout=20):
        with urllib.request.urlopen(url, timeout=timeout) as response:
            assert response.status == 200
            return response.headers["X-Instance-ID"]

    assert {request() for _ in range(12)} == {"app1", "app2"}, "No load balancing"
    sql("CREATE TABLE container_probe (id integer PRIMARY KEY, value text NOT NULL); "
        "INSERT INTO container_probe VALUES (1, 'persistent-marker');")
    assert int(sql("SELECT count(*) FROM knex_migrations")) >= 4
    compose("down")
    compose("up", "-d", "--wait", "--wait-timeout", "180")
    assert sql("SELECT value FROM container_probe WHERE id=1") == "persistent-marker"
    # Rebuild a distinct application image and recreate the environment, retaining the DB volume.
    env["APP_TAG"] += "-updated"
    env["APP_REVISION"] = "check-v2"
    compose("build")
    updated = json.loads(run(["docker", "image", "inspect", "music-store:" + env["APP_TAG"]], capture_output=True).stdout)[0]
    assert updated["Id"] != image_info["Id"], "Image did not change"
    compose("down")
    compose("up", "-d", "--wait", "--wait-timeout", "180")
    assert sql("SELECT value FROM container_probe WHERE id=1") == "persistent-marker"
    endpoint = compose("port", "nginx", "8080", capture=True)
    url = "http://" + endpoint + "/health/ready"
    cid = compose("ps", "-q", "app1", capture=True)
    started = time.monotonic()
    compose("stop", "app1")
    stopped = inspect(cid)
    assert stopped["State"]["ExitCode"] == 0 and not stopped["State"]["OOMKilled"]
    assert time.monotonic() - started < 20
    assert "SIGTERM" in compose("logs", "app1", capture=True)
    # The Docker DNS entry for the stopped container can linger until Nginx refreshes it.
    deadline = time.monotonic() + 12
    while True:
        try:
            if {request(timeout=3) for _ in range(12)} == {"app2"}:
                break
        except (OSError, urllib.error.URLError):
            if time.monotonic() >= deadline:
                raise
        if time.monotonic() >= deadline:
            raise AssertionError("Failover did not converge within 12 seconds")
        time.sleep(0.5)
    migration_count = sql("SELECT count(*) FROM knex_migrations")
    with tempfile.TemporaryFile() as dump:
        compose("exec", "-T", "db", "pg_dump", "-U", "check", "-d", "check", "-Fc",
                stdout=dump)
        dump.seek(0)
        compose("down")
        compose("up", "-d", "--wait", "--wait-timeout", "120", "db", project_name=restore_project)
        compose("exec", "-T", "db", "pg_restore", "-U", "check", "-d", "check", "--exit-on-error",
                "--no-owner", stdin=dump, project_name=restore_project)
    assert sql("SELECT value FROM container_probe WHERE id=1", restore_project) == "persistent-marker"
    assert sql("SELECT count(*) FROM knex_migrations", restore_project) == migration_count
    print("PASS: policy, build, non-root, health, migrations, persistence, image update, "
          "SIGTERM, balancing, failover, backup and restore into a new volume", flush=True)
except Exception:
    compose("logs", "--tail", "60")
    raise
finally:
    for name in (project, restore_project):
        subprocess.run(["docker", "compose", "-p", name, "down", "-v", "--remove-orphans"], env=env)
