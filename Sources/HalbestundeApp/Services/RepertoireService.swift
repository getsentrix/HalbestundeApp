//
//  RepertoireService.swift
//  HalbestundeApp
//
//  Curated classical piano repertoire pre-loaded with note-accurate scores.
//

import Foundation

public final class RepertoireService {
    public static let shared = RepertoireService()
    
    public init() {}
    
    public func loadCatalog() -> [SongItem] {
        return [
            SongItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "Für Elise",
                composer: "Ludwig van Beethoven",
                difficulty: .intermediate,
                isScanned: false,
                isFavorite: true,
                durationSeconds: 165.0,
                estimatedMeasureCount: 24,
                keySignatureName: "A Minor",
                timeSignatureDisplay: "3/8",
                previewScore: furEliseScore()
            ),
            SongItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                title: "Moonlight Sonata (Adagio)",
                composer: "Ludwig van Beethoven",
                difficulty: .advanced,
                isScanned: false,
                isFavorite: true,
                durationSeconds: 320.0,
                estimatedMeasureCount: 36,
                keySignatureName: "C♯ Minor",
                timeSignatureDisplay: "4/4",
                previewScore: moonlightSonataScore()
            ),
            SongItem(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                title: "Minuet in G major",
                composer: "Christian Petzold / J.S. Bach",
                difficulty: .beginner,
                isScanned: false,
                isFavorite: false,
                durationSeconds: 110.0,
                estimatedMeasureCount: 32,
                keySignatureName: "G Major",
                timeSignatureDisplay: "3/4",
                previewScore: minuetInGScore()
            ),
            SongItem(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                title: "Nocturne Op. 9 No. 2",
                composer: "Frédéric Chopin",
                difficulty: .virtuoso,
                isScanned: false,
                isFavorite: true,
                durationSeconds: 270.0,
                estimatedMeasureCount: 34,
                keySignatureName: "E♭ Major",
                timeSignatureDisplay: "12/8",
                previewScore: chopinNocturneScore()
            ),
            SongItem(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                title: "Gymnopédie No. 1",
                composer: "Erik Satie",
                difficulty: .intermediate,
                isScanned: false,
                isFavorite: false,
                durationSeconds: 195.0,
                estimatedMeasureCount: 28,
                keySignatureName: "D Major",
                timeSignatureDisplay: "3/4",
                previewScore: gymnopedieScore()
            )
        ]
    }
    
    // MARK: - Score Builders
    
    public func furEliseScore() -> Score {
        let timeSig = TimeSignature(numerator: 3, denominator: 8)
        let keySig = KeySignature(fifths: 0, mode: "minor") // A minor
        var measures = [Measure]()
        
        // Measure 0 (Pickup / Measure 1): E5 - D#5 - E5 - D#5 - E5 - B4 - D5 - C5
        // Measure 1: A minor motif
        var currentBeat = 0.0
        let beatUnit = 1.0 // In 3/8, each eighth note is 0.5 beat or 1 count
        
        // Measure 1
        var m1Notes = [NoteEvent]()
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 0)) // E5
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 75), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 0)) // D#5
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 0)) // E5
        measures.append(Measure(index: 0, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m1Notes))
        currentBeat += 1.5
        
        // Measure 2
        var m2Notes = [NoteEvent]()
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 75), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 1)) // D#5
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 1)) // E5
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 71), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 1)) // B4
        measures.append(Measure(index: 1, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m2Notes))
        currentBeat += 1.5
        
        // Measure 3
        var m3Notes = [NoteEvent]()
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 74), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 2)) // D5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 72), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 2)) // C5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 69), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 2)) // A4
        // Left hand A minor bass
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 45), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .left, measureIndex: 2)) // A2
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 52), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .left, measureIndex: 2)) // E3
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 57), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .left, measureIndex: 2)) // A3
        measures.append(Measure(index: 2, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m3Notes))
        currentBeat += 1.5
        
        // Measure 4
        var m4Notes = [NoteEvent]()
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 48), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .left, measureIndex: 3)) // C3
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 55), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .left, measureIndex: 3)) // G3
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 60), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .left, measureIndex: 3)) // C4
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 64), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 3)) // E4
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 69), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 3)) // A4
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 71), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 3)) // B4
        measures.append(Measure(index: 3, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m4Notes))
        currentBeat += 1.5
        
        // Measure 5
        var m5Notes = [NoteEvent]()
        m5Notes.append(NoteEvent(pitch: Pitch(midiNumber: 40), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .left, measureIndex: 4)) // E2
        m5Notes.append(NoteEvent(pitch: Pitch(midiNumber: 52), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .left, measureIndex: 4)) // E3
        m5Notes.append(NoteEvent(pitch: Pitch(midiNumber: 56), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .left, measureIndex: 4)) // G#3
        m5Notes.append(NoteEvent(pitch: Pitch(midiNumber: 64), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 4)) // E4
        m5Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 4)) // E5
        m5Notes.append(NoteEvent(pitch: Pitch(midiNumber: 75), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 4)) // D#5
        measures.append(Measure(index: 4, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m5Notes))
        currentBeat += 1.5
        
        // Measure 6
        var m6Notes = [NoteEvent]()
        m6Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 5)) // E5
        m6Notes.append(NoteEvent(pitch: Pitch(midiNumber: 75), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 5)) // D#5
        m6Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 5)) // E5
        measures.append(Measure(index: 5, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m6Notes))
        currentBeat += 1.5
        
        // Measure 7
        var m7Notes = [NoteEvent]()
        m7Notes.append(NoteEvent(pitch: Pitch(midiNumber: 71), startBeat: currentBeat + 0.0, durationBeats: 0.5, hand: .right, measureIndex: 6)) // B4
        m7Notes.append(NoteEvent(pitch: Pitch(midiNumber: 74), startBeat: currentBeat + 0.5, durationBeats: 0.5, hand: .right, measureIndex: 6)) // D5
        m7Notes.append(NoteEvent(pitch: Pitch(midiNumber: 72), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 6)) // C5
        measures.append(Measure(index: 6, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m7Notes))
        currentBeat += 1.5
        
        // Measure 8
        var m8Notes = [NoteEvent]()
        m8Notes.append(NoteEvent(pitch: Pitch(midiNumber: 69), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .right, measureIndex: 7)) // A4
        m8Notes.append(NoteEvent(pitch: Pitch(midiNumber: 45), startBeat: currentBeat + 0.0, durationBeats: 1.5, hand: .left, measureIndex: 7)) // A2 bass
        m8Notes.append(NoteEvent(pitch: Pitch(midiNumber: 57), startBeat: currentBeat + 0.0, durationBeats: 1.5, hand: .left, measureIndex: 7)) // A3
        measures.append(Measure(index: 7, startBeat: currentBeat, durationBeats: 1.5, timeSignature: timeSig, keySignature: keySig, notes: m8Notes))
        
        return Score(
            title: "Für Elise",
            composer: "Ludwig van Beethoven",
            defaultBPM: 130.0,
            timeSignature: timeSig,
            keySignature: keySig,
            measures: measures
        )
    }
    
    public func moonlightSonataScore() -> Score {
        let timeSig = TimeSignature(numerator: 4, denominator: 4)
        let keySig = KeySignature(fifths: 4, mode: "minor") // C# minor (4 sharps)
        var measures = [Measure]()
        var currentBeat = 0.0
        
        // Measure 1: Deep C# minor bass octaves + continuous triplet arpeggios G#3 - C#4 - E4
        for mIdx in 0..<4 {
            var mNotes = [NoteEvent]()
            
            // Bass octave on beat 0
            let bassRoot = mIdx < 2 ? 37 : (mIdx == 2 ? 35 : 33) // C#2, B1, A1
            mNotes.append(NoteEvent(pitch: Pitch(midiNumber: bassRoot), startBeat: currentBeat, durationBeats: 4.0, velocity: 0.65, hand: .left, measureIndex: mIdx))
            mNotes.append(NoteEvent(pitch: Pitch(midiNumber: bassRoot + 12), startBeat: currentBeat, durationBeats: 4.0, velocity: 0.60, hand: .left, measureIndex: mIdx))
            
            // 4 sets of triplet eighth notes (12 notes per measure)
            for beat in 0..<4 {
                let tripletBeats = [0.0, 0.333, 0.666]
                for (tIdx, tOffset) in tripletBeats.enumerated() {
                    let notePitch: Int
                    switch tIdx {
                    case 0: notePitch = 56 // G#3
                    case 1: notePitch = 61 // C#4
                    default: notePitch = 64 // E4
                    }
                    mNotes.append(NoteEvent(
                        pitch: Pitch(midiNumber: notePitch),
                        startBeat: currentBeat + Double(beat) + tOffset,
                        durationBeats: 0.33,
                        velocity: 0.52,
                        hand: .right,
                        measureIndex: mIdx
                    ))
                }
            }
            
            // Melody entry on measure 3 & 4
            if mIdx >= 2 {
                mNotes.append(NoteEvent(
                    pitch: Pitch(midiNumber: 68), // G#4 dotted rhythm
                    startBeat: currentBeat + 2.5,
                    durationBeats: 1.0,
                    velocity: 0.88,
                    hand: .right,
                    measureIndex: mIdx
                ))
            }
            
            measures.append(Measure(
                index: mIdx,
                startBeat: currentBeat,
                durationBeats: 4.0,
                timeSignature: timeSig,
                keySignature: keySig,
                notes: mNotes
            ))
            currentBeat += 4.0
        }
        
        return Score(
            title: "Moonlight Sonata (Adagio)",
            composer: "Ludwig van Beethoven",
            defaultBPM: 56.0,
            timeSignature: timeSig,
            keySignature: keySig,
            measures: measures
        )
    }
    
    public func minuetInGScore() -> Score {
        let timeSig = TimeSignature(numerator: 3, denominator: 4)
        let keySig = KeySignature(fifths: 1, mode: "major") // G major
        var measures = [Measure]()
        var currentBeat = 0.0
        
        // Measure 1: D5 (quarter) - G4 (eighth) A4 (eighth) - B4 (eighth) C5 (eighth)
        var m1Notes = [NoteEvent]()
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 74), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .right, measureIndex: 0)) // D5
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 67), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 0)) // G4
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 69), startBeat: currentBeat + 1.5, durationBeats: 0.5, hand: .right, measureIndex: 0)) // A4
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 71), startBeat: currentBeat + 2.0, durationBeats: 0.5, hand: .right, measureIndex: 0)) // B4
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 72), startBeat: currentBeat + 2.5, durationBeats: 0.5, hand: .right, measureIndex: 0)) // C5
        // Left hand G major chord
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 43), startBeat: currentBeat + 0.0, durationBeats: 2.0, hand: .left, measureIndex: 0)) // G2
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 55), startBeat: currentBeat + 0.0, durationBeats: 2.0, hand: .left, measureIndex: 0)) // G3
        measures.append(Measure(index: 0, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m1Notes))
        currentBeat += 3.0
        
        // Measure 2: D5 (quarter) - G4 (quarter) - G4 (quarter)
        var m2Notes = [NoteEvent]()
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 74), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .right, measureIndex: 1)) // D5
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 67), startBeat: currentBeat + 1.0, durationBeats: 1.0, hand: .right, measureIndex: 1)) // G4
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 67), startBeat: currentBeat + 2.0, durationBeats: 1.0, hand: .right, measureIndex: 1)) // G4
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 52), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .left, measureIndex: 1)) // E3
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 50), startBeat: currentBeat + 1.0, durationBeats: 1.0, hand: .left, measureIndex: 1)) // D3
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 47), startBeat: currentBeat + 2.0, durationBeats: 1.0, hand: .left, measureIndex: 1)) // B2
        measures.append(Measure(index: 1, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m2Notes))
        currentBeat += 3.0
        
        // Measure 3: E5 (quarter) - C5 (eighth) D5 (eighth) - E5 (eighth) F#5 (eighth)
        var m3Notes = [NoteEvent]()
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .right, measureIndex: 2)) // E5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 72), startBeat: currentBeat + 1.0, durationBeats: 0.5, hand: .right, measureIndex: 2)) // C5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 74), startBeat: currentBeat + 1.5, durationBeats: 0.5, hand: .right, measureIndex: 2)) // D5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 76), startBeat: currentBeat + 2.0, durationBeats: 0.5, hand: .right, measureIndex: 2)) // E5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 78), startBeat: currentBeat + 2.5, durationBeats: 0.5, hand: .right, measureIndex: 2)) // F#5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 48), startBeat: currentBeat + 0.0, durationBeats: 2.0, hand: .left, measureIndex: 2)) // C3
        measures.append(Measure(index: 2, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m3Notes))
        currentBeat += 3.0
        
        // Measure 4: G5 (quarter) - G4 (quarter) - G4 (quarter)
        var m4Notes = [NoteEvent]()
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 79), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .right, measureIndex: 3)) // G5
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 67), startBeat: currentBeat + 1.0, durationBeats: 1.0, hand: .right, measureIndex: 3)) // G4
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 67), startBeat: currentBeat + 2.0, durationBeats: 1.0, hand: .right, measureIndex: 3)) // G4
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 47), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .left, measureIndex: 3)) // B2
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 45), startBeat: currentBeat + 1.0, durationBeats: 1.0, hand: .left, measureIndex: 3)) // A2
        m4Notes.append(NoteEvent(pitch: Pitch(midiNumber: 43), startBeat: currentBeat + 2.0, durationBeats: 1.0, hand: .left, measureIndex: 3)) // G2
        measures.append(Measure(index: 3, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m4Notes))
        
        return Score(
            title: "Minuet in G major",
            composer: "Christian Petzold / J.S. Bach",
            defaultBPM: 116.0,
            timeSignature: timeSig,
            keySignature: keySig,
            measures: measures
        )
    }
    
    public func chopinNocturneScore() -> Score {
        let timeSig = TimeSignature(numerator: 12, denominator: 8)
        let keySig = KeySignature(fifths: -3, mode: "major") // Eb major
        var measures = [Measure]()
        var currentBeat = 0.0
        
        // Beautiful opening phrase: Bb4 - G5 - F5 - Eb5
        var m1Notes = [NoteEvent]()
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 70), startBeat: currentBeat + 0.0, durationBeats: 1.5, hand: .right, measureIndex: 0)) // Bb4
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 79), startBeat: currentBeat + 1.5, durationBeats: 1.5, hand: .right, measureIndex: 0)) // G5
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 77), startBeat: currentBeat + 3.0, durationBeats: 1.0, hand: .right, measureIndex: 0)) // F5
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 75), startBeat: currentBeat + 4.0, durationBeats: 2.0, hand: .right, measureIndex: 0)) // Eb5
        
        // Left hand waltz accompaniment
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 39), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .left, measureIndex: 0)) // Eb2
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 51), startBeat: currentBeat + 1.0, durationBeats: 1.0, hand: .left, measureIndex: 0)) // Eb3
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 55), startBeat: currentBeat + 2.0, durationBeats: 1.0, hand: .left, measureIndex: 0)) // G3
        measures.append(Measure(index: 0, startBeat: currentBeat, durationBeats: 6.0, timeSignature: timeSig, keySignature: keySig, notes: m1Notes))
        
        return Score(
            title: "Nocturne Op. 9 No. 2",
            composer: "Frédéric Chopin",
            defaultBPM: 60.0,
            timeSignature: timeSig,
            keySignature: keySig,
            measures: measures
        )
    }
    
    public func gymnopedieScore() -> Score {
        let timeSig = TimeSignature(numerator: 3, denominator: 4)
        let keySig = KeySignature(fifths: 2, mode: "major") // D major
        var measures = [Measure]()
        var currentBeat = 0.0
        
        // Measure 1: G bass note, followed by B-D-F# chord in LH
        var m1Notes = [NoteEvent]()
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 43), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .left, measureIndex: 0)) // G2
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 59), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 0)) // B3
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 62), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 0)) // D4
        m1Notes.append(NoteEvent(pitch: Pitch(midiNumber: 66), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 0)) // F#4
        measures.append(Measure(index: 0, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m1Notes))
        currentBeat += 3.0
        
        // Measure 2: D bass note, followed by A-C#-F# chord
        var m2Notes = [NoteEvent]()
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 38), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .left, measureIndex: 1)) // D2
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 57), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 1)) // A3
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 61), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 1)) // C#4
        m2Notes.append(NoteEvent(pitch: Pitch(midiNumber: 66), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 1)) // F#4
        measures.append(Measure(index: 1, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m2Notes))
        currentBeat += 3.0
        
        // Measure 3: Melody arrives on F#5
        var m3Notes = [NoteEvent]()
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 78), startBeat: currentBeat + 0.0, durationBeats: 3.0, hand: .right, measureIndex: 2)) // F#5
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 43), startBeat: currentBeat + 0.0, durationBeats: 1.0, hand: .left, measureIndex: 2)) // G2
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 59), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 2)) // B3
        m3Notes.append(NoteEvent(pitch: Pitch(midiNumber: 62), startBeat: currentBeat + 1.0, durationBeats: 2.0, hand: .left, measureIndex: 2)) // D4
        measures.append(Measure(index: 2, startBeat: currentBeat, durationBeats: 3.0, timeSignature: timeSig, keySignature: keySig, notes: m3Notes))
        
        return Score(
            title: "Gymnopédie No. 1",
            composer: "Erik Satie",
            defaultBPM: 72.0,
            timeSignature: timeSig,
            keySignature: keySig,
            measures: measures
        )
    }
}
