# Changelog

All notable changes to the Prism plugin are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-04-20

Initial public release. Evolved from an earlier `review-all` skill that ran 4
agents in parallel without verification.

### Added
- Five parallel review agents: Conflict Detection, Improvement, Devil's Advocate,
  Code Review, Robustness (4-axis: concurrency / failure-recovery / data-integrity
  / state-transitions).
- Default 2-pass mode: Pass 1 discovers, Pass 2 verifies findings only one agent
  flagged (singletons). Cross-agent agreement skips Pass 2 automatically.
- Three modes: default `verify`, `--quick` (single pass), `--adversarial`
  (re-checks findings the main agent would dismiss).
- Batched Verifier: one verifier call covers all singletons regardless of count
  - keeps Pass 2 cost flat.
- Report buckets: CRITICAL/HIGH/MEDIUM/LOW + Rejected Singletons + Depends-on-
  Context + Cross-Agent Agreements + Disagreements + Recommended Action Order.

### Known Gaps
- Multi-file or whole-repo reviews are bounded by what fits in a single agent's
  context - large projects benefit from running prism on subsections.
- The Verifier sees Pass 1 outputs but cannot re-spawn agents; it cannot
  challenge an agreement that turns out to be a *shared* false positive.
- For markdown/spec review, `triad` is a better fit (3 perspectives + iteration).

### Companion tools
- `mangchi` - iterative cross-model file refinement (Codex CLI required).
- `prism-devil` - aggressive single-agent attacker-mindset probe.
- `triad` - 3-perspective deliberation for markdown.
