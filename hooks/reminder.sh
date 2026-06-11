#!/bin/bash
# VFF 장기세션 리마인더 (UserPromptSubmit 훅) — 자작 2026-06-12
# 주입 포맷·stdin 필드 출처: code.claude.com/docs/en/hooks.md (2026-06-12 확인)
# 동작: 아래 두 조건을 모두 충족할 때만 짧은 리마인더를 컨텍스트로 주입, 아니면 침묵(비용 0).
#   조건1 (긴 세션): transcript 파일이 THRESHOLD 바이트 초과 — 스킬 본문 주입이 뒤로 밀려
#                    운영 구조가 희미해지는 시점. 기본 400KB, 필요시 아래 값만 수정.
#   조건2 (VFF 활성): output style이 value-for-fable 이거나(상시 모드),
#                    transcript에 "VFF 적용" 마커가 마지막 "VFF 해제됨" 이후 존재(스킬 모드).

THRESHOLD=400000

input=$(cat)
tp=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$tp" ] && exit 0
[ -f "$tp" ] || exit 0

size=$(wc -c < "$tp" 2>/dev/null | tr -d ' ')
[ "${size:-0}" -lt "$THRESHOLD" ] && exit 0

style_on=0
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
for f in "$HOME/.claude/settings.json" "$cwd/.claude/settings.local.json" "$cwd/.claude/settings.json"; do
  [ -f "$f" ] && grep -qs '"outputStyle"[[:space:]]*:[[:space:]]*"[Vv]alue.[Ff]or.[Ff]able"' "$f" && style_on=1 && break
done

# 마커는 리터럴 한글과 \uXXXX 이스케이프 두 형태 모두 탐지(transcript 기록 방식 방어)
if [ "$style_on" -eq 0 ]; then
  on=$(grep -nF -e 'VFF 적용' -e 'VFF \uc801\uc6a9' "$tp" 2>/dev/null | tail -1 | cut -d: -f1)
  [ -z "$on" ] && exit 0
  off=$(grep -nF -e 'VFF 해제됨' -e 'VFF \ud574\uc81c\ub428' "$tp" 2>/dev/null | tail -1 | cut -d: -f1)
  if [ -n "$off" ] && [ "$off" -gt "$on" ]; then exit 0; fi
fi

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<vff-reminder>VFF 유지: 첫 문장=결론, 산문 우선(토막문장·화살표 체인 금지), 완료 주장 전 검증, 명시 분량은 상한 ±5%, 직접 본 것만 단정.</vff-reminder>"}}'
exit 0
