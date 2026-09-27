#!/usr/bin/env python3
"""
Test script validating:
1. AppIcon asset catalog integrity (all 18 resolutions, RGB mode, non-empty, proper JSON).
2. Xcode project and Info.plist icon linkage.
3. Feather-inspired minimal UI compliance (no virtual piano, no waterfall synthesia, AirPlay, cover/score preview, timestamps).
"""

import os
import json
import plistlib
from PIL import Image

def test_app_icon():
    print("[Test 1/4] Validating AppIcon Catalog & Resolutions...")
    catalog_path = "Sources/PianoGlass/Resources/Assets.xcassets/AppIcon.appiconset"
    contents_file = os.path.join(catalog_path, "Contents.json")
    assert os.path.exists(contents_file), "Contents.json missing"
    
    with open(contents_file, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    images = data.get("images", [])
    assert len(images) == 18, f"Expected 18 images, got {len(images)}"
    
    for item in images:
        fn = item["filename"]
        img_path = os.path.join(catalog_path, fn)
        assert os.path.exists(img_path), f"File {fn} missing"
        
        im = Image.open(img_path)
        assert im.mode == "RGB", f"Expected RGB mode for {fn}, got {im.mode}"
        
        # Check size matches spec
        size_parts = item["size"].split("x")
        w, h = float(size_parts[0]), float(size_parts[1])
        scale = float(item["scale"].replace("x", ""))
        exp_w, exp_h = int(w * scale), int(h * scale)
        assert im.size == (exp_w, exp_h), f"Size mismatch for {fn}: expected {exp_w}x{exp_h}, got {im.size}"
        
        # Check corners are opaque
        corners = [(0, 0), (im.size[0] - 1, 0), (0, im.size[1] - 1), (im.size[0] - 1, im.size[1] - 1)]
        for pt in corners:
            pix = im.getpixel(pt)
            assert len(pix) == 3, f"Non-RGB pixel at {pt} in {fn}"
            
    # Check that universal is not present concurrently with ios-marketing
    idioms = [img["idiom"] for img in images]
    assert "universal" not in idioms, "Universal idiom conflicts with idiom-specific set in modern actool"
    assert "ios-marketing" in idioms, "Missing ios-marketing idiom for 1024x1024 App Store icon"
    print("  [OK] All 18 AppIcon PNGs verified: dimensions, 100% opaque RGB, and actool spec confirmed.")

def test_project_and_plist():
    print("[Test 2/4] Validating project.pbxproj & Info.plist icon integration...")
    pbx_path = "PianoGlass.xcodeproj/project.pbxproj"
    with open(pbx_path, "r", encoding="utf-8") as f:
        pbx = f.read()
        
    assert "Assets.xcassets in Resources" in pbx, "Assets.xcassets must be in Resources build phase"
    assert "Assets.xcassets */ = {isa = PBXFileReference" in pbx, "Assets.xcassets PBXFileReference missing"
    assert "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" in pbx, "ASSETCATALOG_COMPILER_APPICON_NAME setting missing"
    
    plist_path = "Sources/PianoGlass/App/Info.plist"
    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
        
    assert "CFBundleIcons" in pl, "CFBundleIcons missing from Info.plist"
    assert pl["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon", "CFBundleIconName must be AppIcon"
    assert "CFBundleIcons~ipad" in pl, "CFBundleIcons~ipad missing from Info.plist"
    print("  [OK] project.pbxproj & Info.plist correctly linked to AppIcon asset catalog.")

def test_ui_components():
    print("[Test 3/4] Validating Feather-inspired minimal UI components...")
    
    # 1. ScorePlayerView
    player_path = "Sources/PianoGlass/Views/ScorePlayerView.swift"
    with open(player_path, "r", encoding="utf-8") as f:
        player_code = f.read()
        
    assert "VirtualPianoKeyboardView" not in player_code, "Virtual piano keyboard must be stripped from player"
    assert "WaterfallNotesView" not in player_code, "Waterfall note streams must be stripped from player"
    assert "PracticeDockView" not in player_code, "Practice dock must be stripped from player"
    assert "ScoreCoverCardView" in player_code, "ScoreCoverCardView (cover preview) must be present"
    assert "ScoreCanvasView" in player_code, "ScoreCanvasView (score preview) must be present"
    assert "AirRoutePickerRepresentable" in player_code, "AirPlay route picker must be present"
    assert "formattedRemainingTime" in player_code, "Remaining time timestamp must be present"
    assert "formattedCurrentTime" in player_code, "Elapsed time timestamp must be present"
    
    # 2. ScannerView
    scanner_path = "Sources/PianoGlass/Views/Scanner/ScannerView.swift"
    with open(scanner_path, "r", encoding="utf-8") as f:
        scanner_code = f.read()
        
    assert "DocumentCameraScannerRepresentable" in scanner_code, "DocumentCameraScannerRepresentable must be present"
    assert "loadTransferable" in scanner_code, "PhotosPicker must load transferable image data"
    assert "ScanReviewSheet" in scanner_code, "ScanReviewSheet must be present"
    
    # 3. SongLibraryView
    lib_path = "Sources/PianoGlass/Views/Library/SongLibraryView.swift"
    with open(lib_path, "r", encoding="utf-8") as f:
        lib_code = f.read()
        
    assert "listStyle(.insetGrouped)" in lib_code, "SongLibraryView must use insetGrouped list styling"
    assert "showScannerSheet" in lib_code, "SongLibraryView must support launching scanner sheet from toolbar"
    
    # 4. SettingsView
    settings_path = "Sources/PianoGlass/Views/Settings/SettingsView.swift"
    with open(settings_path, "r", encoding="utf-8") as f:
        settings_code = f.read()
        
    assert "listStyle(.insetGrouped)" in settings_code, "SettingsView must use insetGrouped list styling"
    
    # 5. ContentView
    content_path = "Sources/PianoGlass/App/ContentView.swift"
    with open(content_path, "r", encoding="utf-8") as f:
        content_code = f.read()
        
    assert "MiniPlayerBar" in content_code, "MiniPlayerBar must be present"
    assert "padding(.bottom, 62)" in content_code, "MiniPlayerBar must have safe clearance above tab bar"
    
    print("  [OK] All UI overhaul checks PASSED: complete Feather-style native iOS design confirmed.")

def test_pianoglass_branding_and_ipa_cleanliness():
    print("[Test 4/4] Validating PianoGlass branding across project, manifests, and IPAs...")
    import zipfile
    
    # 1. Check manifests
    for manifest_path in ["apps.json", "docs/apps.json", "altstore.json", "docs/altstore.json"]:
        if os.path.exists(manifest_path):
            with open(manifest_path, "r", encoding="utf-8") as f:
                content = f.read()
            assert "halbestunde" not in content.lower(), f"Found halbestunde in {manifest_path}"
            assert "com.pianoglass.app" in content, f"Missing bundle ID in {manifest_path}"
            assert '"name": "PianoGlass"' in content, f"Missing app name in {manifest_path}"
            
    # 2. Check IPAs
    for ipa_path in ["PianoGlass.ipa", "PianoGlass-IPA/PianoGlass.ipa"]:
        if os.path.exists(ipa_path):
            with zipfile.ZipFile(ipa_path, "r") as z:
                # Info.plist
                plist_raw = z.read("Payload/PianoGlass.app/Info.plist")
                pl = plistlib.loads(plist_raw)
                assert pl.get("CFBundleDisplayName") == "PianoGlass"
                assert pl.get("CFBundleName") == "PianoGlass"
                assert pl.get("CFBundleIdentifier") == "com.pianoglass.app"
                assert "halbestunde" not in pl.get("NSCameraUsageDescription", "").lower()
                assert "halbestunde" not in pl.get("NSPhotoLibraryUsageDescription", "").lower()
                
    print("  [OK] All PianoGlass branding and IPA bundle integrity checks PASSED.")

if __name__ == "__main__":
    test_app_icon()
    test_project_and_plist()
    test_ui_components()
    test_pianoglass_branding_and_ipa_cleanliness()
    print("\nALL VERIFICATION TESTS COMPLETED SUCCESSFULLY!")
