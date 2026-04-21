---
name: prism
description: "Multi-angle review — 5 agents in parallel discover, then a Verifier pass cross-checks singleton findings. Agreement auto-confirms."
argument-hint: "[file-or-topic] [--quick] [--adversarial]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Task
---

# /prism Command

Run a multi-angle review across 5 specialized agents in parallel, then verify any singleton findings (only one agent flagged them) in a second pass. Cross-agent agreement skips verification automatically.

## Parse Arguments

| Argument Pattern | Action |
|---|---|
| `<target>` | Default: 2-pass verify mode. Pass 1 (5 agents parallel) → triage → Pass 2 (verifier on singletons). |
| `<target> --quick` | 1 pass only. Skip verification — use when speed > signal. |
| `<target> --adversarial` | 1 pass + REJECT re-check. Re-examines findings you'd dismiss, catching self-bias. |
| `(no argument)` | Review the current project's overall design and quality. |

`<target>` may be a file path, a topic/feature name, or `.` for the current project.

## Execution

The full agent prompts and synthesis logic live in the `prism` skill at `skills/prism/SKILL.md`. Read that file before executing — it contains the 5 agent role prompts, the singleton-vs-agreement triage rules, the Verifier prompt, and the report format contract.

## When to use which

| Situation | Mode |
|---|---|
| Standard review | default (verify) |
| You're rushing | `--quick` |
| You suspect you'll dismiss real issues | `--adversarial` |
| Security-sensitive code | combine with `/prism-devil` |

## Companion commands

- `/prism-devil <target>` — single-agent aggressive red-team probe
- `/mangchi <file>` — iterative cross-model file hardening (after prism finds weak files)
- `/triad <file>` — 3-perspective deliberation for markdown/specs (not code)
