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

ssh "${ssh_opts[@]}" "$target" 'hostname; scutil --get ComputerName 2>/dev/null || true; command -v claude >/dev/null'

ssh "${ssh_opts[@]}" "$target" "mkdir -p $remote_dir_q"
rsync -az --delete \
  --exclude '.git/' \
  --exclude '.omx/' \
  --exclude 'node_modules/' \
  "$repo_root/" "$target:${remote_dir%/}/"

ssh "${ssh_opts[@]}" "$target" "cd $remote_dir_q && ./scripts/install-vff-default.sh && ./scripts/smoke-vff-default.sh /tmp/vff-default-smoke-macbook"
