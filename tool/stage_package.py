#!/usr/bin/env python3
"""Copy the reviewable tree without Git metadata, ignored files or submodules."""
import argparse
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path)
parser.add_argument('--publishable', action='store_true', help='Remove publish_to only in this dry-run copy')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
destination = args.destination.resolve()
if destination == root or root in destination.parents or destination.exists():
    raise SystemExit('Use a new destination outside the repository.')
files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
for relative in sorted(set(files)):
    if not relative:
        continue
    source = root / relative
    if not source.is_file():
        continue  # Includes removed files and preserved submodule directories.
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
if args.publishable:
    spec = destination / 'pubspec.yaml'
    spec.write_text(spec.read_text().replace('publish_to: none\n', ''))
