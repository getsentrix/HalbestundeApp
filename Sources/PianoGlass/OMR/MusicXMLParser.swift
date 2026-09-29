//
//  MusicXMLParser.swift
//  PianoGlass
//
//  XML parser for MusicXML partwise sheet music files.
//  Supports polyphonic grand staff piano, multiple voices per staff,
//  accurate <backup>/<forward> timelines, chords, accidentals, and octave shifts.
//

import Foundation

public final class MusicXMLParser: NSObject, XMLParserDelegate {
    private struct VoiceKey: Hashable {
        let staff: Int
        let voice: Int
    }
    
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
    
    // Polyphonic grand-staff timeline tracking per (staff, voice) and part cursor
    private var partTimelineTick: Int = 0
    private var voiceCursors: [VoiceKey: Int] = [:]
    private var lastVoiceNoteStartTicks: [VoiceKey: Int] = [:]
    private var lastNoteStartTicks: Int = 0
    private var stavesSeenInMeasure = Set<Int>()
    private var backupsCountInMeasure: Int = 0
    
    private var inBackup: Bool = false
    private var inForward: Bool = false
    private var backupForwardTicks: Int = 0
    
    // Direction & Clef state
    private var staffClefs: [Int: Clef] = [1: .treble, 2: .bass]
    private var staffOctaveShift: [Int: Int] = [:]
    private var currentClefNumber: Int = 1
    private var currentClefSign: String = ""
    
    // In-measure note building state
    private var inNote: Bool = false
    private var isChordNote: Bool = false
    private var isRestNote: Bool = false
    private var isTieStart: Bool = false
    private var isTieStop: Bool = false
    private var hasExplicitAlter: Bool = false
    private var hasExplicitStaff: Bool = false
    private var currentNoteType: String = ""
    private var currentStep: String = "C"
    private var currentOctave: Int = 4
    private var currentAlter: Int = 0
    private var currentAlterDouble: Double = 0.0  // Raw float alter from MusicXML
    private var currentDurationTicks: Int = 4
    private var currentStaffNumber: Int = 1
    private var currentVoice: Int = 1
    
    // Key: "Step-Staff" e.g. "F-1" to properly track accidentals per staff
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
        partTimelineTick = 0
        voiceCursors.removeAll()
        lastVoiceNoteStartTicks.removeAll()
        stavesSeenInMeasure.removeAll()
        backupsCountInMeasure = 0
        staffClefs = [1: .treble, 2: .bass]
        staffOctaveShift.removeAll()
        scoreTitle = "Untitled Score"
        composer = "Unknown Composer"
        divisions = 4
        timeSignature = TimeSignature(numerator: 4, denominator: 4)
        keySignature = KeySignature(fifths: 0, mode: "major")
        
        let success = parser.parse()
        guard success, !measures.isEmpty else {
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
        if let score = parse(xmlData: data) {
            return score
        }
        
        // Self-healing fallback: repair truncated or malformed XML via MusicXMLRepairEngine
        let repaired = MusicXMLRepairEngine.repairTruncatedXML(xmlString)
        if !repaired.isEmpty, repaired != xmlString, let repairedData = repaired.data(using: .utf8) {
            return parse(xmlData: repairedData)
        }
        return nil
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
            partTimelineTick = 0
            voiceCursors.removeAll()
            lastVoiceNoteStartTicks.removeAll()
            stavesSeenInMeasure.removeAll()
            backupsCountInMeasure = 0
            lastNoteStartTicks = 0
            if let numStr = attributeDict["number"], let num = Int(numStr) {
                currentMeasureIndex = max(0, num - 1)
            }
        } else if elementName == "clef" {
            if let numStr = attributeDict["number"], let n = Int(numStr) {
                currentClefNumber = n
            } else {
                currentClefNumber = 1
            }
            currentClefSign = ""
        } else if elementName == "octave-shift" {
            let shiftType = attributeDict["type"] ?? "stop"
            let size = Int(attributeDict["size"] ?? "8") ?? 8
            let octaves = size >= 15 ? 2 : 1
            let staffNum = Int(attributeDict["staff"] ?? "0") ?? 0
            
            let shiftVal: Int
            if shiftType == "up" {
                shiftVal = octaves
            } else if shiftType == "down" {
                shiftVal = -octaves
            } else {
                shiftVal = 0
            }
            
            if staffNum > 0 {
                staffOctaveShift[staffNum] = shiftVal
            } else {
                staffOctaveShift[1] = shiftVal
                staffOctaveShift[2] = shiftVal
            }
        } else if elementName == "note" {
            inNote = true
            isChordNote = false
            isRestNote = false
            isTieStart = false
            isTieStop = false
            hasExplicitAlter = false
            hasExplicitStaff = false
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
        case "sign":
            currentClefSign = currentText.uppercased()
            if currentClefSign == "F" {
                staffClefs[currentClefNumber] = .bass
            } else if currentClefSign == "G" {
                staffClefs[currentClefNumber] = .treble
            } else if currentClefSign == "C" {
                staffClefs[currentClefNumber] = .alto
            }
        case "type":
            currentNoteType = currentText.lowercased()
        case "step":
            currentStep = currentText.uppercased()
        case "octave":
            if let oct = Int(currentText) { currentOctave = oct }
        case "alter":
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
            if let st = Int(currentText) {
                currentStaffNumber = st
                hasExplicitStaff = true
            }
        case "voice":
            if let vc = Int(currentText) { currentVoice = vc }
            
        case "backup":
            // MusicXML specification: <backup> moves the part's time coordinate backward
            // along the measure timeline for polyphonic voices and multi-staff parts.
            partTimelineTick = max(0, partTimelineTick - backupForwardTicks)
            backupsCountInMeasure += 1
            inBackup = false
            
        case "forward":
            partTimelineTick += backupForwardTicks
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
            
            // Automatic staff & hand deduction if <staff> tag was omitted
            if !hasExplicitStaff {
                if currentVoice >= 2 && currentOctave <= 3 {
                    currentStaffNumber = 2
                } else if staffClefs[1] == .bass {
                    currentStaffNumber = 2
                } else {
                    currentStaffNumber = 1
                }
            }
            
            // Recover from malformed XML where secondary staff omitted <backup>
            if !stavesSeenInMeasure.contains(currentStaffNumber) && backupsCountInMeasure == 0 && currentStaffNumber > 1 && partTimelineTick > 0 {
                partTimelineTick = 0
            }
            stavesSeenInMeasure.insert(currentStaffNumber)
            
            let voiceKey = VoiceKey(staff: currentStaffNumber, voice: currentVoice)
            
            // Resolve chromatic alteration: explicit accidental vs per-staff measure memory vs key signature
            let accidentalKey = "\(currentStep)-\(currentStaffNumber)"
            if !hasExplicitAlter {
                if let remembered = measureAccidentalsByStaff[accidentalKey] {
                    currentAlter = remembered
                } else if let legacyRemembered = measureAccidentals[currentStep] {
                    currentAlter = legacyRemembered
                } else {
                    currentAlter = keySignatureAlter(step: currentStep, fifths: keySignature.fifths)
                }
            } else {
                measureAccidentalsByStaff[accidentalKey] = currentAlter
                measureAccidentals[currentStep] = currentAlter
            }
            
            let durationBeats = max(0.0625, Double(effectiveTicks) / Double(max(1, divisions)))
            let hand: Hand = (currentStaffNumber >= 2) ? .left : .right
            let accidental: Accidental?
            if currentAlter == 1 { accidental = .sharp }
            else if currentAlter == -1 { accidental = .flat }
            else if currentAlter == 2 { accidental = .doubleSharp }
            else if currentAlter == -2 { accidental = .doubleFlat }
            else { accidental = hasExplicitAlter ? .natural : nil }
            
            let octaveShift = staffOctaveShift[currentStaffNumber] ?? 0
            let effectiveOctave = max(0, min(8, currentOctave + octaveShift))
            let pitch = Pitch(name: currentStep, octave: effectiveOctave, accidental: accidental ?? .natural)
            
            // Calculate start tick: chords share previous note's start; non-chords advance part timeline
            let noteStartTick: Int
            if isChordNote {
                noteStartTick = lastVoiceNoteStartTicks[voiceKey] ?? lastNoteStartTicks
            } else {
                noteStartTick = partTimelineTick
                lastVoiceNoteStartTicks[voiceKey] = noteStartTick
                lastNoteStartTicks = noteStartTick
                partTimelineTick += effectiveTicks
                voiceCursors[voiceKey] = partTimelineTick
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
            let maxEnd = currentMeasureNotes.map { ($0.startBeat - currentMeasureBeatStart) + $0.durationBeats }.max() ?? timeSignature.beatsPerMeasure
            let measureDuration: Double
            if measures.isEmpty && !currentMeasureNotes.isEmpty {
                if maxEnd < timeSignature.beatsPerMeasure && maxEnd > 0 {
                    measureDuration = maxEnd
                } else {
                    measureDuration = max(timeSignature.beatsPerMeasure, maxEnd)
                }
            } else {
                measureDuration = max(timeSignature.beatsPerMeasure, maxEnd)
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
