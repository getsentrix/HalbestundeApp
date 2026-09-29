# Adversarial Review & Empirical Challenge Report (OMR & MusicXML)

**Agent**: Challenger 1 (OMR & MusicXML Adversarial Challenger)  
**Date**: 2026-09-29T21:16:00Z  
**Verdict**: **REQUEST_CHANGES**  

---

## 1. Observation

Adversarial stress testing was conducted against the OMR and MusicXML pipelines using the executable test harness:
`python .agents/teamwork/challenger_1/adversarial_omr_musicxml_stress.py`

### Test Execution Summary
```
================================================================================
STARTING ADVERSARIAL STRESS TEST SUITE (OMR & MusicXML)
================================================================================

[Challenge 1] Testing MusicXML Truncation & Token Exhaustion...
  --- Subtest 1A: Truncated XML with Complete Envelope Header (<part-list>) ---
    PASS | Mid-tag truncation: valid=True, measures=1
    PASS | Mid-note truncation: valid=True, measures=1
    PASS | Mid-measure truncation: valid=True, measures=1
    PASS | Nested chord tags truncation: valid=True, measures=1
    PASS | Unclosed part tag: valid=True, measures=1
  --- Subtest 1B: Adversarial Truncation (Omits part-list or cut in measure 1) ---
    VULNERABILITY DETECTED | Adversarial: Omitted <part-list> with <part id='P1'>: valid=False, error=mismatched tag: line 8, column 2
    VULNERABILITY DETECTED | Adversarial: Truncated inside measure 1 (no complete measure): valid=False, error=mismatched tag: line 6, column 6

[Challenge 2] Testing Entity Corruption & Naked Ampersands...
  PASS | Naked ampersand in lyrics: valid=True, double_escaped=False
  PASS | Ampersand in composer credit: valid=True, double_escaped=False
  PASS | Multiple consecutive ampersands: valid=True, double_escaped=False
  PASS | Legitimate entity preservation: valid=True, double_escaped=False
  PASS | Numeric character entities: valid=True, double_escaped=False

[Challenge 3] Testing Polyphonic Grand-Staff Multi-Voice Timing...
  Voice 1 (Staff 1, 4 quarters): onsets=[0.0, 1.0, 2.0, 3.0] -> PASS
  Voice 2 (Staff 1, 2 halves):   onsets=[0.0, 2.0] -> PASS
  Voice 3 (Staff 2, 1 whole):    onsets=[0.0] -> PASS
  Voice 4 (Staff 2, 8 eighths):  onsets=[0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5] -> PASS
  Collapsed to beat 0 check:    collapsed=False -> PASS

[Challenge 4] Testing Extreme Skew & Tilt Detection (±15°, ±20°)...
  PASS | Target: -20.0° -> Detected: -20.00° (Error: 0.00°)
  PASS | Target: -15.0° -> Detected: -15.00° (Error: 0.00°)
  PASS | Target: +15.0° -> Detected: +15.00° (Error: 0.00°)
  PASS | Target: +20.0° -> Detected: +20.00° (Error: 0.00°)

[Challenge 5] Testing Strip Staff Tracker Under Severe Shadows...
  Strip Tracker: 12/12 strips resolved all 5 staff lines across gradient -> PASS

[Challenge 6] Testing Chord Note Stems vs Grand-Staff Barlines...
  Grand-Staff True Barlines (100, 500, 900): [100, 500, 900] -> PASS
  Notehead Bulge Detection with Swift 1.25x Multiplier: 0 rejections (Noteheads failed to meet 1.25x spacing threshold) -> VULNERABILITY CONFIRMED
  Single-Staff False Positive Barline at Chord Stem (X=258): detected=[248] -> VULNERABILITY CONFIRMED (Stem flagged as barline in single staff)
  Hardened 1.0x Multiplier Bulge Detection: 32 rejections -> PASS
```

### Specific Vulnerabilities Observed in Source Code

#### Finding 1: `Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift` (Lines 68–75)
```swift
// 5. Ensure <part-list> and <part id="P1"> exist before measures
if !text.contains("<part-list>") && text.contains("<measure") {
    if let firstMeasure = text.range(of: "<measure") {
        let prefix = text[..<firstMeasure.lowerBound]
        let suffix = text[firstMeasure.lowerBound...]
        text = "\(prefix)\n  <part-list>\n    <score-part id=\"P1\"><part-name>Piano</part-name></score-part>\n  </part-list>\n  <part id=\"P1\">\n\(suffix)"
    }
}
```
When an incoming multimodal response contains `<score-partwise><part id="P1"><measure...` without `<part-list>`, `prefix` contains `<score-partwise><part id="P1">`. Line 73 inserts another `<part id="P1">`, creating duplicate unclosed nested part tags and placing `<part-list>` inside `<part>`. This results in an immediate XML parsing error:
`mismatched tag: line 8, column 2`.

#### Finding 2: `Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift` (Lines 86–98)
```swift
guard let lastMeasureEnd = text.range(of: "</measure>", options: .backwards) else {
    // If not even a single measure completed, attempt to close measure 1 if opened
    if text.contains("<measure") {
        // Strip dangling partial tags like <note... or <pitch...
        if let lastOpenTag = text.range(of: "<", options: .backwards) {
            if !text[lastOpenTag.lowerBound...].contains(">") {
                text = String(text[..<lastOpenTag.lowerBound])
            }
        }
        text += "\n    </measure>\n  </part>\n</score-partwise>"
        return text
    }
    return ""
}
```
When response truncation occurs inside Measure 1 (zero completed measures), line 94 strips only the final open `<tag...` and appends `</measure></part></score-partwise>`, leaving open inner tags (`<note>`, `<pitch>`) unclosed. This produces invalid XML:
`mismatched tag: line 6, column 6`.

#### Finding 3: `Sources/PianoGlass/OMR/VisionStaffDetector.swift` (Lines 724–738)
```swift
if CGFloat(horizRun) >= sp * 1.25 {
    consecutiveWideRows += 1
    if consecutiveWideRows > maxConsecutiveWideRows {
        maxConsecutiveWideRows = consecutiveWideRows
    }
} else {
    consecutiveWideRows = 0
}
...
let hasNoteheadBulge = (CGFloat(maxConsecutiveWideRows) >= sp * 0.45)
```
Standard musical noteheads attached to stems have a horizontal width of ~1.0x to 1.2x staff spacing (`sp`). The condition `horizRun >= sp * 1.25` is too high, causing `consecutiveWideRows` to reset on non-staff rows. Consequently, `hasNoteheadBulge` evaluates to `false` for typical chord noteheads. In single-staff mode (`isGrandStaff == false`), or if chord stems span >= 65% of the staff, the chord notehead stack is falsely classified as a barline (detected at X=248 in test).

---

## 2. Logic Chain

1. **Premise 1**: MusicXML truncation repair must reliably return well-formed XML regardless of whether the AI token cutoff occurs mid-measure, mid-note, mid-tag, or before the first measure completes.
   - *Observation*: In `adversarial_omr_musicxml_stress.py`, inputs lacking `<part-list>` or truncated in Measure 1 failed with `mismatched tag` XML parser errors.
   - *Inference*: `MusicXMLRepairEngine.swift` fails its core contract of resilient self-healing when LLMs output measures without `<part-list>` or when token limits exhaust inside Measure 1.

2. **Premise 2**: Barlines must be discriminated from dense chord stems without false positives on single-staff scores or typical notehead dimensions.
   - *Observation*: The horizontal width threshold of `sp * 1.25` in `VisionStaffDetector.swift` failed to detect notehead bulges on standard noteheads (0 rejections), resulting in a chord notehead stack being detected as a false barline at X=248.
   - *Inference*: While the grand-staff check (`trebleFrac >= 0.52 && bassFrac >= 0.52`) prevents grand staff chord stems from triggering false barlines, single-staff lead sheets or solo piano staves will misidentify dense chords as measure boundaries. Adjusting the threshold multiplier from `1.25` to `0.95` or `1.0` correctly detects 32 bulge rows and eliminates the false positive barline.

3. **Premise 3**: Entity sanitization, polyphonic timing, extreme skew deskewing, and shadow gradient strip tracking are functioning robustly.
   - *Observation*: Challenges 2, 3, 4, and 5 passed 100% of adversarial tests with zero timing collapse, 0.00° deskew error at ±15°/±20°, and 12/12 strips tracked under severe illumination gradients.

---

## 3. Caveats

- **Scope boundary**: This review tested algorithmic logic for R1 and R2 via Python-based mathematical and geometric models replicating Swift implementations.
- **Environment**: macOS with Xcode / Swift toolchain was not available on this Windows host; verification was performed via direct Python translation matching `Sources/PianoGlass/OMR/` line-for-line.

---

## 4. Conclusion

**Verdict**: **REQUEST_CHANGES**

The OMR and MusicXML pipelines demonstrate exceptional strength in entity sanitization (R1), 4-voice polyphony synchronization (R1), extreme skew search (R2), and shadow-resilient strip staff tracking (R2). However, two specific fixes are required before production sign-off:

1. **Fix `MusicXMLRepairEngine.swift` (Lines 68–75)**:
   - Check if `<part` is already present before inserting `<part id="P1">`.
   - Place `<part-list>` outside and before `<part>`.
   - If no complete measure exists (lines 86–98), synthesize a minimal valid envelope (`<score-partwise version="3.1"><part id="P1"></part></score-partwise>`) instead of appending mismatched closing tags to an unclosed note.
2. **Fix `VisionStaffDetector.swift` (Line 724)**:
   - Lower the horizontal notehead run threshold from `sp * 1.25` to `sp * 0.95` (or `sp * 1.0`) so that standard 1.1x spacing noteheads register consecutive wide rows and trigger `hasNoteheadBulge = true`.

---

## 5. Verification Method

1. Run the adversarial stress test suite:
   ```powershell
   python .agents/teamwork/challenger_1/adversarial_omr_musicxml_stress.py
   ```
2. Run the full multi-tier regression test suite:
   ```powershell
   pytest Tests/test_e2e_verification.py
   ```
3. Inspect `Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift` lines 68–75, 86–98, and `Sources/PianoGlass/OMR/VisionStaffDetector.swift` line 724.
