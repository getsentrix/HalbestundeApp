# Handoff Report: R3 (UX & Guided Capture) and R4 (Verification & Release) Codebase Survey

**Report Path**: `c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_3\handoff.md`  
**Survey Date**: 2026-09-29  
**Surveyor**: Explorer 3 (UI/UX & Release Explorer)  
**Parent Agent**: `dea9cb97-0f25-4381-8a56-d33c704f29ed`

---

## 1. Observation

### R3 Observations (Scanner UX, Viewfinder, Progress, Fallback)

1. **Static Viewfinder Without Real-Time Guidance**:
   - `Sources/PianoGlass/Views/Scanner/ScannerView.swift` lines 58–71, 116–135:
     ```swift
     ZStack {
         RoundedRectangle(cornerRadius: 20, style: .continuous)
             .fill(Color(.secondarySystemBackground))
             .overlay(...)
             .overlay(
                 ViewfinderCornerBrackets()
                     .stroke(Color.accentColor, lineWidth: 2.5)
                     .padding(20)
             )
         ...
         Image(systemName: "doc.viewfinder")
         Text("Sheet Music Viewfinder")
         Text("Scan printed notation or import MusicXML & photos")
     }
     ```
     The viewfinder frame is purely a decorative placeholder with corner brackets and static SF Symbols. It does NOT host an active `AVCaptureSession` or camera preview layer.
   - `ScannerView.swift` lines 143–152 & 415–467:
     Tapping "Scan Sheet Music" launches `VNDocumentCameraViewController` (`DocumentCameraScannerRepresentable`) inside a full-screen sheet. This native Apple controller provides rectangular border detection, but has **zero sheet-music-specific guidance** for:
     - **Lighting**: No exposure/lux meter or glare/shadow warning.
     - **Distance**: No frame fill ratio checks or "Move Closer / Farther" prompts.
     - **Orientation / Tilt**: No CoreMotion accelerometer/gyroscope integration to level the phone over the page.

2. **Jumpy, Non-Stepped Recognition Progress Feedback**:
   - `Sources/PianoGlass/OMR/MusicScannerService.swift` lines 83–86:
     ```swift
     await updateState(.enhancingContrast, progress: 0.20)
     await updateState(.detectingStaffSystems, progress: 0.40)
     await updateState(.recognizingNotesAndClefs, progress: 0.70)
     if let score = try await transcribeWithGeminiAI(...)
     ```
     During Gemini transcription (the primary engine), states jump sequentially in <1ms, then stall at `0.70` ("Recognizing noteheads, pitches & clefs...") for 10–30s during the network call.
   - `Sources/PianoGlass/Views/Scanner/ScannerView.swift` lines 94–115:
     ```swift
     ProgressView(value: max(0.05, viewModel.progressFraction))
         .progressViewStyle(.linear)
     Text("\(Int(viewModel.progressFraction * 100))%")
     Text(viewModel.statusMessage)
     ```
     Progress feedback is a single linear bar with a raw percentage and text line. There is no multi-stage visual stepper (e.g. Stage 1: Preprocess → Stage 2: Gemini AI Analysis → Stage 3: MusicXML Validation → Stage 4: Playable Audio Synthesis).

3. **Broken Fallback Path & Opaque Diagnostics on Failure**:
   - `Sources/PianoGlass/ViewModels/ScannerViewModel.swift` lines 121–130:
     ```swift
     case .failure(let error):
         self.isProcessing = false
         self.currentStep = .camera
         self.progressFraction = 0.0
         self.statusMessage = "Scan failed"
         self.errorMessage = "Could not recognize notation in this scan: \(error.localizedDescription)\n\nPlease ensure the sheet music is flat, well-lit, and fills the viewfinder."
         self.pendingFallbackScore = nil
         self.showErrorAlert = true
     ```
   - `Sources/PianoGlass/Views/Scanner/ScannerView.swift` lines 287–296:
     ```swift
     .alert("Scan & Import Notice", isPresented: $viewModel.showErrorAlert) {
         if let fallback = viewModel.pendingFallbackScore {
             Button("Play Practice Score") {
                 viewModel.acceptFallbackScore(fallback)
             }
         }
         Button("OK", role: .cancel) {}
     } message: {
         Text(viewModel.errorMessage)
     }
     ```
     **Defect**: Line 127 in `ScannerViewModel.swift` sets `self.pendingFallbackScore = nil`. As a result, the "Play Practice Score" button is NEVER rendered on scan failure; only an "OK" button appears.
   - **Diagnostics**: Only `error.localizedDescription` is shown. There are no structured diagnostics indicating whether staff lines were detected (count = 0), if Gemini failed (HTTP 401/403/429/timeout), or whether the image was skewed/blurry, nor is there a direct "Retake" button.

4. **Unreachable Scan Review Sheet**:
   - `ScannerView.swift` lines 332–412: `ScanReviewSheet` contains metadata summary (Title, Composer, Key, Time Sig, Measures, Notes, Confidence) and Accept/Retake actions.
   - `ScannerViewModel.swift` line 108: `self.currentStep = .review(scanResult)`.
   - `ScannerView.swift` lines 57–139: The body only branches on `if viewModel.isProcessing`. There is no `.sheet(isPresented:)` or branch for `.review`. Successful scans immediately auto-advance to `onScoreAccepted` after 0.75s, rendering `ScanReviewSheet` completely unreachable dead code.

---

### R4 Observations (Verification, Manifests, Release Workflow)

1. **Missing Test Images & Disconnected Sample Score**:
   - `assets/Bohemian_Rhapsody_Sample.musicxml`:
     Exists in `assets/` (433 lines, 2 measures, 32 notes, key = Bb Major / fifths -2, time = 4/4, divisions = 1).
     - Grep across `Sources/` and `Tests/` found **zero references** to `Bohemian_Rhapsody_Sample`.
     - `Sources/PianoGlass/Services/RepertoireService.swift` line 16: `loadCatalog()` returns `[]` (empty array).
     - No test in `Tests/PianoGlassTests/` or `Tests/test_backend.py` parses `Bohemian_Rhapsody_Sample.musicxml`.
   - **Sample Images**:
     Directory search across the repository returned only `assets/app-icon.png` and `assets/app-icon.svg`. There are **zero test score images** (scans, photos, or digital sheet music) stored in `assets/` or `Tests/`.

2. **Existing Automated Verification Status**:
   - `pytest Tests/test_backend.py`: Executed successfully (17 passed in 6.66s). Tests backend FastAPI endpoints and synthetic Pillow drawings, but no real sheet music images.
   - `python scripts/verify_logic.py`: Executed successfully (7/7 suites passed). Tests Swift file existence, bracket balance, pitch formulas, and mocked timeline algorithms.
   - `python scripts/test_ui_and_icon.py`: Executed successfully (4/4 tests passed). Validates AppIcon resolutions and presence of UI strings.
   - **Gap**: No automated test verifies end-to-end transcription of `Bohemian_Rhapsody_Sample.musicxml` or test score images against expected MusicXML models.

3. **Version Manifest Alignment & Discrepancies**:
   - Current manifest versions:
     - `apps.json`: `1.0.25` (build 10025, size 864054, date 2026-09-28T20:42:58Z)
     - `altstore.json`: `1.0.25`
     - `docs/apps.json`: `1.0.25`
     - `docs/altstore.json`: `1.0.25`
     - `Sources/PianoGlass/App/Info.plist`: `1.0.25` (CFBundleVersion 10025)
     - `PianoGlass.xcodeproj/project.pbxproj`: `MARKETING_VERSION = 1.0.25; CURRENT_PROJECT_VERSION = 10025;` (Debug & Release)
     - `docs/index.html` & `index.html`: `v1.0.25`
   - **Discrepancies**:
     - `Sources/PianoGlass/Views/Settings/SettingsView.swift` line 231:
       `Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.21")")`
       Fallback string is hardcoded to stale `"1.0.21"`.
     - `scripts/patch_ipa.py` lines 29–30:
       `pl["CFBundleShortVersionString"] = "1.0.2"`
       `pl["CFBundleVersion"] = "10002"`
       Hardcoded to `1.0.2`, which downgrades versions if executed.
     - Root `PianoGlass.ipa` file size: `716904` bytes locally, whereas `apps.json` specifies `864054` bytes (recorded by CI runner).

4. **GitHub Actions Workflow (`.github/workflows/build-ipa.yml`)**:
   - Runner: `macos-14`, selecting `/Applications/Xcode_15.4.app`.
   - Release creation: `gh release create "$TAG" build/PianoGlass.ipa`.
   - Manifest commit: `git commit -m "chore(release): bump version to $TAG [skip ci]"` -> `git push origin master`.
   - **Critical Gaps**:
     - **No Automated Tests in CI**: The workflow archives and releases the IPA without executing `swift test`, `verify_logic.py`, or `pytest`.
     - **Hardcoded Branch Push**: Line 125 pushes to `origin master`, which breaks if working on `main`.
     - **Push Trigger Overuse**: Any push to `master` with source changes automatically triggers a patch version bump and release.
     - **Static Release Notes**: Lines 98–102 hardcode generic text from earlier versions without mentioning Gemini AI or OMR capabilities.

---

## 2. Logic Chain

1. **R3 Viewfinder Guidance**:
   - *Observation*: `ScannerView.swift` has a static frame; `VNDocumentCameraViewController` provides generic document cropping only.
   - *Reasoning*: Sheet music OMR requires horizontal alignment (low tilt), adequate lighting (contrast of thin lines), and appropriate camera distance (so staff systems span the frame). Without real-time guidance, users capture angled, shadowed, or distant images that cause OCR/OMR failure.
   - *Inference*: The scanner interface needs an active camera capture session with real-time analysis (luminance for lighting, CoreMotion or Vision bounding ratio for tilt/distance) or guided visual prompts before capturing.

2. **R3 Recognition Feedback**:
   - *Observation*: States jump immediately to 70% and freeze during network requests; progress bar is a single line.
   - *Reasoning*: Multi-tier OMR (Gemini AI -> Remote OMR -> On-device OMR) involves distinct phases: Preprocessing -> Network/Vision Analysis -> MusicXML Validation -> Audio Generation. Freezing at 70% makes the app appear unresponsive.
   - *Inference*: A structured multi-stage progress component reflecting actual pipeline stages (Preprocessing, AI Recognition, Score Assembly, Verification) is needed to give users clarity on progress and current engine tier.

3. **R3 Fallback & Diagnostics**:
   - *Observation*: `pendingFallbackScore` is set to `nil` on error; `errorMessage` is generic; `ScanReviewSheet` is bypassed.
   - *Reasoning*: When recognition fails, users are trapped with an "OK" dialog that resets the camera. They cannot see why it failed (no staff lines vs. API timeout) or immediately play a sample score or retake with guidance.
   - *Inference*: The failure state must set `pendingFallbackScore` (or a known practice score), provide diagnostic insights (lighting, staff count, API code), and provide direct action buttons: "Retake Scan", "Play Practice Score", and "View Details".

4. **R4 Sample Score & End-to-End Testing**:
   - *Observation*: `assets/Bohemian_Rhapsody_Sample.musicxml` is unreferenced in tests/catalog; zero sample score images exist.
   - *Reasoning*: Requirement 4 mandates programmatic verification comparing recognized output against ground-truth MusicXML scores. Without sample images and automated test scripts comparing parser output to `Bohemian_Rhapsody_Sample.musicxml`, regression detection is impossible.
   - *Inference*: Add sample score images (PNG/PDF) to `assets/`, load `Bohemian_Rhapsody_Sample.musicxml` into automated test suites, and write an end-to-end verification script comparing measures, notes, and accidentals.

5. **R4 CI/CD Production Release**:
   - *Observation*: `.github/workflows/build-ipa.yml` builds directly without running verification scripts; `scripts/bump_version.py` misses `SettingsView.swift` and `scripts/patch_ipa.py`.
   - *Reasoning*: Releasing an IPA without automated test validation risks deploying regressions. Outdated fallback strings lead to version mismatch in settings.
   - *Inference*: Add a verification step to `.github/workflows/build-ipa.yml` before the archive step, update `bump_version.py` to synchronize all files, and update release notes generation.

---

## 3. Caveats

1. **macOS / Xcode Execution Environment**:
   - The current environment is Windows PowerShell. Native Xcode compilation (`xcodebuild`) and Swift test runner (`swift test`) cannot be executed locally and must be validated via GitHub Actions macOS runners (`macos-14`).
2. **Apple VisionKit Device Constraints**:
   - `VNDocumentCameraViewController` requires physical iOS hardware with camera support; on Simulator or non-iOS platforms, `isSupported` evaluates to false.
3. **Gemini API Live Calls**:
   - Cloud AI transcription requires a valid `GEMINI_API_KEY`. Verification scripts in automated environments must test both authenticated responses and mock/fallback offline behavior.

---

## 4. Conclusion

The PianoGlass codebase possesses clean architectural foundations (SwiftUI Liquid Glass theme, modular OMR service, comprehensive audio engine, and working GitHub release workflow), but has critical gaps against R3 and R4:

### R3 Gaps
1. **Viewfinder Guidance**: Static placeholder viewfinder; no real-time feedback for lighting, distance, or camera tilt/orientation.
2. **Recognition Progress**: Linear progress bar freezes at 70% during Gemini network calls; lacks multi-stage visual stepper for pipeline phases.
3. **Fallback & Diagnostics Defect**: `pendingFallbackScore` is cleared to `nil` on failure, preventing the "Play Practice Score" button from appearing; diagnostics lack actionable error reasons.
4. **Dead Review Sheet**: `ScanReviewSheet` is completely unreachable; user cannot review score details before playback starts.

### R4 Gaps
1. **Sample Scores & Images**: `assets/Bohemian_Rhapsody_Sample.musicxml` is completely unreferenced by tests or the app catalog; zero test score images exist in the repository.
2. **Automated Verification**: No test validates end-to-end transcription against `Bohemian_Rhapsody_Sample.musicxml` or verifies MusicXML 3.1 schema compliance.
3. **Manifest Inconsistencies**: `SettingsView.swift` hardcodes `"1.0.21"`; `patch_ipa.py` hardcodes `"1.0.2"`.
4. **CI Workflow Missing Verification**: `.github/workflows/build-ipa.yml` produces and publishes IPAs without running test suites.

---

## 5. Verification Method

1. **Verify Backend Tests**:
   ```powershell
   pytest Tests/test_backend.py
   ```
   *Expected*: 17 passed.
2. **Verify Python Deep Verification**:
   ```powershell
   python scripts/verify_logic.py
   ```
   *Expected*: 7/7 suites pass.
3. **Verify UI & Icon Tests**:
   ```powershell
   python scripts/test_ui_and_icon.py
   ```
   *Expected*: 4/4 suites pass.
4. **Inspect Manifest Versions**:
   ```powershell
   python -c "import json; print('apps.json:', json.load(open('apps.json'))['apps'][0]['version']); print('altstore.json:', json.load(open('altstore.json'))['apps'][0]['version'])"
   ```
   *Expected*: Matches current release tag `1.0.25`.
5. **Inspect Fallback Button Bug**:
   View `Sources/PianoGlass/ViewModels/ScannerViewModel.swift` lines 121–130 and `Sources/PianoGlass/Views/Scanner/ScannerView.swift` lines 287–296 to verify `pendingFallbackScore = nil`.
