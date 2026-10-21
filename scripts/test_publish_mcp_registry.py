#!/usr/bin/env python3
"""Test for scripts/publish-mcp-registry.py against a stateful fake registry; exit 0 when all pass."""

import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location('pub', pathlib.Path(__file__).with_name('publish-mcp-registry.py'))
pub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pub)

NEW = 'io.github.Datura-ai/lium-gpu-cloud'

# Each run's publish outcome: ok (lands), fail (never lands), lost (lands but the response is an error),
# late (the response is an error and the commit lands after the script exits). The script never reactivates
# lium-docs, so at no point may both names be active, and a final ok run must leave only the new name.
SEQUENCES = [
    ('success', ['ok']),
    ('fail then rerun', ['fail', 'ok']),
    ('lost then rerun', ['lost', 'ok']),
    ('late commit', ['late']),
    ('fail, fail, rerun', ['fail', 'fail', 'ok']),
    ('success then rerun', ['ok', 'ok']),
]
failed = 0
for name, outcomes in SEQUENCES:
    reg = {pub.OLD: 'active', NEW: None}
    rcs, both = [], False
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
            raise AssertionError(f'unexpected publisher call {args}')

        rcs.append(pub.publish(run, NEW))
        if outcome == 'late':
            reg[NEW] = 'active'
        both |= all(state == 'active' for state in reg.values())
    want_rc = {'ok': 0, 'fail': 1, 'lost': 1, 'late': 1}
    landed = any(o != 'fail' for o in outcomes)
    ok = not both and reg[pub.OLD] == 'deleted' and rcs[0] == want_rc[outcomes[0]] and (reg[NEW] == 'active') == landed
    print(f"{'ok  ' if ok else 'FAIL'} {name}: rcs={rcs} both_active={both}")
    failed += not ok

raise SystemExit(1 if failed else 0)
