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
- Non-code targets (markdown/design/plans) auto-select `--lenses=classic`; the evidence pass still runs but "evidence" means quoting the contradicting/verifying passage instead of an execution path.

### `--diff` mode (change-scoped review)

Target = the diff, not the codebase. Collect and hand each lens:

1. Changed hunks (`git diff <range>`; default range `HEAD` worktree changes, or `main...HEAD`)
2. Pre-change code for each hunk (`git show <base>:<file>` excerpt)
3. Enclosing function/class of each hunk + direct callers/callees (grep the symbol)
4. Tests referencing the changed symbols
5. Schema/config/migration files touched
6. PR description if available (`gh pr view --json title,body`)

Frame every lens with: **"What regression risk does *this change* newly introduce?"** — not "is this codebase good". Findings must reference a hunk. Pre-existing issues in unchanged code are reported only under a separate `PRE-EXISTING (out of scope)` note, max 3 lines.

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
> when you can pin it, a section name when you cannot. Empty block = this lens is clean.
> Do not confirm anything: you produce *suspicions*; the evidence pass does the confirming.

Lens prompts (DEFECT set):

- **Correctness & Contracts**: "Find places where this code produces wrong results or violates its stated/implied contract. Check boundaries (empty/zero/max/unicode), error paths, invariants, return-shape and nullability promises, unit/encoding mismatches. Concrete inputs → wrong output beats abstract concern."
- **Security & Trust Boundaries**: "Find defects where untrusted data or callers can cause harm: missing validation, authz gaps, injection, secret exposure, unsafe defaults, trust-boundary crossings. State the attacker precondition for each."
- **State, Concurrency & Recovery**: "Two callers at once; a crash halfway; a retry after timeout. Find races, lost updates, TOCTOU, non-idempotent retries, orphaned/stuck states, forbidden state transitions. For each: the interleaving or failure sequence that triggers it."
- **Integration & Regression**: "Who calls this, what does it call, what breaks together? Find caller-contract breaks, schema/config drift, backward-compat hazards, hidden coupling. Name the affected caller/consumer for each."
- **Testability & Observability**: "When this fails in production, will anyone know? Find swallowed exceptions, silent fallbacks, misleading logs, untestable seams, failure modes with no signal. For each: how the failure would (not) surface."

(CLASSIC set prompts: unchanged from prism ≤0.1.x — Conflict / Improvement / Devil's Advocate /
Code Review / Robustness 4-axis. Keep their original wording.)

---

## Triage — candidates, not verdicts

After all agents return, parse the fenced records and group semantically overlapping findings:

- **model_agreement** = how many lenses flagged it (e.g. `3/5`). Record it; it is a
  *prioritization* signal only.
- Order the candidate list: agreements first (highest N first), then singletons by severity.
- `--quick` → stop here. Report everything as `SUSPECTED`, labeled by lens + agreement count.

There is **no auto-confirm path**. The old rule "2+ agents → CONFIRMED" is retired: same-model
agreement caps confidence at MEDIUM (see Confidence below) until evidence raises it.

---

## Pass 2 — Evidence & verification (default)

**One Evidence Agent handles ALL candidates in a single batched call.** It has Read/Grep access
to the project.

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
> 6. You may adjust severity with one sentence of justification. Do NOT invent new findings.
> 7. For each `SUPPORTED` finding, name a `suggested_test` (test function name + one-line scenario)
>    even if reproduction is not requested — it makes the finding actionable.
>
> Output one finding record v2 (schema below) per candidate. Agreement count is given; you fill
> `evidence_strength`: NONE (nothing pinned) / WEAK (location only) / MEDIUM (location +
> execution path + quote) / STRONG (reproduced — only the reproduction pass sets this).

### Adversarial mode (`--adversarial`)

Before finalizing any `REJECTED`, the Evidence Agent must argue the reviewer's side: "what if
they're right and I'm missing context?" Only reject if the counter-argument is more specific and
better-sourced than the original claim.

---

## Pass 3 — Reproduction (`--reproduce`)

Prism stays a **pure reviewer**: the project is never modified. Reproduction happens in a
throwaway sandbox.

Selection: `SUPPORTED` findings only, CRIT/HIGH first, **max 5 per run** (cost guard; say in the
report how many were skipped and why).

Per finding:

1. **Search existing tests first** — a test that already covers the path may prove or disprove
   the claim without writing anything.
2. Detect the project's test runner (pytest / vitest / jest / `node --test` / go test / cargo
   test). No runner installable/available → `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`, move on.
3. Write a **minimal failing test** in the OS temp dir (e.g. `$TMPDIR/prism-tests/`), importing
   the target by path. Never write inside the project tree. Never `pip/npm install` into the
   project.
4. Run it with a timeout. Record the exact command and verbatim result.
5. Classify:

| reproduction.status | Meaning |
|---|---|
| `REPRODUCED` | Test failed as the claim predicts → finding status becomes `REPRODUCED` |
| `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT` | Runner/deps/fixtures unavailable here |
| `STATIC_EVIDENCE_ONLY` | Reproduction not attempted (cap, or inherently static claim) |
| `REQUIRES_EXTERNAL_SERVICE` | Needs a DB/API/queue this sandbox doesn't have |
| `REQUIRES_DOMAIN_CONFIRMATION` | Only a human can say whether this behavior is wrong |

6. **If the test passes** (bug does not manifest): that is evidence *against* the finding —
   downgrade to `SUSPECTED` or `REJECTED` and quote the passing run. A reproduction attempt that
   contradicts the claim is as valuable as one that confirms it.
7. Clean up the temp dir at the end; keep the test source **in the report** so the operator can
   promote it into the real test suite.

Never hide that reproduction didn't run: every finding's record carries `reproduction.status`,
and `STATIC_EVIDENCE_ONLY` is an honest, common value.

---

## Finding record v2 (required for every reported finding)

```yaml
id: PRISM-001                    # sequential per run
fingerprint: a3f92c1e            # sha1("<file>|<symbol>|<category>")[:8] — stable across runs, for dedup
file: src/auth.py
lines: 84-102
symbol: reset_password
category: security              # correctness|security|state|integration|testability|improvement
severity: HIGH
status: SUPPORTED               # SUSPECTED|SUPPORTED|REPRODUCED|REJECTED

claim: "Reset token can be reused"
preconditions:
  - "Attacker has a previously used reset token"
execution_path:
  - reset_password()
  - token lookup
  - password update
  - token is not invalidated
evidence:
  - "src/auth.py:98 — token record remains active after successful update"

reproduction:
  status: NOT_RUN               # NOT_RUN|REPRODUCED|NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT|STATIC_EVIDENCE_ONLY|REQUIRES_EXTERNAL_SERVICE|REQUIRES_DOMAIN_CONFIRMATION
  suggested_test: test_reset_token_cannot_be_reused
  command: null                 # exact command when run
  result: null                  # verbatim tail when run

confidence:
  model_agreement: "3/5"
  evidence_strength: MEDIUM     # NONE|WEAK|MEDIUM|STRONG
  label: HIGH                   # from the confidence table below
```

Field rules: `file/lines/symbol` are **required** for `SUPPORTED`+ (a finding without a location
cannot be SUPPORTED). `evidence` requires ≥1 quoted line for SUPPORTED. `SUSPECTED` findings may
have `file: null` but must then carry a `missing:` note explaining what prevented grounding.

## Confidence

```
confidence = f( model_agreement, lens_diversity, evidence_strength, reproduction )
             − missing_context − unverifiable_assumptions
```

| Signal combination | Label |
|---|---|
| Single lens, no evidence | LOW |
| 2+ same-model lenses agree, no evidence | MEDIUM (hard cap — same model repeats the same misunderstanding) |
| Location + execution path + quote (any agreement) | HIGH |
| Failing test reproduced | VERY HIGH |
| Evidence pass found contradicting code | REJECTED (report in its own section) |

Cross-model agreement is not available in single-engine prism — `/prism-all` adds it (same-model
MEDIUM cap becomes MEDIUM-HIGH for cross-model agreement, before evidence).

---

## Final report

```
PRISM REPORT — {target} — {timestamp}
Mode: {verify | quick | adversarial} [+reproduce] [diff <range>]
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

With `--format json`, also write `prism-report.json`:
`{ "meta": {target, mode, lenses, timestamp, counts}, "findings": [<record v2>...] }` — fingerprints
let CI or a future GitHub Action dedup findings across runs. (SARIF output: roadmap, not yet.)

---

## Rules

- Each Pass 1 agent runs with `context: fork`; launch all in one message (parallel).
- Pass full target content to each agent. Never summarize the input.
- **Never modify the target project.** Reproduction tests live in the OS temp dir and are torn down.
- The Evidence Agent runs in a **single batched call** for all candidates.
- Contradicting lenses → surface both under the relevant finding; the Evidence pass picks a side
  only with quoted evidence.
- Keep synthesis concise: the YAML record carries the detail; prose stays ≤3 lines per finding.

## Cost & speed

| Mode | Discovery | Evidence | Repro | Relative cost |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 0 | 1.0× |
| default | 5 | 1 (batched) | 0 | 1.3–1.5× |
| `--reproduce` | 5 | 1 | ≤5 test runs | 1.6–2.2× |

Default includes the evidence pass because ungrounded findings are the #1 failure mode of
multi-agent review — and a batched evidence call is cheap relative to the trust it buys.

## Companion skills

- **prism-all** — adds a Codex engine: cross-model agreement + the same evidence ladder.
- **mangchi** — after prism identifies weak files, iteratively harden them (prism finds, mangchi fixes).
- **triad** — 3-perspective deliberation for markdown/specs.
- **prism-devil** — single-agent red-team probe for security-sensitive targets.
