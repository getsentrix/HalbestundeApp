#!/usr/bin/env python3
"""
scripts/trigger_release.py

Trigger an automated iOS release build via GitHub Actions:
- Increments version number (patch by default)
- Builds .ipa on macOS runner (Xcode 15.4)
- Creates GitHub Release (v1.0.X)
- Updates apps.json AltStore source repository so AltStore catches the update

Usage:
  python scripts/trigger_release.py
  python scripts/trigger_release.py --bump minor
  python scripts/trigger_release.py --version 1.1.0
"""

import argparse
import subprocess
import sys
import time


def run(cmd: list[str]) -> str:
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"Error running {' '.join(cmd)}:\n{res.stderr}", file=sys.stderr)
        sys.exit(res.returncode)
    return res.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description="Trigger PianoGlass GitHub Release")
    parser.add_argument("--bump", choices=["patch", "minor", "major"], default="patch")
    parser.add_argument("--version", default="", help="Specific version override")
    args = parser.parse_args()

    cmd = ["gh", "workflow", "run", "build-ipa.yml", "-f", f"bump_type={args.bump}"]
    if args.version:
        cmd += ["-f", f"custom_version={args.version}"]

    print(f"Triggering GitHub Actions release workflow (bump: {args.bump})...")
    out = run(cmd)
    print(out if out else "Workflow run triggered successfully.")

    print("Waiting 5s for run to register...")
    time.sleep(5)

    runs = run(["gh", "run", "list", "--workflow=build-ipa.yml", "--limit=1"])
    print("\nLatest run:\n" + runs)
    print("\nTo watch live progress, run:")
    print("  gh run watch")


if __name__ == "__main__":
    main()
