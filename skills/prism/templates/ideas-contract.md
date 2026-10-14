## Output contract: PRISM-IDEAS v1

After your reasoning, emit exactly one fenced block as the **last** fence in your message. Inside
it, one JSON object per line and nothing else. The line below shows the shape; every `<...>` is a
placeholder you replace (a line that still contains a placeholder value is discarded):

<<<PRISM-IDEAS v1>>>
{"lens":"<class|route|subtract>","title":"<short title>","problem":"<the real problem this solves>","grounds":["<PRISM-NNN or path:lines — verbatim quote>"],"proposal":"<what to do instead>","replaces":"<what it replaces or removes, or none>","cost":"<S|M|L>","cost_note":"<one line>","effect":"<expected effect and how you would know it worked>","risk":"<what could go wrong, and the mitigation>"}
<<<END>>>

Only the last block of your message that is empty or holds a valid line counts: an earlier draft
is ignored. A block without its `<<<END>>>` line is discarded.

### Fields (all required)

| Field | Rule |
|---|---|
| `lens` | `class`, `route` or `subtract` |
| `title` | at most 120 characters |
| `problem` | at most 500 characters. The real problem this idea solves. A finding ID named here must also be in `grounds` |
| `grounds` | JSON array of 1 to 5 strings. Each is a finding ID (`PRISM-004`) or `path:lines — quote` |
| `proposal` | at most 1500 characters. What to do instead |
| `replaces` | at most 300 characters. What the idea replaces or removes. Write exactly `none` when it only adds (additive ideas rank lower) |
| `cost` | `S`, `M` or `L` |
| `cost_note` | at most 300 characters, one line |
| `effect` | at most 500 characters. The expected effect, and how you would know it worked |
| `risk` | at most 500 characters. What could go wrong, and the mitigation |

Every text is flattened to one line (line breaks become spaces).

### Grounding (a script checks every idea; an idea with no valid ground is discarded)

- **Finding ID:** counts only if the FINDINGS list in this prompt has it as `SUPPORTED` or
  `REPRODUCED`. `SUSPECTED` and `REJECTED` findings do not count. Without a FINDINGS list, use quotes.
- **Quote:** `path:lines — quote`. `path` is relative to the repository root, or a context file's
  name exactly as given (`CONTEXT: <name>`). `lines` is `N` or `N-M`, spanning at most 40 lines. The
  quote is copied verbatim from those lines (whitespace and case may differ, ±2 lines of slack) and
  is at least 8 characters long. Paraphrases fail.
- Refused as grounds: paths outside the repository root that are not given context files, network
  paths, credential files (`.env`, keys, tokens, `*secret*`/`*credential*` config), version-control
  internals (`.git/...`), and any quote that looks like a secret. Never quote secrets.

### Limits

- At most **3 ideas per lens**. The 4th and later ideas of a lens, in the order you write them, are
  discarded unread, so write your best idea first. Fewer strong ideas beat more weak ones.
- An empty block means you found no idea worth proposing. That is a valid answer.
- An idea is an alternative, a structural change or a removal. A local patch for one finding is not
  an idea; the defect report already carries `suggested_fix`.
