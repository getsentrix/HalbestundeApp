## 2026-09-29T20:52:56Z
You are Worker M1 (Gemini AI Transcription & MusicXML Pipeline Worker).
Your working directory: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m1
Original User Request file: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\ORIGINAL_REQUEST.md
Project Scope Document: c:\Users\dylan\Documents\antigravity\busy-hopper\PROJECT.md
Explorer Survey 1: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_1\handoff.md
Skill: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\skills\ios-developer\SKILL.md
Gemini Skill: C:\Users\dylan\.gemini\config\plugins\gemini-api\skills\gemini-api-dev\SKILL.md

Read ORIGINAL_REQUEST.md, PROJECT.md, and explorer_survey_1/handoff.md first.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive Write Ownership:
- Sources/PianoGlass/OMR/MusicScannerService.swift
- Sources/PianoGlass/OMR/MusicXMLParser.swift
- Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift (create new Swift file)
- backend/omr_engine.py
Do NOT modify VisionStaffDetector.swift, NoteRecognitionEngine.swift, or UI files.

Mission (Features F1, F2, F3, F4, F5):
1. F1: Gemini Prompt & Request Engineering
   - Add exponential backoff with jitter on HTTP 429 & 503 errors.
   - Clean failover: primary `gemini-3.8-flash` -> fallback `gemini-3.5-flash-lite`.
   - Configure `thinkingConfig` to limit thinking budget and prevent token starvation.
   - Align timeouts (90s) and token limits across Swift and Python (`backend/omr_engine.py`).
2. F2: Universal Preprocessing & Deskew
   - Ensure `deskewCGImage` is called for ALL image sources, including imported PDFs and photos in `processDocumentData`.
   - Add adaptive lighting normalization / contrast enhancement so staves and accidentals are sharp and clean.
3. F3: Multi-Page & Multi-System Document Pipeline
   - Fix PDF multi-page squashing bug: render pages individually at high DPI without scaling down to 3000px composite.
   - Support multi-page sequential transcription and merging into a coherent `ParsedScore`.
4. F4: Streaming XML Repair & Sanitizer (`MusicXMLRepairEngine.swift`)
   - Implement resilient XML repair: when response is truncated mid-stream by token limit, strip incomplete trailing elements, close all open tags up to last valid `</measure>`, close `</part>` and `</score-partwise>`.
   - Sanitize XML entities and validate MusicXML 3.1 structure before passing to parser.
5. F5: Polyphonic Grand-Staff MusicXML Parser Overhaul
   - In `MusicXMLParser.swift`, separate timeline tracking per `(staff, voice)`.
   - Fix `<backup>` and `<forward>` to rewind/advance along the part/voice timeline, NOT across all staves indiscriminately.
   - Correctly map accidentals, chord groupings, octave shifts, rests, and note durations without timing collapse at beat 0.

Verification:
- Run `pytest Tests/test_backend.py`
- Run `python scripts/verify_logic.py`
- Run ground truth parse against `assets/Bohemian_Rhapsody_Sample.musicxml`
Document all commands and results in your handoff report:
c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m1\handoff.md
When done, notify caller.
