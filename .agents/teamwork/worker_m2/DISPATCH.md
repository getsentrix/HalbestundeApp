## 2026-09-29T20:52:56Z
You are Worker M2 (On-Device Fallback OMR Worker).
Your working directory: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m2
Original User Request file: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\ORIGINAL_REQUEST.md
Project Scope Document: c:\Users\dylan\Documents\antigravity\busy-hopper\PROJECT.md
Explorer Survey 2: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_2\handoff.md
Skill: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\skills\ios-developer\SKILL.md

Read ORIGINAL_REQUEST.md, PROJECT.md, and explorer_survey_2/handoff.md first.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive Write Ownership:
- Sources/PianoGlass/OMR/VisionStaffDetector.swift
- Sources/PianoGlass/OMR/NoteRecognitionEngine.swift
Do NOT modify MusicScannerService.swift, MusicXMLParser.swift, or UI files.

Mission (Features F6, F7, F8, F9, F10):
1. F6: On-Device Image Pipeline & Coordinate Alignment
   - Fix the coordinate mismatch bug: always pass `alignedImage`/`deskewedImage` across staff detection, barline detection, and notehead recognition.
   - Expand coarse deskew angle search to ±20.0° for handheld camera captures.
2. F7: Strip-Based Staff Tracking
   - Implement vertical strip / segment-based staff line detection (slicing width into 8-16 vertical columns) to track curved, sagged, or angled staff lines.
   - Resilient to uneven lighting, page curvature, and cast shadows using local adaptive thresholding.
3. F8: Grand-Staff Barline Discrimination
   - Discriminate true barlines from chord note stems by checking grand staff vertical span and absence of noteheads/beams.
   - Ensure consistent measure boundary indices across both treble and bass staves.
4. F9: Notehead Morphology & Duration Engine
   - Improve notehead segmentation (prevent staff line inpainting from merging noteheads into horizontal artifacts).
   - Distinguish solid (quarter, eighth, sixteenth) vs hollow (half, whole) noteheads.
   - Detect stems, flags, and beams to identify eighth and sixteenth notes and dotted durations.
   - Accurate diatonic pitch mapping relative to staff line coordinates and clefs (treble G-clef, bass F-clef).
5. F10: Multi-Staff Rhythm Quantizer & Beat Sync
   - Eliminate linear X spatial mapping bug.
   - Implement joint temporal clustering of treble and bass notes in each measure.
   - Snap note onsets to musical subdivision grids (quarter, eighth, sixteenth, triplets).
   - Prevent timing collapse or bunching at beat 0; ensure consistent measure duration.

Verification:
- Run `python scripts/verify_logic.py`
- Test staff detection and note recognition logic
Document all commands and results in your handoff report:
c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m2\handoff.md
When done, notify caller.
