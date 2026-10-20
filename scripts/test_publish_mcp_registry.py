#!/usr/bin/env python3
"""Table test for scripts/publish-mcp-registry.py with a fake mcp-publisher and a fake registry; exit 0 when all pass."""

import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location('pub', pathlib.Path(__file__).with_name('publish-mcp-registry.py'))
pub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pub)

NEW, V = 'io.github.Datura-ai/lium-gpu-cloud', '1.0.0'
RESTORE = ('status', '--status', 'active', '--all-versions', '--yes', pub.OLD)

# name, publish rc, new version live after the failure?, restore rc, expected exit, restore expected?
CASES = [
    ('published', 0, True, 0, 0, False),
    ('failed before commit', 1, False, 0, 1, True),
    ('committed, response lost', 1, True, 0, 1, False),
    ('failed and restore failed', 1, False, 1, 1, True),
]

failed = 0
for name, publish_rc, live, restore_rc, want_rc, want_restore in CASES:
    calls = []

    def run(args):
        calls.append(tuple(args))
        return publish_rc if args == ['publish'] else restore_rc if tuple(args) == RESTORE else 0

    rc = pub.publish(run, lambda n, v: (n, v) == (NEW, V) and live, NEW, V)
    restored = RESTORE in calls
    ok = rc == want_rc and restored == want_restore and calls[0][:3] == ('status', '--status', 'deleted')
    print(f"{'ok  ' if ok else 'FAIL'} {name}: rc={rc} restored={restored}")
    failed += not ok

raise SystemExit(1 if failed else 0)
