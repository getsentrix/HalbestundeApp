#!/usr/bin/env python3
"""Patch script: replace FallbackOMR in omr_engine.py with real pitch detection."""
import os

omr_path = os.path.join(os.path.dirname(__file__), '..', 'backend', 'omr_engine.py')

with open(omr_path, 'r', encoding='utf-8') as f:
    content = f.read()

marker_start = 'class FallbackOMR:\n'
marker_end = '\n\ndef run_oemer_transcription'

idx_start = content.index(marker_start)
idx_end = content.index(marker_end)

before = content[:idx_start]
after = content[idx_end:]

new_class = r'''class FallbackOMR:
    """
    Robust pure-Python OMR processor for CPU environments or when deep-learning
    weights are downloading. Uses image morphology, staff line projection,
    and column-density notehead detection to produce real pitch-mapped MusicXML.
    No hardcoded fake notes: every note is derived from the actual image content.
    """

    @staticmethod
    def process_image(image: Image.Image, title: str = "Transcribed Sheet Music") -> str:
        """
        Analyzes the image, identifies staff systems, detects noteheads via column-
        density analysis, maps their pixel Y-positions to diatonic pitches using the
        same lookup tables as NoteRecognitionEngine.swift, and exports MusicXML.
        """
        gray = image.convert("L")
        w, h = gray.size

        # Preserve quality: use LANCZOS (high-quality downsampling), not BILINEAR
        max_dim = 2800
        if max(w, h) > max_dim:
            scale = max_dim / float(max(w, h))
            gray = gray.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
            w, h = gray.size
            logger.info(f"FallbackOMR: Resized to {w}x{h} (scale={scale:.3f}) using LANCZOS.")

        arr = np.array(gray)
        logger.info(f"FallbackOMR: Processing {w}x{h} grayscale image.")

        # Binarize: sheet music has dark notes/lines on light background
        thresh = 180
        binary = (arr < thresh).astype(np.uint8)  # 1 = dark notation, 0 = white paper

        # --- Staff line detection via horizontal projection histogram ---
        row_sums = np.sum(binary, axis=1)
        median_row = float(np.median(row_sums))
        max_row = float(np.max(row_sums))
        peak_threshold = median_row + (max_row - median_row) * 0.35

        peak_indices = np.where(row_sums > peak_threshold)[0]

        # Cluster consecutive peak rows into single staff line positions
        staff_lines: List[int] = []
        if len(peak_indices) > 0:
            current_cluster = [peak_indices[0]]
            for idx in peak_indices[1:]:
                if idx == current_cluster[-1] + 1:
                    current_cluster.append(idx)
                else:
                    staff_lines.append(int(np.mean(current_cluster)))
                    current_cluster = [idx]
            staff_lines.append(int(np.mean(current_cluster)))

        logger.info(f"FallbackOMR: Detected {len(staff_lines)} staff line candidates "
                    f"(row_max={max_row:.0f}, threshold={peak_threshold:.0f}).")

        # Group lines into 5-line staves (spacing range 6-60 px)
        staves: List[List[int]] = []
        if len(staff_lines) >= 5:
            i = 0
            while i <= len(staff_lines) - 5:
                sub = staff_lines[i:i + 5]
                diffs = [sub[j + 1] - sub[j] for j in range(4)]
                avg_sp = float(np.mean(diffs))
                if all(abs(d - avg_sp) < avg_sp * 0.45 for d in diffs) and 6 <= avg_sp <= 60:
                    staves.append(sub)
                    i += 5
                else:
                    i += 1

        logger.info(f"FallbackOMR: Resolved {len(staves)} structured 5-line staves.")

        # --- Diatonic pitch lookup tables (mirrors NoteRecognitionEngine.swift) ---
        # Treble clef: bottom line = E4 = MIDI 64; each step upward is a diatonic note
        TREBLE_DIATONIC = [64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84]
        TREBLE_BELOW    = [62, 60, 59, 57, 55]   # D4, C4 (ledger), B3, A3, G3
        # Bass clef: bottom line = G2 = MIDI 43
        BASS_DIATONIC   = [43, 45, 47, 48, 50, 52, 53, 55, 57, 59, 60, 62, 64]
        BASS_BELOW      = [41, 40, 38, 36]        # F2, E2, D2, C2

        def staff_pos_to_midi(pos: float, is_treble: bool) -> int:
            """Map diatonic staff position (half-steps from bottom line) to MIDI number."""
            rounded = int(round(pos * 2.0))
            if is_treble:
                if 0 <= rounded < len(TREBLE_DIATONIC):
                    return TREBLE_DIATONIC[rounded]
                elif rounded < 0 and -rounded <= len(TREBLE_BELOW):
                    return TREBLE_BELOW[-rounded - 1]
                return max(21, min(108, 64 + rounded))
            else:
                if 0 <= rounded < len(BASS_DIATONIC):
                    return BASS_DIATONIC[rounded]
                elif rounded < 0 and -rounded <= len(BASS_BELOW):
                    return BASS_BELOW[-rounded - 1]
                return max(21, min(108, 43 + rounded))

        def detect_noteheads_in_staff(
            staff_ys: List[int], is_treble: bool
        ) -> List[Tuple[float, int]]:
            """
            Detect noteheads by column-density analysis.

            Staff lines are full-width horizontal strokes that show up as a constant
            baseline density in every column.  A notehead raises the density of a
            localised cluster of columns above that baseline.

            Returns: list of (x_fraction, midi_pitch) sorted by x position.
            """
            spacing = float(np.mean([staff_ys[j + 1] - staff_ys[j] for j in range(4)]))
            top_y = max(0, staff_ys[0] - int(spacing * 2.5))
            bot_y = min(h - 1, staff_ys[4] + int(spacing * 2.5))
            bottom_line_y = staff_ys[4]

            if bot_y <= top_y or w < 10:
                logger.warning(f"FallbackOMR: Staff ROI invalid (top={top_y}, bot={bot_y}).")
                return []

            roi = arr[top_y:bot_y, :]

            # Per-column dark-pixel count
            col_density = np.sum(roi < thresh, axis=0).astype(np.float32)

            # Background = median density (dominated by full-width staff lines)
            staff_bg = float(np.median(col_density))
            # A notehead must add at least 40% of spacing to a localised column cluster
            nh_thresh = staff_bg + spacing * 0.4

            logger.debug(f"FallbackOMR {'treble' if is_treble else 'bass'}: "
                         f"spacing={spacing:.1f}px, bg={staff_bg:.1f}, "
                         f"nh_thresh={nh_thresh:.1f}, roi_h={bot_y - top_y}")

            candidate_cols = np.where(col_density > nh_thresh)[0]
            if len(candidate_cols) == 0:
                logger.info(
                    f"FallbackOMR: No notehead candidates in "
                    f"{'treble' if is_treble else 'bass'} staff "
                    f"(max_density={col_density.max():.1f}, thresh={nh_thresh:.1f})."
                )
                return []

            # Cluster candidate columns → individual noteheads
            min_gap = max(int(spacing * 0.7), 4)
            noteheads: List[Tuple[float, int]] = []
            i = 0
            while i < len(candidate_cols):
                cluster = [candidate_cols[i]]
                while (i + 1 < len(candidate_cols)
                       and candidate_cols[i + 1] - candidate_cols[i] <= 3):
                    i += 1
                    cluster.append(candidate_cols[i])
                i += 1

                cx = int(np.mean(cluster))

                # Enforce minimum notehead separation
                if noteheads and (cx - noteheads[-1][0]) < min_gap:
                    continue

                # Weighted Y centroid of dark pixels in this column cluster
                x_lo = max(0, cx - 2)
                x_hi = min(w, cx + 3)
                sub_roi = roi[:, x_lo:x_hi]
                darkness = np.clip(thresh - sub_roi.astype(np.float32), 0, None)
                total_w = float(darkness.sum())
                if total_w < 1.0:
                    continue

                ys_idx = np.arange(sub_roi.shape[0], dtype=np.float64)
                cy_local = float(np.dot(darkness.sum(axis=1), ys_idx) / total_w)
                global_y = top_y + cy_local

                # Staff position: 0.0 = bottom staff line, increases upward (each half-step = 0.5)
                pos = (bottom_line_y - global_y) / spacing
                midi = staff_pos_to_midi(pos, is_treble)

                x_frac = cx / float(max(1, w - 1))
                noteheads.append((x_frac, midi))
                logger.debug(
                    f"  {'T' if is_treble else 'B'} notehead x={cx} "
                    f"y={global_y:.1f} pos={pos:.2f} -> MIDI {midi}"
                )

            logger.info(
                f"FallbackOMR: {'Treble' if is_treble else 'Bass'} "
                f"detected {len(noteheads)} noteheads."
            )
            return noteheads

        # Detect noteheads in the first two staves (treble + bass)
        detected_rh: List[Tuple[float, int]] = []
        detected_lh: List[Tuple[float, int]] = []
        if len(staves) >= 1:
            detected_rh = detect_noteheads_in_staff(staves[0], is_treble=True)
        if len(staves) >= 2:
            detected_lh = detect_noteheads_in_staff(staves[1], is_treble=False)

        logger.info(
            f"FallbackOMR: Grand total — RH: {len(detected_rh)} notes, "
            f"LH: {len(detected_lh)} notes."
        )

        # Build music21 Score from detected noteheads
        score = music21.stream.Score()
        score.metadata = music21.metadata.Metadata()
        score.metadata.title = title
        score.metadata.composer = "PianoGlass OMR Engine"

        part_rh = music21.stream.Part()
        part_rh.id = "P1"
        part_rh.partName = "Right Hand"

        part_lh = music21.stream.Part()
        part_lh.id = "P2"
        part_lh.partName = "Left Hand"

        tempo_mark = music21.tempo.MetronomeMark(number=110)
        num_measures = max(4, min(8, len(staves) * 2 if staves else 4))
        beats_per_measure = 4.0

        def pitches_to_measures(
            pitches: List[Tuple[float, int]],
            clef_obj,
            num_meas: int,
            is_treble: bool,
        ) -> List[music21.stream.Measure]:
            """
            Distribute detected (x_fraction, midi_pitch) across measures as quarter notes.
            Noteheads are assigned chronologically (left-to-right = earlier in time).
            Gaps are padded with rests; empty measures receive a whole rest.
            """
            sorted_pitches = sorted(pitches, key=lambda p: p[0])
            measures_out = []
            notes_per_measure = max(1, round(len(sorted_pitches) / max(1, num_meas)))

            for m_idx in range(1, num_meas + 1):
                m = music21.stream.Measure(number=m_idx)
                if m_idx == 1:
                    m.append(clef_obj)
                    m.append(music21.meter.TimeSignature("4/4"))
                    m.append(music21.key.KeySignature(0))
                    if is_treble:
                        m.append(tempo_mark)

                start_i = (m_idx - 1) * notes_per_measure
                end_i = min(len(sorted_pitches), start_i + notes_per_measure)
                measure_pitches = sorted_pitches[start_i:end_i]

                if measure_pitches:
                    beat_step = beats_per_measure / len(measure_pitches)
                    note_dur = min(beat_step, 2.0)
                    used_beats = 0.0
                    for _, midi in measure_pitches:
                        p21 = music21.pitch.Pitch()
                        p21.midi = max(21, min(108, midi))
                        n = music21.note.Note(quarterLength=note_dur)
                        n.pitch = p21
                        m.append(n)
                        used_beats += note_dur
                    remaining = beats_per_measure - used_beats
                    if remaining > 0.01:
                        m.append(music21.note.Rest(quarterLength=remaining))
                else:
                    m.append(music21.note.Rest(quarterLength=4.0))

                measures_out.append(m)
            return measures_out

        rh_measures = pitches_to_measures(
            detected_rh, music21.clef.TrebleClef(), num_measures, True
        )
        lh_measures = pitches_to_measures(
            detected_lh, music21.clef.BassClef(), num_measures, False
        )

        for m in rh_measures:
            part_rh.append(m)
        for m in lh_measures:
            part_lh.append(m)

        score.insert(0, part_rh)
        score.insert(0, part_lh)

        # Convert music21 Score to MusicXML string
        sx = music21.musicxml.m21ToXml.ScoreExporter(score)
        root = sx.parse()
        raw_xml = ET.tostring(root, encoding="unicode")
        if not raw_xml.startswith("<?xml"):
            musicxml_str = '<?xml version="1.0" encoding="UTF-8"?>\n' + raw_xml
        else:
            musicxml_str = raw_xml

        logger.info(f"FallbackOMR: MusicXML output ready ({len(musicxml_str)} bytes).")
        return musicxml_str
'''

new_content = before + new_class + after

with open(omr_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Patched successfully. New file size: {len(new_content)} bytes")
# Verify it's importable
import subprocess, sys
result = subprocess.run([sys.executable, '-c', f'import sys; sys.path.insert(0, "backend"); import omr_engine; print("Import OK")'],
                       capture_output=True, text=True, cwd=os.path.dirname(omr_path).replace('backend', '').rstrip('/\\'))
print(result.stdout, result.stderr)
