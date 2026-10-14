# Finding record v2 + confidence model

Canonical copy lives in `prism-all/references/`; `prism` and `prism-codex` carry byte-identical
copies produced by `skills/sync-review-parsers.sh`. Every reported finding is one record.
`verify-evidence.js` finalizes `fingerprint`, `evidence_strength`, and `status` (model values are
overwritten).

## Record

```yaml
id: PRISM-001                    # run-scoped, sequential; NOT stable across runs (use fingerprint)
candidate_id: c1                 # links back to the discovery candidate (batch reconciliation)
fingerprint: a3f92c1e0b71        # sha1(normPath|symbol|category|claim-slug)[:12] — computed by verify-evidence.js
unpinned: false                  # true when file:null → excluded from cross-run dedup
file: src/auth.py                # null allowed only for SUSPECTED
lines: 84-102
symbol: reset_password
category: security               # correctness|security|state|integration|testability|redteam|improvement
                                 # design lenses map: conflict→integration, claim-accuracy→correctness,
                                 # devil→correctness, robustness→state, improvement→improvement
severity: HIGH                   # CRIT|HIGH|MED|LOW
status: SUPPORTED                # SUSPECTED|SUPPORTED|REPRODUCED|REJECTED
missing: null                    # required string when SUSPECTED (what blocked grounding)
degraded: false                  # true only for infra markers (never a real finding)

claim: "Reset token can be reused"
preconditions:
  - "Attacker has a previously used reset token"
execution_path:
  - reset_password() → token lookup → password update → token not invalidated
evidence:
  - "src/auth.py:98 — token record remains active after successful update"
suggested_fix: "invalidate the token row inside the update transaction"   # carried from the v1 line
checklist_ref: null              # "#14 [ACTIVE]" | "[not-in-checklist]" — only when a project checklist was loaded
chain: null                      # "CHAIN-1" when this finding composes with others into an attack chain

reproduction:
  status: NOT_RUN                # NOT_RUN|REPRODUCED|NOT_REPRODUCIBLE_IN_CURRENT_ENVIRONMENT|TIMED_OUT|STATIC_EVIDENCE_ONLY|REQUIRES_EXTERNAL_SERVICE|REQUIRES_DOMAIN_CONFIRMATION|NOT_REPRODUCED_BY_ATTEMPT
  suggested_test: test_reset_token_cannot_be_reused
  expected_signature: null       # pre-registered failure (exception/assertion) before running
  command: null                  # exact command when run
  result: null                   # verbatim tail when run

confidence:
  model_agreement: "3/5"         # /prism, /prism-codex: n/5 lenses. /prism-all: see `agreement` below
  evidence_strength: MEDIUM      # NONE|WEAK|MEDIUM|STRONG  (finalized by verify-evidence.js)
  label: HIGH                    # closed enum below

agreement:                       # /prism-all only
  claude: ["security"]
  codex: ["security"]
  cross_model: true
```

## Field rules

- `file/lines/symbol` are **required** for `SUPPORTED`+ (no location → cannot be SUPPORTED).
- `evidence` requires ≥1 quoted line for SUPPORTED, and each quote must actually appear at the
  cited lines (`verify-evidence.js` enforces this; mismatch → `SUSPECTED (EVIDENCE_QUOTE_MISMATCH)`).
- `SUSPECTED` may have `file: null` but must carry `missing:`.
- `reproduction.status` = `NOT_RUN` in default/`--quick` mode; other values only under `--reproduce`.
- `--quick` emits degenerate records (status SUSPECTED, evidence_strength NONE, reproduction
  NOT_RUN, fingerprint null).
- `evidence_strength`: NONE (nothing pinned) / WEAK (location only) / MEDIUM (location + execution
  path + machine-verified quote) / STRONG (reproduced — only Pass 3 sets it).
- A finding with `degraded: true` is an infrastructure marker (parser could not read a lens). It is
  never a candidate: route it to the DEGRADED LENSES note, exclude from counts and fingerprinting.

## Confidence (closed enum, computable from stored fields)

`confidence = model_agreement × evidence_strength`, minus honesty penalties.
Label enum: `{LOW, MEDIUM, MEDIUM-HIGH, HIGH, HIGH+, VERY-HIGH}`.

| model_agreement | evidence_strength | Label |
|---|---|---|
| single lens | NONE / WEAK | LOW |
| 2+ same-model lenses | NONE / WEAK | MEDIUM (hard cap — same model repeats the same misunderstanding) |
| cross-model (`/prism-all` only) | NONE / WEAK | MEDIUM-HIGH |
| any | MEDIUM (location + path + machine-verified quote) | HIGH |
| cross-model | MEDIUM | HIGH+ |
| any | STRONG (reproduced) | VERY-HIGH |
| — | — (`status: REJECTED`) | reported in the REJECTED section, no label |

Cross-model rows never fire in single-engine skills. On a design-doc target, a finding whose evidence
quotes only the document is capped at MEDIUM (every discovery agent already read the doc); a finding
whose evidence quotes repository code is graded normally (see `design-lenses.md`).

## Certainty language

Only `REPRODUCED` may use certainty language in the report ("does happen"). `SUPPORTED` uses
"the code path allows"; `SUSPECTED` uses "may".
