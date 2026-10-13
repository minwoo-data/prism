# Classic lens set (`--lenses=classic`) — DEPRECATED

> Deprecated in 0.3.0, scheduled for removal in 0.4.0. Prism is a **code** reviewer. Documents,
> plans and specs belong to `/triad` (3 fixed perspectives, multi-round convergence). The classic
> set is kept one more version for anyone with existing scripts; it is **no longer auto-selected**
> for non-code targets — passing it explicitly prints a deprecation warning in the report header.

The original 0.1 lenses (Conflict / Improvement / Devil's Advocate / Code Review / Robustness)
overlap heavily with each other and with the defect set (Devil ⊂ Robustness + Security; Code
Review overlaps everything), which is why they were retired for code in 0.2.

Category mapping into record v2: conflict→integration, devil→correctness, code-review→correctness,
robustness→state, improvement→improvement.

## Lens prompts

- **Conflict Detection**: "Find conflicts, contradictions, and integration risks: overlaps with
  existing code/skills, config contradictions, tool-chain conflicts, edge cases where components
  disagree."
- **Improvement**: "Suggest concrete enhancements. For each: current state → proposed improvement
  → rationale. Focus on logic/efficiency/UX gains, missing features, integration opportunities."
- **Devil's Advocate**: "Find weaknesses, failure modes, and reasons this might not work:
  self-evaluation bias, gaming/Goodhart risk, practical failure modes, cost/time, false
  confidence, scope creep, regression risk. Give each a mitigation."
- **Code Review**: "Review for clarity, completeness, correctness, consistency: ambiguous
  instructions, missing edge cases, pattern consistency, actionability of each step."
- **Robustness (4-Axis)**: "Evaluate 4 orthogonal failure axes with concrete scenarios (N/A if
  none): (1) Concurrency — races, double-submit, lost update, TOCTOU; (2) Failure & Recovery —
  mid-flight crash/timeout, idempotency, retry safety, rollback, orphaned state; (3) Data Integrity
  — FK cascade direction, unique/CHECK constraints, upsert vs replace, schema mismatch; (4) State
  Transitions — every reachable state, forbidden/terminal/re-entry."

All five use the same `<<<PRISM-FINDINGS v1>>>` output contract as the defect lenses (SEV ∈
CRIT|HIGH|MED|LOW, pipe-free LOCUS, real block as the last fence). On a document target the
Evidence pass quotes the contradicting/verifying passage and the confidence label is capped at
MEDIUM (see `record-v2.md`).
