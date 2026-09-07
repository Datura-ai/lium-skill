#!/usr/bin/env bash
# e2e.sh — the skill exercised the way an agent uses it, against the real CLI, without renting anything:
#   1. every `lium …` command line in SKILL.md, references/ and README parses against the released CLI
#      (subcommand exists, every --flag accepted; upcoming flags allow-listed in .cli-upcoming.txt with their PR);
#   2. agents/install.sh installs THIS checkout (served locally) into a throwaway HOME for Claude Code, Cursor and Codex,
#      and what it installed is byte-identical to the repo;
#   3. the first command the skill tells an agent to run, `lium ls --format json`, answers from the public feed with
#      the fields the skill names (the feed is public by design; the CLI only needs some key string set).
# Needs: python3, the `lium` CLI on PATH (CI: `uv tool install lium.io`), network. Exit 0 only when all three pass.
set -uo pipefail
cd "$(dirname "$0")/.."
FAILED=""
step() { local name=$1; shift; echo "::group::$name"; "$@"; local rc=$?; echo "::endgroup::"; echo "e2e: $name $([ $rc -eq 0 ] && echo pass || echo FAIL)"; [ $rc -eq 0 ] || FAILED="$FAILED $name"; }

check_commands() {
  python3 scripts/check-cli-examples.py --allow .cli-upcoming.txt lium README.md llms.txt
}

install_sh() {
  local home port pid
  home=$(mktemp -d); port=$(( 20000 + RANDOM % 20000 ))
  ( cd . && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & pid=$!
  sleep 1
  HOME="$home" LIUM_SKILL_RAW_BASE="http://127.0.0.1:$port" bash agents/install.sh --force >/dev/null || { kill $pid; return 1; }
  kill $pid
  local rc=0
  for d in .claude .cursor .codex; do
    if ! diff -rq lium "$home/$d/skills/lium" >/dev/null; then echo "installed copy in ~/$d/skills/lium differs from lium/"; diff -rq lium "$home/$d/skills/lium" | head; rc=1; fi
  done
  [ $rc -eq 0 ] && echo "install.sh: identical copies in ~/.claude, ~/.cursor, ~/.codex ($(find lium -type f | wc -l | tr -d ' ') files each)"
  rm -rf "$home"; return $rc
}

ls_json() {
  local home out
  home=$(mktemp -d)
  # the executor feed is public by design (the CLI still wants *a* key configured; any string does for `ls`)
  out=$(HOME="$home" LIUM_API_KEY="${LIUM_API_KEY:-lium_skill_e2e_no_real_key}" LIUM_BASE_URL="${LIUM_BASE_URL:-https://lium.io/api}" timeout 120 lium ls --format json 2>/dev/null) || { echo "lium ls --format json failed"; rm -rf "$home"; return 1; }
  rm -rf "$home"
  printf '%s' "$out" | python3 -c '
import json, sys
nodes = json.load(sys.stdin)
assert isinstance(nodes, list), type(nodes)
if not nodes:
    print("public feed lists 0 nodes right now — shape check only"); sys.exit(0)
need = {"id", "huid", "gpu_type", "gpu_count", "price_per_hour", "country"}
missing = need - set(nodes[0])
assert not missing, f"ls --format json lacks fields the skill names: {sorted(missing)}"
print(f"lium ls --format json: {len(nodes)} nodes, fields ok ({', '.join(sorted(need))})")'
}

step check-commands check_commands
step install-sh install_sh
step ls-json ls_json
[ -z "$FAILED" ] && echo "skill e2e: PASS" || { echo "skill e2e: FAIL ($FAILED)"; exit 1; }
