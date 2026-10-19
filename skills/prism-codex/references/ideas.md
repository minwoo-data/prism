# Idea pass (prism-ideas)

Canonical copy lives in `prism-all/references/`; synced byte-identical to `prism` and `prism-codex`
by `skills/sync-review-parsers.sh`.

prism's defect lenses answer "is this wrong?". The idea pass answers "what should we do instead?"
and grades the answers. It runs after the Evidence pass (Pass 4) when prism runs it as a companion,
or alone as `/prism-ideas`. Ideas never mix with defects: separate report section, separate JSON
array, never in defect counts, the action order, degraded angles or a gate.

Two output formats belong to this pass. Each lives in exactly one file, and that file is appended
**verbatim and last** to every prompt that needs it, for both engines. The instructions live in
template files too, and one script assembles every prompt:

| Step | Output fence | Contract file | Instructions | Prompt |
|---|---|---|---|---|
| Propose | `<<<PRISM-IDEAS v1>>>` | `templates/ideas-contract.md` | `templates/ideas-prompt.md` | `verify-ideas.js prompt propose` |
| Check | `<<<PRISM-IDEA-CHECK v1>>>` | `templates/idea-check-contract.md` | `templates/idea-check-prompt.md` | `verify-ideas.js prompt check` |

Never restate a format or the instructions in a prompt or in this file. The Claude agent gets the
bytes `prompt` prints; the Codex call is `codex-run.sh ideas|idea-check` with the same arguments,
which runs the same builder and only puts its Sandbox Safety Preamble in front.
`verify-ideas.js --selftest` fails if a contract file is missing or stops naming a field, value or
limit the script enforces, and `codex-run.sh --selftest` fails if the two engines' prompts differ.

## Findings the pass may cite

`--findings` is the **final** `checked.json` of the run, the one the defect report is built from.
Without `--reproduce` that is the Pass 2 output. With `--reproduce`, Pass 3 changes statuses (to
`REPRODUCED`, or down to `SUSPECTED`), so run `verify-evidence.js` again on the post-Pass-3 records
first; otherwise `REPRODUCED` never reaches the idea pass and a refuted finding still grounds ideas.
Only records that `verify-evidence.js` quote-checked count (`_evidence_check.quote_found`), so the
pre-check `records.json` grounds nothing. A file of the wrong shape is a usage error; duplicate IDs
ground nothing.

## 4a. Propose

One idea agent per engine runs all three lenses, so the target travels once per engine.

```
node "<skill dir>/verify-ideas.js" prompt propose --root <repo-root> --target <file>... [--findings checked.json] \
     [--context <file>]... > <run-dir>/pass4.claude.ideas.prompt.txt     # Claude agent reads this
bash "<skill dir>/codex-run.sh" ideas <run-dir> ideas --root <repo-root> --target <file>... \
     [--findings checked.json] [--context <file>]...                     # Codex: same prompt + preamble
```

`--root` is required: without it both commands exit 2. The builder refuses credential files,
network paths, a `--target` inside the root that a link takes outside it, and a findings file in
which no record was machine-checked (`records.json` instead of `checked.json`).
The prompt opens with `Repository root: <root>. Quote repository files
by their path relative to it.`; every file block is headed by its root-relative path (forward
slashes), or its absolute path when it lies outside the root, so a quote copied from a header
resolves in the gate. Then, in this order:

1. **TARGET** files, verbatim, each headed `--- BEGIN TARGET: <path> ---`, the path named as above
   (root-relative, or absolute outside the root), not as given on the command line.
2. **FINDINGS** (companion mode only): every `SUPPORTED` / `REPRODUCED` record of the final
   `checked.json`, one line each: `PRISM-NNN | STATUS | SEV | file:lines | claim`. Every field is
   flattened to one line; a severity outside CRIT/HIGH/MED/LOW or a malformed line range prints
   `?`, and a secret-shaped claim prints `(claim withheld: secret-shaped)`. Standalone mode has none.
3. **CONTEXT** files (`--context`), each headed `--- BEGIN CONTEXT: <path> ---`, the path named the
   same way. Data an idea needs as ground (exported sheets, logs, measurements) must arrive this
   way so its quote can be checked.
4. **`templates/ideas-prompt.md`**: the three lenses (class: fix the class; route: a different
   route; subtract: remove or reuse) and the rubric.
5. **`templates/ideas-contract.md`**, appended last.

## 4b. Gate (script)

```
node "<skill dir>/verify-ideas.js" gate <proposer-out> <claude|codex> <repo-root> \
     [--findings checked.json] [--target <file>]... [--context <file>]... > <engine>.gated.json
```

Pass the same `--target` and `--context` files the prompt got. A `--target` whose path, as
written, is outside the repository root is a quotable ground like a `--context` file; one inside
it is a repo file, and a link inside the root that leads outside stays `PATH_OUTSIDE_ROOT`.

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
  user and password are the same word is fine). In a `--context` file or a data/config file
  (`.env`-like, `.yml`/`.yaml`, `.ini`, `.toml`, `.properties`, `.conf`, `.cfg`, `.log`, `.txt`,
  `.csv`, `.json`) an unquoted `KEY: value` secret counts too: there a value is data, not a name.
  A quote is matched against every file its path can mean (a `--context`
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
verified grounds, proposal, replaces, cost, effect, risk) and the findings they cite, and has
Read/Grep/Glob on the repository, but not the proposer's reasoning. Batches of at most 8 ideas per
call; `prompt check` prints which batch it built and how many there are (`check batch 1/2: ...`
on stderr) and needs `--batch N` when there is more than one. Every finding the batch cites must be
confirmed in the `--findings` file, or the builder stops (pass the file the gate used). No GATED
idea: skip the check (rank takes the gate output then).

```
node "<skill dir>/verify-ideas.js" prompt check --gated <engine>.gated.json [--findings checked.json] \
     [--batch N] > <run-dir>/pass4.claude.check-<engine>-<N>.prompt.txt  # Claude checker reads this
bash "<skill dir>/codex-run.sh" idea-check <run-dir> check-<engine>-<N> --gated <engine>.gated.json \
     [--findings checked.json] [--batch N]                                # Codex checker
```

Who checks: in `/prism` and `/prism-codex`, a separate agent of the same engine. In `/prism-all`,
the other engine (Codex checks Claude's ideas, Claude checks Codex's), or a fresh checker of the same
engine when the other engine's proposer degraded (the header says so). Every idea is checked once;
grouping comes after the check (4d).

The instructions are `templates/idea-check-prompt.md`: does the proposal address the problem its
grounds point at, does something already do it or conflict with it (search, then quote), are cost
and risk honest, then the verdict. The checker never improves or adds ideas.

```
node "<skill dir>/verify-ideas.js" check <engine>.gated.json <batch-1-out> <repo-root> \
     [--also <batch-2-out>]... [--target <file>]... [--context <file>]... > <engine>.checked-ideas.json
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

The section is rendered by code, never written by hand:

```
node "<skill dir>/verify-ideas.js" render ideas.json
```

It prints an `Engines:` line (each engine that ran, `(degraded)` when its proposer failed), the
header line (`Ideas: N proposed -> G grounded -> k keep, w weak, d drop, u unchecked (merged,
ungrounded, over cap, invalid, bad lines, overflow)`, non-zero ones only), an `Excluded:` tally of
why ideas left before the check (`UNGROUNDED:NO_VALID_GROUND 2, OVER_CAP 1`), a
`Degraded (infra, not ideas):` line when a proposer failed (with the gate's note, e.g. `no
PRISM-IDEAS v1 fence; fallback: claude-unavailable`), a checker answered nothing or only part, a
check batch failed, or verdicts named unknown keys; then one entry per idea
(`- IDEA-1 [cross-model | route | cost M | KEEP: worth doing] <title>` plus problem, replaces,
proposal, effect, risk, grounds with their strength, and the checker's reason), and the checker's
drops. With no idea left it says `- none: the proposers failed (see Degraded)` when every proposer
degraded, else `- none: no idea survived the gate and the check`. Certainty language follows the
verdict: `KEEP` "worth doing", `WEAK` "worth a look", `UNCHECKED` "not checked". Model text is
flattened, re-checked for secrets (`(withheld: secret-shaped)`) and made inert: no HTML, images,
links (`[` and `]` escaped), mentions or `owner/repo#N` references (a zero-width space breaks them).
