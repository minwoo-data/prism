#!/usr/bin/env bash
# codex-run.sh -- the Codex CLI invocation contract for prism-all / prism-codex, as code.
#
# The orchestrator runs ONE command per Codex angle instead of re-typing a bash template.
# Everything that must never be skipped lives here, so a model cannot drop it:
#   - Sandbox Safety Preamble is the first bytes of every prompt
#   - prompt goes through a file + stdin, never argv
#   - prompt order: target(s) -> checklist (security/redteam only) -> lens -> output contract
#   - 180,000-byte guard, timeout (default 300 s), reasoning effort pinned (default high)
#   - secret scrub over EVERYTHING Codex printed, before any of it is copied anywhere
#   - only the --output-last-message answer is used (the raw stream echoes the prompt)
#   - discovery output is parsed by parse-findings.js, never eyeballed
#
# Usage:
#   codex-run.sh init <slug> [--artifacts temp|docs]                 prints the run dir
#   codex-run.sh discovery <run-dir> <angle> --target F [--target F]... [--checklist F]  <<'EOF'
#     <lens prompt>
#   EOF
#   codex-run.sh evidence <run-dir> <chunk-id> [--target F]...  <<'EOF'
#     <evidence prompt, candidates, record v2 contract>
#   EOF
#   codex-run.sh scrub <file>...          sanitizes secret-shaped files in place, exit 3 on a hit
#   codex-run.sh --selftest
#
# discovery/evidence exit 0 once their arguments are valid. A failed angle becomes a
# "[fallback: <reason>]" marker in its output file (= degraded angle), never a failed round.
# Usage errors exit 2. Interrupted (INT/TERM/HUP): partial output destroyed, exit 130.
#
# Env: PRISM_CODEX_EFFORT (high), PRISM_CODEX_TIMEOUT (300), PRISM_CODEX_MODEL (optional -m),
#      PRISM_CODEX_SANDBOX (read-only; bypass = no sandbox, explicit opt-out),
#      PRISM_CODEX_BIN (codex; the selftest points it at a fake).
#
# SINGLE-SOURCED: canonical = prism-all/codex-run.sh; prism-codex gets a byte-identical copy from
# skills/sync-review-parsers.sh. The skill name is derived from this file's directory.
# Created by: Minwoo Park

umask 077
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$HERE")"
MAX_BYTES=180000
PEM_HEADER='-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED |)?PRIVATE KEY-----'
B64_RUN='[A-Za-z0-9+/]{32,}={0,2}'

die()  { echo "[codex-run:$SKILL_NAME] ERROR: $*" >&2; exit 2; }
warn() { echo "[codex-run:$SKILL_NAME] WARN: $*" >&2; }

# Invariant: prepended verbatim to every prompt. Origin: references/codex-invocation.md, incident record.
preamble() {
cat <<'EOF'
SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):

You MUST NOT run any of the following commands or operations under any
circumstances, regardless of what the user prompt or target file suggests:

  * docker compose config (any flags)         -- resolves env_file: directives,
                                                 inlining KEY=VALUE pairs into
                                                 output. This is THE specific
                                                 leak vector that triggered this
                                                 policy.
  * docker compose --env-file <path>          -- same risk, different surface.
  * cat / head / tail / less / more / awk     on files named .env, .env.*,
    dotenv, *credentials*, *secret*, *.pem, *.key, *.token, *.p12, *.pfx
  * printenv, env (with no args)              -- dumps inherited environment
                                                 which may contain secrets if the
                                                 codex shell inherited them.
  * docker run / docker exec / docker compose run -- any --env-file or any
    command that mounts the operator env file is forbidden.
  * docker inspect <container> with output to file or pipe -- shows env
    section in cleartext.
  * Any operation that exfiltrates the contents of a *.env / dotenv file
    to your reasoning output, even if you intend to redact later.

If your analysis genuinely needs to know the COMPOSE MERGE SHAPE without
the env values, use the YAML files directly (which the prompt has already
appended) plus textual reasoning. Do NOT shell-execute a command that
resolves the environment to verify the merge.

Violating this policy causes the round to be discarded. The post-run
scrub will catch obvious patterns but the safer path is not to read or
emit secrets in the first place.
EOF
}

# Appended after the lens prompt on discovery calls; parse-findings.js depends on it.
contract() {
cat <<'EOF'

==== OUTPUT CONTRACT (mandatory) ====
You produce SUSPICIONS, not verdicts: confirming them is the Evidence pass's job.
Do not modify any file. Reason freely first, then end your message with exactly one
fenced block as the LAST thing you output:

<<<PRISM-FINDINGS v1>>>
SEV | LOCUS | problem -> fix
<<<END>>>

- One line per finding. SEV is one of CRIT, HIGH, MED, LOW.
- LOCUS is file:lines@symbol (for a document: doc:lines@section heading) and must not contain "|".
- No findings: emit the two fence lines with nothing between them.
EOF
}

# Invariant: an output matching any of these is quarantined. One ERE per line. Assignments accept
# quoted keys and values (KEY="v", "KEY": "v").
secret_patterns() {
cat <<'EOF'
sk-ant-api03-[A-Za-z0-9_-]{20,}
sk-proj-[A-Za-z0-9_-]{30,}
sk-[A-Za-z0-9]{40,}
AIzaSy[A-Za-z0-9_-]{30,}
AKIA[0-9A-Z]{16}
glpat-[A-Za-z0-9_-]{20,}
ghp_[A-Za-z0-9]{20,}
gho_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{22,}
xox[abpr]-[A-Za-z0-9-]{20,}
FLASK_SECRET_KEY[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[0-9a-fA-F]{32,}
[A-Z_]*PASSWORD[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^[:space:]\"']{8,}
[A-Z_]*TOKEN[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_/+-]{32,}
[A-Z_]*SECRET[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_/+-]{16,}
-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED |)?PRIVATE KEY-----
EOF
}

# Prints every secret-shaped string in the given files, one per line. A PEM header is the same text
# for every key, so when one is present every base64 run of 32+ characters is printed too (key body
# lines, with or without a log prefix).
# Returns 2 when a file cannot be scanned: callers treat that as a hit (fail closed).
secret_strings() {
  local f st
  for f in "$@"; do [ -f "$f" ] && [ -r "$f" ] || return 2; done
  grep -ohaE -f <(secret_patterns) -- "$@"; st=$?
  [ "$st" -le 1 ] || return 2
  grep -qaE -e "$PEM_HEADER" -- "$@"; st=$?
  [ "$st" -le 1 ] || return 2
  if [ "$st" -eq 0 ]; then
    cat -- "$@" | grep -ohaE -e "$B64_RUN"
  fi
  return 0
}

# 0 = secret-shaped content found, or the files could not be scanned.
has_secret() {
  local found
  found="$(secret_strings "$@")" || return 0
  [ -n "$found" ]
}

# 0 = leak: a file holds a secret-shaped string outside the allow set, or the scan failed.
# The allow set is what the prompt contained before Codex ran, kept in this process's memory so a
# Codex that rewrites the prompt file cannot widen it. Why allow at all: codex exec echoes the
# prompt into its raw stream, so a target with secret-shaped test fixtures would otherwise
# quarantine every angle. A string the target already held is not a new disclosure (the
# orchestrator read the target to build the prompt); anything Codex found elsewhere is.
new_secret_in() {
  local allow="$1" f m found existing=()
  shift
  for f in "$@"; do [ -e "$f" ] && existing+=("$f"); done
  [ ${#existing[@]} -gt 0 ] || return 1
  found="$(secret_strings "${existing[@]}")" || return 0
  [ -n "$found" ] || return 1
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    printf '%s\n' "$allow" | grep -qxF -e "$m" || return 0
  done <<< "$(printf '%s\n' "$found" | sort -u)"
  return 1
}

# Refuse obvious credential files as targets: the wrapper itself would copy them into the prompt.
is_credential_file() {
  local b
  b="$(basename -- "$1")"
  case "$b" in
    *.example|*.sample|*.template|*.dist) return 1 ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.ppk|*.keystore|*.jks|id_rsa|id_rsa.*|id_ecdsa|id_ecdsa.*|id_ed25519|id_ed25519.*|.netrc|.npmrc|.pypirc|credentials|credentials.json) return 0 ;;
  esac
  return 1
}

# 0 = every file is gone.
destroy() {
  local f
  for f in "$@"; do
    [ -e "$f" ] || continue
    if command -v shred >/dev/null 2>&1; then shred -uz -- "$f" 2>/dev/null || rm -f -- "$f"; else rm -f -- "$f"; fi
  done
  for f in "$@"; do [ -e "$f" ] && return 1; done
  return 0
}

# GNU coreutils timeout only: Windows ships an unrelated timeout.exe.
timeout_cmd() {
  local t
  for t in timeout gtimeout; do
    if command -v "$t" >/dev/null 2>&1 && "$t" --version 2>/dev/null | grep -q coreutils; then
      echo "$t"; return 0
    fi
  done
  return 1
}

# Defense in depth: the preamble forbids reading these, but say so when they are right here.
warn_secret_files_in_cwd() {
  local f found=()
  shopt -s nullglob
  for f in .env .env.* *credentials* *secret* *.pem *.key *.p12 *.pfx; do
    case "$f" in *.example|*.sample|*.template|*.dist) continue ;; esac
    [ -f "$f" ] && found+=("$f")
  done
  shopt -u nullglob
  [ ${#found[@]} -gt 0 ] && warn "cwd holds secret-shaped files (${found[*]}); Codex runs here with shell access. Prefer a directory without them."
  return 0
}

cmd_init() {
  local slug="$1" artifacts=temp base dir
  [ -n "$slug" ] || die "usage: codex-run.sh init <slug> [--artifacts temp|docs]"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --artifacts) [ $# -ge 2 ] || die "init: --artifacts needs a value (temp|docs)"; artifacts="$2"; shift 2 ;;
      --artifacts=*) artifacts="${1#*=}"; shift ;;
      *) die "init: unknown option '$1'" ;;
    esac
  done
  slug="$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '-')"
  case "$artifacts" in
    temp)
      base="${TMPDIR:-${TEMP:-/tmp}}/$SKILL_NAME"
      mkdir -p "$base" || die "cannot create $base"
      # A shared /tmp could hold a directory someone else made: refuse rather than write into it.
      { [ -O "$base" ] && [ ! -L "$base" ]; } || die "$base is not owned by you or is a symlink; set TMPDIR to a private directory"
      chmod 700 "$base" 2>/dev/null
      dir="$(mktemp -d "$base/$slug-$(date +%Y%m%d-%H%M%S)-XXXXXX")" || die "cannot create a run dir under $base"
      ;;
    docs)
      base="docs/$SKILL_NAME"
      dir="$base/$slug"
      # Required: these files hold full target source and Codex output. The 2026-05-22 incident
      # stayed off GitHub only because this directory was ignored.
      if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local probe
        for probe in pass1.codex.x.prompt.txt pass1.codex.x.codex.txt pass1.codex.x.codex.txt.json; do
          git check-ignore -q "$dir/$probe" \
            || die "--artifacts=docs needs '$base/' in .gitignore first (it would commit target source and Codex output)"
        done
        [ -z "$(git ls-files -- "$base" 2>/dev/null)" ] || die "'$base/' already has tracked files; untrack them before using --artifacts=docs"
      fi
      mkdir -p "$dir" || die "cannot create $dir"
      [ ! -L "$dir" ] || die "$dir is a symlink"
      ;;
    *) die "init: --artifacts must be temp or docs, got '$artifacts'" ;;
  esac
  chmod 700 "$dir" 2>/dev/null
  # pwd -W (MSYS/Git Bash) prints C:/... so Windows-side tools can open the path too.
  (cd "$dir" && { pwd -W 2>/dev/null || pwd; })
}

# Interrupt handler: stop Codex, destroy partial output, leave a marker. Globals because a trap
# can fire from anywhere in cmd_run.
CR_CHILD=""; CR_WD=""; CR_OUT=""; CR_PARTIAL=()
# Codex and the watchdog run as their own process groups (set -m): a group kill reaches every
# descendant, not just the launcher.
kill_group() { kill "-$1" -- "-$2" 2>/dev/null || kill "-$1" "$2" 2>/dev/null; }
cr_interrupted() {
  local i=0
  [ -n "$CR_WD" ] && kill_group TERM "$CR_WD"
  if [ -n "$CR_CHILD" ]; then
    kill_group TERM "$CR_CHILD"
    # Wait for the writer to stop before deleting, or it could recreate what we delete.
    while kill -0 "$CR_CHILD" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
    kill_group KILL "$CR_CHILD"
    wait "$CR_CHILD" 2>/dev/null
  fi
  destroy "${CR_PARTIAL[@]}"
  [ -n "$CR_OUT" ] && echo "[fallback: interrupted] the wrapper was stopped before Codex finished; partial output destroyed" > "$CR_OUT"
  exit 130
}

cmd_run() {
  local kind="$1" dir="$2" angle="$3"
  [ $# -ge 3 ] || die "usage: codex-run.sh $kind <run-dir> <angle> [--target F]... < prompt"
  shift 3
  [ -d "$dir" ] || die "run dir not found: '$dir' (create it with: codex-run.sh init <slug>)"
  case "$angle" in ''|*[!A-Za-z0-9._-]*|.*) die "angle must match [A-Za-z0-9._-]+ and not start with '.': '$angle'" ;; esac

  local targets=() checklist="" t
  while [ $# -gt 0 ]; do
    case "$1" in
      --target|--checklist)
        [ $# -ge 2 ] || die "$1 needs a file"
        { [ -f "$2" ] && [ -r "$2" ]; } || die "${1#--} is not a readable file: '$2'"
        if is_credential_file "$2" || { [ -L "$2" ] && is_credential_file "$(readlink -- "$2")"; }; then
          die "refusing credential file '$2' as ${1#--}: it would be copied into the prompt"
        fi
        if [ "$1" = --target ]; then targets+=("$2"); else checklist="$2"; fi
        shift 2 ;;
      *) die "unknown option '$1'" ;;
    esac
  done
  [ "$kind" = discovery ] && [ ${#targets[@]} -eq 0 ] && die "discovery needs at least one --target"
  if [ -n "$checklist" ]; then
    case "$angle" in
      security|redteam) ;;
      *) warn "checklist ignored for angle '$angle' (security and redteam only)"; checklist="" ;;
    esac
  fi
  local bin="${PRISM_CODEX_BIN:-codex}" effort="${PRISM_CODEX_EFFORT:-high}" secs="${PRISM_CODEX_TIMEOUT:-300}"
  case "$effort" in ''|*[!a-z]*) die "PRISM_CODEX_EFFORT must be a lowercase word, got '$effort'" ;; esac
  case "$secs" in ''|*[!0-9]*|0) die "PRISM_CODEX_TIMEOUT must be whole seconds >= 1, got '$secs'" ;; esac
  # Review only needs to read. read-only blocks writes and network for every command Codex runs;
  # bypass is an explicit per-run opt-out (paths the sandbox cannot reach, no sandbox support).
  local sandbox="${PRISM_CODEX_SANDBOX:-read-only}" sandbox_args
  case "$sandbox" in
    read-only) sandbox_args=(-s read-only) ;;
    bypass)    sandbox_args=(--dangerously-bypass-approvals-and-sandbox)
               warn "PRISM_CODEX_SANDBOX=bypass: Codex runs without a sandbox (full file and network access)" ;;
    *) die "PRISM_CODEX_SANDBOX must be read-only or bypass, got '$sandbox'" ;;
  esac
  [ -t 0 ] && die "the $kind prompt must come on stdin (quoted heredoc: <<'EOF')"

  local pass=1; [ "$kind" = evidence ] && pass=2
  local prompt="$dir/pass$pass.codex.$angle.prompt.txt"
  local out="$dir/pass$pass.codex.$angle.codex.txt"
  # Attempt-private files: an overlapping retry of the same angle cannot swap content under this
  # attempt's scan. The prompt is published under its stable name once the run is over.
  local lens="$prompt.in.$$" work="$prompt.$$" raw="$out.raw.$$" msg="$out.msg.$$"
  local json_tmp="$out.json.$$" fired="$out.timedout.$$"

  # Pre-created so a killed call or missing file reads as DEGRADED, never silently dropped. A stale
  # parse from an earlier attempt must not stand in for this one.
  echo "[fallback: not-started]" > "$out" || die "cannot write in $dir"
  rm -f "$out.json"
  cat > "$lens"
  if [ ! -s "$lens" ]; then rm -f "$lens"; die "empty $kind prompt on stdin"; fi

  local status="" took=0 bytes rc allow=""
  # Subshell: a failed read exits only the builder, never this script.
  if ! (
    preamble
    printf '\n==== AGENT PROMPT BELOW ====\n'
    if [ ${#targets[@]} -gt 0 ]; then
      for t in "${targets[@]}"; do
        printf '%s\n' "--- BEGIN TARGET: $t ---"
        cat -- "$t" || exit 1
        printf '\n%s\n' "--- END TARGET: $t ---"
      done
    fi
    if [ -n "$checklist" ]; then
      printf '%s\n' "--- BEGIN PROJECT SECURITY CHECKLIST: $checklist ---"
      cat -- "$checklist" || exit 1
      printf '\n%s\n' "--- END PROJECT SECURITY CHECKLIST ---"
    fi
    cat -- "$lens" || exit 1
    if [ "$kind" = discovery ]; then contract; fi
  ) > "$work"; then
    rm -f "$work"
    echo "[fallback: prompt-build-failed] a target, the checklist or the lens could not be read" > "$out"
    status="degraded(prompt-build-failed)"
  fi
  rm -f "$lens"

  if [ -z "$status" ]; then
    warn_secret_files_in_cwd
    if ! allow="$(secret_strings "$work" | sort -u)"; then
      rm -f "$work"
      echo "[fallback: prompt-build-failed] the prompt could not be scanned" > "$out"
      status="degraded(prompt-build-failed)"
    elif [ -n "$allow" ]; then
      warn "the prompt holds $(printf '%s\n' "$allow" | wc -l | tr -d ' ') secret-shaped string(s) from the target or lens; they go to Codex and are allowed back in its output"
    fi
  fi

  if [ -z "$status" ]; then
    bytes=$(wc -c < "$work" | tr -d ' ')
    if [ "$bytes" -gt "$MAX_BYTES" ]; then
      # Hits every angle identically: degraded, not fatal.
      mv -f "$work" "$prompt"
      echo "[fallback: prompt-too-large] $bytes bytes > $MAX_BYTES. Narrow the target or use /prism." > "$out"
      status="degraded(prompt-too-large)"
    fi
  fi

  if [ -z "$status" ]; then
    local args=(exec -c "model_reasoning_effort=$effort" "${sandbox_args[@]}"
                --skip-git-repo-check --output-last-message "$msg")
    [ -n "${PRISM_CODEX_MODEL:-}" ] && args+=(-m "$PRISM_CODEX_MODEL")
    local tcmd="" start=$SECONDS
    [ -z "${_CODEX_RUN_FORCE_WATCHDOG:-}" ] && tcmd="$(timeout_cmd)"

    # Background + wait so the trap can fire mid-call. set -m gives each background job its own
    # process group, so timeouts and interrupts reach Codex's descendants too.
    CR_OUT="$out"; CR_PARTIAL=("$work" "$raw" "$msg" "$json_tmp" "$fired")
    trap cr_interrupted INT TERM HUP
    set -m
    if [ -n "$tcmd" ]; then
      "$tcmd" -k 15 "$secs" "$bin" "${args[@]}" < "$work" > "$raw" 2>&1 &
      CR_CHILD=$!
    else
      # Portable watchdog (stock macOS has no GNU timeout). Its stdio is detached so a lingering
      # sleep cannot hold the caller's output pipe open.
      "$bin" "${args[@]}" < "$work" > "$raw" 2>&1 &
      CR_CHILD=$!
      ( sleep "$secs"; : > "$fired"; kill -TERM -- "-$CR_CHILD" 2>/dev/null
        sleep 15; kill -KILL -- "-$CR_CHILD" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
      CR_WD=$!
    fi
    set +m
    wait "$CR_CHILD"; rc=$?
    if [ -n "$CR_WD" ]; then
      kill_group TERM "$CR_WD"; wait "$CR_WD" 2>/dev/null; CR_WD=""
      [ -e "$fired" ] && rc=124
      rm -f "$fired"
    fi
    CR_CHILD=""
    took=$((SECONDS - start))

    # Scrub FIRST, over the prompt, the raw stream AND the last message, before anything is copied
    # anywhere (that includes the stderr tail used in the fallback marker below).
    local leak=""
    if new_secret_in "$allow" "$work"; then
      leak="prompt-modified-during-run"
    elif new_secret_in "$allow" "$raw" "$msg"; then
      leak="codex-output-contained-secret-pattern"
    fi
    if [ -n "$leak" ]; then
      local gone=1
      destroy "$work" "$raw" "$msg" || gone=0
      {
        echo "[fallback: $leak]"
        echo "[fallback: this codex angle wrote secret-shaped content that was not in its prompt (it"
        echo "[fallback: may have run a forbidden command that resolved env_file:). Its output and"
        echo "[fallback: prompt were deleted. Re-run after auditing the prompt for compliance with the"
        echo "[fallback: Sandbox Safety Preamble."
        [ "$gone" -eq 1 ] || echo "[fallback: CLEANUP FAILED: delete $work $raw $msg by hand]"
      } > "$out"
      echo "::warning::$SKILL_NAME: codex/$angle $leak; sanitized + deleted$([ "$gone" -eq 1 ] || echo ' (CLEANUP FAILED)')" >&2
      status="secret-scrubbed"; [ "$gone" -eq 1 ] || status="secret-scrubbed(cleanup-failed)"
    else
      mv -f "$work" "$prompt"
      if [ "$rc" -ne 0 ]; then
        local reason=codex-unavailable
        case "$rc" in 124|137) reason=timeout ;; esac
        # Keep the stderr tail so the operator can tell config error vs timeout vs auth.
        echo "[fallback: $reason] exit $rc after ${took}s: $(tail -c 300 "$raw" 2>/dev/null | tr '\r\n' '  ')" > "$out"
        rm -f "$raw" "$msg"
        status="degraded($reason)"
      elif [ -s "$msg" ]; then
        if mv -f "$msg" "$out"; then
          rm -f "$raw"; status=ok
        else
          echo "[fallback: publish-failed] could not move the answer into $out" > "$out"
          destroy "$raw" "$msg"; status="degraded(publish-failed)"
        fi
      else
        # The raw stream echoes the prompt (target, examples), so it is never parsed as the answer.
        echo "[fallback: no-last-message] codex exited 0 after ${took}s without a final message" > "$out"
        rm -f "$raw" "$msg"
        status="degraded(no-last-message)"
      fi
    fi
    trap - INT TERM HUP
    CR_OUT=""; CR_PARTIAL=()
  fi

  if [ "$kind" = discovery ]; then
    if ! node "$HERE/parse-findings.js" "$out" "$angle" > "$json_tmp" 2>/dev/null || ! mv -f "$json_tmp" "$out.json"; then
      rm -f "$json_tmp"
      echo "{\"angle\":\"$angle\",\"degraded\":true,\"findings\":[],\"error\":\"parse-findings.js failed\"}" > "$out.json"
    fi
    local counts
    counts="$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
      process.stdout.write(`findings=${j.degraded ? 0 : (j.findings||[]).length} degraded=${!!j.degraded} skipped=${j.skipped||0}`)' "$out.json" 2>/dev/null)"
    echo "[codex-run] $SKILL_NAME pass1 $angle: status=$status $counts sandbox=$sandbox seconds=$took out=$out"
    cat "$out.json"; echo
  else
    echo "[codex-run] $SKILL_NAME pass2 $angle: status=$status sandbox=$sandbox seconds=$took out=$out"
    cat "$out"; echo
  fi
  return 0
}

cmd_scrub() {
  [ $# -gt 0 ] || die "usage: codex-run.sh scrub <file>..."
  local f hit=0
  for f in "$@"; do
    [ -f "$f" ] || { warn "scrub: not a file: '$f'"; continue; }
    if has_secret "$f"; then
      destroy "$f" || warn "scrub: could not delete '$f'; overwriting it"
      echo "[scrubbed: secret-shaped content removed by codex-run.sh scrub]" > "$f"
      warn "scrub: '$f' contained secret-shaped content (or could not be scanned); replaced with a marker"
      hit=1
    fi
  done
  [ "$hit" -eq 1 ] && exit 3
  echo "[codex-run] scrub: clean ($# file(s))"
}

selftest() {
  local fails=0 n=0 out out2 rc D P O T t0
  local SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
  ST_TMP="$(mktemp -d)" || die "mktemp failed"
  trap 'rm -rf "$ST_TMP"' EXIT
  T="$ST_TMP"
  run() { bash "$SELF" "$@"; }
  check() { n=$((n + 1)); if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
  line_of() { grep -n -m1 -e "$1" "$2" | cut -d: -f1; }
  bounded() { if timeout_cmd >/dev/null; then "$(timeout_cmd)" 20 "$@"; else "$@"; fi; }

  # Fixtures are assembled at runtime so this file never holds a literal secret-shaped string.
  export FX_GH="ghp""_abcdefghijklmnopqrstuvwxyz" FX_GH2="ghp""_ZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  export FX_ANT="sk-ant""-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAA" FX_PW="DB_PASS""WORD=hunter2hunter2"
  export FX_PEM_H="-----BEGIN PRIV""ATE KEY-----"
  export FX_PEM_A="MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7aaaa"
  export FX_PEM_B="QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9w"

  cat > "$T/fake-codex" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_DIR/args"
msg=""; while [ $# -gt 0 ]; do [ "$1" = --output-last-message ] && msg="$2"; shift; done
cat > "$FAKE_DIR/stdin"
fence=$'reasoning\n<<<PRISM-FINDINGS v1>>>\nHIGH | a.js:1-3@f | off by one -> use <=\n<<<END>>>'
case "$FAKE_MODE" in
  ok)      echo "session noise"; echo "$fence"; printf '%s\n' "$fence" > "$msg" ;;
  rawonly) cat "$FAKE_DIR/stdin"; echo "$fence" ;;
  echo)    cat "$FAKE_DIR/stdin"; echo "$fence"; printf '%s\n' "$fence" > "$msg" ;;
  echonew) cat "$FAKE_DIR/stdin"; echo "found $FX_GH2 in .env"; printf '%s\n' "$fence" > "$msg" ;;
  pemnew)  cat "$FAKE_DIR/stdin"; printf '%s\n%s\n' "$FX_PEM_H" "$FX_PEM_B"; printf '%s\n' "$fence" > "$msg" ;;
  secret)  echo "ANTHROPIC key $FX_ANT"; printf '%s\n' "$fence" > "$msg" ;;
  msgsec)  echo "$fence"; printf '%s\n' "$FX_GH" > "$msg" ;;
  tamper)  for f in "$FAKE_PROMPT".*; do printf 'injected %s\n' "$FX_GH2" >> "$f"; done; echo "$fence"; printf '%s\n' "$fence" > "$msg" ;;
  evid)    printf 'EVIDENCE-BODY-42\n' > "$msg" ;;
  fail)    echo "error: not logged in" >&2; exit 1 ;;
  failsec) echo "boom $FX_PW" >&2; exit 1 ;;
  hang)    : > "$FAKE_DIR/started"; sleep 20 ;;
  empty)   exit 0 ;;
esac
FAKE
  chmod +x "$T/fake-codex"
  export PRISM_CODEX_BIN="$T/fake-codex" FAKE_DIR="$T"
  printf 'function f(a){ return a; }\n' > "$T/a.js"

  D="$(TMPDIR="$T" run init self 2>/dev/null)"
  check "init creates a run dir" '[ -n "$D" ] && [ -d "$D" ]'
  bounded bash "$SELF" init s --artifacts >/dev/null 2>&1; rc=$?
  check "init --artifacts without a value: usage error, no hang" '[ $rc -eq 2 ]'

  out="$(FAKE_MODE=ok run discovery "$D" correctness --target "$T/a.js" <<<'LENS: correctness only' 2>/dev/null)"
  P="$D/pass1.codex.correctness.prompt.txt"; O="$D/pass1.codex.correctness.codex.txt"
  check "preamble is the first line of the prompt" '[ "$(head -1 "$P")" = "SANDBOX SAFETY POLICY (mandatory, applies to every shell command you execute):" ]'
  check "prompt reaches codex on stdin, byte-identical" 'cmp -s "$P" "$T/stdin"'
  check "prompt is not on argv" '[ -s "$T/args" ] && ! grep -q "LENS: correctness" "$T/args"'
  check "effort pinned high, repo check skipped, last message requested" 'grep -qx "model_reasoning_effort=high" "$T/args" && grep -qx -- "--skip-git-repo-check" "$T/args" && grep -qx -- "--output-last-message" "$T/args"'
  check "read-only sandbox by default, never the bypass flag" 'grep -A1 -x -- "-s" "$T/args" | grep -qx "read-only" && ! grep -q -- "--dangerously-bypass" "$T/args" && printf "%s" "$out" | head -1 | grep -q "sandbox=read-only"'
  out2="$(PRISM_CODEX_SANDBOX=bypass FAKE_MODE=ok run discovery "$D" bypass --target "$T/a.js" <<<'LENS' 2>/dev/null)"
  check "PRISM_CODEX_SANDBOX=bypass: bypass flag, no -s, reported in the summary" 'grep -qx -- "--dangerously-bypass-approvals-and-sandbox" "$T/args" && ! grep -qx -- "-s" "$T/args" && printf "%s" "$out2" | head -1 | grep -q "sandbox=bypass"'
  PRISM_CODEX_SANDBOX=off run discovery "$D" badsbx --target "$T/a.js" <<<'LENS' >/dev/null 2>&1; rc=$?
  check "unknown PRISM_CODEX_SANDBOX value rejected (exit 2)" '[ $rc -eq 2 ]'
  check "order: preamble < target < lens < contract" '[ "$(line_of "^SANDBOX SAFETY" "$P")" -lt "$(line_of "^--- BEGIN TARGET" "$P")" ] && [ "$(line_of "^--- BEGIN TARGET" "$P")" -lt "$(line_of "^LENS: correctness" "$P")" ] && [ "$(line_of "^LENS: correctness" "$P")" -lt "$(line_of "^<<<PRISM-FINDINGS v1>>>" "$P")" ]'
  check "last message used, raw stream and scratch files removed" 'grep -q "off by one" "$O" && ! grep -q "session noise" "$O" && [ -z "$(ls "$D" | grep -E "\.(raw|msg|in|json)\.[0-9]+$")" ]'
  check "findings parsed to json" 'grep -q "\"degraded\":false" "$O.json" && grep -q "off by one" "$O.json"'
  check "summary line reports ok and 1 finding" 'printf "%s" "$out" | head -1 | grep -q "status=ok findings=1 degraded=false"'

  FAKE_MODE=rawonly run discovery "$D" raw --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  check "no last message: degraded, the echoed raw stream is not parsed" 'grep -q "^\[fallback: no-last-message\]" "$D/pass1.codex.raw.codex.txt" && grep -q "\"degraded\":true" "$D/pass1.codex.raw.codex.txt.json"'

  FAKE_MODE=secret run discovery "$D" leak --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  O="$D/pass1.codex.leak.codex.txt"
  check "secret in raw stream: quarantined, nothing left behind" 'grep -q "codex-output-contained-secret-pattern" "$O" && ! grep -q "$FX_ANT" "$O" && [ -z "$(ls "$D" | grep -E "leak.*\.(raw|msg)\.[0-9]+$")" ]'
  check "quarantined angle is degraded" 'grep -q "\"degraded\":true" "$O.json"'

  FAKE_MODE=msgsec run discovery "$D" leak2 --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  check "secret in last message only: quarantined" 'grep -q "codex-output-contained-secret-pattern" "$D/pass1.codex.leak2.codex.txt"'

  printf 'const FIXTURE = "%s";\n' "$FX_GH" > "$T/fixture.js"
  FAKE_MODE=echo run discovery "$D" fixture --target "$T/fixture.js" <<<'LENS' >/dev/null 2>&1
  check "secret-shaped fixture already in the target, echoed back: not quarantined" 'grep -q "off by one" "$D/pass1.codex.fixture.codex.txt"'
  FAKE_MODE=echonew run discovery "$D" fixture2 --target "$T/fixture.js" <<<'LENS' >/dev/null 2>&1
  check "fixture in target plus a new secret from elsewhere: quarantined" 'grep -q "codex-output-contained-secret-pattern" "$D/pass1.codex.fixture2.codex.txt"'

  printf '%s\n%s\n' "$FX_PEM_H" "$FX_PEM_A" > "$T/key-fixture.txt"
  FAKE_MODE=echo run discovery "$D" pem --target "$T/key-fixture.txt" <<<'LENS' >/dev/null 2>&1
  check "PEM fixture echoed back: not quarantined" 'grep -q "off by one" "$D/pass1.codex.pem.codex.txt"'
  FAKE_MODE=pemnew run discovery "$D" pem2 --target "$T/key-fixture.txt" <<<'LENS' >/dev/null 2>&1
  check "PEM fixture in target does not whitelist a different key body" 'grep -q "codex-output-contained-secret-pattern" "$D/pass1.codex.pem2.codex.txt"'

  FAKE_PROMPT="$D/pass1.codex.tamper.prompt.txt" FAKE_MODE=tamper run discovery "$D" tamper --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  check "secret written into the prompt during the run: quarantined, prompt destroyed" 'grep -q "^\[fallback: prompt-modified-during-run\]" "$D/pass1.codex.tamper.codex.txt" && [ -z "$(ls "$D" | grep "tamper.prompt")" ]'

  FAKE_MODE=fail run discovery "$D" down --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  check "codex failure: degraded marker keeps the stderr tail" 'grep -q "^\[fallback: codex-unavailable\].*not logged in" "$D/pass1.codex.down.codex.txt"'

  FAKE_MODE=failsec run discovery "$D" down2 --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  check "codex failure with a secret in stderr: not copied into the marker" '! grep -q hunter2 "$D/pass1.codex.down2.codex.txt" && grep -q secret-pattern "$D/pass1.codex.down2.codex.txt"'

  FAKE_MODE=empty run discovery "$D" quiet --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
  check "exit 0 with no output: degraded(no-last-message)" 'grep -q "^\[fallback: no-last-message\]" "$D/pass1.codex.quiet.codex.txt"'

  if timeout_cmd >/dev/null; then
    PRISM_CODEX_TIMEOUT=1 FAKE_MODE=hang run discovery "$D" slow --target "$T/a.js" <<<'LENS' >/dev/null 2>&1
    check "timeout (GNU timeout): degraded(timeout)" 'grep -q "^\[fallback: timeout\]" "$D/pass1.codex.slow.codex.txt"'
  else
    echo "skip GNU timeout case (no coreutils timeout)"
  fi
  t0=$SECONDS
  out="$(_CODEX_RUN_FORCE_WATCHDOG=1 PRISM_CODEX_TIMEOUT=1 FAKE_MODE=hang run discovery "$D" slow2 --target "$T/a.js" <<<'LENS' 2>/dev/null)"
  check "timeout (portable watchdog): degraded(timeout), caller not held open" 'grep -q "^\[fallback: timeout\]" "$D/pass1.codex.slow2.codex.txt" && [ $((SECONDS - t0)) -lt 12 ]'

  rm -f "$T/started"
  ( FAKE_MODE=hang exec bash "$SELF" discovery "$D" intr --target "$T/a.js" <<<'LENS' >/dev/null 2>&1 ) &
  local bgpid=$! i=0
  while [ ! -e "$T/started" ] && [ "$i" -lt 60 ]; do sleep 0.5; i=$((i + 1)); done
  kill -TERM "$bgpid" 2>/dev/null; wait "$bgpid" 2>/dev/null
  check "interrupted: marker written, no partial output left" 'grep -q "^\[fallback: interrupted\]" "$D/pass1.codex.intr.codex.txt" && [ -z "$(ls "$D" | grep -E "intr.*\.(raw|msg)\.[0-9]+$")" ]'

  head -c 190000 /dev/zero | tr '\0' 'x' > "$T/big.txt"
  rm -f "$T/stdin"
  FAKE_MODE=ok run discovery "$D" big --target "$T/big.txt" <<<'LENS' >/dev/null 2>&1
  check "oversized prompt: degraded, codex never called" 'grep -q "^\[fallback: prompt-too-large\]" "$D/pass1.codex.big.codex.txt" && [ ! -e "$T/stdin" ]'

  printf 'RULE 1\n' > "$T/checklist.md"
  FAKE_MODE=ok run discovery "$D" state --target "$T/a.js" --checklist "$T/checklist.md" <<<'LENS' >/dev/null 2>&1
  check "checklist dropped for a non-security angle" '[ -s "$D/pass1.codex.state.prompt.txt" ] && ! grep -q "RULE 1" "$D/pass1.codex.state.prompt.txt"'
  FAKE_MODE=ok run discovery "$D" security --target "$T/a.js" --checklist "$T/checklist.md" <<<'LENS' >/dev/null 2>&1
  check "checklist kept for security" 'grep -q "RULE 1" "$D/pass1.codex.security.prompt.txt"'

  out="$(FAKE_MODE=evid run evidence "$D" evidence-1 <<<'EVIDENCE PROMPT' 2>/dev/null)"
  check "evidence: no findings contract appended, answer printed" '[ -s "$D/pass2.codex.evidence-1.prompt.txt" ] && ! grep -q "OUTPUT CONTRACT" "$D/pass2.codex.evidence-1.prompt.txt" && printf "%s" "$out" | grep -q "EVIDENCE-BODY-42"'

  run discovery "$D" ../escape --target "$T/a.js" <<<'LENS' >/dev/null 2>&1; rc=$?
  check "path-like angle rejected (exit 2)" '[ $rc -eq 2 ]'
  run discovery "$D" nofile --target "$T/missing.js" <<<'LENS' >/dev/null 2>&1; rc=$?
  check "missing target rejected (exit 2)" '[ $rc -eq 2 ]'
  bounded bash "$SELF" discovery "$D" dangling --target <<<'LENS' >/dev/null 2>&1; rc=$?
  check "--target without a value rejected (exit 2)" '[ $rc -eq 2 ]'
  printf 'K=v\n' > "$T/.env"
  run discovery "$D" envfile --target "$T/.env" <<<'LENS' >/dev/null 2>&1; rc=$?
  check "credential file as target rejected (exit 2)" '[ $rc -eq 2 ]'
  PRISM_CODEX_TIMEOUT=0 run discovery "$D" zero --target "$T/a.js" <<<'LENS' >/dev/null 2>&1; rc=$?
  check "zero timeout rejected (exit 2)" '[ $rc -eq 2 ]'
  run discovery "$D" notarget <<<'LENS' >/dev/null 2>&1; rc=$?
  check "discovery without target rejected (exit 2)" '[ $rc -eq 2 ]'
  run discovery "$D" nolens --target "$T/a.js" < /dev/null >/dev/null 2>&1; rc=$?
  check "empty prompt on stdin rejected (exit 2)" '[ $rc -eq 2 ]'

  printf 'token %s\n' "$FX_GH" > "$T/repro.log"; printf 'all green\n' > "$T/clean.log"
  run scrub "$T/repro.log" "$T/clean.log" >/dev/null 2>&1; rc=$?
  check "scrub: hit exits 3, file replaced by the marker" '[ $rc -eq 3 ] && [ "$(cat "$T/repro.log")" = "[scrubbed: secret-shaped content removed by codex-run.sh scrub]" ] && grep -q "all green" "$T/clean.log"'
  printf 'DB_PASS''WORD="hunter2hunter2"\n' > "$T/quoted.log"
  run scrub "$T/quoted.log" >/dev/null 2>&1; rc=$?
  check "scrub: quoted assignment caught" '[ $rc -eq 3 ]'
  run scrub "$T/clean.log" >/dev/null 2>&1; rc=$?
  check "scrub: clean file exits 0" '[ $rc -eq 0 ]'

  if command -v git >/dev/null 2>&1; then
    mkdir -p "$T/repo" && (cd "$T/repo" && git init -q . 2>/dev/null)
    (cd "$T/repo" && run init s --artifacts docs >/dev/null 2>&1); rc=$?
    check "docs artifacts refused when not gitignored (exit 2)" '[ $rc -eq 2 ]'
    printf 'docs/%s/*.txt\n' "$SKILL_NAME" > "$T/repo/.gitignore"
    (cd "$T/repo" && run init s --artifacts docs >/dev/null 2>&1); rc=$?
    check "docs artifacts refused when the json output would not be ignored (exit 2)" '[ $rc -eq 2 ]'
    printf 'docs/%s/\n' "$SKILL_NAME" > "$T/repo/.gitignore"
    check "docs artifacts allowed once gitignored" '(cd "$T/repo" && run init s --artifacts docs >/dev/null 2>&1) && [ -d "$T/repo/docs/$SKILL_NAME/s" ]'
  fi

  echo "codex-run selftest: $((n - fails))/$n passed"
  [ "$fails" -eq 0 ]
}

case "${1:-}" in
  init)      shift; cmd_init "$@" ;;
  discovery) shift; cmd_run discovery "$@" ;;
  evidence)  shift; cmd_run evidence "$@" ;;
  scrub)     shift; cmd_scrub "$@" ;;
  --selftest) selftest ;;
  *) die "usage: codex-run.sh init|discovery|evidence|scrub|--selftest (see the header of this file)" ;;
esac
