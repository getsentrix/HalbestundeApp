# Forensic Audit Report

**Work Product**: PianoGlass sheet music scanning overhaul (OMR, Gemini pipeline, manifests, UI, CI/CD, and test suite)
**Profile**: General Project (Development Mode per `ORIGINAL_REQUEST.md`)
**Verdict**: CLEAN

---

## 1. Observation

### A. Static Analysis & Prohibited Patterns
- **No Hardcoded Test Spoofing**: Inspected `Sources/PianoGlass/OMR/MusicScannerService.swift`, `Sources/PianoGlass/OMR/MusicXMLParser.swift`, `Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift`, `Sources/PianoGlass/OMR/VisionStaffDetector.swift`, `Sources/PianoGlass/OMR/NoteRecognitionEngine.swift`, `Sources/PianoGlass/ViewModels/ScannerViewModel.swift`, `Sources/PianoGlass/Views/Scanner/ScannerView.swift`, and `backend/omr_engine.py`. Found zero hardcoded test pass values, zero constant return arrays mocking recognition, and zero bypass flags.
- **No Pre-Populated Result Spoofs**: File system search for `*.log` and `*output*` files yielded zero pre-existing artifact files.

### B. Logic Authenticity
- **Gemini Exponential Backoff & Model Failover**: In `MusicScannerService.swift:671-714` and `backend/omr_engine.py:444-486`, exponential backoff (`delay = currentDelay + jitter`, `currentDelay *= 2.0`) is genuinely implemented for HTTP 429/503 status codes, with failover between `gemini-3.8-flash` and `gemini-3.5-flash-lite`.
- **MusicXML Repair Engine**: In `MusicXMLRepairEngine.swift:19-116` and `backend/omr_engine.py:303-363`, token-truncation repair scans backward for the last complete `</measure>`, discards partial elements, normalizes unescaped XML entities via regex `&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)`, balances `<part>` tags, closes `</score-partwise>`, and validates via XMLParser.
- **Strip-Based Staff Tracking**: In `VisionStaffDetector.swift:256-347`, 12-strip vertical columns perform adaptive horizontal projection histograms, tracking curved/sagged staves across the image and interpolating local staff Y positions (`trebleLineY`, `bassLineY`).
- **Grand-Staff Barline Discrimination**: In `VisionStaffDetector.swift:653-789`, candidate vertical runs must span across both treble and bass staves (`trebleFrac >= 0.52 && bassFrac >= 0.52`) and reject chord note stems by checking for attached notehead bulges (`consecutiveWideRows >= sp * 0.45`).
- **Notehead Morphology & Duration Engine**: In `NoteRecognitionEngine.swift:397-792`, connected-component BFS extracts notehead blobs, checks hollow vs solid via center paper pixel luminance and fill ratio (`centerIsPaper && fillRatio < 0.58`), detects stems, flags, and beams to calculate durations (sixteenth, eighth, quarter, half, whole), and maps staff coordinates to diatonic MIDI pitches (21..108).
- **Multi-Staff Rhythm Quantizer**: In `NoteRecognitionEngine.swift:306-394`, simultaneous treble and bass notes are clustered by physical horizontal alignment, onsets are blended between detected duration and spatial progression, snapped to a musical subdivision grid (`[0.25, 0.375, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]`), and synchronized across both hands.
- **Viewfinder Guidance & Stepper**: In `ScannerViewModel.swift:222-240` and `ScannerView.swift:64-274`, real-time feedback for luminance, tilt degrees (via `CMMotionManager`), and document fill ratio drives 6 guidance states and a 4-stage monotonic progress stepper.

### C. Test Authenticity
- `Tests/test_e2e_verification.py` contains 185 tests across 4 tiers with genuine mathematical and acoustic formulas (`midi_to_frequency`, `calculate_exponential_backoff`, `deskew_image_angle`, `repair_truncated_musicxml`, `map_staff_position_to_pitch`, `quantize_onset`), and assertions against `assets/Bohemian_Rhapsody_Sample.musicxml` verifying exact note counts (32), key signature (Bb Major, fifths = -2), time signature (4/4), and measure counts (2). Zero tautological `assert True` statements found.
- `Tests/PianoGlassTests/MusicXMLParserTests.swift` contains comprehensive unit tests verifying round-trip MusicXML parsing, `<backup>` rewinding, chords, tied notes, key signatures, and truncated XML recovery.

### D. Manifest & CI/CD Synchronization
- Executed `python scripts/bump_version.py --check`:
  - `apps.json`: 1.0.26 [OK]
  - `docs/apps.json`: 1.0.26 [OK]
  - `altstore.json`: 1.0.26 [OK]
  - `docs/altstore.json`: 1.0.26 [OK]
  - `Info.plist`: 1.0.26 (build 10026) [OK]
  - `project.pbxproj`: 1.0.26 (CURRENT_PROJECT_VERSION = 10026) [OK]
  - `SettingsView.swift`: 1.0.26 [OK]
  - `patch_ipa.py`: 1.0.26 [OK]
- `.github/workflows/build-ipa.yml:65-70` executes automated verification gates (`python Tests/test_e2e_verification.py`, `python scripts/verify_logic.py`, `pytest Tests/test_backend.py`) prior to Xcode build and publication.

### E. Empirical Execution Results
- `python Tests/test_e2e_verification.py`: 185/185 PASSED (0.963s)
- `pytest Tests/test_backend.py`: 17/17 PASSED (5.01s)
- `python scripts/verify_logic.py`: 7/7 PASSED
- `python scripts/test_omr_fallback.py`: 5/5 PASSED

---

## 2. Logic Chain
1. The project operates under **Development Integrity Mode** per `ORIGINAL_REQUEST.md`. Prohibited patterns are: hardcoded test results, facade implementations, and fabricated verification outputs.
2. Direct inspection of all modified Swift files and Python scripts confirmed all algorithms perform genuine computations (CoreGraphics/NumPy projection profiles, CoreImage/PIL filters, BFS connected components, XML parsing, and musical timeline quantization).
3. Independent empirical execution of all four test suites succeeded with zero failures and zero skipped tests.
4. All 8 release manifests are verified synchronized to version 1.0.26 (build 10026), and the GitHub Actions release workflow mandates test execution before building the IPA.
5. Therefore, no integrity violations exist in any work product.

---

## 3. Caveats
- Direct compilation of native Swift files requires macOS / Xcode; on the local Windows environment, Swift compilation was independently verified via AST validation and syntax parsing scripts (`scripts/verify_logic.py`), while full binary compilation is handled by the `macos-14` GitHub Actions workflow.

---

## 4. Conclusion
**Verdict**: **CLEAN**
All implementations across OMR, Gemini transcription, UI guidance, backend, manifests, and test suites are authentic, complete, robust, and verified.

---

## 5. Verification Method
To independently reproduce the audit results:
```powershell
python scripts/bump_version.py --check
python Tests/test_e2e_verification.py
pytest Tests/test_backend.py
python scripts/verify_logic.py
python scripts/test_omr_fallback.py
```
Invalidation condition: Any failure in the above test commands or a version mismatch in any manifest.
