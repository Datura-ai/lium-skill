#!/usr/bin/env python3
"""Negative control for scripts/check-cli-examples.py against the installed CLI: a doc that IS stale must fail it.

Writes one markdown file with command lines a drifted doc could contain and asserts the checker reports exactly them:

  * `lium ls --definitely-not-a-flag`               a flag the CLI does not have, on an ordinary subcommand;
  * `lium mine --definitely-not-a-flag` and `=5`    the same on `lium mine`, which Click declares with
                                                    `ignore_unknown_options=True`: `lium mine --help --definitely-not-a-flag`
                                                    exits 0, so the hidden-flag probe alone would read it as "flag exists"
                                                    and let the line through — ignores_unknown_options() is what catches it;
  * `lium definitely-not-a-subcommand`              a subcommand the CLI does not have;
  * `lium up --port 5`                              a flag that is only a prefix of a real one (`--ports` is in
                                                    `lium up --help`; whole option tokens are compared, not substrings);
  * `lium ls \` + `  --definitely-not-a-flag`       the same unknown flag on a backslash-continued line (the two physical
                                                    lines are one command, reported at the first);
  * `lium provider statu --json`                    a plain word after a group that is none of its sub-commands (the CLI
                                                    answers `No such command 'statu'`; `--json` alone would pass);

while lines that use only flags from `lium ls --help` / `lium mine --help` / `lium up --help` (`--template_id`, `--ports`) stay
clean (one of them backslash-continued), and an allow-listed unknown flag
is reported as allow-listed, not stale.

usage: test_check_cli_examples.py [--lium PATH]      exit 0 when every verdict matches, 1 otherwise, 2 when the CLI is missing
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--lium", default=os.environ.get("LIUM", "lium"))
args = ap.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
checker = os.path.join(here, "check-cli-examples.py")

try:
    ver = subprocess.run([args.lium, "--version"], capture_output=True, text=True, timeout=60)
except OSError as exc:
    print(f"cannot run {args.lium}: {exc}")
    sys.exit(2)
if ver.returncode != 0:
    print(f"{args.lium} --version exited {ver.returncode}: {ver.stderr.strip()}")
    sys.exit(2)

# The property this test guards. Stated, not asserted: a CLI release that stops ignoring unknown options on `mine`
# makes the guard inert, and the planted `mine` lines below must be reported stale either way.
probe = subprocess.run([args.lium, "mine", "--help", "--definitely-not-a-flag"], capture_output=True, text=True, timeout=60)
print(f"{ver.stdout.strip()}; `lium mine --help --definitely-not-a-flag` exits {probe.returncode} "
      + ("(the probe alone would accept any flag on `lium mine`)" if probe.returncode == 0 else "(the CLI rejects unknown options on `lium mine`)"))

STALE = {
    "lium ls --definitely-not-a-flag": "flag(s) --definitely-not-a-flag not in `lium ls --help`",
    "lium mine --definitely-not-a-flag": "flag(s) --definitely-not-a-flag not in `lium mine --help`",
    "lium mine -k hotkey --definitely-not-a-flag=5": "flag(s) --definitely-not-a-flag not in `lium mine --help`",
    "lium definitely-not-a-subcommand --help": "subcommand `lium definitely-not-a-subcommand` not found",
    "lium up --port 5": "flag(s) --port not in `lium up --help`",
    "lium ls --definitely-not-a-flag --format json": "flag(s) --definitely-not-a-flag not in `lium ls --help`",   # continued
    "lium provider statu --json": "`statu` is not a sub-command of `lium provider`",
}
CLEAN = [
    "lium ls --format json",
    "lium mine -k hotkey --auto",   # written as two backslash-continued lines
    "lium mine --verbose",
    "lium up 1 --template_id abc --ports 8080",
]
ALLOWED = ["lium mine --allow-listed-flag"]
# what the planted markdown holds: each command on one line, except the two continued ones
DOC_LINES = [
    *[c for c in STALE if not c.startswith("lium ls --definitely-not-a-flag --format")],
    "lium ls \\",
    "  --definitely-not-a-flag \\",
    "  --format json",
    "lium ls --format json",
    "lium mine -k hotkey \\",
    "  --auto",
    "lium mine --verbose",
    "lium up 1 --template_id abc --ports 8080",
    *ALLOWED,
]

with tempfile.TemporaryDirectory() as tmp:
    doc = os.path.join(tmp, "planted.md")
    with open(doc, "w") as fh:
        fh.write("# planted\n\n```bash\n" + "\n".join(DOC_LINES) + "\n```\n")
    allow = os.path.join(tmp, "allow.txt")
    with open(allow, "w") as fh:
        fh.write("mine|--allow-listed-flag|test_check_cli_examples.py\n")
    run = subprocess.run([sys.executable, checker, "--lium", args.lium, "--allow", allow, doc],
                         capture_output=True, text=True, timeout=600, env={**os.environ, "GITHUB_STEP_SUMMARY": ""})

report = run.stdout
rows = {m.group(1): m.group(2) for m in re.finditer(r"^\| `[^`]+:\d+` \| `([^`]+)` \| (.+?) \|$", report, re.M)}
allowed_lines = set(re.findall(r"^- `[^`]+:\d+` `([^`]+)` — ", report, re.M))

failures = []
if run.returncode != 1:
    failures.append(f"checker exited {run.returncode}, expected 1 (stale lines present)")
for cmd, why in STALE.items():
    if cmd not in rows:
        failures.append(f"not reported stale: `{cmd}`")
    elif not rows[cmd].startswith(why):
        failures.append(f"`{cmd}` reported as {rows[cmd]!r}, expected {why!r}")
for cmd in CLEAN:
    if cmd in rows:
        failures.append(f"reported stale but every flag is in --help: `{cmd}` ({rows[cmd]})")
for cmd in ALLOWED:
    if cmd in rows or cmd not in allowed_lines:
        failures.append(f"allow-listed line not reported as allow-listed: `{cmd}`")
extra = set(rows) - set(STALE)
if extra:
    failures.append(f"unexpected stale rows: {sorted(extra)}")

if failures:
    print("test_check_cli_examples: FAIL")
    print("\n".join(f"  - {f}" for f in failures))
    print("--- checker output ---")
    print(report + run.stderr)
    sys.exit(1)
print(f"test_check_cli_examples: PASS ({len(STALE)} planted lines stale, {len(CLEAN)} clean, {len(ALLOWED)} allow-listed)")
