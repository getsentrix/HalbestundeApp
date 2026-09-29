## 2026-09-29T21:01:00Z
You are Worker M4 (Verification, Manifests & Release Pipeline Worker).
Your working directory: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m4
Original User Request file: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\ORIGINAL_REQUEST.md
Project Scope Document: c:\Users\dylan\Documents\antigravity\busy-hopper\PROJECT.md
Explorer Survey 3: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_3\handoff.md
Skill: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\skills\ios-developer\SKILL.md

Read ORIGINAL_REQUEST.md, PROJECT.md, and explorer_survey_3/handoff.md first.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive Write Ownership:
- apps.json, altstore.json, docs/apps.json, docs/altstore.json
- Sources/PianoGlass/App/Info.plist, PianoGlass.xcodeproj/project.pbxproj
- Sources/PianoGlass/Views/Settings/SettingsView.swift
- scripts/patch_ipa.py, scripts/bump_version.py
- .github/workflows/build-ipa.yml
- Tests/PianoGlassTests/MusicXMLParserTests.swift
Do NOT modify ScannerView.swift, ScannerViewModel.swift, or OMR Swift files.

Mission (Features F15, F16, F17):
1. F15: Sample Score Ground-Truth Verification
   - In `Tests/PianoGlassTests/MusicXMLParserTests.swift`, add automated tests for `assets/Bohemian_Rhapsody_Sample.musicxml` verifying:
     - 2 measures, 32 notes, Bb Major (fifths = -2), 4/4 meter, polyphonic grand-staff separation.
     - Malformed/truncated MusicXML recovery tests (verifying `MusicXMLRepairEngine`).
2. F16: Synchronized Manifest Version Bump
   - Bump version to `1.0.26` (build `10026`) across ALL manifest and config files:
     - `apps.json`: version "1.0.26", build "10026", update downloadURL and timestamp
     - `altstore.json`: version "1.0.26", build "10026", update downloadURL and timestamp
     - `docs/apps.json`: version "1.0.26", build "10026"
     - `docs/altstore.json`: version "1.0.26", build "10026"
     - `Sources/PianoGlass/App/Info.plist`: CFBundleShortVersionString "1.0.26", CFBundleVersion "10026"
     - `PianoGlass.xcodeproj/project.pbxproj`: MARKETING_VERSION = 1.0.26, CURRENT_PROJECT_VERSION = 10026
     - `Sources/PianoGlass/Views/Settings/SettingsView.swift`: update fallback version from stale "1.0.21" to "1.0.26"
     - `scripts/patch_ipa.py`: update hardcoded "1.0.2" to "1.0.26" / "10026"
     - `scripts/bump_version.py`: ensure it updates all above files in sync
3. F17: CI/CD Release Pipeline Hardening
   - In `.github/workflows/build-ipa.yml`:
     - Add a mandatory automated verification step before building and releasing:
       - Run `python Tests/test_e2e_verification.py`
       - Run `python scripts/verify_logic.py`
       - Run `pytest Tests/test_backend.py`
     - Ensure release branch targeting handles both `master` and `main`.
     - Update release notes to highlight Gemini multimodal AI transcription, on-device OMR fallback, and guided viewfinder.

Verification:
- Run `python scripts/bump_version.py --check` or verify manifest versions match 1.0.26
- Run `pytest Tests/test_e2e_verification.py`
- Run `python scripts/verify_logic.py`
Document commands and results in your handoff report:
c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m4\handoff.md
When done, notify caller.
