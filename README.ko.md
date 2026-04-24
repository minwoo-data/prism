# prism

> Language: [English](README.md) · **한국어**

**하나의 파일을 5 각도 리뷰어에게 병렬로 태우고, 1명만 잡은 것은 Verifier가 재검증한다.**

리뷰어 한 명의 "괜찮아 보인다"가 2주 뒤 "어떻게 이걸 놓쳤지?"의 가장 흔한 출처다. prism은 같은 target을 5 개 서로 다른 편향으로 동시에 리뷰하고, **한 명만 지적한 finding**(false positive 위험 구간)만 batched Verifier로 재검증한다. 2명 이상이 합의한 지적은 바로 통과.

```
/prism <target>                  -> 기본: 5 agents + batched Verifier
/prism <target> --quick          -> 1 pass만, Verifier skip
/prism <target> --adversarial    -> 1 pass + REJECT 재검증 (self-bias 방어)
```

5 에이전트, 5 각도, 한 스펙트럼. Target은 파일/디렉토리/주제 전부 OK.

---

## 30초 데모

**prism 없이:**

Claude에게 "이 파일 리뷰해줘" 하면 "괜찮아 보인다" 답이 오고 merge. 2주 뒤, 다른 각도(예: 동시성 또는 config 충돌)에서 보면 금방 잡혔을 버그가 터진다. 그 각도를 독립 리뷰어에게 체크할 생각을 아무도 못 했던 것.

**prism으로:**

`/prism src/services/auth.py`. 5 리뷰어가 병렬로 서로 다른 편향(conflict / improvement / devil / code-review / robustness)에서 파일을 본다. 2명 이상이 같은 지적을 하면 자동 CONFIRMED. 한 명만 본 지적은 별도 Verifier pass를 거쳐 false positive가 시간 낭비하지 않게 한다.

## 누가 써야 하는가

- **큰 아키텍처 결정 직전** — 1관점이 아니라 5관점이 필요할 때
- **확신 안 서는 PR merge 직전** — 본인 LLM의 의견 너머 독립 검토가 필요할 때
- **기능 구현 후** — 릴리스 전 맹점 최종 sweep
- **skill / 디자인 문서 / 워크플로우 감사** — 리뷰어 간 의견 불일치 자체가 신호
- "5명한테 같은 코드 보여주고 싶다"는 욕구를 자동화하고 싶을 때

## 자매 도구 (같은 마켓플레이스)

- **[ddaro](https://github.com/minwoo-data/ddaro)** — worktree 기반 병렬 Claude Code 세션 + 안전한 merge.
- **[triad](https://github.com/minwoo-data/triad)** — markdown / 디자인 문서용 더 깊은 3관점 숙의.
- **[mangchi](https://github.com/minwoo-data/mangchi)** — Claude + Codex cross-review로 파일 반복 다듬기.

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
/prism src/services/auth.py                 # 기본: 5 agents + batched Verifier
/prism src/services/auth.py --quick         # 1 pass만, verify skip
/prism src/services/auth.py --adversarial   # 1 pass + REJECT 재검증
/prism .                                    # 프로젝트 전체 리뷰
```

설치/업데이트 후 Claude Code **재시작**.

---

## 이 플러그인이 제공하는 3 variant

`prism` 플러그인을 설치하면 같은 5-각도 프레임워크를 공유하되 **판단 주체가 다른** 3 skill이 함께 들어옵니다:

| Skill | 엔진 | 언제 쓰나 |
|---|---|---|
| `/prism` | **Claude** — 5 agents 병렬 + Verifier | 기본. Wall-time 가장 빠름, 외부 CLI 불필요. |
| `/prism-codex` | **Codex CLI** — 5 순차 + Verifier, gpt-5.5 | Claude 토큰 절약 / 다른 모델 관점. `codex-cli >= 0.125.0` 필요. |
| `/prism-all` | **Claude + Codex 병렬** — 10 discovery + Verifier | 최고 신뢰. 같은 각도에서 두 엔진이 모두 flag한 이슈는 Tier 1. `--verifier=claude\|codex\|both`로 판정자 선택. |

세 variant 전부 한 번의 플러그인 설치에 포함. Codex CLI 전제 상세: 자매 플러그인의 [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md) ("model does not exist" 에러는 계정 문제가 아니라 CLI 버전 문제).

---

## 5 에이전트

| Agent | 찾는 것 |
|---|---|
| **Conflict Detection** | 기존 코드/스킬 중복, config 모순, 통합 리스크 |
| **Improvement** | 구체적 개선안, 효율 향상, 누락 기능 |
| **Devil's Advocate** | 약점, gaming/Goodhart 위험, false confidence, 회귀 위험 |
| **Code Review** | 명확성, 완결성, 정확성, 패턴 일관성 |
| **Robustness (4축)** | 동시성 / 장애복구 / 데이터무결성 / 상태전이 |

각 에이전트는 **forked context**에서 실행 — 메인 대화가 오염되지 않고, 서로의 응답을 볼 수 없음. Agreement가 echo가 아니라 독립 signal로 성립.

## 검증 동작 방식

Pass 1 종료 후 모든 finding 분류:

- **AGREEMENT** (2+ agent가 같은 지적) → 자동 CONFIRMED, Pass 2 skip
- **SINGLETON** (1 agent만) → Pass 2로

Pass 2는 **단일 batched Verifier** 호출. 전체 target + Pass 1 5개 결과 + singleton 리스트 받아서 `CONFIRMED | REJECTED | DEPENDS` 반환. singleton이 20개든 2개든 비용 동일.

저렴한 합의는 빠르게 통과, borderline만 검증 비용.

## Features

- **병렬 discovery** — 5 에이전트를 한 tool call로 발사. 총 wall-time ≈ 가장 느린 하나, 합이 아님.
- **합의 자동 승급** — 2+ 에이전트 convergence = 최고 신뢰 티어, Verifier skip.
- **Batched Verifier** — 한 호출로 모든 singleton 처리. finding 수가 늘어도 검증 비용 증가 없음.
- **Adversarial 모드** — `--adversarial`에서 Verifier가 자기 REJECT에 대해 반대 주장을 시도 후 통과. 실제 이슈를 잘못 기각하는 걸 방어.
- **Fork 격리** — 5 에이전트가 서로의 응답을 못 봄. 대화 오염 / echo chamber 없음.
- **코드 수정 없음** — prism은 순수 reviewer. 코드를 실제로 바꾸려면 다른 도구 (예: `/mangchi`).

---

## 모드와 출력

```
/prism src/services/auth.py                 # 기본: 2-pass verify
/prism src/services/auth.py --quick         # 1 pass만
/prism src/services/auth.py --adversarial   # 1 pass + REJECT 재검증
/prism .                                    # 프로젝트 전체
```

자연어: *"prism 돌려"*, *"full review"*, *"design review"*.

리포트 형식:

```
PRISM REPORT - src/services/auth.py - 2026-04-20 15:30
Mode: verify

## CRITICAL (must fix)
- [3/5 agreement] CSRF 토큰이 요청 간 재사용됨 → 요청별 회전
- [1/5 → verified] 비밀번호 재설정 링크가 단일 사용이 아님 → nonce 테이블 추가

## HIGH (should fix)
- [2/5 agreement] ...
- [1/5 → verified] ...

## Rejected Singletons
- [Improvement → rejected] "OAuth 로그인 추가" - Verifier: CLAUDE.md에 SSO 영구 deferral 명시됨

## Cross-Agent Agreements
3개 findings에서 multiple agent 합의

## Recommended Action Order
1. ...
```

## 비용

| 모드 | 비용 | 언제 |
|---|---|---|
| `--quick` | 1.0× | 이미 triage된 target |
| 기본 (verify) | 1.2–1.4× | 일반 리뷰 |
| `--adversarial` | 1.2–1.4× | 자기 편향 의심 시 |

Verifier 비용은 singleton 수에 무관 (batched).

---

## 사용 예시

```
/prism src/services/auth.py
# → 5 agent 병렬 (~20~40s, 파일 크기 의존)
# → Pass 1 결과: finding 8개. AGREEMENT 3, SINGLETON 5.
# → 메인: "Running verifier on 5 singletons..."
# → Verifier (batched): CONFIRMED 3, REJECTED 1, DEPENDS 1
# → 최종: actionable 6 + depends 1 + rejected 1 (투명성)

# 보안 리뷰는 더 엄격하게:
/prism src/security/ --adversarial
# → 같은 Pass 1. Verifier가 REJECT 전에 반대 주장 시도.
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
# → Tier 3: singleton (Verifier로 감)
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

- `--quick`으로 Verifier skip (빠르지만 false positive 증가).
- 공격자 마인드 심층 probe가 필요하면 `/prism-devil` 사용.

---

## Requirements

- Claude Code (`/plugin` 명령 있는 버전) — general-purpose 서브에이전트 스폰
- *(선택 — `/prism-codex`, `/prism-all`에만)* [Codex CLI](https://github.com/openai/codex) `>= 0.125.0`
- Windows (Git Bash / WSL2), macOS, Linux 지원

기본 `/prism`은 외부 CLI 없이 Claude Code 안에서 완결.

---

## 이런 작업엔 쓰지 마세요

- **1줄 짜리 변경** — 과잉
- **markdown/스펙 리뷰** — `/triad` (3 관점 숙의)가 더 적합
- **한 파일 반복 다듬기** — `/mangchi` (Codex와 cross-model 망치질)가 더 적합
- **보안 전용 심층 probe** — `/prism-devil` (공격자 마인드 specialist)

## 철학

5 독립 리뷰어가 서로를 못 본다. 그들이 합의한 건 대체로 진짜다. 한 명만 본 건 한 번 더 검증 후 시간을 투자할지 결정. Verifier를 단일 batched 호출로 만든 이유가 이 구조 — discovery와 verification을 분리하면 verification이 finding 수에 선형적으로 비싸지지 않는다.

## 업데이트 기록

- **2026-04-24** — 새 자매 skill `/prism-codex` (Codex 전용)과 `/prism-all` (dual-engine) 추가. Codex CLI 마이그레이션 writeup은 자매 triad 플러그인의 [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md). Codex 기반 variant 첫 사용 시 "model does not exist" 에러 만나면 먼저 읽어보세요.

## 라이선스

MIT — [`LICENSE`](LICENSE) 참조.

## Author

haroom — [github.com/minwoo-data](https://github.com/minwoo-data)

## Contributing

Issues와 PR 환영: [github.com/minwoo-data/prism](https://github.com/minwoo-data/prism).
