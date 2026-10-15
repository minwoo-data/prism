# Design lens set (`--lenses=design`, auto for documents)

Canonical copy lives in `prism-all/references/`; synced byte-identical to `prism` and `prism-codex`.

## What this set is for

A design doc, PRD, plan or spec can be reviewed on two independent questions:

| Question | Tool |
|---|---|
| Is the **design sound**? Does it conflict with what exists, fail under load or partial failure, make false claims about the current code? | **prism, design lens set** (this file) |
| Is the **document well written**? Will a future LLM act on it correctly, will it age well, can a newcomer get it in 5 minutes? | **triad** (LLM clarity / architecture longevity / end-user comprehension) |

`/ddaro:review` runs both on the same design doc (4 + 3 agents, then prism's idea pass). Run either
alone when only one question matters.

The set is selected automatically when the majority of target bytes are markdown/design/plan
text; `--lenses=design` forces it. `--lenses=classic` is accepted as an alias (it was the 0.1–0.3.0
name of this set) and the header always prints `design`.

History: in 0.3.0 prism refused documents and deprecated this set. That broke `/ddaro:review`,
which depends on these angles for design docs, so 0.3.1 restored it as a first-class set and
replaced the old "Code Review" angle (which duplicated triad's LLM-clarity lens) with **Claim
Accuracy**.

## Lens prompts

The set is 4 lenses. Every lens gets the same output contract as the defect lenses (`<<<PRISM-FINDINGS v1>>>`, SEV ∈
CRIT|HIGH|MED|LOW, pipe-free LOCUS, real block as the last fence). LOCUS for a design finding is
`<doc>:<lines>@<section heading>`, or the repository `file:lines@symbol` when the finding is about
existing code.

1. **Conflict & Reuse** — "Find where this design conflicts with what already exists: duplicated
   capabilities (something in the repo already does this — name it so it can be reused), config or
   schema contradictions, tool-chain conflicts, two components of the design that disagree, edge
   cases where the plan and the current system behave differently. Search the repository before
   claiming something does or does not exist."
2. **Claim Accuracy** — "Every statement the document makes about the *current* system is a claim
   to verify: `file:line` references, 'X already does Y', reuse-inventory rows, schema/field names,
   config keys, command names, numbers. Open the referenced files (Read/Grep) and flag each claim
   that is wrong, stale or unverifiable. Quote the actual repository line next to the doc's claim.
   Do not review the writing style — that is triad's job."
3. **Devil's Advocate** — "Find weaknesses and reasons this design might not work: practical
   failure modes, self-evaluation bias, gaming/Goodhart risk, cost and time, false confidence,
   scope creep, regression risk to existing behavior. Give each a concrete mitigation."
4. **Robustness (4-axis)** — "Evaluate the *designed system* on 4 orthogonal failure axes with
   concrete scenarios (N/A + reason if none): (1) Concurrency — races, double-submit, lost update,
   TOCTOU; (2) Failure & Recovery — mid-flight crash/timeout, idempotency, retry safety, rollback,
   orphaned state; (3) Data Integrity — FK cascade direction, unique/CHECK constraints, upsert vs
   replace, schema/version mismatch, migration path; (4) State Transitions — every reachable state,
   forbidden/terminal/re-entry transitions."

The fifth slot (Improvement) is retired in 0.5.0. Alternatives to the design now come from the idea
pass (Pass 4, `references/ideas.md`), which also runs on design targets: its ideas are grounded,
checked by a second engine or agent, and kept out of the defect sections.

The **Red Team** lens (`--redteam`) can be added to a design review the same way as to a code
review — useful for an auth/payments/PII design before any code exists.

## Category mapping (record v2)

conflict→integration, claim-accuracy→correctness, devil→correctness, robustness→state. (Old
`code-review` findings from ≤0.3.0 reports map to correctness; `improvement` records from ≤0.4
reports have no 0.5 category.)

## Evidence and confidence on a design target

- A finding whose evidence is a quote **from the document itself** is capped at confidence MEDIUM:
  every discovery agent already read the whole doc, so re-quoting it is not independent grounding.
- A **Claim Accuracy** (or Conflict & Reuse) finding whose evidence quotes **repository code** — a
  file other than the target doc — is graded exactly like a code finding. `verify-evidence.js`
  checks those quotes against the cited file and lines, so "the doc says X, the code says Y" can
  reach `SUPPORTED` / HIGH.
- `--reproduce` does not apply to design findings (there is nothing to execute yet); they report
  `reproduction.status: STATIC_EVIDENCE_ONLY`.
