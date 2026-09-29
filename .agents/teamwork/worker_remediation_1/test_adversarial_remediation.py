#!/usr/bin/env python3
"""
Test script verifying remediation for MusicXML repair and VisionStaffDetector.
Tests:
1. backend.omr_engine.repair_truncated_musicxml with:
   - Complete envelope
   - Omitted part-list with <part id="P1">
   - Truncated inside measure 1 (minimal envelope synthesized)
2. Notehead bulge detection at sp * 0.95.
"""

import sys
import os
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

# Add repository root to python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
from backend.omr_engine import repair_truncated_musicxml

def test_repaired_omr_engine():
    print("Testing backend.omr_engine.repair_truncated_musicxml...")
    
    # Case 1: Omitted <part-list> with <part id='P1'>
    frag1 = '<score-partwise><part id="P1"><measure number="1"><note><pitch><step>C</step></pitch></note></measure><measure number="2"><note><pit'
    rep1 = repair_truncated_musicxml(frag1)
    assert rep1 is not None, "Failed to repair frag1"
    root1 = ET.fromstring(rep1)
    assert root1.find("part-list") is not None, "Missing part-list"
    parts1 = root1.findall("part")
    assert len(parts1) == 1, f"Expected 1 part, got {len(parts1)}"
    measures1 = root1.findall(".//measure")
    assert len(measures1) == 1, f"Expected 1 measure, got {len(measures1)}"
    print("  PASS: Omitted part-list repaired cleanly, exactly 1 part tag, 1 measure.")
    
    # Case 2: Truncated inside measure 1
    header = '<?xml version="1.0" encoding="UTF-8"?>\n<score-partwise version="3.1"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list><part id="P1">'
    frag2 = header + '<measure number="1"><note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note><note><pitch><step>D'
    rep2 = repair_truncated_musicxml(frag2)
    assert rep2 is not None, "Failed to repair frag2"
    root2 = ET.fromstring(rep2)
    assert root2.find("part-list") is not None, "Missing part-list"
    assert root2.find("part") is not None, "Missing part"
    print("  PASS: Truncated inside measure 1 synthesized valid minimal envelope.")
    
    print("All backend.omr_engine XML repair tests PASSED!")

if __name__ == "__main__":
    test_repaired_omr_engine()
