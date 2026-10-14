---
name: prism
description: "Evidence-graded multi-angle code review - 5 defect lenses discover in parallel, then an Evidence pass pins every candidate to file/lines/execution-path. SUSPECTED → SUPPORTED → REPRODUCED; agreement prioritizes, evidence confirms. --redteam adds an attacker-mindset lens."
argument-hint: "[file-or-topic] [--quick] [--adversarial] [--reproduce] [--redteam] [--diff [range]] [--include-improvements] [--lenses=design] [--format json]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Agent
---

# /prism Command

Run a multi-angle review across 5 defect-focused lenses in parallel, then ground every candidate in actual code (file, lines, execution path) before anything is reported as confirmed. Nothing is confirmed by agreement alone. Code gets the defect lenses; design docs, plans and specs get the design lenses (is the design sound?). For how a document *reads*, use `/triad`.

## Parse Arguments

| Argument Pattern | Action |
|---|---|
| `<target>` | Default: Discovery (5 lenses parallel) → Evidence pass (by-file chunked grounding of ALL candidates). |
| `<target> --quick` | Discovery only — everything reported as SUSPECTED. |
| `<target> --adversarial` | Evidence pass must argue against its own REJECTs before finalizing. |
| `<target> --reproduce` | + Reproduction pass: minimal failing tests in a temp dir (never the project tree). Max 5, CRIT/HIGH first. |
| `<target> --redteam` | + Red Team lens (attacker mindset, project security checklist cross-reference, attack chains). Replaces the retired `/prism-devil`. |
| `--diff [base...head]` | Review the change, not the file: "what regression does this diff newly introduce?" Preferred for PR review. |
| `<target> --include-improvements` | Adds the Improvement lens (suggestions labeled separately). |
| `<target> --format json` | Also emit machine-readable `prism-report.json` (finding records v2). |
| `<target> --lenses=design` | Force the design lens set (automatic for markdown targets). `classic` is an alias. |
| `(no argument)` | Review the current project's code. |

`<target>` may be a file path, a topic/feature name, or `.` for the current project. A markdown/design target gets the design lens set automatically.

## Execution

The full contract lives in the `prism` skill at `skills/prism/SKILL.md`. Read that file before executing — it contains the lens prompts, prompt assembly order (target first, lens last), candidate triage (agreement = priority only), the Evidence Agent prompt and by-file chunking rule, the deterministic `parse-findings.js` / `verify-evidence.js` steps, and the report format. Schema and extra lens prompts are in `skills/prism/references/`.

## When to use which

| Situation | Mode |
|---|---|
| Standard review | default (discovery + Evidence pass) |
| Reviewing a diff/PR | `--diff [range]` |
| Auth / payments / PII / parsers of untrusted input | `--redteam` |
| Before merging a change | `--reproduce` (demonstrate the bug) |
| You're rushing | `--quick` (everything SUSPECTED) |
| You suspect you'll dismiss real issues | `--adversarial` |
| Cross-model confidence | `/prism-all` (Claude + Codex) |
| Is this design doc sound? | `/prism <doc>` (design lenses) |
| Does this doc read well? | `/triad <doc>` |

## Companion commands

- `/prism-all <target>` - dual-engine (Claude + Codex) evidence-graded review
- `/prism-codex <target>` - Codex-only engine (saves Claude tokens)
- `/mangchi <file>` - iterative cross-model file hardening (after prism finds weak files)
- `/triad <file>` - document writing quality (LLM clarity / longevity / comprehension); pair with `/prism <doc>` for design soundness, or run both via `/ddaro:review`
