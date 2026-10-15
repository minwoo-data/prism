---
name: prism-ideas
description: Grounded alternatives instead of verdicts. One idea agent per engine (Claude and Codex) proposes at most 3 ideas per lens - class (fix the class), route (a different route), subtract (remove or reuse) - each tied to a real problem by a finding ID or a machine-checked file:lines quote; ungrounded ideas are dropped by a script; the other engine checks every idea KEEP / WEAK / DROP (a DROP needs a verified quote); a script ranks them. Ideas are never defects. Use before writing a PRD, or after a prism review to ask "what should we do instead?". Triggers on "/prism-ideas <target>", "아이디어 내줘", "대안 찾아줘", "prism ideas".
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
what they are; read it only when a step degrades), `references/codex-invocation.md` (Codex
fallback policy). `parse-findings.js` is here only for `codex-run.sh --selftest`.

When prism, prism-all or prism-codex run a review, they run this same pass after their Evidence pass
(Pass 4). Run this skill alone when you only want ideas, or with `--findings` to reuse a review.

## Arguments

| Argument | Meaning |
|---|---|
| `<target>...` | Files to think about (code, a design doc, a PRD). A directory or topic: pick the files that matter (at most ~150 KB in total) and say which. |
| `--context <file>` | Data an idea may quote as ground: exported sheets, logs, measurements, notes. Repeatable. |
| `--findings <checked.json>` | The final `checked.json` of an earlier prism run. Lets ideas cite `PRISM-NNN` findings. Without it, grounds are quotes only. |
| `--engine both` (default) / `claude` / `codex` | Who proposes and checks. `both` = cross-check (each engine's ideas are checked by the other). Without Codex, `both` falls back to `claude` and says so. |

## Setup

1. Resolve the targets to file paths and the repository root (`git rev-parse --show-toplevel`,
   else the targets' common directory). Never pass credential files (`.env`, keys, tokens); the
   scripts refuse them anyway.
2. Run dir: `RUN="$(bash "<skill dir>/codex-run.sh" init ideas-<slug>)"` (a private temp directory).
3. Engines: `both` needs `codex --version` ≥ 0.125.0; otherwise use `claude` and print
   `Codex unavailable: Claude-only` in the header.

`ARGS` below means the same `--target` / `--findings` / `--context` list every time.

## Step 1 — Propose (one message, parallel)

- **Claude** (`claude` or `both`):
  `node "<skill dir>/verify-ideas.js" prompt propose ARGS > "$RUN/pass4.claude.ideas.prompt.txt"`,
  then one Agent (general-purpose, read-only use): "Read `<that file>` completely and do exactly
  what it says. Do not modify any file. End your message with the fenced block it asks for." Write
  the agent's final message verbatim to `$RUN/pass4.claude.ideas.txt`.
- **Codex** (`codex` or `both`): one Bash call,
  `bash "<skill dir>/codex-run.sh" ideas "$RUN" ideas ARGS`
  with Bash `timeout` = (`PRISM_CODEX_TIMEOUT` (300) + 30) × 1000 ms. The answer lands in
  `$RUN/pass4.codex.ideas.codex.txt`. Never call `codex exec` yourself and never type the prompt:
  the script builds it from the same builder and adds the sandbox preamble, scrub and timeout.

Launch both in the same message. Fallback rules for a degraded Codex call (retry once only for
`timeout` / `codex-unavailable` / `no-last-message`; never for secret-scrub markers):
`references/codex-invocation.md` §Fallback policy.

## Step 2 — Gate (script)

For each engine that ran:

```
node "<skill dir>/verify-ideas.js" gate <its answer file> <claude|codex> <repo-root> ARGS > "$RUN/<engine>.gated.json"
```

`counts.gated` = ideas that survived. `degraded: true` = the engine produced no usable answer
(infra, not ideas): say so in the header, keep going with the other engine.

## Step 3 — Check (cross, batches of 8)

Skip an engine whose `counts.gated` is 0. Otherwise its ideas are checked by **the other engine**
(`both`), or by a fresh agent / call of the same engine (`claude` / `codex`):

- Checker is Claude:
  `node "<skill dir>/verify-ideas.js" prompt check --gated "$RUN/<engine>.gated.json" [--findings F] --batch N > "$RUN/pass4.claude.check-<engine>-N.prompt.txt"`
  (stderr says `check batch N/M`), one fresh Agent per batch ("Read `<file>` completely and do
  exactly what it says. Do not modify any file."), final message written verbatim to
  `$RUN/check-<engine>-N.txt`.
- Checker is Codex:
  `bash "<skill dir>/codex-run.sh" idea-check "$RUN" check-<engine>-N --gated "$RUN/<engine>.gated.json" [--findings F] --batch N`
  (answer in `$RUN/pass4.codex.check-<engine>-N.codex.txt`).

All batches of both directions go out in one parallel message. Then per engine:

```
node "<skill dir>/verify-ideas.js" check "$RUN/<engine>.gated.json" <batch-1 answer> <repo-root> [--also <batch-2 answer>]... ARGS > "$RUN/<engine>.checked.json"
```

A failed batch (Codex timeout, empty answer) may be retried once; pass the retry's file. The
script never turns a missing verdict into KEEP.

## Step 4 — Group and rank

Read the titles and proposals of the GATED ideas in the checked files (or gated files for engines
that skipped the check). Ideas from **different engines** that propose the same change form a group;
write `$RUN/groups.json` as key lists, `[["claude-2-3f9a","codex-1-0b7e"]]` (keys exactly as in
the files; `[]` when nothing matches). Group only real duplicates: same change, not same topic.

```
node "<skill dir>/verify-ideas.js" rank "$RUN/claude.checked.json" "$RUN/codex.checked.json" --groups "$RUN/groups.json" > "$RUN/ideas.json"
node "<skill dir>/verify-ideas.js" render "$RUN/ideas.json"
```

(Pass each engine's checked file, or its gated file when it had nothing to check.)

## Report

```
PRISM IDEAS — {targets} — {timestamp}
Engines: {claude+codex cross-check | claude only (Codex unavailable) | ...} · Findings: {file | none} · Context: {files | none}
<the render output, verbatim>
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
