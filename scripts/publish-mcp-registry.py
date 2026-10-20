#!/usr/bin/env python3
"""Retire io.github.Datura-ai/lium-docs, publish server.json, and put lium-docs back if the new name did not land.

The registry commits the lium-docs deletion on its own, so a failed publish (a 503, say) would leave Lium with no
listing. On failure this asks the registry whether the new version is live, since a publish can commit and still
lose its response: live means keep it (restoring lium-docs would clash on the URL); not live means reactivate
lium-docs. The script exits non-zero whenever the publish failed, so the run still shows red.

usage: publish-mcp-registry.py [--publisher ./mcp-publisher] [--server-json server.json]
"""

import argparse
import json
import subprocess
import sys
import urllib.parse
import urllib.request

OLD = 'io.github.Datura-ai/lium-docs'
REGISTRY = 'https://registry.modelcontextprotocol.io'


def is_live(name, version):
    url = f"{REGISTRY}/v0/servers/{urllib.parse.quote(name, safe='')}/versions/{urllib.parse.quote(version, safe='')}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            meta = json.load(resp).get('_meta', {}).get('io.modelcontextprotocol.registry/official', {})
    except Exception as exc:  # 404 (not published) or the registry is down: either way we cannot see it live
        print(f'registry check for {name} {version}: {exc}')
        return False
    return meta.get('status') == 'active'


def publish(run, live, name, version):
    """Returns the exit code. run(args) -> rc for one mcp-publisher call; live(name, version) -> bool."""
    if run(['status', '--status', 'deleted', '--all-versions', '--yes',
            '--message', f'Replaced by {name}', OLD]) != 0:
        print(f'{OLD} not changed (already deleted?)')
    rc = run(['publish'])
    if rc == 0:
        return 0
    if live(name, version):
        print(f'publish reported failure but {name} {version} is live; leaving {OLD} deleted')
    elif run(['status', '--status', 'active', '--all-versions', '--yes', OLD]) == 0:
        print(f'{name} was not published; restored {OLD}')
    else:
        print(f'::error::{name} was not published and restoring {OLD} failed; Lium may have no registry listing')
    return rc or 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--publisher', default='./mcp-publisher')
    ap.add_argument('--server-json', default='server.json')
    a = ap.parse_args()
    server = json.load(open(a.server_json))
    sys.exit(publish(lambda args: subprocess.call([a.publisher, *args]), is_live, server['name'], server['version']))


if __name__ == '__main__':
    main()
