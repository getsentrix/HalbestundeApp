# PianoGlass E2E Test Infrastructure Specification (TEST_INFRA.md)

## 1. Test Philosophy & Principles

PianoGlass delivers high-precision sheet music scanning, AI-driven and computer-vision Optical Music Recognition (OMR), interactive visualization, and real-time audio playback on Apple platforms. Because sheet music scanning bridges continuous real-world optical artifacts with discrete, mathematically rigorous musical notation (MusicXML 3.1), the testing infrastructure follows five core tenets:

1. **Opaque-Box Verification**: Tests validate observable behaviors, contract inputs and outputs, acoustic invariants, and MusicXML schema compliance rather than private implementation details.
2. **Deterministic Ground-Truth Oracles**: Expected outputs are derived from authoritative ground-truth scores (`assets/Bohemian_Rhapsody_Sample.musicxml`, Bach BWV 846), standard MusicXML 3.1 Partwise DTD/XSD specifications, and physical pitch-frequency formulas ($f = 440 \times 2^{(d - 69)/12}$).
3. **Progressive Testability & Zero-Hardware Independence**: The E2E test suite executes deterministically in headless CI/CD environments (GitHub Actions, Linux/macOS/Windows runners) using Python 3.11+ and `pytest` without requiring physical iOS hardware, cameras, or external network connectivity.
4. **Adversarial Resilience**: Boundary tests subject every subsystem to hostile inputs (malformed XML, truncated tokens, zero-note staves, extreme tempos 10–500 BPM, severe perspective skews $\pm 25^\circ$, HTTP 429 rate-limiting, and microsecond timing collisions).
5. **Strict Release Gate**: 100% test pass rate across all tiers is mandatory before any release build or version tag publication.

---

## 2. Feature Inventory (F1 – F17)

Every feature defined in `PROJECT.md` is mapped to its operational scope, expected contract, and test criteria:

| Feature ID | Feature Name | Component / Scope | Contract & Expected Behavior | Primary Verification Target |
|:---|:---|:---|:---|:---|
| **F1** | Gemini Prompt & Request Engineering | `MusicScannerService`, `omr_engine` | Robust Gemini API calls with exponential backoff on HTTP 429/503, fallback from `gemini-3.8-flash` to `gemini-3.5-flash-lite`, `thinkingConfig` budget enforcement, and 45s unified timeout. | API retry simulation, payload schema, fallback trigger, model parameter validation. |
| **F2** | Universal Preprocessing & Deskew | `VisionStaffDetector`, `omr_engine` | Universal $\pm 20^\circ$ rotation search (Radon/Hough), perspective quad rectification, adaptive lighting normalization/CLAHE across camera frames, photo imports, and PDFs. | Deskew accuracy $\le 0.5^\circ$, contrast normalization, quad warp verification. |
| **F3** | Multi-Page & Multi-System Support | `MusicScannerService`, `server.py` | Multi-page PDF rendering at $\ge 300$ DPI without squashing aspect ratios; multi-page camera capture batching; sequential score and measure merging. | Multi-page PDF ingestion, system count continuity, measure index sequence preservation. |
| **F4** | Streaming XML Repair & Sanitizer | `MusicXMLRepairEngine`, `omr_engine` | Scans truncated XML for the last complete `</measure>`, closes parent tags (`</part>`, `</score-partwise>`), escapes unescaped `&`, `<`, `>`, and recovers valid MusicXML 3.1. | Truncated payload recovery, entity sanitization, well-formedness validation. |
| **F5** | Polyphonic Grand-Staff MusicXML Parser | `MusicXMLParser`, `omr_engine` | Multi-voice timeline separation (`staff 1` treble vs `staff 2` bass), proper `<backup>` rewinding to beat 0, chord detection (`<chord/>`), octave/accidental preservation. | Measure duration balance, zero timing collapse, voice independence, chord alignment. |
| **F6** | On-Device Image Pipeline & Alignment | `VisionStaffDetector`, `omr_engine` | Aligned and deskewed image coordinates are strictly propagated through staff, barline, and notehead detection without coordinate space desynchronization. | Coordinate transformation identity, bounding box overlap, aligned image pipeline propagation. |
| **F7** | Strip-Based Staff Tracking | `VisionStaffDetector`, `omr_engine` | Segment-based vertical slicing (8–16 strips) tracking curved, sagged, or broken staff lines resilient to shadows, page folds, and non-uniform illumination. | Segment continuity, 5-line geometry invariant, shadow resilience, curvature tolerance. |
| **F8** | Grand-Staff Barline Discrimination | `VisionStaffDetector`, `omr_engine` | Continuous vertical line detection spanning both treble and bass staves; filters out false positives from note stems, accidentals, and beams; synchronizes measure boundaries. | False-positive rejection on dense chords, cross-staff barline matching, measure sync. |
| **F9** | Notehead Morphology & Duration Engine | `NoteRecognitionEngine`, `omr_engine` | Solid vs hollow notehead classification (quarter vs half/whole), stem and flag detection (eighth, sixteenth), dotted notes, rests, and diatonic staff coordinate pitch mapping. | Duration classification accuracy, pitch mapping (A0–C8), ledger line calculations. |
| **F10** | Multi-Staff Rhythm Quantizer | `NoteRecognitionEngine`, `omr_engine` | Temporal clustering of simultaneous treble/bass notes, musical subdivision snapping (quarter, 8th, 16th, triplet), and consistent measure division calculation. | Quantization grid alignment, simultaneous note onset sync, valid measure total duration. |
| **F11** | Real-Time Viewfinder Guidance | `ScannerView`, `ScannerViewModel` | Real-time luminance analysis, document distance/fill ratio checks (target 70–95%), and camera tilt/skew orientation indicators. | Guidance state transitions (`tooDark`, `tooClose`, `tilted`, `readyToCapture`). |
| **F12** | Multi-Stage Progress Stepper | `ScannerView`, `MusicScannerService` | 4-stage UI progress pipeline: Preprocessing $\to$ AI Recognition $\to$ Score Assembly $\to$ Audio Ready with monotonic fractional updates (0.0 to 1.0). | State machine progression, timeout prevention, cancelability, progress monotonically increasing. |
| **F13** | Diagnostic Fallback UX | `ScannerViewModel` | Resilient error recovery: preserves `pendingFallbackScore`, displays actionable diagnostics (lighting, staff count, network status), and provides Practice/Retake paths. | Fallback score availability on API failure, diagnostic payload structure, user action routes. |
| **F14** | Scan Review & Confirmation Sheet | `ScannerView`, `ScanReviewSheet` | Modal sheet presenting score title, composer, confidence metric, measure count, and interactive audio preview before adding to Song Library. | Sheet state reachability, metadata binding, playback trigger, commit action. |
| **F15** | Sample Score Ground-Truth Verification | Test Harness, `assets/` | Comprehensive validation of `assets/Bohemian_Rhapsody_Sample.musicxml` against parser and synthesis outputs: 4 measures, $\text{B}\flat$ major, 4/4 time, polyphonic grand staff. | Schema compliance, note count equality, key/time signature fidelity, tempo verification. |
| **F16** | Synchronized Manifest Version Bump | Project manifests | Atomically synchronized version number (`1.0.26`, build `10026`) across `apps.json`, `altstore.json`, `docs/apps.json`, `docs/altstore.json`, `Info.plist`, `project.pbxproj`, `SettingsView.swift`, and `scripts/patch_ipa.py`. | Cross-manifest version and build string equality, release notes alignment. |
| **F17** | CI/CD Release Pipeline Verification | `.github/workflows/build-ipa.yml` | Workflow runs automated verification scripts prior to building IPA, validates branch triggers (`main`, `master`), signs package, and uploads release assets. | Workflow step sequence, runner environment, script exit-code gating, artifact configuration. |

---

## 3. Test Architecture & Tier Taxonomy

The test harness is implemented in `Tests/test_e2e_verification.py`. The suite is structured into four distinct, hierarchically rigorous tiers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   TIER 4: Real-World Application Scenarios             │
│   (Bohemian Rhapsody ground-truth, Bach Prelude, full multi-page PDF)   │
├────────────────────────────────────────────────────────────────────────┤
│                   TIER 3: Cross-Feature Combinations                   │
│      (Pairwise interactions: AI + Truncation, CV + Skew, Quantize)     │
├────────────────────────────────────────────────────────────────────────┤
│                   TIER 2: Boundary & Corner Cases                      │
│   (Empty inputs, zero notes, extreme BPM, malformed XML, HTTP 429)     │
├────────────────────────────────────────────────────────────────────────┤
│                   TIER 1: Feature Coverage (F1 – F17)                  │
│       (>=5 isolated test cases per feature across F1 through F17)      │
└────────────────────────────────────────────────────────────────────────┘
```

### Tier 1: Feature Coverage (F1 – F17)
- **Criterion**: Minimum 5 dedicated test cases per feature (17 features $\times \ge 5 = \ge 85$ tests).
- **Scope**: Verifies individual feature mechanics in isolation against known mathematical, musical, and structural contracts.
- **Coverage**:
  - `F1_01` to `F1_05`: Backoff retry delays, 429 status response, model failover parameter, thinking budget clamp, 45s timeout ceiling.
  - `F2_01` to `F2_05`: $\pm 15^\circ$ rotation deskew, horizontal line orientation, CLAHE histogram stretch, aspect ratio preservation, perspective quadrilateral warp.
  - `F3_01` to `F3_05`: Multi-page PDF page extraction, per-page rendering resolution ($\ge 300\text{ DPI}$), score concatenation, measure number re-indexing, system-break metadata.
  - `F4_01` to `F4_05`: Unclosed `<score-partwise>` closure, truncated `<note>` discard, entity replacement (`&` $\to$ `&amp;`), nested tag balancing, valid XML header emission.
  - `F5_01` to `F5_05`: Two-staff grand staff allocation, `<backup>` duration match, `<chord>` onset synchronization, accidental alteration mapping (`<alter>-1`), pitch step octave validation.
  - `F6_01` to `F6_05`: Preprocessed image matrix propagation, ROI bounding box affine transform, pixel coordinate identity, resolution consistency, channel format normalization.
  - `F7_01` to `F7_05`: 12-strip vertical slice line tracking, staff line curvature polynomial fit, shadow gradient thresholding, 5-line spacing equality, staff gap consistency.
  - `F8_01` to `F8_05`: Grand staff barline span ($y_{\text{bass\_bot}} - y_{\text{treble\_top}}$), note stem exclusion by width/aspect ratio, beam exclusion by angle, measure boundary slicing, final double-barline detection.
  - `F9_01` to `F9_05`: Filled ellipse vs open ellipse duration classification, vertical stem direction and flag detection, dotted duration multiplier ($1.5\times$), rest symbol identification, staff line-to-pitch formula.
  - `F10_01` to `F10_05`: 16th note subdivision grid quantization, simultaneous onset clustering ($\Delta t < 25\text{ms}$), measure duration normalization, triplet handling, beat division consistency.
  - `F11_01` to `F11_05`: Low luminance trigger (`lightingQuality == .poor`), high tilt angle warning ($>12^\circ$), fill ratio bounds ($0.70 \le r \le 0.95$), ready state transition, distance guidance.
  - `F12_01` to `F12_05`: State machine sequential transition (1 $\to$ 2 $\to$ 3 $\to$ 4), progress fraction monotonicity, error state termination, state descriptions, cancellation handling.
  - `F13_01` to `F13_05`: Pending fallback score non-null persistence, diagnostic error string formatting, retake action reset, practice score bypass route, network error diagnostic categorization.
  - `F14_01` to `F14_05`: Modal presentation trigger, metadata display (title/composer/measure count), confidence score percentage formatting, audio preview playback dispatch, confirmation commit action.
  - `F15_01` to `F15_05`: Ground-truth score load, measure count validation ($M=2$), key signature verification ($\text{B}\flat$ major, fifths $=-2$), time signature verification ($4/4$), polyphonic note count verification ($N=32$).
  - `F16_01` to `F16_05`: `apps.json` version string, `altstore.json` version string, `Info.plist` CFBundleShortVersionString, `project.pbxproj` MARKETING_VERSION, version consistency cross-check.
  - `F17_01` to `F17_05`: Workflow YAML syntax validity, step ordering (verify logic $\to$ test suite $\to$ build), release branch trigger filters, artifact upload path verification, environment variable configuration.

### Tier 2: Boundary & Corner Cases
- **Criterion**: Minimum 5 boundary/corner test cases per feature group.
- **Scope**: Tests behavior under extreme, pathological, or degenerate operational conditions.
- **Scenarios Tested**:
  1. Empty and zero-byte file inputs (zero-byte image, empty PDF, zero-length XML string).
  2. Extreme tempos ($10\text{ BPM}$ largo to $500\text{ BPM}$ prestissimo) and unusual time signatures ($7/8$, $12/8$, $5/4$, $1/4$).
  3. Degenerate scores: staves with zero notes (all rests), single-note measures, massive 12-note clusters.
  4. Extreme optical angles: image tilted $\pm 25^\circ$, aspect ratio 10:1 strip, $16\text{K}\times 16\text{K}$ high-res image, $50\times 50$ micro-image.
  5. Severe XML truncation: cut off halfway through an attribute string (`<step a="`), truncated inside CDATA, missing closing root tag.
  6. Network adversity: simulated HTTP 429 Too Many Requests with `Retry-After: 60`, HTTP 503 Service Unavailable, malformed JSON response from AI endpoint.

### Tier 3: Cross-Feature Combinations (Pairwise Interactions)
- **Criterion**: Verifies complex interoperability between features across subsystem boundaries.
- **Scenarios Tested**:
  1. `F1 + F4`: Gemini AI response streaming truncation followed by streaming XML repair and MusicXML parsing.
  2. `F2 + F6 + F7`: Camera skew rectification combined with strip staff tracking on non-uniform shadow gradient.
  3. `F5 + F10`: Polyphonic grand-staff parsing coupled with rhythm quantizer grid alignment.
  4. `F1 + F13`: Gemini network rate-limit (HTTP 429) failover triggering diagnostic fallback UX and on-device synthesis.
  5. `F3 + F15`: Multi-page PDF splitting combined with ground-truth score measure continuity.
  6. `F8 + F9 + F10`: Barline detection isolating dense chord clusters, note duration classification, and simultaneous onset quantization.

### Tier 4: Real-World Application Scenarios
- **Criterion**: Full end-to-end user workflows with realistic assets.
- **Scenarios Tested**:
  1. **Bohemian Rhapsody Intro Ground-Truth Validation**: Complete parse, structural audit, acoustic frequency mapping, and MIDI synthesis of Queen's *Bohemian Rhapsody* intro (`assets/Bohemian_Rhapsody_Sample.musicxml`).
  2. **J.S. Bach Prelude in C Major (BWV 846)**: End-to-end synthesis, arpeggiated polyphony timing, 34 measures, multi-voice timeline validation.
  3. **High-Resolution Multi-System Camera Capture**: Simulated 4-system grand staff score image with lighting variance and staff curvature, validated through deskew $\to$ staff detection $\to$ note recognition $\to$ MusicXML output.
  4. **Multi-Page Sheet Music Document**: 2-page document import, per-page transcription, sequential score assembly, measure numbering audit ($1 \dots N$), and MIDI export round-trip.
  5. **Complete Production Release Gate**: Simultaneous audit of all project manifests, CI/CD workflow configuration, Swift syntax balance, and 100% test execution pass.

---

## 4. Real-World Application Scenarios & Acceptance Criteria

| Scenario | Input Asset | Execution Path | Expected Outcome |
|:---|:---|:---|:---|
| **A. Bohemian Rhapsody Intro** | `assets/Bohemian_Rhapsody_Sample.musicxml` | MusicXML Parser $\to$ Polyphonic Timeline $\to$ Audio Engine frequency synthesis | Parsed cleanly with 0 schema errors; exactly 2 measures; key signature $\text{B}\flat$ major (fifths = -2); 4/4 meter; 32 total notes; proper RH/LH synchronization. |
| **B. Bach Prelude BWV 846** | Synthetic / Backend Sample | OMR Engine $\to$ MusicXML $\to$ MIDI binary synthesis | 34 measures; 544 note events; continuous arpeggiation; valid MIDI file (`MThd` header, track chunk `MTrk`). |
| **C. Mobile Camera Photo Capture** | Skewed, shadowed score image ($15^\circ$) | Preprocessing CLAHE $\to$ Deskew $\to$ Strip Staff Tracker $\to$ Barline & Notehead Engine | Deskewed to $<0.5^\circ$; 5-line staff systems accurately detected; measure boundaries aligned across grand staff. |
| **D. Cloud Rate-Limit & Fallback** | Gemini request with HTTP 429 injection | Gemini client backoff $\to$ Failover $\to$ Diagnostic Fallback Engine | Graceful retry, failover to secondary model; on persistent failure, triggers `pendingFallbackScore` with diagnostic feedback. |
| **E. Production Release Readiness** | Manifests & CI/CD workflow | Automated E2E verification suite $\to$ Manifest version cross-audit | 100% test pass rate; synchronized version `1.0.26` across all 8 manifest targets; release workflow executable. |

---

## 5. Coverage Thresholds & Quality Gates

To guarantee enterprise-grade stability and zero regression, the test suite enforces the following quantitative thresholds:

1. **Test Pass Rate**: $100.0\%$ (zero allowed failures, zero allowed errors).
2. **Feature Coverage**: $100\%$ of features F1 through F17 must have $\ge 5$ passing test cases.
3. **MusicXML Schema Validity**: $100\%$ of generated or repaired MusicXML documents must parse without unhandled XML syntax exceptions.
4. **Timing & Polyphony Accuracy**: In all grand-staff measures, RH (staff 1) and LH (staff 2) cumulative durations must balance within $\pm 0.001$ beats.
5. **Pitch Domain Invariant**: All recognized notes must map strictly to valid MIDI pitches $21 \le p \le 108$ (A0 to C8).
6. **Manifest Synchronization**: $100\%$ match of version and build number across `apps.json`, `altstore.json`, `docs/apps.json`, `docs/altstore.json`, `Info.plist`, `project.pbxproj`, `SettingsView.swift`, and `scripts/patch_ipa.py`.
