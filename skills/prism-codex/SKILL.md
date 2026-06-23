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

### 공통 출력 포맷 v1 (A: 구조화 출력, 모든 5 agents)

각 agent는 자유 추론 뒤 **마지막에** 아래 펜스 블록 하나로 finding을 emit한다. synthesis는 이 레코드만 파싱한다 (prism-all과 동일 포맷 - 가족 일관).

```
<<<PRISM-FINDINGS v1>>>
CRIT | <locus> | <problem> -> <fix>
HIGH | <locus> | <problem> -> <fix>
<<<END>>>
```

- 한 줄 = 한 finding: `SEV | LOCUS | PROBLEM -> FIX`, SEV ∈ `CRIT|HIGH|MED|LOW`. 펜스 밖 텍스트는 무시. finding 없으면 빈 블록. 버전 태그 v1 고정.

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
6. **SANDBOX SAFETY PREAMBLE 모든 prompt에 prepend** (2026-05-22 leak incident 대응; 자세한 preamble 본문은 prism-all SKILL.md §Sandbox Safety Preamble 참조 — 두 skill 독립이지만 preamble 내용은 동일)
7. **SECRET SCRUB 모든 codex output에 적용** (동일 incident 대응)

### Sandbox Safety Preamble (불변 6)

`codex exec --dangerously-bypass-approvals-and-sandbox`는 Codex가 자유롭게 shell 명령을 실행할 수 있게 한다. 2026-05-22 receipt_processor compose 라운드에서 Codex 3개 agent가 `docker compose config`를 자발적으로 실행, env_file: directive를 resolve해서 operator의 6개 API key를 codex output에 inline 시켰다.

**모든** Codex prompt 시작부에 다음 preamble을 cat-prepend한다:

```
SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):

You MUST NOT run any of the following:
  * docker compose config (any flags)         -- resolves env_file: directives.
  * docker compose --env-file <path>          -- same risk.
  * cat / head / tail / less / more / awk     on files named .env, .env.*,
    dotenv, *credentials*, *secret*, *.pem, *.key, *.token, *.p12, *.pfx
  * printenv, env (with no args)              -- dumps inherited env.
  * docker run / docker exec / docker compose run with --env-file.
  * docker inspect <container> with output to file or pipe.
  * Any operation that exfiltrates *.env / dotenv contents to your output.

Use the target files (already appended to this prompt) plus textual
reasoning. Do NOT shell-execute a command that resolves the environment
to verify compose merge shape.
```

### 호출 템플릿

```bash
DIR="docs/prism-codex/<slug>"
N=1
AGENT="<conflict|improvement|devil|code-review|robustness>"
PROMPT="$DIR/pass1.$AGENT.prompt.txt"
OUT="$DIR/pass1.$AGENT.codex.txt"

# Unbreakable preamble FIRST.
cat > "$PROMPT" <<'EOF'
SANDBOX SAFETY POLICY (mandatory):
  ... (full preamble text from §Sandbox Safety Preamble above) ...

==== AGENT PROMPT BELOW ====
EOF

cat >> "$PROMPT" <<'EOF'
(agent prompt 본문)
EOF

cat "$TARGET" >> "$PROMPT"

BYTES=$(wc -c < "$PROMPT")
if [ "$BYTES" -gt 180000 ]; then exit 2; fi

timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --output-last-message "$OUT.msg" < "$PROMPT" > "$OUT.raw" 2>&1 || {
  echo "[fallback: codex-unavailable]" > "$OUT"
  rm -f "$OUT.raw" "$OUT.msg"
}

# Unbreakable post-run scrub (불변 7).
if [ -s "$OUT.raw" ]; then
    if grep -qE "$(cat <<'PATTERNS'
sk-ant-api03-[A-Za-z0-9_-]{20,}
sk-proj-[A-Za-z0-9_-]{30,}
AIzaSy[A-Za-z0-9_-]{30,}
glpat-[A-Za-z0-9_-]{20,}
ghp_[A-Za-z0-9]{20,}
gho_[A-Za-z0-9]{20,}
FLASK_SECRET_KEY[:\=][[:space:]]*[0-9a-fA-F]{32}
[A-Z_]*PASSWORD[:\=][[:space:]]*[^[:space:]\"]{8,}
[A-Z_]*TOKEN[:\=][[:space:]]*[A-Za-z0-9_/+-]{32,}
[A-Z_]*SECRET[:\=][[:space:]]*[A-Za-z0-9_/+-]{16,}
xoxb-[A-Za-z0-9-]{20,}
xoxp-[A-Za-z0-9-]{20,}
-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED |)?PRIVATE KEY-----
PATTERNS
)" "$OUT.raw"; then
        echo "[fallback: codex-output-contained-secret-pattern]" > "$OUT"
        if command -v shred >/dev/null 2>&1; then
            shred -uz "$OUT.raw" "$OUT.msg" 2>/dev/null || rm -f "$OUT.raw" "$OUT.msg"
        else
            rm -f "$OUT.raw" "$OUT.msg"
        fi
        echo "::warning::prism-codex: $AGENT output contained secret-shaped content; sanitized + deleted" >&2
    else
        # Prefer the clean --output-last-message file; raw fallback if unsupported.
        if [ -s "$OUT.msg" ]; then mv "$OUT.msg" "$OUT"; rm -f "$OUT.raw"; else mv "$OUT.raw" "$OUT"; fi
    fi
fi
```

### 출력 파서 v1 (A: 구조화 파싱 + degrade)

1. `<<<PRISM-FINDINGS v1>>>` ~ `<<<END>>>` 펜스 안에서 `^(CRIT|HIGH|MED|LOW)\s*\|` 매칭 줄만 finding으로. 펜스 밖(`^codex$`, `^tokens used$`, stderr `ERROR codex_core::session: failed to record rollout items`)은 전부 무시. fenced yaml 찾지 마라.
1b. **Codex는 전체 응답을 2회 출력한다 -> 펜스가 2개면 첫 번째 블록만** 취해 중복 집계 방지. **권장:** codex 호출에 `--output-last-message FILE`를 주면 최종 메시지만 깨끗이 받아 중복 + hook/echo/skill-load 노이즈가 소스에서 사라진다 (raw는 scrub용 유지).
2. 빈 블록 = 그 각도 깨끗.
3. **degrade (silent-drop 금지):** 펜스 부재 시 레거시 느슨 스캔 1회 fallback; 그래도 0건이면 `MED | <angle> | ANGLE-DEGRADED: 출력 파싱 불가 -> raw 확인/재실행` 1건 강제 추가. 라운드 전체를 fail시키지 않는다.

### Tier 2: 결정론적 파서 (코드, 프로즈 파싱 대체)

**v1.1 정정 (parse-findings.js 헤더가 정본):** 파서는 이제 (1) **모든 펜스 블록을 스캔해 valid finding이 가장 많은 블록 선택** - 첫 블록만 취하던 규칙은 example 펜스 선출력 시 진짜 리뷰를 누락시켜 폐기, (2) **severity 별칭 정규화** (critical→CRIT, medium→MED...), (3) zero-width는 토큰 비교에만 strip. 위 산문의 '첫 블록만' 표현은 구버전 - 코드가 우선.

위 v1 추출을 LLM 눈대중 대신 **코드**로 한다. codex 출력이 `$OUT`로 확정된 뒤:

    node "<이 skill 디렉토리>/parse-findings.js" "$OUT" "$AGENT" > "$OUT.json"

→ `$OUT.json` = `{angle, degraded, skipped, findings:[{severity,locus,text}]}`. synthesis는 raw 프로즈가 아니라 이 **구조화 레코드**로 triage한다 - 코드=추출(결정론), LLM=의미 판단. 첫 펜스만 / degrade / malformed-skip 규칙이 파서에 박힘. 자가 검증: `node parse-findings.js --selftest`. (prism-all과 동일 파일 - 가족 일관)

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
