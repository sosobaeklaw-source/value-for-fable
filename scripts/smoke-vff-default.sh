#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-${TMPDIR:-/tmp}/vff-default-smoke}"
mkdir -p "$out_dir"
out_file="$out_dir/default-smoke.jsonl"

claude -p \
  --model sonnet \
  --tools '' \
  --max-budget-usd "${VFF_SMOKE_MAX_BUDGET_USD:-0.25}" \
  --verbose \
  --include-hook-events \
  --output-format stream-json \
  'vff-default 컨텍스트가 주입되었는지 한 문장으로만 답해라.' \
  >"$out_file"

node - "$out_file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const text = fs.readFileSync(file, 'utf8');
const lines = text.trim().split(/\n+/).filter(Boolean).map((line) => JSON.parse(line));
const sawHook = lines.some((event) => JSON.stringify(event).includes('<vff-default>'));
const sawPlugin = lines.some((event) => JSON.stringify(event).includes('value-for-fable'));
const sawSonnet = lines.some((event) => JSON.stringify(event).includes('sonnet'));
if (!sawHook || !sawPlugin || !sawSonnet) {
  console.error(JSON.stringify({ file, sawHook, sawPlugin, sawSonnet }, null, 2));
  process.exit(1);
}
console.log(JSON.stringify({ file, sawHook, sawPlugin, sawSonnet }, null, 2));
NODE
