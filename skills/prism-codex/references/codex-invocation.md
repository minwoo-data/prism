# Codex CLI invocation contract (prism-codex)

The contract is **code**: `codex-run.sh` in this skill directory. Run it; do not re-type a
template and do not call `codex exec` directly. This file explains *why* the script does what it
does and what to do when an angle degrades. You do not need to read it to run a review.
`prism-codex` carries a generated copy (`sync-review-parsers.sh` rewrites the skill name).

## Invariants and where they are enforced

| # | Invariant | Enforced by |
|---|---|---|
| 1 | Prompt goes through a file + stdin, never argv | `codex-run.sh` (selftest: "prompt is not on argv") |
| 2 | Static prompt text comes from quoted heredocs; nothing is shell-expanded | the orchestrator passes the lens on stdin with `<<'EOF'`; the script only `cat`s files |
| 3 | Prompt order: preamble → target(s) → checklist (security/redteam only) → lens → output contract | `codex-run.sh` (selftest: order, checklist cases) |
| 4 | 180,000-byte guard per call: oversized → degraded, never `exit` | `codex-run.sh` |
| 5 | Timeout 300 s, reasoning effort `high` | `codex-run.sh` (`PRISM_CODEX_TIMEOUT`, `PRISM_CODEX_EFFORT` override per run) |
| 6 | Sandbox Safety Preamble is the first bytes of every prompt | `codex-run.sh` `preamble()` (the only copy of the text) |
| 7 | Secret scrub over everything Codex printed, before anything is copied, including the stderr tail of a failed call | `codex-run.sh` `secret_patterns()`; `codex-run.sh scrub <file>` for reproduction logs |
| 8 | Only the `--output-last-message` answer is parsed | `codex-run.sh` (no last message → degraded) |
| 9 | Codex commands run in the read-only sandbox (no writes, no network); bypass only by explicit `PRISM_CODEX_SANDBOX=bypass` | `codex-run.sh` (selftest: sandbox cases) |
| 10 | Unscrubbed output (prompt in progress, raw stream, last message) lives in a private scratch dir under `$TMPDIR`, never in the run dir; scratch left by a hard-killed run is removed by the next run | `codex-run.sh` |
| 11 | One attempt per angle at a time (lock with the owner's pid; a dead owner's lock is taken over) | `codex-run.sh` (exit 2 while the other attempt runs) |
| 12 | The findings grammar the script appends and the one SKILL.md gives the Claude agents are the same | `codex-run.sh --selftest` |

Why effort is pinned: xhigh exhausts the Codex usage limit within a few calls. Measured on CLI
0.159.3 with a 24 KB prompt: high 44 s, xhigh 113 s, max 227 s. 300 s leaves headroom to raise it.

Why one Bash call per angle: an outer timeout or hang inside a loop loses every later angle as a
missing file. The script pre-creates each output as `[fallback: not-started]`, so a killed call
reads as degraded instead of silently disappearing.

## Fallback markers

A degraded angle's output file starts with one of these. `parse-findings.js` turns any of them
into `degraded:true`, which is infrastructure, not a candidate: it goes to
`meta.degraded_angles` and is excluded from the Evidence pass, candidate counts and fingerprinting.

| Marker | Meaning |
|---|---|
| `[fallback: not-started]` | The call never finished writing (killed outer process) |
| `[fallback: prompt-build-failed]` | A target, the checklist or the lens could not be read or scanned |
| `[fallback: prompt-too-large]` | Prompt over 180,000 bytes. Same for every angle: narrow the target or use `/prism` |
| `[fallback: timeout]` | No answer within `PRISM_CODEX_TIMEOUT` |
| `[fallback: codex-unavailable]` | Non-zero exit; the marker keeps a 300-byte stderr tail (auth, config, model errors) |
| `[fallback: no-last-message]` | Exit 0 without a final message. The raw stream is never parsed instead: it echoes the prompt, so example findings in the target would be read as real ones |
| `[fallback: publish-failed]` | The answer could not be moved into place |
| `[fallback: interrupted]` | The wrapper got INT/TERM/HUP (for example an outer Bash timeout); Codex was stopped, partial output destroyed, the DEGRADED JSON still written; exit 130. An interrupt that comes while a leak is being quarantined keeps the security marker instead (status `secret-scrubbed(...)`): read the JSON `status` before re-running after exit 130 |
| `[fallback: scan-failed] stream=<s>` | A file could not be scanned for secrets, so it was treated as a leak (fail closed). Security marker: never auto-retried; the user checks the disk and permissions first |
| `[fallback: CLEANUP FAILED: delete <dir> by hand ...]` (extra line) | The scratch dir outside the run dir could not be deleted; it may hold unscrubbed Codex output. Also `cleanup_failed` in the JSON and `cleanup_failed="<dir>"` on the summary line; on the leak path the status becomes `secret-scrubbed(...,cleanup-failed)`. Tell the user |
| `[fallback: codex-output-contained-secret-pattern] stream=<raw\|msg>` | Scrub hit. Raw output was destroyed. Security incident, not a finding |
| `[fallback: prompt-modified-during-run]` | Codex wrote a new secret-shaped string into its own prompt file. Prompt and output destroyed. Treat like a scrub hit |

The scrub allows a secret-shaped string back only when the prompt contained it before Codex ran:
`codex exec` echoes the prompt into its raw stream, so a target with test fixtures would otherwise
quarantine every angle. Values are compared without trailing punctuation, quotes or backticks, and placeholder values (`your-...`, `changeme`, `example`, `<...>`) are ignored, so a reviewer quoting the target or writing an example fix is not a leak. That allow set is held in the wrapper's memory, so a Codex that edits the
prompt file cannot widen it. A private-key header is the same for every key, so when one appears
every base64 run of 32+ characters must also have been in the prompt. Anything Codex found
elsewhere is quarantined, and a scan that cannot read a file counts as a hit. Obvious credential
files (`.env`, `*.env`, `.envrc`, `dotenv`, `*.pem`, `*.key`, `*.token`, `id_*`, `.npmrc`, `.git-credentials`, `secrets.yaml`, `*credential*.json`, ..., case-insensitive, through symlink chains) are refused as targets or checklist, because the
wrapper itself would copy them into the prompt.

## Fallback policy (per-angle accounting)

| Situation | Action |
|---|---|
| An angle's Codex call degrades | Retry once (optionally with `PRISM_CODEX_MODEL=<slug>`) only for `timeout`, `codex-unavailable`, `no-last-message`; never for `prompt-too-large` / `prompt-build-failed` (same input fails again). Record it in `meta.degraded_angles`. If the Claude side of the same lens survived, tag it `[cross-model-unavailable]` (never demote below singleton) |
| An angle's Claude agent fails | `[fallback: claude-unavailable]`; the lens is processed from the Codex side only |
| Both engines fail on one lens | No cross-model for that lens: degraded, the run continues |
| Evidence-pass chunk fails / omits a candidate | **That candidate only** → `SUSPECTED (missing: EVIDENCE_PASS_FAILED)`; never re-verdict decided candidates, never fail the run |
| One engine degraded on 3+ lenses | State it in the header (`Codex 2/5`) and suggest `/prism` (Codex broken) or `/prism-codex` (Agent broken). The report claims only what actually ran |
| Secret-scrub hit, `prompt-modified-during-run`, `scan-failed` | Quarantine as a security-incident note, excluded from defect triage, operator warning shown outside the findings. Never auto-retry; a manual rerun keeps the old marker as `*.incident.<timestamp>` |
| Exit 2 (usage/config/install, or the same angle still running) | Fix and rerun; not a model problem |

## Operator rules

- Do not run prism from a working directory that holds `.env`, `dotenv`, `*credentials*`,
  `*secret*` files Codex could read. The preamble forbids reading them; the script warns when the
  working directory holds them. This is defense in depth.
- Bash tool timeout for each call: (`PRISM_CODEX_TIMEOUT` + 30) × 1000 ms, at most 600000, so `PRISM_CODEX_TIMEOUT` ≤ 570 (the script refuses more). A shorter outer timeout kills the wrapper first (`interrupted`).
- Codex runs in the **read-only sandbox** (`-s read-only`): every command it runs can read files
  but cannot write them or reach the network, so a prompt-injected Codex cannot exfiltrate over
  the network, edit the repo, or rewrite its own prompt. It can still *read* secrets and print
  them, which is what the preamble and the scrub are for. Measured on Windows (CLI 0.159.3, sandbox
  `elevated`): same findings and speed as without the sandbox.
- The sandbox cannot reach some locations, e.g. a Google Drive mount (`H:` on Windows returns
  "access denied"). Pass such files as `--target`/`--checklist` (the wrapper reads them, outside
  the sandbox), or, for one run, `PRISM_CODEX_SANDBOX=bypass`. Bypass is never automatic: a
  sandbox failure degrades the angle (`codex-unavailable` with the stderr tail) and the summary
  line always prints `sandbox=read-only|bypass`.
- `--artifacts=docs` writes target source and Codex output into the repo; `codex-run.sh init`
  refuses unless `docs/prism-codex/` is gitignored.
- Codex model: `~/.codex/config.toml` default (`gpt-5.5` recommended). If calls fail on the model,
  re-run with `PRISM_CODEX_MODEL=<slug>` set to the first `visibility: list` slug in
  `~/.codex/models_cache.json`, and record it in state.

## Incident record: 2026-05-22 receipt_processor compose round

Three Codex agents (conflict / code-review / devil) spontaneously ran `docker compose config`,
which resolved `env_file:` and inlined six operator secrets (ANTHROPIC / GEMINI / OPENAI /
GOOGLE_PLACES / GMAIL_APP_PASSWORD / FLASK_SECRET_KEY) into their reasoning output. Four prism
files sat on disk for ~3–15 minutes; the session transcript keeps them permanently (keys were
rotated). The GitHub remote stayed clean (`docs/prism-codex/` was gitignored). This incident created
invariants 6 and 7 and the operator rules above. A recurrence invalidates the round and triggers
immediate key rotation.

## Why the contract became a script (0.4.0)

On 2026-10-13 a prism-codex run on a design doc skipped the template: the orchestrator wrote its own
runner that looped every angle in one Bash call, without the preamble, the scrub, the effort pin or
the `PRISM-FINDINGS v1` contract. Rules written as prose are followed most of the time; the ones
whose failure leaks secrets have to be code.
