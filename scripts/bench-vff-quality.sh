#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
slug="${VFF_BENCH_SLUG:-vff-sonnet-quality}"
baseline="${VFF_BENCH_BASELINE:-$repo_root/.omx/goals/performance/$slug/baseline-vff-v2.md}"
candidate="${VFF_BENCH_CANDIDATE:-$repo_root/output-styles/vff-v2.md}"
task_limit="${VFF_BENCH_TASK_LIMIT:-3}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$repo_root/.omx/goals/performance/$slug/runs/$run_id"

if [[ ! -f "$baseline" ]]; then
  echo "missing baseline prompt: $baseline" >&2
  exit 2
fi
if [[ ! -f "$candidate" ]]; then
  echo "missing candidate prompt: $candidate" >&2
  exit 2
fi

mkdir -p "$run_dir"

node "$repo_root/bench/vff_quality_bench.mjs" \
  --baseline "$baseline" \
  --candidate "$candidate" \
  --run-dir "$run_dir" \
  --task-limit "$task_limit"
