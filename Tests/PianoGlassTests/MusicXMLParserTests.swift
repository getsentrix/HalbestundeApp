//
//  MusicXMLParserTests.swift
//  PianoGlassTests
//
//  Unit tests for MusicXML parsing and exporting.
//

import XCTest
@testable import PianoGlass

final class MusicXMLParserTests: XCTestCase {
    let sampleXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <work><work-title>Test Piece</work-title></work>
      <identification><creator type="composer">Test Composer</creator></identification>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <key><fifths>0</fifths></key>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <staves>2</staves>
          </attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
            <staff>1</staff>
          </note>
          <note>
            <pitch><step>E</step><octave>4</octave></pitch>
            <duration>1</duration>
            <staff>1</staff>
          </note>
          <note>
            <pitch><step>C</step><octave>3</octave></pitch>
            <duration>2</duration>
            <staff>2</staff>
          </note>
        </measure>
      </part>
    </score-partwise>
    """
    
    func testParseValidMusicXML() {
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: sampleXML)
        
        XCTAssertNotNil(score)
        XCTAssertEqual(score?.title, "Test Piece")
        XCTAssertEqual(score?.composer, "Test Composer")
        XCTAssertEqual(score?.measures.count, 1)
        
        guard let measure = score?.measures.first else {
            XCTFail("Measure not parsed")
            return
        }
        
        XCTAssertEqual(measure.notes.count, 3)
        // Right hand notes
        let rhNotes = measure.rightHandNotes
        XCTAssertEqual(rhNotes.count, 2)
        XCTAssertEqual(rhNotes[0].pitch.midiNumber, 60) // C4
        XCTAssertEqual(rhNotes[0].startBeat, 0.0)
        XCTAssertEqual(rhNotes[1].pitch.midiNumber, 64) // E4
        XCTAssertEqual(rhNotes[1].startBeat, 1.0)
        
        // Left hand notes - must start simultaneously at beat 0.0 of measure
        let lhNotes = measure.leftHandNotes
        XCTAssertEqual(lhNotes.count, 1)
        XCTAssertEqual(lhNotes[0].pitch.midiNumber, 48) // C3
        XCTAssertEqual(lhNotes[0].startBeat, 0.0)
    }
    
    func testMusicXMLWithBackupAndChords() {
        let xmlWithBackup = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <work><work-title>Polyphonic Piece</work-title></work>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>2</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <staves>2</staves>
              </attributes>
              <!-- Right Hand Voice 1 Chord -->
              <note>
                <pitch><step>C</step><octave>5</octave></pitch>
                <duration>2</duration>
                <voice>1</voice>
                <staff>1</staff>
              </note>
              <note>
                <chord/>
                <pitch><step>E</step><octave>5</octave></pitch>
                <duration>2</duration>
                <voice>1</voice>
                <staff>1</staff>
              </note>
              <!-- Backup to start of measure for Left Hand -->
              <backup>
                <duration>2</duration>
              </backup>
              <!-- Left Hand Voice 2 -->
              <note>
                <pitch><step>C</step><octave>3</octave></pitch>
                <duration>2</duration>
                <voice>2</voice>
                <staff>2</staff>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: xmlWithBackup)
        XCTAssertNotNil(score)
        guard let measure = score?.measures.first else {
            XCTFail("Measure not parsed")
            return
        }
        
        // C5 and E5 should both have startBeat 0.0 (chord)
        let rhNotes = measure.rightHandNotes
        XCTAssertEqual(rhNotes.count, 2)
        XCTAssertEqual(rhNotes[0].startBeat, 0.0)
        XCTAssertEqual(rhNotes[1].startBeat, 0.0)
        
        // Left hand C3 should also have startBeat 0.0 (rewound by backup)
        let lhNotes = measure.leftHandNotes
        XCTAssertEqual(lhNotes.count, 1)
        XCTAssertEqual(lhNotes[0].startBeat, 0.0)
    }
    
    func testMusicXMLExporterProducesValidXML() {
        let parser = MusicXMLParser()
        guard let originalScore = parser.parse(xmlString: sampleXML) else {
            XCTFail("Original parse failed")
            return
        }
        
        let exporter = MusicXMLExporter()
        let exportedXML = exporter.export(score: originalScore)
        
        XCTAssertTrue(exportedXML.contains("<work-title>Test Piece</work-title>"))
        XCTAssertTrue(exportedXML.contains("<creator type=\"composer\">Test Composer</creator>"))
        XCTAssertTrue(exportedXML.contains("<step>C</step>"))
        XCTAssertTrue(exportedXML.contains("<backup>"))
        
        // Re-parse exported XML to ensure round-trip integrity
        let reScore = parser.parse(xmlString: exportedXML)
        XCTAssertNotNil(reScore)
        XCTAssertEqual(reScore?.measures.count, originalScore.measures.count)
        
        // Verify LH note startBeat is preserved on round-trip
        let reLHNotes = reScore?.measures.first?.leftHandNotes
        XCTAssertEqual(reLHNotes?.count, 1)
        XCTAssertEqual(reLHNotes?.first?.startBeat, 0.0)
    }
    
    func testSynthesizeFallbackMeasures() {
        let measures = NoteRecognitionEngine.synthesizeFallbackMeasures(title: "Fallback Piece")
        XCTAssertEqual(measures.count, 4)
        for measure in measures {
            XCTAssertFalse(measure.rightHandNotes.isEmpty, "RH notes should not be empty")
            XCTAssertFalse(measure.leftHandNotes.isEmpty, "LH notes should not be empty")
            XCTAssertEqual(measure.durationBeats, 4.0)
        }
    }
    
    func testStorageServiceSaveAndLoadScore() {
        let storage = ScanStorageService.shared
        let testScore = Score(
            title: "Storage Test Score",
            composer: "Test Artist",
            defaultBPM: 120.0,
            measures: NoteRecognitionEngine.synthesizeFallbackMeasures(title: "Storage Test Score")
        )
        
        let savedItem = storage.saveScore(testScore)
        XCTAssertEqual(savedItem.title, "Storage Test Score")
        XCTAssertTrue(savedItem.isScanned)
        XCTAssertNotNil(savedItem.previewScore)
        
        let loaded = storage.loadScannedSongs()
        XCTAssertTrue(loaded.contains(where: { $0.id == savedItem.id }))
        
        // Clean up
        storage.deleteScannedSong(withId: savedItem.id)
        let afterDelete = storage.loadScannedSongs()
        XCTAssertFalse(afterDelete.contains(where: { $0.id == savedItem.id }))
    }
    
    func testScannerViewModelFallback() {
        let vm = ScannerViewModel()
        let fallback = vm.createFallbackScore(title: "My Étude")
        XCTAssertEqual(fallback.title, "My Étude")
        XCTAssertEqual(fallback.measures.count, 4)
        XCTAssertEqual(fallback.measures[0].rightHandNotes.count, 4)
        XCTAssertEqual(fallback.measures[0].leftHandNotes.count, 4)
        
        let saved = vm.saveAndOpenScore(score: fallback)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.title, "My Étude")
        
        // Clean up
        if let id = saved?.id {
            ScanStorageService.shared.deleteScannedSong(withId: id)
        }
    }
    
    func testSongLibraryViewModelImportFile() {
        let libVM = SongLibraryViewModel()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_piece.musicxml")
        try? sampleXML.write(to: tempURL, atomically: true, encoding: .utf8)
        
        let expectation = expectation(description: "Import file completes")
        libVM.importFile(at: tempURL) { importedScore in
            XCTAssertEqual(importedScore.title, "Test Piece")
            XCTAssertEqual(importedScore.measures.count, 1)
            XCTAssertFalse(libVM.allSongs.isEmpty)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        try? FileManager.default.removeItem(at: tempURL)
    }
}
