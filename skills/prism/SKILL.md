---
name: prism
description: Evidence-graded multi-angle code review — 5 defect lenses discover in parallel, then an Evidence pass pins every candidate to file/lines/execution-path before anything is confirmed. Statuses SUSPECTED → SUPPORTED → REPRODUCED. Agreement is a prioritization signal, not a verdict. --redteam adds an attacker-mindset lens (absorbed prism-devil). Code only; documents go to /triad. Use when user says "prism", "prism 돌려", "prism <file>", "full review", "red team", "what could break".
argument-hint: "[file-or-topic] [--quick] [--adversarial] [--reproduce] [--redteam] [--diff [range]] [--include-improvements] [--format json]"
context: fork
user-invocable: true
---

# Prism — Evidence-Graded Multi-Angle Review

> 5 lenses look through different facets. Nothing is "confirmed" because reviewers agreed —
> a finding is confirmed because someone **pinned it to code** (file, lines, execution path)
> and, when possible, **reproduced it with a failing test**. Agreement decides what gets
> investigated first; evidence decides what survives.

Files in this skill dir: `parse-findings.js`, `verify-evidence.js` (deterministic, load-bearing),
`references/record-v2.md` (finding schema + confidence table), `references/redteam-lens.md`,
`references/classic-lenses.md` (deprecated). Read a reference only when the step below says so.

## The evidence ladder

| Status | Meaning | Requirements |
|---|---|---|
| `SUSPECTED` | Agent reasoning only | claim + lens source |
| `SUPPORTED` | Static evidence found | file + lines + symbol + execution_path + code quote |
| `REPRODUCED` | Failure demonstrated | SUPPORTED + a failing test/command actually run |
| `REJECTED` | Contradicted or unfounded | the contradicting evidence, stated |

- **Agreement ≠ confirmation.** 2+ lenses agreeing makes a finding a *priority candidate*, never
  a confirmed defect. All prism lenses run on the same model and can share a misunderstanding.
- A finding that cannot be pinned stays `SUSPECTED`, and the report says *why*.
- Certainty language is gated by status (see `references/record-v2.md`).

## Modes

| Invocation | Behavior |
|---|---|
| `/prism <target>` | **Default: Discovery → Evidence pass.** All candidates get evidence-checked. |
| `--quick` | Discovery only. Everything reported as `SUSPECTED`. |
| `--adversarial` | Evidence pass must argue *against* its own REJECTs before finalizing. |
| `--reproduce` | + Reproduction pass: minimal failing tests in a temp dir (never the project). |
| `--redteam` | + 6th discovery agent: hostile attacker-mindset probe (`references/redteam-lens.md`). Adds ATTACK CHAINS and CHECKLIST COVERAGE to the report. |
| `--diff [base...head]` | Review **the change**, not the file. |
| `--include-improvements` | Adds the Improvement lens (labeled separately, excluded from defect counts). |
| `--format json` | Also emit `prism-report.json` (finding records v2). |
| `--lenses=classic` | **Deprecated (removal in 0.4).** Original 0.1 lens set, explicit only. Prints a warning. |

## Target resolution

- File path → review that file. Topic → locate and review relevant files. No argument → current
  project. **Always read the full target first** and pass it verbatim to each agent. No summarization.
- **Prism reviews code.** If the majority of target bytes are markdown/design/plan text (or, in
  `--diff` mode, no hunk touches a code file), **stop** and print:
  `prism is a code reviewer — for documents, plans and specs run /triad <file>.`
  Only an explicit `--lenses=classic` overrides this (deprecated path, header shows `Lenses: classic (deprecated)`).
- **Project security checklist**: before Pass 1, look for `docs/security-checklist.md` →
  `docs/security/checklist.md` → `SECURITY.md` → `docs/SECURITY.md` (first hit, ≤3 tool calls).
  If found, it is handed to the **Security** lens (and the Red Team lens under `--redteam`) only.

### `--diff` mode (change-scoped review)

Range: dirty worktree → staged+unstaged vs `HEAD`; clean → `merge-base main...HEAD` (explicit
`<range>` overrides). Collect and hand each lens: (1) changed hunks, (2) pre-change code per hunk
(`git show <base>:<file>`), (3) enclosing function/class + **up to ~5 direct callers/callees**
(capped against the prompt-size guard), (4) tests referencing changed symbols, (5) touched
schema/config/migration files, (6) PR description (`gh pr view --json title,body`).
Frame every lens with **"What regression risk does *this change* newly introduce?"** Findings must
reference a hunk; pre-existing issues go under `PRE-EXISTING (out of scope)`, max 3 lines.
(`--diff` is `/prism` only; for cross-model diff review run `/prism-all` on the collected context.)
**Prefer `--diff` for PR review** — it sends hunks + context instead of whole files five times, and
it is the only mode where the Integration lens sees real callers instead of guessing them.

---

## Lenses (DEFECT set — the default)

1. **Correctness & Contracts** — wrong results, boundary values, error/exception paths, violated invariants, API contract breaks (return shapes, nullability, units, encoding).
2. **Security & Trust Boundaries** — input validation, authn/authz, secrets handling, injection, data crossing trust boundaries, unsafe defaults. Receives the project checklist when one exists.
3. **State, Concurrency & Recovery** — races, double-submit, lost update, TOCTOU; crash/timeout mid-flight, idempotency, retry safety, rollback, orphaned state; state-machine holes.
4. **Integration & Regression** — caller/callee impact, schema/config drift, backward compatibility, hidden coupling, "works alone, breaks together".
5. **Testability & Observability** — can this failure be caught? missing test seams, swallowed errors, logs that lie, silent fallbacks, unmonitorable failure modes.

Optional: **Red Team** (`--redteam`, prompt in `references/redteam-lens.md`); **Improvement**
(`--include-improvements`, `category: improvement`, excluded from defect counts and action order).

---

## Pass 1 — Parallel discovery

Launch all agents in a **single message** with multiple Agent tool calls (forked context, so
agents cannot see each other). **Assemble every agent prompt in this order:**

1. **Target content** (verbatim; in `--diff` mode the collected diff context) — identical across
   agents, so the shared prefix is prompt-cache friendly.
2. **Lens-specific context** — only Security/Red Team get the project checklist.
3. **Lens definition** (below) and the **output contract** (last).

Output contract (every lens):

> After your reasoning, emit exactly one fenced block, as the **last** fence in the message:
> ```
> <<<PRISM-FINDINGS v1>>>
> SEV | file:lines@symbol | claim -> suggested fix
> <<<END>>>
> ```
> SEV ∈ CRIT|HIGH|MED|LOW (canonical tokens only). LOCUS as precise as you can (`file:lines@symbol`;
> a section name only when you cannot pin it) and **must not contain `|`** (replace with `/`): the
> parser splits on the first two pipes and treats the last `->` as the fix boundary. Empty block =
> this lens is clean. You produce *suspicions*; the Evidence pass does the confirming.

Lens prompts:

- **Correctness & Contracts**: "Find places where this code produces wrong results or violates its stated/implied contract. Check boundaries (empty/zero/max/unicode), error paths, invariants, return-shape and nullability promises, unit/encoding mismatches. Concrete inputs → wrong output beats abstract concern."
- **Security & Trust Boundaries**: "Find defects where untrusted data or callers can cause harm: missing validation, authz gaps, injection, secret exposure, unsafe defaults, trust-boundary crossings. State the attacker precondition for each. If a project security checklist is provided, tag each finding with the matching item (`[checklist:#N]`) or `[not-in-checklist]`."
- **State, Concurrency & Recovery**: "Two callers at once; a crash halfway; a retry after timeout. Find races, lost updates, TOCTOU, non-idempotent retries, orphaned/stuck states, forbidden state transitions. For each: the interleaving or failure sequence that triggers it."
- **Integration & Regression**: "Who calls this, what does it call, what breaks together? Find caller-contract breaks, schema/config drift, backward-compat hazards, hidden coupling. Name the affected caller/consumer for each. If caller context was not provided, say so instead of guessing."
- **Testability & Observability**: "When this fails in production, will anyone know? Find swallowed exceptions, silent fallbacks, misleading logs, untestable seams, failure modes with no signal. For each: how the failure would (not) surface."
- **Red Team** (`--redteam`): full prompt in `references/redteam-lens.md`.
- **Improvement** (`--include-improvements`): "Suggest concrete enhancements. For each: current state → proposed improvement → rationale."
- Classic set (`--lenses=classic`, deprecated): `references/classic-lenses.md`.

---

## Triage — candidates, not verdicts

Write each agent's block to a file and extract deterministically:
```
node "<this skill dir>/parse-findings.js" "<agent-out>" "<lens>" > "<agent-out>.json"
```
Then group semantically overlapping findings.

- **model_agreement** = how many lenses flagged it (`3/5`). Prioritization signal only.
- A parser `degraded:true` record is infra, not a candidate → "DEGRADED LENSES" note, excluded
  from counts and fingerprinting.
- Order: agreements first (highest N), then singletons by severity.
- `--quick` → stop here; report everything as `SUSPECTED` with lens + agreement count.
- There is **no auto-confirm path**; same-model agreement caps confidence at MEDIUM.

---

## Pass 2 — Evidence & verification (default)

The **Evidence Agent** (Agent tool with Read/Grep/Glob + the repo root — *not* a re-paste of the
target) grounds candidates in **chunks of ≤8**, one batched call per chunk.

**Chunking rule:** sort candidates by priority (agreements → CRIT/HIGH → rest), then build each
chunk **by file**: take the highest-priority unassigned candidate, pull every other unassigned
candidate from the same file (up to 8), then continue with the next file. One file is read once per
chunk instead of once per candidate. If a chunk fails or omits a candidate, **that candidate alone**
becomes `SUSPECTED (missing: EVIDENCE_PASS_FAILED)`; never re-verdict, never fail the run. A single
30-candidate call skims and rubber-stamps — the exact failure this pass exists to prevent.

Evidence Agent prompt:

> You are an **Evidence Agent**. Reviewers produced the candidate findings below. Ground each one
> in the actual code — or kill it. Never take a reviewer's word; **read the file for every quote**
> (quotes are machine-checked afterward; a fabricated one is downgraded).
>
> 1. **Pin the location**: exact `file`, `lines`, `symbol`. Cannot locate → stays `SUSPECTED`, record what was missing.
> 2. **Trace the execution path**: ordered call/branch steps from entry to defect.
> 3. **Quote the evidence**: the line(s) that make the claim true, as `file:line — quote`.
> 4. **Check the precondition**: if impossible in this codebase → `REJECTED` with the contradicting quote.
> 5. **Verdict**: `SUPPORTED` (1–3 all present) / `REJECTED` / `SUSPECTED` (cannot pin or needs domain knowledge — name it, e.g. `REQUIRES_DOMAIN_CONFIRMATION: <question>`). Location pinned but path/quote incomplete → `SUSPECTED` + `evidence_strength: WEAK` + `missing:`.
> 6. You may adjust severity with one sentence. Do NOT invent new findings.
> 7. For each `SUPPORTED`: name a `suggested_test` (function name + one-line scenario).
> 8. If two or more candidates compose into a worse outcome, give them the same `chain` id.
>
> Emit one finding record v2 per candidate, one JSON object per line, inside a single fence:
> ```
> <<<PRISM-RECORDS v2>>>
> {"id":"PRISM-001","candidate_id":"c1","file":"src/auth.py","lines":"84-102",...}
> <<<END>>>
> ```
> Schema: `references/record-v2.md`. You fill `evidence_strength`: NONE / WEAK / MEDIUM (STRONG is set only by Pass 3).

**Machine check (invariant):** parse the v2 records to JSON, then
```
node "<this skill dir>/verify-evidence.js" records.json "<repo-root>" > checked.json
```
It greps every `SUPPORTED`/`REPRODUCED` quote against the cited file+lines (mismatch →
`SUSPECTED (EVIDENCE_QUOTE_MISMATCH)`) and computes `fingerprint`. **`checked.json` is the source
of truth.** Self-check: `node verify-evidence.js --selftest`.

**`--adversarial`:** before finalizing any `REJECTED`, argue the reviewer's side; reject only if the
counter-argument is more specific and better-sourced than the claim.

---

## Pass 3 — Reproduction (`--reproduce`)

Prism stays a **pure reviewer**: the project is never modified. Actor: the main agent (or a
Reproduction Agent with Bash) — the Evidence Agent never executes code. Selection: machine-verified
`SUPPORTED` only, CRIT/HIGH first, **max 5 per run** (report how many were skipped and why).

> ⚠️ **"Temp dir" is a write guard, not an execution sandbox.** Importing the target runs its
> module-level side effects with the operator's environment. Every reproduction command MUST run
> with a **stripped env** (`env -i` + allowlist: PATH, language runtime, `HOME` if required),
> **cwd = the temp dir**, **no network** where the runner supports it, **install nothing** (runners
> already on PATH only), ask the operator to **confirm once** before the first execution, and pass
> output through a secret scrub before it enters the report.

1. **Search existing tests first** — run isolated, compare against a baseline run.
2. Detect a runner **already on PATH** (pytest / vitest / jest / `node --test` / go test / cargo test). None → `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT`.
3. Write a **minimal failing test** in `${TMPDIR:-${TEMP:-/tmp}}/prism-tests/` (prefer `mktemp -d`), importing the target by path. Never inside the project tree.
4. **Pre-register the expected failure signature** in the record before running.
5. Run with a **per-test 60s timeout** (5 min total); record exit code, duration, verbatim tail. Require **2 consecutive identical outcomes**.
6. Classify `reproduction.status`: `REPRODUCED` (signature match, twice) / `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT` (incl. any setup/import/fixture error — a non-matching red is NOT a reproduction) / `TIMED_OUT` (never auto-upgrades) / `STATIC_EVIDENCE_ONLY` / `REQUIRES_EXTERNAL_SERVICE` / `REQUIRES_DOMAIN_CONFIRMATION`.
7. **Self-written test passes** → downgrade **at most to `SUSPECTED`**, only if it exercised the claimed preconditions+path; otherwise keep `SUPPORTED` with `NOT_REPRODUCED_BY_ATTEMPT`. Quote the passing run either way.
8. Clean up the temp dir (preserve sanitized markers on a scrub event); keep the test source in the report and JSON.

Every record carries `reproduction.status`; `STATIC_EVIDENCE_ONLY` / `NOT_RUN` are honest values.

---

## Final report

```
PRISM REPORT — {target} — {timestamp}
Mode: {default | quick | adversarial} [+reproduce] [+redteam] [diff <range>]
Lenses: defect {+redteam} {+improvements} | classic (deprecated)
Checklist: {path | none}
Candidates: N discovered → S supported, R reproduced, X rejected, U suspected

## REPRODUCED (demonstrated failures)
- PRISM-003 [HIGH|security|VERY-HIGH] src/auth.py:84-102 reset_password — Reset token can be reused
  path: ... | repro: <command> → FAILED as predicted | fix: ...

## SUPPORTED (code-path evidence, not executed — quotes machine-verified)
- PRISM-001 [...] file:lines@symbol — claim
  [3/5] evidence: file:line — quote | repro: STATIC_EVIDENCE_ONLY | suggested_test: ... | checklist: #14

## SUSPECTED (needs confirmation — reasoning only)
- PRISM-007 [...] — claim — missing: REQUIRES_DOMAIN_CONFIRMATION: <question for the operator>

## REJECTED (transparency)
- [lens] claim — contradicting evidence: file:line — quote

## ATTACK CHAINS (only with --redteam, or when the Evidence pass linked findings)
- CHAIN-1: PRISM-002 + PRISM-005 → account takeover (ID leak + missing authz)

## CHECKLIST COVERAGE (only when a project checklist was loaded)
- [ACTIVE] #14 verified-clean · #21 finding:PRISM-001 · #30 not-probed (out of scope)
- [N/A] #41 "no payments" — re-activated? this file now calls Stripe

## IMPROVEMENTS (only with --include-improvements)
## DEGRADED LENSES (infra — not findings)
## PRE-EXISTING, OUT OF SCOPE (only in --diff mode, max 3 lines)

## Recommended Action Order
1. REPRODUCED first, then SUPPORTED by severity (chains before singletons). SUSPECTED items appear as questions, not tasks.
```

Record schema, field rules and the confidence table: `references/record-v2.md`.

With `--format json`, write `prism-report.json` to the run's artifacts dir
(`${TMPDIR:-${TEMP:-/tmp}}/prism/<slug>-<run-id>/`, or `--artifacts=docs` — never the project
root). Write to a temp file, validate, atomic-rename; on failure emit the JSON inline with a
`json_output: failed` warning. `{ "meta": {target, mode, lenses, engines, checklist, timestamp,
counts}, "findings": [<record v2>...] }`. Fingerprints let CI dedup across runs (link only; never
suppress a prior REJECTED).

---

## Rules

- Each Pass 1 agent runs forked; launch all in one message. Target content first, lens last.
- Pass full target content. Never summarize the input.
- **Never modify the target project.** Reproduction runs in a temp dir with a stripped env.
- Evidence chunks ≤8, grouped by file; every quote machine-checked before it ships as SUPPORTED.
- Status is per-run truth; IDs are run-scoped; dedup across runs by fingerprint only.
- Contradicting lenses → surface both; the Evidence pass picks a side only with quoted evidence.
- Prose ≤3 lines per finding; the record carries the detail.

## Cost & speed

| Mode | Discovery | Evidence | Repro | Relative cost |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 0 | 1.0× |
| default | 5 | ⌈candidates/8⌉ chunked | 0 | 1.3–1.6× |
| `--redteam` | 6 | ⌈candidates/8⌉ | — | +0.25× |
| `--reproduce` | 5 | ⌈candidates/8⌉ | ≤5 test runs | 1.6–2.2× |
| `--include-improvements` | 6 | ⌈candidates/8⌉ | — | +0.2× |

**Where the tokens go, and how to spend fewer:** (a) the target is sent once per discovery agent —
use `--diff` for PR review so hunks+context travel instead of whole files; (b) this skill runs in a
**forked context**, so invoking it at the end of a long session copies that session once before the
agents spawn — run prism early, or in a fresh session; (c) the Evidence pass re-reads files — the
by-file chunking above keeps each read to once per chunk; (d) parsing and quote-checking are done
by scripts, never by the model.

## Companion skills

- **prism-all** / **prism-codex** — ship in this plugin: Codex engine for cross-model agreement (same ladder, same records).
- **mangchi** — after prism identifies weak files, iteratively harden them (prism finds, mangchi fixes). Separate plugin.
- **triad** — 3-perspective deliberation for markdown/specs/plans. Documents go there, not here. Separate plugin.
- **prism-devil** — retired; absorbed as `--redteam` (0.3.0).
