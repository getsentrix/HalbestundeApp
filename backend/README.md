# PianoGlass OMR Backend

High-accuracy Optical Music Recognition (OMR) and MIDI synthesis microservice for **PianoGlass**.

Converts sheet music scans (PDF or high-definition photos) into standard MusicXML 3.1 and Standard MIDI (.mid) files with real-time polyphonic playback and iOS synchronization.

---

## ⚡ Quick Start

### 1. Local Setup

Install Python requirements and start the FastAPI server:

```bash
# Option A: From repository root (recommended)
pip install -r backend/requirements.txt
uvicorn backend.server:app --host 0.0.0.0 --port 8000 --reload

# Option B: From the backend directory
cd backend
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000 --reload
```

Open **`http://localhost:8000`** in your browser to launch the Web Tone.js Player.
Interactive API documentation is at **`http://localhost:8000/docs`**.

---

### 2. Docker Setup (Recommended for Full Production OMR)

The production Docker container includes `poppler-utils`, `openjdk-17-jre-headless` (for Audiveris), and pre-configured deep learning libraries for `oemer`:

```bash
# Build Docker image
docker build -t pianoglass-omr backend/

# Run container on port 8000
docker run -d -p 8000:8000 --name pianoglass-omr-server pianoglass-omr

# Verify health status
curl http://localhost:8000/api/health
```

---

## 📦 Dependencies & Architecture

### Core Stack
- **Web API**: `fastapi>=0.100.0`, `uvicorn[standard]>=0.23.0`, `python-multipart>=0.0.6`, `pydantic>=2.0.0`, `httpx>=0.24.0`
- **Document & Image Processing**: `pillow>=10.0.0`, `pdf2image>=1.16.0`, `poppler-utils`, `pypdf>=4.0.0`, `numpy>=1.24.0`
- **Symbolic Music & MIDI**: `music21>=9.0.0`
- **Testing**: `pytest>=7.0.0`

### 4-Tier OMR Engine Hierarchy
1. **Tier 1 - Audiveris Open-Source OMR**:
   - Industry-standard OMR engine (`audiveris` CLI or Docker container).
   - Exports complete polyphonic score parts, clefs, accidentals, and measures.
2. **Tier 2 - Deep Learning OMR (`oemer`)**:
   - Neural symbol segmentation (`oemer`, `onnxruntime`, `opencv-python-headless`).
   - Automatically downloads checkpoints in Docker container.
3. **Tier 3 - Cloud Multimodal AI OMR (Google Gemini / OpenAI)**:
   - When `GEMINI_API_KEY`, `GOOGLE_API_KEY`, or `OPENAI_API_KEY` is set in the environment, the server can use multimodal LLM vision to transcribe high-res sheet scans into pristine MusicXML 3.1.
4. **Tier 4 - AdvancedVisionOMR (Local Feature Extraction)**:
   - Pure-Python / NumPy computer vision engine that runs reliably anywhere (including CPU, ARM64, and offline environments).
   - Features:
     - Adaptive local contrast binarization (Sauvola/Bradley via BoxBlur) that eliminates paper gradients, shadows, and creases.
     - Dynamic staff spacing support from 6px to 200px (no resolution caps).
     - Full-page multi-system Grand Staff detection (pairs Treble & Bass staves across all systems).
     - Vertical run-length staff filtering that preserves noteheads sitting on lines.
     - Dual Solid AND Hollow notehead recognition (distinguishes half notes, whole notes, quarter notes, 8th notes).
     - Vertical projection barline detection for true measure segmentation.
     - Accidental detection (#, b, ♮) directly modifying diatonic pitches.

---

## 📡 API Reference

### `POST /api/transcribe`
Uploads a sheet music document (PDF or Image) and returns transcribed notation and audio. Supports single and multi-page documents.

**Request**:
- `Content-Type: multipart/form-data`
- `file`: Document file (`.pdf`, `.png`, `.jpg`, `.tiff`, `.webp`)
- `title` *(optional)*: Title of the piece

**Response** (`200 OK`):
```json
{
  "id": "7f8b9a2c1d0e",
  "title": "Chopin Nocturne Op 9 No 2",
  "status": "success",
  "engine": "advanced_vision",
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
  "audiveris_available": false,
  "oemer_available": false,
  "cloud_ai_available": false,
  "poppler_available": true,
  "music21_version": "10.5.0",
  "cached_scores_count": 1
}
```

---

## 📱 Connecting to the iOS App (PianoGlass)

1. Start the server locally:
   ```bash
   uvicorn backend.server:app --host 0.0.0.0 --port 8000
   ```
2. Launch **PianoGlass** on iOS (Simulator or physical device).
3. Tap **Settings** (gear icon) → **Scanner & Recognition**.
4. Enable **Use OMR Backend Server**.
5. Set the server URL:
   - **Simulator**: `http://localhost:8000`
   - **Physical Device**: `http://<your-lan-ip>:8000` (e.g. `http://192.168.1.150:8000`)
6. In the **Scan** tab or file importer, scan or upload any sheet music.
7. The app transmits the document to `/api/transcribe`, receives high-accuracy MusicXML, and immediately launches into interactive score playback!

---

## 🧪 Running Automated Tests

```bash
# Run backend test suite
python -m pytest Tests/test_backend.py -v
```
