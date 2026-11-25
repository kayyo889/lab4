#!/usr/bin/env bash
set -euo pipefail

revision=${GITHUB_SHA:?}
image="ghcr.io/${GITHUB_REPOSITORY,,}"
target=/opt/music-store
sudo install -d -m 0700 "$target" "$target/infra/nginx"
sudo install -m 0644 docker-compose.yml "$target/docker-compose.yml"
sudo install -m 0644 infra/nginx/default.conf "$target/infra/nginx/default.conf"
sudo install -m 0600 infra/release/{compose.release.yml,smoke.py} "$target"
sudo install -m 0755 infra/release/release.sh /usr/local/sbin/music-store-release

password=$(openssl rand -hex 32)
{
  printf 'REGISTRY_IMAGE=%s\nDB_PASSWORD=%s\n' "$image" "$password"
  printf 'HTTP_BIND=127.0.0.1\nHTTP_PORT=18080\n'
} | sudo install -m 0600 /dev/stdin "$target/release.env"
printf '%s' "$GHCR_TOKEN" | sudo docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin
sudo /usr/local/sbin/music-store-release deploy "$revision"

# Simulate a registry tag pointing at the wrong revision on this disposable runner.
sudo docker run -d --name release-demo-registry -p 127.0.0.1:15000:5000 registry:2.8.3
trap 'sudo docker rm -f release-demo-registry >/dev/null' EXIT
curl --fail --silent --show-error --retry 8 --retry-connrefused http://127.0.0.1:15000/v2/
local_image=127.0.0.1:15000/music-store
wrong_revision=0000000000000000000000000000000000000000
for tag in "$revision" "$wrong_revision"; do
  sudo docker tag "$image:$revision" "$local_image:$tag"
  sudo docker push "$local_image:$tag"
done
sudo sed -i "s@^REGISTRY_IMAGE=.*@REGISTRY_IMAGE=$local_image@" "$target/release.env"
if sudo /usr/local/sbin/music-store-release deploy "$wrong_revision"; then
  echo 'Release with wrong image revision unexpectedly passed' >&2
  exit 1
fi
test "$(sudo awk '{print $1}' "$target/.release-state")" = "$revision"
curl --fail --silent --show-error http://127.0.0.1:18080/version | python3 -c \
  'import json, os, sys; sys.exit(json.load(sys.stdin)["revision"] != os.environ["GITHUB_SHA"])'
echo 'Wrong release rejected and the previous version restored'
