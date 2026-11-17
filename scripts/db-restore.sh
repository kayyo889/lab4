#!/bin/sh
set -eu
: "${1:?Usage: sh scripts/db-restore.sh backup.dump new-project-name}"
: "${2:?Provide a NEW Compose project name}"
test -r "$1" || { echo "Backup is not readable" >&2; exit 1; }
case "$2" in restore-*) ;; *) echo 'Project must start with restore-' >&2; exit 1;; esac
# Refuse any existing project volume: restore must never overwrite the running DB.
test -z "$(docker volume ls -q --filter "label=com.docker.compose.project=$2")" || { echo 'Project volume already exists' >&2; exit 1; }
docker compose -p "$2" up -d --wait db
docker compose -p "$2" exec -T db sh -c 'exec pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error' < "$1"
echo "Restored into project $2; its volume is retained."
