#!/usr/bin/env bash
# Lium agent skill installer.
# Downloads the lium SKILL.md + references into Claude Code / Cursor / Codex skill dirs.

set -euo pipefail

# Ref (branch or tag) to install from. Override to pin a known-good version:
#   LIUM_SKILL_VERSION=v0.1.0 curl -fsSL ... | bash
LIUM_SKILL_VERSION="${LIUM_SKILL_VERSION:-main}"
RAW_BASE="${LIUM_SKILL_RAW_BASE:-https://raw.githubusercontent.com/Datura-ai/lium-skill/${LIUM_SKILL_VERSION}}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

info()  { printf "%s[i]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
fail()  { printf "%s[✗]%s %s\n" "$RED"    "$NC" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Lium agent skill installer.

Usage:
  curl -fsSL https://lium.io/agents/install.sh | bash
  curl -fsSL https://lium.io/agents/install.sh | bash -s -- [options]

Options:
  --claude-only        Install only into ~/.claude/skills/lium/
  --cursor-only        Install only into ~/.cursor/skills/lium/
  --codex-only         Install only into ~/.codex/skills/lium/
  --force              Overwrite existing files without backup
  -h, --help           Show this help

Environment:
  LIUM_SKILL_VERSION   Git ref to install from (default: main). Pin a tag for
                       reproducibility: LIUM_SKILL_VERSION=v0.1.0 ...
  LIUM_SKILL_RAW_BASE  Full raw URL base override (default derived from VERSION)

By default, existing skill files are backed up to *.bak before overwriting.
EOF
}

install_claude=1
install_cursor=1
install_codex=1
force=0

for arg in "$@"; do
  case "$arg" in
    --claude-only) install_cursor=0; install_codex=0 ;;
    --cursor-only) install_claude=0; install_codex=0 ;;
    --codex-only)  install_claude=0; install_cursor=0 ;;
    --force)       force=1 ;;
    -h|--help)     usage; exit 0 ;;
    *) fail "unknown flag: $arg (try --help)" ;;
  esac
done

command -v curl >/dev/null 2>&1 || fail "curl is required"

FILES=(
  "lium/SKILL.md"
  "lium/references/cli-commands.md"
  "lium/references/sdk-reference.md"
)

install_into() {
  local target_root="$1" label="$2"
  local dest="$target_root/lium"
  info "Installing lium skill → $dest ($label, ref: $LIUM_SKILL_VERSION)"
  mkdir -p "$dest/references"
  for rel in "${FILES[@]}"; do
    local dest_rel="${rel#lium/}"
    local url="$RAW_BASE/$rel"
    local out="$dest/$dest_rel"
    mkdir -p "$(dirname "$out")"

    # Preserve user edits: back up existing file unless --force
    if [[ -f "$out" && $force -eq 0 ]]; then
      cp "$out" "$out.bak"
    fi

    if ! curl -fsSL "$url" -o "$out"; then
      fail "failed to download $url"
    fi
  done
  ok "Installed $label skill ($(wc -l < "$dest/SKILL.md" | tr -d ' ') lines in SKILL.md)"
}

any_installed=0

if [[ $install_claude -eq 1 ]]; then
  install_into "$HOME/.claude/skills" "Claude Code"
  any_installed=1
fi

if [[ $install_cursor -eq 1 ]]; then
  install_into "$HOME/.cursor/skills" "Cursor"
  any_installed=1
fi

if [[ $install_codex -eq 1 ]]; then
  install_into "$HOME/.codex/skills" "Codex"
  any_installed=1
fi

[[ $any_installed -eq 1 ]] || fail "no target selected"

ok "Done. Restart your agent (or reload skills) to pick up the new skill."
