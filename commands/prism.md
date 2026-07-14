---
name: prism
description: "Evidence-graded multi-angle review - 5 defect lenses discover in parallel, then an Evidence pass pins every candidate to file/lines/execution-path. SUSPECTED → SUPPORTED → REPRODUCED; agreement prioritizes, evidence confirms."
argument-hint: "[file-or-topic] [--quick] [--adversarial] [--reproduce] [--diff [range]] [--include-improvements] [--lenses=classic] [--format json]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Agent
---

# /prism Command

Run a multi-angle review across 5 defect-focused lenses in parallel, then ground every candidate in actual code (file, lines, execution path) before anything is reported as confirmed. Nothing is confirmed by agreement alone.

## Parse Arguments

| Argument Pattern | Action |
|---|---|
| `<target>` | Default: Discovery (5 lenses parallel) → Evidence pass (batched grounding of ALL candidates). |
| `<target> --quick` | Discovery only — everything reported as SUSPECTED. Speed > signal. |
| `<target> --adversarial` | Evidence pass must argue against its own REJECTs before finalizing. |
| `<target> --reproduce` | + Reproduction pass: minimal failing tests in a temp dir (never the project tree). Max 5, CRIT/HIGH first. |
| `--diff [base...head]` | Review the change, not the file: "what regression does this diff newly introduce?" |
| `<target> --include-improvements` | Adds the Improvement lens (suggestions labeled separately). |
| `<target> --lenses=classic` | Legacy lens set — auto-selected for non-code targets (docs, plans). |
| `<target> --format json` | Also emit machine-readable `prism-report.json` (finding records v2). |
| `(no argument)` | Review the current project's overall design and quality. |

`<target>` may be a file path, a topic/feature name, or `.` for the current project.

## Execution

The full contract lives in the `prism` skill at `skills/prism/SKILL.md`. Read that file before executing - it contains the 5 defect-lens prompts (+ the classic set for `--lenses=classic`), candidate triage (agreement = priority only, no auto-confirm), the Evidence Agent prompt, the deterministic `parse-findings.js` / `verify-evidence.js` steps, the finding record v2 schema, and the report format.

## When to use which

| Situation | Mode |
|---|---|
| Standard review | default (discovery + Evidence pass) |
| Before merging a change | `--reproduce` (demonstrate the bug) |
| Reviewing a diff/PR | `--diff [range]` |
| You're rushing | `--quick` (everything SUSPECTED) |
| You suspect you'll dismiss real issues | `--adversarial` |
| Cross-model confidence | `/prism-all` (Claude + Codex) |

## Companion commands

- `/prism-all <target>` - dual-engine (Claude + Codex) evidence-graded review
- `/mangchi <file>` - iterative cross-model file hardening (after prism finds weak files)
- `/triad <file>` - 3-perspective deliberation for markdown/specs (not code)
