# Changelog

All notable changes to the Prism plugin are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-07-14

Evidence over agreement. The review's job is no longer "did reviewers agree?" but
"is this defect grounded in code — and can we watch it fail?"

### Changed (breaking behavior)
- **Agreement no longer auto-confirms.** The 0.1.x rule "2+ agents → CONFIRMED" is retired:
  all prism agents share one model, and same-model agents can share the same misunderstanding.
  Agreement now sets *priority and baseline confidence only* (hard cap MEDIUM without evidence).
- **Every candidate goes through an Evidence pass** (was: singletons only). The pass must pin
  `file`/`lines`/`symbol`, trace the execution path, and quote the evidence line before a
  finding can be reported as confirmed.
- **Statuses replace verdicts**: `SUSPECTED` (reasoning only) → `SUPPORTED` (static evidence)
  → `REPRODUCED` (failing test actually run) / `REJECTED` (contradicting evidence, quoted).
  Report sections are organized by status; certainty language is gated by status.
- **Default lens set is defect-focused** for code targets: Correctness & Contracts / Security &
  Trust Boundaries / State, Concurrency & Recovery / Integration & Regression / Testability &
  Observability. The Improvement lens moved behind `--include-improvements` (suggestions are
  labeled separately and excluded from defect counts). `--lenses=classic` restores the original
  set; non-code targets (docs/plans) auto-select classic.
- prism-all: Tier 1/2/3 now map to *initial confidence*, not verdicts. Cross-model agreement
  = highest-priority candidate (MEDIUM-HIGH baseline); intra-model agreement capped at MEDIUM.
- prism-all/prism-codex artifacts default to the OS temp dir (`$TMPDIR/prism-*/<slug>`) instead
  of `docs/` — repos stay clean. `--artifacts=docs` restores the old location.

### Added
- **`--reproduce`** — reproduction pass: for SUPPORTED findings (CRIT/HIGH first, max 5/run),
  search existing tests, then write a *minimal failing test in the OS temp dir* (never the
  project tree), run it with the project's own runner, and record the verbatim command+result.
  Outcome vocabulary: `REPRODUCED` / `NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT` /
  `STATIC_EVIDENCE_ONLY` / `REQUIRES_EXTERNAL_SERVICE` / `REQUIRES_DOMAIN_CONFIRMATION` —
  "we didn't run it" is stated, never hidden. A passing repro test *downgrades* the finding.
- **Finding record v2** — required fields per finding: `id`, `fingerprint` (stable
  sha1(file|symbol|category)[:8] for cross-run dedup), `file`, `lines`, `symbol`, `category`,
  `severity`, `status`, `claim`, `preconditions`, `execution_path`, `evidence`,
  `reproduction{status,suggested_test,command,result}`, `confidence{model_agreement,
  evidence_strength,label}`.
- **Confidence model** — composite of model diversity + lens diversity + code evidence +
  reproduction − missing context − unverifiable assumptions, with an explicit label table
  (same-model agreement ≤ MEDIUM; location+path+quote → HIGH; reproduction → VERY HIGH).
- **`--diff` mode** — change-scoped review: hands each lens the hunks, pre-change code,
  enclosing symbols, callers/callees, related tests, and PR description; every finding must
  reference a hunk. Frame: "what regression does this change newly introduce?"
- **`--format json`** — `prism-report.json` with meta + finding records v2 (fingerprint-based
  dedup for CI). SARIF output and a GitHub Action are on the roadmap, not in this release.

### Roadmap (not in 0.2.0)
- prism-evals: seeded-defect + clean-control benchmark set with published precision/recall/cost.
- GitHub Action with PR inline comments (summary + Critical/High only) and SARIF upload.

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
