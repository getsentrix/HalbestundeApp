"""
PianoGlass Backend API Server
Provides high-accuracy Optical Music Recognition (OMR) transcription and MIDI synthesis.
Pipeline:
  [PDF/Image Upload] -> pdf2image (300 DPI) -> oemer / FallbackOMR -> music21 -> MIDI + MusicXML
"""

import io
import os
import uuid
import logging
from typing import Optional, Dict, Any
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from omr_engine import (
    convert_document_to_images,
    transcribe_image,
    transcribe_document,
    build_midi_and_metadata,
    OEMER_AVAILABLE,
    POPPLER_AVAILABLE,
)
import music21

logger = logging.getLogger("pianoglass.server")
logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="PianoGlass OMR Backend",
    version="1.0.0",
    description="High-accuracy PDF/Image sheet music to MusicXML and MIDI transcription server.",
)

# Enable CORS for web Tone.js player and iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory storage cache for generated scores
# score_id -> {"title": str, "midi_bytes": bytes, "musicxml_str": str, "metadata": dict}
SCORE_CACHE: Dict[str, Dict[str, Any]] = {}


@app.get("/api/health")
def health_check():
    """Health check and engine status."""
    return {
        "status": "healthy",
        "service": "PianoGlass OMR Backend",
        "oemer_available": OEMER_AVAILABLE,
        "poppler_available": POPPLER_AVAILABLE,
        "music21_version": music21.__version__,
        "cached_scores_count": len(SCORE_CACHE),
    }


@app.post("/api/transcribe")
async def transcribe_sheet_music(
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
):
    """
    Transcribes uploaded sheet music (PDF or Image) to MusicXML and Standard MIDI (.mid).
    1. Converts PDF pages to 300 DPI images (pdf2image / pypdf).
    2. Runs neural symbol segmentation (oemer) or robust fallback OMR.
    3. Parses MusicXML with music21 and exports Standard MIDI.
    4. Returns JSON with MusicXML, base64 MIDI, download URLs, and score metadata.
    """
    if not file.filename:
        raise HTTPException(status_code=400, detail="Missing filename in upload.")
        
    raw_bytes = await file.read()
    if not raw_bytes:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")
        
    if title and title.strip():
        resolved_title = title.strip()
    else:
        resolved_title = os.path.splitext(file.filename)[0].replace("_", " ").replace("-", " ").title()
    
    logger.info(f"Received upload '{file.filename}' ({len(raw_bytes)} bytes). Title: '{resolved_title}'")
    
    # 1. Convert PDF or Image into PIL images
    try:
        images = convert_document_to_images(raw_bytes, file.filename)
    except Exception as e:
        logger.error(f"Document conversion failed: {e}")
        raise HTTPException(status_code=400, detail=f"Failed to process sheet document: {str(e)}")
        
    if not images:
        raise HTTPException(status_code=400, detail="No readable pages or images found in document.")
        
    # 2. Process all pages through OMR pipeline (single or multi-page concatenation)
    try:
        musicxml_str, engine_used = transcribe_document(images, title=resolved_title)
    except Exception as e:
        logger.error(f"OMR transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"OMR processing failed: {str(e)}")
        
    # 3. Parse MusicXML and build standard MIDI + musical metadata
    try:
        score_data = build_midi_and_metadata(musicxml_str, title=resolved_title)
    except Exception as e:
        logger.error(f"Music21 synthesis failed: {e}")
        raise HTTPException(status_code=500, detail=f"MIDI export failed: {str(e)}")
        
    # 4. Generate persistent cache entry for direct downloads
    score_id = uuid.uuid4().hex[:12]
    SCORE_CACHE[score_id] = {
        "title": resolved_title,
        "midi_bytes": score_data["midi_bytes"],
        "musicxml_str": score_data["musicxml"],
        "metadata": score_data,
    }
    
    midi_download_url = f"/api/download/midi/{score_id}"
    xml_download_url = f"/api/download/musicxml/{score_id}"
    
    return {
        "id": score_id,
        "title": resolved_title,
        "status": "success",
        "engine": engine_used,
        "duration": score_data["duration"],
        "bpm": score_data["bpm"],
        "measures_count": score_data["measures_count"],
        "notes_count": score_data["notes_count"],
        "musicxml": score_data["musicxml"],
        "midi_base64": score_data["midi_base64"],
        "midi_url": midi_download_url,
        "musicxml_url": xml_download_url,
    }


@app.get("/api/download/midi/{score_id}")
def download_midi(score_id: str):
    """Downloads the transcribed score as a Standard MIDI File (.mid)."""
    if score_id not in SCORE_CACHE:
        raise HTTPException(status_code=404, detail="Score not found or expired.")
        
    item = SCORE_CACHE[score_id]
    safe_filename = "".join(c for c in item["title"] if c.isalnum() or c in (" ", "-", "_")).strip()
    safe_filename = safe_filename if safe_filename else "transcription"
    
    return Response(
        content=item["midi_bytes"],
        media_type="audio/midi",
        headers={
            "Content-Disposition": f'attachment; filename="{safe_filename}.mid"',
            "Content-Type": "audio/midi",
        },
    )


@app.get("/api/download/musicxml/{score_id}")
def download_musicxml(score_id: str):
    """Downloads the transcribed score as a MusicXML file (.musicxml)."""
    if score_id not in SCORE_CACHE:
        raise HTTPException(status_code=404, detail="Score not found or expired.")
        
    item = SCORE_CACHE[score_id]
    safe_filename = "".join(c for c in item["title"] if c.isalnum() or c in (" ", "-", "_")).strip()
    safe_filename = safe_filename if safe_filename else "transcription"
    
    return Response(
        content=item["musicxml_str"].encode("utf-8"),
        media_type="application/vnd.recordare.musicxml+xml",
        headers={
            "Content-Disposition": f'attachment; filename="{safe_filename}.musicxml"',
            "Content-Type": "application/vnd.recordare.musicxml+xml",
        },
    )


@app.get("/api/sample")
def get_sample_score():
    """Returns a ready-to-play sample transcribed score for instant testing without upload."""
    sample_title = "Bach - Prelude in C Major (BWV 846)"
    
    # Synthesize Bach Prelude in C opening measures with music21
    s = music21.stream.Score()
    s.metadata = music21.metadata.Metadata()
    s.metadata.title = sample_title
    s.metadata.composer = "J.S. Bach"
    
    p1 = music21.stream.Part(id="P1")
    p1.partName = "Right Hand"
    p2 = music21.stream.Part(id="P2")
    p2.partName = "Left Hand"
    
    # Measure 1: C - E - G - c - e - g - c - e
    m1_rh = music21.stream.Measure(number=1)
    m1_rh.append(music21.clef.TrebleClef())
    m1_rh.append(music21.meter.TimeSignature("4/4"))
    m1_rh.append(music21.key.KeySignature(0))
    m1_rh.append(music21.tempo.MetronomeMark(number=112))
    
    m1_lh = music21.stream.Measure(number=1)
    m1_lh.append(music21.clef.BassClef())
    m1_lh.append(music21.meter.TimeSignature("4/4"))
    m1_lh.append(music21.key.KeySignature(0))
    
    # Left hand bass sustained tones
    m1_lh.append([
        music21.note.Note("C3", quarterLength=2.0),
        music21.note.Note("E3", quarterLength=2.0),
    ])
    
    # Right hand arpeggio
    rh_notes = ["G3", "C4", "E4", "G4", "C5", "E5", "G4", "E4"]
    for pitch in rh_notes:
        m1_rh.append(music21.note.Note(pitch, quarterLength=0.5))
        
    # Measure 2: D minor 7
    m2_rh = music21.stream.Measure(number=2)
    m2_lh = music21.stream.Measure(number=2)
    m2_lh.append([
        music21.note.Note("C3", quarterLength=2.0),
        music21.note.Note("D3", quarterLength=2.0),
    ])
    rh_notes_2 = ["A3", "D4", "F4", "A4", "D5", "F5", "A4", "F4"]
    for pitch in rh_notes_2:
        m2_rh.append(music21.note.Note(pitch, quarterLength=0.5))
        
    p1.append([m1_rh, m2_rh])
    p2.append([m1_lh, m2_lh])
    s.insert(0, p1)
    s.insert(0, p2)
    
    import xml.etree.ElementTree as ET
    sx = music21.musicxml.m21ToXml.ScoreExporter(s)
    xml_str = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(sx.parse(), encoding="unicode")
    
    data = build_midi_and_metadata(xml_str, title=sample_title)
    sample_id = "sample_prelude_c"
    SCORE_CACHE[sample_id] = {
        "title": sample_title,
        "midi_bytes": data["midi_bytes"],
        "musicxml_str": data["musicxml"],
        "metadata": data,
    }
    
    return {
        "id": sample_id,
        "title": sample_title,
        "status": "success",
        "engine": "music21-sample",
        "duration": data["duration"],
        "bpm": data["bpm"],
        "measures_count": data["measures_count"],
        "notes_count": data["notes_count"],
        "musicxml": data["musicxml"],
        "midi_base64": data["midi_base64"],
        "midi_url": f"/api/download/midi/{sample_id}",
        "musicxml_url": f"/api/download/musicxml/{sample_id}",
    }


# Static directory setup
STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(STATIC_DIR):
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
def serve_index():
    """Serves the Web Tone.js Player."""
    index_file = os.path.join(STATIC_DIR, "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file, media_type="text/html")
    return {"message": "PianoGlass OMR Backend is running. Open /static/index.html to use the player."}


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("server:app", host="0.0.0.0", port=port, reload=False)
