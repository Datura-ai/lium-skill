#!/usr/bin/env bash
# e2e.sh — the skill exercised the way an agent uses it, against the real CLI, without renting anything:
#   1. the checker's negative control passes (scripts/test_check_cli_examples.py: planted stale lines, incl. on
#      `lium mine`, are reported), then every `lium …` command line in SKILL.md, references/, README and llms.txt parses
#      against the released CLI (subcommand exists, every --flag accepted; upcoming flags allow-listed in
#      .cli-upcoming.txt with their PR);
#   2. agents/install.sh installs THIS checkout (served locally) into a throwaway HOME for Claude Code, Cursor and Codex,
#      and what it installed is byte-identical to the repo; a 404 for provider.md skips it with a warning (exit 0), and
#      a 500 fails the install (exit 1) with an earlier install left untouched;
#   3. the first command the skill tells an agent to run, `lium ls --format json`, answers from the public feed with
#      the fields the skill names (the feed is public by design; the CLI only needs some key string set).
# Needs: python3, the `lium` CLI on PATH (CI: `uv tool install lium.io`), network; step 3 uses GNU `timeout` when
# present (coreutils; `gtimeout` from Homebrew on a Mac) and runs unbounded without it. Exit 0 only when every step passes.
set -uo pipefail
cd "$(dirname "$0")/.."
FAILED=""
step() { local name=$1; shift; echo "::group::$name"; "$@"; local rc=$?; echo "::endgroup::"; echo "e2e: $name $([ $rc -eq 0 ] && echo pass || echo FAIL)"; [ $rc -eq 0 ] || FAILED="$FAILED $name"; }

check_commands() {
  python3 scripts/test_check_cli_examples.py && python3 scripts/check-cli-examples.py --allow .cli-upcoming.txt lium README.md llms.txt
}

install_sh() {
  local home port pid
  home=$(mktemp -d); port=$(( 20000 + RANDOM % 20000 ))
  # started directly so $! is the server (a subshell wrapper leaves the python process alive after `kill $pid` on bash 3.2)
  python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 & pid=$!
  sleep 1
  HOME="$home" LIUM_SKILL_RAW_BASE="http://127.0.0.1:$port" bash agents/install.sh --force >/dev/null || { kill $pid; wait $pid 2>/dev/null; return 1; }
  kill $pid; wait $pid 2>/dev/null
  local rc=0
  for d in .claude .cursor .codex; do
    if ! diff -rq lium "$home/$d/skills/lium" >/dev/null; then echo "installed copy in ~/$d/skills/lium differs from lium/"; diff -rq lium "$home/$d/skills/lium" | head; rc=1; fi
  done
  [ $rc -eq 0 ] && echo "install.sh: identical copies in ~/.claude, ~/.cursor, ~/.codex ($(find lium -type f | wc -l | tr -d ' ') files each)"
  rm -rf "$home"; return $rc
}

# Serves this checkout, but answers provider.md with the status in argv[2].
SERVE_WITH_STATUS='
import http.server, sys
port, status = int(sys.argv[1]), int(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.endswith("/lium/references/provider.md"):
            self.send_error(status)
            return
        super().do_GET()
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
'

install_sh_fetch_errors() {
  local home port pid out code status skill rc=0
  for status in 404 500; do
    home=$(mktemp -d); port=$(( 20000 + RANDOM % 20000 ))
    skill="$home/.claude/skills/lium/SKILL.md"
    mkdir -p "$(dirname "$skill")"; echo "an earlier install" > "$skill"
    python3 -c "$SERVE_WITH_STATUS" "$port" "$status" >/dev/null 2>&1 & pid=$!
    sleep 1
    out=$(HOME="$home" LIUM_SKILL_RAW_BASE="http://127.0.0.1:$port" bash agents/install.sh --claude-only --force 2>&1); code=$?
    kill $pid; wait $pid 2>/dev/null
    if [ "$status" = 404 ]; then
      if [ $code -eq 0 ] && [[ "$out" == *"skipped lium/references/provider.md"* ]] && cmp -s lium/SKILL.md "$skill" \
        && [ ! -e "$home/.claude/skills/lium/references/provider.md" ]; then
        echo "install.sh: provider.md 404 → skipped with a warning, exit 0"
      else echo "install.sh: provider.md 404 → exit $code, want 0 with the skip warning and SKILL.md installed"; rc=1; fi
    else
      if [ $code -eq 1 ] && [ "$(cat "$skill")" = "an earlier install" ] && [ -z "$(find "$home" -name '*.part')" ]; then
        echo "install.sh: provider.md $status → exit 1, earlier install untouched"
      else echo "install.sh: provider.md $status → exit $code, want 1 with the earlier SKILL.md kept and no .part left"; rc=1; fi
    fi
    rm -rf "$home"
  done
  return $rc
}

ls_json() {
  local home out t
  home=$(mktemp -d)
  t=$(command -v timeout || command -v gtimeout || true)   # GNU coreutils; stock macOS has neither
  # the executor feed is public by design (the CLI still wants *a* key configured; any string does for `ls`)
  out=$(HOME="$home" LIUM_API_KEY="${LIUM_API_KEY:-lium_skill_e2e_no_real_key}" LIUM_BASE_URL="${LIUM_BASE_URL:-https://lium.io/api}" ${t:+"$t" 120} lium ls --format json 2>/dev/null) || { echo "lium ls --format json failed"; rm -rf "$home"; return 1; }
  rm -rf "$home"
  printf '%s' "$out" > "${TMPDIR:-/tmp}/lium-ls.json"
  python3 - "${TMPDIR:-/tmp}/lium-ls.json" <<'PY'
import json, sys
nodes = json.load(open(sys.argv[1]))
assert isinstance(nodes, list), type(nodes)
if not nodes:
    print("public feed lists 0 nodes right now - shape check only"); sys.exit(0)
need = {"id", "huid", "gpu_type", "gpu_count", "price_per_hour", "country"}
missing = need - set(nodes[0])
assert not missing, "ls --format json lacks fields the skill names: %s" % sorted(missing)
print("lium ls --format json: %d nodes, fields ok (%s)" % (len(nodes), ", ".join(sorted(need))))
PY
}

step check-commands check_commands
step install-sh install_sh
step install-sh-errors install_sh_fetch_errors
step ls-json ls_json
[ -z "$FAILED" ] && echo "skill e2e: PASS" || { echo "skill e2e: FAIL ($FAILED)"; exit 1; }
