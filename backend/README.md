# PianoGlass OMR Backend

High-accuracy Optical Music Recognition (OMR) and MIDI synthesis service for **PianoGlass**.

Replaces naive heuristic edge detection with an end-to-end deep learning and symbolic music pipeline:

```
[PDF / Image Upload]
         ↓
    pdf2image (300 DPI high-resolution rendering)
         ↓
      oemer (Neural symbol segmentation → MusicXML)
         ↓
      music21 (MusicXML parsing & polyphonic structure)
         ↓
  Standard MIDI (.mid) + MusicXML (.musicxml) + Base64
         ↓
[Web Tone.js Player / iOS ScorePlayerView]
```

---

## ⚡ Quick Start

### 1. Local Setup

```bash
# From repository root
cd backend

# Install Python requirements
pip install -r requirements.txt

# Start the FastAPI server
uvicorn server:app --host 0.0.0.0 --port 8000 --reload
```

Open **`http://localhost:8000`** in your browser to launch the Web Tone.js Player.

---

### 2. Docker Setup (Recommended for Full Production OMR)

The Docker container includes `poppler-utils` and pre-configured deep learning libraries for `oemer`:

```bash
cd backend
docker build -t pianoglass-omr .
docker run -d -p 8000:8000 --name pianoglass-omr-server pianoglass-omr
```

Health check:
```bash
curl http://localhost:8000/api/health
```

---

## 🎹 Pipeline Components

1. **Document Ingestion (`omr_engine.convert_document_to_images`)**:
   - Accepts multi-page PDFs or images (PNG, JPG, TIFF, WebP).
   - Renders PDF pages to crisp **300 DPI** PNGs with `pdf2image`.
   - Includes automatic `pypdf` fallback for environments where system poppler is not yet installed.

2. **Neural OMR (`omr_engine.transcribe_document` / `transcribe_image`)**:
   - Invokes `oemer` ([BreezeWhite/oemer](https://github.com/BreezeWhite/oemer)) deep learning models (ONNX runtime) for stave, clef, notehead, and rhythm segmentation into MusicXML.
   - **Multi-Page Concatenation (`merge_music21_scores`)**: Automatically recognizes every page of multi-page scores and merges parts and measures sequentially into a single continuous score.
   - **Graceful Fallback Mode**: If `oemer` models are downloading or running on low-resource hardware without GPU, the server automatically uses `FallbackOMR` (pure-Python image morphology + staff line projection) so uploads never fail.

3. **Symbolic Synthesis (`omr_engine.build_midi_and_metadata`)**:
   - Parses the MusicXML stream via `music21`.
   - Computes exact duration, tempo (BPM), and polyphonic part layout.
   - Exports standard **SMF Format 1 MIDI (.mid)** bytes with embedded `SET_TEMPO` meta-events and base64 strings.

4. **Web Tone.js Player (`backend/static/index.html`)**:
   - Minimalist Feather-style dark interface.
   - Drag & drop document uploader with real-time stage progress feedback.
   - Interactive Tone.js synthesizer with play/pause, scrub bar, tempo slider (40–240 BPM), and 3-octave piano visualizer.
   - Direct download buttons for `.mid` and `.musicxml`.

---

## 📡 API Reference

### `POST /api/transcribe`
Uploads a sheet music document (PDF or Image) and returns transcribed notation and audio. Supports single and multi-page documents.

**Request**:
- `Content-Type: multipart/form-data`
- `file`: Document file (`.pdf`, `.png`, `.jpg`, `.tiff`)
- `title` *(optional)*: Title of the piece

**Response** (`200 OK`):
```json
{
  "id": "7f8b9a2c1d0e",
  "title": "Chopin Nocturne Op 9 No 2",
  "status": "success",
  "engine": "oemer",
  "duration": 28.5,
  "bpm": 110.0,
  "measures_count": 16,
  "notes_count": 64,
  "musicxml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>...",
  "midi_base64": "TVRoZAAAAAYAAQADAGRNVHJr...",
  "midi_url": "/api/download/midi/7f8b9a2c1d0e",
  "musicxml_url": "/api/download/musicxml/7f8b9a2c1d0e"
}
```

---

### `GET /api/download/midi/{id}`
Downloads the standard MIDI file (`audio/midi`) for opening in DAWs, Tone.js, or MuseScore.

---

### `GET /api/download/musicxml/{id}`
Downloads the standard MusicXML file (`application/vnd.recordare.musicxml+xml`) for opening in Finale, Sibelius, or MuseScore.

---

### `GET /api/sample`
Returns a ready-to-play sample score (Bach Prelude in C Major) for immediate testing.

---

### `GET /api/health`
Health check reporting engine readiness:
```json
{
  "status": "healthy",
  "service": "PianoGlass OMR Backend",
  "oemer_available": true,
  "poppler_available": true,
  "music21_version": "10.5.0",
  "cached_scores_count": 3
}
```

---

## 📱 Connecting to the iOS App (PianoGlass)

1. Ensure the backend server is running on `http://localhost:8000` (or `http://<your-lan-ip>:8000` for physical devices).
2. Launch **PianoGlass** on iOS.
3. Tap **Settings** (gear icon) → **Scanner & Recognition**.
4. Enable **Use OMR Backend Server** and verify the server URL is set to `http://localhost:8000`.
5. In the **Scan** tab or file importer, scan or import any sheet music.
6. The app transmits the document to `/api/transcribe`, receives high-accuracy MusicXML, and immediately launches into **`ScorePlayerView`** for waterfall and keyboard practice!

---

## 🧪 Running Automated Tests

```bash
pytest Tests/test_backend.py -v
```
