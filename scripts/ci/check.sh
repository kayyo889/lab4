#!/bin/sh
set -eu

NODE_IMAGE=node:22-bookworm@sha256:7c400d78797d8cbe3f6bb21d2227b86af4cd24b0014cc9f62ff989cc16de988e

node_container() {
  docker run --rm -v /work:/work -w /work     -e npm_config_cache=/work/.ci-cache/npm     "$NODE_IMAGE" "$@"
}

case "${1:?install|quality|test|security|container|build|scan|registry}" in
  install)
    node_container npm ci --prefer-offline
    ;;
  quality)
    node_container make quality 'LINT_ARGS=--format json --output-file reports/eslint.json'
    ;;
  test)
    export COMPOSE_PROJECT_NAME=lab5-tests DB_USER=ci DB_NAME=ci
    DB_PASSWORD=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
    export DB_PASSWORD
    trap 'docker compose down -v --remove-orphans' EXIT
    docker compose up -d --wait db
    docker run --rm -v /work:/work -w /work --network "${COMPOSE_PROJECT_NAME}_backend" \
      -e NODE_ENV=test -e DB_HOST=db -e DB_USER -e DB_NAME -e DB_PASSWORD \
      "$NODE_IMAGE" sh -ec 'make migrate && make test "TEST_ARGS=--json --outputFile=reports/jest.json"'
    ;;
  security)
    docker run --rm -v /work:/work zricethezav/gitleaks:v8.24.3       dir /work --config /work/.gitleaks.toml --redact --report-format json --report-path /work/reports/gitleaks.json
    node_container npm audit --audit-level=high --json > reports/npm-audit.json
    ;;
  container)
    make container-check
    ;;
  build)
    revision=${2:?commit SHA required}
    docker build --build-arg "APP_REVISION=$revision" -t "music-store:$revision" .
    ;;
  scan)
    revision=${2:?commit SHA required}
    docker run --rm --network bridge -v /var/run/docker.sock:/var/run/docker.sock       -v /work/reports:/reports -v /work/.ci-cache/trivy:/root/.cache/trivy       aquasec/trivy:0.69.3 image --image-src docker --scanners vuln       --exit-code 1 --severity HIGH,CRITICAL --format json       --output /reports/trivy.json "music-store:$revision"
    ;;
  registry)
    revision=${2:?commit SHA required}
    docker run -d --name lab5-registry -p 127.0.0.1::5000 registry:2.8.3
    trap 'docker rm -f lab5-registry >/dev/null' EXIT
    registry=$(docker port lab5-registry 5000/tcp)
    python3 - "$registry" <<'PYTHON'
import sys
import time
from urllib.request import urlopen

for _ in range(30):
    try:
        with urlopen(f"http://{sys.argv[1]}/v2/", timeout=2):
            break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("Local registry did not start")
PYTHON
    docker tag "music-store:$revision" "$registry/music-store:$revision"
    docker push "$registry/music-store:$revision"
    docker image rm "$registry/music-store:$revision"
    docker pull "$registry/music-store:$revision"
    test "$(docker image inspect -f '{{.Id}}' "music-store:$revision")" = \
      "$(docker image inspect -f '{{.Id}}' "$registry/music-store:$revision")"
    ;;
  *) exit 2 ;;
esac
