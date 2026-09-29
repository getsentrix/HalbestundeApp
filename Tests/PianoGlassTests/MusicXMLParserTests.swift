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
    
    func testTiedNotesParsing() {
        let tiedXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>4</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <staves>1</staves>
              </attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>16</duration>
                <tie type="start"/>
                <staff>1</staff>
              </note>
            </measure>
            <measure number="2">
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>4</duration>
                <tie type="stop"/>
                <staff>1</staff>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: tiedXML)
        XCTAssertNotNil(score)
        XCTAssertEqual(score?.measures.count, 2)
        
        let m1Notes = score?.measures[0].notes ?? []
        let m2Notes = score?.measures[1].notes ?? []
        
        XCTAssertEqual(m1Notes.count, 1)
        XCTAssertFalse(m1Notes[0].isTiedContinuation, "First note should not be tied continuation")
        
        XCTAssertEqual(m2Notes.count, 1)
        XCTAssertTrue(m2Notes[0].isTiedContinuation, "Second note must be marked as tied continuation")
        XCTAssertEqual(m2Notes[0].pitch.midiNumber, 60)
    }
    
    func testNoteDurationTypeFallback() {
        let fallbackTypeXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>4</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <staves>1</staves>
              </attributes>
              <note>
                <pitch><step>G</step><octave>4</octave></pitch>
                <type>quarter</type>
                <staff>1</staff>
              </note>
              <note>
                <pitch><step>E</step><octave>4</octave></pitch>
                <type>half</type>
                <staff>1</staff>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: fallbackTypeXML)
        XCTAssertNotNil(score)
        let notes = score?.measures.first?.notes ?? []
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].durationBeats, 1.0, "Quarter note fallback should equal 1.0 beat")
        XCTAssertEqual(notes[1].durationBeats, 2.0, "Half note fallback should equal 2.0 beats")
    }
    
    func testKeySignatureAccidentalResolution() {
        // G Major (1 sharp): F4 should resolve to F#4 (MIDI 66) without explicit alter
        let gMajorXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>4</divisions>
                <key><fifths>1</fifths><mode>major</mode></key>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <staves>1</staves>
              </attributes>
              <note>
                <pitch><step>F</step><octave>4</octave></pitch>
                <duration>4</duration>
                <staff>1</staff>
              </note>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>4</duration>
                <staff>1</staff>
              </note>
            </measure>
          </part>
        </score-partwise>
        """
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: gMajorXML)
        XCTAssertNotNil(score)
        let notes = score?.measures.first?.notes ?? []
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].pitch.midiNumber, 66, "F4 in G Major (1 sharp) must resolve to F#4 (66)")
        XCTAssertEqual(notes[0].accidental, .sharp)
        XCTAssertEqual(notes[1].pitch.midiNumber, 60, "C4 in G Major must remain C4 (60)")
    }

    // MARK: - Ground Truth & Repair Tests (F15)
    
    private func loadBohemianRhapsodySampleXML() -> String {
        let candidatePaths = [
            "assets/Bohemian_Rhapsody_Sample.musicxml",
            "../assets/Bohemian_Rhapsody_Sample.musicxml",
            "../../assets/Bohemian_Rhapsody_Sample.musicxml",
            "../../../assets/Bohemian_Rhapsody_Sample.musicxml"
        ]
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8),
               !content.isEmpty {
                return content
            }
        }
        if let bundlePath = Bundle(for: MusicXMLParserTests.self).path(forResource: "Bohemian_Rhapsody_Sample", ofType: "musicxml"),
           let content = try? String(contentsOfFile: bundlePath, encoding: .utf8),
           !content.isEmpty {
            return content
        }
        return bohemianRhapsodyXMLFallback
    }
    
    func testBohemianRhapsodySampleGroundTruthParsing() {
        let xmlString = loadBohemianRhapsodySampleXML()
        XCTAssertFalse(xmlString.isEmpty, "Sample score XML should not be empty")
        
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: xmlString)
        
        XCTAssertNotNil(score, "Score must parse cleanly")
        guard let score = score else { return }
        
        // 1. Verify Score Title & Composer
        XCTAssertTrue(score.title.contains("Bohemian Rhapsody"), "Title must contain 'Bohemian Rhapsody'")
        XCTAssertTrue(score.composer.contains("Freddie Mercury"), "Composer must contain 'Freddie Mercury'")
        
        // 2. Verify Key Signature: Bb Major (fifths = -2)
        XCTAssertEqual(score.keySignature.fifths, -2, "Key signature must be Bb Major (fifths = -2)")
        XCTAssertEqual(score.keySignature.mode, "major", "Mode must be major")
        
        // 3. Verify Time Signature: 4/4 meter
        XCTAssertEqual(score.timeSignature.numerator, 4, "Time signature numerator must be 4")
        XCTAssertEqual(score.timeSignature.denominator, 4, "Time signature denominator must be 4")
        
        // 4. Verify 2 Measures
        XCTAssertEqual(score.measures.count, 2, "Must contain exactly 2 measures")
        
        // 5. Verify 32 Total Notes
        let allNotes = score.measures.flatMap { $0.notes }
        XCTAssertEqual(allNotes.count, 32, "Must contain exactly 32 note events")
        
        // 6. Verify Polyphonic Grand-Staff Separation in Measure 1
        let m1 = score.measures[0]
        XCTAssertEqual(m1.notes.count, 16, "Measure 1 must have 16 total notes")
        XCTAssertEqual(m1.rightHandNotes.count, 12, "Measure 1 RH must have 12 notes (4 chords x 3 notes)")
        XCTAssertEqual(m1.leftHandNotes.count, 4, "Measure 1 LH must have 4 notes (2 half-note chords x 2 notes)")
        
        // Check timeline synchronization: both hands start at beat 0.0 of measure
        XCTAssertEqual(m1.rightHandNotes.first?.startBeat, 0.0, "RH must start at beat 0.0")
        XCTAssertEqual(m1.leftHandNotes.first?.startBeat, 0.0, "LH must start at beat 0.0 after backup rewind")
        
        // Pitches in Measure 1:
        // RH first chord: Bb3 (58), D4 (62), F4 (65)
        XCTAssertEqual(m1.rightHandNotes[0].pitch.midiNumber, 58, "RH note 0 must be Bb3 (58)")
        XCTAssertEqual(m1.rightHandNotes[1].pitch.midiNumber, 62, "RH note 1 must be D4 (62)")
        XCTAssertEqual(m1.rightHandNotes[2].pitch.midiNumber, 65, "RH note 2 must be F4 (65)")
        
        // LH first chord: Bb1 (34), Bb2 (46)
        XCTAssertEqual(m1.leftHandNotes[0].pitch.midiNumber, 34, "LH note 0 must be Bb1 (34)")
        XCTAssertEqual(m1.leftHandNotes[1].pitch.midiNumber, 46, "LH note 1 must be Bb2 (46)")
        
        // 7. Verify Polyphonic Grand-Staff Separation in Measure 2
        let m2 = score.measures[1]
        XCTAssertEqual(m2.notes.count, 16, "Measure 2 must have 16 total notes")
        XCTAssertEqual(m2.rightHandNotes.count, 12, "Measure 2 RH must have 12 notes")
        XCTAssertEqual(m2.leftHandNotes.count, 4, "Measure 2 LH must have 4 notes")
        
        // LH chords in Measure 2: Eb2 (39), Eb3 (51)
        XCTAssertEqual(m2.leftHandNotes[0].pitch.midiNumber, 39, "LH chord 1 note 0 must be Eb2 (39)")
        XCTAssertEqual(m2.leftHandNotes[1].pitch.midiNumber, 51, "LH chord 1 note 1 must be Eb3 (51)")
    }
    
    func testMusicXMLRepairEngineTruncatedXMLRecovery() {
        let truncatedXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <key><fifths>-2</fifths></key>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <staves>2</staves>
              </attributes>
              <note>
                <pitch><step>B</step><alter>-1</alter><octave>3</octave></pitch>
                <duration>1</duration>
                <staff>1</staff>
              </note>
              <note>
                <pitch><step>D</step><octave>4</octave></pitch>
                <duration>1</duration>
                <staff>1</staff>
              </note>
            </measure>
            <measure number="2">
              <note>
                <pitch><step>G</step><octave>3</octave></pitch>
                <duration>1</duration>
                <staff>1</staff>
              </note>
              <note>
                <pitch><step>B</step><alter>-1
        """
        
        let repaired = MusicXMLRepairEngine.repairTruncatedXML(truncatedXML)
        XCTAssertFalse(repaired.isEmpty, "Repaired XML must not be empty")
        XCTAssertTrue(repaired.contains("</measure>"), "Repaired XML must end with completed measure")
        XCTAssertTrue(repaired.contains("</part>"), "Repaired XML must close part tag")
        XCTAssertTrue(repaired.contains("</score-partwise>"), "Repaired XML must close root tag")
        XCTAssertFalse(repaired.contains("<alter>-1\n"), "Dangling incomplete tags must be stripped")
        
        // Must validate structure
        XCTAssertTrue(MusicXMLRepairEngine.validateMusicXMLStructure(repaired), "Repaired XML must have valid XML structure")
        
        // Must parse into a playable Score with the recovered measure
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: repaired)
        XCTAssertNotNil(score, "Repaired XML must parse into a Score")
        XCTAssertEqual(score?.measures.count, 1, "Must recover 1 complete measure")
        XCTAssertEqual(score?.measures.first?.notes.count, 2, "Recovered measure must have 2 complete notes")
    }
    
    func testMusicXMLRepairEngineMarkdownAndEntitySanitization() {
        let rawAIResponse = """
        Here is the transcribed sheet music for the piece:
        ```xml
        <score-partwise version="3.1">
          <work><work-title>Fish & Chips</work-title></work>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
              </attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>4</duration>
                <staff>1</staff>
              </note>
            </measure>
          </part>
        </score-partwise>
        ```
        Let me know if you need more measures!
        """
        
        let repaired = MusicXMLRepairEngine.repairTruncatedXML(rawAIResponse)
        XCTAssertFalse(repaired.contains("```"), "Markdown fences must be stripped")
        XCTAssertFalse(repaired.contains("Here is the transcribed"), "Preamble must be stripped")
        XCTAssertFalse(repaired.contains("Let me know"), "Postscript must be stripped")
        XCTAssertTrue(repaired.contains("Fish &amp; Chips"), "Naked ampersands must be sanitized to &amp;")
        
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: repaired)
        XCTAssertNotNil(score, "Repaired AI response must parse cleanly")
        XCTAssertEqual(score?.title, "Fish & Chips", "Title must be recovered")
    }
    
    func testMusicXMLRepairEngineMissingEnvelopes() {
        let rawMeasureOnly = """
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <staves>1</staves>
          </attributes>
          <note>
            <pitch><step>A</step><octave>4</octave></pitch>
            <duration>4</duration>
            <staff>1</staff>
          </note>
        </measure>
        """
        
        let repaired = MusicXMLRepairEngine.repairTruncatedXML(rawMeasureOnly)
        XCTAssertTrue(repaired.contains("<score-partwise"), "Must synthesize score-partwise root")
        XCTAssertTrue(repaired.contains("<part-list>"), "Must synthesize part-list")
        XCTAssertTrue(repaired.contains("<part id=\"P1\">"), "Must synthesize part tag")
        
        let parser = MusicXMLParser()
        let score = parser.parse(xmlString: repaired)
        XCTAssertNotNil(score, "Synthesized envelope score must parse")
        XCTAssertEqual(score?.measures.count, 1)
        XCTAssertEqual(score?.measures.first?.notes.first?.pitch.midiNumber, 69) // A4
    }
    
    private let bohemianRhapsodyXMLFallback = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="3.1">
  <work>
    <work-title>Bohemian Rhapsody (Piano Intro)</work-title>
  </work>
  <identification>
    <creator type="composer">Freddie Mercury / Queen</creator>
    <encoding>
      <software>PianoGlass MusicXML Validator</software>
      <encoding-date>2026-09-27</encoding-date>
    </encoding>
  </identification>
  <part-list>
    <score-part id="P1">
      <part-name>Piano</part-name>
    </score-part>
  </part-list>
  <part id="P1">
    <!-- Measure 1 -->
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key>
          <fifths>-2</fifths>
          <mode>major</mode>
        </key>
        <time>
          <beats>4</beats>
          <beat-type>4</beat-type>
        </time>
        <staves>2</staves>
        <clef number="1">
          <sign>G</sign>
          <line>2</line>
        </clef>
        <clef number="2">
          <sign>F</sign>
          <line>4</line>
        </clef>
      </attributes>
      <direction placement="above">
        <direction-type>
          <metronome>
            <beat-unit>quarter</beat-unit>
            <per-minute>72</per-minute>
          </metronome>
        </direction-type>
        <sound tempo="72"/>
      </direction>
      <!-- RH: Chord Bb3, D4, F4 on beat 1 -->
      <note>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>D</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>F</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- RH: Chord Bb3, D4, F4 on beat 2 -->
      <note>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>D</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>F</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- RH: Chord Bb3, D4, F4 on beat 3 -->
      <note>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>D</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>F</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- RH: Chord A3, C4, F4 on beat 4 -->
      <note>
        <pitch>
          <step>A</step>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>C</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>F</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- LH Staff 2 via backup -->
      <backup>
        <duration>4</duration>
      </backup>
      <!-- LH: Bb1 + Bb2 half note on beat 1-2 -->
      <note>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>1</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>2</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
      <!-- LH: D2 + D3 half note on beat 3-4 -->
      <note>
        <pitch>
          <step>D</step>
          <octave>2</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>D</step>
          <octave>3</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
    </measure>
    <!-- Measure 2 -->
    <measure number="2">
      <!-- RH: Chord G3, Bb3, Eb4 on beat 1 -->
      <note>
        <pitch>
          <step>G</step>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>E</step>
          <alter>-1</alter>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- RH: Chord G3, Bb3, Eb4 on beat 2 -->
      <note>
        <pitch>
          <step>G</step>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>E</step>
          <alter>-1</alter>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- RH: Chord G3, Bb3, Eb4 on beat 3 -->
      <note>
        <pitch>
          <step>G</step>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>E</step>
          <alter>-1</alter>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- RH: Chord F3, Bb3, D4 on beat 4 -->
      <note>
        <pitch>
          <step>F</step>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>D</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <voice>1</voice>
        <type>quarter</type>
        <staff>1</staff>
      </note>
      <!-- LH Staff 2 via backup -->
      <backup>
        <duration>4</duration>
      </backup>
      <!-- LH: Eb2 + Eb3 half note on beat 1-2 -->
      <note>
        <pitch>
          <step>E</step>
          <alter>-1</alter>
          <octave>2</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>E</step>
          <alter>-1</alter>
          <octave>3</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
      <!-- LH: Bb1 + Bb2 half note on beat 3-4 -->
      <note>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>1</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>B</step>
          <alter>-1</alter>
          <octave>2</octave>
        </pitch>
        <duration>2</duration>
        <voice>2</voice>
        <type>half</type>
        <staff>2</staff>
      </note>
    </measure>
  </part>
</score-partwise>
"""

}
