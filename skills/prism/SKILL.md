---
name: prism
description: Multi-angle review - 5 agents in parallel discover, then a Verifier pass cross-checks singleton findings. Agreement auto-confirms. Use when user says "prism", "prism 돌려", "prism <file>", "full review", "design review", or before major decisions.
argument-hint: "[file-or-topic] [--quick] [--adversarial]"
context: fork
user-invocable: true
---

# Prism - Multi-Angle Review with Verification

> 5 agents look through different facets. The Verifier cross-checks anything only one agent saw. Agreement passes through; singletons get scrutinized.

## Modes

| Invocation | Behavior |
|---|---|
| `/prism <target>` | **Default: 2-pass verify.** Pass 1 finds, Pass 2 verifies singletons. |
| `/prism <target> --quick` | 1 pass only. Skip verification - use when speed > signal. |
| `/prism <target> --adversarial` | 1 pass + REJECT re-check. Re-examines findings you'd dismiss, catching self-bias. |
| `prism 돌려`, `prism <file>` | Same as `/prism <target>` (default verify). |

## Target resolution

- If argument is a file path → review that file.
- If argument is a topic/description → review relevant files you locate.
- If no argument → review the current project's overall design and quality.
- **Always read the full target content first** and pass it verbatim to each agent. No summarization.

---

## Pass 1 - Parallel discovery (5 agents)

Launch all 5 agents in a **single message** with multiple Agent tool calls. Each runs in a forked context.

### Agent 1: Conflict Detection

> You are a **Conflict Detection Agent**. Find conflicts, contradictions, and integration risks.
> Analyze: overlaps with existing code/skills, config contradictions, tool chain conflicts, edge cases where components disagree.
> Rate each finding: CRITICAL / HIGH / MEDIUM / LOW.

### Agent 2: Improvement

> You are an **Improvement Agent**. Suggest concrete enhancements.
> For each suggestion: current state → proposed improvement → rationale.
> Focus on: formula/logic improvements, efficiency gains, UX improvements, missing features, integration opportunities.

### Agent 3: Devil's Advocate

> You are a **Devil's Advocate Agent**. Find weaknesses, failure modes, and reasons this might not work.
> Be brutally honest. Cover: self-evaluation bias, gaming/Goodhart risks, practical failure modes, cost/time, false confidence, scope creep, regression risks.
> Rate each: CRITICAL / HIGH / MEDIUM / LOW with suggested mitigation.

### Agent 4: Code Review

> You are a **Code Review Agent**. Review for clarity, completeness, correctness, and consistency.
> Check: ambiguous instructions, missing edge cases, pattern consistency with existing code, actionability of each step.
> Format: [SECTION] Issue → Suggested fix.

### Agent 5: Robustness (4-Axis)

> You are a **Robustness Agent**. Evaluate the target against 4 orthogonal failure axes. For each axis, enumerate concrete scenarios specific to this code/design (not generic advice). If an axis has no realistic concern, say "N/A - <reason>".
>
> **Axis 1 - Concurrency**: Two users/requests/workers hit this at once. Race conditions, double-submit, lost update, duplicate inserts, lock contention, TOCTOU.
> **Axis 2 - Failure & Recovery**: Operation interrupted mid-flight (crash, network drop, timeout, partial write). Idempotency, retry safety, rollback, orphaned state, compensating actions.
> **Axis 3 - Data Integrity**: FK cascade direction (CASCADE/RESTRICT/SET NULL), unique/CHECK constraints, referential consistency, overwrite semantics (upsert vs replace vs merge), schema version mismatch.
> **Axis 4 - State Transitions**: Every reachable state and every transition. Forward (A→B), reversal (B→A), forbidden transitions, terminal/stuck states, re-entry after failure.
>
> Format per finding: `[Axis N] Scenario → Current behavior → Risk (CRITICAL/HIGH/MEDIUM/LOW) → Suggested fix`
> End with a **Coverage Summary**: which axes have gaps, which are well-handled.

---

## Synthesis triage

After all 5 agents return, classify every finding:

- **AGREEMENT** - flagged by 2+ agents (semantic overlap counts, not exact wording). These are **auto-CONFIRMED**; they skip Pass 2.
- **SINGLETON** - flagged by exactly 1 agent. Eligible for Pass 2 verification.

Short-circuit rules:
- If `--quick` flag set → skip Pass 2. Go straight to final report (label everything by source agent, no verify label).
- If Pass 1 produces 0 singletons → skip Pass 2 (nothing to verify).
- If total findings ≤ 3 AND `--quick` not set → still run Pass 2, but the verifier gets all findings (cheaper than triaging).

---

## Pass 2 - Singleton verification (default mode)

**One Verifier Agent handles ALL singletons in a single call** - do not spawn one agent per finding (wasteful).

Spawn a general-purpose agent with this prompt:

> You are a **Verifier Agent**. Five reviewers just analyzed the same target. For each **singleton finding** below (only one reviewer flagged it), decide whether it is a real issue, a false positive, or depends on context the reviewer didn't know.
>
> Rules:
> - Read the full target (provided below) and the full output of all 5 Pass 1 agents before verdicting.
> - For each singleton, output one of: `CONFIRMED` / `REJECTED` / `DEPENDS`.
> - `CONFIRMED`: the finding is valid. You may lower severity if the original rating seems inflated.
> - `REJECTED`: the finding is wrong - typically the reviewer lacked context. State which context made the difference.
> - `DEPENDS`: the finding is conditional. State the condition and whether it likely holds here.
> - Do NOT invent new findings. Your job is verification, not discovery.
>
> Format:
> ```yaml
> - id: <singleton_id>
>   original: "<finding summary>"
>   original_severity: CRITICAL|HIGH|MEDIUM|LOW
>   verdict: CONFIRMED|REJECTED|DEPENDS
>   adjusted_severity: <same format, only if CONFIRMED>
>   reasoning: "1-2 sentence justification"
> ```
>
> Inputs follow: [target content] [Pass 1 outputs - all 5 agents] [singleton list with IDs]

### Adversarial mode (`--adversarial`)

Instead of (or in addition to) singleton verification, re-examine findings you were about to REJECT. This protects against self-bias. Swap the verifier prompt's "REJECTED" test toward:

> You suspect the reviewer got this wrong. Before agreeing, argue the opposite: what if they're right and you're missing context? Only REJECT if your counter-argument is more specific and better-sourced than theirs.

---

## Final report

```
PRISM REPORT - {target} - {timestamp}
Mode: {verify | quick | adversarial}

## CRITICAL (must fix)
- [3/5 agreement] Finding → Fix
- [1/5 → verified] Finding → Fix (Verifier: brief reason)

## HIGH (should fix)
- ...

## MEDIUM (consider)
- ...

## LOW (minor)
- ...

## Rejected Singletons   ← only if Pass 2 ran
Findings one agent flagged but the Verifier dismissed. Listed for transparency.
- [source agent] Finding - Verifier: reasoning

## Depends-on-Context    ← only if Verifier returned DEPENDS
- [source agent] Finding - Condition: ... - Likely in this project? yes/no/unclear

## Cross-Agent Agreements
Items where 2+ agents converged. Highest-confidence bucket.

## Cross-Agent Disagreements
Items where agents contradicted each other. Present both sides; Verifier may have picked a side.

## Recommended Action Order
Numbered list, highest impact first. Mix confirmed agreements + verified singletons.
```

**Labeling rules**:
- `[N/5 agreement]` → N agents flagged (semantic, not literal).
- `[1/5 → verified]` → singleton that passed Pass 2.
- `[1/5 → rejected]` → moved to "Rejected Singletons" section.
- `[1/5 → depends]` → moved to "Depends-on-Context" section.
- In `--quick` mode, drop the verification annotations - just `[source agent]`.

---

## Rules

- Each Pass 1 agent runs with `context: fork`; the main context stays clean.
- Pass full target content to each agent. Never summarize the input.
- If two agents return contradicting advice, surface both under "Disagreements" - do not pick a winner unless the Verifier ran and resolved it.
- Keep synthesis concise: max 3 lines per finding.
- Verifier runs in a **single call** covering all singletons, not one-per-finding.
- Agreement bucket is cheap signal; trust it more than any single agent's judgment.

## Cost & speed notes

| Mode | Pass 1 agents | Pass 2 calls | Relative cost | When to use |
|---|---|---|---|---|
| `--quick` | 5 | 0 | 1.0× | Fast sanity check, already-triaged targets |
| default (verify) | 5 | 1 (batched) | 1.2-1.4× | Standard review, most cases |
| `--adversarial` | 5 | 1 (batched) | 1.2-1.4× | When you suspect you'll dismiss real issues |

Default is verify because false positives from a single agent are the most common failure mode - and batched verification is cheap.

## Companion skills

- **mangchi** - after prism identifies weak files, use `/mangchi <file>` to iteratively harden one file with Codex cross-model review.
- **triad** - for markdown/spec review (not code), use `/triad <file>` for 3-perspective deliberation.
- **gsd-discuss-phase** - for upstream design decisions (before code exists), the 4-axis robustness probe runs there.
