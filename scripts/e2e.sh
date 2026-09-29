#!/usr/bin/env bash
# e2e.sh — the skill exercised the way an agent uses it, against the real CLI, without renting anything:
#   1. the checker's negative control passes (scripts/test_check_cli_examples.py: planted stale lines, incl. on
#      `lium mine`, are reported), then every `lium …` command line in SKILL.md, references/, README and llms.txt parses
#      against the released CLI (subcommand exists, every --flag accepted; upcoming flags allow-listed in
#      .cli-upcoming.txt with their PR);
#   2. agents/install.sh installs THIS checkout (served locally) into a throwaway HOME for Claude Code, Cursor and Codex,
#      and what it installed is byte-identical to the repo; a 404 for provider.md skips it with a warning (exit 0), and
#      a 500, a body cut short or a 404 for SKILL.md fails the install (exit 1) with an earlier install left
#      untouched; without --force an earlier SKILL.md is kept as SKILL.md.bak;
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

# Serves this checkout, but answers the file argv[2] with argv[3]: an HTTP status, or `drop` (a body cut short).
SERVE_WITH_FAULT='
import http.server, sys
port, path, fault = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if not self.path.endswith("/" + path) or fault == "none":
            return super().do_GET()
        if fault != "drop":
            return self.send_error(int(fault))
        self.send_response(200); self.send_header("Content-Length", "100000"); self.end_headers()
        self.wfile.write(b"# cut short"); self.wfile.flush(); self.connection.close()
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
'

# Each case: the file, its fault, the install flags. provider.md 404 is skipped (exit 0); any other fault fails the
# install (exit 1) with the earlier SKILL.md kept and no .part left; with no fault and no --force the earlier
# SKILL.md is kept as SKILL.md.bak.
install_sh_fetch_errors() {
  local home port pid out code skill rc=0 file fault flags
  while read -r file fault flags; do
    home=$(mktemp -d); port=$(( 20000 + RANDOM % 20000 ))
    skill="$home/.claude/skills/lium/SKILL.md"
    mkdir -p "$(dirname "$skill")"; echo "an earlier install" > "$skill"
    python3 -c "$SERVE_WITH_FAULT" "$port" "$file" "$fault" >/dev/null 2>&1 & pid=$!
    sleep 1
    # shellcheck disable=SC2086
    out=$(HOME="$home" LIUM_SKILL_RAW_BASE="http://127.0.0.1:$port" bash agents/install.sh --claude-only $flags 2>&1); code=$?
    kill $pid; wait $pid 2>/dev/null
    local case="install.sh: $file $fault ${flags:-(no --force)}"
    if [ "$fault" = none ]; then
      if [ $code -eq 0 ] && cmp -s lium/SKILL.md "$skill" && [ "$(cat "$skill.bak")" = "an earlier install" ]; then
        echo "$case → exit 0, earlier SKILL.md kept as SKILL.md.bak"
      else echo "$case → exit $code, want 0 with SKILL.md.bak holding the earlier install"; rc=1; fi
    elif [ "$fault" = 404 ] && [ "$file" = lium/references/provider.md ]; then
      if [ $code -eq 0 ] && [[ "$out" == *"skipped lium/references/provider.md"* ]] && cmp -s lium/SKILL.md "$skill" \
        && [ ! -e "$home/.claude/skills/lium/references/provider.md" ]; then
        echo "$case → skipped with a warning, exit 0"
      else echo "$case → exit $code, want 0 with the skip warning and SKILL.md installed"; rc=1; fi
    elif [ $code -eq 1 ] && [ "$(cat "$skill")" = "an earlier install" ] && [ -z "$(find "$home" -name '*.part')" ]; then
      echo "$case → exit 1, earlier install untouched"
    else echo "$case → exit $code, want 1 with the earlier SKILL.md kept and no .part left"; rc=1; fi
    rm -rf "$home"
  done <<'CASES'
lium/references/provider.md 404 --force
lium/references/provider.md 500 --force
lium/references/provider.md drop --force
lium/SKILL.md 404 --force
lium/SKILL.md none
CASES
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

provider_doc() {
  python3 - <<'PY'
import re, sys
doc = open("lium/references/provider.md").read()
bad = []
# the password comes from the environment the person set; an assignment on the line would replace it
if re.search(r"^\s*LIUM_PROVIDER_PASSWORD=\S* lium ", doc, re.M):
    bad.append("a command line sets LIUM_PROVIDER_PASSWORD")
print("\n".join(bad) or "provider.md: password from the environment")
sys.exit(1 if bad else 0)
PY
}

step check-commands check_commands
step provider-doc provider_doc
step install-sh install_sh
step install-sh-errors install_sh_fetch_errors
step ls-json ls_json
[ -z "$FAILED" ] && echo "skill e2e: PASS" || { echo "skill e2e: FAIL ($FAILED)"; exit 1; }
