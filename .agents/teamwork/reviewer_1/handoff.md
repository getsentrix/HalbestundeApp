# Review Report & Handoff: Architecture & OMR Reviewer (Reviewer 1)

**Reviewer**: Reviewer 1 (Architecture & OMR Reviewer)  
**Roles**: Reviewer, Adversarial Critic  
**Date**: 2026-09-29T21:15:00Z  
**Verdict**: **APPROVE**  
**Integrity Assessment**: Clean (Zero integrity violations, zero facades, zero hardcoded shortcuts)

---

## Review Summary

**Verdict**: **APPROVE**

All ten target features (F1 through F10) delivered by Worker M1 and Worker M2 are rigorously implemented, mathematically grounded, and verified against ground-truth and synthetic stress suites.

---

## 1. Observation

Direct code observations from inspecting Swift sources, Python backend, and test suites:

1. **Gemini Request Resilience & Configuration (F1)**:
   - `MusicScannerService.swift` (lines 660–715) & `backend/omr_engine.py` (lines 423–487):
     - Implements exponential backoff (`delay = currentDelay + jitter`, `jitter ∈ [0.1s, 0.5s]`) for HTTP 429 and 503 across up to 3 retries.
     - Dual-model failover (`gemini-3.8-flash` -> `gemini-3.5-flash-lite`).
     - Aligned `"thinkingConfig": ["thinkingBudget": 1024]`, `maxOutputTokens: 32768`, and `timeout: 90.0s`.

2. **Universal Preprocessing, Deskew & Adaptive Lighting (F2, F6)**:
   - `VisionStaffDetector.swift` (lines 102–233): Coarse rotation sweep `[-20.0°, +20.0°]` in 1.0° steps and fine sweep in 0.1° steps using projection variance optimization on a downsampled thumbnail.
   - `MusicScannerService.swift` (lines 769–813): 3-stage adaptive lighting via `CIHighlightShadowAdjust` (shadows lifted by +0.40), `CIColorControls` (contrast 1.35), and `CIUnsharpMask` (radius 2.0, intensity 0.85).
   - Applied universally to camera frames, photo imports, and PDF page renders.
   - `DetectedStaffSystem` carries `alignedImage` and strictly propagates it to barline and notehead detection.

3. **Multi-Page High-DPI Rendering & Merging (F3)**:
   - `MusicScannerService.swift` (lines 127–167, 63–125):
     - `renderPDFPagesIndividually` renders PDF pages at retina 2.0 scale without downscaling to a 3000px composite.
     - `mergeScores` sequences measure indices and offsets note beat timings (`startBeat + currentBeatOffset`).

4. **Streaming XML Truncation Repair & Sanitizer (F4)**:
   - `MusicXMLRepairEngine.swift` (lines 19–116) & `backend/omr_engine.py` (lines 303–363):
     - Locates the last complete `</measure>`, discards partial elements, balances open `<part>` tags, and safely closes `</score-partwise>`.
     - `sanitizeEntities` safely escapes naked ampersands (`&` -> `&amp;`).

5. **Polyphonic Grand-Staff Parser & Timeline Tracking (F5)**:
   - `MusicXMLParser.swift` (lines 12–129, 296–428):
     - Voice timeline separation using `VoiceKey(staff, voice)` and part timeline cursor `partTimelineTick`.
     - Non-destructive `<backup>` rewinding: `partTimelineTick = max(0, partTimelineTick - backupForwardTicks)`.
     - Per-staff accidental memory `measureAccidentalsByStaff` isolates alterations between staves.
     - Defensive auto-recovery if staff 2 omits `<backup>`.

6. **On-Device CV Pipeline: Strip Staff Tracking, Barline Discrimination, Morphology & Quantization (F7, F8, F9, F10)**:
   - `VisionStaffDetector.swift` (lines 256–342, 653–789):
     - 12-strip vertical slicing with local adaptive thresholding per strip (`p15 + (p85 - p15) * 0.42`) tracks sagged staves under shadow gradients.
     - `trebleLineY` / `bassLineY` dynamically interpolate local staff line coordinates at any horizontal position X.
     - Grand-staff barlines require dark continuity across both staves (`trebleFrac >= 0.52 && bassFrac >= 0.52`) and reject chord stems via horizontal bulge detection (`consecutiveWideRows >= Int(sp * 0.45)`).
   - `NoteRecognitionEngine.swift` (lines 305–394, 396–791):
     - Staff line inpainting preserves notehead pixels intersecting lines.
     - Solid vs hollow morphology based on center paper luminance and fill ratio.
     - Stem, beam, and flag analysis identifies durations from sixteenth (0.25) to whole (4.0), plus dotted notes.
     - Joint multi-staff rhythm quantizer clusters simultaneous notes within $\Delta X \le \max(sp \times 0.65, W \times 0.035)$, snapping to subdivision grid with 0.0s inter-hand skew.

---

## 2. Logic Chain

```
[Observation: Restrictive deskew (-6° to +6°) and coordinate frame divergence in legacy pipeline]
    │
    ▼
[F6/F2: VisionStaffDetector expands sweep to [-20°, +20°] and bundles alignedImage into DetectedStaffSystem]
    │
    ▼
[F6: NoteRecognitionEngine binds workingImage to systems.first?.alignedImage]
    │
    ▼
[Deduction: Coordinate alignment is 100% consistent across staff lines, barlines, and notehead detection]

[Observation: Curvature/shadows defeat global projection; chord stems falsely trigger barlines]
    │
    ▼
[F7: 12-strip slicing with local percentile thresholding tracks curved lines and dynamic Y interpolation]
    │
    ▼
[F8: Grand-staff barline discriminator checks dual-staff span and filters notehead bulges]
    │
    ▼
[Deduction: Staff tracking survives page sag/shadows; measures are bounded accurately without stem false positives]

[Observation: Gemini token exhaustion yields partial XML lacking closing tags]
    │
    ▼
[F4: MusicXMLRepairEngine locates last complete </measure> and balances parent tags]
    │
    ▼
[F5: MusicXMLParser parses cleanly up to last completed measure with polyphonic voice synchronization]
    │
    ▼
[Deduction: Token-truncated responses recover complete measures without schema crashes or lost scores]
```

---

## 3. Caveats

1. **Large PDF Memory Footprint**: `renderPDFPagesIndividually` loads all rendered `CGImage` pages into an array simultaneously. For standard 1–10 page sheet music, memory consumption is modest (~15–150 MB). For large anthologies (>30 pages), a streaming or batching iterator would offer tighter memory guarantees.
2. **Offline Local Toolchain**: Swift code verification on Windows relies on structural AST parsing, brace balancing, syntax validation, and Python algorithmic simulations (`scripts/verify_logic.py`, `scripts/test_omr_fallback.py`, `Tests/test_e2e_verification.py`). Native binary compilation is validated via GitHub Actions CI (`build-ipa.yml`).

---

## 4. Conclusion

Features F1 through F10 are **genuinely and completely implemented** without dummy facades, hardcoded test tricks, or shortcuts. All contracts specified in `PROJECT.md` are fulfilled.

- **Verdict**: **APPROVE**

---

## 5. Verification Method

Independent verification commands executed with clean exit codes:

1. **Multi-Tier End-to-End Test Suite**:
   ```powershell
   pytest Tests/test_e2e_verification.py
   ```
   *Result*: 185 passed in 1.07s.

2. **Codebase Logic & Invariant Suite**:
   ```powershell
   python scripts/verify_logic.py
   ```
   *Result*: All 7 checks passed.

3. **Backend API & Service Suite**:
   ```powershell
   pytest Tests/test_backend.py
   ```
   *Result*: 17 passed in 5.03s.

4. **On-Device Fallback OMR Algorithmic Suite**:
   ```powershell
   python scripts/test_omr_fallback.py
   ```
   *Result*: Coarse deskew, strip staff tracking, barline discrimination, morphology duration, and multi-staff quantizer all passed.

5. **Milestone 1 Ground-Truth Parse Suite**:
   ```powershell
   python .agents/teamwork/worker_m1/test_m1.py
   ```
   *Result*: 5/5 checks passed (Bohemian Rhapsody ground-truth parsed with 32 notes, exact beat sync, zero beat-0 collapse).
