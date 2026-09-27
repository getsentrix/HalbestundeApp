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

