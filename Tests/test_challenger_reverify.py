"""
Empirical Re-verification Test Suite (Challenger Iteration 2)
Tests deep corner cases for MusicXML repair, barline notehead bulge discrimination,
and schema validity across both Swift spec and Python implementations.
"""

import re
import xml.etree.ElementTree as ET
import pytest
from PIL import Image, ImageDraw
import os
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from backend.omr_engine import repair_truncated_musicxml


class TestMusicXMLRepairEngineDeepVerification:
    """Verifies that MusicXMLRepairEngine handles all adversarial truncation modes."""

    def test_omitted_part_list_with_part_id(self):
        """Case: AI emits <part id='P1'> without <part-list>."""
        raw = """<score-partwise version="3.1">
  <part id="P1">
    <measure number="1">
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>
    </measure>
  </part>
</score-partwise>"""
        repaired = repair_truncated_musicxml(raw)
        assert repaired is not None
        root = ET.fromstring(repaired)
        # Verify part-list exists before part
        children = [elem.tag for elem in root]
        assert "part-list" in children
        assert "part" in children
        assert children.index("part-list") < children.index("part")
        # Verify no duplicate part tags
        parts = root.findall("part")
        assert len(parts) == 1
        assert len(root.findall(".//measure")) == 1

    def test_omitted_part_list_and_omitted_part_tag(self):
        """Case: AI emits raw <measure> without <part-list> or <part>."""
        raw = """<score-partwise version="3.1">
  <measure number="1">
    <note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note>
  </measure>
</score-partwise>"""
        repaired = repair_truncated_musicxml(raw)
        assert repaired is not None
        root = ET.fromstring(repaired)
        parts = root.findall("part")
        assert len(parts) == 1
        assert len(root.findall(".//measure")) == 1

    def test_truncation_mid_measure_1_minimal_envelope(self):
        """Case: Truncated inside measure 1 with open child tags."""
        raw = """<score-partwise version="3.1">
  <part id="P1">
    <measure number="1">
      <note>
        <pitch>
          <step>C</step>"""
        repaired = repair_truncated_musicxml(raw)
        assert repaired is not None
        # Must be valid, parseable XML envelope without mismatched tags
        root = ET.fromstring(repaired)
        assert root.tag == "score-partwise"
        assert root.find("part-list") is not None
        parts = root.findall("part")
        assert len(parts) == 1
        # No measures completed, so 0 measures
        assert len(root.findall(".//measure")) == 0

    def test_truncation_mid_measure_2_preserves_measure_1(self):
        """Case: Truncated in measure 2; measure 1 is preserved and unclosed tags closed."""
        raw = """<score-partwise version="3.1">
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>
    </measure>
    <measure number="2">
      <note><pitch><step>D</step>"""
        repaired = repair_truncated_musicxml(raw)
        assert repaired is not None
        root = ET.fromstring(repaired)
        assert len(root.findall(".//measure")) == 1
        parts = root.findall("part")
        assert len(parts) == 1

    def test_markdown_and_preamble_stripping(self):
        """Case: Conversational text and markdown code fences."""
        raw = """Here is the transcribed MusicXML for your score:
```xml
<score-partwise version="3.1">
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration></note>
    </measure>
  </part>
</score-partwise>
```
Hope this helps!"""
        repaired = repair_truncated_musicxml(raw)
        assert repaired is not None
        root = ET.fromstring(repaired)
        assert len(root.findall(".//measure")) == 1

    def test_complex_ampersand_sanitization(self):
        """Case: Naked & in lyric, title, mixed with legitimate &amp; and numeric entities."""
        raw = """<score-partwise version="3.1">
  <work><work-title>Fish & Chips &#x26; Rock & Roll &amp; Co.</work-title></work>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>
    </measure>
  </part>
</score-partwise>"""
        repaired = repair_truncated_musicxml(raw)
        assert repaired is not None
        root = ET.fromstring(repaired)
        title = root.find(".//work-title").text
        assert "Fish & Chips" in title
        assert "Rock & Roll" in title
        assert "Co." in title


def swift_repair_truncated_xml_exact(raw_text: str) -> str:
    """Exact 1:1 algorithmic transliteration of MusicXMLRepairEngine.swift lines 34-140."""
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

    # Swift lines 69-98:
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

    # Swift lines 101-104:
    end_score_idx = text.rfind("</score-partwise>")
    if end_score_idx != -1:
        text = text[:end_score_idx + len("</score-partwise>")]
        return text

    # Swift lines 108-122:
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


class TestSwiftMusicXMLRepairEngineExact:
    def test_swift_omitted_part_list_with_part_id(self):
        raw = """<score-partwise version="3.1">
  <part id="P1">
    <measure number="1">
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>
    </measure>
  </part>
</score-partwise>"""
        out = swift_repair_truncated_xml_exact(raw)
        root = ET.fromstring(out)
        parts = root.findall("part")
        assert len(parts) == 1, "Swift logic must not create duplicate <part> tags"
        assert root.find("part-list") is not None

    def test_swift_truncation_measure_1(self):
        raw = """<score-partwise version="3.1">
  <part id="P1">
    <measure number="1"><note><pitch><step>C</step>"""
        out = swift_repair_truncated_xml_exact(raw)
        root = ET.fromstring(out)
        assert root.tag == "score-partwise"
        assert len(root.findall("part")) == 1
        assert len(root.findall(".//measure")) == 0


class TestVisionStaffDetectorBarlineDiscrimination:
    """Verifies notehead bulge multiplier (0.95) eliminates chord stem false positives."""

    def test_notehead_bulge_rejection_at_0_95_multiplier(self):
        """Simulate chord noteheads and verify bulge detection triggers at 0.95x spacing."""
        sp = 15.0
        # Standard music engraving notehead: width ~ 1.25 * sp, height ~ 1.0 * sp
        notehead_width = 1.25 * sp
        notehead_half_h = int(sp / 2.0)
        dark_threshold = 128

        # Synthetic image with chord stem + 3 noteheads
        img = Image.new("L", (200, 200), color=255)
        draw = ImageDraw.Draw(img)

        stem_x = 100
        # Draw stem: x=100, y=50..150 (width=2)
        draw.line([(stem_x, 50), (stem_x, 150)], fill=0, width=2)
        # Draw 3 stacked chord noteheads at standard intervals (15px = 1 staff space)
        for ny in [75, 90, 105]:
            draw.ellipse(
                [(stem_x - int(notehead_width / 2), ny - notehead_half_h), (stem_x + int(notehead_width / 2), ny + notehead_half_h)],
                fill=0,
            )

        # Check bulge detection matching Swift lines 712-738:
        pix = img.load()
        width, height = img.size
        consecutive_wide_rows = 0
        max_consecutive_wide = 0

        for row in range(50, 150):
            lum = pix[stem_x, row]
            if lum < dark_threshold:
                horiz_run = 1
                lx = stem_x - 1
                while lx >= 0 and lx >= stem_x - int(sp * 1.5):
                    if pix[lx, row] < dark_threshold:
                        horiz_run += 1
                        lx -= 1
                    else:
                        break
                rx = stem_x + 1
                while rx < width and rx <= stem_x + int(sp * 1.5):
                    if pix[rx, row] < dark_threshold:
                        horiz_run += 1
                        rx += 1
                    else:
                        break

                if horiz_run >= sp * 0.95:
                    consecutive_wide_rows += 1
                    if consecutive_wide_rows > max_consecutive_wide:
                        max_consecutive_wide = consecutive_wide_rows
                else:
                    consecutive_wide_rows = 0
            else:
                consecutive_wide_rows = 0

        has_notehead_bulge = max_consecutive_wide >= sp * 0.45
        assert has_notehead_bulge, f"Expected bulge detection to be True, got max_wide={max_consecutive_wide}"

    def test_true_barline_not_rejected_by_bulge(self):
        """Simulate true thin barline and verify it does NOT trigger notehead bulge."""
        sp = 15.0
        dark_threshold = 128
        img = Image.new("L", (200, 200), color=255)
        draw = ImageDraw.Draw(img)

        bar_x = 100
        # Draw true barline (width 2)
        draw.line([(bar_x, 30), (bar_x, 170)], fill=0, width=2)

        pix = img.load()
        width, height = img.size
        consecutive_wide_rows = 0
        max_consecutive_wide = 0

        for row in range(30, 170):
            lum = pix[bar_x, row]
            if lum < dark_threshold:
                horiz_run = 1
                lx = bar_x - 1
                while lx >= 0 and lx >= bar_x - int(sp * 1.5):
                    if pix[lx, row] < dark_threshold:
                        horiz_run += 1
                        lx -= 1
                    else:
                        break
                rx = bar_x + 1
                while rx < width and rx <= bar_x + int(sp * 1.5):
                    if pix[rx, row] < dark_threshold:
                        horiz_run += 1
                        rx += 1
                    else:
                        break

                if horiz_run >= sp * 0.95:
                    consecutive_wide_rows += 1
                    if consecutive_wide_rows > max_consecutive_wide:
                        max_consecutive_wide = consecutive_wide_rows
                else:
                    consecutive_wide_rows = 0
            else:
                consecutive_wide_rows = 0

        has_notehead_bulge = max_consecutive_wide >= sp * 0.45
        assert not has_notehead_bulge, "True barline should NOT have notehead bulge"
