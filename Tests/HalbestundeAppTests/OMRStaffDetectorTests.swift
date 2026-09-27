//
//  OMRStaffDetectorTests.swift
//  HalbestundeAppTests
//
//  Unit tests for OMR geometric staff position to musical pitch mapping.
//

import XCTest
@testable import HalbestundeApp

final class OMRStaffDetectorTests: XCTestCase {
    func testTrebleClefPitchMapping() {
        // Line 1 (bottom line, position 0.0) = E4 (MIDI 64)
        let line1 = NoteRecognitionEngine.pitchForStaffPosition(position: 0.0, clef: .treble)
        XCTAssertEqual(line1.midiNumber, 64)
        XCTAssertEqual(line1.noteName, "E")
        XCTAssertEqual(line1.octave, 4)
        
        // Space 1 (position 0.5) = F4 (MIDI 65)
        let space1 = NoteRecognitionEngine.pitchForStaffPosition(position: 0.5, clef: .treble)
        XCTAssertEqual(space1.midiNumber, 65)
        XCTAssertEqual(space1.noteName, "F")
        
        // Line 2 (position 1.0) = G4 (MIDI 67)
        let line2 = NoteRecognitionEngine.pitchForStaffPosition(position: 1.0, clef: .treble)
        XCTAssertEqual(line2.midiNumber, 67)
        XCTAssertEqual(line2.noteName, "G")
        
        // Line 3 (middle line, position 2.0) = B4 (MIDI 71)
        let line3 = NoteRecognitionEngine.pitchForStaffPosition(position: 2.0, clef: .treble)
        XCTAssertEqual(line3.midiNumber, 71)
        XCTAssertEqual(line3.noteName, "B")
        
        // Top line 5 (position 4.0) = F5 (MIDI 77)
        let line5 = NoteRecognitionEngine.pitchForStaffPosition(position: 4.0, clef: .treble)
        XCTAssertEqual(line5.midiNumber, 77)
        XCTAssertEqual(line5.noteName, "F")
        
        // Middle C (Ledger line 1 below treble, position -1.0) = C4 (MIDI 60)
        let middleC = NoteRecognitionEngine.pitchForStaffPosition(position: -1.0, clef: .treble)
        XCTAssertEqual(middleC.midiNumber, 60)
        XCTAssertEqual(middleC.noteName, "C")
        XCTAssertEqual(middleC.octave, 4)
    }
    
    func testBassClefPitchMapping() {
        // Line 1 (bottom line, position 0.0) = G2 (MIDI 43)
        let line1 = NoteRecognitionEngine.pitchForStaffPosition(position: 0.0, clef: .bass)
        XCTAssertEqual(line1.midiNumber, 43)
        XCTAssertEqual(line1.noteName, "G")
        XCTAssertEqual(line1.octave, 2)
        
        // Line 4 (F clef line between two dots, position 3.0) = F3 (MIDI 53)
        let line4 = NoteRecognitionEngine.pitchForStaffPosition(position: 3.0, clef: .bass)
        XCTAssertEqual(line4.midiNumber, 53)
        XCTAssertEqual(line4.noteName, "F")
        XCTAssertEqual(line4.octave, 3)
        
        // Middle C (Ledger line 1 above bass, position 5.0) = C4 (MIDI 60)
        let middleC = NoteRecognitionEngine.pitchForStaffPosition(position: 5.0, clef: .bass)
        XCTAssertEqual(middleC.midiNumber, 60)
        XCTAssertEqual(middleC.noteName, "C")
        XCTAssertEqual(middleC.octave, 4)
    }
    
    func testScoreRecognitionFromMockSystems() {
        let detector = VisionStaffDetector()
        let systems = [
            DetectedStaffSystem(
                systemIndex: 0,
                trebleStaffLines: [100, 110, 120, 130, 140],
                bassStaffLines: [200, 210, 220, 230, 240],
                staffLineSpacing: 10.0,
                barlineXPositions: [50, 250, 450, 650],
                bounds: CGRect(x: 0, y: 80, width: 700, height: 180)
            )
        ]
        
        let engine = NoteRecognitionEngine()
        let score = engine.recognizeScore(from: systems, title: "Test OMR")
        
        // 3 measures formed by 4 barlines
        XCTAssertEqual(score.measures.count, 3)
        XCTAssertEqual(score.title, "Test OMR")
        
        // Each measure has notes for both RH and LH
        for measure in score.measures {
            XCTAssertFalse(measure.rightHandNotes.isEmpty)
            XCTAssertFalse(measure.leftHandNotes.isEmpty)
        }
    }
}
