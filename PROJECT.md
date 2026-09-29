# Project: PianoGlass Sheet Music Scanning System Overhaul

## Architecture
PianoGlass is a native iOS sheet music scanner, interactive reader, and audio playback engine with an offline fallback and remote AI transcription capability.

```
                      ┌────────────────────────────────────────┐
                      │              Camera / UI               │
                      │  (ScannerView, Viewfinder, ViewModel)  │
                      └──────────────────┬─────────────────────┘
                                         │
                                         ▼
                      ┌────────────────────────────────────────┐
                      │         Preprocessing & Guidance        │
                      │  (Deskew, Perspective, Lighting, CLAHE)│
                      └──────────────────┬─────────────────────┘
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   │                                           │
                   ▼ (Primary: Cloud AI)                       ▼ (Fallback: On-Device)
       ┌────────────────────────┐                  ┌────────────────────────┐
       │   Gemini AI Pipeline   │                  │   On-Device CV / OMR   │
       │ (generateContent, 429  │                  │ (Strip Staff Tracker,  │
       │  backoff, XML repair)  │                  │  Morphology Duration,  │
       └───────────┬────────────┘                  │  Beat Sync Quantizer)  │
                   │                               └───────────┬────────────┘
                   ▼                                           ▼
       ┌────────────────────────┐                  ┌────────────────────────┐
       │  MusicXML 3.1 Parser   │                  │  MusicXML Synthesizer  │
       │ (Multi-voice timeline, │                  │ (Diatonic coords,      │
       │  backup/forward sync)  │                  │  synchronized staves)  │
       └───────────┬────────────┘                  └───────────┬────────────┘
                   │                                           │
                   └─────────────────────┬─────────────────────┘
                                         │
                                         ▼
                      ┌────────────────────────────────────────┐
                      │             ParsedScore                │
                      │   (Measures, Notes, Hands, Playback)   │
                      └──────────────────┬─────────────────────┘
                                         │
                                         ▼
                      ┌────────────────────────────────────────┐
                      │            Audio / Practice            │
                      │    (AudioEngine, Sampler, Haptics)     │
                      └────────────────────────────────────────┘
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Gemini Prompt & Request Engineering | Exponential backoff on HTTP 429/503, model failover (`gemini-3.8-flash` -> `gemini-3.5-flash-lite`), `thinkingConfig` budget limits, unified timeout. | M1 | Survey R1 |
| F2 | Universal Preprocessing & Deskew | Robust ±20° rotation search, perspective quad correction, adaptive lighting normalization/CLAHE, applied universally across camera and imported documents/PDFs. | M1 | Survey R1 |
| F3 | Multi-Page & Multi-System Support | Per-page rendering without squashing multi-page PDFs to 3000px, multi-page camera capture, sequential score merging. | M1 | Survey R1 |
| F4 | Streaming XML Repair & Sanitizer | Token-aware tag repair engine to recover completed measures from truncated responses, XML entity escaping, and MusicXML 3.1 compliance. | M1 | Survey R1 |
| F5 | Polyphonic Grand-Staff MusicXML Parser | Voice timeline separation (`staff`, `voice`), correct `<backup>` rewinding on part timeline, octave/accidental preservation, zero timing collapse. | M1 | Survey R1 |
| F6 | On-Device Image Pipeline & Alignment | Always propagate `alignedImage`/`deskewedImage` across staff, barline, and notehead detection; fix coordinate mismatch bug. | M2 | Survey R2 |
| F7 | Strip-Based Staff Tracking | Segment-based vertical slicing (8-16 strips) tracking curved/sagged staff lines resilient to non-uniform lighting and shadows. | M2 | Survey R2 |
| F8 | Grand-Staff Barline Discrimination | Require barlines to span grand staff without attached noteheads/beams to eliminate chord stem false positives; sync measure boundaries. | M2 | Survey R2 |
| F9 | Notehead Morphology & Duration Engine | Solid vs hollow classification, stem/flag/beam detection for quarter, eighth, sixteenth, dotted notes, rests, and pitch mapping. | M2 | Survey R2 |
| F10 | Multi-Staff Rhythm Quantizer | Temporal clustering of simultaneous treble/bass notes, musical subdivision grid snapping (quarter, eighth, sixteenth), clean measure duration. | M2 | Survey R2 |
| F11 | Real-Time Viewfinder Guidance | Live lighting/luminance feedback, distance/fill ratio checks, and orientation tilt indicator in scanner view. | M3 | Survey R3 |
| F12 | Multi-Stage Progress Stepper | Visual 4-stage stepper (Preprocessing → AI Recognition → Score Assembly & Validation → Audio Ready) eliminating freezes. | M3 | Survey R3 |
| F13 | Diagnostic Fallback UX | Fix `pendingFallbackScore = nil` bug in `ScannerViewModel`, present actionable error diagnostics, and provide "Play Practice Score" & "Retake" actions. | M3 | Survey R3 |
| F14 | Scan Review & Confirmation Sheet | Restore reachability of `ScanReviewSheet` allowing users to preview score metadata, confidence, and playback before accepting. | M3 | Survey R3 |
| F15 | Sample Score Ground-Truth Verification | Add test score images to repository; build automated validation harness comparing parser outputs against `assets/Bohemian_Rhapsody_Sample.musicxml`. | M4 | Survey R4 |
| F16 | Synchronized Manifest Version Bump | Bump version to next release (`1.0.26`, build `10026`) across `apps.json`, `altstore.json`, `docs/apps.json`, `docs/altstore.json`, `Info.plist`, `project.pbxproj`, `SettingsView.swift`, and `scripts/patch_ipa.py`. | M4 | Survey R4 |
| F17 | CI/CD Release Pipeline Verification | Update `.github/workflows/build-ipa.yml` to run automated verification scripts prior to IPA build and release publication; correct branch push logic. | M4 | Survey R4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Gemini AI Transcription & MusicXML Pipeline | F1, F2, F3, F4, F5: Gemini request hardening, preprocessing, XML repair engine, multi-page handling, and polyphonic MusicXML parser | None | DONE (3a505d0c) |
| M2 | Overhauled On-Device Fallback OMR | F6, F7, F8, F9, F10: Aligned CV pipeline, strip staff tracker, barline discriminator, duration classifier, and multi-staff quantizer | None | DONE (ad81c715) |
| M3 | In-App UX & Guided Capture Experience | F11, F12, F13, F14: Viewfinder guidance, multi-stage progress, fallback diagnostics, and scan review sheet | M1, M2 interfaces | DONE (a4ac6968) |
| M4 | Automated Verification & Production Release | F15, F16, F17: Ground-truth test score suite, manifest version bumps, and CI/CD workflow hardening | M1, M2, M3 | DONE (8e4b4c9b) |
| M_FINAL | 100% E2E Test Pass & Adversarial Hardening | Phase 1: 100% pass of Tiers 1-4 test suite; Phase 2: Tier 5 adversarial edge-case stress hardening | M1, M2, M3, M4, TEST_READY | DONE (Iteration 2 Gate PASS) |

## Interface Contracts

### 1. Preprocessing ↔ Gemini Pipeline / OMR Fallback
- `VisionStaffDetector.deskewCGImage(_ image: CGImage) -> (image: CGImage, angle: Double)`
- `MusicScannerService.enhanceImageForOMR(_ image: CGImage) -> CGImage`
- Input: Raw `CGImage` from camera, photo library, or PDF.
- Output: Aligned `CGImage` guaranteed to have horizontal staves (skew within ±0.5°), normalized contrast, and valid dimensions.
- Rule: All downstream consumers (Gemini payload builder, staff detector, barline detector) MUST consume the aligned image.

### 2. Gemini Pipeline ↔ MusicXML Parser & Truncation Repair
- `MusicXMLRepairEngine.repairTruncatedXML(_ xml: String) -> String`
  - Scans for last complete `</measure>`.
  - Strips dangling incomplete elements (`<note>`, `<pitch>`, etc.).
  - Closes all open parent tags (`</part>`, `</score-partwise>`).
  - Ensures valid MusicXML 3.1 structure.
- `MusicXMLParser.parse(xmlString: String) -> ParsedScore?`
  - Input: Well-formed or repaired MusicXML 3.1 string.
  - Output: `ParsedScore` with populated `measures`, `notes`, `keySignature`, `timeSignature`, and non-zero duration.

### 3. On-Device Fallback OMR ↔ ParsedScore
- `VisionStaffDetector.detectStaves(in image: CGImage) async -> [StaffSystem]`
- `NoteRecognitionEngine.recognizeScore(from systems: [StaffSystem], image: CGImage, title: String, composer: String) -> ParsedScore`
  - Input: Aligned `CGImage` and detected `StaffSystem` list.
  - Output: `ParsedScore` with quantized measure divisions, synchronized treble (`.right`) and bass (`.left`) staves, and notes mapped to diatonic MIDI pitches (21..108).

### 4. ScannerViewModel ↔ UI & Diagnostic Engine
- `ScannerViewModel.ScanStatus`: `.idle`, `.preprocessing`, `.aiTranscribing(model: String)`, `.omrFallback(reason: String)`, `.validating`, `.review(ParsedScore)`, `.failure(ScanDiagnostic)`
- `ScanDiagnostic`: Struct containing `failureReason`, `staffCount`, `lightingQuality`, `apiStatus`, `suggestedAction`, and optional `fallbackScore`.

## Code Layout
- `Sources/PianoGlass/OMR/`
  - `MusicScannerService.swift`: Orchestration of Gemini AI and OMR fallback
  - `MusicXMLParser.swift`: MusicXML 3.1 parser with multi-staff voice timeline
  - `MusicXMLRepairEngine.swift`: Resilient token truncation and tag repair engine
  - `VisionStaffDetector.swift`: Perspective, deskew, and strip-based staff detection
  - `NoteRecognitionEngine.swift`: Morphology duration analysis, diatonic pitch mapping, and multi-staff beat quantizer
- `Sources/PianoGlass/ViewModels/`
  - `ScannerViewModel.swift`: Scanner state machine, progress tracking, fallback diagnostics
- `Sources/PianoGlass/Views/Scanner/`
  - `ScannerView.swift`: Viewfinder guidance, camera integration, multi-stage progress, review sheet
- `Sources/PianoGlass/Services/`
  - `RepertoireService.swift`: Score catalog loader including bundled sample scores
- `assets/`
  - `Bohemian_Rhapsody_Sample.musicxml`: Ground-truth sample score
  - Score test images (PNG/PDF)
- `Tests/`
  - `PianoGlassTests/MusicXMLParserTests.swift`: Swift test suite
  - `test_backend.py`: Python backend tests
  - `test_e2e_verification.py`: Ground-truth comparative validation script
- `.github/workflows/`
  - `build-ipa.yml`: CI/CD build, verification, and release workflow
- Root manifests: `apps.json`, `altstore.json`, `Info.plist`, `project.pbxproj`
