# Original User Request

## 2026-09-29T20:45:01Z

work as a group of engineers

Overhaul the PianoGlass piano sheet music scanning system from the ground up to achieve high-accuracy, reliable music transcription across phone photos, digital images, and PDFs, with Gemini multimodal AI as the primary high-precision engine and an optimized on-device computer vision pipeline as the offline fallback, ending with an automated build and published release.

Working directory: c:\Users\dylan\Documents\antigravity\busy-hopper
Integrity mode: development

## Requirements

### R1. High-Fidelity Gemini AI Transcription Pipeline
Rethink and re-engineer the prompt, image preprocessing (deskewing, contrast, downsampling/upsampling, lighting normalization), and MusicXML extraction pipeline so Gemini accurately transcribes complex grand-staff piano notation:
- Full polyphonic measures, chords, accurate octaves, and correct accidentals
- Multi-system, multi-page layout without dropping staves or truncating
- Strict MusicXML 3.1 validation and recovery from malformed output

### R2. Overhauled On-Device Fallback OMR
Re-architect the local computer vision pipeline to provide a dependable offline scanning fallback:
- Robust staff line detection resilient to shadows, phone camera angles, and page curvature
- Accurate notehead identification, duration analysis (solid vs. hollow), and pitch mapping to diatonic staff coordinates
- Beat-accurate measure distribution and multi-staff timeline synchronization

### R3. In-App User Experience & Guided Capture
Optimize the scanner workflow and error recovery:
- Real-time viewfinder guidance for lighting, distance, and orientation
- Clear progress feedback during multi-stage recognition
- Direct fallback path with informative diagnostics when a scan fails or needs retake

### R4. Automated Verification & Production Release
Validate the entire scanning-to-audio pipeline with automated test scripts and publish a verified GitHub release:
- Programmatic end-to-end verification comparing recognized output against known ground-truth MusicXML scores
- Version bump across all manifests (`apps.json`, `altstore.json`, `Info.plist`, `project.pbxproj`)
- Trigger and verify the GitHub Actions release workflow (`build-ipa.yml`) to produce a verified IPA and release

## Acceptance Criteria

### Recognition & Transcription Quality
- [ ] Automated test suite runs against sample piano scores (`assets/Bohemian_Rhapsody_Sample.musicxml` and test images) and validates that generated MusicXML parses cleanly with zero schema errors.
- [ ] Measure count, time signature, key signature, and note events correspond to the source notation without timing collapse or notes bunching at beat 0.
- [ ] Gemini API requests handle network timeouts, rate limits, and partial tokens gracefully with automatic fallback.

### On-Device Robustness
- [ ] Staff detector and note recognition engine process test score images without throwing unhandled exceptions or returning empty measures when staves are visible.
- [ ] Barlines and measure boundaries are detected with consistent measure indices across both treble and bass staves.

### Build & Release Verification
- [ ] All Swift code compiles cleanly with no syntax or concurrency errors.
- [ ] GitHub Actions release workflow runs to completion and produces a downloadable `PianoGlass.ipa` release asset.
- [ ] Version and download URLs in `apps.json` and `altstore.json` match the new release tag.
