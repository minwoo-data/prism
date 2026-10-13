# prism

> Language: [English](README.md) · **한국어**

**5개 결함 렌즈가 병렬로 찾고 — 모든 finding은 코드에 접지(위치·실행경로·인용)돼야 "진짜"로 인정된다.**

"AI 리뷰어 여러 명이 동의했다"는 증거가 아니다 — prism의 5 agents는 전부 같은 모델이라 같은 오해를 공유할 수 있다. 그래서 v0.2부터 **합의는 조사 우선순위를 정하고, 확정은 증거가 한다.** 모든 후보가 Evidence pass를 거쳐 `file:lines@symbol` 고정 + 실행 경로 추적 + 근거 줄 인용을 받아야 하고, `--reproduce`면 임시 디렉토리의 일회용 테스트로 실패를 직접 시연한다.

```
/prism <target>                        -> discovery (5 렌즈) + Evidence pass
/prism <target> --reproduce            -> + 최소 실패 테스트 (임시 디렉토리 — 프로젝트는 불변)
/prism --diff main...HEAD              -> 변경 리뷰: 이 diff가 새로 만드는 회귀는?
/prism <target> --quick                -> discovery만 (전부 SUSPECTED로 보고)
/prism <target> --adversarial          -> Evidence pass가 자기 REJECT에 반박 후 확정
/prism <target> --redteam              -> + 공격자 관점 Red Team 렌즈 (구 prism-devil 흡수)
/prism <target> --include-improvements -> Improvement 렌즈 추가 (분리 집계)
/prism <target> --format json          -> 기계가독 prism-report.json (finding record v2)
```

모든 finding의 상태: `SUSPECTED`(추론만) → `SUPPORTED`(위치+경로+인용) → `REPRODUCED`(실패 테스트 실행됨) / `REJECTED`(반증 인용). Target은 코드 파일/디렉토리/주제 — 문서는 `/triad`로.

---

## 30초 데모

**prism 없이:**

Claude에게 "이 파일 리뷰해줘" 하면 "괜찮아 보인다" 답이 오고 merge. 2주 뒤, 다른 각도(예: 동시성 또는 config 충돌)에서 보면 금방 잡혔을 버그가 터진다. 그 각도를 독립 리뷰어에게 체크할 생각을 아무도 못 했던 것.

**prism으로:**

`/prism src/services/auth.py --reproduce`. 5 결함 렌즈(correctness / security / state&concurrency / integration / testability)가 병렬로 파일을 보고, 모든 후보가 접지 검증(정확한 위치·실행 경로·인용)을 거친 뒤, 상위 finding은 임시 디렉토리에서 최소 실패 테스트로 실제 시연된다. 리포트는 *시연된 것* / *정적 증거만 있는 것* / *추론뿐인 것* / *반증과 함께 기각된 것*을 구분해 준다. (v0.1의 "2명 합의 = 자동 CONFIRMED" 규칙은 폐기 — 같은 모델의 합의는 상관된 오해일 수 있다.)

## 누가 써야 하는가

- **큰 아키텍처 결정 직전** — 1관점이 아니라 5관점이 필요할 때
- **확신 안 서는 PR merge 직전** — 본인 LLM의 의견 너머 독립 검토가 필요할 때
- **기능 구현 후** — 릴리스 전 맹점 최종 sweep
- **skill / 디자인 문서 / 워크플로우 감사** — 리뷰어 간 의견 불일치 자체가 신호
- "5명한테 같은 코드 보여주고 싶다"는 욕구를 자동화하고 싶을 때

## 어떤 도구를 쓰지? (haroom 패밀리)

| 목적 | 도구 |
|---|---|
| 넓게 결함 찾기 (증거 등급) | **prism** (이 플러그인) |
| Claude + Codex 교차 검토 | `/prism-all` (이 플러그인에 포함) |
| 보안·공격자 관점 심층 프로브 | `/prism <target> --redteam` (prism-devil은 0.3.0에서 흡수) |
| 실제 코드 수정 반복 | [mangchi](https://github.com/minwoo-data/mangchi) |
| 문서·설계 검토 | [triad](https://github.com/minwoo-data/triad) — prism은 문서를 거부한다 |
| worktree 병렬 세션 + 안전한 merge | [ddaro](https://github.com/minwoo-data/ddaro) |

---

## Quick Start

### 1. haroom_plugins 마켓플레이스 등록 (처음 한 번)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git
```

`prism` 은 haroom 플러그인 (ddaro, triad, mangchi) 과 함께 **haroom_plugins** aggregator 를 통해 배포됩니다.

### 2. 설치

```
/plugin install prism
```

### 3. 사용

```
/prism src/services/auth.py                 # 기본: 5 렌즈 + Evidence pass
/prism src/services/auth.py --quick         # 1 pass만, verify skip
/prism src/services/auth.py --adversarial   # 1 pass + REJECT 재검증
/prism .                                    # 프로젝트 전체 리뷰
```

설치/업데이트 후 Claude Code **재시작**.

---

## 이 플러그인이 제공하는 3 variant

`prism` 플러그인을 설치하면 같은 5-렌즈 프레임워크를 공유하되 **판단 주체가 다른** 3 skill이 함께 들어옵니다:

| Skill | 엔진 | 언제 쓰나 |
|---|---|---|
| `/prism` | **Claude** — 5 렌즈 병렬 + Evidence pass | 기본. Wall-time 가장 빠름, 외부 CLI 불필요, `--diff`는 여기만. |
| `/prism-codex` | **Codex CLI** — 5 호출 + Codex Evidence pass, gpt-5.5 | Claude 토큰 절약 / 다른 모델 관점. `codex-cli >= 0.125.0` 필요. |
| `/prism-all` | **Claude + Codex 병렬** — 10 discovery + Evidence pass | 최고 신뢰. 같은 렌즈에서 두 엔진이 모두 flag한 이슈는 Tier 1. `--verifier=claude\|codex\|both`로 판정자 선택. |

세 variant 전부 한 번의 플러그인 설치에 포함. Codex CLI 전제 상세: 자매 플러그인의 [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md) ("model does not exist" 에러는 계정 문제가 아니라 CLI 버전 문제).

---

## 5 결함 렌즈 (기본)

| 렌즈 | 찾는 것 |
|---|---|
| **Correctness & Contracts** | 틀린 결과, 경계값, 에러 경로, 불변식·API 계약 위반 |
| **Security & Trust Boundaries** | 검증 누락, 인가 공백, injection, secret 노출 — 공격자 전제조건 포함. 프로젝트 보안 체크리스트가 있으면 자동 로드해 항목별로 매핑 |
| **State, Concurrency & Recovery** | race, lost update, TOCTOU, 비멱등 재시도, 고아/고착 상태 |
| **Integration & Regression** | 호출자 계약 파괴, 스키마/설정 드리프트, 하위호환, 숨은 결합 |
| **Testability & Observability** | 삼켜진 예외, 조용한 폴백, 거짓 로그, 신호 없는 실패 |

선택 렌즈: **Red Team** (`--redteam`) — 구 `prism-devil`에서 흡수한 공격자 마인드 심층 프로브. 10개 공격 표면을 우선순위대로 훑고, 체크리스트 항목에 교차 참조하고, 둘 이상이 합쳐지는 공격 체인을 이름 붙인다. 다른 렌즈와 똑같이 Evidence pass를 거친다. **Improvement** (`--include-improvements`) — 결함 리포트를 시끄럽게 하지 않도록 기본에서 제외.

**prism은 코드 전용**이다. 문서·설계·계획을 넘기면 `/triad`로 안내하고 멈춘다. 구 0.1 렌즈셋(`--lenses=classic`)은 deprecated — 0.4에서 제거.

각 렌즈는 **forked context**에서 실행 — 서로의 응답을 볼 수 없다. 프롬프트는 **target 먼저, 렌즈 정의 나중** 순으로 조립해 공통 prefix가 prompt cache를 타게 한다.

## 증거 등급 동작 방식

discovery 후 모든 finding은 **후보**다 — 자동 확정은 없다:

- **합의(2+ 렌즈)**는 우선순위와 초기 신뢰만 정한다. 같은 모델의 합의는 MEDIUM 상한 — 같은 모델 5개는 같은 오해를 공유할 수 있다.
- **모든 후보**가 **Evidence pass**를 거친다 (≤8건씩, 파일 단위로 청킹): `file/lines/symbol` 고정, 실행 경로 추적, 근거 줄 인용, 전제조건 점검. 그 후에만 `SUPPORTED` / `REJECTED`(반증 인용) / 여전히 `SUSPECTED`(무엇이 빠졌는지 명시).
- 인용은 `verify-evidence.js`가 실제 파일에서 grep으로 **기계 검증**한다 — 지어낸 인용은 자동 강등.
- **`--reproduce`**는 SUPPORTED(CRIT/HIGH 우선, 최대 5건)에 대해 OS 임시 디렉토리에 최소 실패 테스트를 작성·실행하고 결과를 그대로 기록한다. 프로젝트 트리는 절대 건드리지 않는다. 통과하는 테스트는 finding을 강등시킨다 — 반증도 숨기지 않고 기록.

모든 finding은 구조화된 **record v2**로 나간다 (`id`, `fingerprint`, `file/lines/symbol`, `category`, `severity`, `status`, `claim`, `preconditions`, `execution_path`, `evidence`, `reproduction`, `confidence`, 체크리스트/체인 참조). 스키마: `skills/prism/references/record-v2.md`.

## Features

- **병렬 discovery** — 5 렌즈를 한 tool call로 발사. wall-time ≈ 가장 느린 하나.
- **합의보다 증거** — 확정은 위치 + 실행 경로 + 인용, 표 수가 아님.
- **재현 샌드박스** — 실패 테스트로 버그를 시연하되 프로젝트는 불변. "안 돌렸다"는 항상 명시(`STATIC_EVIDENCE_ONLY` 등).
- **변경 범위 모드** — `--diff`는 코드베이스가 좋은지가 아니라 이 변경이 무엇을 깨는지 본다. PR 리뷰는 이걸로.
- **파일 단위 청킹 Evidence pass** — 한 청크가 한 파일을 한 번만 읽는다. 청크 하나가 실패해도 그 후보들만 강등.
- **Adversarial 모드** — Evidence pass가 자기 REJECT에 반박한 뒤 확정.
- **Red Team 렌즈** — `--redteam`으로 공격자 관점 6번째 에이전트 추가. 보안 체크리스트 커버리지와 공격 체인 섹션이 리포트에 생긴다.
- **코드 수정 없음** — prism은 순수 reviewer. 실제 수정은 `/mangchi`.

---

## 모드와 출력

```
/prism src/services/auth.py                 # 기본: discovery + Evidence pass
/prism src/services/auth.py --quick         # discovery만 (전부 SUSPECTED)
/prism src/services/auth.py --adversarial   # Evidence pass가 자기 REJECT에 반박
/prism src/services/auth.py --redteam       # + 공격자 렌즈, 체크리스트, 공격 체인
/prism --diff main...HEAD                   # 변경 범위 리뷰 (PR에 권장)
/prism .                                    # 프로젝트 전체
```

자연어: *"prism 돌려"*, *"full review"*, *"red team 해줘"*.

리포트 형식:

```
PRISM REPORT - src/auth.py - 2026-10-13 15:30
Mode: default +reproduce · Lenses: defect · Checklist: none
Candidates: 9 discovered → 4 supported, 1 reproduced, 2 rejected, 2 suspected

## REPRODUCED (실패 시연됨)
- PRISM-003 [HIGH|security] src/auth.py:84-102 reset_password — 재설정 토큰 재사용 가능
  path: reset_password → token lookup → password update → token not invalidated
  repro: pytest /tmp/prism-tests/test_reset_reuse.py → FAILED as predicted

## SUPPORTED (코드 경로 증거, 미실행 — 인용 기계검증됨)
- PRISM-001 [MED|state] src/auth.py:120-133 rate_limit — check-then-insert race로 초과 허용
  evidence: src/auth.py:127 — count read before insert, no lock | repro: STATIC_EVIDENCE_ONLY

## SUSPECTED (확인 필요)
- PRISM-007 — missing: REQUIRES_DOMAIN_CONFIRMATION: 5분 내 토큰 재사용이 허용되는 설계인가?

## REJECTED (투명성)
- [security lens] "JWT alg confusion" — 반증: src/auth.py:41 — alg pinned to HS256

## Recommended Action Order
1. PRISM-003 (reproduced) ...
```

## 비용

| 모드 | 비용 | 언제 |
|---|---|---|
| `--quick` | 1.0× | 이미 triage된 target |
| 기본 | 1.3–1.5× | 일반 리뷰 |
| `--redteam` | +0.25× | auth / 결제 / PII / 외부 입력 파서 |
| `--reproduce` | 1.6–2.2× | merge 전 중요한 변경 |

Evidence pass 비용은 ⌈후보/8⌉ 콜(파일 단위 청킹). 토큰이 가는 곳과 줄이는 법: target이 discovery 에이전트 수만큼 전송된다(PR은 `--diff`); prism은 forked context로 실행되므로 긴 세션 끝에서 부르면 그 세션이 한 번 복제된다(초반이나 새 세션에서 실행); 파싱·인용 검증은 스크립트라 모델 토큰 0.

---

## 사용 예시

```
/prism src/services/auth.py
# → 5 렌즈 병렬 (~20~40s, 파일 크기 의존)
# → Triage: 후보 8건. 2+ 렌즈 합의 3(우선), singleton 5.
# → Evidence pass (파일 단위 1청크): SUPPORTED 4, REJECTED 2, SUSPECTED 2
# → verify-evidence.js: SUPPORTED 인용 전부 실제 줄과 일치
# → 최종: supported 4 + suspected 2(질문으로) + rejected 2(투명성)

# 보안 리뷰는 더 엄격하게:
/prism src/security/ --adversarial
# → 같은 Pass 1. Evidence pass가 REJECT 전에 반대 주장 시도.
# → "기각하려 했는데 사실 이건 맞을 수도..." 케이스 포착.

# 프로젝트 전체 sanity check:
/prism .
```

### mangchi와 페어: 반복 하드닝

```
/prism src/services/auth.py     # 약한 파일 식별
/mangchi src/services/auth.py   # 해당 파일을 반복적으로 단단하게
```

### Cross-model variant

```
/prism-all src/services/auth.py
# → Claude 5 + Codex CLI 5, 전부 병렬 (~100~200s)
# → Tier 1: 두 엔진이 같은 각도에서 flag → 최고 신뢰
# → Tier 2: 한 엔진의 여러 각도
# → Tier 3: singleton — 세 티어 모두 Evidence pass를 거친다
# → codex-cli >= 0.125.0 필요
```

---

## 업데이트

```
/plugin update
```

설치 후 Claude Code 재시작.

---

## 트러블슈팅

### 설치 후 `/prism`이 안 보임

플러그인은 Claude Code 시작 시점에 로드됩니다.

1. **Claude Code 재시작** — 설치/업데이트 때마다 필수.
2. `/plugin` 실행, `prism`이 **enabled** 상태인지 확인.
3. disabled면: `/plugin enable prism@haroom_plugins`.
4. 여전히 안 보임? `~/.claude.json`의 `enabledPlugins`에 `prism` 항목 확인. `{}`면 재설치.

### `/prism-codex` 또는 `/prism-all`이 "model does not exist" 에러

**Codex CLI 버전 문제**, 계정 문제 아님. 업그레이드:

```
npm install -g @openai/codex@latest
codex --version   # >= 0.125.0
```

자매 플러그인의 `triad/docs/codex-5.4-to-5.5.md` 참조.

### Findings가 너무 많음 / 리포트가 시끄러움

- `--quick`으로 Evidence pass 생략 (빠르지만 false positive 증가).
- 기본 리포트는 이미 Improvement 렌즈를 제외한다 — `--include-improvements`를 붙였다면 빼기.
- 보안 전용이면 `--redteam`: 깊이는 늘고 소음은 아니다 — 그 finding도 증거 검증을 거친다.

---

## Requirements

- Claude Code (`/plugin` 명령 있는 버전) — general-purpose 서브에이전트 스폰
- *(선택 — `/prism-codex`, `/prism-all`에만)* [Codex CLI](https://github.com/openai/codex) `>= 0.125.0`
- Windows (Git Bash / WSL2), macOS, Linux 지원

기본 `/prism`은 외부 CLI 없이 Claude Code 안에서 완결.

---

## 이런 작업엔 쓰지 마세요

- **1줄 짜리 변경** — 과잉
- **markdown/스펙 리뷰** — prism이 거부한다. `/triad` (3 관점 숙의)로
- **한 파일 반복 다듬기** — `/mangchi` (Codex와 cross-model 망치질)가 더 적합

## 철학

"AI 리뷰어 여럿이 그렇다고 했다"는 여론조사다. 결함 리포트는 *코드에 대한 주장*이고, 코드에 대한 주장은 접지할 수 있다 — 위치, 실행 경로, 인용된 줄, 가능하면 실패하는 테스트. prism은 합의를 탐색 휴리스틱으로, 증거를 확정의 유일한 통화로 취급한다.

## 업데이트 기록

- **2026-10-13 (0.3.0)** — 코드 전용으로 정리, `prism-devil`을 `--redteam`으로 흡수, 보안 체크리스트 자동 로드, SKILL.md 다이어트(참조 파일 분리), target-first 프롬프트 순서, 파일 단위 Evidence 청킹. 상세는 CHANGELOG.
- **2026-04-24** — 새 자매 skill `/prism-codex` (Codex 전용)과 `/prism-all` (dual-engine) 추가. Codex CLI 마이그레이션 writeup은 자매 triad 플러그인의 [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md). Codex 기반 variant 첫 사용 시 "model does not exist" 에러 만나면 먼저 읽어보세요.

## 라이선스

MIT — [`LICENSE`](LICENSE) 참조.

## Author

haroom — [github.com/minwoo-data](https://github.com/minwoo-data)

## Contributing

Issues와 PR 환영: [github.com/minwoo-data/prism](https://github.com/minwoo-data/prism).
