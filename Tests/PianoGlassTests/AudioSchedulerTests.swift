//
//  AudioSchedulerTests.swift
//  PianoGlassTests
//
//  Unit tests for AudioScheduler measure lookup and timing arithmetic.
//

import XCTest
@testable import PianoGlass

final class AudioSchedulerTests: XCTestCase {
    var scheduler: AudioScheduler!
    var sampleScore: Score!
    
    override func setUp() {
        super.setUp()
        scheduler = AudioScheduler(audioEngine: PianoAudioEngine.shared)
        
        let timeSig = TimeSignature(numerator: 4, denominator: 4)
        let keySig = KeySignature(fifths: 0)
        
        let m1 = Measure(index: 0, startBeat: 0.0, durationBeats: 4.0, timeSignature: timeSig, keySignature: keySig)
        let m2 = Measure(index: 1, startBeat: 4.0, durationBeats: 4.0, timeSignature: timeSig, keySignature: keySig)
        let m3 = Measure(index: 2, startBeat: 8.0, durationBeats: 4.0, timeSignature: timeSig, keySignature: keySig)
        
        sampleScore = Score(title: "Scheduler Test", composer: "Tester", defaultBPM: 120.0, measures: [m1, m2, m3])
        scheduler.loadScore(sampleScore)
    }
    
    override func tearDown() {
        scheduler.stop()
        scheduler = nil
        super.tearDown()
    }
    
    func testMeasureIndexLookupForBeat() {
        XCTAssertEqual(scheduler.measureIndex(forBeat: 0.0), 0)
        XCTAssertEqual(scheduler.measureIndex(forBeat: 2.5), 0)
        XCTAssertEqual(scheduler.measureIndex(forBeat: 3.99), 0)
        XCTAssertEqual(scheduler.measureIndex(forBeat: 4.0), 1)
        XCTAssertEqual(scheduler.measureIndex(forBeat: 7.9), 1)
        XCTAssertEqual(scheduler.measureIndex(forBeat: 8.0), 2)
        XCTAssertEqual(scheduler.measureIndex(forBeat: 10.0), 2)
    }
    
    func testTotalBeatsCalculation() {
        XCTAssertEqual(scheduler.totalBeats, 12.0)
    }
    
    func testRepeatedNotesOnSamePitch() {
        let n1 = NoteEvent(pitch: Pitch(midiNumber: 60), startBeat: 0.0, durationBeats: 1.0, hand: .right)
        let n2 = NoteEvent(pitch: Pitch(midiNumber: 60), startBeat: 1.0, durationBeats: 1.0, hand: .right)
        
        let m = Measure(
            index: 0,
            startBeat: 0.0,
            durationBeats: 4.0,
            timeSignature: .commonTime,
            keySignature: KeySignature(fifths: 0),
            notes: [n1, n2]
        )
        let repeatedScore = Score(title: "Repeated Notes", composer: "Tester", defaultBPM: 120.0, measures: [m])
        scheduler.loadScore(repeatedScore)
        
        // At beat 0.5: n1 should be active
        scheduler.seek(toBeat: 0.5)
        let exp1 = XCTestExpectation(description: "Beat 0.5")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(self.scheduler.activeNoteEventIds.contains(n1.id))
            XCTAssertFalse(self.scheduler.activeNoteEventIds.contains(n2.id))
            XCTAssertEqual(self.scheduler.activePitches[60], .right)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        
        // At beat 1.5: n2 should be active, n1 inactive
        scheduler.seek(toBeat: 1.5)
        let exp2 = XCTestExpectation(description: "Beat 1.5")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertFalse(self.scheduler.activeNoteEventIds.contains(n1.id))
            XCTAssertTrue(self.scheduler.activeNoteEventIds.contains(n2.id))
            XCTAssertEqual(self.scheduler.activePitches[60], .right)
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)
    }
}
