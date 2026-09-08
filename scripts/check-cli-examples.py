#!/usr/bin/env python3
"""Every `lium …` command the docs show must parse against the real CLI.

Extracts each command line that starts with `lium` inside fenced code blocks of the given files/directories (.md/.mdx),
then, read-only and without renting anything, checks with the installed CLI that

  * the (nested) subcommand exists — `lium <sub…> --help` exits 0;
  * every `--flag` on the line is listed in that subcommand's `--help` (group flags count for `lium provider …`), or
    is parsed by it anyway — `lium <sub> --help --flag` exits 0 — which is how a hidden alias such as `--json` passes.

Lines whose subcommand is a placeholder (`lium <command>`), chained commands past the first `&&`/`|`, and flags inside
quoted remote commands are ignored. Known-upcoming flags live in an allow-list file (one `subcommand|--flag|why` per
line; `*` as the subcommand matches any subcommand, `*` as the flag allows a subcommand the released CLI does not have
yet, flags included) so a doc may describe what ships in a pending release — each entry names the PR or ticket that
removes it.

usage: check-cli-examples.py [--lium PATH] [--allow FILE] [--report FILE] PATH...      exit 1 when any line is stale
"""

import argparse
import glob
import os
import re
import subprocess
import sys
import time

ap = argparse.ArgumentParser()
ap.add_argument("paths", nargs="+")
ap.add_argument("--lium", default=os.environ.get("LIUM", "lium"))
ap.add_argument("--allow", default=None, help="allow-list: `subcommand|--flag|reason` per line (`sub|*|…` = whole subcommand), # comments")
ap.add_argument("--report", default=None, help="write the markdown report here too ($GITHUB_STEP_SUMMARY is always appended)")
args = ap.parse_args()

files = []
for r in args.paths:
    files += [r] if os.path.isfile(r) else glob.glob(f"{r}/**/*.md", recursive=True) + glob.glob(f"{r}/**/*.mdx", recursive=True)
files = sorted(f for f in set(files) if "/node_modules/" not in f and "/.git/" not in f)

allow = set()
if args.allow and os.path.exists(args.allow):
    for ln in open(args.allow):
        ln = ln.split("#", 1)[0].strip()
        if ln:
            sub, flag, *_ = [x.strip() for x in ln.split("|")]
            allow.add((sub, flag))

cmds = []  # (file, line, command)
for f in files:
    infence = False
    for i, ln in enumerate(open(f, errors="replace"), 1):
        if ln.strip().startswith("```"):
            infence = not infence
            continue
        m = re.match(r"^\s*(?:\$\s*)?(lium\s+[a-z][a-z0-9-]*.*)$", ln) if infence else None
        if m:
            c = re.sub(r"\s+#.*$", "", m.group(1)).strip()
            if not c.startswith("lium --"):
                cmds.append((f, i, c))

help_cache: dict[str, tuple[int, str]] = {}


def helptext(sub: str) -> tuple[int, str]:
    if sub not in help_cache:
        try:
            p = subprocess.run([args.lium, *sub.split(), "--help"], capture_output=True, text=True, timeout=60,
                               env={**os.environ, "NO_COLOR": "1", "TERM": "dumb", "HOME": os.environ.get("CHECK_HOME", os.environ.get("HOME", "/tmp"))})
            help_cache[sub] = (p.returncode, p.stdout + p.stderr)
        except (OSError, subprocess.TimeoutExpired) as exc:
            help_cache[sub] = (127, str(exc))
    return help_cache[sub]


accept_cache: dict[tuple[str, str], bool] = {}


def accepts(sub: str, flag: str) -> bool:
    """True when the CLI parses `flag` for `sub` although `--help` does not list it (a Click `hidden=True` option,
    e.g. the `--json` alias of `--format json`). `lium <sub> --help <flag>` exits 0 when the parser knows the flag
    (`--help` is eager, so it prints and exits before any value is used) and 2 on `No such option`; the `=x` form
    covers a hidden option that takes a value."""
    key = (sub, flag)
    if key not in accept_cache:
        ok = False
        for probe in (flag, f"{flag}=x"):
            try:
                p = subprocess.run([args.lium, *sub.split(), "--help", probe], capture_output=True, text=True, timeout=60,
                                   env={**os.environ, "NO_COLOR": "1", "TERM": "dumb", "HOME": os.environ.get("CHECK_HOME", os.environ.get("HOME", "/tmp"))})
            except (OSError, subprocess.TimeoutExpired):
                break
            if p.returncode == 0:
                ok = True
                break
        accept_cache[key] = ok
    return accept_cache[key]


def subcommands(sub: str) -> set[str]:
    rc, h = helptext(sub)
    m = re.search(r"Commands:\n((?:\s+\S.*\n?)+)", h)
    return set(re.findall(r"^\s+([a-z][a-z0-9-]*)", m.group(1), re.M)) if rc == 0 and m else set()


subs_seen, stale, allowed = set(), [], []
for f, i, c in cmds:
    c_noq = re.sub(r"(\"[^\"]*\"|'[^']*')", "STR", c)
    c_noq = re.split(r"\s(?:&&|\|\||\||;)\s", c_noq)[0]
    parts = c_noq.split()
    if len(parts) < 2 or not re.match(r"^[a-z][a-z0-9-]*$", parts[1]):
        continue
    sub, j = parts[1], 2
    while j < len(parts) and j <= 4 and parts[j] in subcommands(sub):
        sub = f"{sub} {parts[j]}"
        j += 1
    rc, h = helptext(sub)
    subs_seen.add(sub)
    if rc != 0:
        if (sub, "*") in allow:
            allowed.append((f, i, c, [f"`lium {sub}`"]))
        else:
            stale.append((f, i, c, f"subcommand `lium {sub}` not found (exit {rc})"))
        continue
    flags = [t.split("=")[0].strip("[]") for t in parts[j:] if t.startswith("--") and len(t) > 2]
    group_help = helptext(sub.split()[0])[1] if sub.startswith("provider") else ""
    missing = [fl for fl in flags if fl not in h and fl not in group_help and not accepts(sub, fl)]
    still = [fl for fl in missing if (sub, fl) not in allow and ("*", fl) not in allow]
    if missing and not still:
        allowed.append((f, i, c, missing))
    if still:
        stale.append((f, i, c, f"flag(s) {', '.join(still)} not in `lium {sub} --help`"))

ver = subprocess.run([args.lium, "--version"], capture_output=True, text=True).stdout.strip() or "unknown"
lines = [f"### CLI examples check — {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}", "",
         f"{len(files)} files, {len(cmds)} `lium` command lines, {len(subs_seen)} distinct subcommands, CLI `{ver}`; "
         f"**{len(stale)} stale**, {len(allowed)} allow-listed (upcoming).", ""]
if stale:
    lines += ["| file:line | documented command | problem |", "|---|---|---|"]
    lines += [f"| `{f}:{i}` | `{c.replace('|', '/')}` | {why} |" for f, i, c, why in stale]
    lines.append("")
if allowed:
    lines += ["<details><summary>allow-listed (flags on pending releases)</summary>", "",
              *[f"- `{f}:{i}` `{c.replace('|', '/')}` — {', '.join(fl)}" for f, i, c, fl in allowed], "", "</details>", ""]
report = "\n".join(lines)
print(report)
for dest in filter(None, (args.report, os.environ.get("GITHUB_STEP_SUMMARY"))):
    with open(dest, "a") as o:
        o.write(report + "\n")
sys.exit(1 if stale else 0)
