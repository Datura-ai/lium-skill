#!/usr/bin/env python3
"""Fail when the released CLI has moved past the docs: every top-level `lium --help` command needs a `## lium <cmd>`
section in references/cli-commands.md, and SKILL.md's "Covers lium CLI and SDK X" line must name `lium --version`.
The e2e job runs this daily, so a CLI release turns it red until the reference catches up (the 1 Oct -> 0.16.1 gap)."""
import re
import subprocess
import sys

lium = sys.argv[1] if len(sys.argv) > 1 else "lium"
help_text = subprocess.run([lium, "--help"], capture_output=True, text=True, check=True).stdout
commands = re.findall(r"^  ([a-z][a-z0-9-]*)\s", help_text.split("Commands:", 1)[1], re.M)
version = subprocess.run([lium, "--version"], capture_output=True, text=True, check=True).stdout.split()[-1]

ref = open("lium/references/cli-commands.md").read()
skill = open("lium/SKILL.md").read()
# In the CLI but switched off on lium.io (workspaces login answers "not enabled"; keys need a workspace session):
# the reference documents only what works there. Drop a name once lium.io serves it.
NOT_ON_LIUM_IO = {"keys", "workspaces"}
missing = [c for c in commands if c not in NOT_ON_LIUM_IO and not re.search(rf"^## lium {re.escape(c)}\b", ref, re.M)]
covers = re.search(r"Covers lium CLI and SDK ([0-9][0-9.]*)", skill)

problems = []
if missing:
    problems.append("undocumented commands in references/cli-commands.md: " + ", ".join(missing))
if not covers:
    problems.append("SKILL.md has no 'Covers lium CLI and SDK X' line")
elif covers.group(1) != version:
    problems.append(f"SKILL.md covers {covers.group(1)}, the released CLI is {version}: review the release, then bump the line")
assert commands, "parsed no commands from `lium --help`"  # the parser itself broke, not the docs
for p in problems:
    print("::error::" + p)
print(f"CLI coverage: {len(commands)} commands, {len(missing)} undocumented; docs cover {covers.group(1) if covers else '?'}, CLI {version}")
sys.exit(1 if problems else 0)
