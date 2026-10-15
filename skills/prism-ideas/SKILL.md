---
name: prism-ideas
description: Grounded alternatives instead of verdicts. One idea agent per engine (Claude and Codex) proposes at most 3 ideas per lens - class (fix the class), route (a different route), subtract (remove or reuse) - each tied to a real problem by a finding ID or a machine-checked file:lines quote; ungrounded ideas are dropped by a script; the other engine checks every idea KEEP / WEAK / DROP (a DROP needs a verified quote); a script ranks them. Ideas are never defects. Use before writing a PRD, or after a prism review to ask "what should we do instead?". Triggers on "/prism-ideas <target>", "prism ideas", "prism 아이디어".
argument-hint: "<target>... [--context <file>]... [--findings <checked.json>] [--engine both|claude|codex]"
user-invocable: true
---

# prism-ideas — Grounded Alternatives

> prism's lenses answer "is this wrong?". This skill answers "what should we do instead?" and
> grades the answers. Every idea must point at a real problem through a ground a script can check;
> every surviving idea is judged by a checker that did not write it. Ideas never become defects,
> tasks or gates: they are options for a person to choose from.

Files in this skill dir: `verify-ideas.js` (gate / check / rank / prompt / render; load-bearing),
`verify-evidence.js` (its quote matcher), `codex-run.sh` (the Codex call contract as code),
`templates/` (the prompts and the two output contracts), `references/ideas.md` (why the rules are
what they are; read it only when a step degrades). `parse-findings.js` is here only for
`codex-run.sh --selftest`.

From 0.5.0, prism, prism-all and prism-codex run this same pass after their Evidence pass (Pass 4).
Run this skill alone when you only want ideas, or with `--findings` to reuse a review.

## Arguments

| Argument | Meaning |
|---|---|
| `<target>...` | Files to think about (code, a design doc, a PRD). A directory or topic: pick the files that matter and say which. Targets and context together stay under ~150 KB (the Codex prompt is capped at 180 KB). |
| `--context <file>` | Data an idea may quote as ground: exported sheets, logs, measurements, notes. Repeatable. |
| `--findings <checked.json>` | The final `checked.json` of an earlier prism run (what `verify-evidence.js` printed, not `records.json`). Lets ideas cite `PRISM-NNN` findings. Without it, grounds are quotes only. |
| `--engine both` (default) / `claude` / `codex` | Who proposes and checks. `both` = cross-check (each engine's ideas are checked by the other). Without Codex, `both` falls back to `claude` and says so. |

## Setup

1. Resolve the targets to file paths and `<repo-root>` (`git rev-parse --show-toplevel`, else the
   targets' common directory). Never pass credential files (`.env`, keys, tokens); the scripts
   refuse them anyway.
2. Run dir: `RUN="$(bash "<skill dir>/codex-run.sh" init ideas-<slug>)"` (a private temp directory).
3. Engines: `both` needs `codex --version` ≥ 0.125.0; otherwise use `claude` and print
   `Codex unavailable: Claude-only` in the header.

`ARGS` below means the same `--target` / `--findings` / `--context` list every time (every step
accepts it; `check` ignores `--findings`). Every `codex-run.sh` call runs with Bash `timeout` =
(`PRISM_CODEX_TIMEOUT` (300) + 30) × 1000 ms; a shorter one kills the wrapper (`interrupted`).

Claude agents (proposer and checkers) are told: "Use only Read, Grep and Glob; use Write only to
save your complete final message to `<answer file>`. Do not modify any other file." If an agent
fails, or its answer file is missing or holds no closed fenced block, write
`[fallback: claude-unavailable]` to that answer file: gate and check then report the engine as
degraded and the run goes on.

## Step 1 — Propose

Build first, then launch. A builder that exits 2 is an argument error: fix it, launch nothing.

- **Claude** (`claude` or `both`):
  `node "<skill dir>/verify-ideas.js" prompt propose --root <repo-root> ARGS > "$RUN/pass4.claude.ideas.prompt.txt"`.
  Only after it exited 0 and the file is non-empty: one Agent (general-purpose): "Read `<that
  file>` completely and do exactly what it says. End your message with the fenced block it asks
  for." plus the tool rule above, answer file `$RUN/pass4.claude.ideas.txt`.
- **Codex** (`codex` or `both`): one Bash call,
  `bash "<skill dir>/codex-run.sh" ideas "$RUN" ideas --root <repo-root> ARGS`.
  The answer lands in `$RUN/pass4.codex.ideas.codex.txt`; the summary line says `fence=yes|no`.
  Never call `codex exec` yourself and never type the prompt: the script builds it from the same
  builder and adds the sandbox preamble, scrub and timeout.

The Claude agent and the Codex call go out in one message, after the Claude prompt file exists.

### Codex fallback

| Summary line / exit | Action |
|---|---|
| `degraded(timeout)`, `degraded(codex-unavailable)`, `degraded(no-last-message)`, or interrupted (exit 130, `[fallback: interrupted]`) | Retry that call once with the same arguments. Still degraded: keep the marker, the engine counts as degraded. |
| `degraded(prompt-too-large)`, `degraded(prompt-build-failed)` | No retry (the same input fails again): narrow the targets or context, or use `--engine claude`. |
| `secret-scrubbed(...)`, or a `prompt-modified-during-run` / `scan-failed` marker | Security incident: no retry. Tell the user what the marker says; the engine counts as degraded. |
| exit 2 | Usage, argument or install error, or the same call still running: fix it and rerun. Not a model problem. |

## Step 2 — Gate (script)

For each engine that ran:

```
node "<skill dir>/verify-ideas.js" gate <its answer file> <claude|codex> <repo-root> ARGS > "$RUN/<engine>.gated.json"
```

`counts.gated` = ideas that survived. `degraded: true` = the engine produced no usable answer
(infra, not ideas): say so in the header, keep going with the other engine.

## Step 3 — Check (cross, batches of 8)

Skip an engine whose `counts.gated` is 0. Otherwise its ideas are checked by **the other engine**
(`both`), or by a fresh agent / call of the same engine (`claude` / `codex`). With `both`, when the
other engine is degraded (its proposer failed, or Codex is gone), check with a fresh agent / call
of the same engine instead and say so in the header (`checker: same engine, <other> degraded`).

- Checker is Claude:
  `node "<skill dir>/verify-ideas.js" prompt check --gated "$RUN/<engine>.gated.json" [--findings F] --batch N > "$RUN/pass4.claude.check-<engine>-N.prompt.txt"`
  (stderr says `check batch N/M`; `--batch` is required when M > 1). Only after it exited 0 and the
  file is non-empty: one fresh Agent per batch ("Read `<file>` completely and do exactly what it
  says." plus the tool rule above), answer file `$RUN/check-<engine>-N.txt`.
- Checker is Codex:
  `bash "<skill dir>/codex-run.sh" idea-check "$RUN" check-<engine>-N --gated "$RUN/<engine>.gated.json" [--findings F] --batch N`
  (answer in `$RUN/pass4.codex.check-<engine>-N.codex.txt`; its summary line names the batch's keys).

Build all checker prompt files first; then all batches of both directions go out in one parallel
message. Then per checked engine:

```
node "<skill dir>/verify-ideas.js" check "$RUN/<engine>.gated.json" <batch-1 answer> <repo-root> [--also <batch-2 answer>]... ARGS > "$RUN/<engine>.checked.json"
```

A failed batch (Codex fallback above, empty answer) may be retried once; pass the retry's file. The
script never turns a missing verdict into KEEP.

## Step 4 — Group and rank

Pass only the engines that ran: each engine's checked file, or its gated file when it had nothing
to check (degraded, or no idea gated).

- `--engine both`: read the titles and proposals of the GATED ideas in both files. Ideas from
  **different engines** that propose the same change form a group; write `$RUN/groups.json` as key
  lists, `[["claude-2-3f9a","codex-1-0b7e"]]` (keys exactly as in the files; `[]` when nothing
  matches). Group only real duplicates: same change, not same topic.
  `node "<skill dir>/verify-ideas.js" rank "$RUN/claude.checked.json" "$RUN/codex.checked.json" --groups "$RUN/groups.json" > "$RUN/ideas.json"`
- `--engine claude`: `node "<skill dir>/verify-ideas.js" rank "$RUN/claude.checked.json" > "$RUN/ideas.json"`
- `--engine codex`: `node "<skill dir>/verify-ideas.js" rank "$RUN/codex.checked.json" > "$RUN/ideas.json"`

Then `node "<skill dir>/verify-ideas.js" render "$RUN/ideas.json"`.

## Report

```
PRISM IDEAS — {targets} — {timestamp}
Findings: {file | none} · Context: {files | none}{ · Codex unavailable: Claude-only}{ · checker: same engine, <engine> degraded}
<the render output, verbatim: its Engines / Ideas / Excluded / Degraded lines, then the ideas>
Artifacts: $RUN/ideas.json
```

Then at most 3 lines of your own: which KEEP ideas look worth a person's decision first, and why.
Never present an idea as a defect, a task or a confirmed fact; `WEAK` and `UNCHECKED` ideas are
options with doubts attached.

## Rules

- Prompts come only from `verify-ideas.js prompt` (Claude) and `codex-run.sh ideas|idea-check`
  (Codex). Never write or edit a prompt, a contract or a verdict by hand.
- Every count, verdict and order in the report comes from the scripts' JSON. Do not re-judge.
- Never modify the target project. Never apply an idea; that is a person's call (then `/mangchi`
  or a normal PR).
- A degraded engine or checker is reported as infrastructure, never as "no ideas".

## Cost

| Run | Calls | Wall time |
|---|---|---|
| `--engine both` | 1 Claude + 1 Codex proposer, ⌈ideas/8⌉ checks per direction | ~2–4 min (Codex bound) |
| `--engine claude` | 1 proposer + ⌈ideas/8⌉ checkers | ~1 min |
| `--engine codex` | 1 proposer + ⌈ideas/8⌉ checker calls | ~2–3 min |

The target travels once per proposer; checkers get only the ideas and the cited findings and read
the repository themselves. Self-check: `node verify-independence.js --strict`.
