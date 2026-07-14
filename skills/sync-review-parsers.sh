#!/usr/bin/env bash
# Single-source the deterministic scripts. Canonical = prism-all/*.
# prism-codex and prism receive generated copies. Run after editing a canonical.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
for f in parse-findings.js verify-evidence.js; do
  cp "$here/prism-all/$f" "$here/prism-codex/$f"
  cp "$here/prism-all/$f" "$here/prism/$f"
done
echo "synced parse-findings.js + verify-evidence.js from prism-all -> prism-codex, prism"
