---
name: prism-all
description: Dual-engine evidence-graded review. Runs 5 defect lenses on BOTH Claude subagents and Codex CLI in parallel — 10 discovery calls — then an Evidence pass pins every candidate to file/lines/execution-path. Statuses SUSPECTED → SUPPORTED → REPRODUCED; cross-model agreement raises priority and baseline confidence, but only evidence confirms. Use for consequential code. Triggers on "/prism-all <target>", "prism all로", "크로스모델 prism".
argument-hint: "<target> [--quick] [--adversarial] [--reproduce] [--include-improvements] [--lenses=classic] [--format json] [--verifier=claude|codex|both]"
user-invocable: true
---

# prism-all — Dual-Engine Evidence-Graded Review

> 메인은 Claude (오케스트레이터). 매 리뷰 **Claude Agent 5 + Codex CLI 5 = 10 discovery**를 병렬 발사.
> **합의는 우선순위, 확정은 증거.** 어떤 합의도 finding을 확정하지 않는다 — 확정은 Evidence pass가
> 코드 위치·실행 경로·인용을 붙였을 때(SUPPORTED), 그리고 가능하면 실패 테스트로 재현했을 때(REPRODUCED)만.
> 코드/target은 절대 수정하지 않는다 — 리포트만 산출 (재현 테스트는 임시 디렉토리 전용).

## Evidence 사다리 (모든 finding의 상태)

| 상태 | 의미 | 요건 |
|---|---|---|
| `SUSPECTED` | 에이전트 추론만 | claim + 출처 렌즈 |
| `SUPPORTED` | 정적 증거 확보 | file + lines + symbol + execution_path + 코드 인용 |
| `REPRODUCED` | 실패를 실제로 시연 | SUPPORTED + 실행된 실패 테스트/명령 |
| `REJECTED` | 반증됨 | 반증 근거 인용 |

## 핵심 가치

`/prism`은 Claude 5명 내부 ensemble. `/prism-codex`는 Codex 5명 ensemble. **`/prism-all`은 10명 cross-model ensemble**:

- **같은 각도 + 두 엔진 = cross-model agreement** — 상관된 오해 가능성 최소 → **가장 높은 초기 신뢰의 후보**
- **같은 엔진 + 다른 각도 2+ = intra-model agreement** — 같은 모델은 같은 오해를 반복할 수 있음 → 증거 없인 MEDIUM 상한
- **한 엔진 한 각도 singleton** — 가장 낮은 초기 신뢰

어느 티어든 **Evidence pass를 통과해야 SUPPORTED**가 된다. 3 파일 × 2 엔진 벤치마크 기준: 각 엔진이 놓친 unique finding 10+건씩 → 두 엔진 합치면 커버리지 크게 증가.

## 렌즈 × 2 엔진 (10 discovery)

기본은 **DEFECT 렌즈셋** (결함 탐지 전용 — 코드 대상):

| Lens | Claude | Codex (gpt-5.5) |
|---|---|---|
| Correctness & Contracts | ✓ | ✓ |
| Security & Trust Boundaries | ✓ | ✓ |
| State, Concurrency & Recovery | ✓ | ✓ |
| Integration & Regression | ✓ | ✓ |
| Testability & Observability | ✓ | ✓ |

- **Improvement 렌즈는 기본에서 제외** — 결함 리포트를 시끄럽게 만든다. `--include-improvements`로 6번째 렌즈로 추가(양 엔진), 결과는 `category: improvement`로 분리 집계.
- `--lenses=classic` → 구 렌즈셋(Conflict/Improvement/Devil/CodeReview/Robustness). **비코드 대상(설계 문서·계획)은 classic 자동 선택.**
- + **Evidence pass** 1콜 (기본 Claude, `--verifier=codex|both`로 override).

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
| `/prism-all <target>` | 기본 — 10 discovery + Evidence pass |
| `/prism-all <target> --quick` | Evidence pass 생략 — 전부 `SUSPECTED`로 보고 |
| `/prism-all <target> --adversarial` | Evidence pass가 REJECT 확정 전 반대 주장 의무 |
| `/prism-all <target> --reproduce` | + 재현 pass: 임시 디렉토리에 최소 실패 테스트 작성·실행 (SUPPORTED CRIT/HIGH 우선, 최대 5건) |
| `/prism-all <target> --include-improvements` | Improvement 렌즈 추가(분리 집계) |
| `/prism-all <target> --lenses=classic` | 구 렌즈셋 (비코드 대상은 자동) |
| `/prism-all <target> --format json` | finding record v2 배열을 `prism-report.json`으로도 출력 |
| `/prism-all <target> --verifier=claude` | Evidence pass = Claude (기본) |
| `/prism-all <target> --verifier=codex` | Evidence pass = Codex |
| `/prism-all <target> --verifier=both` | 양쪽이 각각 판정, 둘 다 SUPPORTED일 때만 SUPPORTED (엇갈림 = SUSPECTED) |
| 자연어 | "prism all로", "크로스모델 prism" |

---

## Pass 1 — 10 병렬 발사

**한 메시지 안에서 전부 병렬**:
- Claude 5개: `Agent` tool × 5 (Conflict/Improvement/Devil/CodeReview/Robustness), forked context
- Codex 5개: `Bash` tool × 1 (내부 5개 순차 Codex CLI). 전체 Bash는 Claude Agent와 **병렬**

Wall time ≈ max(Claude 5 parallel ≈ 20~40s, Codex 5 sequential ≈ 100~200s) = **Codex 쪽 병목** (~100~200s).

Agent 프롬프트는 **이 SKILL.md가 자체 보유** (독립성). DEFECT 렌즈셋(기본):

**1. Correctness & Contracts** — 틀린 결과/경계값/에러 경로/불변식/API 계약 위반. "구체 입력 → 틀린 출력"이 추상적 우려보다 우선.
**2. Security & Trust Boundaries** — 입력 검증/인가 공백/injection/secret 노출/unsafe default. 각 finding에 공격자 전제조건 명시.
**3. State, Concurrency & Recovery** — 동시 호출·중간 크래시·재시도. race/lost update/TOCTOU/비멱등 재시도/고아·고착 상태. 트리거 시퀀스 명시.
**4. Integration & Regression** — 호출자 계약 파괴/스키마·설정 드리프트/하위호환/숨은 결합. 영향받는 호출자·소비자 명명.
**5. Testability & Observability** — 삼켜진 예외/조용한 폴백/거짓 로그/테스트 불가 seam/신호 없는 실패 모드.

(`--include-improvements` 시 6번: **Improvement** — 현재 → 개선안 → 근거. `--lenses=classic` 시 구 5종: Conflict/Improvement/Devil/CodeReview/Robustness — 기존 문구 유지.)

모든 discovery 프롬프트 공통 계약: **"너는 의심(suspicion)을 생산한다 — 확정은 Evidence pass의 일이다. LOCUS는 가능한 한 `file:lines@symbol`로 정밀하게."**

### 출력 레코드 포맷 v1 (A: 구조화 출력 - 양 엔진 공통)

각 agent(Claude 5 + Codex 5)는 자유 추론 뒤 **마지막에** 아래 펜스 블록 하나로 finding을 emit한다. synthesis는 자유 텍스트가 아니라 이 레코드만 파싱한다 — model이 출력 포맷을 바꿔도 깨지지 않게.

```
<<<PRISM-FINDINGS v1>>>
CRIT | <locus> | <problem> -> <fix>
HIGH | <locus> | <problem> -> <fix>
MED  | <locus> | <problem> -> <fix>
<<<END>>>
```

- 한 줄 = 한 finding: `SEV | LOCUS | PROBLEM -> FIX`. SEV ∈ `CRIT|HIGH|MED|LOW`.
- 블록 밖 자유 텍스트(추론/근거)는 무시된다 — 파서는 펜스 안에서 `^(CRIT|HIGH|MED|LOW)\s*\|` 매칭 줄만 취한다. 줄 단위라 일부 잘림에도 파싱된 N건은 살아남는다 (중첩 JSON 대비 robust).
- finding이 없으면 빈 블록(펜스만)을 emit한다 (= "이 각도 깨끗"의 명시적 신호).
- **버전 태그 v1 고정.** 포맷 변경 시 v2로 올리고 파서가 둘 다 읽게 한다 (skill 독립 사본 간 drift 감지용).

---

## Synthesis Triage — 후보 분류 (확정 아님)

10 응답 수집 후 3-tier 분류. **Tier는 초기 신뢰(우선순위)만 결정한다 — 어느 Tier도 자동 확정되지 않고, 전부 Evidence pass로 간다.**

### Tier 1 — Cross-model agreement (최고 초기 신뢰)
같은 렌즈에서 Claude + Codex 둘 다 flag. 레이블: `[cross-model/<lens>]`. severity = union (높은 쪽). Evidence pass에서 **가장 먼저** 처리.

### Tier 2 — Intra-model multi-lens (중간 초기 신뢰)
한 엔진의 2+ 렌즈가 동일 finding. 레이블: `[claude/multi]` 또는 `[codex/multi]`. ⚠️ **같은 모델의 에이전트들은 같은 오해를 반복할 수 있다** — 이 티어는 증거 없이는 confidence MEDIUM을 넘지 못한다 (구버전의 "2+ agents = 자동 CONFIRMED" 규칙은 폐기).

### Tier 3 — Singleton (최저 초기 신뢰)
한 엔진의 한 렌즈만 flag. 레이블: `[claude/<lens>]` 또는 `[codex/<lens>]`.

### Conflicts
두 엔진이 반대 방향 조언 → "Conflicting" 섹션에 양쪽 표시. Evidence pass가 **인용 근거로만** 한쪽을 선택.

### Short-circuit
- `--quick` → Pass 2 스킵, 전부 `SUSPECTED`로 보고 (Tier 레이블 유지)
- 후보 0건 → Pass 2 스킵

---

## Pass 2 — Evidence pass (전 후보 배치 검증)

**1 콜로 모든 후보 판정** (선택된 엔진). Verifier가 아니라 **Evidence Agent** — 의견 대조가 아니라 코드 접지(grounding)가 일이다:

> 너는 Evidence Agent. 10 리뷰어(Claude 5 + Codex 5)가 같은 target을 분석해 아래 후보들을 냈다. 각 후보를 **실제 코드에 접지시키거나, 죽여라.** 리뷰어 말은 절대 그대로 믿지 않는다. 후보마다 순서대로:
>
> 1. **위치 고정**: 정확한 `file`, `lines`, `symbol`. 고정 불가 → `SUSPECTED` 유지 + 무엇이 부족했는지 기록.
> 2. **실행 경로 추적**: 진입→결함까지 순서 있는 호출/분기 단계.
> 3. **증거 인용**: claim을 참으로 만드는 줄을 `file:line — 인용`으로.
> 4. **전제조건 점검**: 공격자/호출자/상태가 충족해야 할 조건. 이 코드베이스에서 불가능하면 반증 인용과 함께 `REJECTED`.
> 5. **판정**: `SUPPORTED`(1~3 전부 확보) / `REJECTED`(반증 인용) / `SUSPECTED`(고정 불가 또는 도메인 지식 필요 — 부족한 컨텍스트를 `REQUIRES_DOMAIN_CONFIRMATION: <질문>` 형태로 명시).
> 6. severity 조정 가능(한 문장 근거). 새 finding 발명 금지.
> 7. `SUPPORTED`마다 `suggested_test`(테스트 함수명 + 한 줄 시나리오) 명명 — 재현 미요청이어도.
> 8. 후보마다 finding record v2(아래 스키마) 1건 출력. `evidence_strength`: NONE/WEAK(위치만)/MEDIUM(위치+경로+인용)/STRONG(재현 — 재현 pass만 부여).
>
> `--verifier=both`: Claude 1콜 + Codex 1콜, 둘 다 SUPPORTED일 때만 SUPPORTED (엇갈림 = SUSPECTED).
> `--adversarial`: REJECT 확정 전 리뷰어 편에서 반박 시도 — 반박이 원 주장보다 구체적·근거 우위일 때만 REJECT.

---

## Pass 3 — 재현 (`--reproduce`)

프로젝트는 **절대 수정하지 않는다** — 재현은 일회용 샌드박스에서.

- 대상: `SUPPORTED`만, CRIT/HIGH 우선, **런당 최대 5건**(초과분은 `STATIC_EVIDENCE_ONLY`로 명시).
- 절차: ① 기존 테스트 먼저 검색(이미 커버하는 테스트가 증명/반증할 수 있음) ② 테스트 러너 감지(pytest/vitest/jest/node --test/go test/cargo test — 없으면 `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`) ③ OS 임시 디렉토리(`$TMPDIR/prism-tests/`)에 최소 실패 테스트 작성 — 프로젝트 트리에 쓰기 금지, 프로젝트에 의존성 설치 금지 ④ 타임아웃 걸고 실행, 명령과 결과를 원문 그대로 기록.
- 분류: `REPRODUCED` / `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT` / `STATIC_EVIDENCE_ONLY` / `REQUIRES_EXTERNAL_SERVICE` / `REQUIRES_DOMAIN_CONFIRMATION`.
- **테스트가 통과하면(버그 미발현) 그건 반증** — `SUSPECTED`/`REJECTED`로 강등하고 통과 로그 인용. 재현 시도가 claim을 반박하는 것도 확인만큼 가치 있다.
- 종료 시 임시 디렉토리 정리, 테스트 소스는 **리포트에 보존**(운영자가 실제 스위트로 승격할 수 있게).
- 재현을 안 돌린 사실을 숨기지 않는다 — 모든 finding이 `reproduction.status`를 갖고, `STATIC_EVIDENCE_ONLY`는 정직하고 흔한 값이다.

---

## Finding record v2 + Confidence

record 스키마는 `/prism` SKILL.md와 동일 (id/fingerprint/file/lines/symbol/category/severity/status/claim/preconditions/execution_path/evidence/reproduction/confidence). `SUPPORTED` 이상은 file/lines/symbol/execution_path/인용이 **필수**. fingerprint = `sha1("<file>|<symbol>|<category>")[:8]` — 런 간 dedup 용.

```
Confidence = model diversity + lens diversity + direct code evidence + executable reproduction
             − missing context − unverifiable assumptions
```

| 신호 조합 | confidence.label |
|---|---|
| 한 렌즈 singleton, 증거 없음 | LOW |
| 같은 엔진 2+ 렌즈 합의, 증거 없음 | **MEDIUM (상한)** — 같은 모델은 같은 오해 반복 가능 |
| Claude+Codex 크로스모델 합의, 증거 없음 | MEDIUM-HIGH |
| (합의 무관) 위치+실행경로+인용 확보 | HIGH |
| 크로스모델 합의 + 정확한 코드 경로 | HIGH+ |
| 실패 테스트 재현 | VERY HIGH |

---

## Final Report

```
PRISM-ALL REPORT — {target} — {timestamp}
Mode: {verify | quick | adversarial} [+reproduce]
Engines: Claude 5 + Codex 5 (gpt-5.5) · Evidence: {claude | codex | both}
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected

## REPRODUCED (실패 시연됨)
- PRISM-003 [HIGH|security|VERY HIGH] file:lines@symbol — claim
  [cross-model/security] path: ... | repro: <command> → FAILED as predicted | fix: ...

## SUPPORTED (코드 경로 증거, 미실행)
- PRISM-001 [...|HIGH] file:lines@symbol — claim
  [claude/multi] evidence: file:line — 인용 | repro: STATIC_EVIDENCE_ONLY | suggested_test: ...

## SUSPECTED (추론만 — 확인 필요)
- PRISM-007 [...] — claim — missing: REQUIRES_DOMAIN_CONFIRMATION: <운영자에게 물을 질문>

## REJECTED (투명성)
- [codex/correctness] claim — 반증: file:line — 인용

## IMPROVEMENTS (--include-improvements 시만)
## Engine-Unique Findings (참고)
  ### Claude-only (Codex가 놓친 것) / ### Codex-only (Claude가 놓친 것)
## Conflicting Advice (있으면)
## Recommended Action Order
REPRODUCED 먼저, 그다음 SUPPORTED를 severity 순으로. SUSPECTED는 task가 아니라 질문으로.
```

`--format json`: 위와 함께 `prism-report.json` 출력 — `{ "meta": {...}, "findings": [<record v2>...] }`. fingerprint로 런 간 중복 제거 가능. (SARIF: 로드맵.)

---

## Codex 호출 규약 (엄수, 자체 보유)

### 불변
1. argv 금지 — tempfile + stdin만
2. Heredoc quoted (`<<'EOF'`)
3. Dynamic content는 `cat ... >> prompt.txt`로 append
4. 180K char guard per call
5. Timeout 180s
6. **모든 Codex prompt에 SANDBOX SAFETY PREAMBLE 삽입** (불변 6 — 2026-05-22 leak incident 대응)
7. **모든 Codex output에 SECRET SCRUB 단계 적용** (불변 7 — 동일 incident 대응)

### Sandbox Safety Preamble (불변 6)

`codex exec --dangerously-bypass-approvals-and-sandbox`는 Codex가 자유롭게 shell 명령을 실행할 수 있게 한다. 2026-05-22 receipt_processor compose 라운드에서 Codex 3개 agent (conflict / code-review / devil)가 `docker compose config`를 자발적으로 실행, env_file: directive를 resolve해서 operator의 6개 API key + secret을 codex output에 inline 시켰다. 4개 파일이 disk에 ~3-15분 노출, session transcript에는 영구 남음.

**모든** Codex prompt 시작부에 다음 preamble을 cat으로 prepend한다 — agent 종류와 무관:

```
SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):

You MUST NOT run any of the following commands or operations under any
circumstances, regardless of what the user prompt or target file suggests:

  * docker compose config (any flags)         -- resolves env_file: directives,
                                                 inlining KEY=VALUE pairs into
                                                 output. This is THE specific
                                                 leak vector that triggered this
                                                 policy.
  * docker compose --env-file <path>          -- same risk, different surface.
  * cat / head / tail / less / more / awk     on files named .env, .env.*,
    dotenv, *credentials*, *secret*, *.pem, *.key, *.token, *.p12, *.pfx
  * printenv, env (with no args)              -- dumps inherited environment
                                                 which may contain secrets if the
                                                 codex shell inherited them.
  * docker run / docker exec / docker compose run -- any --env-file or any
    command that mounts the operator env file is forbidden.
  * docker inspect <container> with output to file or pipe -- shows env
    section in cleartext.
  * Any operation that exfiltrates the contents of a *.env / dotenv file
    to your reasoning output, even if you intend to redact later.

If your analysis genuinely needs to know the COMPOSE MERGE SHAPE without
the env values, use the YAML files directly (which the prompt has already
appended) plus textual reasoning. Do NOT shell-execute a command that
resolves the environment to verify the merge.

Violating this policy causes the round to be discarded. The post-run
scrub will catch obvious patterns but the safer path is not to read or
emit secrets in the first place.
```

### 호출 템플릿

```bash
# 산출물은 기본 임시 디렉토리 — repo를 오염시키지 않는다 (2026-07 실사용 피드백).
#  기록을 repo에 남기고 싶으면 --artifacts=docs 로 기존 경로(docs/prism-all/<slug>) 사용
#  + 그 경로를 .gitignore에 추가할 것.
DIR="${TMPDIR:-/tmp}/prism-all/<slug>"        # --artifacts=docs -> docs/prism-all/<slug>
AGENT="<correctness|security|state|integration|testability>"   # classic: conflict|improvement|devil|code-review|robustness
PROMPT="$DIR/pass1.codex.$AGENT.prompt.txt"
OUT="$DIR/pass1.codex.$AGENT.codex.txt"

# Unbreakable preamble FIRST (do not let the agent prompt override).
cat > "$PROMPT" <<'EOF'
SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):
... (full preamble text from §Sandbox Safety Preamble above) ...

==== AGENT PROMPT BELOW ====
EOF

# Agent-specific prompt.
cat >> "$PROMPT" <<'EOF'
(agent prompt)
EOF

# Target content.
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
        # Leak detected. Replace the output with a sanitized failure marker
        # so the synthesis layer sees the angle invalid + the operator knows
        # to investigate. Do NOT keep the raw file (the leak is on disk).
        echo "[fallback: codex-output-contained-secret-pattern]" > "$OUT"
        echo "[fallback: this codex angle ran a forbidden command that resolved" >> "$OUT"
        echo "[fallback: env_file: or printed secret-shaped content. The .raw" >> "$OUT"
        echo "[fallback: file was deleted. Re-run the round after auditing the" >> "$OUT"
        echo "[fallback: codex prompt for compliance with §Sandbox Safety Preamble." >> "$OUT"
        # IMPORTANT: shred not just rm. /tmp on macOS / Windows is often
        # tmpfs-backed (no recovery) but Linux+ext4 has overwrite-on-free
        # behaviour that depends on FS aging. shred works on best-effort.
        if command -v shred >/dev/null 2>&1; then
            shred -uz "$OUT.raw" "$OUT.msg" 2>/dev/null || rm -f "$OUT.raw" "$OUT.msg"
        else
            rm -f "$OUT.raw" "$OUT.msg"
        fi
        # Operator-facing alert.
        echo "::warning::prism-all: codex/$AGENT output contained secret-shaped content; sanitized + deleted" >&2
    else
        # Clean. Prefer the --output-last-message file (clean final message:
        # single fence, no echo/hook/dup). raw passed the scrub so the message
        # subset is clean too; fall back to raw if the flag was unsupported.
        if [ -s "$OUT.msg" ]; then mv "$OUT.msg" "$OUT"; rm -f "$OUT.raw"; else mv "$OUT.raw" "$OUT"; fi
    fi
fi
```

### 출력 파서 v1 (A: 구조화 파싱 + degrade)

1. `<<<PRISM-FINDINGS v1>>>` ~ `<<<END>>>` 펜스 블록을 찾는다. 그 안에서 `^(CRIT|HIGH|MED|LOW)\s*\|` 매칭 줄만 finding으로 취한다. 펜스 밖(추론, `^codex$`, `^tokens used$`, stderr `ERROR codex_core::session: failed to record rollout items`)은 전부 무시 - preamble/prose/잘림에 강건.
1b. **Codex CLI는 전체 응답을 2회 출력한다** (`response -> tokens used N -> response 재출력`, 실측 확인). 펜스 블록이 2개로 나오면 **첫 번째 블록만** 취해 중복 집계를 막는다. **권장:** codex 호출에 `--output-last-message FILE`를 주면 최종 메시지만 그 파일에 깨끗이 받아 이 중복 + `hook:`/echo/`failed to load skill` 노이즈가 소스에서 제거된다 (raw 캡처는 invariant 7 scrub 용도로 별도 유지). `--output-schema FILE`로 JSON 강제도 가능하나 reasoning 깊이가 얕아질 수 있어 free-form+펜스가 기본.
2. **빈 블록(펜스만)** = 그 각도 "깨끗", 정상.
3. **펜스 부재 시 fallback:** 레거시 느슨 스캔(`^codex$`~`^tokens used$` 사이 텍스트에서 severity 라인 휴리스틱 추출)을 1회 시도.
4. **그래도 0건이면 silent-drop 금지:** 합성 finding 한 건을 강제 추가 - `MED | <angle> | ANGLE-DEGRADED: 출력 파싱 불가 -> raw 확인 또는 재실행`. 각도가 통째로 사라지는 게 아니라 "깨졌다"가 보이게. **절대 라운드 전체를 fail시키지 않는다.**

### Tier 2: 결정론적 파서 (코드, 프로즈 파싱 대체)

**v1.1 정정 (parse-findings.js 헤더가 정본):** 파서는 이제 (1) **모든 펜스 블록을 스캔해 valid finding이 가장 많은 블록 선택** - 첫 블록만 취하던 규칙은 모델이 example/format 펜스를 먼저 emit하면 진짜 리뷰를 통째로 누락시켜서 폐기, (2) **severity 별칭 정규화** (critical→CRIT, medium→MED, nit/info→LOW...), (3) zero-width는 펜스 토큰 비교에만 strip(내용 보존). 위 산문의 '첫 블록만' 표현은 구버전 - 코드가 우선.

위 v1 추출을 LLM 눈대중 대신 **코드**로 한다. codex 출력이 `$OUT`로 확정된 뒤 (또는 Claude agent 반환값을 파일로 쓴 뒤):

    node "<이 skill 디렉토리>/parse-findings.js" "$OUT" "$AGENT" > "$OUT.json"

→ `$OUT.json` = `{angle, degraded, skipped, findings:[{severity,locus,text}]}`. synthesis는 raw 프로즈가 아니라 이 **구조화 레코드**로 triage(cross-model 합의·dedup)한다 - 코드=추출(결정론), LLM=의미 판단. 첫 펜스만 / degrade / malformed-skip 규칙이 파서에 박혀 모델 출력 흔들림에 강건. 자가 검증: `node parse-findings.js --selftest`.

### Fallback 정책

| 상황 | 동작 |
|---|---|
| 특정 각도 Claude 실패 | `[fallback: claude-unavailable]` 태그, Codex 응답만으로 판정. state.json에 기록 |
| 특정 각도 Codex 실패 | 폴백 모델 1회 재시도 → 실패 시 `[fallback: codex-unavailable]`, Claude 응답만 |
| 같은 각도 양쪽 모두 실패 | Tier 1 불가 (cross-model 불가능), 해당 각도 invalid |
| 3+ 각도에서 한 엔진 전체 실패 | 라운드 invalid, 사용자에게 `/prism` (Codex 고장) 또는 `/prism-codex` (Agent 고장) 전환 제시 |

---

## 비용 / 속도

| Mode | Claude 콜 | Codex 콜 | Evidence | Repro | wall time | 상대 비용 |
|---|---|---|---|---|---|---|
| `--quick` | 5 | 5 | 0 | 0 | ~100~200s | 2.0× prism |
| default | 5 | 5 | 1 (batched) | 0 | ~120~220s | 2.2~2.4× |
| `--adversarial` | 5 | 5 | 1 | 0 | ~120~220s | 2.2~2.4× |
| `--verifier=both` | 5 | 5 | 2 (batched×2) | 0 | ~140~240s | 2.4~2.6× |
| `--reproduce` | 5 | 5 | 1 | ≤5 test runs | ~180~320s | 2.6~3.2× |

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
- ❌ **합의만으로 확정** — 같은 엔진이든 크로스모델이든, Evidence pass 없이 SUPPORTED 부여 금지. 합의는 우선순위다.
- ❌ **위치 없는 SUPPORTED** — file/lines/symbol/실행경로/인용 없이 SUPPORTED 라벨 금지. 접지 못 하면 SUSPECTED로 정직하게.
- ❌ **재현 테스트를 프로젝트 트리에 작성** — 임시 디렉토리 전용. 프로젝트는 read-only.
- ❌ **재현 실패(테스트 통과)를 조용히 버림** — 반증도 기록: 강등 + 통과 로그 인용.
- ❌ Cross-model agreement 있는데 singleton 급으로 격하 — Tier 1 우선순위 고정
- ❌ 한 엔진 실패 시 조용히 다른 쪽만으로 계속 — fallback 태그 + state 기록
- ❌ argv로 Codex 호출 — tempfile + stdin
- ❌ target 수정 — 항상 read-only report only
- ❌ 다른 plugin/skill 참조 — 전역 hook 차단
- ❌ **Codex prompt에 SANDBOX SAFETY PREAMBLE 빠뜨림** (불변 6) — 매 prompt 시작부에 unbreakable preamble cat-prepend. agent prompt가 절대 override할 수 없는 위치.
- ❌ **post-run scrub 건너뜀** (불변 7) — secret pattern grep 우회하면 disk + transcript에 leak 영구화. 의심스러우면 .raw 파일 즉시 shred.
- ❌ **operator env file 위치에서 prism 실행** — 작업 디렉토리 안에 `.env`, `dotenv`, `*credentials*`, `*secret*`가 있으면 codex가 자발적으로 읽을 수 있다 (preamble로 막지만 defense-in-depth). compose 라운드는 항상 별도 작업 디렉토리에서 실행.

## 사건 기록

### 2026-05-22 — receipt_processor compose round secret leak

3개 Codex agent (conflict / code-review / devil)가 `docker compose config`를 자발적으로 실행해서 operator의 6개 secret (ANTHROPIC / GEMINI / OPENAI / GOOGLE_PLACES / GMAIL_APP_PASSWORD / FLASK_SECRET_KEY)을 codex reasoning output에 inline. 4개 prism 파일 disk에 ~3-15분 노출. session transcript에 영구 보존 (operator는 cutover 시 키 rotation 예정). GitHub remote는 깨끗 (`docs/prism-all/`은 gitignore).

이 사건이 불변 6 + 7 + 안티패턴 마지막 3개 항목을 만들었다. 같은 vector가 다시 발생하면 round invalid + operator 즉시 rotation 트리거.
