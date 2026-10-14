## Output contract: PRISM-IDEA-CHECK v1

After your reasoning, emit exactly one fenced block as the **last** fence in your message. Inside
it, one JSON object per idea key you were given, one per line, and nothing else. The line below
shows the shape; every `<...>` is a placeholder you replace:

<<<PRISM-IDEA-CHECK v1>>>
{"key":"<idea key>","verdict":"<KEEP|WEAK|DROP>","basis":"<exists|conflicts|not-solving|other>","reason":"<one or two sentences>","quote":"<path:lines — verbatim quote>","cost":"<S|M|L>","cost_note":"<why the cost changed>"}
<<<END>>>

Only the last block of your message counts. A block cut off before its `<<<END>>>` line, or an
empty block, answers nothing.

### Fields

| Field | Rule |
|---|---|
| `key` | required. The idea key exactly as given (`claude-2-3f9a`, `codex-1-0b7e`). Answer every key once |
| `verdict` | required. `KEEP` (addresses its problem, no blocking conflict), `WEAK` (only partly addresses it, or the cost or risk is understated), `DROP` (does not solve it, already exists, or conflicts) |
| `basis` | required for `DROP`: `exists`, `conflicts`, `not-solving` or `other` |
| `reason` | required, at most 500 characters |
| `quote` | required for a `DROP` unless its basis is `not-solving`: `path:lines — quote` of the existing or conflicting code (or whatever proves the claim), copied verbatim, same rules as idea grounds. Otherwise omit |
| `cost`, `cost_note` | optional. Only to correct the proposer's cost: `S`, `M` or `L`, plus one line why |

### Rules a script enforces

- A `DROP` stands only on a quote that verifies at the cited lines, unless its basis is `not-solving`.
  Without one it becomes `WEAK`. An idea is never dropped on an unverified claim.
- A key you do not answer becomes `UNCHECKED`, never `KEEP`. A line the script rejects (for example
  a `DROP` without a basis) counts as not answered, and the report says why.
- Keys you were not given are ignored. Do not invent new ideas.
