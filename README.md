# prism

> Language: **English** · [한국어](README.ko.md)

**Put one file through five specialized reviewers, then verify whatever only one of them caught.**

A single reviewer's "looks good" is the most common source of "how did we miss that?" two weeks later. prism runs five different biases over the same target in parallel, then runs a batched verifier over the findings only one agent flagged — the false-positive zone. Whatever two or more agents converged on passes straight through.

```
/prism <target>                  -> default: 5 agents + batched Verifier
/prism <target> --quick          -> 1 pass only, no Verifier
/prism <target> --adversarial    -> 1 pass + REJECT re-check (self-bias defense)
```

Five agents, five angles, one spectrum. Agreement passes through. Singletons get scrutinized. Target can be a file, a directory, or a topic.

---

## 30-second demo

**Without prism:**

You ask Claude "review this file". It says "looks good". You ship it. Two weeks later a bug surfaces that a different review angle (say, concurrency or config conflict) would have caught immediately. But no one thought to check that angle with an independent reviewer.

**With prism:**

`/prism src/services/auth.py`. Five reviewers look at the file in parallel with five different biases (conflict detection / improvement / devil's advocate / code review / robustness). Anything 2+ agree on is auto-confirmed. Anything only one agent saw gets a second verifier pass so false positives don't waste your time.

## Who should use this

- **Before a major architectural decision** — you want 5 angles, not 1
- **Before merging a PR you're unsure about** — independent review beyond your own LLM's opinion
- **After implementing a feature** — last-line sweep for blind spots before release
- **Auditing a skill, design doc, or workflow** — the disagreement between reviewers is itself signal
- **Whenever you'd ask 5 senior engineers to look at the same thing**

## Sibling tools (same marketplace)

- **[ddaro](https://github.com/minwoo-data/ddaro)** — worktree-based parallel Claude Code sessions with safe merge.
- **[triad](https://github.com/minwoo-data/triad)** — deeper 3-perspective deliberation for markdown and design docs.
- **[mangchi](https://github.com/minwoo-data/mangchi)** — iterative file refinement with Claude + Codex cross-review.

---

## Quick Start

### 1. Add the haroom_plugins marketplace (one time)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git
```

`prism` is distributed through the **haroom_plugins** aggregator along with the other haroom plugins (ddaro, triad, mangchi).

### 2. Install

```
/plugin install prism
```

### 3. Use

```
/prism src/services/auth.py                 # default: 5 agents + batched Verifier
/prism src/services/auth.py --quick         # 1 pass only, no Verifier
/prism src/services/auth.py --adversarial   # 1 pass + REJECT re-check
/prism .                                    # whole-project review
```

Restart Claude Code after install/update.

---

## Variants shipped in this plugin

Installing `prism` gives you three independent skills that share the 5-angle framework but differ in who runs each agent:

| Skill | Engine | When to use |
|---|---|---|
| `/prism` | **Claude only** — 5 agents parallel + Verifier | Default. Fastest wall-time, no external CLI. |
| `/prism-codex` | **Codex CLI only** — 5 sequential + Verifier, gpt-5.5 | Save Claude tokens, or get a different-model opinion. Requires `codex-cli >= 0.125.0`. |
| `/prism-all` | **Claude + Codex in parallel** — 10 discovery + Verifier | Highest confidence. Same-angle cross-model agreement gets a dedicated Tier 1. `--verifier=claude\|codex\|both` picks the adjudicator. |

All three ship inside one plugin install. Pick one per run. Codex CLI prerequisite details (including the "model does not exist" error which is actually a CLI version issue): see [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md) in the sibling triad plugin.

---

## The five agents

| Agent | Looks for |
|---|---|
| **Conflict Detection** | Overlaps with existing code/skills, config contradictions, integration risks |
| **Improvement** | Concrete enhancements, efficiency gains, missing features |
| **Devil's Advocate** | Weaknesses, gaming/Goodhart risk, false confidence, regression risk |
| **Code Review** | Clarity, completeness, correctness, pattern consistency |
| **Robustness (4-Axis)** | Concurrency / Failure & Recovery / Data Integrity / State Transitions |

Each runs in a **forked context** so the main conversation stays clean and the agents can't see each other's output — agreement becomes independent signal, not echo.

## How verification works

After Pass 1, every finding is classified:

- **AGREEMENT** (2+ agents flagged) → auto-CONFIRMED, skips Pass 2
- **SINGLETON** (1 agent only) → goes into Pass 2

Pass 2 runs **one batched Verifier agent** that gets the full target + all 5 Pass 1 outputs + the singleton list. It returns `CONFIRMED | REJECTED | DEPENDS` for each. Twenty singletons cost the same as two — the verifier batches them.

Cheap consensus passes through fast. Only borderline findings pay the verification cost.

## Features

- **Parallel discovery** — 5 agents fire in a single tool call, so total wall-time ≈ the slowest one, not the sum.
- **Auto-promotion on agreement** — 2+ agents converging is treated as the highest-confidence tier and skips Verifier entirely.
- **Batched Verifier** — one call covers all singletons; the cost of verification does not scale with finding count.
- **Adversarial mode** — in `--adversarial`, the Verifier argues against its own REJECT before accepting it. Defense against dismissing a real issue.
- **Fork isolation** — the 5 agents run in separate contexts. No conversation bleed, no echo chamber.
- **Code never modified** — prism is a pure reviewer. Use a different tool (e.g. `/mangchi`) to actually change code.

---

## Modes and output

```
/prism src/services/auth.py                 # default: 2-pass verify
/prism src/services/auth.py --quick         # 1 pass only, no verify
/prism src/services/auth.py --adversarial   # 1 pass + REJECT re-check
/prism .                                    # whole-project review
```

Natural language: *"full review"*, *"design review"*, *"prism 돌려"*.

Report shape:

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
| default (verify) | 1.2–1.4× | Standard reviews |
| `--adversarial` | 1.2–1.4× | When you suspect self-bias |

Verifier cost is constant in the number of singletons (one batched call).

---

## Example session

```
/prism src/services/auth.py
# → 5 agents in parallel (~20-40s depending on file size)
# → Pass 1 result: 8 findings. 3 AGREEMENT (2+), 5 SINGLETON.
# → Main: "Running verifier on 5 singletons..."
# → Verifier (batched): 3 CONFIRMED, 1 REJECTED, 1 DEPENDS
# → Final report: 6 actionable + 1 depends + 1 rejected (shown for transparency)

# Stricter pass on a security review:
/prism src/security/ --adversarial
# → Same Pass 1. Verifier argues against its own REJECTs before finalizing.
# → Catches "I was about to dismiss this but actually..." cases.

# Whole-project sanity check:
/prism .
# → Target resolver picks up top-level project structure/skills/docs
```

### Pair with mangchi for iterative hardening

```
/prism src/services/auth.py           # identifies weak file
/mangchi src/services/auth.py         # iteratively harden that specific file
```

### Cross-model variant

```
/prism-all src/services/auth.py
# → Claude 5 agents + Codex CLI 5 calls, all in parallel (~100-200s)
# → Tier 1: same angle flagged by both engines → highest confidence
# → Tier 2: one engine, multiple angles
# → Tier 3: singletons (goes to Verifier)
# → Requires codex-cli >= 0.125.0
```

---

## Update

```
/plugin update
```

Then restart Claude Code.

---

## Troubleshooting

### `/prism` doesn't appear after install

Plugins are loaded at Claude Code startup.

1. **Restart Claude Code** — required after every install and update.
2. Run `/plugin` and confirm `prism` is listed as **enabled**.
3. If listed but disabled: `/plugin enable prism@haroom_plugins`.
4. Still missing? Check `~/.claude.json` has a `prism` entry under `enabledPlugins`. If `{}`, the install didn't complete — rerun `/plugin install prism`.

### `/prism-codex` or `/prism-all` errors with "model does not exist"

That's a Codex CLI version issue, not an account issue. Upgrade:

```
npm install -g @openai/codex@latest
codex --version   # must be >= 0.125.0
```

Full writeup: sibling `triad/docs/codex-5.4-to-5.5.md` in this marketplace.

### Too many findings / report is noisy

- Use `--quick` to skip verification (faster, more false positives).
- Or use `/prism-devil` if you specifically want an attacker-mindset red-team pass instead of multi-angle breadth.

---

## Requirements

- Claude Code (any version with `/plugin` command) — spawns general-purpose subagents
- *(Optional — only for `/prism-codex` and `/prism-all`)* [Codex CLI](https://github.com/openai/codex) `>= 0.125.0`
- Works on Windows (Git Bash / WSL2), macOS, Linux

The base `/prism` runs entirely within Claude Code. No external CLI required.

---

## When NOT to use prism

- **Tiny one-line changes** — overkill
- **Pure markdown/spec review** — use `/triad` (3 perspectives is enough)
- **Iterative file hardening** — use `/mangchi` (better tool for that loop)
- **Security-only deep probe** — `/prism-devil` is the attacker-mindset specialist

## Philosophy

Five independent reviewers who can't see each other. Whatever they agree on is almost certainly real. Whatever only one of them saw gets one more pass before you spend a minute on it. The verifier runs in a single batched call so verification is cheap per finding — which is the whole point of separating discovery from verification.

## Updates

- **2026-04-24** — New sibling skills `/prism-codex` (Codex-only) and `/prism-all` (dual-engine) shipped. Codex CLI migration writeup in the sibling triad plugin: [triad/docs/codex-5.4-to-5.5.md](../triad/docs/codex-5.4-to-5.5.md). Read it if you hit a "model does not exist" error when first using a Codex-backed variant.

## License

MIT — see [`LICENSE`](LICENSE).

## Author

haroom — [github.com/minwoo-data](https://github.com/minwoo-data)

## Contributing

Issues and PRs welcome at [github.com/minwoo-data/prism](https://github.com/minwoo-data/prism).
