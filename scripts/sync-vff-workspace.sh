#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync-vff-workspace.sh <status|push|pull|install|smoke|verify> [target] [remote_dir]

Defaults:
  target     macbookpro on Mac mini, macmini on MacBook
  remote_dir peer workspace path for the detected Mac

Environment:
  VFF_SSH_CONFIG    optional ssh config path
  VFF_SSH_USER      optional ssh user
  VFF_SSH_IDENTITY  optional ssh identity file
  VFF_PEER_TARGET   override default peer ssh target
  VFF_PEER_DIR      override default peer workspace path
  VFF_SYNC_BACKUP   backup directory name for rsync --delete backups

Commands:
  status   print local/remote commit, plugin state, and rsync dry-run drift
  push     publish HEAD, sync this workspace to the remote Mac, and align remote git metadata
  pull     sync the remote Mac workspace back to this Mac and align local git metadata
  install  run VFF default installer on both Macs
  smoke    run VFF smoke on both Macs
  verify   run status, install, then smoke
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_host="$(hostname)"

default_target() {
  case "$local_host" in
    *MacBook*|*Macbook*) printf '%s\n' "${VFF_PEER_TARGET:-macmini}" ;;
    *) printf '%s\n' "${VFF_PEER_TARGET:-macbookpro}" ;;
  esac
}

default_remote_dir() {
  case "$local_host" in
    *MacBook*|*Macbook*) printf '%s\n' "${VFF_PEER_DIR:-/Users/son-won-il/Documents/Codex/2026-06-14-https-github-com-itsinseong-value-for}" ;;
    *) printf '%s\n' "${VFF_PEER_DIR:-/Users/son-won-il/Documents/Codex/value-for-fable}" ;;
  esac
}

cmd="${1:-status}"
target="${2:-$(default_target)}"
remote_dir="${3:-$(default_remote_dir)}"
remote_dir_q="$(printf '%q' "$remote_dir")"
backup_name="${VFF_SYNC_BACKUP:-.vff-sync-backups/$(date +%Y%m%dT%H%M%S)}"

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
rsync_common=(
  -az
  --delete
  --backup
  --backup-dir "$backup_name"
  --exclude '.git/'
  --exclude '.omx/'
  --exclude 'node_modules/'
  --exclude '.vff-sync-backups/'
)

remote() {
  ssh "${ssh_opts[@]}" "$target" "$@"
}

remote_repo() {
  remote "cd $remote_dir_q && $*"
}

local_head() {
  git -C "$repo_root" rev-parse HEAD
}

publish_head() {
  git -C "$repo_root" push -q fork HEAD:master
}

ensure_remote_dir() {
  remote "mkdir -p $remote_dir_q"
}

ensure_remote_git() {
  local head
  head="$(local_head)"
  remote "cd $remote_dir_q && \
    git init -q && \
    (git remote get-url origin >/dev/null 2>&1 || git remote add origin https://github.com/itsinseong/value-for-fable.git) && \
    git remote set-url origin https://github.com/itsinseong/value-for-fable.git && \
    (git remote get-url fork >/dev/null 2>&1 || git remote add fork git@github.com:sosobaeklaw-source/value-for-fable.git) && \
    git remote set-url fork git@github.com:sosobaeklaw-source/value-for-fable.git && \
    git fetch -q fork master && \
    git reset --mixed -q $head"
}

ensure_local_git_from_remote() {
  local remote_head
  remote_head="$(remote_repo "git rev-parse HEAD")"
  git -C "$repo_root" fetch -q fork master
  git -C "$repo_root" reset --mixed -q "$remote_head"
}

sync_push() {
  publish_head
  ensure_remote_dir
  rsync "${rsync_common[@]}" -e "${rsync_ssh[*]}" "$repo_root/" "$target:${remote_dir%/}/"
  ensure_remote_git
}

sync_pull() {
  ensure_remote_dir
  rsync "${rsync_common[@]}" -e "${rsync_ssh[*]}" "$target:${remote_dir%/}/" "$repo_root/"
  ensure_local_git_from_remote
}

plugin_state_local() {
  claude plugin list 2>/dev/null | sed -n '/value-for-fable@itsinseong/,+4p' || true
}

plugin_state_remote() {
  remote "claude plugin list 2>/dev/null | sed -n '/value-for-fable@itsinseong/,+4p' || true"
}

drift_check() {
  rsync -azn --delete \
    --exclude '.git/' \
    --exclude '.omx/' \
    --exclude 'node_modules/' \
    --exclude '.vff-sync-backups/' \
    -e "${rsync_ssh[*]}" \
    "$repo_root/" "$target:${remote_dir%/}/"
}

status_report() {
  ensure_remote_dir
  printf 'local_host=%s\n' "$(hostname)"
  printf 'local_repo=%s\n' "$repo_root"
  printf 'local_head=%s\n' "$(local_head)"
  printf 'local_status=%s\n' "$(git -C "$repo_root" status --short | tr '\n' ';')"
  printf 'remote_host='
  remote 'hostname'
  printf 'remote_repo=%s\n' "$remote_dir"
  if remote "[ -d $remote_dir_q/.git ]"; then
    printf 'remote_head='
    remote_repo 'git rev-parse HEAD'
    printf 'remote_status='
    remote_repo "git status --short | tr '\n' ';'; printf '\n'"
  else
    printf 'remote_head=NO_GIT\n'
    printf 'remote_status=NO_GIT\n'
  fi
  printf 'local_plugin:\n'
  plugin_state_local
  printf 'remote_plugin:\n'
  plugin_state_remote
  printf 'rsync_drift:\n'
  drift_check | sed -n '1,80p'
}

run_install() {
  "$repo_root/scripts/install-vff-default.sh"
  remote_repo './scripts/install-vff-default.sh'
}

run_smoke() {
  "$repo_root/scripts/smoke-vff-default.sh" /tmp/vff-default-smoke-local
  remote_repo './scripts/smoke-vff-default.sh /tmp/vff-default-smoke-remote'
}

case "$cmd" in
  status)
    status_report
    ;;
  push)
    sync_push
    status_report
    ;;
  pull)
    sync_pull
    status_report
    ;;
  install)
    run_install
    ;;
  smoke)
    run_smoke
    ;;
  verify)
    sync_push
    status_report
    run_install
    run_smoke
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
