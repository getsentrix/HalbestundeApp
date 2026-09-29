# BRIEFING — 2026-09-29T20:50:00Z

## Mission
Survey the entire codebase for Requirement 2 (On-Device Fallback OMR overhaul), analyze algorithms, identify bugs/gaps, and produce a comprehensive handoff report.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\dylan\Documents\antigravity\busy-hopper\.agents\teamwork\explorer_survey_2
- Original parent: dea9cb97-0f25-4381-8a56-d33c704f29ed
- Milestone: exploration_survey

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Adhere to ADHD reader output style (command/path first, numbered steps, <=5 items per list, concrete time estimates, no filler)
- Self-contained 5-component handoff report in handoff.md

## Current Parent
- Conversation ID: dea9cb97-0f25-4381-8a56-d33c704f29ed
- Updated: 2026-09-29T20:47:00Z

## Investigation State
- **Explored paths**:
  - `Sources/PianoGlass/OMR/VisionStaffDetector.swift`
  - `Sources/PianoGlass/OMR/NoteRecognitionEngine.swift`
  - `Sources/PianoGlass/OMR/MusicScannerService.swift`
  - `Sources/PianoGlass/OMR/MusicXMLParser.swift` & `MusicXMLExporter.swift`
  - `Sources/PianoGlass/Models/MusicModels.swift` & `ScanResult.swift`
  - `Tests/PianoGlassTests/OMRStaffDetectorTests.swift`
  - `scripts/verify_logic.py`, `scripts/_patch_omr.py`
- **Key findings**:
  - Critical bug: `MusicScannerService.swift` lines 178 & 193 pass un-deskewed `cgImage` instead of `alignedImage`; `VisionStaffDetector.swift` lines 223 & 254 also pass un-deskewed `cgImage`.
  - Angle limitation: Deskew only tests `±6.0°` (fails on tilted phone captures).
  - Global projection: 1D horizontal projection across 70% width collapses under shadows and page curvature.
  - Barline detection bug: detects note stems as barlines due to low vertical darkness fraction (30%-44%).
  - Inpainting flaw: Surviving staff lines join noteheads into wide blobs filtered out by width check, dropping notes.
  - Duration deficiency: Only whole/half/quarter; zero support for eighths, sixteenths, beams, flags, or rests.
  - Multi-staff desynchronization: linear X-to-beat conversion without joint RH/LH alignment causes micro-delays and beat bleed.
- **Unexplored areas**:
  - None within R2 scope.

## Key Decisions Made
- Documented 6 core algorithmic failure modes with precise line references and remediation blueprints.

## Artifact Index
- `progress.md` — Liveness & status tracking
- `DISPATCH.md` — Dispatch message log
- `handoff.md` — 5-component handoff report
