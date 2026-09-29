# BRIEFING — 2026-09-29T21:14:00Z

## Mission
Empirically and adversarially challenge the OMR and MusicXML pipelines (R1, R2) across edge cases, truncation, entity corruption, polyphonic timing, extreme skew, shadows, and chord stem discrimination.

## 🔒 My Identity
- Archetype: challenger
- Roles: critic, specialist
- Working directory: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\challenger_1
- Original parent: dea9cb97-0f25-4381-8a56-d33c704f29ed
- Milestone: M_FINAL (Challenger 1)
- Instance: 1 of 1

## 🔒 Key Constraints
- Review-only — do NOT modify implementation code directly
- Must empirically verify edge cases using executable test harness
- Focus on R1 & R2: MusicXML repair, entity sanitization, polyphonic timing, deskew, strip tracking, barline discrimination
- Report pass/fail with concrete evidence and deliver hard handoff with verdict (APPROVE or REQUEST_CHANGES)

## Current Parent
- Conversation ID: dea9cb97-0f25-4381-8a56-d33c704f29ed
- Updated: 2026-09-29T21:14:00Z

## Review Scope
- **Files to review**:
  - `Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift`
  - `Sources/PianoGlass/OMR/MusicXMLParser.swift`
  - `Sources/PianoGlass/OMR/VisionStaffDetector.swift`
  - `Sources/PianoGlass/OMR/NoteRecognitionEngine.swift`
  - `Tests/PianoGlassTests/MusicXMLParserTests.swift`
  - `Tests/PianoGlassTests/OMRStaffDetectorTests.swift`
  - `Tests/test_e2e_verification.py`
  - `assets/Bohemian_Rhapsody_Sample.musicxml`
- **Interface contracts**: PROJECT.md Contracts 1, 2, 3
- **Review criteria**: Adversarial stress testing across 6 edge case categories

## Attack Surface
- **Hypotheses tested**:
  - H1: Truncation mid-tag, mid-note, mid-measure, nested chord tags, unclosed parts. (CONFIRMED VULNERABILITIES in missing part-list & measure 1 cut)
  - H2: Entity corruption: unescaped & in lyrics, credits, titles. (ROBUST / PASS)
  - H3: Polyphonic timing: 4-voice grand staff, backup/forward sync without beat 0 collapse. (ROBUST / PASS)
  - H4: Extreme skew/tilt (±15°, ±20°), optimal variance identification. (ROBUST / PASS)
  - H5: Severe shadows / non-uniform lighting across staves in strip tracker. (ROBUST / PASS)
  - H6: Chord note stems vs barlines: dense chords causing false positive barlines. (CONFIRMED VULNERABILITY in single staff & notehead width threshold)
- **Vulnerabilities found**:
  1. `MusicXMLRepairEngine.swift` lines 68-75: Injects duplicate `<part id="P1">` and malformed `<part-list>` inside `<part>` if `<part id="P1">` exists without `<part-list>`, causing XML parse failure `mismatched tag`.
  2. `MusicXMLRepairEngine.swift` lines 86-98: When truncated in Measure 1, attempts to close `</measure>` without closing open inner tags (`<note>`, `<pitch>`), causing XML parse failure `mismatched tag`.
  3. `VisionStaffDetector.swift` line 724: `horizRun >= sp * 1.25` is too wide for standard 1.1x noteheads attached to stems, causing `hasNoteheadBulge` to fail and falsely classifying chord notehead stacks as barlines in single-staff mode.
- **Untested angles**: Multi-movement partwise scores with lyrics containing CDATA blocks.

## Loaded Skills
- None required for standalone python adversarial harness

## Key Decisions Made
- Executed empirical adversarial stress harness (`adversarial_omr_musicxml_stress.py`) across all 6 test dimensions.
- Verdict reached: **REQUEST_CHANGES** due to confirmed bugs in `MusicXMLRepairEngine.swift` and `VisionStaffDetector.swift`.

## Artifact Index
- `adversarial_omr_musicxml_stress.py` — Python adversarial stress test harness
- `progress.md` — Liveness & status tracking
- `handoff.md` — 5-component hard handoff report with REQUEST_CHANGES verdict
