# Halbestunde iOS • Liquid Glass Piano Sheet Music Scanner & Player

A pure native Swift & SwiftUI iOS application inspired by **Halbestunde**. Scan printed or digital piano sheet music, immediately recognize the musical notation with an Optical Music Recognition (OMR) pipeline, and play along with real-time polyphonic piano audio, an interactive vector score with animated glowing playhead, and an illuminated 61/88-key virtual piano keyboard.

All styled in a luxury dark concert-hall **Liquid Glass (Glassmorphism)** design system with frosted `.ultraThinMaterial` blurs, glowing specular rim gradients, and iridescent accents.

---

## Key Features

### 1. Liquid Glass Design System
- **Frosted Translucency**: Layered translucent surfaces with `.ultraThinMaterial`, dynamic blurs, and deep obsidian surface tints (`#080B10`).
- **Specular Highlights & Rim Lighting**: High-contrast multi-stop linear gradients reflecting light along edges and rounded corners.
- **Glowing Visual Cues**: Neon Cyan (`#00E5FF`) for Left Hand / Bass clef, Radiant Amber (`#FFB300`) for Right Hand / Treble clef, and Violet (`#D500F9`) for dual-hand unisons.
- **Haptic Spring Buttons**: Dynamic press-down spring animations (`.springPressEffect()`) with reactive glow feedback.

### 2. Sheet Music Scanner & OMR Pipeline
- **Document & Camera Capture**: Camera viewfinder with alignment corner brackets and animated sweeping laser line.
- **Vision Staff Detection (`VisionStaffDetector`)**: Identifies 5-line staff clusters, calculates exact staff spacing ($sp$), locates grand staff systems (Treble & Bass), and identifies measure barlines.
- **Pitch & Rhythm Recognition (`NoteRecognitionEngine`)**:
  - Maps notehead Y-coordinates to diatonic lines and spaces for both Treble (G clef) and Bass (F clef) with full ledger line support.
  - Distinguishes solid noteheads from hollow noteheads and reads stems/beams to extract rhythm durations (whole, half, quarter, eighth, sixteenth, triplets).
- **MusicXML & MIDI Compatibility**:
  - `MusicXMLParser`: Full parser for `<score-partwise>` MusicXML files.
  - `MusicXMLExporter`: Serializes recognized scores back into clean MusicXML 3.1.
- **Built-in Scanner Simulator**: Instant demonstration mode allows testing the complete OMR pipeline on simulator or devices without camera access.

### 3. Polyphonic Acoustic Piano Audio Engine
- **Physical Acoustic Modeling (`AVAudioSourceNode`)**:
  - True polyphonic grand piano synthesizer using physical modeling: inharmonic string overtone dispersion, sharp hammer strike attack (<5ms), multi-stage exponential harmonic decay, and sympathetic unison string bloom.
  - Smooth damper note-off release damping (120ms).
  - Standalone and self-contained: works out of the box with zero external soundfont dependencies!
- **SoundFont & Sampler Support (`AVAudioUnitSampler`)**: Optional loading of `.sf2` soundfonts.
- **Metronome Generator**: Click track generator with distinct accents for measure downbeats and subdivisions.

### 4. Interactive Visual Score & Illuminated Virtual Keyboard
- **Vector Grand Staff Score (`ScoreCanvasView`)**:
  - Renders Treble and Bass staves, barlines, noteheads, stems, and clefs.
  - Real-time animated vertical playhead cursor tracking current beat and measure.
  - Auto-scrolls horizontally to keep the active measure centered.
  - Tap any measure to seek directly or set loop points.
- **Interactive Piano Keyboard (`VirtualPianoKeyboardView`)**:
  - Switchable between 61 keys (C2 to C7) and 88 keys (A0 to C8).
  - Ivory white keys and ebony black keys with liquid glass sheen and shadows.
  - **Dynamic Hand Illumination**: Real-time glow lighting keys during playback (Cyan for LH, Amber for RH, Violet for both).
  - **Interactive Audition**: Tap or swipe across keys to play notes directly with real-time sound.
- **Falling Notes Stream (`WaterfallNotesView`)**: Synthesia-style falling note blocks cascading toward keys.

### 5. Comprehensive Practice Studio
- **Tempo Dial**: 40 to 240 BPM slider with quick presets (Largo, Andante, Moderato, Allegro, Presto).
- **A-B Measure Looping**: Select start measure A and end measure B for targeted passage repetition.
- **Pitch Transposition**: Shift key by -12 to +12 semitones with automatic key signature recalculation.
- **Hand Isolation**: Independent Solo and Mute toggles for Left Hand (Bass) and Right Hand (Treble) parts.

### 6. Curated Classical Repertoire & Scan Library
- **Pre-Loaded Pieces**:
  1. *Für Elise* - Ludwig van Beethoven (WoO 59)
  2. *Moonlight Sonata (Adagio)* - Ludwig van Beethoven (Op. 27 No. 2)
  3. *Minuet in G major* - Christian Petzold / J.S. Bach (BWV Anh. 114)
  4. *Nocturne in E-flat major* - Frédéric Chopin (Op. 9 No. 2)
  5. *Gymnopédie No. 1* - Erik Satie
- **Scan History Store**: Local JSON persistence for user-scanned sheet music with favorites and difficulty filtering.

---

## Project Structure

```
├── Package.swift                             # Swift Package Manager manifest
├── HalbestundeApp.xcodeproj/                 # Xcode project for iOS 17+
│   └── project.pbxproj
├── Sources/HalbestundeApp/
│   ├── App/
│   │   ├── HalbestundeApp.swift              # App entry point (@main)
│   │   ├── ContentView.swift                 # Main tab navigation
│   │   └── Info.plist                        # Camera & background audio permissions
│   ├── Models/
│   │   ├── MusicModels.swift                 # Pitch, NoteEvent, Measure, Score, KeySignature
│   │   ├── PracticeSession.swift             # PracticeSettings, LoopRange, HandIsolation
│   │   ├── SongItem.swift                    # Catalog metadata & difficulty levels
│   │   └── ScanResult.swift                  # OMR detection results & confidence metrics
│   ├── DesignSystem/
│   │   ├── LiquidGlassTheme.swift            # Theme tokens, colors, gradients
│   │   ├── LiquidGlassModifiers.swift        # .liquidGlass(), .glowing(), .springPressEffect()
│   │   └── GlassComponents.swift             # GlassCard, GlassButton, GlassIconButton, GlassBadge
│   ├── AudioEngine/
│   │   ├── PianoAudioEngine.swift            # Polyphonic acoustic physical piano synthesizer
│   │   └── AudioScheduler.swift              # Beat clock, playhead tracking, metronome
│   ├── OMR/
│   │   ├── VisionStaffDetector.swift         # Apple Vision staff line & barline detection
│   │   ├── NoteRecognitionEngine.swift       # Geometry-to-pitch & duration mapper
│   │   ├── MusicXMLParser.swift              # MusicXML partwise parser
│   │   ├── MusicXMLExporter.swift            # MusicXML serializer
│   │   └── MusicScannerService.swift         # End-to-end scanning coordinator
│   ├── Services/
│   │   ├── RepertoireService.swift           # Classical piano pieces
│   │   └── ScanStorageService.swift          # Local JSON scan persistence
│   ├── ViewModels/
│   │   ├── ScorePlayerViewModel.swift        # Audio, score, and practice state
│   │   ├── ScannerViewModel.swift            # Camera capture & OMR review state
│   │   └── SongLibraryViewModel.swift        # Library browsing & search filters
│   ├── Views/
│   │   ├── Score/ScoreCanvasView.swift       # Vector grand staff & playhead cursor
│   │   ├── Keyboard/
│   │   │   ├── VirtualPianoKeyboardView.swift# 61/88-key illuminated piano
│   │   │   └── WaterfallNotesView.swift      # Falling notes visualizer
│   │   ├── Practice/
│   │   │   ├── PracticeDockView.swift        # Floating liquid glass dock
│   │   │   └── PracticeSettingsSheet.swift   # Detailed practice settings modal
│   │   ├── Scanner/ScannerView.swift         # Viewfinder & scan review
│   │   ├── Library/SongLibraryView.swift     # Glass catalog list & filters
│   │   ├── Settings/SettingsView.swift       # App preferences
│   │   └── ScorePlayerView.swift             # Master player layout
│   └── Resources/
│       └── fur_elise.musicxml                # Sample MusicXML sheet music
├── Tests/HalbestundeAppTests/
│   ├── ScoreModelTests.swift                 # Unit tests for Pitch, Frequency, Score
│   ├── MusicXMLParserTests.swift             # Unit tests for XML parsing & roundtrip
│   ├── PracticeControlsTests.swift           # Unit tests for Hand isolation & looping
│   ├── OMRStaffDetectorTests.swift           # Unit tests for Clef & Staff mapping
│   ├── AudioSchedulerTests.swift             # Unit tests for Beat clock & seeking
│   └── XCTestManifests.swift
└── scripts/
    └── verify_logic.py                       # Automated verification test suite
```

---

## How to Build and Run

### Option 1: Xcode (macOS)
1. Open `HalbestundeApp.xcodeproj` in Xcode 15 or later.
2. Select an iOS 17+ Simulator (e.g. *iPhone 15 Pro*) or your connected physical iPhone / iPad.
3. Press **Cmd + R** to build and run.

### Option 2: Swift Package Manager
```bash
swift build
swift test
```

### Option 3: Automated Verification Suite (Cross-Platform)
```bash
python scripts/verify_logic.py
```
Outputs validation across 38 project files, pitch frequency equations, OMR coordinate mappings, MusicXML parsing, and practice loop algorithms.
