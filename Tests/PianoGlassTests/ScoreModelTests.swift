//
//  ScoreModelTests.swift
//  PianoGlassTests
//
//  Unit tests for Pitch, Frequency, Measure, and Score models.
//

import XCTest
@testable import PianoGlass

final class ScoreModelTests: XCTestCase {
    func testPitchFrequencyCalculation() {
        // A4 = MIDI 69 = 440 Hz
        let a4 = Pitch(midiNumber: 69)
        XCTAssertEqual(a4.frequency, 440.0, accuracy: 0.001)
        XCTAssertEqual(a4.noteName, "A")
        XCTAssertEqual(a4.octave, 4)
        XCTAssertEqual(a4.fullDisplayName, "A4")
        XCTAssertFalse(a4.isBlackKey)
        
        // Middle C = C4 = MIDI 60 ≈ 261.63 Hz
        let c4 = Pitch(midiNumber: 60)
        XCTAssertEqual(c4.frequency, 261.6255, accuracy: 0.01)
        XCTAssertEqual(c4.noteName, "C")
        XCTAssertEqual(c4.octave, 4)
        XCTAssertFalse(c4.isBlackKey)
        
        // F#4 = MIDI 66
        let fs4 = Pitch(midiNumber: 66)
        XCTAssertTrue(fs4.isBlackKey)
        XCTAssertEqual(fs4.noteName, "F#")
    }
    
    func testPitchTransposition() {
        let c4 = Pitch(midiNumber: 60)
        let d4 = c4.transposed(by: 2)
        XCTAssertEqual(d4.midiNumber, 62)
        XCTAssertEqual(d4.noteName, "D")
        
        let bb3 = c4.transposed(by: -2)
        XCTAssertEqual(bb3.midiNumber, 58)
        XCTAssertEqual(bb3.noteName, "A#")
    }
    
    func testTimeSignatureMath() {
        let fourFour = TimeSignature(numerator: 4, denominator: 4)
        XCTAssertEqual(fourFour.beatsPerMeasure, 4.0)
        
        let threeEight = TimeSignature(numerator: 3, denominator: 8)
        XCTAssertEqual(threeEight.beatsPerMeasure, 1.5)
        
        let sixEight = TimeSignature(numerator: 6, denominator: 8)
        XCTAssertEqual(sixEight.beatsPerMeasure, 3.0)
    }
    
    func testScoreTotalBeatsAndDuration() {
        let timeSig = TimeSignature(numerator: 4, denominator: 4)
        let keySig = KeySignature(fifths: 0)
        
        let m1 = Measure(index: 0, startBeat: 0.0, durationBeats: 4.0, timeSignature: timeSig, keySignature: keySig)
        let m2 = Measure(index: 1, startBeat: 4.0, durationBeats: 4.0, timeSignature: timeSig, keySignature: keySig)
        let m3 = Measure(index: 2, startBeat: 8.0, durationBeats: 4.0, timeSignature: timeSig, keySignature: keySig)
        
        let score = Score(title: "Test Score", composer: "Test Composer", defaultBPM: 120.0, measures: [m1, m2, m3])
        
        XCTAssertEqual(score.totalBeats, 12.0)
        // At 120 BPM, 12 beats take 6 seconds
        XCTAssertEqual(score.durationSeconds(at: 120.0), 6.0, accuracy: 0.01)
        // At 60 BPM, 12 beats take 12 seconds
        XCTAssertEqual(score.durationSeconds(at: 60.0), 12.0, accuracy: 0.01)
    }
}
