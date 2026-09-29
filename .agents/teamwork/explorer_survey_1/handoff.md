# Handoff Report: Gemini AI Transcription Pipeline (R1 Survey)

**Agent**: Explorer 1 (Gemini AI Pipeline Explorer)  
**Date**: 2026-09-29T20:52:00Z  
**Target Milestone**: Survey of Requirement 1 (R1)  
**Working Directory**: `c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_1`

---

## 1. Observation

Direct code observations from inspecting Swift sources, Python backend, test files, and configuration:

### 1.1 Gemini Multimodal API Calls and Model Configuration
- **Swift Direct Client (`Sources/PianoGlass/OMR/MusicScannerService.swift`)**:
  - Lines 76–114: `processImage` checks `UserDefaults.standard.string(forKey: "geminiAPIKey")`. If present, calls `transcribeWithGeminiAI`.
  - Lines 478–481: Preferred model defaults to `gemini-3.8-flash` with fallback to `gemini-3.5-flash-lite`:
    ```swift
    let preferredModel = UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-3.8-flash"
    let fallbackModel = (preferredModel == "gemini-3.8-flash") ? "gemini-3.5-flash-lite" : "gemini-3.8-flash"
    let candidateModels = [preferredModel, fallbackModel]
    ```
  - Lines 516: Endpoint is `https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)`.
  - Lines 549–553: Generation configuration:
    ```swift
    "generationConfig": [
        "temperature": 0.05,
        "maxOutputTokens": 32768
    ]
    ```
  - Missing parameter: `thinkingConfig` is omitted. In Gemini 2.5/3.x models, thinking is enabled by default and dynamically consumes output tokens against `maxOutputTokens`.
  - Safety settings: No safety setting overrides provided; false-positive blockages of complex score notation can occur without fallback visibility.
- **Python Backend (`backend/omr_engine.py` & `backend/server.py`)**:
  - `backend/omr_engine.py` lines 315–317: Uses `gemini-3.8-flash` and `gemini-3.5-flash-lite`.
  - Line 360: Python sets `"maxOutputTokens": 8192`. This is 1/4 the token limit of Swift (32768) and causes premature truncation for complex multi-measure scores.
  - Line 374: `urllib.request.urlopen(req, timeout=35)` hardcodes a 35-second timeout, which aborts long multimodal generation prematurely.

### 1.2 Image Preprocessing (Deskewing, Contrast, Lighting Normalization, Resolution)
- **Deskewing**:
  - Swift: `VisionStaffDetector.deskewCGImage` (`Sources/PianoGlass/OMR/VisionStaffDetector.swift` lines 31–159) optimizes projection profile variance on a 600px thumbnail between -6.0° and +6.0° in 0.5° coarse and 0.1° fine steps.
  - Python: `deskew_image` (`backend/omr_engine.py` lines 57–117) uses `scipy.ndimage.rotate` between -8.0° and +8.0° in 0.5° coarse and 0.1° fine steps.
  - **Critical Defect**: In `MusicScannerService.swift:processDocumentData` (lines 256–282), when a user imports a PDF or image file via document picker or Photos, `deskewCGImage` is **never called**. Only `enhanceImageForOMR` is executed.
  - **Perspective / Keystone Distortion**: Neither Swift nor Python performs quadrilateral detection, keystone correction, or perspective un-warping for camera angle tilts.
- **Lighting Normalization & Contrast**:
  - Swift: `enhanceImageForOMR` (`Sources/PianoGlass/OMR/MusicScannerService.swift` lines 642–668):
    ```swift
    colorFilter.setValue(1.25, forKey: kCIInputContrastKey)
    colorFilter.setValue(0.0,  forKey: kCIInputSaturationKey)
    colorFilter.setValue(0.05, forKey: kCIInputBrightnessKey)
    // Followed by CIUnsharpMask radius=1.5, intensity=0.7
    ```
    This applies a static contrast/brightness offset. It does not perform adaptive local thresholding, CLAHE, background illumination removal, or shadow normalization.
  - Python: `run_cloud_ai_transcription` (`backend/omr_engine.py` lines 320–328) has **zero** image enhancement: no grayscale conversion, no contrast boost, and no unsharp filter.
- **Downsampling / Upsampling**:
  - Swift: `cgImageToJPEGData` (`MusicScannerService.swift` line 444) downsamples images where `maxSide > 3000` to 3000px. It does not upsample low-resolution inputs.
  - Python: `backend/omr_engine.py` line 323 downsamples if `max(w, h) > 2048` to 2048px. 2048px is insufficient for full 6-system grand staff scores (staves become <1px).

### 1.3 Multi-Page and Multi-System Layout
- **Multi-Page Handling in Swift**:
  - `renderAllPDFPages` (`MusicScannerService.swift` lines 672–727) renders all PDF pages vertically stitched into one giant canvas at 2x scale, then passes it to `cgImageToJPEGData(maxDimension: 3000)`.
  - For a 5-page PDF, 8000px height is squashed down to 3000px (~600px per page), reducing staff lines and noteheads to illegible blurry artifacts.
  - Camera document scanner (`DocumentCameraScannerRepresentable`, `ScannerView.swift` line 450) executes:
    `let capturedImage: UIImage? = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil`
    Pages 1 through N are discarded.
- **Multi-Page Handling in Python**:
  - `transcribe_document` (`backend/omr_engine.py` lines 1134–1177) iterates each page independently and merges them using `merge_music21_scores`. However, it lacks batching, concurrency, or page-level error recovery.

### 1.4 MusicXML Extraction, Schema Validation, Sanitization, and Truncation Recovery
- **Stripping & Truncation Vulnerability**:
  - In `MusicScannerService.swift` lines 577–603:
    ```swift
    if let startTag = cleanXML.range(of: "<?xml") { cleanXML = String(cleanXML[startTag.lowerBound...]) }
    else if let startTag = cleanXML.range(of: "<score-partwise") { cleanXML = String(cleanXML[startTag.lowerBound...]) }
    if let endTag = cleanXML.range(of: "</score-partwise>", options: .backwards) {
        cleanXML = String(cleanXML[..<endTag.upperBound])
    }
    guard cleanXML.contains("<score-partwise") else { throw ... }
    let parser = MusicXMLParser()
    if var parsedScore = parser.parse(xmlString: cleanXML), !parsedScore.measures.isEmpty { ... }
    ```
  - When Gemini hits token limits (`finishReason == "MAX_TOKENS"`), the text cuts off mid-measure (e.g., `<measure number="14"><note><pitch><step>C</step>`).
  - Because `</score-partwise>` does not exist in the output, `endTag` is `nil`. The raw truncated XML string is passed to `MusicXMLParser`.
  - Apple's `XMLParser` fails with an unclosed element error and returns `nil`.
  - **Result**: The entire transcription is discarded.
- **Schema Validation & Sanitization**:
  - No MusicXML 3.1 DTD or XSD validation exists in Swift or Python.
  - No tag balancer / auto-closer exists to rescue completed measures from partial responses.
  - XML entities (`&`, `<`, `>`, `"`, `'`) in titles or lyrics are not sanitized before parsing.

### 1.5 Polyphonic Grand-Staff Handling & Parser Flaws
- In `MusicXMLParser.swift`:
  - Line 48 & 223: `currentVoice` is parsed from `<voice>` but never stored in `NoteEvent` and never used for voice cursor calculations.
  - Lines 225–235:
    ```swift
    case "backup":
        globalMeasureTicks = max(0, globalMeasureTicks - backupForwardTicks)
        for (st, cur) in staffTickCursors {
            staffTickCursors[st] = max(0, cur - backupForwardTicks)
        }
        for (st, cur) in lastStaffNoteStartTicks {
            lastStaffNoteStartTicks[st] = max(0, cur - backupForwardTicks)
        }
        lastNoteStartTicks = max(0, lastNoteStartTicks - backupForwardTicks)
        inBackup = false
    ```
    `<backup>` subtracts `backupForwardTicks` from **all** staves simultaneously. In MusicXML, `<backup>` moves the part's timeline backward to start another voice/staff. Subtracting from all staves can corrupt start ticks when staves have unequal voice durations.
  - Line 287: `let hand: Hand = (currentStaffNumber >= 2) ? .left : .right`. If `<staff>2</staff>` is omitted by Gemini, bass notes are misassigned to Right Hand (`.right`).
  - Lines 327–342: Measure duration is calculated as `max(timeSignature.beatsPerMeasure, maxEnd)`. Notes bunch at beat 0 if `<rest>` elements are omitted or `<divisions>` is miscalculated.

### 1.6 Network Error Handling, Rate Limiting, Timeouts, and Fallback Triggers
- **HTTP 429 & 503 Handling**:
  - `executeGeminiRequest` throws `NSError(code: code)` on HTTP error.
  - `transcribeWithGeminiAI` immediately tries `fallbackModel` without backoff or jitter.
  - If `fallbackModel` also fails, it immediately falls back to remote OMR or local Vision OMR.
- **Timeout**:
  - Swift has a hardcoded 90.0s timeout without intermediate progress notifications.
  - Python backend has a 35.0s timeout, causing timeouts on large scores.
- **Gemini Response Inspection**:
  - Response JSON parsing (`MusicScannerService.swift` line 567) only reads `candidates[0].content.parts[0].text`.
  - It ignores `candidates[0].finishReason` (`MAX_TOKENS`, `STOP`, `SAFETY`), `safetyRatings`, and `promptFeedback.blockReason`.

### 1.7 Acceptance Test Suite Gap
- The repository sample score `assets/Bohemian_Rhapsody_Sample.musicxml` is **never tested** in `Tests/PianoGlassTests/MusicXMLParserTests.swift` or `Tests/test_backend.py`.
- No automated test currently verifies Gemini prompt output structure, token truncation recovery, or MusicXML schema validation against `Bohemian_Rhapsody_Sample.musicxml`.

---

## 2. Logic Chain

```
[Observation 1.1, 1.4: Gemini truncation emits incomplete XML without </score-partwise>]
    │
    ▼
[Step 1: cleanXML backward search for </score-partwise> fails; passes raw unclosed XML to XMLParser]
    │
    ▼
[Step 2: XMLParser fails parse() on unclosed tags and returns nil]
    │
    ▼
[Step 3: All valid transcribed measures (e.g. 10-20 measures) are dropped; pipeline falls back to empty/generic OMR]
    │
    ▼
[Deduction: A streaming/token-aware XML repair engine that closes open tags and discards only the incomplete trailing fragment is essential for R1 compliance]

[Observation 1.2: processDocumentData skips deskewCGImage; enhanceImageForOMR uses static CIColorControls]
    │
    ▼
[Step 4: Imported phone camera photos with skew or uneven shadow are fed directly to Gemini]
    │
    ▼
[Step 5: Skewed staves and shadow regions cause Gemini OCR to misread clefs, ledger lines, and accidental signs]
    │
    ▼
[Deduction: Universal deskewing and adaptive lighting/shadow normalization must be integrated into both Swift and Python entry points]

[Observation 1.5: MusicXMLParser rewinds all staves concurrently and ignores currentVoice]
    │
    ▼
[Step 6: Complex grand-staff scores with independent voice lines (e.g. 2 voices in treble, 2 in bass) get out of sync]
    │
    ▼
[Step 7: Notes bunch at beat 0 or timing collapses across voices]
    │
    ▼
[Deduction: MusicXMLParser must track timelines per (staff, voice) tuple and handle <backup>/<forward> strictly along the part timeline]

[Observation 1.6: Immediate retry on 429 without backoff; 35s Python timeout]
    │
    ▼
[Step 8: Temporary quota spikes fail both primary and fallback models in <100ms; Python backend times out prematurely]
    │
    ▼
[Deduction: Must implement exponential backoff with jitter (1s, 2s, 4s) and unified 90s timeout]
```

---

## 3. Caveats

1. **Local Swift Compilation**: `swift` CLI is not available in the local Windows environment; verification of Swift code relies on AST syntax validation, brace balancing, and type-checking scripts (`scripts/verify_logic.py`). Full compilation is executed via GitHub Actions macOS runners (`build-ipa.yml`).
2. **Gemini API Key in Automated CI**: In automated test runs without a live `GEMINI_API_KEY`, testing of the Gemini pipeline must utilize realistic mocked API response fixtures (including clean MusicXML, token-truncated MusicXML, HTTP 429 rate limit responses, and malformed XML).
3. **No Direct Engraving CLI**: MuseScore / LilyPond binaries are not installed on the host to render MusicXML into PNGs locally; synthetic image generation via PIL is used for backend tests.

---

## 4. Conclusion

The current codebase contains the foundational scaffolding for Gemini multimodal OMR in both Swift (`MusicScannerService.swift`) and Python (`omr_engine.py`), but suffers from **six critical gaps** preventing it from fulfilling R1:

1. **Truncation & Malformed XML Fragility**: No XML sanitizer or tag repair engine. Any token truncation causes 100% loss of transcribed music.
2. **Preprocessing Inconsistencies**: Document imports bypass deskewing. Preprocessing lacks shadow removal, adaptive thresholding, and lighting normalization.
3. **Multi-Page Squashing Bug**: Multi-page PDFs in Swift are vertically stitched and downscaled to 3000px, rendering multi-page scores illegible. Document camera scanner discards pages > 0.
4. **Polyphonic Timeline & Voice Cursor Issues**: `MusicXMLParser.swift` rewinds all staves simultaneously on `<backup>` and ignores `<voice>`, risking timing collapse in complex grand-staff piano music.
5. **Network Resilience & Token Budgeting**: Lacks exponential backoff on HTTP 429/503. Python token limit (8192) and timeout (35s) are too restrictive. `thinkingConfig` is unconstrained.
6. **Missing Automated Validation**: `assets/Bohemian_Rhapsody_Sample.musicxml` is not incorporated into any automated test suite.

---

## 5. Verification Method

### 5.1 Independent Test Commands
Execute the following verification commands to validate current and future behavior:

1. **Backend Unit & Feature Tests**:
   ```powershell
   pytest Tests/test_backend.py
   ```
   *Expected*: 17 passed.

2. **App Logic, Math & Syntax Verification**:
   ```powershell
   python scripts/verify_logic.py
   ```
   *Expected*: 7/7 verification checks passed.

3. **MusicXML 3.1 Sample Integrity Test**:
   ```powershell
   python -c "import music21; s = music21.converter.parse('assets/Bohemian_Rhapsody_Sample.musicxml'); assert len(s.parts) == 2; assert len(s.flatten().pitches) == 32; print('Bohemian Rhapsody Sample: VALID')"
   ```
   *Expected*: Prints `Bohemian Rhapsody Sample: VALID`.

### 5.2 Key Files to Inspect
- `Sources/PianoGlass/OMR/MusicScannerService.swift` (lines 76–114, 256–314, 472–614, 639–727)
- `Sources/PianoGlass/OMR/MusicXMLParser.swift` (lines 113–155, 225–246, 268–355)
- `backend/omr_engine.py` (lines 300–401, 1020–1065, 1134–1177)
- `assets/Bohemian_Rhapsody_Sample.musicxml` (full reference score)
- `Tests/PianoGlassTests/MusicXMLParserTests.swift` (test suite to be expanded with Bohemian Rhapsody and malformed XML recovery tests)
