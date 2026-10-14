---
name: prism-all
description: Dual-engine evidence-graded code review. Runs 5 defect lenses on BOTH Claude subagents and Codex CLI in parallel — 10 discovery calls — then an Evidence pass pins every candidate to file/lines/execution-path. Statuses SUSPECTED → SUPPORTED → REPRODUCED; cross-model agreement raises priority and baseline confidence, but only evidence confirms. --redteam adds an attacker-mindset lens on both engines. Design docs get the design lens set (pair with /triad for writing quality). Triggers on "/prism-all <target>", "prism all로", "크로스모델 prism".
argument-hint: "<target> [--quick] [--adversarial] [--reproduce] [--redteam] [--include-improvements] [--lenses=design] [--format json] [--verifier=claude|codex|both] [--artifacts=temp|docs]"
user-invocable: true
---

# prism-all — Dual-Engine Evidence-Graded Review

> 메인은 Claude (오케스트레이터). 매 리뷰 **Claude Agent 5 + Codex CLI 5 = 10 discovery**를 병렬 발사.
> **합의는 우선순위, 확정은 증거.** 어떤 합의도 finding을 확정하지 않는다 — Evidence pass가
> 코드 위치·실행 경로·인용을 붙였을 때(SUPPORTED), 가능하면 실패 테스트로 재현했을 때(REPRODUCED)만.
> 코드/target은 절대 수정하지 않는다 — 리포트만 산출 (재현 테스트는 임시 디렉토리 전용).

이 skill 디렉토리의 파일: `codex-run.sh`(Codex 호출 계약을 코드로 — preamble·stdin·가드·timeout·scrub·파싱),
`parse-findings.js`, `verify-evidence.js`(결정론 스크립트, load-bearing),
`references/codex-invocation.md`(왜 그런 계약인지 — 불변식·fallback 정책·사건 기록, 렌즈가 degraded일 때만 읽는다),
`references/record-v2.md`(finding 스키마 + confidence 표), `references/redteam-lens.md`,
`references/design-lenses.md`(문서용 design 렌즈셋). 참조 파일은 아래 단계가 지시할 때만 읽는다.

## Evidence 사다리

| 상태 | 의미 | 요건 |
|---|---|---|
| `SUSPECTED` | 에이전트 추론만 | claim + 출처 렌즈 |
| `SUPPORTED` | 정적 증거 확보 | file + lines + symbol + execution_path + 코드 인용 |
| `REPRODUCED` | 실패를 실제로 시연 | SUPPORTED + 실행된 실패 테스트/명령 |
| `REJECTED` | 반증됨 | 반증 근거 인용 |

## 핵심 가치

`/prism` = Claude 5 내부 ensemble, `/prism-codex` = Codex 5 ensemble, **`/prism-all` = 10 cross-model ensemble**:

- **같은 렌즈 + 두 엔진 = cross-model agreement** — 상관된 오해 가능성 최소 → 가장 높은 초기 신뢰 후보
- **같은 엔진 + 다른 렌즈 2+ = intra-model agreement** — 같은 모델은 같은 오해를 반복 → 증거 없인 MEDIUM 상한
- **한 엔진 한 렌즈 singleton** — 가장 낮은 초기 신뢰

어느 티어든 **Evidence pass를 통과해야 SUPPORTED**.

## 렌즈 × 2 엔진

코드 대상은 **DEFECT 렌즈셋**: Correctness & Contracts / Security & Trust Boundaries /
State, Concurrency & Recovery / Integration & Regression / Testability & Observability — 양 엔진 각 1.

- `--redteam` → 6번째 **Red Team** 렌즈(양 엔진). 프롬프트는 `references/redteam-lens.md`. 공격 체인·체크리스트 커버리지 섹션 추가.
- `--include-improvements` → **Improvement** 렌즈 추가(양 엔진), `category: improvement`로 분리 집계.
- **문서·설계·계획 대상은 DESIGN 렌즈셋 자동** (`--lenses=design`으로 강제, `classic`은 별칭): Conflict & Reuse / Claim Accuracy / Devil's Advocate / Robustness 4축 / Improvement. 프롬프트는 `references/design-lenses.md`. prism은 "설계가 맞는가", `/triad`는 "문서로서 잘 쓰였는가" — `/ddaro:review`가 둘 다 돌린다. 헤더에 `Lenses: defect|design (auto|explicit)` 표기.
- **프로젝트 보안 체크리스트**: Pass 1 전에 `docs/security-checklist.md` → `docs/security/checklist.md` → `SECURITY.md` → `docs/SECURITY.md` 순으로 첫 파일을 읽어(≤3 tool call) **Security·Red Team 렌즈에만** 전달.

## 전제 (Prerequisite)

1. **Claude Code** (메인 + Agent) — ambient
2. **Codex CLI ≥ 0.125.0** — `codex --version`, 부적합 시 `npm install -g @openai/codex@latest`

**Codex 없음** → `/prism` 전환 제시. 반만 돌지 않는다 (skill 이름에 반함). 모델 선택·폴백은 `references/codex-invocation.md` §Operator rules.

## 트리거

| 형태 | 모드 |
|---|---|
| `/prism-all <target>` | 기본 — 10 discovery + Evidence pass |
| `--quick` | Evidence pass 생략 — 전부 `SUSPECTED` |
| `--adversarial` | Evidence pass가 REJECT 확정 전 반대 주장 의무 |
| `--reproduce` | + 재현 pass (SUPPORTED CRIT/HIGH 우선, 최대 5건, 임시 디렉토리) |
| `--redteam` | + Red Team 렌즈 양 엔진 (12 discovery) |
| `--include-improvements` | Improvement 렌즈 추가(분리 집계) |
| `--lenses=design` | DESIGN 렌즈셋 강제 (markdown 대상은 자동, `classic`은 별칭) |
| `--format json` | finding record v2를 `prism-report.json`으로도 출력 |
| `--verifier=claude` (기본) / `codex` / `both` | Evidence pass 엔진. `both`: 둘 다 SUPPORTED일 때만 SUPPORTED, 엇갈림 = SUSPECTED + 양쪽 근거 병기 |
| `--artifacts=temp` (기본) / `docs` | 산출물 위치. `docs`는 `docs/prism-all/<slug>`, .gitignore 필수 |
| 자연어 | "prism all로", "크로스모델 prism" |

---

## Pass 1 — 10 병렬 발사

**한 메시지 안에서 전부 병렬**:
- Claude 5(+1): `Agent` tool × 렌즈 수, forked context.
- Codex 5(+1): **렌즈당 별도 `Bash` 호출로 `codex-run.sh`를 실행** (한 Bash에 순차 금지 — 외부 타임아웃·hang 시 뒷 렌즈가 파일 없이 유실). Bash tool `timeout`은 330000 이상. 호출 템플릿을 손으로 쓰지 않는다 — Sandbox Safety Preamble·tempfile+stdin·180K 가드·300s timeout·effort high·secret scrub·`--output-last-message`·`[fallback: not-started]` 선생성·`parse-findings.js` 추출을 스크립트가 강제한다.

```bash
# 런당 1회, 출력된 경로를 이후 호출에 그대로 쓴다. --artifacts docs는 .gitignore에 없으면 거부된다.
bash "<skill dir>/codex-run.sh" init <slug> [--artifacts docs]
# 렌즈당 Bash 1개. heredoc에는 렌즈 정의만 — 출력 계약(PRISM-FINDINGS v1)은 스크립트가 붙인다.
bash "<skill dir>/codex-run.sh" discovery <run-dir> <angle> --target <file> [--target <file>]... [--checklist <file>] <<'EOF'
<렌즈 프롬프트>
EOF
```

`<angle>`: `correctness|security|state|integration|testability|redteam|improvement` (design: `conflict|claim-accuracy|devil|robustness|improvement`). 체크리스트는 `security`·`redteam`에만 들어간다(다른 angle이면 스크립트가 버린다). stdout = 요약 1줄(`status=ok|degraded(<사유>)|secret-scrubbed findings=N`) + 파서 JSON. 실패한 렌즈도 exit 0 + `degraded:true` — 라운드는 계속된다. exit 2는 인자 오류뿐. 사유별 처리는 `references/codex-invocation.md` §Fallback policy.

Wall time ≈ max(Claude 5 parallel ≈ 20~40s, Codex 5 ≈ 100~200s) = Codex 병목.

**프롬프트 조립 순서(양 엔진 동일)**: ① target 전문(요약 금지; 모든 렌즈에 동일 → 공통 prefix로 prompt-cache 친화) ② 렌즈별 컨텍스트(Security/Red Team만 체크리스트) ③ 렌즈 정의 + 출력 계약(마지막). Codex는 그 앞에 Sandbox Safety Preamble이 먼저 온다.

DEFECT 렌즈 프롬프트:

1. **Correctness & Contracts** — 틀린 결과/경계값/에러 경로/불변식/API 계약 위반. "구체 입력 → 틀린 출력"이 추상적 우려보다 우선.
2. **Security & Trust Boundaries** — 입력 검증/인가 공백/injection/secret 노출/unsafe default. 각 finding에 공격자 전제조건 명시. 체크리스트가 주어지면 `[checklist:#N]` 또는 `[not-in-checklist]` 태그.
3. **State, Concurrency & Recovery** — 동시 호출·중간 크래시·재시도. race/lost update/TOCTOU/비멱등 재시도/고아·고착 상태. 트리거 시퀀스 명시.
4. **Integration & Regression** — 호출자 계약 파괴/스키마·설정 드리프트/하위호환/숨은 결합. 영향받는 호출자 명명. 호출자 컨텍스트가 없으면 추측 대신 그 사실을 말한다.
5. **Testability & Observability** — 삼켜진 예외/조용한 폴백/거짓 로그/테스트 불가 seam/신호 없는 실패 모드.
6. **Red Team** (`--redteam`) — `references/redteam-lens.md` 전문.
   **Improvement** (`--include-improvements`) — 현재 → 개선안 → 근거.

공통 계약: **"너는 의심(suspicion)을 생산한다 — 확정은 Evidence pass의 일. LOCUS는 `file:lines@symbol`로 정밀하게, `|` 금지."**

### 출력 포맷 v1 (양 엔진 공통)

자유 추론 뒤 **메시지 마지막 펜스**로 emit. synthesis는 이 레코드만 파싱한다.

```
<<<PRISM-FINDINGS v1>>>
CRIT | <locus> | <problem> -> <fix>
HIGH | <locus> | <problem> -> <fix>
<<<END>>>
```

한 줄 = 한 finding, SEV ∈ `CRIT|HIGH|MED|LOW`. 펜스 밖 텍스트는 무시. finding 없으면 빈 블록. 버전 태그 v1 고정(변경 시 v2 + 파서 양쪽 지원).

---

## Synthesis Triage — 후보 분류 (확정 아님)

`node parse-findings.js "$OUT" "$LENS" > "$OUT.json"`로 양 엔진 출력을 코드로 추출(눈대중 금지; 파서 헤더가 정본). 파싱된 record를 `{engine, lens, degraded, raw_locus, raw_text}` 봉투로 감싸 semantic dedup.

- **Tier 1 — Cross-model agreement**: 같은 렌즈에서 Claude + Codex 둘 다 flag. `[cross-model/<lens>]`, severity = 높은 쪽. Evidence pass 최우선.
- **Tier 2 — Intra-model multi-lens**: 한 엔진의 2+ 렌즈. `[claude/multi]`·`[codex/multi]`. 증거 없이는 MEDIUM 상한.
- **Tier 3 — Singleton**: `[claude/<lens>]`·`[codex/<lens>]`.
- **Conflicts**: 두 엔진이 반대 조언 → "Conflicting" 섹션에 양쪽 표시, Evidence pass가 인용 근거로만 선택.
- **`degraded:true` 마커는 후보가 아니다** → `meta.degraded_angles`, "DEGRADED ANGLES" 섹션. candidate_count·fingerprint 제외.
- `--quick` → 전부 `SUSPECTED`(Tier 레이블 유지), 후보 0건 → Pass 2 스킵.

---

## Pass 2 — Evidence pass (전 후보 청킹 접지 + 기계 검증)

**Evidence Agent**(기본 Claude; `--verifier`로 변경). Read/Grep/Glob으로 실제 파일을 읽어 인용한다.

**청킹 규약**: 후보를 우선순위(Tier 1 → CRIT/HIGH → 나머지)로 정렬한 뒤 **파일 단위로** 청크를 만든다 — 최우선 후보의 파일을 잡고 같은 파일의 미배정 후보를 최대 8건까지 묶고, 다음 파일로. 한 청크에서 한 파일을 한 번만 읽게 된다. 콜 실패/후보 누락 → **그 후보만** `SUSPECTED(missing: EVIDENCE_PASS_FAILED)`, 판정된 후보 재실행 금지, 라운드 fail 금지.

Evidence Agent 프롬프트:

> 너는 Evidence Agent. 리뷰어들이 낸 아래 후보들을 **실제 코드에 접지시키거나, 죽여라.** 리뷰어 말은 믿지 않는다 — 인용은 반드시 파일을 Read 해서 가져온다(사후 기계 검증, 지어내면 강등). 후보마다:
> 1. **위치 고정**: `file`, `lines`, `symbol`. 불가 → `SUSPECTED` + `missing`.
> 2. **실행 경로 추적**: 진입→결함 순서.
> 3. **증거 인용**: `file:line — 실제 줄 텍스트`.
> 4. **전제조건 점검**: 불가능하면 반증 인용과 함께 `REJECTED`.
> 5. **판정**: `SUPPORTED`(1~3 전부) / `REJECTED` / `SUSPECTED`(고정 불가 또는 `REQUIRES_DOMAIN_CONFIRMATION: <질문>`). 위치만 = `SUSPECTED` + `evidence_strength: WEAK`.
> 6. severity 조정 가능(한 문장). 새 finding 발명 금지.
> 7. `SUPPORTED`마다 `suggested_test`.
> 8. 둘 이상이 합쳐져 더 큰 결과가 되면 같은 `chain` id.
> 9. 후보마다 finding record v2 1건, `<<<PRISM-RECORDS v2>>>` ~ `<<<END>>>` 펜스 안에 한 줄 JSON. 스키마는 `references/record-v2.md`. `evidence_strength`: NONE/WEAK/MEDIUM (STRONG은 Pass 3만).
>
> `--verifier=codex|both`의 Codex 콜: `bash "<skill dir>/codex-run.sh" evidence <run-dir> evidence-<n> [--target <file>]... <<'EOF'` + 위 프롬프트·후보·record v2 계약 + `EOF` (preamble·timeout·scrub은 스크립트가 붙인다).
> `--verifier=both`: Claude·Codex 각 1콜. 둘 다 SUPPORTED → SUPPORTED. 한쪽 실패 → 생존 엔진 단독(헤더 플래그). SUPPORTED×REJECTED → SUSPECTED + 양쪽 근거 Conflicting에 병기. 둘 다 REJECTED → REJECTED.
> `--adversarial`: REJECT 확정 전 리뷰어 편에서 반박 — 반박이 더 구체적·근거 우위일 때만 REJECT.

**기계 검증(불변)**: v2 record를 JSON으로 파싱 후 반드시
```
node "<skill dir>/verify-evidence.js" records.json "<repo-root>" > checked.json
```
— `SUPPORTED/REPRODUCED` 인용을 실제 파일에서 grep, 없으면 `SUSPECTED(EVIDENCE_QUOTE_MISMATCH)` 강등, fingerprint 코드 계산. **checked.json이 최종 진실.** (`--selftest`로 자가 검증.)

---

## Pass 3 — 재현 (`--reproduce`)

프로젝트는 **절대 수정하지 않는다**. Actor: main agent(또는 Bash 권한 Reproduction Agent) — Evidence Agent는 코드를 실행하지 않는다. 대상: 기계 검증 통과 `SUPPORTED`만, CRIT/HIGH 우선, **런당 최대 5건**(초과분 `STATIC_EVIDENCE_ONLY`).

**실행 안전(불변 — "임시 디렉토리"는 쓰기 가드일 뿐 실행 샌드박스가 아니다)**: target import는 모듈 레벨 부작용을 운영자 env로 실행한다. 재현 명령은 반드시 ① `env -i` + allowlist(PATH·언어 런타임·필요시 HOME) ② cwd = 임시 디렉토리 ③ 네트워크 차단(가능 시) ④ **설치 금지**(PATH의 러너만) ⑤ 첫 실행 전 운영자 confirm 1회 ⑥ 출력 로그에 `bash "<skill dir>/codex-run.sh" scrub <로그 파일>...` 적용(exit 3 = 치환됨 → scrub 이벤트).

절차: ① 기존 테스트 먼저 검색(격리 실행 + baseline 비교) ② PATH의 러너 감지(pytest/vitest/jest/node --test/go test/cargo test — 없으면 `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`) ③ `${TMPDIR:-${TEMP:-/tmp}}/prism-tests/`(`mktemp -d`)에 최소 실패 테스트 작성 ④ **예상 실패 시그니처를 record에 먼저 등록** ⑤ per-test 60s(총 5min), exit code·duration·tail 원문 기록, **2회 연속 동일**해야 인정.

분류: `REPRODUCED`(시그니처 일치 2회) / `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`(러너 없음 **또는 setup/import/fixture 에러** — 아무 red나 재현으로 세지 않음) / `TIMED_OUT`(상향 금지, 별도 기록) / `STATIC_EVIDENCE_ONLY` / `REQUIRES_EXTERNAL_SERVICE` / `REQUIRES_DOMAIN_CONFIRMATION`. **자작 테스트 통과** → 같은 전제·경로를 exercise한 경우에만 최대 `SUSPECTED`까지 강등, 아니면 `SUPPORTED` + `NOT_REPRODUCED_BY_ATTEMPT`. 종료 시 임시 디렉토리 정리(scrub 이벤트 시 보존), 테스트 소스는 리포트+JSON에 보존.

---

## Final Report

```
PRISM-ALL REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce] [+redteam] · Lenses: defect | design {+redteam} {+improvements} ({auto|explicit})
Engines: Claude {n}/5 + Codex {n}/5{ (degraded: <lenses>)} · Evidence: {claude | codex | both} · Checklist: {path | none}
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected  (infra-degraded: D)

## REPRODUCED (실패 시연됨)
- PRISM-003 [HIGH|security|VERY-HIGH] file:lines@symbol — claim
  [cross-model/security] path: ... | repro: <command> → FAILED (signature match) | fix: ...
## SUPPORTED (코드 경로 증거, 미실행 — 인용 기계검증됨)
- PRISM-001 [...|HIGH+] file:lines@symbol — claim
  [cross-model/state] evidence: file:line — 인용 (verified) | repro: STATIC_EVIDENCE_ONLY | suggested_test: ... | checklist: #14
## SUSPECTED (추론만 — 확인 필요)
## REJECTED (투명성 — 반증 인용)
## ATTACK CHAINS (--redteam 또는 Evidence pass가 chain을 묶었을 때)
## CHECKLIST COVERAGE (체크리스트 로드 시)
## DEGRADED ANGLES (인프라 — finding 아님)
## IMPROVEMENTS (--include-improvements 시만)
## Engine-Unique Findings (참고) / ## Conflicting Advice (있으면)
## Recommended Action Order
REPRODUCED → SUPPORTED severity 순(chain 먼저). SUSPECTED는 task가 아니라 질문으로.
```

**리포트는 실제로 돈 것만 주장한다** — 헤더의 `Codex {n}/5`·DEGRADED ANGLES는 파서의 `degraded` 플래그에서 생성. cross-model 라벨은 실제 양쪽이 응답한 렌즈에만. record 스키마·confidence 표: `references/record-v2.md`.

`--format json`: `${artifacts}/prism-report.json`(기본 `$TMPDIR/prism-all/<slug>-<run-id>/`, `--artifacts=docs` 시 repo — .gitignore 필수)에 원자적 출력(temp write → validate → rename). 실패 시 인라인 + `json_output: failed`. fingerprint로 런 간 link만 — 이전 REJECTED를 suppress하지 않는다.

---

## 비용 / 속도

| Mode | Claude 콜 | Codex 콜 | Evidence | Repro | wall time | 상대 비용 |
|---|---|---|---|---|---|---|
| `--quick` | 5 | 5 | 0 | 0 | ~100~200s | 2.0× prism |
| default | 5 | 5 | ⌈후보/8⌉ chunked | 0 | ~120~240s | 2.2~2.5× |
| `--redteam` | 6 | 6 | ⌈후보/8⌉ | 0 | ~140~260s | +0.4× |
| `--verifier=both` | 5 | 5 | ⌈후보/8⌉×2 | 0 | ~140~280s | 2.4~2.8× |
| `--reproduce` | 5 | 5 | ⌈후보/8⌉ | ≤5 | ~180~340s | 2.6~3.2× |

토큰이 가는 곳과 줄이는 법: target이 discovery 수만큼 전송된다(10~12회) — 파일 전체보다 변경 범위를 좁혀 넘기고, 큰 파일은 `/prism --diff`를 먼저 고려. 프롬프트는 target 먼저·렌즈 나중(공통 prefix 캐시). Evidence는 파일 단위 청킹. 파싱·인용 검증은 스크립트(토큰 0).

## 자립성 검증

```bash
node verify-independence.js --strict   # 필수 파일 + 스크립트 selftest(codex-run.sh 포함) + Codex CLI >= 0.125.0
```

## 자매 skill

| Skill | Engine | 언제 |
|---|---|---|
| `/prism` | Claude 5 + Claude Evidence | 빠른 1-엔진, `--diff` 지원 |
| `/prism-codex` | Codex 5 + Codex Evidence | 다른 모델 ensemble / Claude 토큰 절약 |
| `/prism-all` (이 skill) | Claude 5 + Codex 5 + Evidence | 최고 신뢰 |

셋 다 독립 — 런타임에 다른 plugin 파일을 참조하지 않는다. 결정론 스크립트와 `references/*.md`의 정본은 prism-all, 사본은 `skills/sync-review-parsers.sh`로 생성·검증. 문서의 글 품질은 `/triad`(설계 건전성은 이 skill의 design 렌즈), 반복 수정은 `/mangchi`, 구 `prism-devil`은 `--redteam`으로 흡수.

## 안티패턴

- ❌ Claude 5 + Codex 5를 순차로 — 한 메시지 안 병렬
- ❌ Codex 여러 렌즈를 한 Bash 안에서 순차 — 렌즈당 Bash 1개
- ❌ **합의만으로 확정** — Evidence pass 없이 SUPPORTED 금지
- ❌ **위치 없는 SUPPORTED** / 기계 검증 건너뜀
- ❌ 재현 테스트를 프로젝트 트리에 / env 스트립 없이 / 러너 설치
- ❌ 재현 실패(테스트 통과)를 조용히 버림 — 강등 + 통과 로그 인용
- ❌ Cross-model agreement를 singleton 급으로 격하
- ❌ 한 엔진 실패 시 조용히 다른 쪽만으로 — fallback 태그 + 헤더 명시
- ❌ `codex exec`를 직접 호출하거나 자체 실행 스크립트를 만듦 — preamble·scrub·출력 계약이 빠진다. Codex는 `codex-run.sh`로만
- ❌ `.env`·`*secret*`이 있는 작업 디렉토리에서 실행
- ❌ 문서의 글 품질(명확성·온보딩)을 prism에 기대함 — 그건 `/triad`. design 렌즈는 설계 건전성만 본다
- ❌ 다른 plugin/skill 파일 런타임 참조
