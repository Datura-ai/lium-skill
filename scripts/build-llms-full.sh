#!/usr/bin/env bash
# Generate llms-full.txt by inlining SKILL.md + references/*.md into one self-contained file.
# Single source of truth: lium/SKILL.md and lium/references/*.md.
# Run locally or in CI on every push to main.
#
# Usage:
#   ./scripts/build-llms-full.sh            # writes ./llms-full.txt
#   ./scripts/build-llms-full.sh /tmp/out   # writes /tmp/out

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/llms-full.txt}"

SKILL="$ROOT/lium/SKILL.md"
CLI_REF="$ROOT/lium/references/cli-commands.md"
SDK_REF="$ROOT/lium/references/sdk-reference.md"

for f in "$SKILL" "$CLI_REF" "$SDK_REF"; do
  [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }
done

# Strip YAML frontmatter (first --- ... --- block) from SKILL.md.
strip_frontmatter() {
  awk '
    BEGIN { in_fm = 0; done = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { in_fm = 0; done = 1; next }
    in_fm { next }
    { print }
  ' "$1"
}

# Drop only the "## Detailed References" section (external links) —
# references are inlined below instead. Resumes printing at the next ^## heading
# so any future sections appended after it are preserved.
strip_detailed_references_section() {
  awk '
    /^## Detailed References[[:space:]]*$/ { skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }
  ' /dev/stdin
}

{
  echo "# Lium — Full Reference for Agents"
  echo
  echo "Self-contained reference for AI agents. Includes skill overview, CLI command reference, and Python SDK reference."
  echo "Source of truth: https://github.com/Datura-ai/lium-skill"
  echo
  echo "---"
  echo

  strip_frontmatter "$SKILL" | strip_detailed_references_section
  echo
  echo "---"
  echo
  echo "# CLI Commands — Full Reference"
  echo
  cat "$CLI_REF"
  echo
  echo "---"
  echo
  echo "# Python SDK — Full Reference"
  echo
  cat "$SDK_REF"
} > "$OUT"

echo "Wrote $(wc -l < "$OUT") lines to $OUT"
