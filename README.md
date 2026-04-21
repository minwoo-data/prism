# Prism — Multi-Angle Review with Verification

**Language**: **English** · [한국어](README.ko.md)

> 5 reviewers, 5 angles, one spectrum. Agreement passes through. Singletons get verified.

---

## What this is

A Claude Code skill that runs **5 specialized review agents in parallel** against a target (file, design, project), then runs a **second verifier pass** on findings that only one agent flagged. Cross-agent agreement auto-confirms — no need to re-verify what 3 reviewers already converged on.

The default mode is **verify**, not quick, because false positives from a single reviewer are the most common failure of multi-agent review. A short batched verifier pass catches them at ~1.2–1.4× cost of a single round.

## When to use it

- Before a major architectural decision
- Before merging a PR you're unsure about
- After implementing a feature, to catch what you missed
- Auditing a skill, design doc, or workflow
- Whenever you'd ask 5 senior engineers to look at the same thing

## When not to use it

- Tiny one-line changes (overkill)
- Pure markdown/spec review (use `/triad` instead — 3 perspectives are enough)
- Iterative file hardening (use `/mangchi` — better tool for that loop)

## The 5 agents

Each agent runs in a forked context, so the main conversation stays clean.

| Agent | Looks for |
|---|---|
| **Conflict Detection** | Overlaps with existing code/skills, config contradictions, integration risks |
| **Improvement** | Concrete enhancements, efficiency gains, missing features |
| **Devil's Advocate** | Weaknesses, gaming/Goodhart risk, false confidence, regression risk |
| **Code Review** | Clarity, completeness, correctness, pattern consistency |
| **Robustness (4-Axis)** | Concurrency / Failure & Recovery / Data Integrity / State Transitions |

## How verification works

After Pass 1, every finding is classified:

- **AGREEMENT** (2+ agents flagged) → auto-CONFIRMED, skips Pass 2
- **SINGLETON** (1 agent only) → goes into Pass 2

Pass 2 runs **one batched Verifier agent** that gets the full target + all 5 Pass 1 outputs + the singleton list. It returns `CONFIRMED | REJECTED | DEPENDS` for each.

This means cheap consensus passes through fast, and only borderline findings pay the verification cost.

## Modes

```
/prism src/services/auth.py                 # default: 2-pass verify
/prism src/services/auth.py --quick         # 1 pass only, no verify
/prism src/services/auth.py --adversarial   # 1 pass + REJECT re-check
/prism .                                    # whole-project review
```

Natural language also works: *"prism 돌려"*, *"full review"*, *"design review"*.

## Output

```
PRISM REPORT — src/services/auth.py — 2026-04-20 15:30
Mode: verify

## CRITICAL (must fix)
- [3/5 agreement] CSRF token reused across requests → rotate per request
- [1/5 → verified] Password reset link not single-use → add nonce table

## HIGH (should fix)
- [2/5 agreement] ...
- [1/5 → verified] ...

## Rejected Singletons
- [Improvement → rejected] "Add OAuth login" — Verifier: out of scope per CLAUDE.md (SSO permanently deferred)

## Cross-Agent Agreements
3 findings where multiple agents converged.

## Recommended Action Order
1. ...
```

## Cost

| Mode | Cost | When |
|---|---|---|
| `--quick` | 1.0× | Already-triaged targets |
| default (verify) | 1.2–1.4× | Standard reviews |
| `--adversarial` | 1.2–1.4× | When you suspect self-bias |

The verifier runs in **a single batched call** (not one-per-finding), so 20 singletons cost the same as 2.

## Companion tools

- **[mangchi](https://github.com/minwoo-data/mangchi)** — iterative cross-model file refinement. Use after prism identifies a weak file.
- **prism-devil** — aggressive single-agent attacker-mindset probe. Pair with prism for security-sensitive code.
- **[triad](https://github.com/minwoo-data/triad)** — 3-perspective deliberation for markdown and short docs.

## Install

Drop the skill into your Claude Code skills directory:

```
~/.claude/skills/prism/SKILL.md
```

Or wire as a slash command via `commands/prism.md` (Claude Code reads it from `.claude/commands/` per project, or `~/.claude/commands/` globally).

## Created by

Minwoo Park
