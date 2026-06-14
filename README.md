# 𝐕𝐚𝐥𝐮𝐞-𝐟𝐨𝐫-𝐅𝐚𝐛𝐥𝐞 (𝐕𝐅𝐅)

**Opus에 근접한 품질을 Sonnet 단가에 — 가성비 AI 운영 모델을 직접 구축한 Claude Code 프로젝트**

***🡒 PRO 사용자들에겐 추천, OPUS 사용자 들에겐 비추천***

Fable5 구조를 넣은 Sonnet이 Opus와 블라인드 테스트에서 사실상 비겼다!!
그것도 답 1건당 비용 3분의 1로!!([bench/](bench/RESULTS.md)) 

## 왜 Sonnet+VFF인가

### 비용

| 모델 | 입력 ($/1M) | 출력 ($/1M) |
|---|---|---|
| Claude Fable 5 | $10.00 | $50.00 |
| Claude Opus 4.8 | $5.00 | $25.00 |
| **Claude Sonnet 4.6** | **$3.00** | **$15.00** |

Sonnet은 Opus 대비 40%, Fable 대비 70% 저렴하다. 문제는 구조 없이 쓰면 그 차이가 품질 격차로 그대로 드러난다는 것이다. VFF는 그 격차를 운영 구조로 메운다.

작업 종류별 실제 절감폭(입력형 코딩 vs 출력형 글쓰기) 계산과 라우팅 기준은 [COST.md](COST.md) 참고.

### 실측 결과 (2026-06-14 재검증)

> 원판은 **Fable 5 ultracode 환경, 2026.06.11**에서 생성됐고(단판이라 재현 실패), 재검증은 **Opus 4.8 ultracode 멀티에이전트 하네스**로 수십 개 블라인드 심판·선수 에이전트를 병렬 실행했다. 원자료까지 [bench/](bench/)에 공개.

원래 2026-06-11 단판 벤치("5/6승·257점")는 원자료가 안 남아 재현 불가였고, 공정 베이스라인·중립 채점표로 다시 재니 재현되지 않았다. 재현 가능한 하네스와 원자료는 [bench/](bench/), 상세는 [bench/RESULTS.md](bench/RESULTS.md)에 있다.

핵심 수치(중립 채점표, 독립 심판 2명 평균, 0–100):

| 비교 | 결과 |
|---|---|
| v1 → v2 (압축 제거) | 76.2 → **87.1** (+10.9점) |
| Sonnet+v2 vs 맨 Opus | 두 재채점에서 87.1 vs 86.2, 84.8 vs 89.4 → **노이즈 안 동률(약 95–100%)** |
| 출력 비용 (v2 / Opus) | 약 **0.30배** (70% 저렴) → 품질당 비용효율 약 3배 |

v2는 기본 진단·분량글에선 Opus와 같거나 앞서고(분량 과제는 Opus가 글자 수 초과로 감점), 깊은 추론(아키텍처 결정·복잡 성능진단)에선 Opus가 5–7점 앞선다. **압축 규칙이 품질 부채였고 그걸 들어낸 v2가 진짜 개선이다.** v3(복합진단 분해 추가)는 중립 기준 효과가 없어 폐기했다.

⚠️ 한계: 과제당 1–2회·심판 2명·Claude 단일 가족·진단/조언 중심 표본. 두 재채점이 약 5점 흔들리는 노이즈가 있어 방향(v2≫v1, v2≈Opus)은 견고하나 소수점은 단정하지 않는다.

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
├── .claude-plugin/
│   ├── plugin.json             # 플러그인 매니페스트 (name·메타데이터)
│   └── marketplace.json        # 마켓플레이스 카탈로그 (단일 플러그인, source "./")
├── skills/itsvff/SKILL.md      # 세션 모드 — 트리거로 수동 발동
├── agents/itsvff.md            # 위임 전용 에이전트 (2-pass 리뷰 백엔드)
├── output-styles/vff.md        # 상시 모드 v1 (원본 보존)
├── output-styles/vff-v2.md     # 상시 모드 v2 (권장 — 압축 제거판, bench 재검증)
├── bench/                      # 재현 가능한 벤치 하네스 + 원자료 + RESULTS.md
├── hooks/hooks.json            # 훅 등록 설정 (reminder.sh를 UserPromptSubmit에 연결)
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

> **권장 버전 = v2** (`output-styles/vff-v2.md`). 재검증(bench/)에서 v1의 압축 강제가 품질 부채로 확인돼, 그걸 들어내고 진단·검증 구조만 남긴 v2가 v1보다 중립 채점표 +10.9점 높다. 신규 사용은 v2 권장, v1(`vff.md`)은 원본 보존용. (한때 시도한 v3=복합진단 분해 추가는 중립 기준 효과가 없어 폐기.)

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

> **v2(권장)는 위 v1 기준에서 변경됨**: `token_economy`의 압축 압박을 들어내고 `communication`·`writing_and_research`의 "짧게/분량 상한" 강제를 완화했다(분량은 상한이 아니라 정확히 맞춤). 재검증에서 압축 강제가 품질 부채로 확인됐기 때문이며, 자산인 `verification`(단서 우선·측정 먼저)은 그대로 유지한다. 상세 [bench/RESULTS.md](bench/RESULTS.md).

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

### 방법 1 — 플러그인 설치 (권장)

Claude Code 플러그인으로 한 번에 설치한다. 스킬·에이전트·output style(VFF)·훅이 모두 자동 등록된다.

```
/plugin marketplace add itsinseong/value-for-fable
/plugin install value-for-fable@itsinseong
```

이 repo는 마켓플레이스(`.claude-plugin/marketplace.json`)와 플러그인(`.claude-plugin/plugin.json`)을 겸한다. private repo이므로 설치하는 머신에 GitHub 인증(`gh auth login` 또는 git credential helper)이 돼 있어야 한다.

- 갱신: `/plugin marketplace update itsinseong` 후 재설치
- 제거: `/plugin uninstall value-for-fable@itsinseong`

### 방법 2 — 수동 복사

플러그인을 쓰지 않고 파일만 직접 둘 경우:

```bash
mkdir -p ~/.claude/skills/itsvff
cp skills/itsvff/SKILL.md ~/.claude/skills/itsvff/SKILL.md
cp agents/itsvff.md ~/.claude/agents/itsvff.md
cp output-styles/vff.md ~/.claude/output-styles/vff.md
cp hooks/reminder.sh ~/.claude/hooks/reminder.sh
chmod +x ~/.claude/hooks/reminder.sh
```

훅 등록 — `~/.claude/settings.json`의 `UserPromptSubmit` 배열에 아래 블록 추가:

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

### 사용

설치 후 새 세션에서 `/model sonnet` → `VFF` 입력으로 즉시 사용 가능하다.  
Output Style 상시 모드는 `/config` → Output style → VFF 선택.

### Mac mini / MacBook 동기화

양쪽 Mac에서 같은 VFF 기본값과 같은 작업공간을 유지하려면 repo 루트에서 아래 스크립트를 쓴다. 기본 대상은 `macbookpro:/Users/son-won-il/Documents/Codex/value-for-fable`이다.

```bash
./scripts/sync-vff-workspace.sh status
./scripts/sync-vff-workspace.sh push
./scripts/sync-vff-workspace.sh pull
./scripts/sync-vff-workspace.sh verify
```

`push`는 현재 Mac의 파일을 MacBook으로, `pull`은 MacBook의 파일을 현재 Mac으로 맞춘다. `.git`, `.omx`, `node_modules`, sync backup 디렉터리는 rsync 대상에서 제외한다. 삭제 동기화가 필요한 파일은 `.vff-sync-backups/` 아래에 백업된다. `verify`는 push 후 양쪽 플러그인 설치와 Sonnet smoke까지 실행한다.

---

## 한계

VFF는 행동 패턴만 바꾼다. Sonnet이 모르는 도메인 지식을 채워주지 않는다. 순수 추론 천장이 필요한 과제는 Opus 라우팅이 여전히 정답이다.

---

## 출처

- **Fable 5 운영 구조 원본**: [elder-plinius/CL4R1T4S — CLAUDE-FABLE-5.md](https://github.com/elder-plinius/CL4R1T4S/blob/main/ANTHROPIC/CLAUDE-FABLE-5.md). VFF의 8섹션(커뮤니케이션·추론·도구 규율·검증·코드·글쓰기·톤·토큰 절약) 구조는 이 파일에 공개된 Fable 5 시스템 프롬프트에서 운영 원칙을 관찰해 독립적으로 재구성한 것이다.
- 실측 데이터: 초기 2026-06-11 단판 표본은 재현에 실패했다. 현재 근거는 2026-06-14 재검증([bench/RESULTS.md](bench/RESULTS.md)) — 중립 채점표·독립 심판 2명·재현 가능한 하네스(원자료 포함). 심판은 Claude 계열, 과제는 진단·조언·결정 중심(한계 명시).
- 스킬·에이전트·훅 코드: 전체 자작.
