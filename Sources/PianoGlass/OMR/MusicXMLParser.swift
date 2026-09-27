//
//  MusicXMLParser.swift
//  PianoGlass
//
//  XML parser for MusicXML partwise sheet music files.
//  Supports multi-staff (grand staff piano), chords, backup/forward, and key/time signatures.
//

import Foundation

public final class MusicXMLParser: NSObject, XMLParserDelegate {
    private var scoreTitle: String = "Untitled Score"
    private var composer: String = "Unknown Composer"
    private var divisions: Int = 4
    private var timeSignature = TimeSignature(numerator: 4, denominator: 4)
    private var keySignature = KeySignature(fifths: 0, mode: "major")
    private var measures = [Measure]()
    
    // Parse tracking state
    private var currentElement: String = ""
    private var currentText: String = ""
    private var currentMeasureIndex: Int = 0
    private var currentMeasureBeatStart: Double = 0.0
    private var currentMeasureNotes = [NoteEvent]()
    private var measureAccidentals: [String: Int] = [:]
    
    // Timeline tracking inside measure
    private var globalMeasureTicks: Int = 0
    private var staffTickCursors: [Int: Int] = [:]
    private var inBackup: Bool = false
    private var inForward: Bool = false
    private var backupForwardTicks: Int = 0
    
    // In-measure note building state
    private var inNote: Bool = false
    private var isChordNote: Bool = false
    private var isRestNote: Bool = false
    private var isTieStart: Bool = false
    private var isTieStop: Bool = false
    private var hasExplicitAlter: Bool = false
    private var currentNoteType: String = ""
    private var currentStep: String = "C"
    private var currentOctave: Int = 4
    private var currentAlter: Int = 0
    private var currentAlterDouble: Double = 0.0  // Raw float alter from MusicXML
    private var currentDurationTicks: Int = 4
    private var currentStaffNumber: Int = 1
    private var currentVoice: Int = 1
    private var lastNoteStartTicks: Int = 0
    private var lastStaffNoteStartTicks: [Int: Int] = [:]
    
    // Key: "Step-Staff" e.g. "F#-1" to properly track accidentals per staff
    private var measureAccidentalsByStaff: [String: Int] = [:]
    
    public override init() {
        super.init()
    }
    
    /// Parses MusicXML data string into a playable Score
    public func parse(xmlData: Data) -> Score? {
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        // Security hardening: Disable external entity and DTD resolution to prevent XXE
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        
        measures.removeAll()
        measureAccidentals.removeAll()
        measureAccidentalsByStaff.removeAll()
        currentMeasureIndex = 0
        currentMeasureBeatStart = 0.0
        globalMeasureTicks = 0
        staffTickCursors = [:]
        scoreTitle = "Untitled Score"
        composer = "Unknown Composer"
        divisions = 4
        timeSignature = TimeSignature(numerator: 4, denominator: 4)
        keySignature = KeySignature(fifths: 0, mode: "major")
        
        let success = parser.parse()
        guard success else {
            return nil
        }
        
        return Score(
            title: scoreTitle,
            composer: composer,
            defaultBPM: 110.0,
            timeSignature: timeSignature,
            keySignature: keySignature,
            measures: measures
        )
    }
    
    public func parse(xmlString: String) -> Score? {
        guard let data = xmlString.data(using: .utf8) else { return nil }
        return parse(xmlData: data)
    }
    
    // MARK: - XMLParserDelegate
    
    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
        
        if elementName == "measure" {
            currentMeasureNotes = []
            measureAccidentals.removeAll()
            measureAccidentalsByStaff.removeAll()
            globalMeasureTicks = 0
            staffTickCursors = [1: 0, 2: 0]
            lastStaffNoteStartTicks = [1: 0, 2: 0]
            lastNoteStartTicks = 0
            if let numStr = attributeDict["number"], let num = Int(numStr) {
                currentMeasureIndex = max(0, num - 1)
            }
        } else if elementName == "note" {
            inNote = true
            isChordNote = false
            isRestNote = false
            isTieStart = false
            isTieStop = false
            hasExplicitAlter = false
            currentNoteType = ""
            currentStep = "C"
            currentOctave = 4
            currentAlter = 0
            currentAlterDouble = 0.0
            currentDurationTicks = max(1, divisions)
            currentStaffNumber = 1
            currentVoice = 1
        } else if elementName == "chord" {
            isChordNote = true
        } else if elementName == "rest" {
            isRestNote = true
        } else if elementName == "tie" || elementName == "tied" {
            if let type = attributeDict["type"] {
                if type == "start" { isTieStart = true }
                else if type == "stop" { isTieStop = true }
            }
        } else if elementName == "backup" {
            inBackup = true
            backupForwardTicks = 0
        } else if elementName == "forward" {
            inForward = true
            backupForwardTicks = 0
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "work-title", "movement-title":
            if !currentText.isEmpty { scoreTitle = currentText }
        case "creator":
            if !currentText.isEmpty { composer = currentText }
        case "divisions":
            if let div = Int(currentText), div > 0 { divisions = div }
        case "beats":
            if let b = Int(currentText) {
                timeSignature = TimeSignature(numerator: b, denominator: timeSignature.denominator)
            }
        case "beat-type":
            if let bt = Int(currentText) {
                timeSignature = TimeSignature(numerator: timeSignature.numerator, denominator: bt)
            }
        case "fifths":
            if let f = Int(currentText) {
                keySignature = KeySignature(fifths: f, mode: keySignature.mode)
            }
        case "mode":
            if !currentText.isEmpty {
                keySignature = KeySignature(fifths: keySignature.fifths, mode: currentText)
            }
        case "type":
            currentNoteType = currentText.lowercased()
        case "step":
            currentStep = currentText.uppercased()
        case "octave":
            if let oct = Int(currentText) { currentOctave = oct }
        case "alter":
            // MusicXML alter can be float (e.g. 0.5 for quarter-tones) or int (-1, 0, 1, 2)
            // We round to nearest semitone for playback
            if let altDouble = Double(currentText) {
                currentAlterDouble = altDouble
                currentAlter = Int(altDouble.rounded())
                hasExplicitAlter = true
            }
        case "accidental":
            let acc = currentText.lowercased()
            hasExplicitAlter = true
            if acc == "natural" { currentAlter = 0 }
            else if acc == "sharp" { currentAlter = 1 }
            else if acc == "flat" { currentAlter = -1 }
            else if acc == "double-sharp" { currentAlter = 2 }
            else if acc == "flat-flat" { currentAlter = -2 }
        case "duration":
            if let dur = Int(currentText) {
                if inBackup || inForward {
                    backupForwardTicks = dur
                } else {
                    currentDurationTicks = dur
                }
            }
        case "staff":
            if let st = Int(currentText) { currentStaffNumber = st }
        case "voice":
            if let vc = Int(currentText) { currentVoice = vc }
            
        case "backup":
            globalMeasureTicks = max(0, globalMeasureTicks - backupForwardTicks)
            for (st, cur) in staffTickCursors {
                staffTickCursors[st] = max(0, cur - backupForwardTicks)
            }
            for (st, cur) in lastStaffNoteStartTicks {
                lastStaffNoteStartTicks[st] = max(0, cur - backupForwardTicks)
            }
            lastNoteStartTicks = max(0, lastNoteStartTicks - backupForwardTicks)
            inBackup = false
            
        case "forward":
            globalMeasureTicks += backupForwardTicks
            for (st, cur) in staffTickCursors {
                staffTickCursors[st] = cur + backupForwardTicks
            }
            for (st, cur) in lastStaffNoteStartTicks {
                lastStaffNoteStartTicks[st] = cur + backupForwardTicks
            }
            lastNoteStartTicks += backupForwardTicks
            inForward = false
            
        case "note":
            var effectiveTicks = currentDurationTicks
            if effectiveTicks <= 0 && !currentNoteType.isEmpty {
                let div = max(1, divisions)
                switch currentNoteType {
                case "whole": effectiveTicks = div * 4
                case "dotted-half", "dotted half": effectiveTicks = div * 3
                case "half": effectiveTicks = div * 2
                case "dotted-quarter", "dotted quarter": effectiveTicks = Int(Double(div) * 1.5)
                case "quarter": effectiveTicks = div
                case "dotted-eighth", "dotted eighth": effectiveTicks = max(1, Int(Double(div) * 0.75))
                case "eighth": effectiveTicks = max(1, div / 2)
                case "16th", "sixteenth": effectiveTicks = max(1, div / 4)
                case "32nd": effectiveTicks = max(1, div / 8)
                default: effectiveTicks = div
                }
            }
            if effectiveTicks <= 0 {
                effectiveTicks = max(1, divisions)
            }
            
            // Resolve chromatic alteration: explicit accidental vs per-staff measure memory vs key signature
            // Key includes both step and staff number to avoid cross-staff contamination (e.g. treble F# vs bass F)
            let accidentalKey = "\(currentStep)-\(currentStaffNumber)"
            if !hasExplicitAlter {
                if let remembered = measureAccidentalsByStaff[accidentalKey] {
                    currentAlter = remembered
                } else if let legacyRemembered = measureAccidentals[currentStep] {
                    // Fall back to old per-step memory for backwards compatibility
                    currentAlter = legacyRemembered
                } else {
                    currentAlter = keySignatureAlter(step: currentStep, fifths: keySignature.fifths)
                }
            } else {
                // Natural sign explicitly cancels key signature accidentals within this measure
                measureAccidentalsByStaff[accidentalKey] = currentAlter
                measureAccidentals[currentStep] = currentAlter
            }
            
            let durationBeats = max(0.125, Double(effectiveTicks) / Double(max(1, divisions)))
            let hand: Hand = (currentStaffNumber >= 2) ? .left : .right
            let accidental: Accidental?
            if currentAlter == 1 { accidental = .sharp }
            else if currentAlter == -1 { accidental = .flat }
            else if currentAlter == 2 { accidental = .doubleSharp }
            else if currentAlter == -2 { accidental = .doubleFlat }
            else { accidental = nil }
            
            let pitch = Pitch(name: currentStep, octave: currentOctave, accidental: accidental ?? .natural)
            
            // Calculate start tick: if chord, same as previous note on this staff; else staff cursor
            let noteStartTick: Int
            if isChordNote {
                noteStartTick = lastStaffNoteStartTicks[currentStaffNumber] ?? lastNoteStartTicks
            } else {
                let staffCursor = staffTickCursors[currentStaffNumber] ?? 0
                noteStartTick = staffCursor
                lastStaffNoteStartTicks[currentStaffNumber] = noteStartTick
                lastNoteStartTicks = noteStartTick
                staffTickCursors[currentStaffNumber] = staffCursor + effectiveTicks
                globalMeasureTicks = max(globalMeasureTicks, staffCursor + effectiveTicks)
            }
            
            let noteStartBeatWithinMeasure = Double(noteStartTick) / Double(max(1, divisions))
            
            let note = NoteEvent(
                pitch: pitch,
                startBeat: currentMeasureBeatStart + noteStartBeatWithinMeasure,
                durationBeats: durationBeats,
                velocity: hand == .right ? 0.82 : 0.70,
                hand: hand,
                measureIndex: currentMeasureIndex,
                isRest: isRestNote,
                accidental: accidental,
                isTiedContinuation: isTieStop
            )
            currentMeasureNotes.append(note)
            inNote = false
            
        case "measure":
            let measureDuration: Double
            if measures.isEmpty && !currentMeasureNotes.isEmpty {
                let maxEnd = currentMeasureNotes.map { ($0.startBeat - currentMeasureBeatStart) + $0.durationBeats }.max() ?? timeSignature.beatsPerMeasure
                if maxEnd < timeSignature.beatsPerMeasure && maxEnd > 0 {
                    measureDuration = maxEnd
                } else {
                    measureDuration = timeSignature.beatsPerMeasure
                }
            } else {
                let maxEnd = currentMeasureNotes.map { ($0.startBeat - currentMeasureBeatStart) + $0.durationBeats }.max() ?? timeSignature.beatsPerMeasure
                if maxEnd > timeSignature.beatsPerMeasure {
                    measureDuration = maxEnd
                } else {
                    measureDuration = timeSignature.beatsPerMeasure
                }
            }
            
            let measure = Measure(
                index: currentMeasureIndex,
                startBeat: currentMeasureBeatStart,
                durationBeats: measureDuration,
                timeSignature: timeSignature,
                keySignature: keySignature,
                notes: currentMeasureNotes.sorted(by: { $0.startBeat < $1.startBeat })
            )
            measures.append(measure)
            currentMeasureBeatStart += measureDuration
            currentMeasureIndex += 1
            
        default:
            break
        }
    }
    
    private func keySignatureAlter(step: String, fifths: Int) -> Int {
        let sharpOrder = ["F", "C", "G", "D", "A", "E", "B"]
        let flatOrder = ["B", "E", "A", "D", "G", "C", "F"]
        if fifths > 0 {
            let count = min(7, fifths)
            if sharpOrder.prefix(count).contains(step) {
                return 1
            }
        } else if fifths < 0 {
            let count = min(7, -fifths)
            if flatOrder.prefix(count).contains(step) {
                return -1
            }
        }
        return 0
    }
}
