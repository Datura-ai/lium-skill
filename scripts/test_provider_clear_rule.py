#!/usr/bin/env python3
"""Document contract for provider.md's blocking rule: step 4, step 5 and the watch's Clear predicate say the same thing.

Step 4 defines when a reason blocks: `gating: true`, a `kind` other than `idle_pay`, or no `gating` and a code the
Blocking reasons table does not mark non-gating. Step 5 and the Clear predicate repeat that rule in their own words; an
agent that reads only the Clear bullet must not call a node clear while a reason step 4 calls blocking is still listed.

The checks, on lium/references/provider.md and on the generated llms-full.txt:

  * each of the three places names all three blocking conditions (the missing-gating one is what the Clear bullet
    once dropped: `{"code": "future_gate", "requires_unknown": true}` with neither `kind` nor `gating` read as clear);
  * step 4's rule, applied with the page's own table, blocks on that unknown reason and on the table's gating codes,
    and lets through the codes the table marks non-gating and an `idle_pay` reason with `gating: false`.

usage: test_provider_clear_rule.py      exit 0 when every check passes, 1 otherwise
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = [ROOT / "lium" / "references" / "provider.md", ROOT / "llms-full.txt"]
UNKNOWN_REASON = {"code": "future_gate", "requires_unknown": True}


def section(text: str, start: str, end: str) -> str:
    i = text.index(start)
    return text[i : text.index(end, i)]


def places(text: str) -> dict[str, str]:
    step4 = section(text, "Read `gating` from the reason", "### 5. Fix, then verify")
    step5 = section(text, "For each reason that blocks by the rule of", "decide first")
    clear = section(text, "- **Clear** only when", "**and** `lium provider node listing")
    return {name: " ".join(body.split()) for name, body in (("step 4", step4), ("step 5", step5), ("Clear", clear))}


def names_every_condition(body: str) -> list[str]:
    missing = []
    if "`gating: true`" not in body:
        missing.append("gating: true")
    if not re.search(r"`kind` other\s+than `idle_pay`", body):
        missing.append("a kind other than idle_pay")
    if not re.search(r"without `gating`|no `gating`", body) or "`gating: false`" not in body:
        missing.append("no gating unless the table marks the code gating: false")
    return missing


def non_gating_codes(text: str) -> set[str]:
    table = section(text, "## Blocking reasons", "### Discord linking")
    codes = set()
    for row in table.splitlines():
        m = re.match(r"\|\s*`([a-z_]+)`\s*\|(.*)", row)
        if m and ("`gating: false`" in m.group(2) or "not gating" in m.group(2)):
            codes.add(m.group(1))
    return codes


def blocks(reason: dict, non_gating: set[str]) -> bool:
    if reason.get("gating") is True:
        return True
    if reason.get("kind", "idle_pay") != "idle_pay":
        return True
    if "gating" not in reason:
        return reason.get("code") not in non_gating
    return False


def check(doc: Path) -> list[str]:
    text = doc.read_text()
    failures = []
    for name, body in places(text).items():
        for cond in names_every_condition(body):
            failures.append(f"{doc.name}: {name} does not name the condition `{cond}`")

    non_gating = non_gating_codes(text)
    if not non_gating:
        failures.append(f"{doc.name}: no code in the Blocking reasons table is marked non-gating")
    cases = [
        (UNKNOWN_REASON, True),
        ({"code": "future_gate", "gating": True}, True),
        ({"code": "future_gate", "kind": "availability", "gating": False}, True),
        ({"code": "future_gate", "kind": "idle_pay", "gating": False}, False),
        *(({"code": code}, False) for code in sorted(non_gating)),
    ]
    for reason, want in cases:
        if blocks(reason, non_gating) is not want:
            failures.append(f"{doc.name}: step 4 reads {reason} as {'clear' if want else 'blocking'}")
    if UNKNOWN_REASON["code"] in non_gating:
        failures.append(f"{doc.name}: the table marks the made-up code {UNKNOWN_REASON['code']} non-gating")
    return failures


def main() -> int:
    failures = [f for doc in DOCS for f in check(doc)]
    for f in failures:
        print(f"FAIL {f}")
    if failures:
        return 1
    print(f"PASS: step 4, step 5 and the Clear predicate agree in {', '.join(d.name for d in DOCS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
