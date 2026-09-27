#!/usr/bin/env python3
"""
scripts/bump_version.py

Automates version bumping across:
- apps.json & docs/apps.json (AltStore / LiveContainer manifest)
- Sources/PianoGlass/App/Info.plist (iOS bundle version)
- PianoGlass.xcodeproj/project.pbxproj (Xcode marketing version)
- docs/index.html & index.html (Showcase download button)

Usage:
  python scripts/bump_version.py --bump patch
  python scripts/bump_version.py --bump minor
  python scripts/bump_version.py --set-version 1.0.2
  python scripts/bump_version.py --set-size 715486
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: str, data: dict):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def parse_semver(version_str: str) -> tuple[int, int, int]:
    clean = version_str.lstrip("v").strip()
    parts = clean.split(".")
    major = int(parts[0]) if len(parts) > 0 else 1
    minor = int(parts[1]) if len(parts) > 1 else 0
    patch = int(parts[2]) if len(parts) > 2 else 0
    return major, minor, patch


def bump_semver(version_str: str, bump_type: str = "patch") -> str:
    major, minor, patch = parse_semver(version_str)
    if bump_type == "major":
        return f"{major + 1}.0.0"
    elif bump_type == "minor":
        return f"{major}.{minor + 1}.0"
    else:  # patch
        return f"{major}.{minor}.{patch + 1}"


def update_info_plist(plist_path: str, new_version: str, build_num: int):
    if not os.path.exists(plist_path):
        return
    with open(plist_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Update CFBundleShortVersionString
    content = re.sub(
        r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
        rf"\g<1>{new_version}\2",
        content,
    )
    # Update CFBundleVersion
    content = re.sub(
        r"(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)",
        rf"\g<1>{build_num}\2",
        content,
    )

    with open(plist_path, "w", encoding="utf-8") as f:
        f.write(content)


def update_pbxproj(pbxproj_path: str, new_version: str, build_num: int):
    if not os.path.exists(pbxproj_path):
        return
    with open(pbxproj_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Update MARKETING_VERSION
    content = re.sub(
        r"(MARKETING_VERSION = )[^;]+(;)",
        rf"\g<1>{new_version}\2",
        content,
    )
    # Update CURRENT_PROJECT_VERSION
    content = re.sub(
        r"(CURRENT_PROJECT_VERSION = )[^;]+(;)",
        rf"\g<1>{build_num}\2",
        content,
    )

    with open(pbxproj_path, "w", encoding="utf-8") as f:
        f.write(content)


def update_html(html_path: str, old_version: str, new_version: str):
    if not os.path.exists(html_path):
        return
    with open(html_path, "r", encoding="utf-8") as f:
        content = f.read()

    content = content.replace(
        f"/releases/download/v{old_version}/PianoGlass.ipa",
        f"/releases/download/v{new_version}/PianoGlass.ipa",
    )
    content = content.replace(
        f"Download .IPA (v{old_version})",
        f"Download .IPA (v{new_version})",
    )

    with open(html_path, "w", encoding="utf-8") as f:
        f.write(content)


def main():
    parser = argparse.ArgumentParser(description="PianoGlass Version & AltStore Updater")
    parser.add_argument("--bump", choices=["patch", "minor", "major"], default=None, help="Semver bump type")
    parser.add_argument("--set-version", default=None, help="Set exact version")
    parser.add_argument("--set-size", type=int, default=None, help="Update IPA size in bytes")
    parser.add_argument("--dry-run", action="store_true", help="Print changes without modifying files")
    args = parser.parse_args()

    apps_json_path = os.path.join(REPO_ROOT, "apps.json")
    docs_apps_json_path = os.path.join(REPO_ROOT, "docs", "apps.json")
    altstore_json_path = os.path.join(REPO_ROOT, "altstore.json")
    docs_altstore_json_path = os.path.join(REPO_ROOT, "docs", "altstore.json")
    plist_path = os.path.join(REPO_ROOT, "Sources", "PianoGlass", "App", "Info.plist")
    pbxproj_path = os.path.join(REPO_ROOT, "PianoGlass.xcodeproj", "project.pbxproj")
    docs_index_path = os.path.join(REPO_ROOT, "docs", "index.html")
    root_index_path = os.path.join(REPO_ROOT, "index.html")

    data = load_json(apps_json_path)
    current_version = data["apps"][0]["version"]

    if args.set_size is not None and args.bump is None and args.set_version is None:
        # Just update size
        if not args.dry_run:
            data["apps"][0]["size"] = args.set_size
            save_json(apps_json_path, data)
            save_json(docs_apps_json_path, data)
            if os.path.exists(altstore_json_path):
                save_json(altstore_json_path, data)
            if os.path.exists(docs_altstore_json_path):
                save_json(docs_altstore_json_path, data)
        print(f"Updated IPA size to {args.set_size} bytes.")
        return

    if args.set_version:
        new_version = args.set_version.lstrip("v").strip()
    elif args.bump:
        new_version = bump_semver(current_version, args.bump)
    else:
        new_version = current_version

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    major, minor, patch = parse_semver(new_version)
    build_num = major * 10000 + minor * 100 + patch

    print(f"Current version: {current_version}")
    print(f"Target version:  {new_version} (build {build_num})")

    if args.dry_run:
        print("Dry run complete. No files changed.")
        return

    # 1. Update apps.json & docs/apps.json
    data["apps"][0]["version"] = new_version
    data["apps"][0]["versionDate"] = now_iso
    data["apps"][0]["downloadURL"] = f"https://github.com/getsentrix/PianoGlass/releases/download/v{new_version}/PianoGlass.ipa"
    if args.set_size is not None:
        data["apps"][0]["size"] = args.set_size

    # Update release description header & news title
    desc = data["apps"][0].get("versionDescription", "")
    data["apps"][0]["versionDescription"] = re.sub(
        r"^(Release v)[0-9\.]+(.*)",
        rf"\g<1>{new_version}\2",
        desc,
        flags=re.MULTILINE,
    )
    if "news" in data and len(data["news"]) > 0:
        data["news"][0]["title"] = f"PianoGlass v{new_version} Available"
        data["news"][0]["date"] = now_iso
        data["news"][0]["identifier"] = f"pianoglass-v{new_version.replace('.', '')}-release"

    save_json(apps_json_path, data)
    save_json(docs_apps_json_path, data)
    if os.path.exists(altstore_json_path):
        save_json(altstore_json_path, data)
    if os.path.exists(docs_altstore_json_path):
        save_json(docs_altstore_json_path, data)

    # 2. Update Info.plist
    update_info_plist(plist_path, new_version, build_num)

    # 3. Update project.pbxproj
    update_pbxproj(pbxproj_path, new_version, build_num)

    # 4. Update index.html files
    update_html(docs_index_path, current_version, new_version)
    update_html(root_index_path, current_version, new_version)

    print(f"SUCCESS: Successfully bumped version to v{new_version}")

    # Output to GitHub Actions environment if running in workflow
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a", encoding="utf-8") as f:
            f.write(f"version={new_version}\n")
            f.write(f"tag=v{new_version}\n")
            f.write(f"build_num={build_num}\n")


if __name__ == "__main__":
    main()
