# Orchestrator Plan: PianoGlass Sheet Music Overhaul

## 1. Survey Phase
- Explorer 1 (Focus: R1 Gemini AI Transcription Pipeline, preprocessing, prompt engineering, MusicXML 3.1 schema, recovery)
- Explorer 2 (Focus: R2 On-Device CV/OMR Fallback, staff detection, notehead & duration analysis, measure synchronization)
- Explorer 3 (Focus: R3 & R4 UI/UX Guided Capture, Viewfinder, Error diagnostics, Build & Release pipeline, GitHub Actions, manifests)

## 2. Synthesis & Decomposition
- Synthesize 3 Explorer reports into `PROJECT.md` with:
  - Architecture and Module boundaries
  - Complete Feature Inventory mapped to milestones
  - Milestone decomposition (M1: Gemini Pipeline, M2: On-Device OMR, M3: UI/UX & Capture Flow, M4: Build & Release Verification)
  - Interface contracts between components
  - Code layout guidelines

## 3. Parallel Tracks Execution
- Track A: E2E Testing Track (Spawn E2E Testing Orchestrator to build requirement-driven opaque-box test suite for Tiers 1-4)
- Track B: Implementation Track (Spawn sub-orchestrators for milestones M1, M2, M3, M4)

## 4. Final Milestone & Hardening
- Phase 1: 100% E2E test pass across all Tiers 1-4
- Phase 2: Tier 5 Adversarial coverage hardening (Challenger -> Worker -> Reviewer loop)

## 5. Verification & Sentinel Notification
- Verify all manifests (apps.json, altstore.json, Info.plist, project.pbxproj)
- Verify GitHub Actions workflow configuration
- Send completion handoff to Sentinel for victory audit
