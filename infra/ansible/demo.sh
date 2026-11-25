#!/usr/bin/env bash
set -euo pipefail

# This script configures the current, disposable GitHub Actions runner.
test "${GITHUB_ACTIONS:-}" = true
: "${RUNNER_TEMP:?}" "${GITHUB_SHA:?}" "${GHCR_TOKEN:?}"

umask 077
key_dir=$(mktemp -d "$RUNNER_TEMP/ansible-demo.XXXXXX")
trap 'rm -rf "$key_dir"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$key_dir/deploy"

# Avoid two declarations of the same Docker source with different keyrings.
for source in /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources; do
  if sudo test -f "$source"; then sudo mv "$source" "$key_dir/"; fi
done
printf '%s' "$GHCR_TOKEN" | sudo docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin
unset GHCR_TOKEN

export MUSIC_ANSIBLE_HOST=127.0.0.1
export MUSIC_MANAGEMENT_CIDR=127.0.0.1/32
export MUSIC_DEPLOY_PUBLIC_KEY
MUSIC_DEPLOY_PUBLIC_KEY=$(cat "$key_dir/deploy.pub")
export MUSIC_DB_PASSWORD
MUSIC_DB_PASSWORD=$(openssl rand -hex 32)
export MUSIC_RELEASE_SHA=$GITHUB_SHA

apply() {
  ansible-playbook -i inventories/qa/hosts.yml -c local site.yml
}

apply
apply | tee "$key_dir/second-run.log"
grep -E 'music-qa[[:blank:]]+:.*changed=0.*unreachable=0.*failed=0' "$key_dir/second-run.log"

sudo chmod 0644 /opt/music-store/release.env
apply
test "$(sudo stat -c %a /opt/music-store/release.env)" = 600
sudo ufw status | grep 'Status: active'
printf '127.0.0.1 %s\n' "$(sudo cat /etc/ssh/ssh_host_ed25519_key.pub)" > "$key_dir/known_hosts"
set +e
ssh -T -i "$key_dir/deploy" -o BatchMode=yes -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$key_dir/known_hosts" \
  -o ConnectTimeout=10 music-deploy@127.0.0.1 status
ssh_status=$?
set -e
test "$ssh_status" = 2
echo 'Configuration converged, permission drift was repaired, and deploy SSH rejected an unapproved command.'
