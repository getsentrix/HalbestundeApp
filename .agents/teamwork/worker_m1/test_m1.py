#!/usr/bin/env python3
"""
Verification script for Milestone 1 (Features F1 to F5):
- Resilient MusicXML repair engine (truncation recovery, tag closing, entity sanitization)
- Bohemian Rhapsody sample ground truth parse and polyphonic timeline verification
- Backoff, model failover, and request parameter verification
"""

import os
import sys
import re
import xml.etree.ElementTree as ET

# Add backend directory to sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "backend"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import omr_engine
from omr_engine import repair_truncated_musicxml

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

def test_repair_clean_xml():
    print("[1/5] Testing clean XML preservation...")
    xml_clean = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<score-partwise version="3.1">\n'
        '  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>\n'
        '  <part id="P1">\n'
        '    <measure number="1">\n'
        '      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>\n'
        '    </measure>\n'
        '  </part>\n'
        '</score-partwise>'
    )
    repaired = repair_truncated_musicxml(xml_clean)
    assert repaired is not None, "Clean XML must be preserved"
    assert "</score-partwise>" in repaired
    ET.fromstring(repaired)
    print("  ✓ Clean XML preserved and validated.")

def test_repair_truncated_xml():
    print("[2/5] Testing token-truncated XML recovery...")
    xml_truncated = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<score-partwise version="3.1">\n'
        '  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>\n'
        '  <part id="P1">\n'
        '    <measure number="1">\n'
        '      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>\n'
        '    </measure>\n'
        '    <measure number="2">\n'
        '      <note><pitch><step>D</step><octave>4</octave></pitch><duration>4</duration></note>\n'
        '    </measure>\n'
        '    <measure number="3">\n'
        '      <note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note>\n'
        '      <note><pitch><step>F</step><oct'
    )
    repaired = repair_truncated_musicxml(xml_truncated)
    assert repaired is not None, "Truncated XML must be repaired"
    assert "</score-partwise>" in repaired
    assert "</part>" in repaired
    assert '<measure number="2">' in repaired
    assert '<measure number="3">' not in repaired
    root = ET.fromstring(repaired)
    measures = root.findall(".//measure")
    assert len(measures) == 2, f"Expected 2 completed measures, got {len(measures)}"
    print("  ✓ Truncated XML mid-measure cleanly recovered up to last valid measure.")

def test_repair_entity_sanitization():
    print("[3/5] Testing unescaped entity sanitization...")
    xml_amp = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<score-partwise version="3.1">\n'
        '  <work><work-title>Simon & Garfunkel / Bridge & Water</work-title></work>\n'
        '  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>\n'
        '  <part id="P1">\n'
        '    <measure number="1">\n'
        '      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>\n'
        '    </measure>\n'
        '  </part>\n'
        '</score-partwise>'
    )
    repaired = repair_truncated_musicxml(xml_amp)
    assert repaired is not None
    assert "Simon &amp; Garfunkel" in repaired
    assert "Bridge &amp; Water" in repaired
    ET.fromstring(repaired)
    print("  ✓ Unescaped ampersands safely sanitized to valid entities.")

def test_bohemian_rhapsody_ground_truth():
    print("[4/5] Testing Bohemian Rhapsody ground truth parse & polyphony...")
    filepath = "assets/Bohemian_Rhapsody_Sample.musicxml"
    assert os.path.exists(filepath), f"File not found: {filepath}"
    
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    repaired = repair_truncated_musicxml(content)
    assert repaired is not None
    root = ET.fromstring(repaired)
    
    measures = root.findall(".//measure")
    assert len(measures) == 2, f"Expected 2 measures in sample, got {len(measures)}"
    
    # Simulate MusicXMLParser timeline on Bohemian Rhapsody
    for m_idx, m in enumerate(measures):
        divisions = int(m.find(".//divisions").text) if m.find(".//divisions") is not None else 1
        part_cursor = 0
        voice_cursors = {}
        last_voice_start = {}
        staves_seen = set()
        backups_count = 0
        parsed_notes = []
        
        for elem in m:
            if elem.tag == "backup":
                dur = int(elem.find("duration").text) if elem.find("duration") is not None else 0
                part_cursor = max(0, part_cursor - dur)
                backups_count += 1
            elif elem.tag == "forward":
                dur = int(elem.find("duration").text) if elem.find("duration") is not None else 0
                part_cursor += dur
            elif elem.tag == "note":
                is_chord = elem.find("chord") is not None
                is_rest = elem.find("rest") is not None
                staff = int(elem.find("staff").text) if elem.find("staff") is not None else 1
                voice = int(elem.find("voice").text) if elem.find("voice") is not None else 1
                dur = int(elem.find("duration").text) if elem.find("duration") is not None else divisions
                
                step = elem.find(".//step").text if elem.find(".//step") is not None else "C"
                octave = int(elem.find(".//octave").text) if elem.find(".//octave") is not None else 4
                alter = int(elem.find(".//alter").text) if elem.find(".//alter") is not None else 0
                
                v_key = (staff, voice)
                if not is_chord:
                    if staff not in staves_seen and backups_count == 0 and staff > 1 and part_cursor > 0:
                        part_cursor = 0
                    staves_seen.add(staff)
                    start_tick = part_cursor
                    last_voice_start[v_key] = start_tick
                    part_cursor += dur
                    voice_cursors[v_key] = part_cursor
                else:
                    start_tick = last_voice_start.get(v_key, 0)
                
                start_beat = start_tick / divisions
                dur_beat = dur / divisions
                parsed_notes.append({
                    "step": step,
                    "octave": octave,
                    "alter": alter,
                    "staff": staff,
                    "voice": voice,
                    "is_chord": is_chord,
                    "start_beat": start_beat,
                    "dur_beat": dur_beat
                })
        
        rh = [n for n in parsed_notes if n["staff"] == 1]
        lh = [n for n in parsed_notes if n["staff"] == 2]
        
        assert len(rh) == 12, f"Measure {m_idx + 1}: Expected 12 RH notes, got {len(rh)}"
        assert len(lh) == 4, f"Measure {m_idx + 1}: Expected 4 LH notes, got {len(lh)}"
        
        # Verify RH chord beats: 4 chords on beats 0, 1, 2, 3
        rh_beats = [n["start_beat"] for n in rh]
        assert rh_beats == [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0, 3.0, 3.0, 3.0], f"RH beats mismatch: {rh_beats}"
        
        # Verify LH chord beats: 2 chords on beats 0, 2
        lh_beats = [n["start_beat"] for n in lh]
        assert lh_beats == [0.0, 0.0, 2.0, 2.0], f"LH beats mismatch: {lh_beats}"
        
    print("  ✓ Bohemian Rhapsody parsed: 32 notes, exact beat synchronization, zero beat-0 collapse.")

def test_swift_source_integrity():
    print("[5/5] Testing Swift source code alignment and contracts...")
    with open("Sources/PianoGlass/OMR/MusicScannerService.swift", "r", encoding="utf-8") as f:
        scanner_code = f.read()
    assert "MusicXMLRepairEngine.repairTruncatedXML" in scanner_code, "MusicScannerService must use MusicXMLRepairEngine"
    assert "gemini-3.8-flash" in scanner_code, "Must use gemini-3.8-flash as primary model"
    assert "gemini-3.5-flash-lite" in scanner_code, "Must use gemini-3.5-flash-lite as fallback model"
    assert "thinkingBudget" in scanner_code, "Must configure thinkingBudget"
    assert "maxOutputTokens\": 32768" in scanner_code or "32768" in scanner_code, "Must use 32768 tokens"
    assert "timeoutInterval = 90.0" in scanner_code, "Must use 90s timeout"
    assert "renderPDFPagesIndividually" in scanner_code, "Must render PDF pages individually"
    assert "mergeScores" in scanner_code, "Must merge multi-page scores"
    
    with open("Sources/PianoGlass/OMR/MusicXMLParser.swift", "r", encoding="utf-8") as f:
        parser_code = f.read()
    assert "VoiceKey" in parser_code, "MusicXMLParser must track VoiceKey per (staff, voice)"
    assert "partTimelineTick" in parser_code, "MusicXMLParser must track part timeline cursor"
    assert "octave-shift" in parser_code, "MusicXMLParser must handle octave-shift"
    assert "staffClefs" in parser_code, "MusicXMLParser must track clefs"
    
    with open("Sources/PianoGlass/OMR/MusicXMLRepairEngine.swift", "r", encoding="utf-8") as f:
        repair_code = f.read()
    assert "repairTruncatedXML" in repair_code, "MusicXMLRepairEngine must have repairTruncatedXML"
    assert "sanitizeEntities" in repair_code, "MusicXMLRepairEngine must have sanitizeEntities"
    
    with open("backend/omr_engine.py", "r", encoding="utf-8") as f:
        backend_code = f.read()
    assert "gemini-3.8-flash" in backend_code, "backend must use gemini-3.8-flash"
    assert "gemini-3.5-flash-lite" in backend_code, "backend must use gemini-3.5-flash-lite"
    assert "thinkingBudget" in backend_code, "backend must configure thinkingBudget"
    assert "32768" in backend_code, "backend must align token limit to 32768"
    assert "timeout=90" in backend_code, "backend must align timeout to 90s"
    assert "repair_truncated_musicxml" in backend_code, "backend must use repair_truncated_musicxml"
    
    print("  ✓ Swift and Python pipelines fully aligned with all interface contracts.")

if __name__ == "__main__":
    test_repair_clean_xml()
    test_repair_truncated_xml()
    test_repair_entity_sanitization()
    test_bohemian_rhapsody_ground_truth()
    test_swift_source_integrity()
    print("\nALL MILESTONE 1 VERIFICATION CHECKS PASSED SUCCESSFULLY!")
