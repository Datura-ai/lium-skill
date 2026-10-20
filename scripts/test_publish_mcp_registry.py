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


# The workflow's concurrency group runs pushes and manual runs one after another, never interleaved. Replay such
# sequences against a stateful fake registry: after every run at most one of the two names may be active.
# Each run's publish outcome: ok (lands), fail (never lands), lost (lands but the response is an error).
SEQUENCES = [
    ('fail then success', ['fail', 'ok']),
    ('lost then rerun', ['lost', 'ok']),
    ('fail, fail, recovery', ['fail', 'fail', 'ok']),
    ('success then rerun', ['ok', 'ok']),
]
for name, outcomes in SEQUENCES:
    reg = {pub.OLD: 'active', NEW: None}
    seen = []
    for outcome in outcomes:
        def run(args):
            if args[:3] == ['status', '--status', 'deleted']:
                reg[pub.OLD] = 'deleted'
                return 0
            if args == ['publish']:
                if reg[NEW] == 'active':
                    return 1  # the registry refuses a version it already holds
                if outcome in ('ok', 'lost'):
                    reg[NEW] = 'active'
                return 0 if outcome == 'ok' else 1
            if tuple(args) == RESTORE:
                if reg[NEW] == 'active':
                    return 1  # same URL under two names
                reg[pub.OLD] = 'active'
                return 0
            return 0

        pub.publish(run, lambda n, v: reg.get(n) == 'active', NEW, V)
        seen.append(sum(state == 'active' for state in reg.values()))
    ok = all(n == 1 for n in seen) and reg[NEW] == 'active'
    print(f"{'ok  ' if ok else 'FAIL'} {name}: active names after each run={seen}")
    failed += not ok

raise SystemExit(1 if failed else 0)
