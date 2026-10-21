#!/usr/bin/env python3
"""Retire io.github.Datura-ai/lium-docs, then publish server.json.

The registry treats one endpoint under two names as spam and only a deleted entry frees its URL, so lium-docs is
deleted first. It is never restored: a publish that lost its response can still commit at any later time, and a
restore would then leave both names active. If the publish fails, the run exits non-zero and Lium has no registry
listing until the workflow is rerun (workflow_dispatch); deleting an already-deleted lium-docs is a no-op.

usage: publish-mcp-registry.py [--publisher ./mcp-publisher] [--server-json server.json]
"""

import argparse
import json
import subprocess
import sys

OLD = 'io.github.Datura-ai/lium-docs'


def publish(run, name):
    """Returns the exit code. run(args) -> rc for one mcp-publisher call."""
    if run(['status', '--status', 'deleted', '--all-versions', '--yes',
            '--message', f'Replaced by {name}', OLD]) != 0:
        print(f'{OLD} not changed (already deleted?)')
    rc = run(['publish'])
    if rc != 0:
        print(f'::error::publishing {name} failed; {OLD} stays deleted. Rerun this workflow to publish.')
    return rc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--publisher', default='./mcp-publisher')
    ap.add_argument('--server-json', default='server.json')
    a = ap.parse_args()
    server = json.load(open(a.server_json))
    sys.exit(publish(lambda args: subprocess.call([a.publisher, *args]), server['name']))


if __name__ == '__main__':
    main()
