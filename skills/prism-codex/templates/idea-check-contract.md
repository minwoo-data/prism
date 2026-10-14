## Output contract: PRISM-IDEA-CHECK v1

After your reasoning, emit exactly one fenced block as the **last** fence in your message. Inside
it, one JSON object per idea key you were given, one per line, and nothing else. The line below
shows the shape; every `<...>` is a placeholder you replace:

<<<PRISM-IDEA-CHECK v1>>>
{"key":"<idea key>","verdict":"<KEEP|WEAK|DROP>","basis":"<exists|conflicts|not-solving|other>","reason":"<one or two sentences>","quote":"<path:lines — verbatim quote>","cost":"<S|M|L>","cost_note":"<why the cost changed>"}
<<<END>>>

### Fields

| Field | Rule |
|---|---|
| `key` | required. The idea key exactly as given (`claude-2`, `codex-1`). Answer every key once |
| `verdict` | required. `KEEP` (addresses its problem, no blocking conflict), `WEAK` (only partly addresses it, or the cost or risk is understated), `DROP` (does not solve it, already exists, or conflicts) |
| `basis` | required for `DROP`: `exists`, `conflicts`, `not-solving` or `other` |
| `reason` | required, at most 500 characters |
| `quote` | required when `basis` is `exists` or `conflicts`: `path:lines — quote` of the existing or conflicting code, copied verbatim (same rules as idea grounds). Otherwise omit |
| `cost`, `cost_note` | optional. Only to correct the proposer's cost: `S`, `M` or `L`, plus one line why |

### Rules a script enforces

- A `DROP` whose basis is `exists` or `conflicts` without a quote that verifies at the cited lines
  becomes `WEAK`. An idea is never dropped on an unverified claim.
- A key you do not answer becomes `UNCHECKED`, never `KEEP`.
- Keys you were not given are ignored. Do not invent new ideas.
