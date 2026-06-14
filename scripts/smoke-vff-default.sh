#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-${TMPDIR:-/tmp}/vff-default-smoke}"
mkdir -p "$out_dir"
out_file="$out_dir/default-smoke.jsonl"

claude_status=0
claude -p \
  --model sonnet \
  --tools '' \
  --max-budget-usd "${VFF_SMOKE_MAX_BUDGET_USD:-0.25}" \
  --verbose \
  --include-hook-events \
  --output-format stream-json \
  'vff-default 컨텍스트가 주입되었는지 한 문장으로만 답해라.' \
  >"$out_file" || claude_status=$?

node - "$out_file" "$claude_status" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const claudeStatus = Number(process.argv[3] || '0');
const text = fs.readFileSync(file, 'utf8');
const lines = text.trim().split(/\n+/).filter(Boolean).map((line) => {
  try {
    return JSON.parse(line);
  } catch {
    return { raw: line };
  }
});
const sawHook = lines.some((event) => JSON.stringify(event).includes('<vff-default>'));
const sawPlugin = lines.some((event) => JSON.stringify(event).includes('value-for-fable'));
const sawSonnet = lines.some((event) => JSON.stringify(event).includes('sonnet'));
const authFailed = /401|authentication|Not logged in|Invalid authentication credentials/i.test(text);
console.log(JSON.stringify({ file, sawHook, sawPlugin, sawSonnet, authFailed, claudeStatus }, null, 2));
if (!sawHook || !sawPlugin || !sawSonnet) {
  process.exit(1);
}
if (claudeStatus !== 0) {
  process.exit(claudeStatus);
}
NODE
