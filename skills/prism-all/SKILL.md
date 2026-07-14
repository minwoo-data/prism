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

**한 메시지 안에서 전부 병렬** (기본 DEFECT 렌즈 — `--lenses=classic`일 때만 구 이름):
- Claude 5개: `Agent` tool × 5 (Correctness / Security / State / Integration / Testability), forked context. `--include-improvements` 시 6번째(Improvement) 추가.
- Codex 5개: **각도당 별도 `Bash` 호출**(한 Bash에 5개 순차 금지 — 외부 타임아웃·부분 hang 시 뒷 각도가 파일 없이 통째로 유실됨, robustness A1-2/A2-3). 발사 전 5개 `$OUT`를 `[fallback: not-started]`로 미리 생성 → 안 채워진 각도 = degraded로 확정.

Wall time ≈ max(Claude 5 parallel ≈ 20~40s, Codex 5 (각도별 병렬/순차) ≈ 100~200s) = **Codex 쪽 병목**.

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

### 합성(ANGLE-DEGRADED) 마커는 후보가 아니다
파서가 각도 파싱 실패 시 주입하는 `MED | <angle> | ANGLE-DEGRADED...` 는 인프라 신호다 — **triage/Evidence pass에 넣지 않는다**(넣으면 Evidence Agent가 접지 불가로 REJECTED시켜 신호가 소멸, robustness A1-1). `degraded:true`로 표시해 리포트의 "DEGRADED ANGLES" 섹션으로 직행시키고 candidate_count·fingerprint에서 제외.

### Short-circuit
- `--quick` → Pass 2 스킵, 전부 `SUSPECTED`(evidence_strength NONE, reproduction NOT_RUN, fingerprint null)로 보고 (Tier 레이블 유지)
- 후보 0건 → Pass 2 스킵

---

## Pass 2 — Evidence pass (전 후보 배치 검증 + 기계 검증)

Verifier가 아니라 **Evidence Agent** — 의견 대조가 아니라 코드 접지(grounding)가 일이다. Read/Grep/Glob 도구로 실제 파일을 읽어 인용한다.

**배치 규약(무보호 단일 콜 금지)**: 후보 **≤8건**마다 한 콜로 청킹, Tier 1 → CRIT/HIGH → 나머지 순. 각 콜 프롬프트·응답에 candidate id를 실어 1:1 대응 검증. 어느 콜이 죽거나 후보를 빠뜨리면 **그 후보만** `SUSPECTED(missing: EVIDENCE_PASS_FAILED)`로 보고 — 이미 판정된 후보 재실행 금지, 라운드 전체 fail 금지.

Evidence Agent 프롬프트:

> 너는 Evidence Agent. 리뷰어들이 낸 아래 후보들을 **실제 코드에 접지시키거나, 죽여라.** 리뷰어 말은 절대 그대로 믿지 않는다 — 인용은 반드시 파일을 Read 해서 가져온다. 후보마다:
>
> 1. **위치 고정**: 정확한 `file`, `lines`, `symbol`. 고정 불가 → `SUSPECTED` + `missing` 기록.
> 2. **실행 경로 추적**: 진입→결함까지 순서 있는 호출/분기 단계.
> 3. **증거 인용**: claim을 참으로 만드는 줄을 `file:line — 인용`으로. **인용 문자열은 그 줄에 실제로 존재하는 텍스트여야 한다**(사후 기계 검증됨 — 지어내면 강등된다).
> 4. **전제조건 점검**: 불가능하면 반증 인용과 함께 `REJECTED`.
> 5. **판정**: `SUPPORTED`(1~3 전부) / `REJECTED`(반증 인용) / `SUSPECTED`(고정 불가 또는 `REQUIRES_DOMAIN_CONFIRMATION: <질문>`). 위치는 잡았으나 경로/인용 불완전 = `SUSPECTED` + `evidence_strength: WEAK`.
> 6. severity 조정 가능(한 문장 근거). 새 finding 발명 금지.
> 7. `SUPPORTED`마다 `suggested_test`(함수명 + 한 줄 시나리오).
> 8. 후보마다 finding record v2 1건을 아래 펜스로 emit:
> ```
> <<<PRISM-RECORDS v2>>>
> {"id":"PRISM-001","candidate_id":"c1","file":"src/auth.py","lines":"84-102","symbol":"reset_password","category":"security","severity":"HIGH","status":"SUPPORTED","claim":"...","evidence":["src/auth.py:98 — <실제 줄 텍스트>"],"reproduction":{"status":"NOT_RUN"},"confidence":{"model_agreement":"3/5","evidence_strength":"MEDIUM"}}
> <<<END>>>
> ```
> (한 줄 = 한 JSON record. `evidence_strength`: NONE / WEAK(위치만) / MEDIUM(위치+경로+인용) / STRONG(재현 pass만).)
>
> `--verifier=both`: Claude·Codex 각 1콜. 둘 다 SUPPORTED → SUPPORTED. 한쪽 실패 → 생존 엔진 단독 모드(헤더 플래그). SUPPORTED×REJECTED → SUSPECTED + 양쪽 근거를 Conflicting에 병기. 둘 다 REJECTED → REJECTED.
> `--adversarial`: REJECT 확정 전 리뷰어 편에서 반박 — 반박이 더 구체적·근거 우위일 때만 REJECT.

**기계 검증(불변, LLM 자기채점 방지)**: Evidence 응답의 v2 record를 파싱한 뒤 반드시
```
node "<skill dir>/verify-evidence.js" records.json "<repo-root>" > checked.json
```
를 돌린다. 이 스크립트가 (1) 모든 `SUPPORTED/REPRODUCED`의 `file:line — 인용`을 실제 파일에서 grep해 없으면 `SUSPECTED(EVIDENCE_QUOTE_MISMATCH)`로 자동 강등, (2) fingerprint를 코드로 재계산(sha1(file|symbol|category|claim-slug)[:12], LLM freehand hex 폐기)한다. **checked.json이 최종 진실** — 검증 안 된 인용은 SUPPORTED로 리포트 금지.

---

## Pass 3 — 재현 (`--reproduce`)

프로젝트는 **절대 수정하지 않는다** — 재현은 일회용 샌드박스에서. Actor: **main agent(또는 Bash 권한을 가진 Reproduction Agent)** 가 실행한다 — Evidence Agent는 코드를 실행하지 않는다.

- 대상: `SUPPORTED`(기계 검증 통과분)만, CRIT/HIGH 우선, **런당 최대 5건**(초과분은 `STATIC_EVIDENCE_ONLY`).
- **실행 안전(불변 — "임시 디렉토리"는 쓰기 가드일 뿐 실행 샌드박스가 아니다, Devil CRIT)**: target을 import/실행하면 모듈 레벨 부작용이 **운영자 env를 물려받아** 돈다(2026-05-22 유출 표면과 동일). 그러므로 재현 명령은 반드시 ① **env 스트립**(`env -i` + PATH·언어런타임 등 allowlist만) ② **cwd = 임시 디렉토리** ③ 네트워크 차단(러너가 지원 시) ④ **설치 전면 금지**(PATH에 이미 있는 러너만 — "installable"이라고 새로 깔지 않는다) ⑤ 첫 실행 전 **운영자 confirm 1회** ⑥ 출력에 §Codex 불변 7의 secret-scrub 적용 후 리포트 반영.
- 절차: ① 기존 테스트 먼저 검색 ② PATH의 러너 감지(pytest/vitest/jest/node --test/go test/cargo test — 없으면 `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`, 설치하지 않음) ③ 임시 디렉토리(`${TMPDIR:-${TEMP:-/tmp}}/prism-tests/`, `mktemp -d` 권장)에 최소 실패 테스트 작성 — 프로젝트 트리 쓰기 금지 ④ **claim의 실패 시그니처(예상 예외/assertion 메시지)를 record에 먼저 등록** ⑤ per-test **60s** 타임아웃(총 5min)으로 실행, exit code·duration·stdout/stderr tail 원문 기록.
- 분류: `REPRODUCED`(등록한 시그니처와 **일치하는** 실패, 2회 연속 동일) / `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`(러너·의존성 없음) / `TIMED_OUT`(동시성 버그는 hang이 곧 재현일 수 있음 — 상향 금지, 별도 기록) / `STATIC_EVIDENCE_ONLY`(cap/정적 claim) / `REQUIRES_EXTERNAL_SERVICE` / `REQUIRES_DOMAIN_CONFIRMATION`.
- **setup/import/fixture 에러는 `REPRODUCED`가 아니라 `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`** — 아무 red나 "예측대로 실패"로 세지 않는다.
- **자작 테스트 통과 시**: 같은 전제조건·경로를 실제로 exercise한 경우에만 강등. 그렇지 않으면 `SUPPORTED` 유지 + `reproduction.status: NOT_REPRODUCED_BY_ATTEMPT`. 강등은 최대 `SUSPECTED`까지 — 자작 통과 테스트는 `REJECTED` 근거가 못 된다.
- 종료 시 임시 디렉토리 정리(단 scrub 이벤트 시 §A2 보존 규칙), 테스트 소스는 **리포트+JSON에 보존**.

---

## Finding record v2 + Confidence

record 스키마는 `/prism` SKILL.md와 동일 (id / candidate_id / fingerprint / file / lines / symbol / category / severity / status / claim / preconditions / execution_path / evidence / reproduction{status,suggested_test,expected_signature,command,result} / confidence{model_agreement,evidence_strength,label} / missing / degraded / suggested_fix / agreement{claude,codex,cross_model}). `SUPPORTED` 이상은 file/lines/symbol/execution_path/인용 **필수**. **fingerprint·evidence_strength·status는 verify-evidence.js가 최종 확정**(모델값 덮어씀). fingerprint = `sha1(normPath|symbol|category|claim-slug)[:12]`, `file:null` → `unpinned:true`로 CI dedup 제외.

**Confidence 결정표(스토어된 필드로 계산 가능 — 닫힌 enum {LOW, MEDIUM, MEDIUM-HIGH, HIGH, HIGH+, VERY-HIGH})**:

| model_agreement | evidence_strength | label |
|---|---|---|
| singleton | NONE/WEAK | LOW |
| intra-model 2+ | NONE/WEAK | **MEDIUM (상한 — 같은 모델 반복 오해)** |
| cross-model | NONE/WEAK | MEDIUM-HIGH |
| (any) | MEDIUM (위치+경로+인용, 기계검증됨) | HIGH |
| cross-model | MEDIUM | HIGH+ |
| (any) | STRONG (재현됨) | VERY-HIGH |
| REJECTED | — | (REJECTED 섹션, label 없음) |

비코드 대상(문서)은 "인용"이 실행 경로가 아니라 문서 구절이므로 **HIGH 부여 금지 — MEDIUM 상한**(discovery agent가 이미 전체 문서를 봤으므로 같은 문서 재인용은 독립 접지가 아님).

---

## Final Report

```
PRISM-ALL REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce] · Lenses: {defect|classic} {(auto)|(explicit)}
Engines: Claude 5/5 + Codex {n}/5{ (degraded: <lenses>)} · Evidence: {claude | codex | both}
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected  (infra-degraded: D)

## REPRODUCED (실패 시연됨)
- PRISM-003 [HIGH|security|VERY-HIGH] file:lines@symbol — claim
  [cross-model/security] path: ... | repro: <command> → FAILED (signature match) | fix: ...

## SUPPORTED (코드 경로 증거, 미실행 — 인용 기계검증됨)
- PRISM-001 [...|HIGH] file:lines@symbol — claim
  [claude/multi] evidence: file:line — 인용 (verified) | repro: STATIC_EVIDENCE_ONLY | suggested_test: ...

## SUSPECTED (추론만 — 확인 필요)
- PRISM-007 [...] — claim — missing: REQUIRES_DOMAIN_CONFIRMATION: <운영자에게 물을 질문>

## REJECTED (투명성)
- [codex/correctness] claim — 반증: file:line — 인용

## DEGRADED ANGLES (인프라 — finding 아님)
- codex/state: [fallback: codex-unavailable] · codex/security: [fallback: prompt-too-large]

## IMPROVEMENTS (--include-improvements 시만)
## Engine-Unique Findings (참고) / ## Conflicting Advice (있으면)
## Recommended Action Order
REPRODUCED 먼저, 그다음 SUPPORTED를 severity 순으로. SUSPECTED는 task가 아니라 질문으로.
```

**리포트는 실제로 돈 것만 주장한다** — 헤더의 `Codex {n}/5`·DEGRADED ANGLES는 파서의 `degraded` 플래그에서 생성. 2개 각도가 fallback이면 "Claude 5/5 + Codex 3/5 (degraded: security, state)"로 표기하고, cross-model 신뢰 라벨은 실제 양쪽이 응답한 렌즈에만 부여.

`--format json`: `${artifacts}/prism-report.json`(기본 `$TMPDIR/prism-all/<slug>-<run-id>/`, `--artifacts=docs` 시 repo — 이땐 .gitignore 필수)에 원자적 출력(temp write → validate → rename). 실패 시 리포트에 인라인 + `json_output: failed` 경고, 라운드는 실패시키지 않음. `{ "meta": {target,mode,lenses,engines,timestamp,counts}, "findings": [<record v2>...] }`. fingerprint(verify-evidence.js 계산)로 런 간 dedup — **status는 per-run 진실, dedup은 fingerprint로 link만 하고 이전 REJECTED를 다음 런에 suppress하지 않는다**(A4-1). (SARIF·GitHub Action: 로드맵.)

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
# 산출물은 기본 임시 디렉토리 — repo를 오염시키지 않는다. run-id 로 동시/재실행 격리하고
#  mode 700 으로 멀티유저 /tmp 에서 target 소스가 world-readable 되는 것을 막는다 (robustness A4-2).
#  기록을 repo 에 남기려면 --artifacts=docs (docs/prism-all/<slug>) — 이땐 그 경로를 .gitignore 에.
BASE="${TMPDIR:-${TEMP:-/tmp}}/prism-all"
DIR="$BASE/<slug>-<run-id>"                    # run-id = timestamp/PID; --artifacts=docs -> docs/prism-all/<slug>
mkdir -p "$DIR"; chmod 700 "$BASE" "$DIR" 2>/dev/null
AGENT="<correctness|security|state|integration|testability>"   # classic: conflict|improvement|devil|code-review|robustness
PROMPT="$DIR/pass1.codex.$AGENT.prompt.txt"
OUT="$DIR/pass1.codex.$AGENT.codex.txt"

# Pre-create the output as not-started so a killed outer loop / missing file is
# read as DEGRADED, never silently dropped (robustness A1-2/A2-3).
echo "[fallback: not-started]" > "$OUT"

# Unbreakable preamble FIRST (do not let the agent prompt override).
cat > "$PROMPT" <<'EOF'
SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):
... (full preamble text from §Sandbox Safety Preamble above) ...

==== AGENT PROMPT BELOW ====
EOF
cat >> "$PROMPT" <<'EOF'
(agent prompt)
EOF
cat "$TARGET" >> "$PROMPT"

BYTES=$(wc -c < "$PROMPT")
# Oversized prompt hits EVERY angle identically -> mark degraded + continue,
# never `exit 2` (that killed later angles with no marker). Suggest /prism switch.
if [ "$BYTES" -gt 180000 ]; then echo "[fallback: prompt-too-large]" > "$OUT"; continue; fi

# NOTE: each angle is its own Bash invocation (SKILL §Pass 1). Do NOT loop all 5
# inside one Bash — outer-timeout/hang then loses later angles as missing files.
timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --output-last-message "$OUT.msg" < "$PROMPT" > "$OUT.raw" 2>&1 || {
  # keep stderr tail so the operator can tell config-error vs timeout vs auth
  echo "[fallback: codex-unavailable] $(tail -c 300 "$OUT.raw" 2>/dev/null | tr '\n' ' ')" > "$OUT"
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

**파서가 정본 — 이 산문은 계약 설명일 뿐, 규칙 충돌 시 parse-findings.js 헤더가 이긴다.** discovery 출력(`<<<PRISM-FINDINGS v1>>>`~`<<<END>>>`, 한 줄 = `SEV | LOCUS | TEXT`)을 LLM 눈대중이 아니라 코드로 추출:

```
node "<skill dir>/parse-findings.js" "$OUT" "$AGENT" > "$OUT.json"
```

파서 실동작(헤더 정본): (1) **모든 펜스 블록을 스캔해 valid finding이 가장 많은 블록 선택**, 개수 동률이면 첫 블록 — "첫 블록만" 규칙은 모델이 example 펜스를 먼저 emit하면 진짜 리뷰를 누락시켜 **폐기됨**(구 산문 표현 삭제). ⚠️ 역실패 주의: real 블록이 비어 있고(각도 clean) example 블록이 finding을 담으면 example이 이길 수 있으므로, discovery 계약은 "**진짜 블록을 메시지 마지막 펜스로** emit"하도록 요구하고 파서는 동률 시 last-valid 우선. (2) severity 별칭 정규화(critical→CRIT 등). (3) LOCUS는 **`|` 금지**(파서는 첫 두 `|`로만 분할, 마지막 `->`를 fix 경계로) — 렌즈는 markdown 제목/경로의 `|`를 치환 후 emit. (4) zero-width는 토큰 비교에만 strip(내용 보존). (5) `--output-last-message FILE`로 codex 2회출력·노이즈 소스 제거(raw는 scrub용 별도).

→ `$OUT.json` = `{angle, degraded, skipped, findings:[{severity,locus,text}]}`. **degraded=true는 후보가 아니라 `meta.degraded_angles`로** — Evidence pass·candidate_count·fingerprint 제외(A1-1). synthesis는 파싱된 record를 `{engine, lens, degraded, raw_locus, raw_text}` 봉투로 감싼 뒤 triage(cross-model 합의·dedup)한다 — 코드=추출, LLM=의미 판단. 자가 검증: `node parse-findings.js --selftest` (+ Evidence 단계: `node verify-evidence.js --selftest`).

### Fallback 정책 (각도별 독립 회계)

| 상황 | 동작 |
|---|---|
| 각도 Codex 실패/미시작/prompt-too-large | `$OUT`의 `[fallback: ...]` 마커 → 해당 각도 degraded, `meta.degraded_angles`에 기록. Claude측 같은 렌즈 생존 시 `[cross-model-unavailable]`로 태그(singleton보다 아래로 격하 금지) |
| 각도 Claude 실패 | `[fallback: claude-unavailable]`, Codex측만으로 그 렌즈 처리 |
| 같은 렌즈 양쪽 실패 | 그 렌즈 cross-model 불가 — degraded 처리, 라운드는 계속 |
| Evidence pass 콜 실패/후보 누락 | **그 후보만** `SUSPECTED(missing: EVIDENCE_PASS_FAILED)` — 판정된 후보 재실행 금지, 라운드 fail 금지 |
| 3+ 렌즈에서 한 엔진 전체 degraded | 헤더에 명시(`Codex 2/5`) + `/prism`(Codex 고장) 또는 `/prism-codex`(Agent 고장) 전환 제시. 리포트는 실제 돈 것만 주장 |
| secret-scrub 히트 | 보안 인시던트 메타로 격리 — defect triage 제외, 운영자 경고를 findings 밖에 표시(A2-6) |

---

## 비용 / 속도

| Mode | Claude 콜 | Codex 콜 | Evidence | Repro | wall time | 상대 비용 |
|---|---|---|---|---|---|---|
| `--quick` | 5 | 5 | 0 | 0 | ~100~200s | 2.0× prism |
| default | 5 | 5 | ⌈후보/8⌉ chunked | 0 | ~120~240s | 2.2~2.5× |
| `--adversarial` | 5 | 5 | ⌈후보/8⌉ | 0 | ~120~240s | 2.2~2.5× |
| `--verifier=both` | 5 | 5 | ⌈후보/8⌉×2 | 0 | ~140~280s | 2.4~2.8× |
| `--reproduce` | 5 | 5 | ⌈후보/8⌉ | ≤5 test runs | ~180~340s | 2.6~3.2× |

`--include-improvements`: discovery 6+6. Evidence는 후보 ≤8건마다 1콜(청킹) — 이전 "1 batched"는 30+후보를 한 콜에 밀어넣어 접지 깊이가 붕괴하던 걸 숨겼음(리뷰 HIGH).

## 자립성 검증

```bash
node verify-independence.js --strict   # Codex CLI >= 0.125.0 포함
```

## 자매 skill과의 관계

| Skill | Engine | 언제 |
|---|---|---|
| `/prism` | Claude 5 + Claude Evidence pass | 빠른 1-엔진, Claude 토큰 여유 |
| `/prism-codex` | Codex 5 + Codex Evidence pass | 다른 모델 ensemble / Claude 토큰 절약 |
| `/prism-all` (이 skill) | Claude 5 + Codex 5 + Evidence pass | 최고 신뢰, 양쪽 토큰 OK |

셋 다 독립 plugin — 각자 SKILL.md에 record v2 스키마·preamble·결정론 스크립트(parse-findings.js, verify-evidence.js) 사본을 자체 보유(포인터는 provenance 주석일 뿐, 다른 plugin 파일을 런타임 참조하지 않는다). 정본은 prism-all, 사본은 `skills/sync-review-parsers.sh`로 생성.

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
