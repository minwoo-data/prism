# Changelog

All notable changes to the Prism plugin are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

prism-ideas, slice S1: the idea pass's contracts and its deterministic gate. No skill calls it yet,
so prism's behavior does not change.

### Added
- **`verify-ideas.js`** (canonical in prism-all, synced to prism and prism-codex):
  - `gate` takes the last closed `PRISM-IDEAS v1` fence (only an echoed contract example is
    skipped; a draft or planted fence earlier in the output never wins, and a cut-off final fence is
    no answer), validates every JSON line and flattens every text to one line. Ideas past the 3rd
    per lens become `OVER_CAP`.
  - `gate` checks every ground. A finding ID counts only if the final `checked.json` has it as
    `SUPPORTED`/`REPRODUCED` and `verify-evidence.js` quote-checked it. A `path:lines — quote`
    counts only if the quote is really at those lines, in a file under the repo root or a
    `--context` file. Quotes span at most 40 lines and are at least 8 characters; network paths,
    credential files (the `codex-run.sh` globs, on the real path), `.git` internals and
    secret-shaped quotes are refused (code that only names a secret is fine). A quote is matched
    against every file its path can mean, so a repo file and a same-named `--context` file never
    shadow each other. No valid ground means `UNGROUNDED`, and a failed ground's text is never kept.
  - Idea keys are `<engine>-<n>-<hash>`, so a verdict or group from another gate run cannot land on
    a different idea.
  - `check` applies `PRISM-IDEA-CHECK v1` verdicts, one checker output per batch. A `DROP` without
    a verified quote becomes `WEAK` unless its basis is `not-solving`; a missing verdict becomes
    `UNCHECKED`, and a rejected one says why. An empty or cut-off checker answer answers nothing; a
    failed batch is counted and makes the result `partial` or `degraded` until a retry answers its
    keys; two checkers that disagree leave the stricter verdict.
  - `rank` sets `cross_model` only from explicit groups, orders ideas by content alone, and reports
    degraded proposers and checkers in `meta`.
  - Unreadable inputs, a findings file of the wrong shape and a missing `verify-evidence.js` exit 2.
  - `--selftest` (90 cases; all 45 deliberate code and contract breaks tried are caught).
- **`templates/ideas-contract.md`** and **`templates/idea-check-contract.md`**: the two output
  formats, each in one file that is appended verbatim and last to every prompt that needs it.
  The selftest fails if a contract stops naming a field, value or limit the script enforces.
- **`references/ideas.md`**: the three idea lenses (class / route / subtract), the checker prompt,
  the prompt assembly order and the ranking rules.

### Changed
- `verify-evidence.js` exports its quote matcher (`quoteWindow` / `quoteInWindow`) for
  verify-ideas.js. Its CLI output and selftest are unchanged, and the CLI only runs when invoked
  directly.
- `verify-independence.js` requires the new files and runs `verify-ideas.js --selftest` under
  `--strict`.

### Fixed
- `sync-review-parsers.sh` reported "synced" even when a copy failed to land (a failed `mv` inside
  `a && b` does not trip `set -e`). It now creates missing directories and exits 1 on any failed
  step.

## [0.4.2] - 2026-10-14

Hardening of `codex-run.sh` from a prism-all review of the same code ported to triad (39 findings
confirmed; the shared ones are fixed here).

### Fixed
- **False quarantines:** a reviewer quoting a target value in backticks or with a Korean particle,
  or writing a placeholder fix (`<your-password>`, `your-client-secret`), quarantined the whole
  angle. Values are now compared without trailing punctuation/quotes and placeholders are ignored.
- **Missed secrets:** `NAME_SECRET_KEY=` / `AWS_SECRET_ACCESS_KEY:` style names, `sk-ant-oat01-`,
  `sk_live_`, `gho_`/`ghs_`, URL passwords (`scheme://user:pw@`) and JWTs are now caught.
- **Prompt scan failure was masked** (no pipefail: the status was `sort`'s); Codex then ran and the
  result was mislabelled as a prompt modification. Now `prompt-build-failed` before any call.
- A scan failure after the call gets its own `scan-failed` marker; markers name the stream.
- `PRISM_CODEX_TIMEOUT=00` meant "no limit" to GNU timeout; leading zeros and values above 570 are
  refused (the caller's Bash timeout caps at 600 s).
- Interrupted calls now also write their DEGRADED JSON (still exit 130).
- The `no-last-message` marker keeps the stderr tail; failure tails are printable ASCII with fence
  brackets removed, so they can never parse as findings.
- After the launcher exits, its whole process group is killed before the scrub reads the files;
  the watchdog no longer turns a just-finished answer into a timeout.
- Credential-file refusal covers the preamble's families (`*.env`, `.envrc`, `dotenv`, `*.token`,
  `id_*`, `.git-credentials`, `secrets.yaml`, `*credential*.json`, ...), case-insensitively,
  through symlink chains, for `--checklist` too.
- `verify-independence.js --strict` picked WSL's `bash.exe` when run from PowerShell and failed
  with no reason shown; it now prefers Git Bash, prints the failing cases, has a timeout, and checks
  that the installed Codex CLI accepts every flag the script passes.
- `sync-review-parsers.sh` compared after copying (its drift check could never fail) and lost the
  sed-generated copies in a subshell; it now builds copies in a temp dir, reports drift first, and
  has `--check`.
- The selftest no longer inherits `PRISM_CODEX_*` from the caller.

### Added
- Unscrubbed scratch (prompt in progress, raw stream, last message) moved to a private dir under
  `$TMPDIR`; a hard-killed run's scratch is removed by the next run.
- One attempt per angle at a time (lock; a dead owner's lock is taken over).
- A rerun keeps a previous security marker as `*.incident.<timestamp>` instead of overwriting it.
- `model=` / `effort=` in the summary line; `status`, `model`, `effort`, `sandbox`, `seconds` in
  the JSON.
- Selftest: 57 cases, including a self-scan that keeps literal secret-shaped strings out of the script (GitHub push protection blocked a fake key once), each new protection mutation-tested (11 mutants, each caught). It also
  checks that SKILL.md still carries the findings grammar the script appends.
- SKILL.md: Bash timeout rule, exit codes, which statuses may be retried.

## [0.4.1] - 2026-10-14

### Changed
- **Codex runs in the read-only sandbox** (`-s read-only`) instead of
  `--dangerously-bypass-approvals-and-sandbox`. Commands Codex runs can read files but cannot
  write them or reach the network: a prompt-injected Codex can no longer exfiltrate over the
  network, edit the repo, or rewrite its own prompt. Reading and printing a secret is still
  possible, which the preamble and scrub cover.
  Measured on Windows (CLI 0.159.3, `[windows] sandbox = "elevated"`): reads inside and outside
  the working directory work, writes and `curl` are blocked, and the same planted-bug review gave
  the same finding (13 s vs 16 s unsandboxed).
- `PRISM_CODEX_SANDBOX=bypass` is the explicit per-run opt-out, for paths the sandbox cannot
  reach (a Google Drive mount such as `H:` returned "access denied") or machines without sandbox
  support. Never automatic; the summary line always prints `sandbox=read-only|bypass`. Files the
  sandbox cannot reach can also be passed as `--target`, since the wrapper reads them itself.
- Selftest: 45 cases (sandbox default, bypass, invalid value).

## [0.4.0] - 2026-10-14

The Codex invocation contract is now a script. prism-all and prism-codex call
`codex-run.sh` once per angle instead of having the model re-type a bash template.

### Why
On 2026-10-13 a prism-all run on a design doc skipped the template: the orchestrator wrote its
own runner that looped every angle in one Bash call, with no Sandbox Safety Preamble, no secret
scrub, no effort pin and no `PRISM-FINDINGS v1` contract (so the parser could not read the
output). The preamble and scrub exist because of the 2026-05-22 secret leak; prose was not enough
to keep them.

### Added
- **`codex-run.sh`** (`skills/prism-all/`, byte-identical copy in `prism-codex/`):
  - `init <slug> [--artifacts docs]` creates a private run dir (`mktemp -d`, umask 077, refuses a
    base dir owned by someone else). `docs` is refused unless `docs/<skill>/` is gitignored.
  - `discovery <run-dir> <angle> --target F... [--checklist F]` with the lens prompt on stdin.
    The script prepends the preamble, embeds the target(s), adds the checklist for
    `security`/`redteam` only, appends the output contract, applies the 180,000-byte guard,
    runs Codex with a timeout (300 s) and pinned effort (`high`), scrubs the raw stream and the
    last message, and runs `parse-findings.js`. Prints one summary line plus the parser JSON.
  - `evidence <run-dir> <chunk-id>` for Codex Evidence-pass calls (same safety, no findings
    contract, no parsing).
  - `scrub <file>...` for reproduction logs (exit 3 when a file was sanitized).
  - `--selftest`: 42 cases against a fake Codex. `verify-independence.js --strict` runs it.
    Each protection was mutation-tested: removing it fails its case.
- `.gitattributes` keeps `*.sh` at LF.

### Changed (behavior the old template got wrong)
- **Targets with secret-shaped test fixtures no longer quarantine every angle.** `codex exec`
  echoes the prompt into its raw stream, so the old scrub flagged the target's own fixtures (found
  when prism-all reviewed this script: all five angles came back scrubbed). A string is now allowed
  back only if the prompt held it before Codex ran. That allow set lives in the wrapper's memory,
  so a Codex that edits its prompt file cannot widen it, and a secret written into the prompt is
  itself caught. A private-key header additionally needs its key body in the prompt.
- **The raw stream is never parsed as the answer.** It echoes the prompt, so example findings in
  the target (SKILL.md has some) would have been read as real ones. No last message → degraded.
- The scrub runs before a failed call's stderr tail is quoted (the old template quoted it
  unscrubbed), fails closed when a file cannot be scanned, and catches quoted assignments
  (`PASSWORD="..."`, `"TOKEN": "..."`), AWS access key ids, `github_pat_` and `sk-` keys.
- Codex runs as its own process group. Interrupting the wrapper (an outer Bash timeout) stops the
  whole group, waits for it, then destroys partial output.
- Timeout falls back to `gtimeout`, then to a portable watchdog (stock macOS); Windows
  `timeout.exe` is ignored. `PRISM_CODEX_TIMEOUT=0` is rejected.
- Every attempt works on private files (prompt, raw, message, json) and publishes them at the
  end, so an overlapping retry of the same angle cannot swap content under the scan; a stale
  parse from an earlier attempt is removed first.
- Obvious credential files (`.env`, `*.pem`, `*.key`, `id_rsa`, `.npmrc`, ...) are refused as
  targets. `--artifacts=docs` checks the real artifact names against `.gitignore` and refuses a
  directory with tracked files.
- New fallback markers: `timeout`, `no-last-message`, `interrupted`, `publish-failed`,
  `prompt-build-failed`, `prompt-modified-during-run`.
- `references/codex-invocation.md` keeps the reasoning (invariants with where each is enforced,
  fallback markers and policy, operator rules, incident record) and drops the template and the
  preamble copy. The preamble text now lives only in the script. The orchestrator reads this
  file only when an angle degrades.
- `PRISM_CODEX_MODEL` passes `-m` for the model fallback in Operator rules.

### Not changed
- Codex still ran with `--dangerously-bypass-approvals-and-sandbox` in 0.4.0 (fixed in 0.4.1).

### Cost
Codex-related orchestration text in a default prism-all run (5 Codex angles) drops from about
39 KB to about 2.7 KB. Before: the 10 KB contract was read before the first call, and the
preamble plus template (about 5.9 KB) was written out as model output once per angle. After:
SKILL.md grows by about 1.7 KB and each call is about 0.2 KB plus the lens prompt.

## [0.3.1] - 2026-10-13

Correction release. 0.3.0 made prism refuse documents and deprecated the classic lens set; that
broke `/ddaro:review`, whose design-review gate runs prism's design angles and triad's writing
lenses together on the same design doc. The split is now by *question*, not by file type:
prism asks "is it sound?" (code: defect lenses, documents: design lenses), triad asks "is the
document well written?".

### Changed
- **Documents are reviewed again**, with the **design lens set** selected automatically for
  markdown/design/plan targets (`--lenses=design` forces it; `--lenses=classic` stays as an alias).
  No deprecation, no refusal.
- The set is the old classic set with one angle replaced: **Code Review → Claim Accuracy**. Code
  Review's "ambiguous instructions / actionability" checks duplicated triad's LLM-clarity lens;
  Claim Accuracy instead verifies every statement the doc makes about the current system
  (`file:line` refs, "X already does Y", reuse-inventory rows) against the repository. Conflict
  Detection became **Conflict & Reuse** (name the existing capability so it can be reused).
- Design-target confidence: document-only quotes stay capped at MEDIUM; findings that quote
  repository code are graded like code findings (the machine quote-check covers them).
- **Codex calls pin `model_reasoning_effort=high` and a 300 s timeout** (was: config.toml default
  effort, 180 s). xhigh exhausts the Codex usage limit within a few calls; measured on CLI 0.159.3
  with a 24 KB prompt: high 44 s, xhigh 113 s, max 227 s. Override per run with
  `PRISM_CODEX_EFFORT` / `PRISM_CODEX_TIMEOUT`. Ported from the unreleased `feat/codex-effort`
  work into the 0.3.0 layout (`references/codex-invocation.md`).

### Renamed
- `references/classic-lenses.md` → `references/design-lenses.md` (sync script and
  `verify-independence.js` updated).

## [0.3.0] - 2026-10-13

Consolidation release. Prism becomes a **code-only** reviewer, absorbs `prism-devil`, and sheds
roughly 40% of the per-invocation SKILL.md weight by moving reference material out of the hot path.

### Added
- **`--redteam`** — the retired `prism-devil` plugin lives on as an optional 6th discovery lens
  (both engines in `/prism-all`). Hostile attacker-mindset probe over 10 prioritized attack
  surfaces, strict severity rubric, `[chain:X]` tags for findings that compose. Unlike the old
  plugin its findings go through the Evidence pass like everything else. Prompt in
  `references/redteam-lens.md`.
- **Project security checklist auto-load** — `docs/security-checklist.md` / `docs/security/checklist.md`
  / `SECURITY.md` / `docs/SECURITY.md` (first hit) is handed to the Security and Red Team lenses
  only; findings carry `[checklist:#N]` or `[not-in-checklist]`. Report gains **ATTACK CHAINS**
  and **CHECKLIST COVERAGE** sections. Record v2 gains `checklist_ref` and `chain`.
- **`references/` per skill** — `record-v2.md` (schema + confidence table), `redteam-lens.md`,
  `classic-lenses.md`, and (Codex skills) `codex-invocation.md` holding the Sandbox Safety
  Preamble, call template, scrub patterns, fallback table and the 2026-05-22 incident record.
  `sync-review-parsers.sh` now syncs these too and `verify-independence.js` requires them.
  prism-all/prism-codex previously pointed at "the `/prism` SKILL.md" for the record schema —
  a soft cross-skill dependency; each skill now carries its own copy.

### Changed
- **Code only.** A markdown/design/plan target is refused with a pointer to `/triad` instead of
  silently switching lens sets. The two parallel document-review paths (prism classic vs triad)
  collapse into one.
- **`--lenses=classic` deprecated** (removal in 0.4.0): no longer auto-selected for non-code,
  explicit use prints a deprecation warning in the header. The classic lenses overlapped each
  other and the defect set (Devil ⊂ Robustness + Security; Code Review overlapped everything).
- **Prompt assembly order fixed: target first, lens last.** The target is identical across all
  discovery agents, so it is now the shared prefix (prompt-cache friendly); lens-specific context
  (checklist) and the lens definition come after. Applies to Claude agents and the Codex template.
- **Evidence chunks are built by file.** Candidates are still prioritized (agreement → CRIT/HIGH →
  rest) but each ≤8 chunk is filled from one file before moving on, so the Evidence Agent reads a
  file once per chunk instead of once per candidate.
- **Integration lens** now says so when caller context was not supplied instead of guessing
  callers; `--diff` (the only mode that supplies real callers) is recommended for PR review.
- **Cost section** documents where tokens go and the `context: fork` implication (invoking prism
  at the end of a long session copies that session once before agents spawn — run early or in a
  fresh session).
- SKILL.md sizes: prism 418 → 296 lines, prism-all 464 → 238, prism-codex 351 → 173, with every
  rule preserved (moved, not dropped).
- README/README.ko: removed leftover 0.1 vocabulary (Verifier, CONFIRMED, Rejected Singletons),
  fixed the "Evidence pass is one batched call" claim (it has been chunked since 0.2.1), pointed
  the security row of the tool table at `--redteam`.

### Removed
- Companion-tool status for `prism-devil` (repo archived; `--redteam` supersedes it).

## [0.2.1] - 2026-07-14

Hardening pass over 0.2.0, driven by a `/prism-all` meta-review of the redesign
itself. 0.2.0 stated "evidence, not agreement" but left the evidence rung as an
LLM self-citation; 0.2.1 makes it machine-checkable and closes the runtime seams.

### Added
- **`verify-evidence.js`** (new deterministic script, self-tested) — greps every
  `SUPPORTED`/`REPRODUCED` quote against the cited file+lines and auto-downgrades a
  non-matching finding to `SUSPECTED (EVIDENCE_QUOTE_MISMATCH)`. Also computes the
  `fingerprint` in code (an LLM cannot compute sha1). `checked.json` is the source
  of truth — a fabricated quote can no longer ship as SUPPORTED. This is the
  keystone: it does for evidence what `parse-findings.js` did for parsing.
- **`skills/sync-review-parsers.sh`** — single-sources the scripts from prism-all to
  prism-codex and prism (they claim self-containment; now they actually match), and
  **verifies the sync held** (diff gate) instead of copying blind.
- **`verify-independence.js` in every skill** (was missing from the flagship `prism`)
  now lists the deterministic scripts in `REQUIRED_FILES` and, under `--strict`, runs
  each script's `--selftest`. A missing or silently-broken `parse-findings.js` /
  `verify-evidence.js` now FAILs the self-check instead of passing as "self-contained"
  — the load-bearing v0.2 scripts are covered by the integrity gate that already
  guards cross-plugin references.
- `<<<PRISM-RECORDS v2>>>` fenced output contract for the Evidence pass, so the
  pass that decides every finding's status is itself parseable + degrade-safe.
- Record v2 fields: `candidate_id`, `missing`, `degraded`, `suggested_fix`,
  `expected_signature`, `agreement{claude,codex,cross_model}`, `unpinned`.

### Changed / Fixed
- **Fingerprint** = `sha1(normPath|symbol|category|claim-slug)[:12]`, computed by
  verify-evidence.js — was `sha1(file|symbol|category)[:8]` freehand by the model,
  which collided two defects in one symbol and changed every run. `file:null` →
  `unpinned:true`, excluded from cross-run dedup.
- **`--reproduce` execution safety** — "temp dir" was a write guard, not a sandbox:
  importing the target runs its side effects with the operator's full env. Now
  mandates stripped env (`env -i` + allowlist), cwd=temp, no network, **no installs
  anywhere** (runners already on PATH only), one operator confirmation, and secret-
  scrub on output. Added `expected_signature` pre-registration, `TIMED_OUT` and
  `NOT_REPRODUCED_BY_ATTEMPT` statuses, a flake guard (2 identical runs), and the
  rule that setup/import errors are `NOT_REPRODUCIBLE`, not `REPRODUCED`.
- **Evidence pass is chunked (≤8 candidates/call)**, not one unbounded call that
  skims 30+ candidates; a failed chunk downgrades only its own candidates.
- **v0.1 vocabulary purged from the executable paths** — prism-all Pass 1 launched
  the *classic* lens names by default (would have run the wrong agents); prism-codex's
  trigger table + an anti-pattern line still described (and one *instructed*)
  singleton-only auto-confirm; commands/prism.md described "the Verifier prompt". All
  aligned to the defect lenses + Evidence pass. Classic prompts are now inlined in
  every skill (the "keep original wording" pointer was dangling).
- **Deterministic scope everywhere** — prism now also runs `parse-findings.js`;
  ANGLE-DEGRADED markers go to `meta.degraded_angles`, never into the Evidence pass
  (they used to be fed to a pass designed to reject them); confidence table is a
  closed enum computable from stored fields; LOCUS must be pipe-free (parser contract).
- **Artifacts hardened** — temp dir is `mktemp`-style with `chmod 700` (0.2.0's move
  to `$TMPDIR` had exposed target source world-readable on multi-user hosts and made
  scrub forensics ephemeral); `--format json` path pinned to the artifacts dir with
  atomic write; `--diff` range + caller-cap made deterministic; header now reports
  actually-degraded engines instead of asserting a full 10-agent run.

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
