---
name: prism-codex
description: Codex-backed multi-angle review. Like prism but the 5 discovery agents + Verifier are all Codex CLI (gpt-5.5) instead of Claude subagents. Same 5 angles (Conflict / Improvement / Devil / CodeReview / Robustness) + singleton Verifier. Use when you want different-model opinions or Claude tokens are scarce. Triggers on "/prism-codex <target>", "prism codex로", "codex prism".
argument-hint: "<target> [--quick] [--adversarial]"
user-invocable: true
---

# prism-codex — Codex-backed Multi-Angle Review

> 메인은 Claude (오케스트레이터). 5 discovery agents + 1 Verifier는 **모두 Codex CLI** (gpt-5.5). 목적: Claude self-bias 회피 + Claude 토큰 절약.

## 핵심 가치

기존 `/prism`과 동일한 5-각도 분산 + Verifier 패턴. 차이는 판단 주체가 다른 모델 (OpenAI gpt-5.5 via Codex CLI). prism이 Claude 내부 ensemble이라면, prism-codex는 **다른 모델에 같은 구조의 ensemble을 실행**. 둘 다 원하면 `/prism-all`.

## 5 각도 (prism과 동일)

| Agent | 역할 |
|---|---|
| 1. **Conflict Detection** | 충돌·모순·통합 위험 |
| 2. **Improvement** | 구체적 개선 제안 |
| 3. **Devil's Advocate** | 약점·실패 모드·self-bias 저격 |
| 4. **Code Review** | 명확성/완전성/정확성/일관성 |
| 5. **Robustness (4-Axis)** | 동시성/실패복구/데이터무결성/상태전이 |

+ **Verifier**: singleton findings (1명만 지적한 것) 일괄 검증.

## 전제 (Prerequisite)

**Codex CLI ≥ 0.125.0** 필수 (gpt-5.5 payload 지원 최소 버전):

```bash
codex --version      # >= 0.125.0
```

부적합 시: 중단 + `npm install -g @openai/codex@latest` 안내. Claude로 자동 대체하지 않음 (이 skill의 존재 이유가 다른 모델 ensemble).

**모델**: `~/.codex/config.toml`의 `model` (권장 `gpt-5.5`). 실패 시 `~/.codex/models_cache.json`의 `"visibility": "list"` 첫 slug로 폴백, state에 기록.

## 트리거

| 형태 | 모드 |
|---|---|
| `/prism-codex <target>` | 기본 — 5 discovery + Verifier (singleton 검증) |
| `/prism-codex <target> --quick` | Verifier 생략 (속도 우선) |
| `/prism-codex <target> --adversarial` | Verifier가 REJECT 하기 전 반대 주장 (self-bias 방어) |
| 자연어 | "prism codex로", "codex prism", "prism-codex 돌려" |

## Target 해석
- 파일 경로 → 해당 파일 리뷰
- 주제/설명 → 관련 파일 찾아 리뷰
- 인자 없음 → 현재 프로젝트 전반

**Target 내용은 항상 먼저 전체를 읽고** 각 Codex 호출에 그대로 전달 (요약 금지).

---

## Pass 1 — 5 Codex 호출 (순차)

Claude Agent 병렬 스폰과 달리 Codex CLI는 한 번에 1콜이 안정적. **5개 순차 실행**. Wall time ≈ 5 × (15~40s) = **~100~200s**.

각 호출마다 프롬프트 파일 생성 → `codex exec --dangerously-bypass-approvals-and-sandbox < prompt.txt > out.txt`.

### Agent 프롬프트 (5개, 이 SKILL.md 자체 보유)

**1. Conflict Detection**

> 너는 **Conflict Detection Agent**. 충돌, 모순, 통합 위험을 찾는다.
> 분석: 기존 코드/skill과의 중복, 설정 모순, 툴 체인 충돌, 구성요소 간 disagree하는 엣지 케이스.
> 각 발견에 severity (CRITICAL/HIGH/MEDIUM/LOW) 부여.

**2. Improvement**

> 너는 **Improvement Agent**. 구체적 개선을 제안한다.
> 각 제안: 현재 상태 → 개선안 → 근거.
> 포커스: 수식/로직 개선, 효율성, UX, 누락된 기능, 통합 기회.

**3. Devil's Advocate**

> 너는 **Devil's Advocate Agent**. 약점, 실패 모드, 작동 안 할 이유를 찾는다.
> 냉혹하게. 커버: self-bias, Goodhart 위험, 실제 실패 모드, 비용/시간, false confidence, scope creep, 회귀 위험.
> 각 발견에 severity + 완화책.

**4. Code Review**

> 너는 **Code Review Agent**. 명확성/완전성/정확성/일관성을 본다.
> 체크: 모호한 지시, 누락 엣지 케이스, 기존 코드와 패턴 일관성, 각 단계 actionability.
> 형식: [SECTION] Issue → Fix.

**5. Robustness (4-Axis)**

> 너는 **Robustness Agent**. 4 실패 축 평가. 각 축마다 코드/설계 구체 시나리오. 해당 없으면 "N/A — <reason>".
>
> **Axis 1 — Concurrency**: 두 user/request/worker 동시 접근. Race, double-submit, lost update, duplicate inserts, lock contention, TOCTOU.
> **Axis 2 — Failure & Recovery**: 중간 중단 (crash, network, timeout, partial write). Idempotency, retry safety, rollback, orphaned state.
> **Axis 3 — Data Integrity**: FK cascade, unique/CHECK constraints, referential consistency, upsert vs replace vs merge, schema version mismatch.
> **Axis 4 — State Transitions**: 도달 가능 상태 + 전이. Forward/reversal/forbidden/terminal/re-entry.
>
> 형식: `[Axis N] Scenario → Current → Risk (CRIT/HIGH/MED/LOW) → Fix`
> End with Coverage Summary.

### 공통 출력 포맷 (모든 5 agents)

각 agent는 finding 목록을 구조화된 형태로. 파싱 가능한 포맷이면 됨 (prism 원본과 동일하게 느슨 허용).

---

## Synthesis Triage (메인)

5 응답 수집 후 각 finding 분류:

- **AGREEMENT**: 2+ agents가 (semantic overlap) 지적 → 자동 CONFIRM, Pass 2 스킵
- **SINGLETON**: 정확히 1 agent → Pass 2 Verifier 대상

Short-circuit:
- `--quick` → Pass 2 스킵
- singletons = 0 → Pass 2 스킵
- total ≤ 3 AND `--quick` 아님 → Pass 2 실행하되 Verifier에 전체 전달

---

## Pass 2 — Codex Verifier (singleton 배치 검증)

**1 Codex 콜로 모든 singleton 일괄**:

> 너는 **Verifier Agent**. 5 리뷰어가 같은 target을 분석했다. 각 singleton (1명만 지적)마다 판정: `CONFIRMED` / `REJECTED` / `DEPENDS`.
>
> 규칙:
> - target 전체 + 5 Pass 1 응답 전부 + singleton list 읽고 판정.
> - CONFIRMED: 유효. severity 조정 가능.
> - REJECTED: 틀림. 어느 context가 차이 만들었는지 명시.
> - DEPENDS: 조건부. 조건 명시 + 여기서 성립 여부.
> - 새 finding 발명 금지.
>
> 포맷:
> ```yaml
> - id: <singleton_id>
>   original: "<finding>"
>   original_severity: CRIT|HIGH|MED|LOW
>   verdict: CONFIRMED|REJECTED|DEPENDS
>   adjusted_severity: <CONFIRMED일 때만>
>   reasoning: "1-2문장"
> ```

### `--adversarial` 모드

> REJECT 하기 전 반대 주장 먼저 해라 — 리뷰어가 맞고 네가 놓친 context가 있을 수 있다. 너의 반박이 더 구체적이고 더 잘 근거 있어야만 REJECT.

---

## Final Report

```
PRISM-CODEX REPORT — {target} — {timestamp}
Mode: {verify | quick | adversarial}
Engine: Codex CLI (gpt-5.5)

## CRITICAL (must fix)
- [3/5 agreement] Finding → Fix
- [1/5 → verified] Finding → Fix (Verifier: reason)

## HIGH / MEDIUM / LOW (same format)
## Rejected Singletons (Pass 2 ran)
## Depends-on-Context (Verifier DEPENDS)
## Cross-Agent Agreements
## Cross-Agent Disagreements
## Recommended Action Order
```

레이블:
- `[N/5 agreement]` — N명이 semantic match
- `[1/5 → verified]` — Pass 2 통과 singleton
- `[1/5 → rejected]` — Verifier dismissed
- `[1/5 → depends]` — Verifier conditional
- `--quick`: 검증 레이블 없이 `[source agent]`만

---

## Codex 호출 규약 (엄수, 이 skill 자체 보유)

### 불변
1. **argv 금지** — tempfile + stdin만
2. **Heredoc quoted** (`<<'EOF'`)
3. **Dynamic content는 파일 append** — `cat ... >> prompt.txt`, unquoted expansion 금지
4. **180K chars guard** per call
5. **Timeout 180s**

### 호출 템플릿

```bash
DIR="docs/prism-codex/<slug>"
N=1
AGENT="<conflict|improvement|devil|code-review|robustness>"
PROMPT="$DIR/pass1.$AGENT.prompt.txt"
OUT="$DIR/pass1.$AGENT.codex.txt"

cat > "$PROMPT" <<'EOF'
(agent prompt 본문)
EOF

cat "$TARGET" >> "$PROMPT"

BYTES=$(wc -c < "$PROMPT")
if [ "$BYTES" -gt 180000 ]; then exit 2; fi

timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox < "$PROMPT" > "$OUT" 2>&1 || {
  echo "[fallback: codex-unavailable]" > "$OUT"
}
```

### 출력 파서 (gpt-5.5, CLI 0.125.0)

Codex stdout에서 응답 본문은 `^codex$` 마커 이후부터 `^tokens used$` 직전까지. fenced yaml 블록 찾지 마라 — 5.5는 fence 안 씀.

`ERROR codex_core::session: failed to record rollout items` 경고는 무시 (stderr, 응답 영향 없음).

### Fallback 정책

- Codex 호출 실패 → Phase 0 폴백 모델로 1회 재시도. 여전히 실패 → 해당 agent에 `[fallback: codex-unavailable]` 태그.
- 5 agents 중 3+ fallback → 라운드 invalid, 사용자에게 `/prism` 전환 제시.
- Verifier fallback → singleton 전부 `[unverified]` 레이블로 리포트, 재실행 제안.

---

## 비용 / 속도

| Mode | Pass 1 호출 | Pass 2 호출 | 상대 비용 | 언제 |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 1.0× | 빠른 sanity check |
| default (verify) | 5 | 1 (batched) | 1.2~1.4× | 표준 리뷰 |
| `--adversarial` | 5 | 1 (batched) | 1.2~1.4× | self-bias 의심 |

wall time: Codex 순차 5콜이므로 **~100~200s** (파일 크기 의존).

## 자립성 검증

```bash
node verify-independence.js --strict   # Codex CLI >= 0.125.0 포함 체크
```

## 자매 skill과의 관계

| Skill | Engine | 언제 |
|---|---|---|
| `/prism` | Claude 5 + Claude Verifier | Claude 토큰 여유, 빠른 1-엔진 리뷰 |
| `/prism-codex` (이 skill) | Codex 5 + Codex Verifier | 다른 모델 관점 필요 / Claude 토큰 절약 |
| `/prism-all` | Claude 5 + Codex 5 (병렬) + Verifier | 최고 신뢰, 양쪽 토큰 OK |

세 skill은 완전 독립 plugin. 하나만 설치해도 동작.

## 안티패턴

- ❌ Codex 호출을 병렬 시도 — CLI는 한 번에 1콜이 안정적, 순차로.
- ❌ agreement 2+건 있는데 Pass 2로 보내기 — 자동 CONFIRM.
- ❌ Verifier를 5번 스폰 (finding당 1번) — 1 콜 batched.
- ❌ argv로 프롬프트 — 항상 tempfile + stdin.
- ❌ 다른 plugin/skill 파일 참조 — 전역 hook이 차단.
