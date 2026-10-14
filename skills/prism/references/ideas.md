# Idea pass (prism-ideas)

Canonical copy lives in `prism-all/references/`; synced byte-identical to `prism` and `prism-codex`
by `skills/sync-review-parsers.sh`. Design and decisions: `docs/design/prism-ideas.md` in the prism
repository.

prism's defect lenses answer "is this wrong?". The idea pass answers "what should we do instead?"
and grades the answers. It runs after the Evidence pass (Pass 4) when prism runs it as a companion,
or alone as `/prism-ideas`. Ideas never mix with defects: separate report section, separate JSON
array, never in defect counts, the action order, degraded angles or a gate.

Two output formats belong to this pass. Each lives in exactly one file, and that file is appended
**verbatim and last** to every prompt that needs it, for both engines:

| Step | Output fence | Contract file |
|---|---|---|
| Propose | `<<<PRISM-IDEAS v1>>>` | `templates/ideas-contract.md` |
| Check | `<<<PRISM-IDEA-CHECK v1>>>` | `templates/idea-check-contract.md` |

Never restate either format in a prompt or in this file; `verify-ideas.js --selftest` fails if a
contract file is missing or stops naming a field or value the script enforces.

## 4a. Propose

One idea agent per engine runs all three lenses, so the target travels once per engine. Assemble
its prompt in this order (identical for Claude and Codex; Codex additionally gets its sandbox
preamble first):

1. **Target content**, verbatim (the same prefix the discovery lenses got).
2. **FINDINGS** (companion mode only): every `SUPPORTED` / `REPRODUCED` record from `checked.json`,
   one line each: `PRISM-NNN | STATUS | SEV | file:lines | claim`. Standalone mode has none.
3. **CONTEXT** files (`--context`), each headed `CONTEXT: <name as given>`. Data an idea needs as
   ground (exported sheets, logs, measurements) must arrive this way so its quote can be checked.
4. **The idea prompt** below.
5. **`templates/ideas-contract.md`**, appended last.

Idea prompt:

> You propose alternatives; you do not look for bugs. The findings above, and the target itself,
> show real problems. For each lens below, propose at most 3 ideas that would solve a real problem
> better than patching it, best first. Every idea must point at its problem through `grounds`: a
> finding ID from FINDINGS, or a verbatim quote from the repository or a CONTEXT file. An idea you
> cannot ground is discarded, so do not propose it.
>
> - **class (fix the class):** several problems share a cause. What structural change removes the
>   whole class instead of patching each instance? Example: rules that live only in prompt text
>   move into a script that enforces them.
> - **route (a different route):** another mechanism that reaches the same goal and sidesteps the
>   problem. Example: keyword scoring under-rates good matches, so pre-judge from the posting body
>   first and score second.
> - **subtract (remove or reuse):** what can be deleted, merged, or replaced by something that
>   already exists? Name the existing thing with `path:lines` and quote it. Search the repository
>   before claiming something does or does not exist.
>
> For each idea fill the rubric honestly: the problem it solves, what it replaces (`none` if it only
> adds), cost, expected effect and how you would know it worked, and the risk with its mitigation.

## 4b. Gate (script)

```
node "<skill dir>/verify-ideas.js" gate <proposer-out> <claude|codex> <repo-root> \
     [--findings checked.json] [--context <file>]... > <engine>.gated.json
```

Enforced in code: the richest `PRISM-IDEAS v1` fence wins (ties go to the last fence, so an echoed
example cannot beat the real answer); JSON shape, enums, lengths and placeholder values; the first 3
format-valid ideas per lens are kept and later ones are `OVER_CAP`; every ground is checked (finding
must be `SUPPORTED`/`REPRODUCED` in `checked.json`; a quote must sit at the cited lines of a file
under the repo root or a `--context` file, span ≤ 40 lines, ≥ 8 characters, no credential files); no
valid ground, or a `problem` that names an unverified finding, makes the idea `UNGROUNDED`. Status
per idea: `GATED` / `UNGROUNDED` / `OVER_CAP` / `INVALID`. No fence, or fences with only garbage,
gives `degraded: true` (infra, not an idea).

Keys are `<engine>-<n>` in emission order (`claude-2`). They are what the checker answers to.

## 4c. Check

An independent checker rates every `GATED` idea. It sees the ideas (key, lens, title, problem,
grounds, proposal, replaces, cost, effect, risk) and has Read/Grep/Glob on the repository, but not
the proposer's reasoning. Batches of at most 8 ideas per call. Append
`templates/idea-check-contract.md` last.

Who checks: in `/prism` and `/prism-codex`, a separate agent of the same engine. In `/prism-all`,
the other engine (Codex checks Claude's ideas, Claude checks Codex's); ideas grouped as cross-model
before checking are checked once, by the `--verifier` engine.

Checker prompt:

> You are the **Idea Checker**. Proposers produced the ideas below. Judge each one; do not improve
> it and do not add ideas.
>
> 1. Does the proposal actually address the problem its grounds point at?
> 2. Does something in the repository already do this, or conflict with it? Search before you claim
>    either, and quote what you found.
> 3. Are the cost and the risk honest? Correct the cost only if it is clearly wrong.
> 4. Give the verdict.

```
node "<skill dir>/verify-ideas.js" check <engine>.gated.json <checker-out> <repo-root> \
     [--also <checker-out>]... [--context <file>]... > <engine>.checked-ideas.json
```

Enforced in code: the last verdict per key wins across all `PRISM-IDEA-CHECK v1` fences (batches may
be concatenated or passed with `--also`); a `DROP` with basis `exists`/`conflicts` whose quote does
not verify becomes `WEAK` (note `DROP_QUOTE_UNVERIFIED`); an unanswered key becomes `UNCHECKED`;
unknown keys are ignored and counted.

## 4d. Group and rank

Grouping is semantic, so the main agent does it: ideas that propose the same change are written to a
groups file as explicit key lists, `[["claude-2","codex-1"], ...]`. The script never guesses a
group, and `cross_model` is set only for a group whose `GATED` members come from two engines.

```
node "<skill dir>/verify-ideas.js" rank <engine>.checked-ideas.json... [--groups groups.json] > ideas.json
```

A group's verdict is the worst verdict among its checked members (`UNCHECKED` members are ignored
unless none was checked), so agreement never overrides a checker's finding. `DROP` entries go to
`dropped`; everything else is ordered by: `KEEP` before `WEAK` before `UNCHECKED` → cross-model
before single → replaces something before additive (`replaces: none`) → cost `S` < `M` < `L` (the
checker's corrected cost when given) → ground strength `REPRODUCED` > `SUPPORTED` > quote only →
title, engine, key. The order depends only on content, never on input order. Entries get `IDEA-n`.
`ideas.json` also carries `meta` (proposed, grounded, keep, weak, drop, unchecked, ungrounded,
over_cap, invalid, bad_lines, merged_away, engines, degraded engines) for `meta.ideas` in the report.

## Report section

```
## IDEAS (alternatives, not defects; not in the action order)
Ideas: 14 proposed -> 9 grounded -> 6 keep, 2 weak, 1 drop  (ungrounded 3, over cap 2)
- IDEA-1 [cross-model | route | cost M | KEEP] <title>
  problem: <problem> · replaces: <replaces> · effect: <effect> · risk: <risk>
  grounds: PRISM-004 (SUPPORTED), <path>:<lines> — "<quote>"
```

Certainty language follows the verdict: `KEEP` "worth doing", `WEAK` "worth a look", `UNCHECKED`
"not checked".
