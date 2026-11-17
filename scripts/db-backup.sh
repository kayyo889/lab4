#!/bin/sh
set -eu
umask 077
mkdir -p backups
file="${1:-backups/music-store-$(date -u +%Y%m%dT%H%M%SZ).dump}"
test ! -e "$file" || { echo "File already exists: $file" >&2; exit 1; }
temporary=$(mktemp "${file}.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$temporary"
mv "$temporary" "$file"
echo "$file"
