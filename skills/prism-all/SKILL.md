---
name: prism-all
description: Dual-engine multi-angle review. Runs all 5 angles (Conflict / Improvement / Devil / CodeReview / Robustness) on BOTH Claude subagents and Codex CLI in parallel — 10 total discovery calls — then Verifier cross-checks singletons. Cross-model agreement = highest confidence. Use for consequential code where you want the strongest possible review. Triggers on "/prism-all <target>", "prism all로", "크로스모델 prism".
argument-hint: "<target> [--quick] [--adversarial] [--verifier=claude|codex|both]"
user-invocable: true
---

# prism-all — Dual-Engine Multi-Angle Review

> 메인은 Claude (오케스트레이터). 매 리뷰 **Claude Agent 5 + Codex CLI 5 = 10 discovery**를 병렬 발사, 같은 각도에서 두 엔진이 모두 잡은 finding을 최고 신뢰 티어로 승급.
> 코드/target은 절대 수정하지 않는다 — 리포트만 산출.

## 핵심 가치

`/prism`은 Claude 5명 내부 ensemble. `/prism-codex`는 Codex 5명 ensemble. **`/prism-all`은 10명 cross-model ensemble**:

- **같은 각도 + 두 엔진 = cross-model agreement** — false positive 가능성 최소
- **같은 엔진 + 다른 각도 2+ = intra-model agreement** — 기존 prism 수준 신뢰
- **한 엔진 한 각도 singleton** — Verifier 검증으로 필터

3 파일 × 2 엔진 벤치마크 기준: 각 엔진이 놓친 unique finding 10+건씩 → 두 엔진 합치면 커버리지 크게 증가.

## 5 각도 × 2 엔진 (10 discovery)

| Agent | Claude | Codex (gpt-5.5) |
|---|---|---|
| Conflict Detection | ✓ | ✓ |
| Improvement | ✓ | ✓ |
| Devil's Advocate | ✓ | ✓ |
| Code Review | ✓ | ✓ |
| Robustness (4-Axis) | ✓ | ✓ |

+ **Verifier** 1콜 (기본 Claude, `--verifier=codex|both`로 override).

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
| `/prism-all <target>` | 기본 — 10 discovery + Verifier |
| `/prism-all <target> --quick` | Verifier 생략 |
| `/prism-all <target> --adversarial` | Verifier가 REJECT 전 반대 주장 |
| `/prism-all <target> --verifier=claude` | Verifier = Claude (기본) |
| `/prism-all <target> --verifier=codex` | Verifier = Codex |
| `/prism-all <target> --verifier=both` | 양쪽 Verifier 각각 singleton 판정, 둘 다 CONFIRMED면 확정 |
| 자연어 | "prism all로", "크로스모델 prism" |

---

## Pass 1 — 10 병렬 발사

**한 메시지 안에서 전부 병렬**:
- Claude 5개: `Agent` tool × 5 (Conflict/Improvement/Devil/CodeReview/Robustness), forked context
- Codex 5개: `Bash` tool × 1 (내부 5개 순차 Codex CLI). 전체 Bash는 Claude Agent와 **병렬**

Wall time ≈ max(Claude 5 parallel ≈ 20~40s, Codex 5 sequential ≈ 100~200s) = **Codex 쪽 병목** (~100~200s).

Agent 프롬프트는 **이 SKILL.md가 자체 보유** (독립성):

**1. Conflict Detection** — 충돌/모순/통합 위험. severity CRIT/HIGH/MED/LOW.
**2. Improvement** — 현재 → 개선안 → 근거. 효율/UX/누락/통합.
**3. Devil's Advocate** — 약점/실패모드, self-bias, Goodhart, 회귀 위험. severity + 완화.
**4. Code Review** — 명확성/완전성/정확성/일관성. `[SECTION] Issue → Fix`.
**5. Robustness (4-Axis)** — Concurrency / Failure&Recovery / Data Integrity / State Transitions. `[Axis N] Scenario → Current → Risk → Fix` + Coverage Summary.

(상세 프롬프트 텍스트는 prism-codex SKILL.md와 동일하며, 이 파일 내부에도 복사됨 — 두 skill 독립 유지.)

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

## Synthesis Triage with Cross-Model Promotion

10 응답 수집 후 3-tier 분류:

### Tier 1 — Cross-model agreement (최고 신뢰)
같은 각도에서 Claude + Codex 둘 다 flag. 레이블: `[cross-model/<angle>]`. severity = union (conservative, 높은 쪽).

### Tier 2 — Intra-model multi-angle (중간 신뢰)
한 엔진의 2+ 각도가 동일 finding. 레이블: `[claude/multi]` 또는 `[codex/multi]`. 기존 prism의 "2+ agents" 수준.

### Tier 3 — Singleton (Verifier 검증 대상)
한 엔진의 한 각도만 flag. 레이블: `[claude/<angle>]` 또는 `[codex/<angle>]`. Pass 2로 감.

### Conflicts
두 엔진이 반대 방향 조언 → "Conflicting" 섹션에 양쪽 표시, Verifier에게 판정 맡기거나 main이 한 줄 근거로 선택.

### Short-circuit
- `--quick` → Pass 2 스킵
- Tier 3 = 0 → Pass 2 스킵
- Tier 3 ≤ 3 → Verifier에 Tier 1/2도 함께 전달 (저렴)

---

## Pass 2 — Verifier (singleton 배치 검증)

**1 콜로 모든 singleton 판정** (선택된 엔진):

> 너는 Verifier. 10 리뷰어 (Claude 5 + Codex 5)가 같은 target을 분석했다. 각 singleton (1명만 지적) 마다 `CONFIRMED` / `REJECTED` / `DEPENDS` 판정.
>
> 규칙:
> - target 전체 + 10 Pass 1 응답 전부 + singleton list 읽고 판정
> - CONFIRMED/REJECTED/DEPENDS (새 finding 발명 금지)
> - severity 조정 가능 (CONFIRMED 시)
>
> `--verifier=both`: Claude Verifier 1콜 + Codex Verifier 1콜. 두 Verifier 모두 CONFIRMED = 확정. 엇갈림 = DEPENDS 처리.
>
> `--adversarial`: REJECT 하기 전 반박 시도 — 더 구체적이고 더 잘 근거 있어야 REJECT.

---

## Final Report

```
PRISM-ALL REPORT — {target} — {timestamp}
Mode: {verify | quick | adversarial}
Engines: Claude 5 + Codex 5 (gpt-5.5)
Verifier: {claude | codex | both}

## CRITICAL (must fix)
- [cross-model/conflict] Finding → Fix         # Tier 1
- [claude/multi] Finding → Fix                 # Tier 2
- [codex/devil → verified] Finding → Fix (Verifier: reason)   # Tier 3 passed

## HIGH / MEDIUM / LOW ...

## Rejected Singletons (Verifier dismissed)
## Depends-on-Context (Verifier DEPENDS)
## Cross-Model Agreements (Tier 1 summary)
## Intra-Model Multi-Angle (Tier 2 summary)
## Engine-Unique Findings (for reference)
  ### Claude-only (what Codex missed)
  ### Codex-only (what Claude missed)
## Conflicting Advice (if any)
## Recommended Action Order
```

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
DIR="docs/prism-all/<slug>"
AGENT="<conflict|improvement|devil|code-review|robustness>"
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

| Mode | Claude 콜 | Codex 콜 | Verifier | wall time | 상대 비용 |
|---|---|---|---|---|---|
| `--quick` | 5 | 5 | 0 | ~100~200s | 2.0× prism |
| default (verify) | 5 | 5 | 1 (batched) | ~120~220s | 2.2~2.4× |
| `--adversarial` | 5 | 5 | 1 | ~120~220s | 2.2~2.4× |
| `--verifier=both` | 5 | 5 | 2 (both batched) | ~140~240s | 2.4~2.6× |

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
- ❌ Cross-model agreement 있는데 singleton 급으로 격하 — Tier 1 고정
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
