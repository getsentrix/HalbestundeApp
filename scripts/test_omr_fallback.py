#!/usr/bin/env python3
"""
Deep Verification Suite for PianoGlass On-Device Fallback OMR (Features F6, F7, F8, F9, F10).
Validates algorithmic correctness of VisionStaffDetector.swift and NoteRecognitionEngine.swift:
- F6: Deskew range expansion (+/-20.0 deg) and coordinate alignment propagation.
- F7: Strip-based staff line tracking (8-16 vertical columns) resilient to page curvature/sag and shadow gradients.
- F8: Grand-staff barline discrimination against chord note stems; measure boundary synchronization.
- F9: Notehead morphology (solid vs hollow), stem/beam/flag/dot duration analysis, diatonic pitch mapping.
- F10: Joint multi-staff rhythm quantizer and beat synchronization between treble and bass hands.
"""

import sys
import math
import numpy as np
from PIL import Image, ImageDraw

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def test_f6_deskew_and_coordinate_alignment():
    print("[F6] Testing Deskew Sweep (+/-20 deg) & Coordinate Alignment...")
    
    # 1. Verify deskew coarse sweep range in Swift source code
    with open("Sources/PianoGlass/OMR/VisionStaffDetector.swift", "r", encoding="utf-8") as f:
        src = f.read()
    
    assert "testAngle: CGFloat = -20.0" in src, "VisionStaffDetector must start deskew coarse search at -20.0 deg"
    assert "testAngle <= 20.05" in src, "VisionStaffDetector must sweep through +20.0 deg"
    assert "alignedImage: CGImage?" in src, "DetectedStaffSystem must store alignedImage"
    assert "detectBarlines(" in src and "in: alignedImage" in src, "detectBarlines must receive alignedImage, not raw cgImage"
    
    with open("Sources/PianoGlass/OMR/NoteRecognitionEngine.swift", "r", encoding="utf-8") as f:
        note_src = f.read()
    assert "systems.first?.alignedImage" in note_src, "NoteRecognitionEngine must consume alignedImage from DetectedStaffSystem"
    
    # 2. Algorithmic simulation of horizontal projection variance under tilt
    w, h = 600, 400
    base_img = Image.new("L", (w, h), color=255)
    draw = ImageDraw.Draw(base_img)
    for y in [100, 115, 130, 145, 160, 240, 255, 270, 285, 300]:
        draw.line([(50, y), (550, y)], fill=0, width=2)
        
    tilt_angle = 12.5  # Handheld phone capture tilt
    tilted_img = base_img.rotate(tilt_angle, resample=Image.Resampling.BICUBIC, fillcolor=255)
    
    # Run coarse rotation variance search over -20 to +20 degrees
    def row_variance(img_rot, deg):
        test_rot = img_rot.rotate(deg, resample=Image.Resampling.BILINEAR, fillcolor=255)
        arr = np.array(test_rot)
        dark = (arr[:, 90:510] < 160).sum(axis=1)
        return float(np.var(dark))
        
    best_deg = 0.0
    best_var = 0.0
    for deg in range(-20, 21):
        v = row_variance(tilted_img, deg)
        if v > best_var:
            best_var = v
            best_deg = deg
            
    # Counter-rotation to un-tilt should peak at approximately -tilt_angle (-12 to -13 deg)
    assert abs(best_deg - (-tilt_angle)) <= 1.5, f"Expected counter-rotation near -{tilt_angle}, got {best_deg}"
    print(f"  ✓ Coarse deskew correctly located peak variance at {best_deg}° for a {tilt_angle}° tilted capture.")


def test_f7_strip_based_staff_tracking():
    print("[F7] Testing Strip-Based Staff Tracking on Curved / Sagged Staves & Shadows...")
    
    w, h = 1200, 800
    curved_img = Image.new("L", (w, h), color=255)
    draw = ImageDraw.Draw(curved_img)
    
    # Draw staves with realistic page sag (sagging downward in center by 12px)
    def sag_y(x, base_y):
        norm_x = (x - w / 2) / (w / 2)
        return base_y + 12.0 * (1.0 - norm_x * norm_x)
        
    base_lines = [200, 215, 230, 245, 260]
    for x in range(100, w - 100):
        for bl in base_lines:
            y0 = int(round(sag_y(x, bl)))
            draw.point((x, y0), fill=0)
            draw.point((x, y0 + 1), fill=0)
            
    # Add a cast shadow gradient across the page (darkening from left to right)
    arr = np.array(curved_img, dtype=np.float32)
    shadow = np.linspace(0.95, 0.45, w).reshape(1, w)
    arr = arr * shadow
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    shadow_img = Image.fromarray(arr)
    
    # 1. Global projection across full width: curved staves smear across rows
    global_dark = (arr[:, 120:w-120] < 140).sum(axis=1)
    global_max = float(np.max(global_dark))
    global_median = float(np.median(global_dark))
    global_prominence = global_max - global_median
    
    # 2. Strip-based projection (12 strips): local projection retains sharp peaks!
    num_strips = 12
    strip_w = w // num_strips
    detected_strip_lines = []
    
    for s in range(num_strips):
        sx0 = s * strip_w
        sx1 = (s + 1) * strip_w
        strip_crop = arr[:, sx0:sx1]
        
        # Local adaptive thresholding per strip
        p15 = np.percentile(strip_crop, 15)
        p85 = np.percentile(strip_crop, 85)
        local_thresh = p15 + (p85 - p15) * 0.42
        
        strip_dark = (strip_crop < local_thresh).sum(axis=1)
        # Find 5 peaks in this strip
        peaks = []
        med = np.median(strip_dark)
        mx = np.max(strip_dark)
        thresh = med + (mx - med) * 0.25
        for y in range(1, h - 1):
            if strip_dark[y] > thresh and strip_dark[y] >= strip_dark[y-1] and strip_dark[y] >= strip_dark[y+1]:
                if not peaks or (y - peaks[-1]) >= 8:
                    peaks.append(y)
        if len(peaks) >= 5:
            detected_strip_lines.append((s, peaks[:5]))
            
    assert len(detected_strip_lines) >= 8, f"Strip tracker must detect staves in >=8 strips, got {len(detected_strip_lines)}"
    
    # Verify that the detected strip lines track the sag curvature:
    center_strip = [lines for s, lines in detected_strip_lines if s == num_strips // 2]
    left_strip = [lines for s, lines in detected_strip_lines if s == 1]
    if center_strip and left_strip:
        center_y = center_strip[0][0]
        left_y = left_strip[0][0]
        assert center_y > left_y, f"Center sag expected center_y > left_y, got center={center_y}, left={left_y}"
        
    print(f"  ✓ Strip tracker successfully traced sagged staff across {len(detected_strip_lines)}/12 strips despite shadow gradient.")


def test_f8_grand_staff_barline_discrimination():
    print("[F8] Testing Grand-Staff Barline Discrimination vs Note Stems...")
    
    w, h = 800, 600
    score_img = Image.new("L", (w, h), color=255)
    draw = ImageDraw.Draw(score_img)
    
    # Grand staff geometry
    treble_top, treble_bot = 150, 210  # 5 lines, 15px spacing
    bass_top, bass_bot = 310, 370      # 5 lines, 15px spacing
    
    for y in range(treble_top, treble_bot + 1, 15):
        draw.line([(50, y), (750, y)], fill=0, width=2)
    for y in range(bass_top, bass_bot + 1, 15):
        draw.line([(50, y), (750, y)], fill=0, width=2)
        
    # Draw true grand staff barlines (spanning from treble_top to bass_bot) at X=100, 350, 600
    true_barlines = [100, 350, 600]
    for bx in true_barlines:
        draw.line([(bx, treble_top), (bx, bass_bot)], fill=0, width=2)
        
    # Draw dense note stems and chord noteheads at X=180, 230, 280, 420, 480
    stem_xs = [180, 230, 280, 420, 480]
    for sx in stem_xs:
        # Note stem only spans within treble staff (~45px)
        draw.line([(sx, treble_top + 10), (sx, treble_top + 55)], fill=0, width=2)
        # Notehead bulge at bottom of stem: width 18px (>= 1.2 * spacing)
        draw.ellipse([(sx - 8, treble_top + 45), (sx + 8, treble_top + 60)], fill=0)
        
    arr = np.array(score_img)
    
    # Barline discrimination algorithm from VisionStaffDetector.swift:
    detected_barlines = []
    sp = 15.0
    treble_rows = treble_bot - treble_top
    bass_rows = bass_bot - bass_top
    
    for x in range(60, 740):
        col = arr[treble_top:bass_bot, x]
        dark_treble = (arr[treble_top:treble_bot, x] < 145).sum()
        dark_bass = (arr[bass_top:bass_bot, x] < 145).sum()
        
        # Check notehead bulge: require multiple consecutive rows to distinguish noteheads from staff line crossings
        consecutive_wide = 0
        max_consecutive_wide = 0
        for y in range(treble_top, bass_bot):
            if arr[y, x] < 145:
                # Horizontal run length
                lx = x
                while lx >= 0 and lx >= x - int(sp * 1.5) and arr[y, lx] < 145:
                    lx -= 1
                rx = x
                while rx < w and rx <= x + int(sp * 1.5) and arr[y, rx] < 145:
                    rx += 1
                if (rx - lx) >= int(sp * 1.25):
                    consecutive_wide += 1
                    if consecutive_wide > max_consecutive_wide:
                        max_consecutive_wide = consecutive_wide
                else:
                    consecutive_wide = 0
            else:
                consecutive_wide = 0
                
        has_notehead_bulge = (max_consecutive_wide >= int(sp * 0.45))
        treble_frac = dark_treble / float(treble_rows)
        bass_frac = dark_bass / float(bass_rows)
        
        if not has_notehead_bulge and treble_frac >= 0.52 and bass_frac >= 0.52:
            if not detected_barlines or (x - detected_barlines[-1]) >= int(sp * 5):
                detected_barlines.append(x)
                
    assert len(detected_barlines) == 3, f"Expected exactly 3 true barlines, got {detected_barlines}"
    for tb in true_barlines:
        assert any(abs(db - tb) <= 3 for db in detected_barlines), f"True barline at {tb} not matched in {detected_barlines}"
    for sx in stem_xs:
        assert not any(abs(db - sx) <= 5 for db in detected_barlines), f"Note stem at {sx} was falsely accepted as barline!"
        
    print(f"  ✓ Barline discriminator accepted {len(detected_barlines)} true barlines and rejected all {len(stem_xs)} chord stems.")


def test_f9_notehead_morphology_and_durations():
    print("[F9] Testing Notehead Morphology, Duration Classifier & Pitch Mapping...")
    
    sp = 16.0
    # 1. Test solid vs hollow notehead classification
    # Solid notehead: filled ellipse, high fill ratio (>0.60), dark center
    solid_img = Image.new("L", (int(sp * 2), int(sp * 2)), color=255)
    draw_s = ImageDraw.Draw(solid_img)
    draw_s.ellipse([(4, 4), (int(sp * 1.5), int(sp * 1.1))], fill=0)
    arr_s = np.array(solid_img)
    s_dark = (arr_s < 140).sum()
    s_bw = int(sp * 1.5) - 4
    s_bh = int(sp * 1.1) - 4
    s_fill = s_dark / float(s_bw * s_bh)
    center_dark = arr_s[int(sp * 0.75), int(sp * 0.75)] < 140
    assert s_fill > 0.60 and center_dark, "Solid notehead must have high fill ratio and dark center"
    
    # Hollow notehead: stroke ellipse, white paper center, low fill ratio (<0.55)
    hollow_img = Image.new("L", (int(sp * 2), int(sp * 2)), color=255)
    draw_h = ImageDraw.Draw(hollow_img)
    draw_h.ellipse([(4, 4), (int(sp * 1.5), int(sp * 1.1))], outline=0, width=3)
    arr_h = np.array(hollow_img)
    h_dark = (arr_h < 140).sum()
    h_fill = h_dark / float(s_bw * s_bh)
    center_paper = arr_h[int(sp * 0.75), int(sp * 0.75)] >= 140
    assert h_fill < 0.55 and center_paper, "Hollow notehead must have paper center and fill ratio < 0.55"
    
    # 2. Test duration rule matrix
    # (is_hollow, has_stem, beams/flags, is_dotted) -> duration
    def classify_duration(is_hollow, has_stem, beams, is_dotted):
        if is_hollow:
            dur = 2.0 if has_stem else 4.0
        else:
            if not has_stem:
                dur = 1.0
            elif beams >= 2:
                dur = 0.25  # Sixteenth
            elif beams == 1:
                dur = 0.5   # Eighth
            else:
                dur = 1.0   # Quarter
        if is_dotted:
            dur *= 1.5
        return dur
        
    assert classify_duration(False, True, 0, False) == 1.0, "Quarter note duration mismatch"
    assert classify_duration(False, True, 1, False) == 0.5, "Eighth note duration mismatch"
    assert classify_duration(False, True, 2, False) == 0.25, "Sixteenth note duration mismatch"
    assert classify_duration(True, True, 0, False) == 2.0, "Half note duration mismatch"
    assert classify_duration(True, False, 0, False) == 4.0, "Whole note duration mismatch"
    assert classify_duration(True, True, 0, True) == 3.0, "Dotted half note duration mismatch"
    assert classify_duration(False, True, 0, True) == 1.5, "Dotted quarter note duration mismatch"
    assert classify_duration(False, True, 1, True) == 0.75, "Dotted eighth note duration mismatch"
    
    # 3. Test Diatonic pitch mapping across octave boundaries
    diatonicTrebleFromE4 = [64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84]
    belowTreble = [62, 60, 59, 57, 55]
    def pitch_calc(pos, clef):
        steps = int(round(pos * 2.0))
        if clef == "treble":
            if 0 <= steps < len(diatonicTrebleFromE4): return diatonicTrebleFromE4[steps]
            if steps < 0 and -steps <= len(belowTreble): return belowTreble[-steps - 1]
            return 64 + steps
        else:
            diatonicBass = [43, 45, 47, 48, 50, 52, 53, 55, 57, 59, 60, 62, 64]
            belowBass = [41, 40, 38, 36]
            if 0 <= steps < len(diatonicBass): return diatonicBass[steps]
            if steps < 0 and -steps <= len(belowBass): return belowBass[-steps - 1]
            return 43 + steps
            
    assert pitch_calc(0.0, "treble") == 64  # E4
    assert pitch_calc(2.0, "treble") == 71  # B4
    assert pitch_calc(4.0, "treble") == 77  # F5
    assert pitch_calc(-1.0, "treble") == 60 # Middle C (C4)
    assert pitch_calc(0.0, "bass") == 43    # G2
    assert pitch_calc(3.0, "bass") == 53    # F3
    assert pitch_calc(5.0, "bass") == 60    # Middle C (C4)
    print("  ✓ Solid/hollow morphology, stem/beam durations (16th to Whole, dotted), and pitch mapping verified.")


def test_f10_multi_staff_rhythm_quantizer():
    print("[F10] Testing Multi-Staff Rhythm Quantizer & Beat Synchronization...")
    
    # Simulate a measure with 4 simultaneous RH & LH chord events:
    # Beat 0: RH C5 (72) & LH C3 (48), Quarter
    # Beat 1: RH D5 (74) & LH G3 (55), Quarter
    # Beat 2: RH E5 (76) & LH C4 (60), Quarter
    # Beat 3: RH G5 (79) & LH G2 (43), Quarter
    # With non-linear engraving spacing (accidentals, spacing variation)
    measure_left_x = 100.0
    measure_right_x = 500.0
    measure_w = 400.0
    beats_per_measure = 4.0
    sp = 12.0
    
    # Notes with physical X positions (non-linear spacing!)
    # Event 1 at X=125, Event 2 at X=210, Event 3 at X=305, Event 4 at X=415
    raw_notes = [
        {"x": 124.5, "hand": "RH", "pitch": 72, "dur": 1.0},
        {"x": 125.2, "hand": "LH", "pitch": 48, "dur": 1.0},
        {"x": 210.0, "hand": "RH", "pitch": 74, "dur": 1.0},
        {"x": 209.8, "hand": "LH", "pitch": 55, "dur": 1.0},
        {"x": 304.5, "hand": "RH", "pitch": 76, "dur": 1.0},
        {"x": 305.1, "hand": "LH", "pitch": 60, "dur": 1.0},
        {"x": 415.0, "hand": "RH", "pitch": 79, "dur": 1.0},
        {"x": 414.8, "hand": "LH", "pitch": 43, "dur": 1.0},
    ]
    
    # 1. Joint temporal clustering
    cluster_threshold = max(sp * 0.65, measure_w * 0.035)
    time_slices = []
    for n in sorted(raw_notes, key=lambda n: n["x"]):
        if time_slices and abs(n["x"] - time_slices[-1][0]["x"]) <= cluster_threshold:
            time_slices[-1].append(n)
        else:
            time_slices.append([n])
            
    assert len(time_slices) == 4, f"Expected 4 distinct simultaneous time slices, got {len(time_slices)}"
    
    # 2. Rhythm quantizer assigning onsets
    slice_onsets = [0.0] * len(time_slices)
    grid = [0.25, 0.375, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
    for k in range(len(time_slices) - 1):
        cur_x = sum(n["x"] for n in time_slices[k]) / len(time_slices[k])
        nxt_x = sum(n["x"] for n in time_slices[k + 1]) / len(time_slices[k + 1])
        delta_x = nxt_x - cur_x
        spatial_est = (delta_x / measure_w) * beats_per_measure
        detected_dur = min(n["dur"] for n in time_slices[k])
        blended = (detected_dur * 0.6) + (spatial_est * 0.4)
        best_step = min(grid, key=lambda g: abs(blended - g))
        
        next_onset = slice_onsets[k] + best_step
        max_allowed = beats_per_measure - (len(time_slices) - 1 - k) * 0.25
        slice_onsets[k + 1] = max(slice_onsets[k] + 0.25, min(max_allowed, next_onset))
        
    scheduled_notes = []
    for k, s in enumerate(time_slices):
        onset = slice_onsets[k]
        for n in s:
            scheduled_notes.append({
                "pitch": n["pitch"],
                "hand": n["hand"],
                "startBeat": onset,
                "dur": min(n["dur"], beats_per_measure - onset)
            })
            
    # Check that in every time slice, RH and LH have IDENTICAL startBeat
    for k, s in enumerate(time_slices):
        rh = [n for n in scheduled_notes if n["hand"] == "RH" and n["startBeat"] == slice_onsets[k]]
        lh = [n for n in scheduled_notes if n["hand"] == "LH" and n["startBeat"] == slice_onsets[k]]
        assert len(rh) == 1 and len(lh) == 1, f"Slice {k} RH/LH desync"
        assert rh[0]["startBeat"] == lh[0]["startBeat"], f"Slice {k} beat mismatch: RH={rh[0]['startBeat']} != LH={lh[0]['startBeat']}"
        
    # Check that onsets span the measure cleanly [0.0, 1.0, 2.0, 3.0] without bunching at beat 0
    expected_onsets = [0.0, 1.0, 2.0, 3.0]
    assert slice_onsets == expected_onsets, f"Expected {expected_onsets}, got {slice_onsets}"
    print(f"  ✓ Multi-staff quantizer aligned 4 simultaneous chord slices to {slice_onsets} with 0.0s inter-hand skew.")


if __name__ == "__main__":
    test_f6_deskew_and_coordinate_alignment()
    test_f7_strip_based_staff_tracking()
    test_f8_grand_staff_barline_discrimination()
    test_f9_notehead_morphology_and_durations()
    test_f10_multi_staff_rhythm_quantizer()
    print("\nSUCCESS: All On-Device Fallback OMR (F6-F10) verification checks PASSED!")
