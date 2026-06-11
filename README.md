# Value-for-Fable (VFF)

Sonnet 4.6에 Claude Fable 5의 운영 구조를 이식하는 Claude Code 자산 모음.  
**같은 Sonnet인데 VFF 유무로 5승 vs 0승** — 3-way 블라인드 실측(2026-06-11) 결과.

---

## 왜 Sonnet+VFF인가

### 비용

| 모델 | 입력 ($/1M) | 출력 ($/1M) |
|---|---|---|
| Claude Fable 5 | $10.00 | $50.00 |
| Claude Opus 4.8 | $5.00 | $25.00 |
| **Claude Sonnet 4.6** | **$3.00** | **$15.00** |

Sonnet은 Opus 대비 40%, Fable 대비 70% 저렴하다. 문제는 구조 없이 쓰면 그 차이가 품질 격차로 그대로 드러난다는 것이다. VFF는 그 격차를 운영 구조로 메운다.

### 실측 결과 (2026-06-11, Fable 5 ultracode 환경)

과제 3종(FastAPI 디버깅 조언 / 공모전 기대효과 350자 / RAG 학부생 설명) × 선수 3명(Sonnet+VFF / 맨 Sonnet / 맨 Opus 4.8) × 블라인드 심판 6명(critic 에이전트, 정답 셔플).

| 선수 | 총점 (300점 만점) | 렌즈 1위 횟수 |
|---|---|---|
| **Sonnet + VFF** | **257** | **5 / 6** |
| Opus 4.8 | 237 | 1 / 6 (기술 깊이) |
| 맨 Sonnet | 230 | 0 / 6 |

Opus가 이긴 유일한 렌즈는 async 이벤트루프 블로킹을 혼자 짚어낸 기술 진단 과제였다. 이 영역은 프롬프트로 메꿀 수 없는 지식 천장이고, VFF도 이를 인정한다 — 어려운 진단은 Opus 라우팅이 정답.

**출력 효율**: T1 FastAPI 과제에서 VFF는 1,294자로 Opus(3,440자)와 체감 동률을 기록했다. 출력 토큰 기준 약 1/4이다. 같은 품질에 토큰을 덜 쓰는 게 가성비의 핵심이다.

### 핵심 원리

VFF가 품질을 끌어올리는 방식은 모델을 바꾸는 게 아니라 **행동 패턴을 바꾸는 것**이다.

맨 Sonnet은 질문을 받으면 헤더를 만들고 동급 항목을 나열한다. 단서를 활용하지 않고, 첫 문장에 결론이 없다. VFF를 입히면 첫 문장이 결론이 되고, 관찰된 단서('가끔', '정확히 30초', '산발적')를 후보를 갈라내는 데 쓴다. 처방 전에 가장 싼 측정 한 가지를 먼저 제시하고, 검증 없이 완료를 선언하지 않는다.

이것은 Fable 5가 실제로 구사하는 운영 패턴이다. VFF는 그 패턴을 Sonnet에게 명시적으로 주입한다.

---

## 구성

```
value-for-fable/
├── skills/itsvff/SKILL.md      # 세션 모드 — "VFF" 트리거로 수동 발동
├── agents/itsvff.md            # 위임 전용 에이전트 (2-pass 리뷰 백엔드)
├── output-styles/vff.md        # 상시 모드 — /config에서 선택 시 항상 적용
└── hooks/reminder.sh           # 장기 세션 드리프트 방지 훅
```

### 스킬 (`skills/itsvff/SKILL.md`)

"VFF", "패블 모드", "가성비 패블", "sonnet을 fable처럼" 중 하나를 입력하면 발동한다. 발동 시 "VFF 적용" 한 줄 출력 후 바로 해당 세션에 8섹션 운영 구조를 적용한다. 해제는 "VFF 해제" 또는 "stop VFF".

세션 모드라서 해당 대화에만 적용된다. 다음 세션에서 다시 트리거해야 한다.

### 에이전트 (`agents/itsvff.md`)

사용자가 직접 부르는 게 아니다. 스킬이 2-pass 리뷰를 돌릴 때 별도 컨텍스트에서 Sonnet 단가로 돌리는 백엔드다. 고난도 과제나 "2-pass" 요청 시 스킬이 자동으로 위임한다. 리뷰어 모델은 기본 Sonnet이되, 지식 격차가 의심되는 과제는 Opus로 오버라이드할 수 있다(Sonnet 초안 + Opus 리뷰 < 풀 Opus 1회).

### Output Style (`output-styles/vff.md`)

/config 메뉴에서 Output style을 "VFF"로 선택하면 활성화된다. 스킬과 달리 트리거 없이 모든 세션에 자동 적용되는 패시브 모드다. 한 번 설정하면 /clear 이후에도 유지된다. 스킬 트리거와 동시에 쓸 필요 없다(중복 주입 방지).

비용 목표는 `/model sonnet`과 함께 쓸 때 달성된다.

### 훅 (`hooks/reminder.sh`)

세션이 길어지면 초기에 주입된 스킬 본문이 컨텍스트 뒤로 밀려 구조가 흐려진다. 훅은 transcript가 400KB를 넘고 VFF가 활성 상태일 때만 매 턴 107자짜리 리마인더를 주입한다. 비용은 턴당 약 50토큰.

조건을 모두 충족하지 않으면 아무것도 주입하지 않는다(비용 0).

---

## 설치

```bash
# 1. 파일 복사
cp skills/itsvff/SKILL.md ~/.claude/skills/itsvff/SKILL.md
cp agents/itsvff.md ~/.claude/agents/itsvff.md
cp output-styles/vff.md ~/.claude/output-styles/vff.md
cp hooks/reminder.sh ~/.claude/hooks/reminder.sh
chmod +x ~/.claude/hooks/reminder.sh

# 2. 훅 등록 — ~/.claude/settings.json의 UserPromptSubmit 배열에 추가
# {
#   "matcher": "",
#   "hooks": [{"type": "command", "command": "/bin/bash /Users/<name>/.claude/hooks/reminder.sh", "timeout": 10}]
# }
```

설치 후 새 세션에서 `/model sonnet` → "VFF" 입력으로 즉시 사용 가능하다. Output Style 상시 모드는 `/config` → Output style → VFF 선택.

---

## 한계

VFF는 행동 패턴만 바꾼다. Sonnet이 모르는 도메인 지식을 채워주지 않는다. 순수 추론 천장이 필요한 과제(복잡한 기술 진단, 낯선 도메인 심층 분석)는 Opus 라우팅이 여전히 정답이다. VFF는 그 경계를 사용자에게 먼저 알리도록 설계돼 있다.

출처: 전체 자작. 실측 데이터는 2026-06-11 Fable 5 ultracode 환경 단판 표본이며, 심판 전원이 Opus 계열이고 과제가 문서·조언형에 편중돼 있다.
