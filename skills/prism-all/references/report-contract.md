# Report contract 2 (`/prism --run-tag` gate runs)

This contract applies only to the `prism-report.json` of a `/prism --run-tag ... --format json`
run (a gate run, written by `assemble-report.js finish`). The reports of prism-all and prism-codex,
and of `/prism` without `--run-tag`, are written by the model and are outside this contract; this
file ships with them only because `skills/sync-review-parsers.sh` copies it.

The contract version lives in `skills/prism/report-contract.json` (`{"report_contract": "2"}`),
which only the `/prism` skill ships. A consumer (ddaro's merge gate) reads that file from the
installed plugin to know what it will get, and `assemble-report.js` copies the value into
`meta.report_contract`. `plugin.json` carries the plugin version, not the contract.

## Versioning

- **minor** (the number stays): fields are added. A consumer must ignore fields it does not know.
- **major** (the number changes): an enum value or the meaning of an existing field changes, or a
  field goes away. A consumer that reads a higher major than it knows must refuse the report.
- `meta.record_version` is the version of the finding records (`"2.1"` here: record v2 plus the
  fields below). It is not the contract version.

## Shape

```json
{
  "meta": { ... },
  "findings": [ <record v2.1>, ... ],
  "ideas": []
}
```

### `meta`, the 0.5.0 fields

| field | value in a gate run |
|---|---|
| `target` | `--target` text, else `diff <range>` or `rejudge <n> blocker(s)` |
| `mode` | `"default"` (a gate run is never quick or adversarial) |
| `lenses` | the lens set name, `"defect"` (same as `lens_set`) |
| `engines` | `["claude"]` |
| `checklist` | `--checklist` path, else `null` |
| `timestamp` | ISO 8601 instant of `finish` (`--timestamp` pins it) |
| `counts` | `{records, supported, reproduced, suspected, rejected}`, counted from `checked.json` only |
| `ideas` | `{"ran": false, "reason": "--no-ideas"}`: a gate run never runs Pass 4 |

### `meta`, added by contract 2

| field | meaning |
|---|---|
| `report_contract` | `"2"`, from `report-contract.json` |
| `record_version` | `"2.1"` |
| `run_tag` | the gate's run id, as given to `--run-tag` |
| `head` | the 40-hex commit the run reviewed (`--head`); Pass 2 quotes were checked at this commit (`verify-evidence.js --rev`) |
| `base` | the range's base sha, or `null` in a rejudge |
| `range` | `<base>...<head>` (or `..`), or `null` in a rejudge |
| `scope` | `"diff"` (a full or incremental review of the range) or `"rejudge"` (blockers only, no Pass 1) |
| `lens_set` | `"defect"` |
| `lenses_requested` | the Pass 1 angles asked for, in order (`[]` in a rejudge) |
| `lenses_completed` | the subset whose answer parsed with `degraded: false`, `skipped` 0, `overflow` 0, and every `<<<PRISM-FINDINGS v1>>>` closed by an `<<<END>>>` |
| `degraded_angles` | `[{angle, reason}]` for every requested lens not in `lenses_completed`; `reason` is `fallback: <marker>`, the parser's degraded note, `skipped N`, `overflow N`, `unclosed`, joined by `, ` |
| `candidate_ids` | sorted: every candidate id in `candidates.json` plus `blocker:<id>` for every entry of the blockers file (a rejudge has only the latter) |
| `tree_changed` | `true` when, at `finish`, HEAD differs from `head` or a tracked file is modified; the gate treats a changed tree as an error |
| `unmapped_findings` | lens finding ids (`<angle>#<n>`, n counted from 1 in that lens's parsed `findings`) that `candidates.json` did not map; a candidates key no lens produced is a `finish` error instead |

### `findings`: record v2.1

Every element of the final `checked.json` (see `record-v2.md`), as `verify-evidence.js --rev`
wrote it, plus:

| field | meaning |
|---|---|
| `grounding_failed` | `true` when the quote check downgraded the record (`status` SUSPECTED, `_evidence_check.checked` true, `quote_found` false) or `missing` is exactly `EVIDENCE_PASS_FAILED`; nothing is parsed out of other `missing` text |
| `_evidence_check.quote_lines` | from `--rev`: the lines the quotes (8+ loose characters) actually sit on, sorted and unique; `[]` when nothing matched; REJECTED records with evidence carry it too, with `status` untouched |

A record's `candidate_id` is one of `meta.candidate_ids`; `finish` refuses any other. The gate
decides which candidates lack a record (it ignores `blocker:` ids that were never re-judged).

### `ideas`

`[]`. Contract 2 reports never carry ideas; the gate does not read `ideas` or `meta.ideas`.

## Run folder files (what `finish` reads)

| file | written by | read by |
|---|---|---|
| `prism-run.json` | `begin` (exclusive create) | `finish` (run_tag, head, scope, contract must match); the gate, to tell "no report yet" from "unknown folder" |
| `pass1.claude.<angle>.txt` | the lens agent (or the orchestrator's `[fallback: claude-unavailable]`) | `finish` |
| `pass1.claude.<angle>.txt.json` | `parse-findings.js` | `finish` |
| `candidates.json` | the orchestrator: `{"<angle>#<n>": "<candidate id>"}` | `finish` |
| `blockers.json` | the gate | `begin`, `finish`, the Evidence pass |
| `records.json` → `checked.json` | the Evidence pass → `verify-evidence.js --rev <head>` | `finish` |
| `prism-report.json` | `finish` only (temp file, fsync, one hard link) | the gate |
