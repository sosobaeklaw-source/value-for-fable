# Value-for-Fable (VFF)

Fable 5 수준의 품질을 Sonnet 단가에 — 가성비 AI 운영 모델을 직접 구축한 Claude Code 프로젝트.  
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

작업 종류별 실제 절감폭(입력형 코딩 vs 출력형 글쓰기) 계산과 라우팅 기준은 [COST.md](COST.md) 참고.

### 실측 결과 (2026-06-11, Fable 5 ultracode 환경)

과제 3종(FastAPI 디버깅 조언 / 공모전 기대효과 350자 / RAG 학부생 설명) × 선수 3명(Sonnet+VFF / 맨 Sonnet / 맨 Opus 4.8) × 블라인드 심판 6명(critic 에이전트, 정답 셔플).

| 선수 | 총점 (300점 만점) | 렌즈 1위 횟수 |
|---|---|---|
| **Sonnet + VFF** | **257** | **5 / 6** |
| Opus 4.8 | 237 | 1 / 6 (기술 깊이) |
| 맨 Sonnet | 230 | 0 / 6 |

Opus가 이긴 유일한 렌즈는 async 이벤트루프 블로킹을 혼자 짚어낸 기술 진단 과제였다. 이 영역은 프롬프트로 메꿀 수 없는 지식 천장이고, VFF도 이를 인정한다 — 어려운 진단은 Opus 라우팅이 정답.

**출력 효율**: T1 FastAPI 과제에서 VFF는 1,294자로 Opus(3,440자)와 체감 동률을 기록했다. 출력 토큰 기준 약 1/4이다. 같은 품질에 토큰을 덜 쓰는 게 가성비의 핵심이다.

### Before / After

질문: "배포 후 API가 가끔 500을 뱉어요. 왜죠?"

**맨 Sonnet (VFF 없음)**
```
## 가능한 원인
1. DB 연결 문제
2. 메모리 부족
3. 코드 버그

각각 확인 → 해결하세요.
```
단서('가끔')를 쓰지 않고 동급 후보를 나열한다. 첫 문장에 결론이 없다.

**Sonnet + VFF**
```
코드를 보기 전엔 단정할 수 없지만, '가끔'이라는 패턴이 단서입니다.
항상이 아니라 간헐적이면 설정 오류보다 경합 조건이나 리소스 고갈 쪽이
유력합니다. 가장 싼 확인부터: 500이 찍힌 시각의 서버 로그 한 줄을 보면
두 갈래가 갈립니다 — 타임아웃 계열이면 커넥션 풀 고갈을, 스택트레이스가
있으면 그 코드 경로를 봅니다. 로그를 붙여주시면 거기서 좁히겠습니다.
```
'가끔'을 후보를 갈라내는 단서로 쓰고, 처방 전에 가장 싼 측정을 먼저 제시한다.

### 핵심 원리

VFF가 품질을 끌어올리는 방식은 모델을 바꾸는 게 아니라 **행동 패턴을 바꾸는 것**이다. Fable 5가 실제로 구사하는 운영 패턴 — 단서 우선 가설, 측정 먼저, 결론 첫 문장, 검증 후 완료 선언 — 을 Sonnet에게 명시적으로 주입한다.

---

## 구성

```
value-for-fable/
├── skills/itsvff/SKILL.md      # 세션 모드 — 트리거로 수동 발동
├── agents/itsvff.md            # 위임 전용 에이전트 (2-pass 리뷰 백엔드)
├── output-styles/vff.md        # 상시 모드 — /config에서 선택 시 항상 적용
└── hooks/reminder.sh           # 장기 세션 드리프트 방지 훅
```

### 스킬 (`skills/itsvff/SKILL.md`) — 세션 모드

아래 트리거 중 하나를 입력하면 발동한다. 해당 대화에만 적용되며, 다음 세션에서 다시 트리거해야 한다.

**발동**: `VFF` / `Value-for-Fable` / `패블 모드` / `가성비 패블` / `sonnet을 fable처럼`  
**해제**: `VFF 해제` / `VFF 꺼` / `VFF 그만` / `stop VFF` / `패블 모드 꺼`

발동 시 "VFF 적용" 한 줄, 해제 시 "VFF 해제됨" 한 줄을 출력한다(생략 불가). 세션 끝까지 유지된다.

### 에이전트 (`agents/itsvff.md`) — 2-pass 리뷰 백엔드

사용자가 직접 부르는 게 아니다. 스킬이 내부적으로 위임하는 Sonnet 단가 서브에이전트다.

고난도 과제(원인 진단·기술 심층 분석·고위험 결정 문서)이거나 대화에서 "2-pass" 또는 "리뷰 패스"라고 입력하면 스킬이 자동으로 이 에이전트에 리뷰를 위임한다. 리뷰 기준은 4가지로 고정된다: ①요구사항 누락 ②사실·수치 오류 ③설명되지 않는 단서 ④분량 초과. 기준 밖의 지적은 하지 않는다.

리뷰어는 기본 Sonnet이되, 지식 격차가 의심되는 과제는 Opus로 오버라이드할 수 있다. Sonnet 초안 + Opus 리뷰는 풀 Opus 1회보다 싸면서 Sonnet이 모르는 깊이를 보강한다.

### Output Style (`output-styles/vff.md`) — 상시 모드

`/config` → Output style → **VFF** 선택 시 활성화된다. 트리거 없이 모든 세션에 자동 적용되는 패시브 모드다. `/clear` 이후에도 유지되며, 스킬 트리거와 동시에 쓸 필요 없다(중복 주입 방지).

비용 목표는 `/model sonnet`과 함께 쓸 때 달성된다. 끄려면 `/config` → Output style → default.

### 훅 (`hooks/reminder.sh`) — 드리프트 방지

세션이 길어지면 초기에 주입된 스킬 본문이 컨텍스트 뒤로 밀려 구조가 흐려진다. 훅은 아래 두 조건을 모두 충족할 때만 매 턴 리마인더를 주입한다.

- 조건 1: transcript 파일이 400KB 초과 (기본값, `THRESHOLD` 변수로 조정 가능)
- 조건 2: VFF 활성 상태 (Output Style 설정 또는 transcript에 "VFF 적용" 마커 존재)

두 조건 중 하나라도 불충족이면 아무것도 주입하지 않는다(비용 0).

---

## 8섹션 운영 구조

VFF가 주입하는 구조는 8개 섹션으로 구성된다.

| 섹션 | 핵심 규칙 |
|---|---|
| communication | 첫 문장=결론, 산문 우선, 헤더·불릿은 정말 필요할 때만 |
| style_reference | 맨 Sonnet과 VFF의 실제 응답 차이를 예시로 고정 |
| effort_and_reasoning | 난이도 비례 추론, 확정 사실 재도출 금지, 추천만 |
| tool_discipline | 독립 호출 병렬화, 읽기 전 편집 금지, 불필요한 검색 금지 |
| verification | 완료 전 검증 필수, 단서를 설명하는 가설 우선, 측정 먼저 |
| code_and_changes | 요청 범위 준수, 파괴적 작업 사전 확인, 모호하면 보류 |
| writing_and_research | 출처 명시, 분량 ±5% 준수, 범위 밖 문장 삭제 우선 |
| tone_and_conduct | 필요한 반박 포함, 빈 칭찬 금지, 과잉 사과 금지 |
| token_economy | diff 수준 보고, 완료 후 꼬리 제안 금지 |

---

## 언제 Opus로 라우팅해야 하는가

VFF는 행동 패턴만 바꾼다. Sonnet이 모르는 도메인 지식은 채워주지 않는다. 아래 상황에서는 Opus 라우팅이 정답이다.

- 낯선 도메인이 겹겹인 심층 기술 진단 (async 이벤트루프, 복잡한 분산 시스템 등)
- 여러 도메인 지식이 동시에 필요한 복합 분석
- 추론 자체가 병목인 수학·논리 과제

VFF 스킬은 이 상황을 만나면 본 작업 전에 한 줄 안내한다: "이 과제는 `/effort max`로 올리거나 Opus 라우팅이 더 나을 수 있습니다." 안내 후에는 현재 설정에서 최선을 다하며, 이 안내를 면책으로 쓰지 않는다.

Sonnet에서 전역 `effortLevel: xhigh`는 조용히 `high`로 클램프된다. Sonnet 최고 effort인 `max`는 `/effort max`로만 진입한다.

---

## 설치

```bash
# 1. 폴더 생성 및 파일 복사
mkdir -p ~/.claude/skills/itsvff
cp skills/itsvff/SKILL.md ~/.claude/skills/itsvff/SKILL.md
cp agents/itsvff.md ~/.claude/agents/itsvff.md
cp output-styles/vff.md ~/.claude/output-styles/vff.md
cp hooks/reminder.sh ~/.claude/hooks/reminder.sh
chmod +x ~/.claude/hooks/reminder.sh
```

```bash
# 2. 훅 등록 — ~/.claude/settings.json의 UserPromptSubmit 배열에 아래 블록 추가
```

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "/bin/bash /Users/<your-username>/.claude/hooks/reminder.sh",
      "timeout": 10
    }
  ]
}
```

설치 후 새 세션에서 `/model sonnet` → `VFF` 입력으로 즉시 사용 가능하다.  
Output Style 상시 모드는 `/config` → Output style → VFF 선택.

---

## 한계

VFF는 행동 패턴만 바꾼다. Sonnet이 모르는 도메인 지식을 채워주지 않는다. 순수 추론 천장이 필요한 과제는 Opus 라우팅이 여전히 정답이다.

---

## 출처

- **Fable 5 운영 구조 원본**: [elder-plinius/CL4R1T4S — CLAUDE-FABLE-5.md](https://github.com/elder-plinius/CL4R1T4S/blob/main/ANTHROPIC/CLAUDE-FABLE-5.md). VFF의 8섹션(커뮤니케이션·추론·도구 규율·검증·코드·글쓰기·톤·토큰 절약) 구조는 이 파일에 공개된 Fable 5 시스템 프롬프트에서 운영 원칙을 관찰해 독립적으로 재구성한 것이다.
- 실측 데이터: 2026-06-11 Fable 5 ultracode 환경 단판 표본. 심판 전원 Opus 계열, 과제 문서·조언형 편중.
- 스킬·에이전트·훅 코드: 전체 자작.
