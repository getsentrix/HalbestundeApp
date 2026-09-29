#!/usr/bin/env python3
"""
Adversarial Verification & Stress Test Harness for PianoGlass (Challenger 2)

Covers:
1. ScannerViewModel state transitions under rapid simulated failure, retake, and fallback.
2. Verification that pendingFallbackScore is NEVER nil on failure and produces playable audio events.
3. Stress test manifest consistency across all 8 manifest files (identical versions, valid formats, non-empty URLs).
4. Bohemian Rhapsody ground truth verification (measure count = 2, note count = 32, key = Bb Major, simultaneous beat 0 starts).
"""

import os
import sys
import json
import re
import plistlib
import xml.etree.ElementTree as ET
import random
from typing import List, Dict, Optional, Any
import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

BOHEMIAN_XML_PATH = os.path.join(REPO_ROOT, "assets", "Bohemian_Rhapsody_Sample.musicxml")


# ============================================================================
# 1. ScannerViewModel State Machine Simulation & Invariant Checker
# ============================================================================

class ScannerStep:
    CAMERA = "camera"
    PROCESSING = "processing"
    REVIEW = "review"


class ProgressStage:
    PREPROCESSING = 1
    RECOGNITION = 2
    ASSEMBLY = 3
    AUDIO_READY = 4


class NoteEvent:
    def __init__(self, pitch: int, start_beat: float, duration_beats: float, velocity: float, hand: str, measure_idx: int):
        self.pitch = pitch
        self.start_beat = start_beat
        self.duration_beats = duration_beats
        self.velocity = velocity
        self.hand = hand
        self.measure_idx = measure_idx

    @property
    def end_beat(self) -> float:
        return self.start_beat + self.duration_beats


class Measure:
    def __init__(self, index: int, start_beat: float, duration_beats: float, notes: List[NoteEvent]):
        self.index = index
        self.start_beat = start_beat
        self.duration_beats = duration_beats
        self.notes = notes


class Score:
    def __init__(self, title: str, composer: str, default_bpm: float, measures: List[Measure], fifths: int = 0):
        self.title = title
        self.composer = composer
        self.default_bpm = default_bpm
        self.measures = measures
        self.fifths = fifths

    @property
    def total_notes(self) -> int:
        return sum(len(m.notes) for m in self.measures)


def synthesize_fallback_score(title: str = "Fallback Score") -> Score:
    """Exact emulation of NoteRecognitionEngine.synthesizeFallbackMeasures."""
    chords = [
        ([64, 67, 72, 76], [36, 43, 48, 52]),
        ([65, 69, 72, 77], [41, 45, 48, 53]),
        ([67, 71, 74, 79], [43, 47, 50, 55]),
        ([64, 67, 72, 84], [36, 48, 52, 60]),
    ]
    measures = []
    for m_idx, (rh, lh) in enumerate(chords):
        notes = []
        m_start = float(m_idx) * 4.0
        for beat_idx, (rh_pitch, lh_pitch) in enumerate(zip(rh, lh)):
            note_beat = m_start + float(beat_idx)
            notes.append(NoteEvent(rh_pitch, note_beat, 1.0, 0.82, "right", m_idx))
            notes.append(NoteEvent(lh_pitch, note_beat, 1.0, 0.72, "left", m_idx))
        measures.append(Measure(m_idx, m_start, 4.0, notes))
    return Score(title, "Arranged for PianoGlass", 112.0, measures, 0)


class MockScannerViewModel:
    """State machine matching Sources/PianoGlass/ViewModels/ScannerViewModel.swift."""

    def __init__(self, on_score_accepted=None):
        self.current_step = ScannerStep.CAMERA
        self.is_processing = False
        self.status_message = "Align piano sheet music within glass frame"
        self.progress_fraction = 0.0
        self.scan_confidence = 0.0
        self.captured_score: Optional[Score] = None
        self.active_scan_result: Optional[Score] = None
        self.current_guidance_state = "readyToCapture"
        self.current_stage = ProgressStage.PREPROCESSING
        self.show_error_alert = False
        self.error_message = ""
        self.pending_fallback_score: Optional[Score] = None
        self.last_diagnostic: Optional[Dict[str, Any]] = None
        self.show_detailed_diagnostics = False
        self.show_review_sheet = False
        self.on_score_accepted = on_score_accepted

    @staticmethod
    def categorize_error(err_str: str) -> str:
        lower = err_str.lower()
        if any(k in lower for k in ["429", "network", "http", "connect", "timeout"]):
            return "connectivity"
        if any(k in lower for k in ["staff", "stave", "optical", "omr"]):
            return "optical"
        return "unknown"

    def update_viewfinder_guidance(self, luminance: float, fill_ratio: float, tilt_deg: float):
        if luminance < 0.30:
            self.current_guidance_state = "tooDark"
        elif luminance > 0.95:
            self.current_guidance_state = "glareWarning"
        elif abs(tilt_deg) > 12.0:
            self.current_guidance_state = "tiltWarning"
        elif fill_ratio < 0.70:
            self.current_guidance_state = "tooFar"
        elif fill_ratio > 0.98:
            self.current_guidance_state = "tooClose"
        else:
            self.current_guidance_state = "readyToCapture"

    def process_captured_image_start(self):
        self.is_processing = True
        self.current_step = ScannerStep.PROCESSING
        self.current_stage = ProgressStage.PREPROCESSING
        self.progress_fraction = 0.05
        self.status_message = "Analyzing staves & musical notation..."

    def process_captured_image_success(self, score: Score, confidence: float = 0.94):
        self.scan_confidence = confidence
        self.captured_score = score
        self.active_scan_result = score
        self.current_step = ScannerStep.REVIEW
        self.current_stage = ProgressStage.AUDIO_READY
        self.progress_fraction = 1.0
        self.status_message = "Recognition Complete (100%)"
        self.is_processing = False
        self.show_review_sheet = True

    def process_captured_image_failure(self, error_desc: str, title: str = "Scanned Sheet Music"):
        self.is_processing = False
        self.current_step = ScannerStep.CAMERA
        self.current_stage = ProgressStage.PREPROCESSING
        self.progress_fraction = 0.0
        self.status_message = "Scan failed"

        cat = self.categorize_error(error_desc)
        fallback = synthesize_fallback_score(title)
        self.pending_fallback_score = fallback

        if cat == "optical":
            action = "Ensure sheet music is flat, well-lit, and fills 75%+ of the frame without tilt."
        elif cat == "connectivity":
            action = "Gemini cloud service is busy or rate-limited. Retry in a moment or use the offline fallback practice score."
        else:
            action = "Ensure the sheet music is flat, well-lit, and fills the viewfinder."

        self.last_diagnostic = {
            "failureReason": error_desc or "Notation recognition failed",
            "staffCount": 0,
            "lightingQuality": "adequate",
            "apiStatus": "HTTP 429 / Connectivity Error" if cat == "connectivity" else "Offline OMR Active",
            "suggestedAction": action,
            "fallbackScore": fallback,
            "errorCategory": cat,
        }
        self.error_message = f"Could not recognize notation in this scan: {error_desc}\n\n{action}"
        self.show_error_alert = True

    def accept_scan_result(self, score: Score):
        self.show_review_sheet = False
        self.current_step = ScannerStep.CAMERA
        if self.on_score_accepted:
            self.on_score_accepted(score)

    def accept_fallback_score(self, score: Score):
        if self.on_score_accepted:
            self.on_score_accepted(score)

    def retake(self):
        self.captured_score = None
        self.active_scan_result = None
        self.show_review_sheet = False
        self.show_detailed_diagnostics = False
        self.current_step = ScannerStep.CAMERA
        self.is_processing = False
        self.current_stage = ProgressStage.PREPROCESSING
        self.progress_fraction = 0.0
        self.status_message = "Align piano sheet music within glass frame"


# ============================================================================
# Test Suite 1: ScannerViewModel State Transitions & Stress Testing
# ============================================================================

class TestScannerViewModelTransitions:
    """Requirement 1: ScannerViewModel state transitions under rapid simulated failure, retake, and fallback."""

    def test_initial_state_invariants(self):
        vm = MockScannerViewModel()
        assert vm.current_step == ScannerStep.CAMERA
        assert vm.is_processing is False
        assert vm.progress_fraction == 0.0
        assert vm.show_review_sheet is False
        assert vm.show_error_alert is False
        assert vm.pending_fallback_score is None

    def test_failure_sets_pending_fallback_and_diagnostics(self):
        vm = MockScannerViewModel()
        vm.process_captured_image_start()
        assert vm.is_processing is True
        assert vm.current_step == ScannerStep.PROCESSING

        vm.process_captured_image_failure("No staves detected in frame", title="Test Piece")
        assert vm.is_processing is False
        assert vm.current_step == ScannerStep.CAMERA
        assert vm.show_error_alert is True
        assert vm.pending_fallback_score is not None
        assert vm.last_diagnostic is not None
        assert vm.last_diagnostic["errorCategory"] == "optical"
        assert "flat, well-lit" in vm.last_diagnostic["suggestedAction"]

    def test_http_429_rate_limit_failure_categorization(self):
        vm = MockScannerViewModel()
        vm.process_captured_image_start()
        vm.process_captured_image_failure("HTTP 429: Resource exhausted rate limit")
        assert vm.last_diagnostic["errorCategory"] == "connectivity"
        assert "HTTP 429" in vm.last_diagnostic["apiStatus"]
        assert vm.pending_fallback_score is not None

    def test_retake_clears_all_transient_state(self):
        vm = MockScannerViewModel()
        vm.process_captured_image_start()
        dummy_score = synthesize_fallback_score("Successful Scan")
        vm.process_captured_image_success(dummy_score)
        assert vm.show_review_sheet is True
        assert vm.current_step == ScannerStep.REVIEW

        vm.retake()
        assert vm.show_review_sheet is False
        assert vm.current_step == ScannerStep.CAMERA
        assert vm.is_processing is False
        assert vm.progress_fraction == 0.0
        assert vm.captured_score is None
        assert vm.active_scan_result is None

    def test_rapid_cancellation_during_processing(self):
        vm = MockScannerViewModel()
        for _ in range(20):
            vm.process_captured_image_start()
            assert vm.is_processing is True
            vm.retake()
            assert vm.is_processing is False
            assert vm.current_step == ScannerStep.CAMERA

    def test_double_consecutive_failures_stability(self):
        vm = MockScannerViewModel()
        vm.process_captured_image_start()
        vm.process_captured_image_failure("Error 1: Network timeout")
        first_fallback = vm.pending_fallback_score
        assert first_fallback is not None

        # Immediate second failure without retake
        vm.process_captured_image_start()
        vm.process_captured_image_failure("Error 2: Staff detection failed")
        assert vm.pending_fallback_score is not None
        assert vm.last_diagnostic["errorCategory"] == "optical"
        assert vm.is_processing is False

    def test_guidance_state_transitions(self):
        vm = MockScannerViewModel()
        vm.update_viewfinder_guidance(luminance=0.1, fill_ratio=0.8, tilt_deg=2.0)
        assert vm.current_guidance_state == "tooDark"

        vm.update_viewfinder_guidance(luminance=0.98, fill_ratio=0.8, tilt_deg=2.0)
        assert vm.current_guidance_state == "glareWarning"

        vm.update_viewfinder_guidance(luminance=0.6, fill_ratio=0.8, tilt_deg=15.0)
        assert vm.current_guidance_state == "tiltWarning"

        vm.update_viewfinder_guidance(luminance=0.6, fill_ratio=0.5, tilt_deg=2.0)
        assert vm.current_guidance_state == "tooFar"

        vm.update_viewfinder_guidance(luminance=0.6, fill_ratio=0.99, tilt_deg=2.0)
        assert vm.current_guidance_state == "tooClose"

        vm.update_viewfinder_guidance(luminance=0.6, fill_ratio=0.85, tilt_deg=2.0)
        assert vm.current_guidance_state == "readyToCapture"

    def test_randomized_fuzzing_state_invariants_1000_cycles(self):
        """Adversarially fuzzed state machine testing 1000 random actions to ensure no corrupt states."""
        accepted_scores = []
        vm = MockScannerViewModel(on_score_accepted=lambda s: accepted_scores.append(s))
        random.seed(42)

        for cycle in range(1000):
            action = random.choice([
                "start_scan", "fail_optical", "fail_network", "succeed",
                "accept_review", "retake", "accept_fallback", "guidance"
            ])
            if action == "start_scan":
                vm.process_captured_image_start()
            elif action == "fail_optical":
                vm.process_captured_image_failure("OMR staff line detection failure", title=f"Fuzz_{cycle}")
            elif action == "fail_network":
                vm.process_captured_image_failure("HTTP 429 rate limit exceeded", title=f"Fuzz_{cycle}")
            elif action == "succeed":
                sc = synthesize_fallback_score(f"Scan_{cycle}")
                vm.process_captured_image_success(sc)
            elif action == "accept_review":
                if vm.show_review_sheet and vm.active_scan_result:
                    vm.accept_scan_result(vm.active_scan_result)
            elif action == "retake":
                vm.retake()
            elif action == "accept_fallback":
                if vm.pending_fallback_score:
                    vm.accept_fallback_score(vm.pending_fallback_score)
            elif action == "guidance":
                vm.update_viewfinder_guidance(
                    random.uniform(0.0, 1.0),
                    random.uniform(0.5, 1.0),
                    random.uniform(-20.0, 20.0)
                )

            # Assert invariants at every cycle
            assert 0.0 <= vm.progress_fraction <= 1.0
            if vm.current_step == ScannerStep.REVIEW:
                assert vm.show_review_sheet is True
                assert vm.active_scan_result is not None
            if vm.show_error_alert:
                assert vm.pending_fallback_score is not None
                assert vm.last_diagnostic is not None


# ============================================================================
# Test Suite 2: Pending Fallback Score Playability Guarantees
# ============================================================================

class TestPendingFallbackScoreGuarantees:
    """Requirement 2: Verify that pendingFallbackScore is NEVER nil on failure and produces playable audio events."""

    def test_pending_fallback_score_is_never_nil_on_any_error(self):
        vm = MockScannerViewModel()
        error_samples = [
            "HTTP 429 Too Many Requests",
            "HTTP 503 Backend Service Unavailable",
            "Vision staff line tracking returned 0 systems",
            "MusicXML parse error on line 42",
            "SecurityScopedResource access denied",
            "",
            "Unknown hardware exception",
        ]
        for err in error_samples:
            vm.process_captured_image_start()
            vm.process_captured_image_failure(err)
            assert vm.pending_fallback_score is not None, f"pendingFallbackScore was None for error: '{err}'"
            assert isinstance(vm.pending_fallback_score, Score)

    def test_fallback_score_audio_event_playability(self):
        score = synthesize_fallback_score("Etude Fallback")
        assert len(score.measures) == 4
        assert score.total_notes == 32

        # Check all notes have playable MIDI pitches in 88-key piano range (21 to 108)
        for m in score.measures:
            assert m.duration_beats == 4.0
            assert len(m.notes) == 8
            for note in m.notes:
                assert 21 <= note.pitch <= 108, f"Pitch {note.pitch} outside piano range"
                assert note.duration_beats > 0, "Zero or negative note duration"
                assert 0.0 < note.velocity <= 1.0, "Invalid note velocity"
                assert note.hand in ["left", "right"], "Unassigned hand"
                assert note.start_beat >= m.start_beat, "Note starts before measure"
                assert note.end_beat <= m.start_beat + m.duration_beats, "Note extends beyond measure"

    def test_fallback_audio_scheduler_dispatch_simulation(self):
        """Simulate high-precision AudioScheduler tick loop across all 16 beats of fallback score."""
        score = synthesize_fallback_score("Playback Test")
        total_beats = 16.0
        time_step = 0.05  # Simulate tick every 0.05 beats (~25ms at 120 bpm)

        dispatched_notes = set()
        active_sounding = set()

        # Step until score completion plus a small delta to allow final note offs
        current_beat = 0.0
        while current_beat <= total_beats + (time_step * 2):
            # Dispatch notes that start at this tick
            for m in score.measures:
                for idx, note in enumerate(m.notes):
                    note_id = (m.index, idx)
                    if abs(note.start_beat - current_beat) < (time_step / 2.0):
                        dispatched_notes.add(note_id)
                        active_sounding.add(note_id)
                    # Note off
                    if note.end_beat <= current_beat + 1e-6:
                        active_sounding.discard(note_id)
            current_beat += time_step

        assert len(dispatched_notes) == 32, f"Expected 32 notes dispatched, got {len(dispatched_notes)}"
        assert len(active_sounding) == 0, f"Stuck sounding notes at score completion: {active_sounding}"


# ============================================================================
# Test Suite 3: Manifest Consistency Stress Testing (8 Manifest Files)
# ============================================================================

class TestManifestConsistency:
    """Requirement 3: Stress test manifest consistency across all 8 manifest files."""

    CANONICAL_VERSION = "1.0.26"
    CANONICAL_BUILD = "10026"
    EXPECTED_DOWNLOAD_URL = "https://github.com/getsentrix/PianoGlass/releases/download/v1.0.26/PianoGlass.ipa"

    def test_manifest_01_apps_json(self):
        path = os.path.join(REPO_ROOT, "apps.json")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        app = data["apps"][0]
        assert app["version"] == self.CANONICAL_VERSION
        assert app["downloadURL"] == self.EXPECTED_DOWNLOAD_URL
        assert app["bundleIdentifier"] == "com.pianoglass.app"
        assert len(app["screenshots"]) >= 2
        assert app["iconURL"].startswith("https://")

    def test_manifest_02_altstore_json(self):
        path = os.path.join(REPO_ROOT, "altstore.json")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        app = data["apps"][0]
        assert app["version"] == self.CANONICAL_VERSION
        assert app["downloadURL"] == self.EXPECTED_DOWNLOAD_URL

    def test_manifest_03_docs_apps_json(self):
        path = os.path.join(REPO_ROOT, "docs", "apps.json")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        app = data["apps"][0]
        assert app["version"] == self.CANONICAL_VERSION
        assert app["downloadURL"] == self.EXPECTED_DOWNLOAD_URL

    def test_manifest_04_docs_altstore_json(self):
        path = os.path.join(REPO_ROOT, "docs", "altstore.json")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        app = data["apps"][0]
        assert app["version"] == self.CANONICAL_VERSION
        assert app["downloadURL"] == self.EXPECTED_DOWNLOAD_URL

    def test_manifest_05_info_plist(self):
        path = os.path.join(REPO_ROOT, "Sources", "PianoGlass", "App", "Info.plist")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "rb") as f:
            plist_data = plistlib.load(f)

        assert plist_data["CFBundleShortVersionString"] == self.CANONICAL_VERSION
        assert plist_data["CFBundleVersion"] == self.CANONICAL_BUILD
        assert plist_data["CFBundleIdentifier"] == "com.pianoglass.app"

    def test_manifest_06_project_pbxproj(self):
        path = os.path.join(REPO_ROOT, "PianoGlass.xcodeproj", "project.pbxproj")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        # Find all MARKETING_VERSION entries
        marketing_versions = re.findall(r"MARKETING_VERSION\s*=\s*([^;]+);", content)
        assert len(marketing_versions) >= 2, "Expected at least 2 MARKETING_VERSION definitions (Debug & Release)"
        for v in marketing_versions:
            assert v.strip() == self.CANONICAL_VERSION

        # Find all CURRENT_PROJECT_VERSION entries
        build_versions = re.findall(r"CURRENT_PROJECT_VERSION\s*=\s*([^;]+);", content)
        assert len(build_versions) >= 2, "Expected at least 2 CURRENT_PROJECT_VERSION definitions"
        for b in build_versions:
            assert b.strip() == self.CANONICAL_BUILD

    def test_manifest_07_settings_view_swift(self):
        path = os.path.join(REPO_ROOT, "Sources", "PianoGlass", "Views", "Settings", "SettingsView.swift")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        assert self.CANONICAL_VERSION in content, f"SettingsView.swift does not reference version {self.CANONICAL_VERSION}"

    def test_manifest_08_patch_ipa_py(self):
        path = os.path.join(REPO_ROOT, "scripts", "patch_ipa.py")
        assert os.path.exists(path), f"Missing {path}"
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        assert f'pl["CFBundleShortVersionString"] = "{self.CANONICAL_VERSION}"' in content
        assert f'pl["CFBundleVersion"] = "{self.CANONICAL_BUILD}"' in content

    def test_all_manifests_cross_consistency(self):
        """Cross-check that root and docs manifests are 100% identical in app definitions."""
        root_apps = json.load(open(os.path.join(REPO_ROOT, "apps.json"), "r", encoding="utf-8"))
        docs_apps = json.load(open(os.path.join(REPO_ROOT, "docs", "apps.json"), "r", encoding="utf-8"))
        assert root_apps["apps"] == docs_apps["apps"]
        assert root_apps["news"] == docs_apps["news"]

        root_alt = json.load(open(os.path.join(REPO_ROOT, "altstore.json"), "r", encoding="utf-8"))
        docs_alt = json.load(open(os.path.join(REPO_ROOT, "docs", "altstore.json"), "r", encoding="utf-8"))
        assert root_alt["apps"] == docs_alt["apps"]
        assert root_alt["news"] == docs_alt["news"]


# ============================================================================
# Test Suite 4: Bohemian Rhapsody Ground Truth Verification
# ============================================================================

class TestBohemianRhapsodyGroundTruth:
    """
    Requirement 4: Verify Bohemian Rhapsody ground truth:
    - measure count = 2
    - note count = 32
    - key = Bb Major (fifths: -2, mode: major)
    - simultaneous beat 0 starts across treble & bass staves
    """

    @pytest.fixture(autouse=True)
    def parse_xml(self):
        assert os.path.exists(BOHEMIAN_XML_PATH), f"Missing ground truth score: {BOHEMIAN_XML_PATH}"
        tree = ET.parse(BOHEMIAN_XML_PATH)
        self.root = tree.getroot()

    def test_root_and_schema(self):
        assert self.root.tag == "score-partwise"
        assert self.root.attrib.get("version") == "3.1"

    def test_measure_count_exactly_2(self):
        measures = self.root.findall(".//part[@id='P1']/measure")
        assert len(measures) == 2, f"Expected 2 measures, found {len(measures)}"

    def test_note_count_exactly_32(self):
        all_notes = self.root.findall(".//part[@id='P1']/measure/note")
        # Filter pitched notes (all notes in sample are pitched)
        pitched_notes = [n for n in all_notes if n.find("pitch") is not None]
        assert len(pitched_notes) == 32, f"Expected exactly 32 pitched notes, got {len(pitched_notes)}"

    def test_measure_note_distribution(self):
        measures = self.root.findall(".//part[@id='P1']/measure")
        m1_notes = [n for n in measures[0].findall("note") if n.find("pitch") is not None]
        m2_notes = [n for n in measures[1].findall("note") if n.find("pitch") is not None]
        assert len(m1_notes) == 16, f"Measure 1 expected 16 notes, got {len(m1_notes)}"
        assert len(m2_notes) == 16, f"Measure 2 expected 16 notes, got {len(m2_notes)}"

    def test_key_signature_bb_major(self):
        fifths = self.root.find(".//key/fifths")
        assert fifths is not None and fifths.text == "-2", "Expected fifths = -2"
        mode = self.root.find(".//key/mode")
        assert mode is not None and mode.text == "major", "Expected mode = major"

    def test_time_signature_and_tempo(self):
        beats = self.root.find(".//time/beats")
        beat_type = self.root.find(".//time/beat-type")
        assert beats is not None and beats.text == "4"
        assert beat_type is not None and beat_type.text == "4"

        sound = self.root.find(".//sound")
        assert sound is not None and sound.attrib.get("tempo") == "72"

    def test_simultaneous_beat_0_starts_measure_1(self):
        """
        Verify that Measure 1 contains simultaneous note starts at beat 0 on both
        Staff 1 (Treble: Bb3, D4, F4) and Staff 2 (Bass: Bb1, Bb2).
        """
        m1 = self.root.findall(".//part[@id='P1']/measure")[0]
        
        part_timeline = 0
        last_note_start = 0
        staff1_beat0_pitches = []
        staff2_beat0_pitches = []

        for elem in m1:
            if elem.tag == "note":
                is_chord = elem.find("chord") is not None
                dur_elem = elem.find("duration")
                dur = int(dur_elem.text) if dur_elem is not None else 0
                staff = elem.find("staff").text if elem.find("staff") is not None else "1"

                step = elem.find(".//pitch/step").text
                octave = elem.find(".//pitch/octave").text
                alter_elem = elem.find(".//pitch/alter")
                alter = alter_elem.text if alter_elem is not None else ""
                pitch_str = f"{step}{'b' if alter == '-1' else ''}{octave}"

                if is_chord:
                    note_start = last_note_start
                else:
                    note_start = part_timeline
                    last_note_start = note_start
                    part_timeline += dur

                if note_start == 0:
                    if staff == "1":
                        staff1_beat0_pitches.append(pitch_str)
                    elif staff == "2":
                        staff2_beat0_pitches.append(pitch_str)

            elif elem.tag == "backup":
                dur = int(elem.find("duration").text)
                part_timeline -= dur

        assert len(staff1_beat0_pitches) == 3, f"Staff 1 beat 0 expected 3 notes, got {staff1_beat0_pitches}"
        assert set(staff1_beat0_pitches) == {"Bb3", "D4", "F4"}
        assert len(staff2_beat0_pitches) == 2, f"Staff 2 beat 0 expected 2 notes, got {staff2_beat0_pitches}"
        assert set(staff2_beat0_pitches) == {"Bb1", "Bb2"}

    def test_simultaneous_beat_0_starts_measure_2(self):
        """
        Verify that Measure 2 contains simultaneous note starts at beat 0 on both
        Staff 1 (Treble: G3, Bb3, Eb4) and Staff 2 (Bass: Eb2, Eb3).
        """
        m2 = self.root.findall(".//part[@id='P1']/measure")[1]
        
        part_timeline = 0
        last_note_start = 0
        staff1_beat0_pitches = []
        staff2_beat0_pitches = []

        for elem in m2:
            if elem.tag == "note":
                is_chord = elem.find("chord") is not None
                dur_elem = elem.find("duration")
                dur = int(dur_elem.text) if dur_elem is not None else 0
                staff = elem.find("staff").text if elem.find("staff") is not None else "1"

                step = elem.find(".//pitch/step").text
                octave = elem.find(".//pitch/octave").text
                alter_elem = elem.find(".//pitch/alter")
                alter = alter_elem.text if alter_elem is not None else ""
                pitch_str = f"{step}{'b' if alter == '-1' else ''}{octave}"

                if is_chord:
                    note_start = last_note_start
                else:
                    note_start = part_timeline
                    last_note_start = note_start
                    part_timeline += dur

                if note_start == 0:
                    if staff == "1":
                        staff1_beat0_pitches.append(pitch_str)
                    elif staff == "2":
                        staff2_beat0_pitches.append(pitch_str)

            elif elem.tag == "backup":
                dur = int(elem.find("duration").text)
                part_timeline -= dur

        assert len(staff1_beat0_pitches) == 3, f"Staff 1 beat 0 expected 3 notes, got {staff1_beat0_pitches}"
        assert set(staff1_beat0_pitches) == {"G3", "Bb3", "Eb4"}
        assert len(staff2_beat0_pitches) == 2, f"Staff 2 beat 0 expected 2 notes, got {staff2_beat0_pitches}"
        assert set(staff2_beat0_pitches) == {"Eb2", "Eb3"}


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
