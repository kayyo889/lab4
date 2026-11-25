#!/usr/bin/env bash
set -euo pipefail

: "${STAGING_HOST:?}" "${STAGING_SSH_KEY:?}" "${STAGING_KNOWN_HOSTS:?}"
[[ $STAGING_HOST =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]
sha=${1:?Specify commit SHA or rollback}
[[ $sha == rollback || $sha =~ ^[0-9a-f]{40}$ ]]
command=rollback
[[ $sha == rollback ]] || command="deploy $sha"
port=${STAGING_PORT:-22}
[[ $port =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))

umask 077
ssh_dir=$(mktemp -d)
trap 'rm -rf "$ssh_dir"' EXIT
printf '%s\n' "$STAGING_SSH_KEY" > "$ssh_dir/key"
printf '%s\n' "$STAGING_KNOWN_HOSTS" > "$ssh_dir/known_hosts"
ssh -T -p "$port" -i "$ssh_dir/key" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$ssh_dir/known_hosts" \
  -o ConnectTimeout=15 "music-deploy@$STAGING_HOST" "$command"
