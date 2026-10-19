# prism

> Language: **English** · [한국어](README.ko.md)

**Five defect lenses discover in parallel — then every finding must be pinned to code before it's called real.**

"Multiple AI reviewers agreed" is not evidence: all five prism agents run on the same model, and same-model agents can share the same misunderstanding. So in prism, **agreement decides what gets investigated first; evidence decides what survives.** Every candidate goes through an Evidence pass that pins `file:lines@symbol`, traces the execution path, and quotes the line that makes the claim true. With `--reproduce`, prism goes one step further and demonstrates the failure with a throwaway test.

```
/prism <target>                        -> discovery (5 lenses) + Evidence pass + idea pass
/prism <target> --reproduce            -> + minimal failing tests in a temp dir (never your project)
/prism --diff main...HEAD              -> review the CHANGE: what regression does this diff introduce?
/prism <target> --quick                -> discovery only (everything reported as SUSPECTED)
/prism <target> --adversarial          -> Evidence pass argues against its own REJECTs
/prism <target> --redteam              -> + attacker-mindset Red Team lens (absorbed prism-devil)
/prism <target> --no-ideas             -> skip the idea pass (grounded alternatives)
/prism <target> --format json          -> machine-readable prism-report.json (finding records v2)
/prism-ideas <target>                  -> alternatives only, no review (Claude + Codex cross-checked)
```

Every finding carries a status on the evidence ladder:

| Status | Meaning |
|---|---|
| `SUSPECTED` | agent reasoning only |
| `SUPPORTED` | file + lines + execution path + quoted evidence |
| `REPRODUCED` | a failing test was actually run |
| `REJECTED` | contradicted — with the contradicting line quoted |

After the Evidence pass, an **idea pass** asks "what should we do instead?" and lists grounded
alternatives under their own `## IDEAS` heading: options for a person, never findings, never counted.

---

## 30-second demo

**Without prism:**

You ask Claude "review this file". It says "looks good". You ship it. Two weeks later a bug surfaces that a different review angle (say, concurrency or config conflict) would have caught immediately. But no one thought to check that angle with an independent reviewer.

**With prism:**

`/prism src/services/auth.py --reproduce`. Five defect lenses scan the file in parallel (correctness / security / state & concurrency / integration / testability). Every candidate is then grounded: exact location, execution path, quoted evidence — and the top findings get a minimal failing test written in a temp directory and actually run. The report tells you what was *demonstrated*, what has *static evidence*, what is *only suspected*, and what was *rejected with proof*.

## Who should use this

- **Before a major architectural decision** — you want 5 angles, not 1
- **Before merging a PR you're unsure about** — independent review beyond your own LLM's opinion
- **After implementing a feature** — last-line sweep for blind spots before release
- **Auditing a skill, design doc, or workflow** — the disagreement between reviewers is itself signal
- **Whenever you'd ask 5 senior engineers to look at the same thing**

## Which tool do I want? (haroom family)

| Goal | Tool |
|---|---|
| Find defects broadly, evidence-graded | **prism** (this plugin) |
| Cross-check with a second model (Claude + Codex) | `/prism-all` (ships in this plugin) |
| Grounded alternatives instead of verdicts (before a PRD, after a review) | `/prism-ideas` (ships in this plugin) |
| Security / attacker-mindset deep probe | `/prism <target> --redteam` (prism-devil was absorbed in 0.3.0) |
| Actually fix a file, iteratively | [mangchi](https://github.com/minwoo-data/mangchi) |
| Check a design doc is sound (conflicts, claims vs code, failure modes) | `/prism <doc>` (design lens set, automatic for markdown) |
| Review how a doc reads (LLM clarity / longevity / comprehension) | [triad](https://github.com/minwoo-data/triad) |
| Parallel worktree sessions with safe merge | [ddaro](https://github.com/minwoo-data/ddaro) |

---

## Quick Start

### 1. Add the haroom_plugins marketplace (one time)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git
```

`prism` is distributed through the **haroom_plugins** aggregator along with the other haroom plugins (ddaro, triad, mangchi).

### 2. Install

```
/plugin install prism
```

### 3. Use

```
/prism src/services/auth.py                 # discovery + Evidence pass + idea pass
/prism src/services/auth.py --reproduce     # + failing-test reproduction (temp dir)
/prism --diff main...HEAD                   # change-scoped: regressions this diff introduces
/prism .                                    # whole-project review
```

Restart Claude Code after install/update.

---

## Variants shipped in this plugin

Installing `prism` gives you three review skills that share the 5-angle framework but differ in who runs each agent, plus `/prism-ideas`, the idea pass on its own:

| Skill | Engine | When to use |
|---|---|---|
| `/prism` | **Claude only** — 5 agents parallel + Evidence pass | Default. Fastest wall-time, no external CLI, only variant with `--diff`. |
| `/prism-codex` | **Codex CLI only** — 5 calls + Codex Evidence pass, gpt-5.5 | Save Claude tokens, or get a different-model opinion. Requires `codex-cli >= 0.125.0`. |
| `/prism-all` | **Claude + Codex in parallel** — 10 discovery + Evidence pass | Highest confidence. Same-angle cross-model agreement gets a dedicated Tier 1. `--verifier=claude\|codex\|both` picks the adjudicator. |
| `/prism-ideas` | **Claude + Codex** (Claude-only without Codex) — propose, gate, cross-check, rank | Alternatives without a review; `--findings` reuses a run's `checked.json`. |

All four ship inside one plugin install. Pick one per run. Codex CLI prerequisite details (including the "model does not exist" error which is actually a CLI version issue): see [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md) in the sibling triad plugin.

---

## The five lenses (defect set — default for code)

| Lens | Looks for |
|---|---|
| **Correctness & Contracts** | Wrong results, boundary values, error paths, violated invariants, API contract breaks |
| **Security & Trust Boundaries** | Missing validation, authz gaps, injection, secret exposure — with the attacker precondition |
| **State, Concurrency & Recovery** | Races, lost updates, TOCTOU, non-idempotent retries, orphaned/stuck states |
| **Integration & Regression** | Caller-contract breaks, schema/config drift, backward-compat hazards, hidden coupling |
| **Testability & Observability** | Swallowed errors, silent fallbacks, lying logs, failure modes with no signal |

Optional lenses: **Red Team** (`--redteam`) — the hostile attacker-mindset probe inherited from
`prism-devil`, with project security-checklist cross-reference and attack-chain detection; its
findings go through the same Evidence pass. **Design docs, plans and specs** get the **design lens
set** instead (conflict & reuse / claim accuracy against the repo / devil's advocate / robustness of
the designed system): prism answers "is the design sound?", triad answers "is the document well
written?", and `/ddaro:review` runs both. The Improvement lens is retired (0.5.0): alternatives come
from the idea pass below, and `--include-improvements` is kept only as an alias that turns it on.

Prompts are assembled **target first, lens last**, so the shared prefix is prompt-cache friendly.

Each lens runs in a **forked context** so agents can't see each other's output — agreement stays
an independent signal, not an echo.

## How evidence grading works

After discovery, every finding is a **candidate** — nothing is auto-confirmed:

- **Agreement (2+ lenses)** sets priority and baseline confidence only. Same-model agreement is
  capped at MEDIUM confidence: five copies of the same model can share the same misunderstanding.
- **Every candidate** goes through the **Evidence pass** (chunks of ≤8, built by file): pin `file/lines/symbol`, trace
  the execution path, quote the evidence line, check the precondition. Only then:
  `SUPPORTED` / `REJECTED` (with contradicting quote) / still `SUSPECTED` (with what's missing).
- **`--reproduce`** takes SUPPORTED findings (CRIT/HIGH first, max 5) and writes a minimal failing
  test in the OS temp dir — never your project tree — runs it, and records the verbatim result.
  A test that *passes* downgrades the finding: contradiction is recorded, not hidden.

Every finding ships as a structured **record v2** — `id`, stable `fingerprint` (cross-run dedup),
`file/lines/symbol`, `category`, `severity`, `status`, `claim`, `preconditions`, `execution_path`,
`evidence`, `reproduction{status,suggested_test,command,result}`, `confidence`, plus `checklist_ref` and `chain` when a security checklist / Red Team lens is in play. Schema: `skills/prism/references/record-v2.md`.

## The idea pass (Pass 4)

Lenses ask "is this wrong?"; the idea pass asks "what should we do instead?". After the Evidence
pass, a proposer reads the same target plus the machine-checked findings and offers at most 3
alternatives per idea lens: **class** (fix the whole class of problem), **route** (a different
approach), **subtract** (remove or reuse something). Every idea must cite a ground a script can
check: a `SUPPORTED`/`REPRODUCED` finding ID, or a `file:lines — quote` that really sits at those
lines. `verify-ideas.js` drops ungrounded ideas; nobody judges them by feel. A checker that did not
write the idea (in `/prism-all`, the other engine) rules KEEP / WEAK / DROP, and a DROP needs a
verified quote. The report lists ideas under `## IDEAS`, apart from findings: never counted, never
in the action order, never a gate. `--no-ideas` or `--quick` turns the pass off; `/prism-ideas`
runs it alone.

## Features

- **Parallel discovery** — 5 lenses fire in a single tool call; wall-time ≈ the slowest one.
- **Evidence over agreement** — confirmation requires location + execution path + quote, never vote count.
- **Reproduction sandbox** — failing tests demonstrate bugs without touching your project; "we didn't run it" is always stated (`STATIC_EVIDENCE_ONLY`, `REQUIRES_EXTERNAL_SERVICE`, ...).
- **Change-scoped mode** — `--diff` reviews what a change breaks, not whether the codebase is nice.
- **Chunked Evidence pass** — ≤8 candidates per call, grouped by file so each file is read once per chunk; a failed chunk downgrades only its own candidates.
- **Adversarial mode** — the Evidence pass argues against its own REJECTs before finalizing.
- **Red Team lens** — `--redteam` adds a deliberately hostile 6th agent; findings are cross-referenced to your project's security checklist and composed into attack chains.
- **Idea pass** — grounded alternatives after the review, cross-checked and kept apart from findings (`--no-ideas` to skip).
- **Code never modified** — prism is a pure reviewer. Use `/mangchi` to actually change code.

---

## Modes and output

```
/prism src/services/auth.py                 # default: discovery + Evidence pass + idea pass
/prism src/services/auth.py --quick         # discovery only (all SUSPECTED, no idea pass)
/prism src/services/auth.py --no-ideas      # defects only, no IDEAS section
/prism src/services/auth.py --adversarial   # Evidence pass argues against its own REJECTs
/prism src/services/auth.py --redteam       # + attacker-mindset lens, checklist, attack chains
/prism --diff main...HEAD                   # change-scoped review (preferred for PRs)
/prism docs/design/billing.md               # design doc → design lens set (auto)
/prism .                                    # whole-project review
```

Natural language: *"full review"*, *"red team this"*, *"prism 돌려"*.

Report shape:

```
PRISM REPORT - src/auth.py - 2026-07-14 15:30
Mode: default +reproduce · Lenses: defect · Checklist: none
Ideas: on (claude)
Candidates: 9 discovered → 4 supported, 1 reproduced, 2 rejected, 2 suspected

## REPRODUCED (demonstrated failures)
- PRISM-003 [HIGH|security] src/auth.py:84-102 reset_password — Reset token can be reused
  path: reset_password → token lookup → password update → token not invalidated
  repro: pytest /tmp/prism-tests/test_reset_reuse.py → FAILED as predicted

## SUPPORTED (code-path evidence, not executed)
- PRISM-001 [MED|state] src/auth.py:120-133 rate_limit — check-then-insert race allows overshoot
  evidence: src/auth.py:127 — count read before insert, no lock | repro: STATIC_EVIDENCE_ONLY

## SUSPECTED (needs confirmation)
- PRISM-007 — missing: REQUIRES_DOMAIN_CONFIRMATION: is 5-minute token reuse acceptable here?

## REJECTED (transparency)
- [security lens] "JWT alg confusion" — contradicting evidence: src/auth.py:41 — alg pinned to HS256

## Recommended Action Order
1. PRISM-003 (reproduced) ...

## IDEAS (alternatives, not defects; not in the action order)
Engines: claude
Ideas: 2 proposed -> 2 grounded -> 1 keep, 1 weak, 0 drop, 0 unchecked
- IDEA-1 [claude | class | cost S | KEEP: worth doing] Issue single-use reset tokens from one helper
  problem: ... · replaces: ...
  proposal: ...
  effect: ... · risk: ...
  grounds: PRISM-003 (REPRODUCED)
  check: ...
- IDEA-2 [claude | route | cost M | WEAK: worth a look] ...
```

### Gate run (`--run-tag`, for ddaro's merge gate)

```
/prism --diff <base>...<head> --lenses=defect --no-pr-body --no-ideas --run-tag <id> --head <head> --out <dir> [--blockers <dir>/blockers.json]
```

A gate run is a `--diff` review whose `prism-report.json` is assembled by a script
(`assemble-report.js`), never written by the model: `begin` checks the folder and the tree before
Pass 1, Pass 2's quotes are checked against the commit (`verify-evidence.js --rev <head>`, so a
report pins to the head it reviewed), blockers from an earlier run are re-judged as `SUPPORTED`
(still there) or `REJECTED` (fixed, with the fixing line quoted), and `finish` publishes the report
whole or not at all with the meta a gate needs (`lenses_completed`, `tree_changed`,
`candidate_ids`, `grounding_failed` per record). Contract: `references/report-contract.md`
(`report_contract` 2, read by ddaro from `skills/prism/report-contract.json`). Without `--run-tag`
nothing changes.

## Cost

| Mode | Cost | When |
|---|---|---|
| `--quick` | 1.0× | Already-triaged targets (everything SUSPECTED) |
| default | 1.3–1.6× | Standard reviews |
| `--redteam` | +0.25× | Auth / payments / PII / untrusted-input parsers |
| `--reproduce` | 1.6–2.2× | Before merging anything that matters |
| idea pass (on by default) | about +30–60 s | Off with `--no-ideas` (gates, CI) or `--quick` |

Evidence-pass cost is ⌈candidates/8⌉ calls, chunked by file. Where tokens go and how to spend
fewer: the target travels once per discovery agent (use `--diff` for PRs); every agent starts fresh
with only its prompt, never your session; parsing and quote-checking are scripts, not model calls.

---

## Example session

```
/prism src/services/auth.py
# → 5 lenses in parallel (~20-40s depending on file size)
# → Triage: 8 candidates. 3 flagged by 2+ lenses (priority), 5 singletons.
# → Evidence pass (1 chunk of 8, grouped by file): 4 SUPPORTED, 2 REJECTED, 2 SUSPECTED
# → verify-evidence.js: every SUPPORTED quote matched the cited lines
# → Final report: 4 supported + 2 suspected (as questions) + 2 rejected (shown for transparency)

# Stricter pass on a security review:
/prism src/security/ --adversarial
# → Same Pass 1. Evidence pass argues against its own REJECTs before finalizing.
# → Catches "I was about to dismiss this but actually..." cases.

# Whole-project sanity check:
/prism .
# → Target resolver picks up top-level project structure/skills/docs
```

### Pair with mangchi for iterative hardening

```
/prism src/services/auth.py           # identifies weak file
/mangchi src/services/auth.py         # iteratively harden that specific file
```

### Cross-model variant

```
/prism-all src/services/auth.py
# → Claude 5 agents + Codex CLI 5 calls, all in parallel (~100-200s)
# → Tier 1: same angle flagged by both engines → highest confidence
# → Tier 2: one engine, multiple angles
# → Tier 3: singletons — all three tiers go through the Evidence pass
# → Requires codex-cli >= 0.125.0
```

---

## Update

```
/plugin update
```

Then restart Claude Code.

---

## Troubleshooting

### `/prism` doesn't appear after install

Plugins are loaded at Claude Code startup.

1. **Restart Claude Code** — required after every install and update.
2. Run `/plugin` and confirm `prism` is listed as **enabled**.
3. If listed but disabled: `/plugin enable prism@haroom_plugins`.
4. Still missing? Check `~/.claude.json` has a `prism` entry under `enabledPlugins`. If `{}`, the install didn't complete — rerun `/plugin install prism`.

### `/prism-codex` or `/prism-all` errors with "model does not exist"

That's a Codex CLI version issue, not an account issue. Upgrade:

```
npm install -g @openai/codex@latest
codex --version   # must be >= 0.125.0
```

Full writeup: sibling `triad/docs/codex-5.4-to-5.5.md` in this marketplace.

### Too many findings / report is noisy

- Use `--quick` to skip the Evidence pass (faster, more false positives).
- Ideas are listed apart from findings and never counted; `--no-ideas` drops the IDEAS section.
- For a security-only pass, `--redteam` adds depth, not noise: its findings are evidence-checked like the rest.

---

## Requirements

- Claude Code (any version with `/plugin` command) — spawns general-purpose subagents
- Node.js on PATH (the deterministic scripts: `parse-findings.js`, `verify-evidence.js`, `verify-ideas.js`)
- *(Optional — for `/prism-codex`, `/prism-all`, and `/prism-ideas`, which runs Claude-only without it)* [Codex CLI](https://github.com/openai/codex) `>= 0.125.0`
- Works on Windows (Git Bash / WSL2), macOS, Linux

The base `/prism` runs within Claude Code plus Node.js. No external AI CLI required.

---

## When NOT to use prism

- **Tiny one-line changes** — overkill
- **Iterative file hardening** — use `/mangchi` (better tool for that loop)
- **Polishing how a document reads** — that is `/triad`; prism's design lenses check whether the design is sound, not the prose

## Philosophy

"Several AI reviewers said so" is an opinion poll. A defect report is a *claim about code*, and
claims about code can be grounded: a location, an execution path, a quoted line — ideally a test
you can watch fail. prism v0.2 treats agreement as a search heuristic and evidence as the only
currency of confirmation. The most honest sentence in a review is often
`reproduction: STATIC_EVIDENCE_ONLY` — said out loud instead of implied away.

## Updates

- **2026-10-19 (v0.6.0)** — Merge-gate support for ddaro: `/prism --run-tag` gate runs whose
  `prism-report.json` is assembled by `assemble-report.js` (contract 2,
  `references/report-contract.md`), `verify-evidence.js --rev <sha>` (quotes checked at a commit,
  `quote_lines`, REJECTED annotated). Without `--run-tag` the reviews run as in 0.5.0. Details in
  CHANGELOG.
- **2026-10-19 (v0.5.0)** — Idea pass (Pass 4) in `/prism`, `/prism-all` and `/prism-codex`: grounded
  alternatives (class / route / subtract) gated by `verify-ideas.js`, judged by a checker that did
  not write them, listed under `## IDEAS` apart from findings (`--no-ideas` to skip). New
  `/prism-ideas` runs the pass alone. The Improvement lens is retired (design set = 4 lenses). See
  CHANGELOG.
- **2026-10-14 (v0.4.2)** — `codex-run.sh` hardening from a prism-all review: no false quarantines on quoted values or placeholder fixes, more secret forms caught, scratch outside the run dir, one attempt per angle, `--strict` works from PowerShell.
- **2026-10-14 (v0.4.1)** — Codex runs in the read-only sandbox (reads only; no writes, no
  network). `PRISM_CODEX_SANDBOX=bypass` is an explicit per-run opt-out.
- **2026-10-14 (v0.4.0)** — The Codex invocation contract is a script (`codex-run.sh`): the
  safety preamble, secret scrub, output contract, timeout and effort pin are enforced by code,
  not by the model. Codex-related orchestration text per prism-all run drops from about 39 KB to
  about 2.7 KB. See CHANGELOG.
- **2026-07-14 (v0.2.0)** — Evidence over agreement: statuses SUSPECTED/SUPPORTED/REPRODUCED/REJECTED,
  mandatory Evidence pass for all candidates (same-model agreement no longer auto-confirms),
  finding records v2 with stable fingerprints, `--reproduce` (temp-dir failing tests),
  `--diff` change-scoped mode, defect-focused default lenses (`--include-improvements` opt-in),
  `--format json`. See CHANGELOG for the full list.
- **2026-04-24** — New sibling skills `/prism-codex` (Codex-only) and `/prism-all` (dual-engine) shipped. Codex CLI migration writeup in the sibling triad plugin: [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md). Read it if you hit a "model does not exist" error when first using a Codex-backed variant.

## License

MIT — see [`LICENSE`](LICENSE).

## Author

haroom — [github.com/minwoo-data](https://github.com/minwoo-data)

## Contributing

Issues and PRs welcome at [github.com/minwoo-data/prism](https://github.com/minwoo-data/prism).
