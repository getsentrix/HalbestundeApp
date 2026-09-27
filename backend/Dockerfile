# Production Dockerfile for PianoGlass OMR Backend
# Supports pdf2image (poppler), oemer (ONNX/OpenCV), and music21 (MIDI/MusicXML)
FROM python:3.11-slim

# Prevent Python from writing .pyc and buffer stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    HOST=0.0.0.0

# Install system dependencies: poppler-utils for pdf2image, libgl/opencv libraries for oemer
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    ffmpeg \
    libsm6 \
    libxext6 \
    libgl1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir oemer onnxruntime opencv-python-headless && \
    python -c "from oemer.ete import CHECKPOINTS_URL, MODULE_PATH, download_file; import os; [os.makedirs(os.path.join(MODULE_PATH, 'checkpoints', 'unet_big' if t.startswith('1st') else 'seg_net'), exist_ok=True) or download_file(t, u, os.path.join(MODULE_PATH, 'checkpoints', 'unet_big' if t.startswith('1st') else 'seg_net', t.split('_')[1])) for t, u in CHECKPOINTS_URL.items()]" || true

# Copy backend application files
COPY . .

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/api/health || exit 1

# Launch FastAPI server with Uvicorn
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
