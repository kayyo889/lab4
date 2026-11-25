#!/usr/bin/env bash
set -euo pipefail
umask 077

cd /opt/music-store
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export DOCKER_CONFIG=/root/.docker
unset DOCKER_HOST DOCKER_CONTEXT COMPOSE_FILE COMPOSE_PROJECT_NAME
nginx_hash=$(sha256sum infra/nginx/default.conf)
export NGINX_CONFIG_SHA=${nginx_hash%% *}

valid_sha() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
usage() { echo 'Usage: music-store-release deploy SHA | rollback | reconcile' >&2; exit 2; }

action=${1:-}
case "$action" in
  deploy) [[ $# == 2 ]] && valid_sha "$2" || usage ;;
  rollback|reconcile) [[ $# == 1 ]] || usage ;;
  *) usage ;;
esac

exec 9>.deploy.lock
flock -w 480 9
current=''
previous=''
if [[ -f .release-state ]]; then
  read -r current previous < .release-state
  valid_sha "$current"
  [[ -z $previous ]] || valid_sha "$previous"
fi
case "$action" in
  deploy) target=$2 ;;
  rollback) target=${previous:?No earlier accepted release} ;;
  reconcile) target=${current:?No accepted release} ;;
esac

compose() {
  docker compose --env-file release.env -p music-store-release \
    -f docker-compose.yml -f compose.release.yml "$@"
}

apply_and_check() {
  export RELEASE_TAG=$1
  compose up -d --no-build --pull never --wait --wait-timeout 120 || return
  migrate_status=$(compose ps -aq migrate) || return
  [[ -n $migrate_status ]] || return 1
  [[ $(docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' "$migrate_status") == 'exited 0' ]] || return 1

  for service in db app1 app2 nginx; do
    cid=$(compose ps -q "$service") || return
    [[ -n $cid ]] || return 1
    [[ $(docker inspect --format '{{.State.Health.Status}}' "$cid") == healthy ]] || return 1
    case "$service" in
      app1|app2)
        [[ $(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$cid") == "$RELEASE_TAG" ]] || return 1
        ;;
    esac
  done

  endpoint=$(compose port nginx 8080) || return
  [[ $endpoint =~ ^127\.0\.0\.1:[0-9]+$ ]] || return 1
  python3 smoke.py "http://$endpoint" "$RELEASE_TAG"
}

export RELEASE_TAG=$target
compose config --quiet
if [[ $action == deploy ]]; then
  compose pull
else
  compose pull --policy missing
fi
if apply_and_check "$target"; then
  if [[ $target != "$current" ]]; then
    state=$(mktemp .release-state.XXXXXX)
    printf '%s %s\n' "$target" "$current" > "$state"
    mv -f "$state" .release-state
  fi
  echo "Accepted release $target"
  exit 0
fi

echo "Release verification failed for $target" >&2
if [[ -n $current && $current != "$target" ]]; then
  if apply_and_check "$current"; then
    echo "Restored release $current" >&2
  else
    echo "Could not restore $current" >&2
  fi
elif [[ -z $current ]]; then
  compose stop nginx app1 app2 || true
fi
exit 1
