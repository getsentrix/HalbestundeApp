#!/usr/bin/env python3
"""
Auditor Re-verification 1: Independent Forensic Test Suite
Directly tests edge cases against backend/omr_engine.py and simulated MusicXMLRepairEngine.swift.
"""

import sys
import os
import re
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from backend.omr_engine import repair_truncated_musicxml

def swift_repair_exact(raw_text: str) -> str:
    """Exact transcription of Swift MusicXMLRepairEngine.swift logic."""
    text = raw_text.strip()
    if not text:
        return ""
    if "```xml" in text:
        text = text.split("```xml", 1)[1]
    elif "```" in text:
        text = text.split("```", 1)[1]
    if "```" in text:
        text = text.split("```", 1)[0]
    text = text.strip()

    if "<?xml" in text:
        text = text[text.find("<?xml"):]
    elif "<score-partwise" in text:
        text = text[text.find("<score-partwise"):]

    text = re.sub(r"&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)", "&amp;", text)

    if "<score-partwise" not in text:
        if "<measure" in text:
            text = (
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<score-partwise version="3.1">\n'
                '  <part-list>\n'
                '    <score-part id="P1"><part-name>Piano</part-name></score-part>\n'
                '  </part-list>\n'
                '  <part id="P1">\n' + text
            )
        else:
            return ""

    if "<part-list>" not in text and "<measure" in text:
        first_m = text.find("<measure")
        part_idx = -1
        p_space = text.find("<part ")
        p_tag = text.find("<part>")
        if p_space != -1 and p_space < first_m:
            part_idx = p_space
        if p_tag != -1 and p_tag < first_m:
            if part_idx != -1:
                if p_tag < part_idx:
                    part_idx = p_tag
            else:
                part_idx = p_tag

        if part_idx != -1:
            prefix = text[:part_idx]
            suffix = text[part_idx:]
            text = f"{prefix}\n  <part-list>\n    <score-part id=\"P1\"><part-name>Piano</part-name></score-part>\n  </part-list>\n{suffix}"
        else:
            prefix = text[:first_m]
            suffix = text[first_m:]
            text = f"{prefix}\n  <part-list>\n    <score-part id=\"P1\"><part-name>Piano</part-name></score-part>\n  </part-list>\n  <part id=\"P1\">\n{suffix}"

    end_score_idx = text.rfind("</score-partwise>")
    if end_score_idx != -1:
        text = text[:end_score_idx + len("</score-partwise>")]
        return text

    last_m_end = text.rfind("</measure>")
    if last_m_end == -1:
        if "<measure" in text:
            return (
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<score-partwise version="3.1">\n'
                '  <part-list>\n'
                '    <score-part id="P1"><part-name>Piano</part-name></score-part>\n'
                '  </part-list>\n'
                '  <part id="P1"></part>\n'
                '</score-partwise>\n'
            )
        return ""

    repaired = text[:last_m_end + len("</measure>")]
    open_parts = repaired.count("<part ") + repaired.count("<part>")
    close_parts = repaired.count("</part>")
    if open_parts > close_parts:
        repaired += "\n  </part>"
    if "</score-partwise>" not in repaired:
        repaired += "\n</score-partwise>"
    return repaired


def run_independent_checks():
    print("Running independent forensic checks...")

    # Edge Case 1: Multiple complete measures followed by truncated measure
    tc1 = """
    <score-partwise version="3.1">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1"><note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note></measure>
        <measure number="2"><note><pitch><step>D</step><octave>4</octave></pitch><duration>4</duration></note></measure>
        <measure number="3"><note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note></measure>
        <measure number="4"><note><pitch><step>F</step><octave>4</octave></pitch>
    """
    rep_py1 = repair_truncated_musicxml(tc1)
    rep_sw1 = swift_repair_exact(tc1)
    root_py1 = ET.fromstring(rep_py1)
    root_sw1 = ET.fromstring(rep_sw1)
    assert len(root_py1.findall(".//measure")) == 3, "Expected exactly 3 measures in Python"
    assert len(root_sw1.findall(".//measure")) == 3, "Expected exactly 3 measures in Swift"
    print("  PASS Edge Case 1: 3 completed measures recovered, truncated measure 4 stripped cleanly.")

    # Edge Case 2: Deeply nested unclosed tags inside measure 1 with no complete measures
    tc2 = """
    <score-partwise version="3.1">
      <part id="P1">
        <measure number="1">
          <attributes><divisions>4</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
          <note>
            <pitch>
              <step>A</step>
              <alter>1</alter>
              <octave>
    """
    rep_py2 = repair_truncated_musicxml(tc2)
    rep_sw2 = swift_repair_exact(tc2)
    root_py2 = ET.fromstring(rep_py2)
    root_sw2 = ET.fromstring(rep_sw2)
    assert root_py2.tag == "score-partwise"
    assert root_sw2.tag == "score-partwise"
    assert len(root_py2.findall("part")) == 1
    assert len(root_sw2.findall("part")) == 1
    assert root_py2.find("part-list") is not None
    assert root_sw2.find("part-list") is not None
    print("  PASS Edge Case 2: Deeply nested unclosed tags in measure 1 synthesized valid envelope.")

    # Edge Case 3: Naked XML with no score-partwise and no part-list, 2 measures complete
    tc3 = """
    <measure number="1"><note><pitch><step>C</step></pitch></note></measure>
    <measure number="2"><note><pitch><step>D</step></pitch></note></measure>
    <measure number="3"><note><pitch><step>E
    """
    rep_py3 = repair_truncated_musicxml(tc3)
    rep_sw3 = swift_repair_exact(tc3)
    root_py3 = ET.fromstring(rep_py3)
    root_sw3 = ET.fromstring(rep_sw3)
    assert len(root_py3.findall(".//measure")) == 2
    assert len(root_sw3.findall(".//measure")) == 2
    assert root_py3.find("part-list") is not None
    assert root_sw3.find("part-list") is not None
    assert len(root_py3.findall("part")) == 1
    assert len(root_sw3.findall("part")) == 1
    print("  PASS Edge Case 3: Raw measures synthesized envelope and recovered 2 complete measures.")

    # Edge Case 4: Ampersands in attributes and text
    tc4 = """
    <score-partwise version="3.1">
      <work><work-title>Me & You &amp; Them & Everyone</work-title></work>
      <part-list><score-part id="P1"><part-name>Piano & Keys</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1"><note><pitch><step>C</step></pitch></note></measure>
      </part>
    </score-partwise>
    """
    rep_py4 = repair_truncated_musicxml(tc4)
    rep_sw4 = swift_repair_exact(tc4)
    root_py4 = ET.fromstring(rep_py4)
    root_sw4 = ET.fromstring(rep_sw4)
    assert root_py4.find(".//work-title").text == "Me & You & Them & Everyone"
    assert root_sw4.find(".//work-title").text == "Me & You & Them & Everyone"
    print("  PASS Edge Case 4: Entities escaped without double-escaping &amp;.")

    print("\nALL INDEPENDENT FORENSIC CHECKS PASSED EMPIRICALLY!")

if __name__ == "__main__":
    run_independent_checks()
