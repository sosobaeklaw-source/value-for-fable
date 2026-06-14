#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hook_dir="$claude_dir/hooks"
hook_file="$hook_dir/reminder.sh"
settings_file="$claude_dir/settings.json"

mkdir -p "$hook_dir"

claude plugin marketplace add "$repo_root" --scope user >/dev/null 2>&1 || true
if claude plugin list 2>/dev/null | grep -q 'value-for-fable@itsinseong'; then
  claude plugin update value-for-fable@itsinseong >/dev/null || true
else
  claude plugin install value-for-fable@itsinseong --scope user >/dev/null
fi
claude plugin enable value-for-fable@itsinseong >/dev/null 2>&1 || true

cat > "$hook_file" <<'EOF'
#!/bin/bash

input=$(cat)

if printf '%s' "$input" | grep -Eqi 'VFF[[:space:]]*(해제|그만|꺼|off|disable)|패블[[:space:]]*모드[[:space:]]*(해제|꺼)|stop[[:space:]]+VFF|no[[:space:]]+VFF'; then
  exit 0
fi

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<vff-default>VFF 기본값 적용: 결론 먼저, 근거는 확인한 것만, 도구/검증은 필요한 만큼 병렬화, 완료 주장 전 fresh evidence 확보, 산문 우선으로 읽히게 답한다. 고난도 검토나 품질 비교가 필요하면 itsvff Sonnet 서브에이전트를 우선 고려한다.</vff-default>"}}'
exit 0
EOF
chmod +x "$hook_file"

node - "$settings_file" "$hook_file" <<'NODE'
const fs = require('fs');
const settingsFile = process.argv[2];
const hookFile = process.argv[3];
let settings = {};
if (fs.existsSync(settingsFile)) {
  settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
}
settings.hooks ||= {};
settings.hooks.UserPromptSubmit ||= [];
settings.hooks.UserPromptSubmit = settings.hooks.UserPromptSubmit.filter((entry) => {
  return !JSON.stringify(entry).includes('/hooks/reminder.sh');
});
settings.hooks.UserPromptSubmit.push({
  matcher: '',
  hooks: [{ type: 'command', command: `/bin/bash ${hookFile}`, timeout: 10 }],
});
settings.enabledPlugins ||= {};
settings.enabledPlugins['value-for-fable@itsinseong'] = true;
fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
NODE

claude plugin list | grep -A4 'value-for-fable@itsinseong'
