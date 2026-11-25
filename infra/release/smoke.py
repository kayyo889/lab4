"""Probe the deployed app through Nginx, including an authenticated catalogue read."""

import json
from http.cookiejar import CookieJar
import secrets
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import HTTPCookieProcessor, Request, build_opener

base_url, expected_sha = sys.argv[1:]
cookies = CookieJar()
client = build_opener(HTTPCookieProcessor(cookies))


def request(path, expected_status=200, data=None):
    payload = json.dumps(data).encode() if data is not None else None
    req = Request(
        base_url + path, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        response = client.open(req, timeout=8)
    except HTTPError as error:
        response = error
    with response:
        if response.status != expected_status:
            raise RuntimeError(f"{path}: HTTP {response.status}, expected {expected_status}")
        raw = response.read()
    return json.loads(raw) if raw else None


def remove_probe(login):
    subprocess.run(
        [
            "docker", "compose", "--env-file", "release.env", "-p", "music-store-release",
            "-f", "docker-compose.yml", "-f", "compose.release.yml", "exec", "-T", "db",
            "sh", "-ec",
            'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -v login="$1"',
            "psql", login,
        ],
        input="DELETE FROM users WHERE login = :'login';\n",
        text=True,
        check=True,
        timeout=20,
    )


def main():
    if request("/health/ready") != {"status": "ready", "db": "up"}:
        raise RuntimeError("Unexpected readiness response")
    if request("/version") != {"revision": expected_sha}:
        raise RuntimeError("Unexpected revision")
    request("/records", expected_status=401)

    login = "probe_" + secrets.token_hex(9)
    credentials = {"login": login, "password": secrets.token_urlsafe(24)}
    try:
        user = request("/auth/register", expected_status=201, data=credentials)["user"]
        if user["login"] != login or user["role"] != "viewer":
            raise RuntimeError("Unexpected response from registration")
        cookies.clear()
        user = request("/auth/login", data=credentials)["user"]
        if user["login"] != login or not isinstance(request("/records"), list):
            raise RuntimeError("The authenticated catalogue cannot be read")
        request("/auth/logout", expected_status=204, data={})
        request("/records", expected_status=401)
    finally:
        remove_probe(login)
    print(f"Ready, version {expected_sha}, catalogue scenario passed")


if __name__ == "__main__":
    main()
