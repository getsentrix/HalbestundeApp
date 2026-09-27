//
//  MusicModels.swift
//  PianoGlass
//
//  Created for PianoGlass Piano Sheet Music Scanner & Player.
//

import Foundation
import CoreGraphics

// MARK: - Hand Designation
public enum Hand: String, Codable, CaseIterable, Identifiable {
    case left = "Left Hand"
    case right = "Right Hand"
    
    public var id: String { rawValue }
    
    public var defaultClef: Clef {
        switch self {
        case .left: return .bass
        case .right: return .treble
        }
    }
}

// MARK: - Musical Clef
public enum Clef: String, Codable, CaseIterable, Identifiable {
    case treble = "G"
    case bass = "F"
    case alto = "C"
    
    public var id: String { rawValue }
    
    public var symbol: String {
        switch self {
        case .treble: return "𝄞"
        case .bass: return "𝄢"
        case .alto: return "𝄡"
        }
    }
}

// MARK: - Accidental
public enum Accidental: String, Codable, CaseIterable {
    case natural = "♮"
    case sharp = "♯"
    case flat = "♭"
    case doubleSharp = "𝄪"
    case doubleFlat = "𝄫"
    
    public var semitoneOffset: Int {
        switch self {
        case .natural: return 0
        case .sharp: return 1
        case .flat: return -1
        case .doubleSharp: return 2
        case .doubleFlat: return -2
        }
    }
}

// MARK: - Musical Pitch
public struct Pitch: Codable, Hashable, Comparable, Identifiable {
    public var id: Int { midiNumber }
    
    /// MIDI note number (21 = A0, 60 = Middle C / C4, 108 = C8)
    public let midiNumber: Int
    
    public init(midiNumber: Int) {
        self.midiNumber = max(0, min(127, midiNumber))
    }
    
    public init(name: String, octave: Int, accidental: Accidental = .natural) {
        let basePitches: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
        ]
        let base = basePitches[name.uppercased()] ?? 0
        let midi = (octave + 1) * 12 + base + accidental.semitoneOffset
        self.midiNumber = max(0, min(127, midi))
    }
    
    public var frequency: Double {
        // A4 = 440 Hz = MIDI 69
        return 440.0 * pow(2.0, Double(midiNumber - 69) / 12.0)
    }
    
    public var noteName: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let index = midiNumber % 12
        return noteNames[index]
    }
    
    public var octave: Int {
        return (midiNumber / 12) - 1
    }
    
    public var fullDisplayName: String {
        return "\(noteName)\(octave)"
    }
    
    public var isBlackKey: Bool {
        let semitone = midiNumber % 12
        return [1, 3, 6, 8, 10].contains(semitone)
    }
    
    public func transposed(by semitones: Int) -> Pitch {
        return Pitch(midiNumber: midiNumber + semitones)
    }
    
    public static func < (lhs: Pitch, rhs: Pitch) -> Bool {
        lhs.midiNumber < rhs.midiNumber
    }
}

// MARK: - Note Duration
public enum NoteDuration: Double, Codable, CaseIterable {
    case whole = 4.0
    case half = 2.0
    case quarter = 1.0
    case eighth = 0.5
    case sixteenth = 0.25
    case thirtySecond = 0.125
    case dottedHalf = 3.0
    case dottedQuarter = 1.5
    case dottedEighth = 0.75
    case tripletQuarter = 0.6666666666666666
    case tripletEighth = 0.3333333333333333
    
    public var beats: Double { rawValue }
    
    public var name: String {
        switch self {
        case .whole: return "Whole"
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .sixteenth: return "Sixteenth"
        case .thirtySecond: return "Thirty-Second"
        case .dottedHalf: return "Dotted Half"
        case .dottedQuarter: return "Dotted Quarter"
        case .dottedEighth: return "Dotted Eighth"
        case .tripletQuarter: return "Triplet Quarter"
        case .tripletEighth: return "Triplet Eighth"
        }
    }
}

// MARK: - Note Event
public struct NoteEvent: Identifiable, Codable, Hashable {
    public let id: UUID
    public let pitch: Pitch
    /// Start position in beats relative to the score beginning
    public let startBeat: Double
    /// Duration of the note in beats (1.0 = quarter note in 4/4)
    public let durationBeats: Double
    /// Note velocity / dynamic volume from 0.0 to 1.0
    public var velocity: Float
    /// Assigned playing hand (Right Hand / Treble vs Left Hand / Bass)
    public var hand: Hand
    /// Which measure this note belongs to (0-indexed)
    public var measureIndex: Int
    /// Whether this event is a musical rest
    public var isRest: Bool
    /// Optional graphical bounding box in the original sheet music image
    public var boundingBox: CGRect?
    /// Musical accidental override, if explicitly printed
    public var accidental: Accidental?
    
    public init(
        id: UUID = UUID(),
        pitch: Pitch,
        startBeat: Double,
        durationBeats: Double,
        velocity: Float = 0.8,
        hand: Hand,
        measureIndex: Int = 0,
        isRest: Bool = false,
        boundingBox: CGRect? = nil,
        accidental: Accidental? = nil
    ) {
        self.id = id
        self.pitch = pitch
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.velocity = velocity
        self.hand = hand
        self.measureIndex = measureIndex
        self.isRest = isRest
        self.boundingBox = boundingBox
        self.accidental = accidental
    }
    
    public var endBeat: Double {
        return startBeat + durationBeats
    }
    
    public static func == (lhs: NoteEvent, rhs: NoteEvent) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Time Signature
public struct TimeSignature: Codable, Equatable {
    public let numerator: Int
    public let denominator: Int
    
    public init(numerator: Int = 4, denominator: Int = 4) {
        self.numerator = max(1, numerator)
        self.denominator = max(1, denominator)
    }
    
    public var beatsPerMeasure: Double {
        return Double(numerator) * (4.0 / Double(denominator))
    }
    
    public var displayString: String {
        return "\(numerator)/\(denominator)"
    }
    
    public static let commonTime = TimeSignature(numerator: 4, denominator: 4)
    public static let waltzTime = TimeSignature(numerator: 3, denominator: 4)
    public static let cutTime = TimeSignature(numerator: 2, denominator: 2)
    public static let sixEight = TimeSignature(numerator: 6, denominator: 8)
}

// MARK: - Key Signature
public struct KeySignature: Codable, Equatable {
    /// Fifth offset (-7 to +7, e.g. -1 is F major/D minor, 1 is G major/E minor, 0 is C major/A minor)
    public let fifths: Int
    public let mode: String
    
    public init(fifths: Int = 0, mode: String = "major") {
        self.fifths = fifths
        self.mode = mode
    }
    
    public var name: String {
        let majorKeys = [
            -7: "C♭ Major", -6: "G♭ Major", -5: "D♭ Major", -4: "A♭ Major",
            -3: "E♭ Major", -2: "B♭ Major", -1: "F Major", 0: "C Major",
            1: "G Major", 2: "D Major", 3: "A Major", 4: "E Major",
            5: "B Major", 6: "F♯ Major", 7: "C♯ Major"
        ]
        let minorKeys = [
            -7: "A♭ Minor", -6: "E♭ Minor", -5: "B♭ Minor", -4: "F Minor",
            -3: "C Minor", -2: "G Minor", -1: "D Minor", 0: "A Minor",
            1: "E Minor", 2: "B Minor", 3: "F♯ Minor", 4: "C♯ Minor",
            5: "G♯ Minor", 6: "D♯ Minor", 7: "A♯ Minor"
        ]
        if mode.lowercased() == "minor" {
            return minorKeys[fifths] ?? "\(fifths) sharps/flats Minor"
        } else {
            return majorKeys[fifths] ?? "\(fifths) sharps/flats Major"
        }
    }
}

// MARK: - Measure Model
public struct Measure: Identifiable, Codable, Equatable {
    public let id: UUID
    public let index: Int
    public var startBeat: Double
    public var durationBeats: Double
    public var timeSignature: TimeSignature
    public var keySignature: KeySignature
    public var notes: [NoteEvent]
    public var boundingBox: CGRect?
    
    public init(
        id: UUID = UUID(),
        index: Int,
        startBeat: Double,
        durationBeats: Double,
        timeSignature: TimeSignature,
        keySignature: KeySignature,
        notes: [NoteEvent] = [],
        boundingBox: CGRect? = nil
    ) {
        self.id = id
        self.index = index
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.notes = notes
        self.boundingBox = boundingBox
    }
    
    public var rightHandNotes: [NoteEvent] {
        notes.filter { $0.hand == .right && !$0.isRest }
    }
    
    public var leftHandNotes: [NoteEvent] {
        notes.filter { $0.hand == .left && !$0.isRest }
    }
    
    public static func == (lhs: Measure, rhs: Measure) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index && lhs.startBeat == rhs.startBeat && lhs.notes == rhs.notes
    }
}

// MARK: - Full Score Model
public struct Score: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var composer: String
    public var defaultBPM: Double
    public var timeSignature: TimeSignature
    public var keySignature: KeySignature
    public var measures: [Measure]
    public var scanImageURL: URL?
    
    public init(
        id: UUID = UUID(),
        title: String,
        composer: String,
        defaultBPM: Double = 120.0,
        timeSignature: TimeSignature = .commonTime,
        keySignature: KeySignature = KeySignature(fifths: 0, mode: "major"),
        measures: [Measure] = [],
        scanImageURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.defaultBPM = defaultBPM
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.measures = measures
        self.scanImageURL = scanImageURL
    }
    
    public var allNotes: [NoteEvent] {
        measures.flatMap { $0.notes }
    }
    
    public var totalBeats: Double {
        if let lastMeasure = measures.last {
            return lastMeasure.startBeat + lastMeasure.durationBeats
        }
        return 0.0
    }
    
    public func durationSeconds(at bpm: Double) -> Double {
        guard bpm > 0 else { return 0 }
        return (totalBeats / bpm) * 60.0
    }
    
    public var measureCount: Int {
        measures.count
    }
    
    public static func == (lhs: Score, rhs: Score) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.measures == rhs.measures
    }
    
    public static let empty = Score(
        title: "No Score Selected",
        composer: "",
        defaultBPM: 120.0,
        timeSignature: .commonTime,
        keySignature: KeySignature(fifths: 0, mode: "major"),
        measures: []
    )
}
