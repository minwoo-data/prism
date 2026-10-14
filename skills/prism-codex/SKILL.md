---
name: prism-codex
description: Codex-backed evidence-graded code review. Like prism but the 5 discovery agents + Evidence pass are all Codex CLI (gpt-5.5). Statuses SUSPECTED → SUPPORTED → REPRODUCED; agreement prioritizes, evidence confirms. --redteam adds an attacker-mindset lens. Code only; documents go to /triad. Use when you want different-model opinions or Claude tokens are scarce. Triggers on "/prism-codex <target>", "prism codex로", "codex prism".
argument-hint: "<target> [--quick] [--adversarial] [--reproduce] [--redteam] [--include-improvements] [--format json] [--artifacts=temp|docs]"
user-invocable: true
---

# prism-codex — Codex-backed Multi-Angle Review

> 메인은 Claude (오케스트레이터). 5 discovery + Evidence pass는 **모두 Codex CLI** (gpt-5.5). 목적: Claude self-bias 회피 + Claude 토큰 절약. **합의는 우선순위, 확정은 코드 접지.**

이 skill 디렉토리의 파일: `parse-findings.js`, `verify-evidence.js`(결정론 스크립트),
`references/codex-invocation.md`(Codex 호출 계약 — preamble·템플릿·scrub·fallback·사건 기록),
`references/record-v2.md`(finding 스키마 + confidence 표), `references/redteam-lens.md`,
`references/classic-lenses.md`(deprecated). 참조 파일은 아래 단계가 지시할 때만 읽는다.

## 핵심 가치

`/prism`과 동일한 5-렌즈 분산 + Evidence pass 패턴. 차이는 판단 주체가 다른 모델(OpenAI gpt-5.5 via Codex CLI). 둘 다 원하면 `/prism-all`.

⚠️ **단일 모델 ensemble의 한계**: 5 agents가 전부 같은 모델이므로 **합의(2+)는 확정이 아니라 우선순위 신호**. 합의만으로 confidence MEDIUM 상한; SUPPORTED 이상은 Evidence pass의 코드 접지(위치+실행경로+인용)가 필요. Evidence 사다리(SUSPECTED/SUPPORTED/REPRODUCED/REJECTED)와 record v2는 prism 가족 공통(`references/record-v2.md`).

## 렌즈 (기본 DEFECT)

| Lens | 역할 |
|---|---|
| 1. **Correctness & Contracts** | 틀린 결과·경계값·에러 경로·불변식·API 계약 위반. "구체 입력 → 틀린 출력" 우선 |
| 2. **Security & Trust Boundaries** | 입력 검증·인가 공백·injection·secret·unsafe default (+공격자 전제조건). 체크리스트가 있으면 `[checklist:#N]`/`[not-in-checklist]` 태그 |
| 3. **State, Concurrency & Recovery** | race/lost update/TOCTOU·비멱등 재시도·고아/고착 상태 (+트리거 시퀀스) |
| 4. **Integration & Regression** | 호출자 계약 파괴·스키마/설정 드리프트·하위호환·숨은 결합. 호출자 컨텍스트가 없으면 추측 대신 명시 |
| 5. **Testability & Observability** | 삼켜진 예외·조용한 폴백·거짓 로그·신호 없는 실패 |

- `--redteam` → 6번째 **Red Team** 렌즈. 프롬프트 `references/redteam-lens.md`. ATTACK CHAINS·CHECKLIST COVERAGE 섹션 추가.
- `--include-improvements` → **Improvement** 렌즈 추가(분리 집계).
- `--lenses=classic` → **deprecated(0.4 제거)**, 명시할 때만. `references/classic-lenses.md`.
- **비코드 대상은 거부**: `prism은 코드 리뷰어 — 문서는 /triad <file>` 출력 후 중단(명시적 classic만 예외).
- **프로젝트 보안 체크리스트**: Pass 1 전에 `docs/security-checklist.md` → `docs/security/checklist.md` → `SECURITY.md` → `docs/SECURITY.md` 첫 파일(≤3 tool call) → **Security·Red Team 렌즈에만** 전달.

## 전제 (Prerequisite)

**Codex CLI ≥ 0.125.0** 필수 (`codex --version`). 부적합 시 중단 + `npm install -g @openai/codex@latest` 안내. Claude로 자동 대체하지 않음(이 skill의 존재 이유가 다른 모델). 모델·폴백: `references/codex-invocation.md` §Operator rules.

## 트리거

| 형태 | 모드 |
|---|---|
| `/prism-codex <target>` | 기본 — 5 discovery + Evidence pass(전 후보 접지) |
| `--quick` | Evidence pass 생략 — 전부 `SUSPECTED` |
| `--adversarial` | REJECT 확정 전 반대 주장 |
| `--reproduce` | + 재현 pass(SUPPORTED CRIT/HIGH 우선, 최대 5건, prism 공통 규약) |
| `--redteam` | + Red Team 렌즈 |
| `--include-improvements` | Improvement 렌즈 추가 |
| `--format json` | record v2를 `prism-report.json`으로도 출력 |
| `--artifacts=temp` (기본) / `docs` | 산출물 위치(`docs`는 .gitignore 필수) |
| 자연어 | "prism codex로", "codex prism", "prism-codex 돌려" |

## Target 해석

파일 경로 → 해당 파일. 주제 → 관련 파일 탐색. 인자 없음 → 현재 프로젝트. **항상 전체를 먼저 읽고** 각 Codex 호출에 그대로 전달(요약 금지).

---

## Pass 1 — Codex 호출 (렌즈당 Bash 1개)

**첫 Codex 호출 전에 `references/codex-invocation.md`를 읽고 그 템플릿을 그대로 쓴다** (Sandbox Safety Preamble prepend·tempfile+stdin·180K 가드·180s timeout·secret scrub·`--output-last-message`·`parse-findings.js` 추출). 렌즈당 별도 Bash 호출(한 Bash 안에서 5개 순차 금지 — hang 시 뒷 렌즈 유실). Codex CLI는 한 번에 1콜이 안정적이므로 Bash들을 순차로 발사. Wall time ≈ 5 × (15~40s) = **~100~200s**.

**프롬프트 조립 순서**: Preamble → ① target 전문(모든 렌즈 동일 → 공통 prefix) → ② 렌즈별 컨텍스트(Security/Red Team만 체크리스트) → ③ 렌즈 정의 + 출력 계약(마지막).

공통 계약: **"너는 의심을 생산한다 — 확정은 Evidence pass의 일. LOCUS는 `file:lines@symbol`, `|` 금지."**

### 출력 포맷 v1

자유 추론 뒤 **마지막 펜스**로:
```
<<<PRISM-FINDINGS v1>>>
CRIT | <locus> | <problem> -> <fix>
HIGH | <locus> | <problem> -> <fix>
<<<END>>>
```
SEV ∈ `CRIT|HIGH|MED|LOW`. 펜스 밖 텍스트 무시. finding 없으면 빈 블록. v1 고정.

---

## Synthesis Triage (메인)

`$OUT.json`(파서 출력)을 모아 semantic dedup. **분류는 우선순위이지 확정이 아니다 — 전 후보가 Pass 2로 간다.**

- **AGREEMENT**: 2+ agents 지적 → 우선 후보. 자동 CONFIRM 금지(같은 모델 5명의 합의는 상관된 오해일 수 있음).
- **SINGLETON**: 1 agent → 후순위.
- `degraded:true`는 후보 아님 → `meta.degraded_angles`, "DEGRADED ANGLES" 섹션.
- `--quick` → 전부 `SUSPECTED`. 후보 0건 → Pass 2 스킵.

---

## Pass 2 — Codex Evidence pass (파일 단위 청킹 접지)

후보를 우선순위(AGREEMENT → CRIT/HIGH → 나머지)로 정렬 후 **파일 단위로 ≤8건씩** 청킹(최우선 후보의 파일을 잡고 같은 파일 후보를 묶고 다음 파일로 — 한 청크가 한 파일을 한 번만 읽게). 각 콜에 candidate id를 실어 1:1 대응. 콜 실패/후보 누락 → **그 후보만** `SUSPECTED(missing: EVIDENCE_PASS_FAILED)`, 판정된 후보 재실행 금지, 라운드 fail 금지. Evidence 호출도 `codex-invocation.md` 템플릿(preamble·scrub)을 따른다.

> 너는 **Evidence Agent**. 5 리뷰어가 같은 target을 분석해 아래 후보를 냈다. 각 후보를 실제 코드에 접지시키거나, 죽여라. 인용은 반드시 파일을 읽어 실제 존재하는 텍스트로(사후 기계 검증).
> 1. 위치 고정: `file`, `lines`, `symbol`. 불가 → `SUSPECTED` + `missing`.
> 2. 실행 경로: 진입→결함 순서.
> 3. 증거 인용: `file:line — 인용`.
> 4. 전제조건: 불가능하면 반증 인용과 `REJECTED`.
> 5. 판정: `SUPPORTED` / `REJECTED` / `SUSPECTED`(+`REQUIRES_DOMAIN_CONFIRMATION: <질문>`). 위치만 → `evidence_strength: WEAK`.
> 6. severity 조정 가능(한 문장). 새 finding 발명 금지.
> 7. `SUPPORTED`마다 `suggested_test`. 8. 합쳐져 더 큰 결과가 되는 후보는 같은 `chain` id.
> 포맷: 후보당 record v2 1건을 `<<<PRISM-RECORDS v2>>>` ~ `<<<END>>>` 펜스에 한 줄 JSON(스키마 `references/record-v2.md`). `evidence_strength`: NONE/WEAK/MEDIUM.

**기계 검증(불변)**: `node verify-evidence.js records.json <repo-root> > checked.json` — 인용 불일치 → `SUSPECTED(EVIDENCE_QUOTE_MISMATCH)` 자동 강등, fingerprint 코드 계산. **checked.json이 최종 진실.**

`--adversarial`: REJECT 전 반대 주장 먼저 — 반박이 더 구체적·근거 우위일 때만 REJECT.

`--reproduce`: prism 공통 규약 — 기계 검증 통과 SUPPORTED, CRIT/HIGH 우선 최대 5건, **stripped env·cwd=임시 디렉토리·프로젝트 트리 쓰기 금지·러너 설치 금지·실패 시그니처 사전 등록·per-test 60s·2회 연속 동일·운영자 confirm 1회**. 분류: REPRODUCED / NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT(setup/import 에러 포함) / TIMED_OUT / STATIC_EVIDENCE_ONLY / REQUIRES_EXTERNAL_SERVICE / REQUIRES_DOMAIN_CONFIRMATION. 자작 통과 테스트는 최대 SUSPECTED까지만 강등.

---

## Final Report

```
PRISM-CODEX REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce] [+redteam] · Lenses: defect {+redteam} | classic (deprecated)
Engine: Codex CLI (gpt-5.5) {n}/5 · Checklist: {path | none}
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected

## REPRODUCED / ## SUPPORTED / ## SUSPECTED / ## REJECTED
- PRISM-001 [HIGH|security|HIGH] file:lines@symbol — claim
  [3/5 agreement] evidence: file:line — 인용 (verified) | repro: STATIC_EVIDENCE_ONLY | suggested_test: ... | checklist: #14
## ATTACK CHAINS (--redteam 또는 chain 있을 때) / ## CHECKLIST COVERAGE (체크리스트 로드 시)
## DEGRADED ANGLES / ## IMPROVEMENTS (--include-improvements)
## Recommended Action Order
```

`[N/5 agreement]`는 우선순위 신호. 단일 모델이므로 합의만으로 MEDIUM 상한. `--quick`: 전부 SUSPECTED. `--format json`: `${artifacts}/prism-report.json`(기본 `$TMPDIR/prism-codex/<slug>-<run-id>/`) 원자적 출력.

---

## 비용 / 속도

| Mode | Pass 1 | Evidence | Repro | 상대 비용 |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 0 | 1.0× |
| default | 5 | ⌈후보/8⌉ chunked | 0 | 1.2~1.5× |
| `--redteam` | 6 | ⌈후보/8⌉ | 0 | +0.25× |
| `--reproduce` | 5 | ⌈후보/8⌉ | ≤5 | 1.5~2.2× |

Claude 토큰은 오케스트레이션분만 소비. target을 작게(변경 범위로) 넘기는 것이 가장 큰 절약. 프롬프트는 target 먼저·렌즈 나중.

## 자립성 검증

```bash
node verify-independence.js --strict
```

## 자매 skill

| Skill | Engine | 언제 |
|---|---|---|
| `/prism` | Claude 5 + Claude Evidence | Claude 토큰 여유, `--diff` |
| `/prism-codex` (이 skill) | Codex 5 + Codex Evidence | 다른 모델 / Claude 토큰 절약 |
| `/prism-all` | Claude 5 + Codex 5 + Evidence | 최고 신뢰 |

완전 독립 plugin. 정본은 prism-all, 사본은 `sync-review-parsers.sh`. 문서는 `/triad`, 반복 수정은 `/mangchi`, 구 `prism-devil`은 `--redteam`.

## 안티패턴

- ❌ Codex 여러 렌즈를 한 Bash 안에서 — 렌즈당 Bash 1개
- ❌ **합의 2+를 Evidence pass 없이 자동 CONFIRM**
- ❌ **위치 없는 SUPPORTED / verify-evidence.js 건너뜀**
- ❌ Evidence pass를 후보당 1콜로 — 파일 단위 ≤8 청킹
- ❌ 재현 테스트를 프로젝트 트리에 / env 안 스트립 / 러너 설치
- ❌ argv로 프롬프트 / SANDBOX SAFETY PREAMBLE 누락 / scrub 건너뜀 (`references/codex-invocation.md`)
- ❌ 문서를 prism으로 — `/triad`
- ❌ 다른 plugin/skill 파일 런타임 참조
