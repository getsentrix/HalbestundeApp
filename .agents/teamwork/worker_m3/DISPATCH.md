## 2026-09-29T21:01:00Z
You are Worker M3 (In-App UX & Guided Capture Experience Worker).
Your working directory: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m3
Original User Request file: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\ORIGINAL_REQUEST.md
Project Scope Document: c:\Users\dylan\Documents\antigravity\busy-hopper\PROJECT.md
Explorer Survey 3: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_3\handoff.md
Skill: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\skills\ios-developer\SKILL.md

Read ORIGINAL_REQUEST.md, PROJECT.md, and explorer_survey_3/handoff.md first.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive Write Ownership:
- Sources/PianoGlass/ViewModels/ScannerViewModel.swift
- Sources/PianoGlass/Views/Scanner/ScannerView.swift
- Sources/PianoGlass/Services/RepertoireService.swift
Do NOT modify OMR files, manifests, or workflow files.

Mission (Features F11, F12, F13, F14):
1. F11: Real-Time Viewfinder Guidance
   - In `ScannerView.swift`, build responsive guided capture overlays:
     - Real-time lighting feedback (adequate / too dark / high glare warning)
     - Distance guidance (fill ratio indicator: "Move closer" / "Position score in frame")
     - Orientation / tilt guidance (level angle indicator)
2. F12: Multi-Stage Progress Stepper
   - Replace the stalling linear progress bar with a clean 4-stage visual stepper:
     1) Preprocessing & Deskew
     2) AI / Vision Recognition
     3) Score Assembly & MusicXML Validation
     4) Audio Engine Synthesis
   - Ensure progress updates smoothly through all stages without freezing at 70%.
3. F13: Diagnostic Fallback UX & Bug Fix
   - FIX BUG in `ScannerViewModel.swift` line 127: Do NOT set `pendingFallbackScore = nil` on failure. Instead, load a fallback practice score (or the Bohemian Rhapsody sample score) so the "Play Practice Score" button appears!
   - Present clear, actionable diagnostics in the failure dialog (lighting quality, staves found count, API status / error type, suggested corrective action).
   - Add explicit "Retake Scan" and "View Details" buttons.
4. F14: Scan Review & Confirmation Sheet
   - Restore reachability of `ScanReviewSheet`: when a scan succeeds, present the review sheet (or preview) so the user can inspect detected metadata (title, composer, key, time signature, measures, notes, confidence) and preview playback before accepting.

Verification:
- Run `python scripts/test_ui_and_icon.py`
- Run `python scripts/verify_logic.py`
- Run `pytest Tests/test_e2e_verification.py`
Document commands and results in your handoff report:
c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\worker_m3\handoff.md
When done, notify caller.
