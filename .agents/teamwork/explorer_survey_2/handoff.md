# Handoff Report: Explorer 2 — On-Device OMR Overhaul (R2)

## 1. Observation

Direct examination of the On-Device OMR pipeline revealed six critical algorithmic and architectural defects across `VisionStaffDetector.swift`, `NoteRecognitionEngine.swift`, and `MusicScannerService.swift`:

1. **Un-deskewed Image Passing Bug**:
   - In `Sources/PianoGlass/OMR/MusicScannerService.swift` (lines 73-74):
     ```swift
     let (deskewedImage, _) = VisionStaffDetector.deskewCGImage(cgImage)
     let workingImage = deskewedImage
     ```
     At lines 178 and 191-196, the on-device fallback bypasses `workingImage` and passes the raw `cgImage`:
     ```swift
     let systems = await staffDetector.detectStaves(in: cgImage)
     ...
     let recognizedScore = noteEngine.recognizeScore(
         from: systems,
         image: cgImage,
         title: scoreTitle,
         composer: composer
     )
     ```
   - In `Sources/PianoGlass/OMR/VisionStaffDetector.swift` (lines 163, 223, 254):
     `detectStaves(in: cgImage)` produces `alignedImage = deskewCGImage(cgImage)`, but passes raw `cgImage` to `detectBarlines(in: cgImage, topY: topY, bottomY: bottomY, width: width)`. Staff coordinates from `alignedImage` do not align with `cgImage`.

2. **Restrictive Deskew Range & Missing Keystone Correction**:
   - In `VisionStaffDetector.swift` (lines 105-115, 129):
     Coarse loop runs `testAngle: -6.0` to `6.05` degrees. Line 129 rejects adjustments if `maxVar <= baseVar * 1.10`.
     Any phone capture tilted beyond `±6.0°` (common 8°-20° hand-held tilts) or under uneven contrast is completely uncorrected (`angle: 0.0`).
     The Vision framework (`import Vision` at line 12) is imported but never called for perspective quad/rectangle detection (`VNDetectRectanglesRequest`).

3. **Global Projection Fragility to Page Curvature and Shadows**:
   - In `VisionStaffDetector.swift` (lines 309-357):
     A single 1D row array `var profile = [Float](repeating: 0, count: height)` sums dark pixels across 70% of the image width using a single global luminance scalar `inkThreshold`.
     Page sag/curvature of 5-10 pixels across the page width smears horizontal staff lines over multiple rows, flattening the peak prominence below `threshold = medianVal + (maxVal - medianVal) * 0.18`.
     Shadows push local luminance below `inkThreshold`, saturating the profile with background noise.

4. **Note Stems Falsely Detected as Barlines**:
   - In `VisionStaffDetector.swift` (lines 454-468):
     `barlineMinFraction` is set to `0.30` (for grand staff > 100px) or `0.44` (for single staff).
     Standard note stems in piano music span 3.5 staff spaces (>85% of single staff height, or ~40% of grand staff height). Dense chords and note stems qualify as barlines, fragmenting real measures into bogus 1-beat slices.
     When fewer than 2 candidates survive, line 502 falls back to `equalBarlines(width: width)`, arbitrarily dividing the width into 4 equal segments.

5. **Staff Line Inpainting Destroys Noteheads & Missing Durations**:
   - In `NoteRecognitionEngine.swift` (lines 388-412):
     Inpainting checks `!binary[aboveOff + x] && !binary[belowOff + x]`. If a staff line is slightly curved or thick, pixels fail this check and remain in `noteheadMask`. In BFS connected components (lines 431-480), the surviving staff line joins all noteheads on that line into a single wide blob (`bw >> sp * 3.0`), which line 494 filters out, erasing all noteheads on that line.
   - In lines 569-575:
     `noteDuration` only supports whole (`4.0`), half (`2.0`), and quarter (`1.0`) notes. Zero support exists for eighth notes (`0.5`), sixteenth notes (`0.25`), dotted notes, beams, flags, or rests.

6. **Linear Spatial Timing & Multi-Staff Desynchronization**:
   - In `NoteRecognitionEngine.swift` (lines 610-616):
     Horizontal X position is mapped linearly to beats (`xFrac * 4.0`). Engraved sheet music uses non-linear duration-proportional spacing with variable margins. Notes fall on arbitrary fractions (e.g., beat 0.38, 1.15).
   - Treble and bass notes are extracted independently (lines 40-65) without joint temporal alignment, causing vertical chords between hands to split into staggered, out-of-sync events.
   - Line 85 increments `currentBeat += timeSig.beatsPerMeasure` (fixed at 4.0), so notes placed late in measure N bleed into measure N+1.

---

## 2. Logic Chain

1. **Premise**: R2 mandates robust offline OMR across phone camera angles, shadows, page curvature, accurate notehead/duration analysis, and multi-staff synchronization.
2. **Step 1 (Image Misalignment)**: Because `MusicScannerService.swift:178` and `VisionStaffDetector.swift:223` pass raw `cgImage` instead of `alignedImage`, any rotation performed by deskewing invalidates all downstream Y/X coordinates.
3. **Step 2 (Camera Angle Failure)**: Because `VisionStaffDetector.swift:105` caps deskew search to `[-6.0°, +6.0°]` and lacks perspective transformation, any phone capture taken at an angle fails to orient staff lines horizontally.
4. **Step 3 (Curvature & Shadow Breakdown)**: Because `calculateHorizontalProfile` computes a single 1D global projection with a single scalar threshold, page curvature and cast shadows flatten staff peak prominence, resulting in 0 detected staves and triggering immediate scan failure (`code: 10`).
5. **Step 4 (Rhythmic Breakdown)**: Because `NoteRecognitionEngine.swift:574` defaults all solid noteheads to 1.0 beat without analyzing beams/flags, and lines 612-616 map X linearly, recognized scores suffer from timing collapse, irregular beats, and desynchronized hands.
6. **Conclusion**: The current on-device fallback cannot satisfy R2 acceptance criteria without targeted refactoring of the preprocessor, staff segment tracker, barline validator, and multi-staff quantizer.

---

## 3. Caveats

1. **macOS/iOS Build Environment**: The current workspace host runs Windows; Swift compilation and Xcode builds execute via GitHub Actions on `macos-14`. Local verification relies on static inspection and Python algorithmic verification (`scripts/verify_logic.py`).
2. **Neural Model Independence**: This survey covers the on-device Swift fallback pipeline (R2). Remote neural OMR (`backend/omr_engine.py`) and direct Gemini AI (`transcribeWithGeminiAI`) operate independently of these Swift CV algorithms.

---

## 4. Conclusion

The on-device OMR fallback requires five bounded architectural improvements:
1. **Coordinate & Preprocessing Consistency**: Always propagate `deskewedImage` / `alignedImage` across all stages; expand deskew range to `±20.0°`; apply local adaptive binarization (Sauvola or block-level Otsu) rather than a single global threshold.
2. **Segment-Based / Strip-Based Staff Tracking**: Split the page width into vertical slices (e.g., 8-16 columns) to track curved staff lines locally and connect them into smooth polynomial/spline paths resilient to curvature.
3. **Barline Stem Discrimination**: Require barlines to span both staves of a grand staff without attached horizontal noteheads/beams, filtering out isolated note stems.
4. **Beam, Flag & Rest Detection**: Inspect vertical runs connected to stems for horizontal beams (eighth/sixteenth) and hollow centers with dots for dotted notes.
5. **Multi-Staff Beat Quantization**: Jointly sort treble and bass note events by X coordinate within each measure, cluster vertically aligned notes into simultaneous chord events, and snap to musical subdivision grids (quarter, eighth, sixteenth).

---

## 5. Verification Method

To verify these findings and check codebase structural integrity:

1. **Run algorithmic verification script**:
   ```powershell
   python scripts/verify_logic.py
   ```
   *Expected result*: Validates Swift file presence, balanced braces, pitch math (A0-C8), MusicXML multi-staff polyphony, and AudioScheduler re-triggering.

2. **Inspect critical defect lines**:
   - `Sources/PianoGlass/OMR/MusicScannerService.swift`: Lines 178, 193 (un-deskewed `cgImage` usage).
   - `Sources/PianoGlass/OMR/VisionStaffDetector.swift`: Lines 105-115 (tilt cap), 223 (un-deskewed call), 454 (stem false positive).
   - `Sources/PianoGlass/OMR/NoteRecognitionEngine.swift`: Lines 388-412 (inpainting blob merge), 574 (1.0 quarter note assumption), 612-616 (linear X mapping).

3. **Invalidation condition**:
   If an image test harness demonstrates that `cgImage` is identical to `alignedImage` when tilted, or that note stems do not trigger `columnDarkFraction >= 0.30`, this finding would be invalidated. Code inspection confirms both conditions are active bugs.
