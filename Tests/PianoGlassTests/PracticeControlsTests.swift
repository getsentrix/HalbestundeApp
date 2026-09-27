//
//  PracticeControlsTests.swift
//  PianoGlassTests
//
//  Unit tests for PracticeSettings, HandIsolation, and LoopRange.
//

import XCTest
@testable import PianoGlass

final class PracticeControlsTests: XCTestCase {
    func testLoopRangeContainment() {
        let loop = LoopRange(startMeasure: 2, endMeasure: 5)
        XCTAssertFalse(loop.contains(measureIndex: 1))
        XCTAssertTrue(loop.contains(measureIndex: 2))
        XCTAssertTrue(loop.contains(measureIndex: 4))
        XCTAssertTrue(loop.contains(measureIndex: 5))
        XCTAssertFalse(loop.contains(measureIndex: 6))
    }
    
    func testHandIsolationFiltering() {
        var settings = PracticeSettings()
        
        // Default: both hands play
        XCTAssertTrue(settings.shouldPlay(hand: .left))
        XCTAssertTrue(settings.shouldPlay(hand: .right))
        
        // Mute Left Hand
        settings.isLeftHandMuted = true
        XCTAssertFalse(settings.shouldPlay(hand: .left))
        XCTAssertTrue(settings.shouldPlay(hand: .right))
        
        // Solo Right Hand
        settings.isLeftHandMuted = false
        settings.isRightHandSolo = true
        XCTAssertFalse(settings.shouldPlay(hand: .left))
        XCTAssertTrue(settings.shouldPlay(hand: .right))
        
        // Solo Left Hand
        settings.isRightHandSolo = false
        settings.isLeftHandSolo = true
        XCTAssertTrue(settings.shouldPlay(hand: .left))
        XCTAssertFalse(settings.shouldPlay(hand: .right))
    }
    
    func testHandVolumeFactor() {
        var settings = PracticeSettings()
        settings.leftHandVolume = 0.5
        settings.rightHandVolume = 0.9
        
        XCTAssertEqual(settings.volume(for: .left), 0.5, accuracy: 0.001)
        XCTAssertEqual(settings.volume(for: .right), 0.9, accuracy: 0.001)
        
        settings.isLeftHandMuted = true
        XCTAssertEqual(settings.volume(for: .left), 0.0, accuracy: 0.001)
    }
    
    func testTempoClamping() {
        let lowSettings = PracticeSettings(tempoBPM: 10.0)
        XCTAssertEqual(lowSettings.tempoBPM, 40.0)
        
        let highSettings = PracticeSettings(tempoBPM: 300.0)
        XCTAssertEqual(highSettings.tempoBPM, 240.0)
    }
}
