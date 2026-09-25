#!/usr/bin/env python3
"""Run an opt-in smoke test without putting credentials in arguments or logs."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--env-file', required=True, type=Path)
parser.add_argument('--flutter', default='flutter')
parser.add_argument('--event', help='Approved existing event definition for one synthetic event per SDK ID')
args = parser.parse_args()
allowed = {'CONFIDENCE_FLAG_CLIENT_SECRET', 'CONFIDENCE_TEST_FLAG', 'CONFIDENCE_TARGETING_KEY'}
values = {}
for line in args.env_file.read_text().splitlines():
    line = line.strip().removeprefix('export ')
    if not line or line.startswith('#') or '=' not in line:
        continue
    key, value = line.split('=', 1)
    if key.strip() not in allowed:
        continue
    parts = shlex.split(value, comments=True)
    if len(parts) != 1:
        raise SystemExit('Required smoke configuration has an invalid value.')
    values[key.strip()] = parts[0]
if any(not values.get(key) for key in allowed):
    raise SystemExit('Missing required flag smoke configuration.')
env = dict(os.environ, **values)
env.pop('CONFIDENCE_SMOKE_EVENT', None)
if args.event:
    env['CONFIDENCE_SMOKE_EVENT'] = args.event
package = Path(__file__).resolve().parents[2]
raise SystemExit(subprocess.call([args.flutter, 'test', '--no-pub',
    'tool/live_smoke/live_smoke_test.dart', '--reporter', 'expanded'], cwd=package, env=env))
