---
name: prism-all
description: Dual-engine multi-angle review. Runs all 5 angles (Conflict / Improvement / Devil / CodeReview / Robustness) on BOTH Claude subagents and Codex CLI in parallel — 10 total discovery calls — then Verifier cross-checks singletons. Cross-model agreement = highest confidence. Use for consequential code where you want the strongest possible review. Triggers on "/prism-all <target>", "prism all로", "크로스모델 prism".
argument-hint: "<target> [--quick] [--adversarial] [--verifier=claude|codex|both]"
user-invocable: true
---

# prism-all — Dual-Engine Multi-Angle Review

> 메인은 Claude (오케스트레이터). 매 리뷰 **Claude Agent 5 + Codex CLI 5 = 10 discovery**를 병렬 발사, 같은 각도에서 두 엔진이 모두 잡은 finding을 최고 신뢰 티어로 승급.
> 코드/target은 절대 수정하지 않는다 — 리포트만 산출.

## 핵심 가치

`/prism`은 Claude 5명 내부 ensemble. `/prism-codex`는 Codex 5명 ensemble. **`/prism-all`은 10명 cross-model ensemble**:

- **같은 각도 + 두 엔진 = cross-model agreement** — false positive 가능성 최소
- **같은 엔진 + 다른 각도 2+ = intra-model agreement** — 기존 prism 수준 신뢰
- **한 엔진 한 각도 singleton** — Verifier 검증으로 필터

3 파일 × 2 엔진 벤치마크 기준: 각 엔진이 놓친 unique finding 10+건씩 → 두 엔진 합치면 커버리지 크게 증가.

## 5 각도 × 2 엔진 (10 discovery)

| Agent | Claude | Codex (gpt-5.5) |
|---|---|---|
| Conflict Detection | ✓ | ✓ |
| Improvement | ✓ | ✓ |
| Devil's Advocate | ✓ | ✓ |
| Code Review | ✓ | ✓ |
| Robustness (4-Axis) | ✓ | ✓ |

+ **Verifier** 1콜 (기본 Claude, `--verifier=codex|both`로 override).

## 전제 (Prerequisite)

**둘 다 필수**:

1. **Claude Code** (메인 + 5 Agent) — ambient
2. **Codex CLI ≥ 0.125.0** (gpt-5.5 payload 지원)
   - `codex --version` 확인, 부적합 시 `npm install -g @openai/codex@latest`

**Codex 없음**: `/prism` 전환 제시. 반만 돌지 않음 (skill 이름에 반함).

**Codex 모델**: `~/.codex/config.toml` 기본 (`gpt-5.5` 권장). 실패 시 `~/.codex/models_cache.json` `visibility: list` 첫 slug로 폴백, state에 기록.

## 트리거

| 형태 | 모드 |
|---|---|
| `/prism-all <target>` | 기본 — 10 discovery + Verifier |
| `/prism-all <target> --quick` | Verifier 생략 |
| `/prism-all <target> --adversarial` | Verifier가 REJECT 전 반대 주장 |
| `/prism-all <target> --verifier=claude` | Verifier = Claude (기본) |
| `/prism-all <target> --verifier=codex` | Verifier = Codex |
| `/prism-all <target> --verifier=both` | 양쪽 Verifier 각각 singleton 판정, 둘 다 CONFIRMED면 확정 |
| 자연어 | "prism all로", "크로스모델 prism" |

---

## Pass 1 — 10 병렬 발사

**한 메시지 안에서 전부 병렬**:
- Claude 5개: `Agent` tool × 5 (Conflict/Improvement/Devil/CodeReview/Robustness), forked context
- Codex 5개: `Bash` tool × 1 (내부 5개 순차 Codex CLI). 전체 Bash는 Claude Agent와 **병렬**

Wall time ≈ max(Claude 5 parallel ≈ 20~40s, Codex 5 sequential ≈ 100~200s) = **Codex 쪽 병목** (~100~200s).

Agent 프롬프트는 **이 SKILL.md가 자체 보유** (독립성):

**1. Conflict Detection** — 충돌/모순/통합 위험. severity CRIT/HIGH/MED/LOW.
**2. Improvement** — 현재 → 개선안 → 근거. 효율/UX/누락/통합.
**3. Devil's Advocate** — 약점/실패모드, self-bias, Goodhart, 회귀 위험. severity + 완화.
**4. Code Review** — 명확성/완전성/정확성/일관성. `[SECTION] Issue → Fix`.
**5. Robustness (4-Axis)** — Concurrency / Failure&Recovery / Data Integrity / State Transitions. `[Axis N] Scenario → Current → Risk → Fix` + Coverage Summary.

(상세 프롬프트 텍스트는 prism-codex SKILL.md와 동일하며, 이 파일 내부에도 복사됨 — 두 skill 독립 유지.)

---

## Synthesis Triage with Cross-Model Promotion

10 응답 수집 후 3-tier 분류:

### Tier 1 — Cross-model agreement (최고 신뢰)
같은 각도에서 Claude + Codex 둘 다 flag. 레이블: `[cross-model/<angle>]`. severity = union (conservative, 높은 쪽).

### Tier 2 — Intra-model multi-angle (중간 신뢰)
한 엔진의 2+ 각도가 동일 finding. 레이블: `[claude/multi]` 또는 `[codex/multi]`. 기존 prism의 "2+ agents" 수준.

### Tier 3 — Singleton (Verifier 검증 대상)
한 엔진의 한 각도만 flag. 레이블: `[claude/<angle>]` 또는 `[codex/<angle>]`. Pass 2로 감.

### Conflicts
두 엔진이 반대 방향 조언 → "Conflicting" 섹션에 양쪽 표시, Verifier에게 판정 맡기거나 main이 한 줄 근거로 선택.

### Short-circuit
- `--quick` → Pass 2 스킵
- Tier 3 = 0 → Pass 2 스킵
- Tier 3 ≤ 3 → Verifier에 Tier 1/2도 함께 전달 (저렴)

---

## Pass 2 — Verifier (singleton 배치 검증)

**1 콜로 모든 singleton 판정** (선택된 엔진):

> 너는 Verifier. 10 리뷰어 (Claude 5 + Codex 5)가 같은 target을 분석했다. 각 singleton (1명만 지적) 마다 `CONFIRMED` / `REJECTED` / `DEPENDS` 판정.
>
> 규칙:
> - target 전체 + 10 Pass 1 응답 전부 + singleton list 읽고 판정
> - CONFIRMED/REJECTED/DEPENDS (새 finding 발명 금지)
> - severity 조정 가능 (CONFIRMED 시)
>
> `--verifier=both`: Claude Verifier 1콜 + Codex Verifier 1콜. 두 Verifier 모두 CONFIRMED = 확정. 엇갈림 = DEPENDS 처리.
>
> `--adversarial`: REJECT 하기 전 반박 시도 — 더 구체적이고 더 잘 근거 있어야 REJECT.

---

## Final Report

```
PRISM-ALL REPORT — {target} — {timestamp}
Mode: {verify | quick | adversarial}
Engines: Claude 5 + Codex 5 (gpt-5.5)
Verifier: {claude | codex | both}

## CRITICAL (must fix)
- [cross-model/conflict] Finding → Fix         # Tier 1
- [claude/multi] Finding → Fix                 # Tier 2
- [codex/devil → verified] Finding → Fix (Verifier: reason)   # Tier 3 passed

## HIGH / MEDIUM / LOW ...

## Rejected Singletons (Verifier dismissed)
## Depends-on-Context (Verifier DEPENDS)
## Cross-Model Agreements (Tier 1 summary)
## Intra-Model Multi-Angle (Tier 2 summary)
## Engine-Unique Findings (for reference)
  ### Claude-only (what Codex missed)
  ### Codex-only (what Claude missed)
## Conflicting Advice (if any)
## Recommended Action Order
```

---

## Codex 호출 규약 (엄수, 자체 보유)

### 불변
1. argv 금지 — tempfile + stdin만
2. Heredoc quoted (`<<'EOF'`)
3. Dynamic content는 `cat ... >> prompt.txt`로 append
4. 180K char guard per call
5. Timeout 180s

### 호출 템플릿

```bash
DIR="docs/prism-all/<slug>"
AGENT="<conflict|improvement|devil|code-review|robustness>"
PROMPT="$DIR/pass1.codex.$AGENT.prompt.txt"
OUT="$DIR/pass1.codex.$AGENT.codex.txt"

cat > "$PROMPT" <<'EOF'
(agent prompt)
EOF
cat "$TARGET" >> "$PROMPT"

BYTES=$(wc -c < "$PROMPT")
if [ "$BYTES" -gt 180000 ]; then exit 2; fi

timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox < "$PROMPT" > "$OUT" 2>&1 || {
  echo "[fallback: codex-unavailable]" > "$OUT"
}
```

### 출력 파서 (gpt-5.5 / CLI 0.125.0)

- `^codex$` 마커 이후 본문 시작, `^tokens used$` 직전 종료
- fenced yaml 찾지 마라 (5.5는 사용 안 함)
- stderr `ERROR codex_core::session: failed to record rollout items` 무시

### Fallback 정책

| 상황 | 동작 |
|---|---|
| 특정 각도 Claude 실패 | `[fallback: claude-unavailable]` 태그, Codex 응답만으로 판정. state.json에 기록 |
| 특정 각도 Codex 실패 | 폴백 모델 1회 재시도 → 실패 시 `[fallback: codex-unavailable]`, Claude 응답만 |
| 같은 각도 양쪽 모두 실패 | Tier 1 불가 (cross-model 불가능), 해당 각도 invalid |
| 3+ 각도에서 한 엔진 전체 실패 | 라운드 invalid, 사용자에게 `/prism` (Codex 고장) 또는 `/prism-codex` (Agent 고장) 전환 제시 |

---

## 비용 / 속도

| Mode | Claude 콜 | Codex 콜 | Verifier | wall time | 상대 비용 |
|---|---|---|---|---|---|
| `--quick` | 5 | 5 | 0 | ~100~200s | 2.0× prism |
| default (verify) | 5 | 5 | 1 (batched) | ~120~220s | 2.2~2.4× |
| `--adversarial` | 5 | 5 | 1 | ~120~220s | 2.2~2.4× |
| `--verifier=both` | 5 | 5 | 2 (both batched) | ~140~240s | 2.4~2.6× |

## 자립성 검증

```bash
node verify-independence.js --strict   # Codex CLI >= 0.125.0 포함
```

## 자매 skill과의 관계

| Skill | Engine | 언제 |
|---|---|---|
| `/prism` | Claude 5 + Claude Verifier | 빠른 1-엔진, Claude 토큰 여유 |
| `/prism-codex` | Codex 5 + Codex Verifier | 다른 모델 ensemble / Claude 토큰 절약 |
| `/prism-all` (이 skill) | Claude 5 + Codex 5 + Verifier | 최고 신뢰, 양쪽 토큰 OK |

셋 다 독립 plugin. 하나만 설치해도 동작.

## 안티패턴

- ❌ Claude 5 + Codex 5를 순차로 — 반드시 한 메시지 안 병렬 (parallel tool calls)
- ❌ Cross-model agreement 있는데 singleton 급으로 격하 — Tier 1 고정
- ❌ 한 엔진 실패 시 조용히 다른 쪽만으로 계속 — fallback 태그 + state 기록
- ❌ argv로 Codex 호출 — tempfile + stdin
- ❌ target 수정 — 항상 read-only report only
- ❌ 다른 plugin/skill 참조 — 전역 hook 차단
