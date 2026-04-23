# Prism — 검증까지 포함된 다관점 리뷰

**Language**: [English](README.md) · **한국어**

> 5명의 리뷰어, 5개 각도, 한 스펙트럼. 합의는 통과, singleton은 검증.

---

## 이런 분을 위한 도구입니다

- 큰 결정 전에 여러 각도로 한 번 훑고 싶은 분
- 단일 agent 리뷰의 false positive에 시달려본 분
- "5명한테 같은 코드 보여주고 싶다"는 욕구를 자동화하고 싶은 분
- 합의된 지적과 한 명만 한 지적을 구분해서 보고 싶은 분

## 이런 작업엔 쓰지 마세요

- 1줄 짜리 변경 — 과잉
- markdown/스펙 리뷰 — `/triad` (3 관점 숙의)가 더 적합
- 한 파일 반복 다듬기 — `/mangchi` (Codex와 cross-model 망치질)가 더 적합

## 5개 agent

| Agent | 찾는 것 |
|---|---|
| **Conflict Detection** | 기존 코드/스킬 중복, config 모순, 통합 리스크 |
| **Improvement** | 구체적 개선안, 효율 향상, 누락 기능 |
| **Devil's Advocate** | 약점, gaming/Goodhart 위험, false confidence, 회귀 위험 |
| **Code Review** | 명확성, 완결성, 정확성, 패턴 일관성 |
| **Robustness (4축)** | 동시성 / 장애복구 / 데이터무결성 / 상태전이 |

각 agent는 forked context에서 실행되므로 메인 대화는 깨끗하게 유지.

## 검증(verify)이 동작하는 방식

Pass 1 종료 후 모든 finding 분류:

- **AGREEMENT** (2+ agent가 같은 지적) → 자동 CONFIRMED, Pass 2 skip
- **SINGLETON** (1 agent만) → Pass 2로

Pass 2는 **단일 Verifier agent** 호출 (batched). 전체 target + Pass 1 5개 결과 + singleton 리스트를 받아서 각각에 `CONFIRMED | REJECTED | DEPENDS` 반환.

저렴한 합의는 빠르게 통과시키고, borderline만 검증 비용 부담.

## 모드

```
/prism src/services/auth.py                 # 기본: 2-pass verify
/prism src/services/auth.py --quick         # 1 pass만, verify skip
/prism src/services/auth.py --adversarial   # 1 pass + REJECT 재검증
/prism .                                    # 프로젝트 전체 리뷰
```

자연어도 동작: *"prism 돌려"*, *"full review"*, *"design review"*.

## 출력 예시

```
PRISM REPORT — src/services/auth.py — 2026-04-20 15:30
Mode: verify

## CRITICAL (must fix)
- [3/5 agreement] CSRF 토큰이 요청 간 재사용됨 → 요청별 회전
- [1/5 → verified] 비밀번호 재설정 링크가 단일 사용이 아님 → nonce 테이블 추가

## HIGH (should fix)
- [2/5 agreement] ...
- [1/5 → verified] ...

## Rejected Singletons
- [Improvement → rejected] "OAuth 로그인 추가" — Verifier: CLAUDE.md에 SSO 영구 deferral 명시됨

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

Verifier는 **단일 batched 호출** (finding당 1번 X). 20개 singleton이든 2개든 비용 동일.

## 자매 도구

- **[mangchi](https://github.com/minwoo-data/mangchi)** — Codex와 반복 cross-model 다듬기. prism이 약한 파일 찾으면 mangchi로 넘김.
- **prism-devil** — 공격자 마인드 단일 agent aggressive probe. 보안 민감 코드는 prism과 같이 사용.
- **[triad](https://github.com/minwoo-data/triad)** — markdown/짧은 문서용 3관점 숙의.

## 설치

### 1. haroom_plugin 마켓플레이스 등록 (처음 한 번만)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugin.git
```

`prism` 은 haroom 플러그인 (ddaro, triad, mangchi) 과 함께 **haroom_plugin** aggregator 를 통해 배포됩니다.

### 2. 플러그인 설치

```
/plugin install prism
```

설치 후 Claude Code 재시작.

## Created by

Minwoo Park
