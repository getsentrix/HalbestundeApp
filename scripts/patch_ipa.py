#!/usr/bin/env python3
"""
scripts/patch_ipa.py
Updates Payload/PianoGlass.app/Info.plist inside PianoGlass.ipa and PianoGlass-IPA/PianoGlass.ipa
to eliminate all occurrences of Halbestunde, update version to 1.0.2 (10002), and patch
any embedded string literals in the executable.
"""

import os
import zipfile
import plistlib

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def patch_archive(ipa_path: str):
    print(f"Patching {ipa_path}...")
    with zipfile.ZipFile(ipa_path, "r") as zin:
        items = {}
        for item in zin.infolist():
            items[item.filename] = zin.read(item.filename)

    # 1. Update Info.plist
    plist_key = "Payload/PianoGlass.app/Info.plist"
    if plist_key in items:
        pl = plistlib.loads(items[plist_key])
        pl["CFBundleDisplayName"] = "PianoGlass"
        pl["CFBundleName"] = "PianoGlass"
        pl["CFBundleIdentifier"] = "com.pianoglass.app"
        pl["CFBundleShortVersionString"] = "1.0.27"
        pl["CFBundleVersion"] = "10027"
        pl["NSCameraUsageDescription"] = "PianoGlass requires camera access to scan piano sheet music and recognize musical notation."
        pl["NSPhotoLibraryUsageDescription"] = "PianoGlass requires photo library access to import sheet music images and PDFs for recognition."
        items[plist_key] = plistlib.dumps(pl)
        print("  [OK] Updated Info.plist in IPA")

    # 2. Update embedded strings in Mach-O binary
    bin_key = "Payload/PianoGlass.app/PianoGlass"
    if bin_key in items:
        bin_data = bytearray(items[bin_key])
        
        replacements = [
            (b"com.halbestunde.audioscheduler", b"com.pianoglass.audioscheduler\x00"),
            (b"<software>Halbestunde iOS Liquid Glass OMR</software>", b"<software>PianoGlass iOS Liquid Glass OMR</software> "),
            (b"https://github.com/getsentrix/HalbestundeApp", b"https://github.com/getsentrix/PianoGlass\x00\x00\x00\x00"),
            (b"https://getsentrix.github.io/HalbestundeApp/", b"https://getsentrix.github.io/PianoGlass/\x00\x00\x00\x00"),
        ]
        
        for old_b, new_b in replacements:
            assert len(old_b) == len(new_b)
            count = bin_data.count(old_b)
            if count > 0:
                bin_data = bytearray(bytes(bin_data).replace(old_b, new_b))
                print(f"  [OK] Replaced {count} instances of {old_b[:30]!r}")
                
        items[bin_key] = bytes(bin_data)

    # 3. Write back archive with consistent compression
    with zipfile.ZipFile(ipa_path, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for filename, data in items.items():
            zout.writestr(filename, data)

    new_size = os.path.getsize(ipa_path)
    print(f"  [OK] Wrote {ipa_path}, new size: {new_size} bytes")
    return new_size

def main():
    target_ipas = [
        os.path.join(REPO_ROOT, "PianoGlass.ipa"),
        os.path.join(REPO_ROOT, "PianoGlass-IPA", "PianoGlass.ipa"),
    ]
    new_sizes = {}
    for p in target_ipas:
        if os.path.exists(p):
            new_sizes[p] = patch_archive(p)

    return new_sizes

if __name__ == "__main__":
    main()
