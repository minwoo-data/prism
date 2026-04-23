# Prism - Multi-Angle Review with Verification

**Language**: **English** · [한국어](README.ko.md)

**Ever had a single reviewer miss something another angle would have caught, then later regret shipping it?** prism runs 5 specialized reviewers in parallel (conflict / improvement / devil's advocate / code review / robustness), then cross-checks singleton findings to filter out false positives.

> 5 reviewers, 5 angles, one spectrum. Agreement passes through. Singletons get verified.

---

## 30-second demo

**Without prism:**

You ask Claude "review this file". It says "looks good". You ship it. Two weeks later a bug surfaces that a different review angle (say, concurrency or config conflict) would have caught immediately. But no one thought to check that angle with an independent reviewer.

**With prism:**

`/prism src/services/auth.py`. Five reviewers look at the file in parallel with five different biases (conflict detection / improvement / devil's advocate / code review / robustness). Anything 2+ agree on is auto-confirmed. Anything only one agent saw gets a second verifier pass so false positives do not waste your time.

## Who should use this

- **Before major architectural decisions** - you want 5 angles, not 1
- **Before merging a PR you are not sure about** - independent review beyond your own LLM's opinion
- **After implementing a feature** - last-line sweep for blind spots before release
- **Auditing a skill, design doc, or workflow** - the disagreement between reviewers is itself signal

## Sibling tools (same marketplace)

- **[ddaro](https://github.com/minwoo-data/ddaro)** - worktree-based parallel Claude Code sessions with safe merge.
- **[triad](https://github.com/minwoo-data/triad)** - deeper 3-perspective deliberation for markdown / design docs.
- **[mangchi](https://github.com/minwoo-data/mangchi)** - iterative file refinement with Claude + Codex cross-review.

---

## What this is

A Claude Code skill that runs **5 specialized review agents in parallel** against a target (file, design, project), then runs a **second verifier pass** on findings that only one agent flagged. Cross-agent agreement auto-confirms - no need to re-verify what 3 reviewers already converged on.

The default mode is **verify**, not quick, because false positives from a single reviewer are the most common failure of multi-agent review. A short batched verifier pass catches them at ~1.2-1.4× cost of a single round.

## When to use it

- Before a major architectural decision
- Before merging a PR you're unsure about
- After implementing a feature, to catch what you missed
- Auditing a skill, design doc, or workflow
- Whenever you'd ask 5 senior engineers to look at the same thing

## When not to use it

- Tiny one-line changes (overkill)
- Pure markdown/spec review (use `/triad` instead - 3 perspectives are enough)
- Iterative file hardening (use `/mangchi` - better tool for that loop)

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
PRISM REPORT - src/services/auth.py - 2026-04-20 15:30
Mode: verify

## CRITICAL (must fix)
- [3/5 agreement] CSRF token reused across requests → rotate per request
- [1/5 → verified] Password reset link not single-use → add nonce table

## HIGH (should fix)
- [2/5 agreement] ...
- [1/5 → verified] ...

## Rejected Singletons
- [Improvement → rejected] "Add OAuth login" - Verifier: out of scope per CLAUDE.md (SSO permanently deferred)

## Cross-Agent Agreements
3 findings where multiple agents converged.

## Recommended Action Order
1. ...
```

## Cost

| Mode | Cost | When |
|---|---|---|
| `--quick` | 1.0× | Already-triaged targets |
| default (verify) | 1.2-1.4× | Standard reviews |
| `--adversarial` | 1.2-1.4× | When you suspect self-bias |

The verifier runs in **a single batched call** (not one-per-finding), so 20 singletons cost the same as 2.

## Companion tools

- **[mangchi](https://github.com/minwoo-data/mangchi)** - iterative cross-model file refinement. Use after prism identifies a weak file.
- **prism-devil** - aggressive single-agent attacker-mindset probe. Pair with prism for security-sensitive code.
- **[triad](https://github.com/minwoo-data/triad)** - 3-perspective deliberation for markdown and short docs.

## Install

### 1. Add the haroom_plugins marketplace (one time)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git
```

`prism` is distributed through the **haroom_plugins** aggregator along with the other haroom plugins (ddaro, triad, mangchi).

### 2. Install

```
/plugin install prism
```

Restart Claude Code after install.

## Created by

haroom
