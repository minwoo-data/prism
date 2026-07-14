---
name: prism-codex
description: Codex-backed evidence-graded review. Like prism but the 5 discovery agents + Evidence pass are all Codex CLI (gpt-5.5). Statuses SUSPECTED → SUPPORTED → REPRODUCED; agreement prioritizes, evidence confirms. Use when you want different-model opinions or Claude tokens are scarce. Triggers on "/prism-codex <target>", "prism codex로", "codex prism".
argument-hint: "<target> [--quick] [--adversarial] [--reproduce] [--include-improvements] [--lenses=classic]"
user-invocable: true
---

# prism-codex — Codex-backed Multi-Angle Review

> 메인은 Claude (오케스트레이터). 5 discovery agents + Evidence pass는 **모두 Codex CLI** (gpt-5.5). 목적: Claude self-bias 회피 + Claude 토큰 절약. **합의는 우선순위, 확정은 코드 접지.**

## 핵심 가치

기존 `/prism`과 동일한 5-렌즈 분산 + Evidence pass 패턴. 차이는 판단 주체가 다른 모델 (OpenAI gpt-5.5 via Codex CLI). 둘 다 원하면 `/prism-all`.

⚠️ **단일 모델 ensemble의 한계**: 5 agents가 전부 같은 모델이므로 **합의(2+)는 확정이 아니라 우선순위 신호**다 — 같은 모델은 같은 오해를 반복할 수 있다. 합의만으로는 confidence MEDIUM 상한; SUPPORTED 이상은 Evidence pass의 코드 접지(위치+실행경로+인용)가 필요하다. Evidence 사다리(SUSPECTED/SUPPORTED/REPRODUCED/REJECTED)와 finding record v2는 `/prism` v0.2와 동일 계약.

## 렌즈 (기본 DEFECT — prism v0.2와 동일)

| Lens | 역할 |
|---|---|
| 1. **Correctness & Contracts** | 틀린 결과·경계값·에러 경로·불변식·API 계약 위반 |
| 2. **Security & Trust Boundaries** | 입력 검증·인가 공백·injection·secret·unsafe default (+공격자 전제조건) |
| 3. **State, Concurrency & Recovery** | race/lost update/TOCTOU·비멱등 재시도·고아/고착 상태 (+트리거 시퀀스) |
| 4. **Integration & Regression** | 호출자 계약 파괴·스키마/설정 드리프트·하위호환·숨은 결합 |
| 5. **Testability & Observability** | 삼켜진 예외·조용한 폴백·거짓 로그·신호 없는 실패 |

`--include-improvements` → Improvement 렌즈 추가(분리 집계). `--lenses=classic` → 아래 구 5종 프롬프트 사용(비코드 대상은 자동).

+ **Evidence pass**: 전 후보 일괄 접지 검증.

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
| `/prism-codex <target>` | 기본 — 5 discovery + Evidence pass (**전 후보** 접지) |
| `/prism-codex <target> --quick` | Evidence pass 생략 — 전부 `SUSPECTED` |
| `/prism-codex <target> --adversarial` | Evidence pass가 REJECT 확정 전 반대 주장 |
| `/prism-codex <target> --reproduce` | + 재현 pass (SUPPORTED CRIT/HIGH 우선, 최대 5건, `/prism` v0.2 규약) |
| `/prism-codex <target> --include-improvements` | Improvement 렌즈 추가(분리 집계) |
| `/prism-codex <target> --lenses=classic` | 구 렌즈셋 (비코드 대상은 자동) |
| `/prism-codex <target> --format json` | finding record v2를 `prism-report.json`으로도 출력 |
| `/prism-codex <target> --artifacts=[temp|docs]` | 산출물 위치(기본 temp; docs는 .gitignore 필수) |
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

### Agent 프롬프트 (이 SKILL.md 자체 보유)

**DEFECT 렌즈셋(기본)** — 각 프롬프트는 위 렌즈 표의 역할 정의 + 공통 계약("너는 의심을 생산한다 — 확정은 Evidence pass의 일. LOCUS는 가능한 한 `file:lines@symbol`")으로 구성한다. **CLASSIC 렌즈셋(`--lenses=classic`)** 은 아래 구 프롬프트 5개를 그대로 사용:

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

5 응답 수집 후 각 finding 분류 — **분류는 우선순위이지 확정이 아니다. 전 후보가 Pass 2로 간다**:

- **AGREEMENT**: 2+ agents가 (semantic overlap) 지적 → 우선 처리 후보. ⚠️ 자동 CONFIRM 금지 — 같은 모델 5명의 합의는 상관된 오해일 수 있다 (구버전 규칙 폐기).
- **SINGLETON**: 정확히 1 agent → 후순위 후보.

Short-circuit:
- `--quick` → Pass 2 스킵, 전부 `SUSPECTED`로 보고
- 후보 0건 → Pass 2 스킵

---

## Pass 2 — Codex Evidence pass (전 후보 배치 접지)

**후보 ≤8건마다 Codex 1콜로 청킹**(AGREEMENT 먼저, CRIT/HIGH 다음, 나머지 순). 각 콜에 candidate id를 실어 1:1 대응. 콜 실패/후보 누락 → 그 후보만 `SUSPECTED(missing: EVIDENCE_PASS_FAILED)`, 판정된 후보 재실행 금지, 라운드 fail 금지:

> 너는 **Evidence Agent**. 5 리뷰어가 같은 target을 분석해 아래 후보들을 냈다. 각 후보를 실제 코드에 접지시키거나, 죽여라. 인용은 반드시 파일을 읽어 실제 존재하는 텍스트로(사후 기계 검증됨). 후보마다:
>
> 1. 위치 고정: `file`, `lines`, `symbol`. 고정 불가 → `SUSPECTED` + `missing` 기록.
> 2. 실행 경로 추적: 진입→결함 순서 단계.
> 3. 증거 인용: `file:line — 인용`.
> 4. 전제조건 점검: 불가능하면 반증 인용과 함께 `REJECTED`.
> 5. 판정: `SUPPORTED` / `REJECTED` / `SUSPECTED`(+`REQUIRES_DOMAIN_CONFIRMATION: <질문>`). 위치만 잡히면 `evidence_strength: WEAK`.
> 6. severity 조정 가능(한 문장 근거). 새 finding 발명 금지.
> 7. `SUPPORTED`마다 `suggested_test` 명명.
>
> 포맷: 후보당 finding record v2 1건을 `<<<PRISM-RECORDS v2>>>` ~ `<<<END>>>` 펜스에 한 줄 JSON으로(id/candidate_id/fingerprint/file/lines/symbol/category/severity/status/claim/preconditions/execution_path/evidence/reproduction/confidence — `/prism` v0.2 동일 스키마). `evidence_strength`: NONE/WEAK/MEDIUM/STRONG.

**기계 검증(불변)**: 응답을 파싱 후 `node verify-evidence.js records.json <repo-root> > checked.json` — 인용 grep 불일치는 `SUSPECTED(EVIDENCE_QUOTE_MISMATCH)` 자동 강등, fingerprint 코드 계산. checked.json이 최종 진실.

`--reproduce`: `/prism` v0.2와 동일 규약 — SUPPORTED CRIT/HIGH 우선 최대 5건, **stripped env·프로젝트 트리 쓰기 금지·러너 설치 금지·실패 시그니처 사전 등록·per-test 60s**, 임시 디렉토리에만 작성·실행. 분류: REPRODUCED / NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT / TIMED_OUT / STATIC_EVIDENCE_ONLY / REQUIRES_EXTERNAL_SERVICE / REQUIRES_DOMAIN_CONFIRMATION. 자작 통과 테스트는 최대 SUSPECTED까지만 강등.

### `--adversarial` 모드

> REJECT 하기 전 반대 주장 먼저 해라 — 리뷰어가 맞고 네가 놓친 context가 있을 수 있다. 너의 반박이 더 구체적이고 더 잘 근거 있어야만 REJECT.

---

## Final Report

```
PRISM-CODEX REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce]
Engine: Codex CLI (gpt-5.5)
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected

## REPRODUCED (실패 시연됨)
## SUPPORTED (코드 경로 증거, 미실행)
- PRISM-001 [HIGH|security] file:lines@symbol — claim
  [3/5 agreement] evidence: file:line — 인용 | repro: STATIC_EVIDENCE_ONLY | suggested_test: ...
## SUSPECTED (추론만 — 확인 필요)
## REJECTED (투명성 — 반증 인용)
## IMPROVEMENTS (--include-improvements 시만)
## Recommended Action Order
```

레이블: `[N/5 agreement]` — N명 semantic match (우선순위 신호). ⚠️ 단일 모델이므로 합의만으로 confidence MEDIUM 상한 — 상태(SUPPORTED+)는 항상 Evidence pass 산출. `--quick`: 전부 SUSPECTED, `[source agent]` 레이블만.

---

## Codex 호출 규약 (엄수, 이 skill 자체 보유)

### 불변
1. **argv 금지** — tempfile + stdin만
2. **Heredoc quoted** (`<<'EOF'`)
3. **Dynamic content는 파일 append** — `cat ... >> prompt.txt`, unquoted expansion 금지
4. **180K chars guard** per call
5. **Timeout 180s**
6. **SANDBOX SAFETY PREAMBLE 모든 prompt에 prepend** (2026-05-22 leak incident 대응 — 아래 §Sandbox Safety Preamble에 **전문 자체 보유**, 다른 skill을 런타임 참조하지 않는다)
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
# 산출물 기본 위치는 임시 디렉토리 — repo 오염 방지. 기록 보존 원하면 --artifacts=docs.
DIR="${TMPDIR:-/tmp}/prism-codex/<slug>"      # --artifacts=docs -> docs/prism-codex/<slug>
N=1
AGENT="<correctness|security|state|integration|testability>"   # classic: conflict|improvement|devil|code-review|robustness
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

**파서가 정본** — parse-findings.js 헤더가 규칙 충돌 시 이긴다. discovery 출력을 코드로 추출:
```
node "<skill dir>/parse-findings.js" "$OUT" "$AGENT" > "$OUT.json"
```
파서 실동작: (1) **모든 펜스 블록 스캔 → valid finding 최다 블록 선택**(개수 동률 시 last-valid — "첫 블록만" 규칙 폐기, 산문 표현 삭제). real 블록이 비었고 example 블록이 채워지면 역선출되므로 discovery 계약은 진짜 블록을 **마지막 펜스**로 emit하도록 요구. (2) severity 별칭 정규화. (3) LOCUS `|` 금지(첫 두 `|`로만 분할). (4) zero-width는 토큰 비교에만 strip. `--output-last-message FILE`로 codex 2회출력·노이즈 소스 제거(raw는 scrub용).

→ `$OUT.json` = `{angle, degraded, skipped, findings:[...]}`. **degraded=true는 후보 아님 → `meta.degraded_angles`**(Evidence pass·candidate_count·fingerprint 제외). 자가 검증: `node parse-findings.js --selftest`.

**Evidence pass 기계 검증(불변)**: Evidence 응답의 v2 record를 JSON으로 파싱 후 반드시
```
node "<skill dir>/verify-evidence.js" records.json "<repo-root>" > checked.json
```
— SUPPORTED/REPRODUCED의 `file:line — 인용`을 실제 파일에서 grep해 없으면 `SUSPECTED(EVIDENCE_QUOTE_MISMATCH)` 자동 강등 + fingerprint 코드 계산. **checked.json이 최종 진실.** `node verify-evidence.js --selftest`. (parse-findings.js·verify-evidence.js는 prism-all이 정본, `sync-review-parsers.sh`로 동기화된 동일 사본.)

### Fallback 정책 (각도별 독립 회계)

| 상황 | 동작 |
|---|---|
| Codex 각도 실패/미시작/prompt-too-large | models_cache 폴백 slug로 1회 재시도 → 실패 시 `[fallback: ...]` 마커(stderr tail 보존) → degraded, `meta.degraded_angles` |
| Evidence pass 콜 실패/후보 누락 | **그 후보만** `SUSPECTED(missing: EVIDENCE_PASS_FAILED)` — 판정된 후보 재실행 금지, 라운드 fail 금지 |
| 5 각도 중 3+ degraded | 헤더에 명시 + `/prism` 전환 제시. 리포트는 실제 돈 것만 주장 |
| secret-scrub 히트 | 보안 인시던트 메타로 격리 — defect triage 제외, 경고를 findings 밖에 |

---

## 비용 / 속도

| Mode | Pass 1 | Evidence | Repro | 상대 비용 |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 0 | 1.0× |
| default | 5 | ⌈후보/8⌉ chunked | 0 | 1.2~1.5× |
| `--adversarial` | 5 | ⌈후보/8⌉ | 0 | 1.2~1.5× |
| `--reproduce` | 5 | ⌈후보/8⌉ | ≤5 test runs | 1.5~2.2× |

wall time: Codex 각도별 호출이므로 **~100~200s** (파일 크기 의존). `--include-improvements`: Pass 1 = 6.

## 자립성 검증

```bash
node verify-independence.js --strict   # Codex CLI >= 0.125.0 포함 체크
```

## 자매 skill과의 관계

| Skill | Engine | 언제 |
|---|---|---|
| `/prism` | Claude 5 + Claude Evidence pass | Claude 토큰 여유, 빠른 1-엔진 리뷰 |
| `/prism-codex` (이 skill) | Codex 5 + Codex Evidence pass | 다른 모델 관점 필요 / Claude 토큰 절약 |
| `/prism-all` | Claude 5 + Codex 5 (병렬) + Evidence pass | 최고 신뢰, 양쪽 토큰 OK |

세 skill은 완전 독립 plugin. 하나만 설치해도 동작.

## 안티패턴

- ❌ Codex 호출을 한 각도씩이 아니라 병렬로 — CLI는 한 번에 1콜이 안정적.
- ❌ **합의 2+건을 Evidence pass 없이 자동 CONFIRM** — 같은 모델의 합의는 상관된 오해일 수 있다. 합의는 우선순위, 확정은 코드 접지.
- ❌ **위치 없는 SUPPORTED / 기계 검증(verify-evidence.js) 건너뜀** — 지어낸 인용이 SUPPORTED로 나가면 v0.1보다 나쁘다.
- ❌ Evidence pass를 후보당 1콜로 스폰 — ≤8건 chunked batch.
- ❌ **재현 테스트를 프로젝트 트리에 작성 / env 안 스트립하고 실행 / 러너 설치** — 임시 디렉토리·stripped env·PATH의 러너만(§Pass 3, `/prism` v0.2 규약).
- ❌ argv로 프롬프트 — 항상 tempfile + stdin.
- ❌ SANDBOX SAFETY PREAMBLE 누락 / post-run scrub 건너뜀 (불변 6·7).
- ❌ 다른 plugin/skill 파일을 **런타임 참조** — record v2 스키마·preamble·스크립트는 이 파일이 자체 보유(정본은 prism-all, sync로 동일 사본).
