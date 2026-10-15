# Idea pass (prism-ideas)

Canonical copy lives in `prism-all/references/`; synced byte-identical to `prism` and `prism-codex`
by `skills/sync-review-parsers.sh`.

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
contract file is missing or stops naming a field, value or limit the script enforces.

## Findings the pass may cite

`--findings` is the **final** `checked.json` of the run, the one the defect report is built from.
Without `--reproduce` that is the Pass 2 output. With `--reproduce`, Pass 3 changes statuses (to
`REPRODUCED`, or down to `SUSPECTED`), so run `verify-evidence.js` again on the post-Pass-3 records
first; otherwise `REPRODUCED` never reaches the idea pass and a refuted finding still grounds ideas.
Only records that `verify-evidence.js` quote-checked count (`_evidence_check.quote_found`), so the
pre-check `records.json` grounds nothing. A file of the wrong shape is a usage error; duplicate IDs
ground nothing.

## 4a. Propose

One idea agent per engine runs all three lenses, so the target travels once per engine. Assemble
its prompt in this order (identical for Claude and Codex; Codex additionally gets its sandbox
preamble first):

1. **Target content**, verbatim (the same prefix the discovery lenses got).
2. **FINDINGS** (companion mode only): every `SUPPORTED` / `REPRODUCED` record of the final
   `checked.json`, one line each: `PRISM-NNN | STATUS | SEV | file:lines | claim`. Standalone mode
   has none.
3. **CONTEXT** files (`--context`), each headed `CONTEXT: <name as given>`. Data an idea needs as
   ground (exported sheets, logs, measurements) must arrive this way so its quote can be checked. A
   target that lives **outside the repository root** (another drive, a temp diff-context file) is
   passed as `--context` too; otherwise every quote of it is `PATH_OUTSIDE_ROOT`.
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
>   problem. Example: a loop that re-reads a whole file every second to notice changes is replaced
>   by a change event.
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

Enforced in code:
- **Which fence:** the last closed `PRISM-IDEAS v1` fence. Only an echoed contract example is
  skipped: a fence whose every line still has the template placeholder in `lens`. A draft or planted
  fence earlier in the output never wins, even when the last fence is invalid (then the engine is
  `degraded` and the last fence's lines are listed as `INVALID`). An empty final fence means "no
  ideas" (`clean`). A final fence cut off before `<<<END>>>` is no answer (`degraded`).
- **Shape:** JSON shape, enums, lengths, placeholder values; every text flattened to one line (no
  control, line-break or bidi characters); a text field holding something secret-shaped (including
  an unquoted `.env`-style `KEY=value` with letters and digits) makes the idea `INVALID`.
- **Cap:** the first 3 format-valid ideas per lens are kept, later ones are `OVER_CAP`.
- **Grounds:** a finding must be machine-checked `SUPPORTED`/`REPRODUCED` (see above). A quote must
  sit at the cited lines (±2) of a file under the repo root or a `--context` file, span ≤ 40 lines,
  be ≥ 8 characters, and is refused for network paths, credential files (the same globs
  `codex-run.sh` refuses, checked on the real path), `.git`/`.hg`/`.svn` internals and
  secret-shaped text: a known token format, credentials in a URL, or a secret-named key with a
  quoted literal (an unquoted value is code that only names a secret, and a local test DSN whose
  user and password are the same word is fine). A quote is matched against every file its path can mean (a `--context`
  file named that way and the repo file), so neither shadows the other; a `--context` basename
  counts only when nothing else matched.
- No valid ground, or a `problem` that names an unverified finding, makes the idea `UNGROUNDED`.
- The text of a failed ground is never kept: only `path:lines` and the reason.
- Status per idea: `GATED` / `UNGROUNDED` / `OVER_CAP` / `INVALID`. No fence, or no fence with a
  valid line, gives `degraded: true` (infra, not an idea).
- The output records the resolved repo root; `check` refuses a different one.

Keys are `<engine>-<n>-<hash>` (`claude-2-3f9a`): emission order plus a hash of the idea's lens,
title and proposal. A verdict or group written for another gate run does not match and is counted
as an unknown key instead of landing on a different idea.

## 4c. Check

An independent checker rates every `GATED` idea. It sees the ideas (key, lens, title, problem,
verified grounds, proposal, replaces, cost, effect, risk) and has Read/Grep/Glob on the repository,
but not the proposer's reasoning. Batches of at most 8 ideas per call. Append
`templates/idea-check-contract.md` last.

Who checks: in `/prism` and `/prism-codex`, a separate agent of the same engine. In `/prism-all`,
the other engine (Codex checks Claude's ideas, Claude checks Codex's). Every idea is checked once;
grouping comes after the check (4d).

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
node "<skill dir>/verify-ideas.js" check <engine>.gated.json <batch-1-out> <repo-root> \
     [--also <batch-2-out>]... [--context <file>]... > <engine>.checked-ideas.json
```

Enforced in code:
- The input must be the gate output; a re-check starts again from `gated.json` with every batch.
- One checker output per batch file. In each, the last closed `PRISM-IDEA-CHECK v1` fence counts
  (echoed examples skipped, as in 4b); within it the last line for a key wins. An empty or cut-off
  final fence answers nothing.
- A `DROP` stands only on a quote that verifies, unless its basis is `not-solving`; otherwise it
  becomes `WEAK` (note `DROP_QUOTE_UNVERIFIED`). A failed quote's text is never kept.
- An unanswered key becomes `UNCHECKED` (note `NO_VERDICT`, or `VERDICT_REJECTED:<reason>` when its
  line broke the contract). Unknown keys are ignored and counted.
- If two batch files answer the same key differently, the stricter verdict stands
  (`CHECKERS_DISAGREE`).
- A batch file without a usable answer (a `[fallback: ...]` marker, no fence, an empty fence,
  only rejected lines) is a failed batch, counted in `failed_batches` with its reason.
  `check.degraded` means no GATED key was answered, `check.partial` that some were not. A retry
  that answers the failed batch's keys clears both (pass the retry's file; keeping the failed one
  next to it is harmless). Nothing GATED means neither.
- An unreadable input file is a usage error (exit 2), never an empty answer.

## 4d. Group and rank

Grouping is semantic, so the main agent does it: ideas that propose the same change are written to a
groups file as explicit key lists, `[["claude-2-3f9a","codex-1-0b7e"], ...]`. The script never
guesses a group, and `cross_model` is set only for a group whose `GATED` members come from two
engines.

```
node "<skill dir>/verify-ideas.js" rank <engine>.checked-ideas.json... [--groups groups.json] > ideas.json
```

`rank` takes check outputs; a gate output is accepted only when it has nothing to check (an engine
that degraded or proposed nothing). A group's verdict is the worst verdict among its checked members
(`UNCHECKED` members are ignored unless none was checked), so agreement never overrides a checker's
finding. `DROP` entries go to `dropped`; everything else is ordered by: `KEEP` before `WEAK` before
`UNCHECKED` → cross-model before single → replaces something before additive (`replaces: none`) →
cost `S` < `M` < `L` (the checker's corrected cost when given) → ground strength `REPRODUCED` >
`SUPPORTED` > quote only → title, engine, key. The order depends only on content, never on input
order. Entries get `IDEA-n` and carry `grounds_failed` (how many of their grounds failed).

`ideas.json` also carries `meta` for `meta.ideas` in the report: `proposed`, `grounded`, `keep`,
`weak`, `drop`, `unchecked`, `merged_away`, `ungrounded`, `over_cap`, `invalid`, `bad_lines`,
`overflow`, `unclosed`, `engines`, `degraded_engines` (proposer failed), `check_degraded` (checker
answered nothing), `check_partial` (a batch failed or keys went unanswered) and `check` (the
checkers' failed batches, rejected lines, unknown and repeated keys, disagreements). Identity:
`grounded = keep + weak + drop + unchecked + merged_away`.

## Report section

```
## IDEAS (alternatives, not defects; not in the action order)
Ideas: 14 proposed -> 9 grounded -> 5 keep, 2 weak, 1 drop, 0 unchecked (merged 1; ungrounded 3, over cap 2)
- IDEA-1 [cross-model | route | cost M | KEEP] <title>
  problem: <problem> · replaces: <replaces> · effect: <effect> · risk: <risk>
  grounds: PRISM-004 (SUPPORTED), <path>:<lines> — "<quote>"
```

Add a `Degraded:` line naming `degraded_engines`, `check_degraded` and `check_partial` when any is
non-empty. Certainty language follows the verdict: `KEEP` "worth doing", `WEAK` "worth a look",
`UNCHECKED` "not checked".
