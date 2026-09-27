//
//  MusicXMLExporter.swift
//  PianoGlass
//
//  Serializes Score models into standard MusicXML 3.1 format.
//

import Foundation

public final class MusicXMLExporter {
    public init() {}
    
    public func export(score: Score) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="3.1">
          <work>
            <work-title>\(escapeXML(score.title))</work-title>
          </work>
          <identification>
            <creator type="composer">\(escapeXML(score.composer))</creator>
            <encoding>
              <software>PianoGlass iOS Liquid Glass OMR</software>
              <encoding-date>\(ISO8601DateFormatter().string(from: Date()))</encoding-date>
            </encoding>
          </identification>
          <part-list>
            <score-part id="P1">
              <part-name>Piano</part-name>
            </score-part>
          </part-list>
          <part id="P1">
        """
        
        let divisions = 4
        
        for measure in score.measures {
            xml += """
            \n    <measure number="\(measure.index + 1)">
                  <attributes>
                    <divisions>\(divisions)</divisions>
                    <key>
                      <fifths>\(measure.keySignature.fifths)</fifths>
                      <mode>\(measure.keySignature.mode)</mode>
                    </key>
                    <time>
                      <beats>\(measure.timeSignature.numerator)</beats>
                      <beat-type>\(measure.timeSignature.denominator)</beat-type>
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
            """
            
            let rhNotes = measure.notes.filter { $0.hand == .right }.sorted(by: { $0.startBeat < $1.startBeat })
            let lhNotes = measure.notes.filter { $0.hand == .left }.sorted(by: { $0.startBeat < $1.startBeat })
            
            // Export Staff 1 (Right Hand, Voice 1)
            var lastRHStartBeat: Double = -1.0
            for note in rhNotes {
                let isChord = abs(note.startBeat - lastRHStartBeat) < 0.001
                if !isChord { lastRHStartBeat = note.startBeat }
                xml += serializeNote(note, staffNum: 1, voiceNum: 1, isChord: isChord, divisions: divisions)
            }
            
            // If Left Hand exists and Right Hand had notes, insert <backup>
            if !lhNotes.isEmpty && !rhNotes.isEmpty {
                let rhEndBeat = rhNotes.map { $0.endBeat - measure.startBeat }.max() ?? measure.durationBeats
                let backupTicks = max(1, Int(rhEndBeat * Double(divisions)))
                xml += """
                \n      <backup>
                        <duration>\(backupTicks)</duration>
                      </backup>
                """
            }
            
            // Export Staff 2 (Left Hand, Voice 2)
            var lastLHStartBeat: Double = -1.0
            for note in lhNotes {
                let isChord = abs(note.startBeat - lastLHStartBeat) < 0.001
                if !isChord { lastLHStartBeat = note.startBeat }
                xml += serializeNote(note, staffNum: 2, voiceNum: 2, isChord: isChord, divisions: divisions)
            }
            
            xml += "\n    </measure>"
        }
        
        xml += """
        \n  </part>
        </score-partwise>
        """
        return xml
    }
    
    private func serializeNote(_ note: NoteEvent, staffNum: Int, voiceNum: Int, isChord: Bool, divisions: Int) -> String {
        let durTicks = max(1, Int(note.durationBeats * Double(divisions)))
        if note.isRest {
            return """
            \n      <note>
                    <rest/>
                    <duration>\(durTicks)</duration>
                    <voice>\(voiceNum)</voice>
                    <staff>\(staffNum)</staff>
                  </note>
            """
        } else {
            let pitchName = note.pitch.noteName
            let step = String(pitchName.prefix(1))
            let isSharp = pitchName.contains("#")
            let octave = note.pitch.octave
            let chordTag = isChord ? "\n        <chord/>" : ""
            
            return """
            \n      <note>\(chordTag)
                    <pitch>
                      <step>\(step)</step>
                      \(isSharp ? "<alter>1</alter>" : "")
                      <octave>\(octave)</octave>
                    </pitch>
                    <duration>\(durTicks)</duration>
                    <voice>\(voiceNum)</voice>
                    <staff>\(staffNum)</staff>
                  </note>
            """
        }
    }
    
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
