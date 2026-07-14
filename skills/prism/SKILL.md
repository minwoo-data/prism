---
name: prism
description: Evidence-graded multi-angle review — 5 defect-focused lenses discover in parallel, then an Evidence pass pins every candidate to file/lines/execution-path before anything is confirmed. Statuses SUSPECTED → SUPPORTED → REPRODUCED. Agreement is a prioritization signal, not a verdict. Use when user says "prism", "prism 돌려", "prism <file>", "full review", or before major decisions.
argument-hint: "[file-or-topic] [--quick] [--adversarial] [--reproduce] [--diff [range]] [--include-improvements] [--lenses=classic] [--format json]"
context: fork
user-invocable: true
---

# Prism — Evidence-Graded Multi-Angle Review

> 5 lenses look through different facets. Nothing is "confirmed" because reviewers agreed —
> a finding is confirmed because someone **pinned it to code** (file, lines, execution path)
> and, when possible, **reproduced it with a failing test**. Agreement decides what gets
> investigated first; evidence decides what survives.

## The evidence ladder

Every finding carries exactly one status:

| Status | Meaning | Requirements |
|---|---|---|
| `SUSPECTED` | Agent reasoning only | claim + lens source |
| `SUPPORTED` | Static evidence found | file + lines + symbol + execution_path + code quote |
| `REPRODUCED` | Failure demonstrated | SUPPORTED + a failing test/command actually run |
| `REJECTED` | Contradicted or unfounded | the contradicting evidence, stated |

Rules that follow from the ladder:

- **Agreement ≠ confirmation.** 2+ lenses agreeing makes a finding a *priority candidate*,
  never a confirmed defect. All prism lenses run on the same model, and same-model agents
  can share the same misunderstanding.
- A finding that cannot be pinned to a location stays `SUSPECTED`, and the report says
  *why* (missing context, needs domain confirmation, target not in scope).
- Only `REPRODUCED` may claim certainty language in the report ("does happen"). `SUPPORTED`
  uses "the code path allows"; `SUSPECTED` uses "may".

## Modes

| Invocation | Behavior |
|---|---|
| `/prism <target>` | **Default: Discovery → Evidence pass.** All candidates get evidence-checked. |
| `/prism <target> --quick` | Discovery only. Everything reported as `SUSPECTED`. Speed > signal. |
| `/prism <target> --adversarial` | Evidence pass must argue *against* its own REJECTs before finalizing. |
| `/prism <target> --reproduce` | + Reproduction pass: minimal failing tests in a temp dir (never the project). |
| `/prism --diff [base...head]` | Review **the change**, not the file: "what regression does this diff introduce?" |
| `/prism <target> --include-improvements` | Adds the Improvement lens (suggestions labeled separately, excluded from defect counts). |
| `/prism <target> --lenses=classic` | Legacy lens set (Conflict/Improvement/Devil/CodeReview/Robustness). Auto-selected for non-code targets (design docs, plans). |
| `/prism <target> --format json` | Also emit machine-readable `prism-report.json` (finding records v2). |

## Target resolution

- File path → review that file. Topic → locate and review relevant files. No argument → current project design/quality.
- **Always read the full target content first** and pass it verbatim to each agent. No summarization.
- Target type detection (decides the lens set + auto-choice): **code** if the majority of target
  bytes are source files (or, in `--diff` mode, if any hunk touches a code file); **non-code**
  (markdown/design/plans) otherwise → auto `--lenses=classic`. The header prints `Lenses: defect
  (auto)` / `classic (auto)` / `... (explicit)` so a silent flip between runs is visible. For
  non-code the evidence pass still runs but "evidence" = quoting the contradicting/verifying
  passage, capped at MEDIUM confidence (§Confidence).

### `--diff` mode (change-scoped review)

Target = the diff, not the codebase. Range selection rule: dirty worktree → staged+unstaged vs
`HEAD`; clean worktree → `merge-base main...HEAD` (explicit `<range>` overrides). Collect and hand
each lens:

1. Changed hunks (`git diff <range>`)
2. Pre-change code for each hunk (`git show <base>:<file>` excerpt)
3. Enclosing function/class of each hunk + **up to ~5 direct callers/callees** (grep the symbol;
   cap the context against the prompt-size guard so runs are comparable)
4. Tests referencing the changed symbols
5. Schema/config/migration files touched
6. PR description if available (`gh pr view --json title,body`)

Frame every lens with: **"What regression risk does *this change* newly introduce?"** — not "is this codebase good". Findings must reference a hunk. Pre-existing issues in unchanged code are reported only under a separate `PRE-EXISTING (out of scope)` note, max 3 lines. (`--diff` is `/prism` only; for cross-model diff review run `/prism-all` on the same collected context.)

---

## Lens sets

### DEFECT set (default for code)

Five lenses tuned to find **defects**, not opinions:

1. **Correctness & Contracts** — wrong results, boundary values, error/exception paths, violated invariants, API contract breaks (return shapes, nullability, units, encoding).
2. **Security & Trust Boundaries** — input validation, authn/authz, secrets handling, injection, data crossing trust boundaries, unsafe defaults.
3. **State, Concurrency & Recovery** — races, double-submit, lost update, TOCTOU; crash/timeout mid-flight, idempotency, retry safety, rollback, orphaned state; state machine holes (forbidden/stuck/re-entry transitions).
4. **Integration & Regression** — caller/callee impact, schema/config drift, backward compatibility, hidden coupling, "works alone, breaks together".
5. **Testability & Observability** — can this failure be caught? missing test seams, swallowed errors, logs that lie, silent fallbacks, unmonitorable failure modes.

The **Improvement** lens (refactors, features, UX ideas) is *not* in the default set — it makes
defect reports noisy. `--include-improvements` adds it as a 6th agent; its findings are labeled
`category: improvement` and excluded from defect counts and the action order.

### CLASSIC set (`--lenses=classic`, auto for non-code)

Conflict Detection / Improvement / Devil's Advocate / Code Review / Robustness (4-axis) — the
original prism lenses, better suited to designs, plans, and documents.

---

## Pass 1 — Parallel discovery (5 agents)

Launch all agents in a **single message** with multiple Agent tool calls, forked context.
Each agent gets: the lens definition below, the full target, and this output contract:

> After your reasoning, emit exactly one fenced block. One line per finding:
> ```
> <<<PRISM-FINDINGS v1>>>
> SEV | file:lines@symbol | claim -> suggested fix
> <<<END>>>
> ```
> SEV ∈ CRIT|HIGH|MED|LOW. LOCUS must be as precise as you can make it — `file:lines@symbol`
> when you can pin it, a section name when you cannot. **LOCUS must not contain `|`** (replace any
> pipe with `/`); the parser splits on the first two pipes and treats the last `->` as the fix
> boundary. Emit your real block as the **last** fence in the message. Empty block = this lens is
> clean. Do not confirm anything: you produce *suspicions*; the evidence pass does the confirming.

Lens prompts (DEFECT set — default for code):

- **Correctness & Contracts**: "Find places where this code produces wrong results or violates its stated/implied contract. Check boundaries (empty/zero/max/unicode), error paths, invariants, return-shape and nullability promises, unit/encoding mismatches. Concrete inputs → wrong output beats abstract concern."
- **Security & Trust Boundaries**: "Find defects where untrusted data or callers can cause harm: missing validation, authz gaps, injection, secret exposure, unsafe defaults, trust-boundary crossings. State the attacker precondition for each."
- **State, Concurrency & Recovery**: "Two callers at once; a crash halfway; a retry after timeout. Find races, lost updates, TOCTOU, non-idempotent retries, orphaned/stuck states, forbidden state transitions. For each: the interleaving or failure sequence that triggers it."
- **Integration & Regression**: "Who calls this, what does it call, what breaks together? Find caller-contract breaks, schema/config drift, backward-compat hazards, hidden coupling. Name the affected caller/consumer for each."
- **Testability & Observability**: "When this fails in production, will anyone know? Find swallowed exceptions, silent fallbacks, misleading logs, untestable seams, failure modes with no signal. For each: how the failure would (not) surface."

CLASSIC set (`--lenses=classic`, auto for non-code targets). Category mapping into record v2 is in
the schema comment.

- **Conflict Detection**: "Find conflicts, contradictions, and integration risks: overlaps with existing code/skills, config contradictions, tool-chain conflicts, edge cases where components disagree."
- **Improvement**: "Suggest concrete enhancements. For each: current state → proposed improvement → rationale. Focus on logic/efficiency/UX gains, missing features, integration opportunities."
- **Devil's Advocate**: "Find weaknesses, failure modes, and reasons this might not work: self-evaluation bias, gaming/Goodhart risk, practical failure modes, cost/time, false confidence, scope creep, regression risk. Give each a mitigation."
- **Code Review**: "Review for clarity, completeness, correctness, consistency: ambiguous instructions, missing edge cases, pattern consistency, actionability of each step."
- **Robustness (4-Axis)**: "Evaluate 4 orthogonal failure axes with concrete scenarios (N/A if none): (1) Concurrency — races, double-submit, lost update, TOCTOU; (2) Failure & Recovery — mid-flight crash/timeout, idempotency, retry safety, rollback, orphaned state; (3) Data Integrity — FK cascade direction, unique/CHECK constraints, upsert vs replace, schema mismatch; (4) State Transitions — every reachable state, forbidden/terminal/re-entry."

Severity tokens in every lens must be the fence set `CRIT|HIGH|MED|LOW` (not CRITICAL/MEDIUM — the
parser normalizes aliases but emit the canonical tokens to be safe).

---

## Triage — candidates, not verdicts

Write each agent's returned block to a file and extract deterministically — the same code-not-
eyeballing rule the dual-engine skills use:
```
node "<this skill dir>/parse-findings.js" "<agent-out>" "<lens>" > "<agent-out>.json"
```
Then group semantically overlapping findings:

- **model_agreement** = how many lenses flagged it (e.g. `3/5`). Record it; it is a
  *prioritization* signal only. A parser `degraded:true` record is infra, not a candidate — route
  it to a "DEGRADED LENSES" note, exclude from candidate counts and fingerprinting.
- Order the candidate list: agreements first (highest N first), then singletons by severity.
- `--quick` → stop here. Report everything as `SUSPECTED`, labeled by lens + agreement count.

There is **no auto-confirm path**. The old rule "2+ agents → CONFIRMED" is retired: same-model
agreement caps confidence at MEDIUM (see Confidence below) until evidence raises it.

---

## Pass 2 — Evidence & verification (default)

The **Evidence Agent** (spawned via the Agent tool with Read/Grep/Glob + the repo root, *not* a
re-paste of the target) grounds candidates in **chunks of ≤8** (agreements first, then CRIT/HIGH),
one batched call per chunk. It reads the actual files to quote them.

> You are an **Evidence Agent**. Reviewers produced the candidate findings below. For each one,
> your job is to *ground it in the actual code* — or kill it. Never take a reviewer's word.
>
> For each candidate, do this in order:
> 1. **Pin the location**: exact `file`, `lines`, `symbol`. If you cannot locate it, the finding
>    stays `SUSPECTED` — record what was missing.
> 2. **Trace the execution path**: the ordered call/branch steps from entry to defect
>    (e.g. `reset_password() → token lookup → password update → token not invalidated`).
> 3. **Quote the evidence**: the line(s) that make the claim true, cited as `file:line — quote`.
> 4. **Check the precondition**: what must an attacker/caller/state satisfy? If the precondition
>    is impossible in this codebase, that is a `REJECTED` with the contradicting evidence.
> 5. **Verdict**: `SUPPORTED` (1–3 all present) / `REJECTED` (contradicting evidence, quote it) /
>    `SUSPECTED` (cannot pin or needs domain knowledge — name the missing context, e.g.
>    `REQUIRES_DOMAIN_CONFIRMATION: is reuse of reset tokens within 5min acceptable?`).
> 5b. Location pinned but path or quote incomplete → `SUSPECTED` with `evidence_strength: WEAK`
>    and a `missing:` note (do not grant SUPPORTED on a partial pin).
> 6. You may adjust severity with one sentence of justification. Do NOT invent new findings.
> 7. For each `SUPPORTED` finding, name a `suggested_test` (test function name + one-line scenario)
>    even if reproduction is not requested — it makes the finding actionable.
> 8. Read the actual file for every quote — do NOT trust the reviewer's wording. Quotes are
>    machine-checked afterward; a fabricated one is downgraded, so quoting real lines is the only
>    way a finding survives as SUPPORTED.
>
> Output one finding record v2 (schema below) per candidate, each as one JSON object on its own
> line inside a single fence:
> ```
> <<<PRISM-RECORDS v2>>>
> {"id":"PRISM-001","candidate_id":"c1","file":"src/auth.py","lines":"84-102",...}
> <<<END>>>
> ```
> Agreement count is given; you fill `evidence_strength`: NONE (nothing pinned) / WEAK (location
> only) / MEDIUM (location + execution path + quote) / STRONG (reproduced — only Pass 3 sets it).

**Batching (no unbounded single call):** ground candidates in chunks of **≤8**, agreements first,
then CRIT/HIGH, then the rest — one batched call per chunk. If a chunk call fails or omits a
candidate, that candidate alone is reported `SUSPECTED (missing: EVIDENCE_PASS_FAILED)`; never
re-verdict a candidate already decided, never fail the whole run. A single 30-candidate call
skims and rubber-stamps — the exact failure the evidence pass exists to prevent.

**Machine check (invariant — stops the model grading its own homework):** parse the v2 records to
JSON, then run
```
node "<this skill dir>/verify-evidence.js" records.json "<repo-root>" > checked.json
```
It (1) greps every `SUPPORTED`/`REPRODUCED` quote against the cited file+lines and auto-downgrades
non-matches to `SUSPECTED (EVIDENCE_QUOTE_MISMATCH)`, and (2) computes `fingerprint` in code (an
LLM cannot compute sha1). **`checked.json` is the source of truth** — an unverified quote must not
ship as SUPPORTED. Self-check: `node verify-evidence.js --selftest`.

### Adversarial mode (`--adversarial`)

Before finalizing any `REJECTED`, the Evidence Agent must argue the reviewer's side: "what if
they're right and I'm missing context?" Only reject if the counter-argument is more specific and
better-sourced than the original claim.

---

## Pass 3 — Reproduction (`--reproduce`)

Prism stays a **pure reviewer**: the project is never modified. Reproduction happens in a
throwaway sandbox.

Actor: the **main agent (or a dedicated Reproduction Agent with Bash)** runs this — the Evidence
Agent never executes code. Selection: machine-verified `SUPPORTED` only, CRIT/HIGH first,
**max 5 per run** (report how many were skipped and why).

> ⚠️ **"Temp dir" is a write guard, not an execution sandbox.** Importing/running the target
> executes its module-level side effects **with the operator's full environment** — the same env
> whose secrets a prior incident leaked. Every reproduction command MUST: run with a **stripped
> env** (`env -i` + an allowlist: PATH, language runtime, `HOME` if required); **cwd = the temp
> dir**; **no network** where the runner supports disabling it; **install nothing anywhere** (only
> runners already on PATH); ask the operator to **confirm once** before the first execution this
> run; and pass output through the §Codex invariant-7 secret-scrub before it enters the report.

Per finding:

1. **Search existing tests first** — an existing test covering the path may prove or disprove the
   claim without writing anything (run it *isolated*, and compare against a baseline run so an
   unrelated failing suite doesn't bias the verdict).
2. Detect a test runner **already on PATH** (pytest / vitest / jest / `node --test` / go test /
   cargo test). None on PATH → `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT` (do **not** install one).
3. Write a **minimal failing test** in `${TMPDIR:-${TEMP:-/tmp}}/prism-tests/` (prefer `mktemp -d`),
   importing the target by path. Never write inside the project tree.
4. **Pre-register the expected failure signature** (exception type / assertion message) in the
   record *before* running — only a failure matching it counts as REPRODUCED.
5. Run with a **per-test 60s timeout** (5min total). Record exit code, duration, and the verbatim
   stdout/stderr tail. Require **2 consecutive identical outcomes** (flake guard).
6. Classify:

| reproduction.status | Meaning |
|---|---|
| `REPRODUCED` | Failure **matching the pre-registered signature**, twice → finding becomes `REPRODUCED` |
| `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT` | Runner/deps/fixtures unavailable, **or a setup/import/fixture error** (a non-matching red is NOT a reproduction) |
| `TIMED_OUT` | Ran past the timeout (for a concurrency bug a hang may *be* the reproduction) — never auto-upgrades; recorded for the operator |
| `STATIC_EVIDENCE_ONLY` | Not attempted (cap, or inherently static claim) |
| `REQUIRES_EXTERNAL_SERVICE` | Needs a DB/API/queue this sandbox doesn't have |
| `REQUIRES_DOMAIN_CONFIRMATION` | Only a human can say whether this behavior is wrong |

7. **If the self-written test passes**: downgrade **at most to `SUSPECTED`** (a self-written passing
   test is not the "contradicting evidence" a `REJECTED` requires), and only if it actually
   exercises the claimed preconditions+path; otherwise keep `SUPPORTED` with
   `reproduction.status: NOT_REPRODUCED_BY_ATTEMPT`. Quote the passing run either way.
8. Clean up the temp dir (except on a scrub event — then preserve the sanitized markers durably and
   tell the operator); keep the test source **in the report and JSON** for promotion.

Never hide that reproduction didn't run: every record carries `reproduction.status`, and
`STATIC_EVIDENCE_ONLY` / `NOT_RUN` are honest, common values.

---

## Finding record v2 (required for every reported finding)

```yaml
id: PRISM-001                    # run-scoped, sequential; NOT stable across runs (use fingerprint for that)
candidate_id: c1                 # links back to the discovery candidate for batch reconciliation
fingerprint: a3f92c1e0b71        # sha1(normPath|symbol|category|claim-slug)[:12] — computed by verify-evidence.js, NOT the model
unpinned: false                  # true when file:null → excluded from cross-run dedup
file: src/auth.py                # null allowed only for SUSPECTED
lines: 84-102
symbol: reset_password
category: security               # correctness|security|state|integration|testability|improvement
                                 # classic lenses map: conflict→integration, devil→correctness,
                                 # code-review→correctness, robustness→state, improvement→improvement
severity: HIGH
status: SUPPORTED                # SUSPECTED|SUPPORTED|REPRODUCED|REJECTED
missing: null                    # required string when SUSPECTED (what blocked grounding)
degraded: false                  # true only for infra markers (never a real finding)

claim: "Reset token can be reused"
preconditions:
  - "Attacker has a previously used reset token"
execution_path:
  - reset_password() → token lookup → password update → token not invalidated
evidence:
  - "src/auth.py:98 — token record remains active after successful update"
suggested_fix: "invalidate the token row inside the update transaction"   # carried from the v1 line

reproduction:
  status: NOT_RUN                # NOT_RUN|REPRODUCED|NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT|TIMED_OUT|STATIC_EVIDENCE_ONLY|REQUIRES_EXTERNAL_SERVICE|REQUIRES_DOMAIN_CONFIRMATION|NOT_REPRODUCED_BY_ATTEMPT
  suggested_test: test_reset_token_cannot_be_reused
  expected_signature: null       # pre-registered failure (exception/assertion) before running
  command: null                  # exact command when run
  result: null                   # verbatim tail when run

confidence:
  model_agreement: "3/5"         # /prism: n/5. /prism-all uses agreement:{claude,codex,cross_model} instead
  evidence_strength: MEDIUM      # NONE|WEAK|MEDIUM|STRONG  (finalized by verify-evidence.js)
  label: HIGH                    # closed enum below
```

Field rules: `file/lines/symbol` are **required** for `SUPPORTED`+ (no location → cannot be
SUPPORTED). `evidence` requires ≥1 quoted line for SUPPORTED, and each quote must actually appear
at the cited lines (verify-evidence.js enforces this). `SUSPECTED` may have `file: null` but must
carry `missing:`. `reproduction.status` = `NOT_RUN` in default/`--quick` mode; the other values
only appear under `--reproduce`. `--quick` emits degenerate records (status SUSPECTED,
evidence_strength NONE, reproduction NOT_RUN, fingerprint null).

## Confidence (closed enum, computable from stored fields)

`confidence = model_agreement × evidence_strength`, minus honesty penalties. Label enum:
`{LOW, MEDIUM, MEDIUM-HIGH, HIGH, HIGH+, VERY-HIGH}`.

| model_agreement | evidence_strength | Label |
|---|---|---|
| single lens | NONE / WEAK | LOW |
| 2+ same-model lenses | NONE / WEAK | MEDIUM (hard cap — same model repeats the same misunderstanding) |
| cross-model (`/prism-all` only) | NONE / WEAK | MEDIUM-HIGH |
| any | MEDIUM (location + path + machine-verified quote) | HIGH |
| cross-model | MEDIUM | HIGH+ |
| any | STRONG (reproduced) | VERY-HIGH |
| — | — (`status: REJECTED`) | reported in the REJECTED section, no label |

Cross-model agreement is not available in single-engine prism (its rows never fire here);
`/prism-all` adds it. For **non-code targets** "evidence" is a document quote, not an execution
path — cap the label at MEDIUM (a discovery agent already saw the whole doc; re-quoting it is not
independent grounding).

---

## Final report

```
PRISM REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce] [diff <range>]
Lenses: {defect | classic} {+improvements}
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected

## REPRODUCED (demonstrated failures)
- PRISM-003 [HIGH|security] src/auth.py:84-102 reset_password — Reset token can be reused
  path: reset_password → token lookup → update → not invalidated
  repro: pytest /tmp/prism-tests/test_reset_reuse.py → FAILED as predicted
  fix: invalidate token row inside the update transaction

## SUPPORTED (code-path evidence, not executed)
- PRISM-001 [...] file:lines@symbol — claim
  evidence: file:line — quote | repro: STATIC_EVIDENCE_ONLY | suggested_test: ...

## SUSPECTED (needs confirmation — reasoning only)
- PRISM-007 [...] — claim — missing: REQUIRES_DOMAIN_CONFIRMATION: <question for the operator>

## REJECTED (transparency)
- [lens] claim — contradicting evidence: file:line — quote

## IMPROVEMENTS (only with --include-improvements)
## PRE-EXISTING, OUT OF SCOPE (only in --diff mode, max 3 lines)

## Recommended Action Order
1. REPRODUCED first, then SUPPORTED by severity. SUSPECTED items appear as questions, not tasks.
```

With `--format json`, also write `prism-report.json` to the **run's artifacts dir**
(`${TMPDIR:-${TEMP:-/tmp}}/prism/<slug>-<run-id>/`, or the `--artifacts=docs` location — never the
project root, which would violate the read-only invariant). Write to a temp file, validate, then
atomic-rename; on failure emit the JSON inline in the transcript with a `json_output: failed`
warning rather than failing the run, and print the absolute path in the report header.
`{ "meta": {target, mode, lenses, engines, timestamp, counts}, "findings": [<record v2>...] }` —
fingerprints let CI dedup across runs (link by fingerprint; never suppress a prior REJECTED).
(SARIF output + GitHub Action: roadmap.)

---

## Rules

- Each Pass 1 agent runs with `context: fork`; launch all in one message (parallel).
- Pass full target content to each agent. Never summarize the input.
- **Never modify the target project.** Reproduction runs in a temp dir with a stripped env and no
  installs (§Pass 3); artifacts default to the temp dir, not the repo.
- The Evidence Agent grounds candidates in **chunks of ≤8**, not one unbounded call; every quote is
  machine-checked by `verify-evidence.js` before it can ship as SUPPORTED.
- Status is **per-run truth**; cross-run dedup links by fingerprint but never carries a prior
  verdict forward. IDs (`PRISM-00N`) are run-scoped — do not correlate across runs.
- Contradicting lenses → surface both; the Evidence pass picks a side only with quoted evidence.
- Keep synthesis concise: the record carries the detail; prose stays ≤3 lines per finding.

## Cost & speed

| Mode | Discovery | Evidence | Repro | Relative cost |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 0 | 1.0× |
| default | 5 | ⌈candidates/8⌉ chunked | 0 | 1.3–1.6× |
| `--reproduce` | 5 | ⌈candidates/8⌉ | ≤5 test runs | 1.6–2.2× |
| `--include-improvements` | 6 | ⌈candidates/8⌉ | — | +0.2× |

Default includes the evidence pass because ungrounded findings are the #1 failure mode of
multi-agent review, and the machine quote-check is what keeps the pass from rubber-stamping.

## Companion skills

- **prism-all** — ships in this plugin: adds a Codex engine for cross-model agreement on the same evidence ladder.
- **mangchi** — after prism identifies weak files, iteratively harden them (prism finds, mangchi fixes). Separate plugin.
- **triad** — 3-perspective deliberation for markdown/specs. Separate plugin.
- **prism-devil** — single-agent red-team probe for security-sensitive targets. Separate plugin (`minwoo-data/prism-devil`), not required by prism.
