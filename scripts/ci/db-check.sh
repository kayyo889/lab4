#!/bin/sh
set -eu

export DB_USER=ci DB_NAME=ci
DB_PASSWORD=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
export DB_PASSWORD
suffix=$(python3 -c 'import secrets; print(secrets.token_hex(6))')
export COMPOSE_PROJECT_NAME="lab5-$suffix" APP_TAG="db-check-$suffix"
restored="restore-$suffix"
scratch=$(mktemp -d)

cleanup() {
  docker compose down -v --remove-orphans || true
  docker compose -p "$restored" down -v --remove-orphans || true
  docker image rm "music-store:$APP_TAG" >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

compose_sql() {
  docker compose -p "$1" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -Atc "$2"
}

docker compose up -d --wait db
docker compose build migrate
docker compose run --rm --no-deps migrate
docker compose run --rm --no-deps migrate
compose_sql "$COMPOSE_PROJECT_NAME" "CREATE TABLE lab5_restore_probe (value text NOT NULL); INSERT INTO lab5_restore_probe VALUES ('restored');"
sh scripts/db-backup.sh "$scratch/check.dump"
make container-restore BACKUP="$scratch/check.dump" RESTORE_PROJECT="$restored"
test "$(compose_sql "$restored" 'SELECT value FROM lab5_restore_probe')" = restored
test "$(compose_sql "$restored" "SELECT to_regclass('public.records')")" = records
echo 'Миграции, резервная копия и восстановление в отдельной БД прошли проверку.'
