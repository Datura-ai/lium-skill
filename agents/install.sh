#!/usr/bin/env bash
# Lium agent skill installer.
# Downloads the lium SKILL.md + references into Claude Code / Cursor / Codex skill dirs.
#
# Usage:
#   curl -fsSL https://lium.io/agents/install.sh | bash
#   curl -fsSL https://lium.io/agents/install.sh | bash -s -- --claude-only
#   curl -fsSL https://lium.io/agents/install.sh | bash -s -- --cursor-only
#   curl -fsSL https://lium.io/agents/install.sh | bash -s -- --codex-only

set -euo pipefail

RAW_BASE="${LIUM_SKILL_RAW_BASE:-https://raw.githubusercontent.com/Datura-ai/lium-skill/main}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

info()  { printf "%s[i]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
fail()  { printf "%s[✗]%s %s\n" "$RED"    "$NC" "$*" >&2; exit 1; }

install_claude=1
install_cursor=1
install_codex=1

for arg in "$@"; do
  case "$arg" in
    --claude-only) install_cursor=0; install_codex=0 ;;
    --cursor-only) install_claude=0; install_codex=0 ;;
    --codex-only)  install_claude=0; install_cursor=0 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "unknown flag: $arg" ;;
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
  info "Installing lium skill → $dest ($label)"
  mkdir -p "$dest/references"
  for rel in "${FILES[@]}"; do
    local dest_rel="${rel#lium/}"
    local url="$RAW_BASE/$rel"
    local out="$dest/$dest_rel"
    mkdir -p "$(dirname "$out")"
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
