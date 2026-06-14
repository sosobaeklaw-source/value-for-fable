#!/usr/bin/env bash
set -euo pipefail

target="${1:-macbookpro}"
remote_dir="${2:-/Users/son-won-il/Documents/Codex/value-for-fable}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remote_dir_q="$(printf '%q' "$remote_dir")"

ssh_opts=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ConnectionAttempts=1
)

if [ -n "${VFF_SSH_CONFIG:-}" ]; then
  ssh_opts+=(-F "$VFF_SSH_CONFIG")
fi
if [ -n "${VFF_SSH_USER:-}" ]; then
  ssh_opts+=(-o "User=$VFF_SSH_USER")
fi
if [ -n "${VFF_SSH_IDENTITY:-}" ]; then
  ssh_opts+=(-i "$VFF_SSH_IDENTITY")
fi

rsync_ssh=(ssh "${ssh_opts[@]}")

ssh "${ssh_opts[@]}" "$target" 'hostname; scutil --get ComputerName 2>/dev/null || true; command -v claude >/dev/null'

ssh "${ssh_opts[@]}" "$target" "mkdir -p $remote_dir_q"
rsync -az --delete -e "${rsync_ssh[*]}" \
  --exclude '.git/' \
  --exclude '.omx/' \
  --exclude 'node_modules/' \
  "$repo_root/" "$target:${remote_dir%/}/"

ssh "${ssh_opts[@]}" "$target" "cd $remote_dir_q && ./scripts/install-vff-default.sh && ./scripts/smoke-vff-default.sh /tmp/vff-default-smoke-macbook"
