#!/usr/bin/env bash
set -euo pipefail

container=lab5-dind
case "${1:?start|exec|stop}" in
  start)
    mkdir -p .ci-cache reports
    docker run -d --name "$container" --privileged       --env DOCKER_TLS_CERTDIR= --mount "type=bind,source=$PWD,target=/work"       --workdir /work docker:28.5.2-dind --host=unix:///var/run/docker.sock
    for attempt in {1..30}; do
      if docker exec "$container" docker info >/dev/null 2>&1; then
        docker exec "$container" apk add --no-cache git make python3
        docker exec "$container" git config --global --add safe.directory /work
        exit
      fi
      sleep 2
    done
    docker logs "$container"
    exit 1
    ;;
  exec)
    shift
    docker exec "$container" "$@"
    ;;
  stop)
    docker rm -f "$container" 2>/dev/null || true
    ;;
  *) exit 2 ;;
esac
