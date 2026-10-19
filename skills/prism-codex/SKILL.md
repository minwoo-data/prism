---
name: prism-codex
description: Codex-backed evidence-graded code review. Like prism but the 5 discovery agents + Evidence pass are all Codex CLI (gpt-5.5). Statuses SUSPECTED → SUPPORTED → REPRODUCED; agreement prioritizes, evidence confirms. --redteam adds an attacker-mindset lens. Design docs get the design lens set (pair with /triad for writing quality). Use when you want different-model opinions or Claude tokens are scarce. Triggers on "/prism-codex <target>", "prism codex로", "codex prism".
argument-hint: "<target> [--quick] [--adversarial] [--reproduce] [--redteam] [--no-ideas] [--include-improvements] [--lenses=design] [--format json] [--artifacts=temp|docs]"
user-invocable: true
---

# prism-codex — Codex-backed Multi-Angle Review

> 메인은 Claude (오케스트레이터). 5 discovery + Evidence pass는 **모두 Codex CLI** (gpt-5.5). 목적: Claude self-bias 회피 + Claude 토큰 절약. **합의는 우선순위, 확정은 코드 접지.**

이 skill 디렉토리의 파일: `codex-run.sh`(Codex 호출 계약을 코드로 — preamble·stdin·가드·timeout·scrub·파싱),
`parse-findings.js`, `verify-evidence.js`, `verify-ideas.js`(결정론 스크립트),
`templates/`(아이디어 pass의 프롬프트·출력 계약),
`references/codex-invocation.md`(왜 그런 계약인지 — 불변식·fallback 정책·사건 기록, 렌즈가 degraded일 때만 읽는다),
`references/record-v2.md`(finding 스키마 + confidence 표), `references/redteam-lens.md`,
`references/design-lenses.md`(문서용 design 렌즈셋), `references/ideas.md`(아이디어 pass 규칙·실패 처리). 참조 파일은 아래 단계가 지시할 때만 읽는다.

## 핵심 가치

`/prism`과 동일한 5-렌즈 분산 + Evidence pass 패턴. 차이는 판단 주체가 다른 모델(OpenAI gpt-5.5 via Codex CLI). 둘 다 원하면 `/prism-all`.

⚠️ **단일 모델 ensemble의 한계**: 5 agents가 전부 같은 모델이므로 **합의(2+)는 확정이 아니라 우선순위 신호**. 합의만으로 confidence MEDIUM 상한; SUPPORTED 이상은 Evidence pass의 코드 접지(위치+실행경로+인용)가 필요. Evidence 사다리(SUSPECTED/SUPPORTED/REPRODUCED/REJECTED)와 record v2는 prism 가족 공통(`references/record-v2.md`).

## 렌즈 (코드 대상 기본 DEFECT)

| Lens | 역할 |
|---|---|
| 1. **Correctness & Contracts** | 틀린 결과·경계값·에러 경로·불변식·API 계약 위반. "구체 입력 → 틀린 출력" 우선 |
| 2. **Security & Trust Boundaries** | 입력 검증·인가 공백·injection·secret·unsafe default (+공격자 전제조건). 체크리스트가 있으면 `[checklist:#N]`/`[not-in-checklist]` 태그 |
| 3. **State, Concurrency & Recovery** | race/lost update/TOCTOU·비멱등 재시도·고아/고착 상태 (+트리거 시퀀스) |
| 4. **Integration & Regression** | 호출자 계약 파괴·스키마/설정 드리프트·하위호환·숨은 결합. 호출자 컨텍스트가 없으면 추측 대신 명시 |
| 5. **Testability & Observability** | 삼켜진 예외·조용한 폴백·거짓 로그·신호 없는 실패 |

- `--redteam` → 6번째 **Red Team** 렌즈. 프롬프트 `references/redteam-lens.md`. ATTACK CHAINS·CHECKLIST COVERAGE 섹션 추가.
- 대안은 렌즈가 아니라 **아이디어 pass**(Pass 4)에서 나온다.
- **문서·설계·계획 대상은 DESIGN 렌즈셋 자동** (`--lenses=design`으로 강제, `classic`은 별칭): Conflict & Reuse / Claim Accuracy / Devil's Advocate / Robustness 4축. 프롬프트는 `references/design-lenses.md`. prism은 "설계가 맞는가", `/triad`는 "문서로서 잘 쓰였는가" — `/ddaro:review`가 둘 다 돌린다. 헤더에 `Lenses: defect|design (auto|explicit)` 표기.
- **프로젝트 보안 체크리스트**: Pass 1 전에 `docs/security-checklist.md` → `docs/security/checklist.md` → `SECURITY.md` → `docs/SECURITY.md` 첫 파일(≤3 tool call) → **Security·Red Team 렌즈에만** 전달.

## 전제 (Prerequisite)

**Codex CLI ≥ 0.125.0** 필수 (`codex --version`). 부적합 시 중단 + `npm install -g @openai/codex@latest` 안내. Claude로 자동 대체하지 않음(이 skill의 존재 이유가 다른 모델). 모델·폴백: `references/codex-invocation.md` §Operator rules.

Codex는 **read-only 샌드박스**로 돈다(읽기만, 쓰기·네트워크 차단). 샌드박스가 못 읽는 경로(예: Google Drive `H:`)의 파일은 `--target`/`--checklist`로 넘긴다. 샌드박스 없이 돌리기는 사용자가 요청할 때만 `PRISM_CODEX_SANDBOX=bypass`.

## 트리거

| 형태 | 모드 |
|---|---|
| `/prism-codex <target>` | 기본 — 렌즈마다 discovery 1(defect 5, design 4) + Evidence pass(전 후보 접지) + 아이디어 pass(Pass 4) |
| `--quick` | Evidence pass 생략 — 전부 `SUSPECTED`, 아이디어 pass도 생략(`--include-improvements`면 돈다) |
| `--adversarial` | REJECT 확정 전 반대 주장 |
| `--reproduce` | + 재현 pass(SUPPORTED CRIT/HIGH 우선, 최대 5건, prism 공통 규약) |
| `--redteam` | + Red Team 렌즈 |
| `--no-ideas` | 아이디어 pass(Pass 4) 생략 |
| `--include-improvements` | 옛 명령용 별칭: 아이디어 pass를 켠다 — `--quick`이어도 돈다(`<findings>` 없이). `--no-ideas`와 같이 주면 `--no-ideas`가 이긴다 |
| `--lenses=design` | DESIGN 렌즈셋 강제 (markdown 대상은 자동, `classic`은 별칭) |
| `--format json` | record v2를 `prism-report.json`으로도 출력 |
| `--artifacts=temp` (기본) / `docs` | 산출물 위치(`docs`는 .gitignore 필수) |
| 자연어 | "prism codex로", "codex prism", "prism-codex 돌려" |

## Target 해석

파일 경로 → 해당 파일. 주제 → 관련 파일 탐색. 인자 없음 → 현재 프로젝트. **항상 전체를 먼저 읽고** 각 Codex 호출에 그대로 전달(요약 금지).

---

## Pass 1 — Codex 호출 (렌즈당 Bash 1개)

**Codex는 `codex-run.sh`로만 부른다** — 호출 템플릿을 손으로 쓰지 않는다. Sandbox Safety Preamble·tempfile+stdin·180K 가드·300s timeout·effort high·secret scrub·`--output-last-message`·`[fallback: not-started]` 선생성·`parse-findings.js` 추출을 스크립트가 강제한다. 렌즈당 별도 Bash 호출(한 Bash 안에서 5개 순차 금지 — hang 시 뒷 렌즈 유실), Bash tool `timeout` = (`PRISM_CODEX_TIMEOUT`(기본 300) + 30) × 1000 ms, 최대 600000 (그래서 `PRISM_CODEX_TIMEOUT` ≤ 570). Codex CLI는 한 번에 1콜이 안정적이므로 Bash들을 순차로 발사. Wall time ≈ 5 × (15~40s) = **~100~200s**.

```bash
# 런당 1회, 출력된 경로를 이후 호출에 그대로 쓴다. --artifacts docs는 .gitignore에 없으면 거부된다.
bash "<skill dir>/codex-run.sh" init <slug> [--artifacts docs]
# 렌즈당 Bash 1개. heredoc에는 렌즈 정의만 — 출력 계약(PRISM-FINDINGS v1)은 스크립트가 붙인다.
bash "<skill dir>/codex-run.sh" discovery <run-dir> <angle> --target <file> [--target <file>]... [--checklist <file>] <<'EOF'
<렌즈 프롬프트>
EOF
```

`<angle>`: `correctness|security|state|integration|testability|redteam` (design: `conflict|claim-accuracy|devil|robustness`). 스크립트의 조립 순서: Preamble → ① target 전문(모든 렌즈 동일 → 공통 prefix) → ② 체크리스트(`security`·`redteam`만, 다른 angle이면 버린다) → ③ 렌즈 정의 → ④ 출력 계약. stdout = 요약 1줄(`status=ok|degraded(<사유>)|secret-scrubbed findings=N`) + 파서 JSON. 실패한 렌즈도 exit 0 + `degraded:true` — 라운드는 계속된다. exit 2 = 인자·설정·설치 오류 또는 같은 angle이 아직 실행 중(고친 뒤 다시 실행, 다른 모델로 재시도하지 않는다). exit 130 = 중단(마커와 DEGRADED JSON은 남는다). 재시도는 `timeout`·`codex-unavailable`·`no-last-message`만 1회. `codex-output-contained-secret-pattern`·`prompt-modified-during-run`·`scan-failed`는 보안 사건 — 자동 재시도 금지, 사용자에게 알린다(다음 실행 때 이전 마커는 `*.incident.*`로 보존된다). 사유별 처리는 `references/codex-invocation.md` §Fallback policy.

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

후보를 우선순위(AGREEMENT → CRIT/HIGH → 나머지)로 정렬 후 **파일 단위로 ≤8건씩** 청킹(최우선 후보의 파일을 잡고 같은 파일 후보를 묶고 다음 파일로 — 한 청크가 한 파일을 한 번만 읽게). 각 콜에 candidate id를 실어 1:1 대응. 콜 실패/후보 누락 → **그 후보만** `SUSPECTED(missing: EVIDENCE_PASS_FAILED)`, 판정된 후보 재실행 금지, 라운드 fail 금지. Evidence 콜: `bash "<skill dir>/codex-run.sh" evidence <run-dir> evidence-<n> [--target <file>]... <<'EOF'` + 아래 프롬프트·후보·record v2 계약 + `EOF` (preamble·timeout·scrub은 스크립트가 붙이고, 출력 계약은 붙이지 않는다).

> 너는 **Evidence Agent**. 5 리뷰어가 같은 target을 분석해 아래 후보를 냈다. 각 후보를 실제 코드에 접지시키거나, 죽여라. 인용은 반드시 파일을 읽어 실제 존재하는 텍스트로(사후 기계 검증).
> 1. 위치 고정: `file`, `lines`, `symbol`. 불가 → `SUSPECTED` + `missing`.
> 2. 실행 경로: 진입→결함 순서.
> 3. 증거 인용: `file:line — 인용`.
> 4. 전제조건: 불가능하면 반증 인용과 `REJECTED`.
> 5. 판정: `SUPPORTED` / `REJECTED` / `SUSPECTED`(+`REQUIRES_DOMAIN_CONFIRMATION: <질문>`). 위치만 → `evidence_strength: WEAK`.
> 6. severity 조정 가능(한 문장). 새 finding 발명 금지.
> 7. `SUPPORTED`마다 `suggested_test`. 8. 합쳐져 더 큰 결과가 되는 후보는 같은 `chain` id.
> 포맷: 후보당 record v2 1건을 `<<<PRISM-RECORDS v2>>>` ~ `<<<END>>>` 펜스에 한 줄 JSON(스키마 `references/record-v2.md`). `evidence_strength`: NONE/WEAK/MEDIUM.

**기계 검증(불변)**: `node verify-evidence.js <run-dir>/records.json <repo-root> > <run-dir>/checked.json` — 인용 불일치 → `SUSPECTED(EVIDENCE_QUOTE_MISMATCH)` 자동 강등, fingerprint 코드 계산. **checked.json이 최종 진실.**

`--adversarial`: REJECT 전 반대 주장 먼저 — 반박이 더 구체적·근거 우위일 때만 REJECT.

`--reproduce`: prism 공통 규약 — 기계 검증 통과 SUPPORTED, CRIT/HIGH 우선 최대 5건, **stripped env·cwd=임시 디렉토리·프로젝트 트리 쓰기 금지·러너 설치 금지·실패 시그니처 사전 등록·per-test 60s·2회 연속 동일·운영자 confirm 1회·출력 로그에 `codex-run.sh scrub`(exit 3 = 치환됨)**. 분류: REPRODUCED / NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT(setup/import 에러 포함) / TIMED_OUT / STATIC_EVIDENCE_ONLY / REQUIRES_EXTERNAL_SERVICE / REQUIRES_DOMAIN_CONFIRMATION. 자작 통과 테스트는 최대 SUSPECTED까지만 강등.

---

## Pass 4 — 아이디어 (기본 ON; `--quick`·`--no-ideas`면 OFF)

렌즈는 "이게 틀렸나?", 아이디어 pass는 "대신 무엇을 할까?"에 답한다 — 아이디어 렌즈당 최대 3개의 근거 있는 대안을 스크립트가 gate하고, 쓰지 않은 checker가 판정한다. Pass 2/3 뒤에, 코드·설계 대상 모두에서 돈다(`--include-improvements`가 있으면 `--quick`이어도 돈다). 규칙·gate 검사·실패 처리는 `references/ideas.md`(단계가 degraded일 때만 읽는다). **프롬프트를 손으로 쓰지 않는다** — Codex 프롬프트는 `codex-run.sh ideas|idea-check`가 `verify-ideas.js prompt`로 만들고, 계약·판정도 손대지 않는다. 아이디어는 결함 카운트·액션 순서·degraded angle·어떤 게이트에도 들어가지 않는다.

- `<repo-root>` = 검토한 저장소의 루트, Pass 2에서 `verify-evidence.js`가 받은 것과 같은 루트: 대상 파일이 있는 저장소에서 `git rev-parse --show-toplevel`, git이 아니면 대상들의 공통 디렉터리. `<run-dir>`이나 임시 폴더에 있는 대상(수집한 diff 컨텍스트 등)은 루트를 정하는 데 쓰지 않는다 — 그 내용을 뽑아 온 저장소의 루트를 쓴다. 루트가 홈·드라이브 루트·`/`·임시 폴더면 Pass 4를 돌리지 않는다(gate가 그 아래 아무 파일이나 근거로 받는다) — `Ideas: failed (root: <경로>)`. `codex-run.sh ideas`는 매번 `--root <repo-root>`를 받는다(필수).
- `<findings>` = `--findings <run-dir>/checked.json`, **최종** checked.json. `--reproduce`면 Pass 3 이후 record를 `<run-dir>/records.pass3.json`에 쓰고 `node "<skill dir>/verify-evidence.js" <run-dir>/records.pass3.json "<repo-root>" > <run-dir>/checked.pass3.json`을 돌린 다음, exit 0이고 배열이 비어 있지 않을 때만 그 파일을 `<run-dir>/checked.json`으로 옮긴다. 한 명령에서 같은 파일을 입력이자 출력으로 쓰지 않는다(셸이 먼저 비우고, `verify-evidence.js`는 빈 입력에 `[]`를 낸다). 후보 0건(Pass 2 스킵)이거나 `--quick`이면 `<findings>`를 뺀다.
- `<targets>` = 렌즈가 읽은 파일마다 `--target <file>` (discovery와 같은 목록).
- **먼저 초기화**: `<run-dir>`의 이전 Pass 4 결과(`codex.gated.json`, `codex.checked-ideas.json`, `ideas.json`)를 지운다(`--artifacts docs`는 같은 폴더를 다시 쓴다). Codex 답 파일은 `codex-run.sh`가 매 콜 전에 비운다.
- Codex 콜은 Bash 1개씩 순차, Bash `timeout`은 discovery와 같다((`PRISM_CODEX_TIMEOUT`+30)×1000 ms). 재시도는 `degraded(timeout|codex-unavailable|no-last-message)`와 중단(exit 130)만, 같은 인자로 1회. `degraded(prompt-too-large)`는 재시도하지 않는다(대상을 좁히거나 `--no-ideas`). `secret-scrubbed(...)`·`prompt-modified-during-run`·`scan-failed`는 보안 사건 — 재시도 금지, 사용자에게 알린다. degraded 아이디어 콜은 render의 Degraded 줄과 `meta.ideas`, 헤더의 Ideas 줄에만 나온다 — `meta.degraded_angles`·Engine 줄·DEGRADED ANGLES에는 넣지 않는다(discovery의 fallback 표는 렌즈용이다).
- **exit code**: `codex-run.sh ideas|idea-check`가 exit 2면 사용법·인자·설치 오류다(빌더 거부 포함) — 고치고 다시 돌린다(모델 문제가 아니다; 빌더가 거부한 대상은 `<targets>`에서 빼고 Ideas 줄에 적는다). `gate`·`check`·`rank`·`render`도 매 단계 exit 0이어야 다음 단계가 그 출력을 읽는다 — exit 2면 stderr가 말하는 입력을 고쳐 그 단계만 다시 돌린다. 고칠 수 없으면 Pass 4를 멈추고 `Ideas: failed (<단계>: <사유>)`로 보고한다.

```bash
# 1. 제안 (Codex 1콜) → 답: <run-dir>/pass4.codex.ideas.codex.txt
bash "<skill dir>/codex-run.sh" ideas <run-dir> ideas --root <repo-root> <targets> <findings>
# 2. gate
node "<skill dir>/verify-ideas.js" gate <run-dir>/pass4.codex.ideas.codex.txt codex <repo-root> <findings> <targets> > <run-dir>/codex.gated.json
# 3. 검사 — counts.gated가 0이면(근거 없음 또는 degraded: true) 건너뛰고 4로(rank가 gate 출력을 받는다).
#    배치 N = 1..⌈counts.gated/8⌉, 배치당 Bash 1개(새 Codex 콜 = 제안자와 분리된 checker)
bash "<skill dir>/codex-run.sh" idea-check <run-dir> check-codex-N --gated <run-dir>/codex.gated.json <findings> --batch N
node "<skill dir>/verify-ideas.js" check <run-dir>/codex.gated.json <run-dir>/pass4.codex.check-codex-1.codex.txt <repo-root> [--also <run-dir>/pass4.codex.check-codex-N.codex.txt]... <targets> > <run-dir>/codex.checked-ideas.json
# 4. 순위 + 렌더 (엔진 1개라 groups 없음). 3을 건너뛰었으면 codex.checked-ideas.json 대신 codex.gated.json을 넘긴다.
node "<skill dir>/verify-ideas.js" rank <run-dir>/codex.checked-ideas.json > <run-dir>/ideas.json
node "<skill dir>/verify-ideas.js" render <run-dir>/ideas.json
```

---

## Final Report

```
PRISM-CODEX REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce] [+redteam] · Lenses: defect | design {+redteam} ({auto|explicit})
Engine: Codex CLI (gpt-5.5) {n}/{k} · Checklist: {path | none}
Ideas: on (codex){ · degraded: <proposer | checker>} | off (--no-ideas | --quick) | failed (<단계>: <사유>)
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected

## REPRODUCED / ## SUPPORTED / ## SUSPECTED / ## REJECTED
- PRISM-001 [HIGH|security|HIGH] file:lines@symbol — claim
  [3/5 agreement] evidence: file:line — 인용 (verified) | repro: STATIC_EVIDENCE_ONLY | suggested_test: ... | checklist: #14
## ATTACK CHAINS (--redteam 또는 chain 있을 때) / ## CHECKLIST COVERAGE (체크리스트 로드 시)
## DEGRADED ANGLES
## Recommended Action Order
<`node "<skill dir>/verify-ideas.js" render <run-dir>/ideas.json` 출력 그대로 — 첫 줄이 `## IDEAS (...)` 제목이다. 선택지이지 task가 아니다. off면 없고, failed면 `## IDEAS` 아래 실패 한 줄>
```

`{k}` = 돌린 렌즈셋 크기(defect 5, design 4, `--redteam`이면 +1). `[N/{k} agreement]`는 우선순위 신호. 단일 모델이므로 합의만으로 MEDIUM 상한. `--quick`: 전부 SUSPECTED. `--format json`: `${artifacts}/prism-report.json`(기본 `$TMPDIR/prism-codex/<slug>-<run-id>/`) 원자적 출력. `findings`·`meta.counts`는 아이디어 pass와 무관하게 그대로이고, 최상위 `ideas`(= `ideas.json`의 `.ideas`)와 `meta.ideas`(= `ideas.json`의 `.meta` + `"ran": true`)를 더한다. pass를 안 돌렸거나 끝내지 못했으면 `"ideas": []`, `meta.ideas` = `{"ran": false, "reason": "--no-ideas" | "--quick" | "failed: <단계>"}`.

---

## 비용 / 속도

| Mode | Pass 1 | Evidence | Repro | 상대 비용 |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 0 | 1.0× |
| default | 5 | ⌈후보/8⌉ chunked | 0 | 1.2~1.5× |
| `--redteam` | 6 | ⌈후보/8⌉ | 0 | +0.25× |
| `--reproduce` | 5 | ⌈후보/8⌉ | ≤5 | 1.5~2.2× |
| 아이디어 pass (Pass 4, 기본) | +1 Codex proposer 콜 | +⌈아이디어/8⌉ checker 콜 | 0 | 순차 Codex 콜만큼 wall time 증가 |
| `--quick` / `--no-ideas` | — | — | — | 아이디어 pass 0 |

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

완전 독립 plugin. 정본은 prism-all, 사본은 `sync-review-parsers.sh`. 문서의 글 품질은 `/triad`(설계 건전성은 이 skill의 design 렌즈), 반복 수정은 `/mangchi`, 구 `prism-devil`은 `--redteam`.

## 안티패턴

- ❌ Codex 여러 렌즈를 한 Bash 안에서 — 렌즈당 Bash 1개
- ❌ **합의 2+를 Evidence pass 없이 자동 CONFIRM**
- ❌ **위치 없는 SUPPORTED / verify-evidence.js 건너뜀**
- ❌ Evidence pass를 후보당 1콜로 — 파일 단위 ≤8 청킹
- ❌ 재현 테스트를 프로젝트 트리에 / env 안 스트립 / 러너 설치
- ❌ `codex exec`를 직접 호출하거나 자체 실행 스크립트를 만듦 — preamble·scrub·출력 계약이 빠진다. Codex는 `codex-run.sh`로만
- ❌ 문서의 글 품질(명확성·온보딩)을 prism에 기대함 — 그건 `/triad`. design 렌즈는 설계 건전성만 본다
- ❌ 아이디어를 결함처럼 다룸 — IDEAS는 액션 순서·카운트·게이트에 들어가지 않는다
- ❌ 다른 plugin/skill 파일 런타임 참조
