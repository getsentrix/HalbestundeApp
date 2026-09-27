"""
Automated verification tests for PianoGlass OMR Backend:
- Health check
- Sample score synthesis and playback payload
- Image upload and OMR transcription (oemer / FallbackOMR)
- PDF document upload and high-resolution rendering
- MusicXML verification and MIDI binary export (MThd header)
- File download endpoints (/api/download/midi and /api/download/musicxml)
- Error handling and boundary conditions
"""

import io
import os
import sys
import base64
import pytest
from PIL import Image, ImageDraw
from fastapi.testclient import TestClient

# Add backend directory to sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from server import app
import omr_engine
import music21

client = TestClient(app)


def test_health_check():
    """Verify backend health endpoint reports status and dependencies."""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "music21_version" in data
    assert "oemer_available" in data
    assert "poppler_available" in data


def test_sample_score():
    """Verify sample endpoint returns playable Bach Prelude payload."""
    response = client.get("/api/sample")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert "Bach" in data["title"]
    assert data["duration"] > 0
    assert data["notes_count"] > 0
    assert "<score-partwise" in data["musicxml"]
    assert len(data["midi_base64"]) > 50
    assert "/api/download/midi/" in data["midi_url"]
    assert "/api/download/musicxml/" in data["musicxml_url"]


def test_transcribe_image():
    """Verify end-to-end OMR transcription of a sheet music image."""
    # Create a synthetic sheet image with staves
    img = Image.new("RGB", (800, 1000), color="white")
    draw = ImageDraw.Draw(img)
    # Draw 5 staff lines
    for y in [200, 220, 240, 260, 280]:
        draw.line([(50, y), (750, y)], fill="black", width=2)
    # Draw noteheads
    for x, y in [(150, 220), (250, 240), (350, 260), (450, 200)]:
        draw.ellipse([(x - 6, y - 5), (x + 6, y + 5)], fill="black")
        draw.line([(x + 6, y), (x + 6, y - 35)], fill="black", width=2)

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)

    response = client.post(
        "/api/transcribe",
        files={"file": ("test_sheet.png", buf.getvalue(), "image/png")},
        data={"title": "Test Etude"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["title"] == "Test Etude"
    assert data["notes_count"] > 0
    assert data["measures_count"] > 0
    assert "<score-partwise" in data["musicxml"]
    assert data["midi_base64"] is not None

    # Test downloading the generated MIDI file
    midi_res = client.get(data["midi_url"])
    assert midi_res.status_code == 200
    assert midi_res.headers["content-type"] == "audio/midi"
    # Verify standard MIDI file header MThd
    assert midi_res.content[:4] == b"MThd"

    # Test downloading the generated MusicXML file
    xml_res = client.get(data["musicxml_url"])
    assert xml_res.status_code == 200
    assert "xml" in xml_res.headers["content-type"]
    assert b"<score-partwise" in xml_res.content


def test_transcribe_pdf():
    """Verify single-page PDF upload and conversion pipeline."""
    # Generate a single-page PDF containing a sheet image
    img = Image.new("RGB", (600, 800), color="white")
    draw = ImageDraw.Draw(img)
    for y in [150, 170, 190, 210, 230]:
        draw.line([(40, y), (560, y)], fill="black", width=2)

    pdf_buf = io.BytesIO()
    img.save(pdf_buf, format="PDF")
    pdf_bytes = pdf_buf.getvalue()

    response = client.post(
        "/api/transcribe",
        files={"file": ("score_document.pdf", pdf_bytes, "application/pdf")},
        data={"title": "PDF Sonata"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert "PDF Sonata" in data["title"]
    assert len(data["midi_base64"]) > 0


def test_transcribe_multipage_pdf():
    """Verify multi-page PDF upload stitches all pages into a unified score."""
    img1 = Image.new("RGB", (600, 800), color="white")
    draw1 = ImageDraw.Draw(img1)
    for y in [150, 170, 190, 210, 230]:
        draw1.line([(40, y), (560, y)], fill="black", width=2)

    img2 = Image.new("RGB", (600, 800), color="white")
    draw2 = ImageDraw.Draw(img2)
    for y in [180, 200, 220, 240, 260]:
        draw2.line([(40, y), (560, y)], fill="black", width=2)

    pdf_buf = io.BytesIO()
    img1.save(pdf_buf, format="PDF", save_all=True, append_images=[img2])
    pdf_bytes = pdf_buf.getvalue()

    response = client.post(
        "/api/transcribe",
        files={"file": ("multipage_etude.pdf", pdf_bytes, "application/pdf")},
        data={"title": "Two Page Etude"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["title"] == "Two Page Etude"
    assert data["measures_count"] >= 8  # 2 pages of measures concatenated
    assert data["notes_count"] >= 30
    assert len(data["midi_base64"]) > 0


def test_merge_music21_scores_direct():
    """Verify merge_music21_scores sequences measures and preserves all parts."""
    s1 = music21.stream.Score()
    p1 = music21.stream.Part(id="P1")
    p1.partName = "Right Hand"
    m1 = music21.stream.Measure(1)
    m1.append(music21.note.Note("C4", quarterLength=4))
    p1.append(m1)
    s1.append(p1)

    s2 = music21.stream.Score()
    p2 = music21.stream.Part(id="P1")
    p2.partName = "Right Hand"
    m2 = music21.stream.Measure(1)
    m2.append(music21.note.Note("G4", quarterLength=4))
    p2.append(m2)
    s2.append(p2)

    merged = omr_engine.merge_music21_scores([s1, s2], title="Direct Merge Test")
    assert len(merged.parts) == 1
    measures = list(merged.parts[0].getElementsByClass(music21.stream.Measure))
    assert len(measures) == 2
    assert measures[0].number == 1
    assert measures[1].number == 2
    assert len(merged.flatten().notes) == 2


def test_midi_tempo_meta_event():
    """Verify that build_midi_and_metadata injects SET_TEMPO event into MIDI track 0."""
    xml_str = omr_engine.FallbackOMR.process_image(Image.new("RGB", (200, 200), "white"), title="Tempo Test")
    meta = omr_engine.build_midi_and_metadata(xml_str, title="Tempo Test")
    
    # Parse MIDI file bytes
    mf = music21.midi.MidiFile()
    mf.readstr(meta["midi_bytes"])
    
    # Track 0 should contain a SET_TEMPO event
    has_tempo_event = False
    for event in mf.tracks[0].events:
        event_name = getattr(event.type, "name", str(event.type))
        if event_name == "SET_TEMPO" or event.type == 0x51:
            has_tempo_event = True
            break
    assert has_tempo_event, "MIDI file missing SET_TEMPO meta-event in track 0"


def test_fallback_omr_direct():
    """Directly test FallbackOMR processor and music21 compatibility."""
    img = Image.new("RGB", (700, 900), color="white")
    xml_str = omr_engine.FallbackOMR.process_image(img, title="Fallback Test")
    assert "<score-partwise" in xml_str
    
    # Verify music21 can parse and convert back to MIDI
    meta = omr_engine.build_midi_and_metadata(xml_str, title="Fallback Test")
    assert meta["notes_count"] >= 16
    assert meta["midi_bytes"][:4] == b"MThd"
    assert meta["duration"] > 0


def test_error_handling():
    """Test boundary error cases (empty uploads, missing files, corrupted files, invalid IDs)."""
    # Empty upload
    res = client.post(
        "/api/transcribe",
        files={"file": ("empty.png", b"", "image/png")},
    )
    assert res.status_code == 400

    # Corrupted image bytes
    res_corrupt = client.post(
        "/api/transcribe",
        files={"file": ("corrupt.png", b"NOT_A_VALID_IMAGE_DATA_12345", "image/png")},
    )
    assert res_corrupt.status_code == 400

    # Non-existent score downloads
    res_midi = client.get("/api/download/midi/non_existent_id")
    assert res_midi.status_code == 404

    res_xml = client.get("/api/download/musicxml/non_existent_id")
    assert res_xml.status_code == 404


def test_serve_web_player():
    """Verify that the FastAPI app serves the Tone.js Web Player."""
    res = client.get("/")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    assert "Tone.js" in res.text
    assert "piano-keys" in res.text
    assert "PianoGlass OMR" in res.text
    assert "tempoSlider" in res.text


def test_musicxml_schema_validity():
    """Verify generated MusicXML adheres to XML specification and contains required tags."""
    import xml.etree.ElementTree as ET
    img = Image.new("RGB", (400, 400), color="white")
    xml_str = omr_engine.FallbackOMR.process_image(img, title="Schema Test")
    
    # Must parse without xml.etree.ElementTree.ParseError
    root = ET.fromstring(xml_str)
    assert root.tag == "score-partwise"
    part_list = root.find("part-list")
    assert part_list is not None
    parts = root.findall("part")
    assert len(parts) >= 1
    # Check measure and attributes
    measure = parts[0].find("measure")
    assert measure is not None
    assert measure.find("note") is not None


def test_health_check_engines():
    """Verify health check reports all engine tiers."""
    res = client.get("/api/health")
    assert res.status_code == 200
    data = res.json()
    assert "audiveris_available" in data
    assert "cloud_ai_available" in data
    assert "oemer_available" in data
    assert "poppler_available" in data


def test_advanced_vision_omr_features():
    """Verify AdvancedVisionOMR recognizes both solid and hollow noteheads with exact pitches and durations."""
    # Create image with staves, barlines, solid notehead (quarter note) and hollow notehead (half note)
    img = Image.new("RGB", (800, 600), color="white")
    draw = ImageDraw.Draw(img)
    # Staves
    for y in [150, 170, 190, 210, 230]:
        draw.line([(50, y), (750, y)], fill="black", width=2)
    # Barlines at x=50, x=400, x=750
    for bx in [50, 400, 750]:
        draw.line([(bx, 150), (bx, 230)], fill="black", width=2)
    # Measure 1: Solid notehead (quarter note) at x=200, y=190 (line 3 = B4)
    draw.ellipse([(193, 185), (207, 195)], fill="black")
    draw.line([(207, 190), (207, 155)], fill="black", width=2)
    # Measure 2: Hollow notehead (half note) at x=550, y=210 (line 2 = G4)
    draw.ellipse([(542, 205), (558, 215)], outline="black", width=2)
    draw.line([(558, 210), (558, 175)], fill="black", width=2)

    xml_str = omr_engine.AdvancedVisionOMR.process_image(img, title="Features Test")
    assert "<score-partwise" in xml_str
    meta = omr_engine.build_midi_and_metadata(xml_str, title="Features Test")
    assert meta["notes_count"] >= 2
    assert meta["measures_count"] == 2
    assert meta["duration"] > 0

    # Parse and verify exact pitches and rhythm durations
    parsed_score = music21.converter.parseData(xml_str, format="musicxml")
    p1 = parsed_score.parts[0]
    measures = list(p1.getElementsByClass(music21.stream.Measure))
    assert len(measures) == 2

    # Measure 1 should contain B4 (MIDI 71) with quarterLength 1.0 (quarter note)
    m1_notes = list(measures[0].notes)
    assert len(m1_notes) == 1
    assert m1_notes[0].pitch.midi == 71  # B4
    assert m1_notes[0].duration.quarterLength == 1.0

    # Measure 2 should contain G4 (MIDI 67) with quarterLength 2.0 (half note)
    m2_notes = list(measures[1].notes)
    assert len(m2_notes) == 1
    assert m2_notes[0].pitch.midi == 67  # G4
    assert m2_notes[0].duration.quarterLength == 2.0


def test_chord_and_polyphony_recognition():
    """Verify AdvancedVisionOMR recognizes vertically stacked noteheads as polyphonic chords."""
    img = Image.new("RGB", (800, 600), color="white")
    draw = ImageDraw.Draw(img)
    # Staves
    for y in [150, 170, 190, 210, 230]:
        draw.line([(50, y), (750, y)], fill="black", width=2)
    for bx in [50, 400, 750]:
        draw.line([(bx, 150), (bx, 230)], fill="black", width=2)
    # Measure 1: Chord E4 (y=230, line 1) and B4 (y=190, line 3) with stem
    draw.ellipse([(193, 225), (207, 235)], fill="black")
    draw.ellipse([(193, 185), (207, 195)], fill="black")
    draw.line([(207, 230), (207, 155)], fill="black", width=2)

    xml_str = omr_engine.AdvancedVisionOMR.process_image(img, title="Chord Test")
    parsed_score = music21.converter.parseData(xml_str, format="musicxml")
    p1 = parsed_score.parts[0]
    m1 = p1.getElementsByClass(music21.stream.Measure)[0]

    chord_objs = list(m1.getElementsByClass(music21.chord.Chord))
    assert len(chord_objs) == 1
    chord_pitches = [p.midi for p in chord_objs[0].pitches]
    assert 64 in chord_pitches  # E4
    assert 71 in chord_pitches  # B4
    assert chord_objs[0].duration.quarterLength == 1.0


def test_accidental_sharp_recognition():
    """Verify AdvancedVisionOMR detects sharp (#) without false positives from staff lines."""
    img = Image.new("RGB", (800, 600), color="white")
    draw = ImageDraw.Draw(img)
    for y in [150, 170, 190, 210, 230]:
        draw.line([(50, y), (750, y)], fill="black", width=2)
    for bx in [50, 400, 750]:
        draw.line([(bx, 150), (bx, 230)], fill="black", width=2)
    # Measure 2: G#4 (sharp at x=530, hollow notehead at x=550, y=210)
    draw.ellipse([(542, 205), (558, 215)], outline="black", width=2)
    draw.line([(558, 210), (558, 175)], fill="black", width=2)
    # Sharp glyph
    draw.line([(527, 196), (527, 224)], fill="black", width=2)
    draw.line([(533, 196), (533, 224)], fill="black", width=2)
    draw.line([(524, 206), (536, 204)], fill="black", width=2)
    draw.line([(524, 216), (536, 214)], fill="black", width=2)

    xml_str = omr_engine.AdvancedVisionOMR.process_image(img, title="Sharp Test")
    parsed_score = music21.converter.parseData(xml_str, format="musicxml")
    p1 = parsed_score.parts[0]
    m2 = p1.getElementsByClass(music21.stream.Measure)[1]
    m2_notes = list(m2.notes)
    assert len(m2_notes) == 1
    # G#4 is MIDI 68
    assert m2_notes[0].pitch.midi == 68
    assert m2_notes[0].duration.quarterLength == 2.0


