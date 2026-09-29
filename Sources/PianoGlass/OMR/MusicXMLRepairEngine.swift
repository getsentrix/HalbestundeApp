//
//  MusicXMLRepairEngine.swift
//  PianoGlass
//
//  Resilient streaming repair engine and sanitizer for MusicXML 3.1.
//  Recovers completed measures from token-truncated multimodal AI responses,
//  sanitizes XML entities, and ensures valid MusicXML 3.1 hierarchy.
//

import Foundation

public typealias ParsedScore = Score

public struct MusicXMLRepairEngine {
    
    /// Sanitizes and repairs a potentially truncated or malformed MusicXML string.
    /// Recovers all complete measures, strips trailing partial elements, closes parent
    /// tags, and ensures standard MusicXML 3.1 structure.
    public static func repairTruncatedXML(_ rawXML: String) -> String {
        var text = rawXML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // 1. Strip markdown fences if present
        if text.contains("```xml") {
            if let start = text.range(of: "```xml") {
                text = String(text[start.upperBound...])
            }
        } else if text.contains("```") {
            if let start = text.range(of: "```") {
                text = String(text[start.upperBound...])
            }
        }
        if let end = text.range(of: "```") {
            text = String(text[..<end.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Strip conversational preambles before XML tags
        if let xmlHeader = text.range(of: "<?xml") {
            text = String(text[xmlHeader.lowerBound...])
        } else if let scoreTag = text.range(of: "<score-partwise") {
            text = String(text[scoreTag.lowerBound...])
        }
        
        // 3. Sanitize XML entities (e.g. unescaped & to &amp;)
        text = sanitizeEntities(text)
        
        // 4. Ensure root <score-partwise> is present
        if !text.contains("<score-partwise") {
            // Synthesize minimal envelope if raw measures or parts were returned
            if text.contains("<measure") {
                text = """
                <?xml version="1.0" encoding="UTF-8"?>
                <score-partwise version="3.1">
                  <part-list>
                    <score-part id="P1">
                      <part-name>Piano</part-name>
                    </score-part>
                  </part-list>
                  <part id="P1">
                \(text)
                """
            } else {
                return ""
            }
        }
        
        // 5. Ensure <part-list> and <part id="P1"> exist before measures
        if !text.contains("<part-list>") && text.contains("<measure") {
            if let firstMeasure = text.range(of: "<measure") {
                // Check if <part is already present before <measure
                var partRange: Range<String.Index>? = nil
                if let pSpace = text.range(of: "<part "), pSpace.lowerBound < firstMeasure.lowerBound {
                    partRange = pSpace
                }
                if let pTag = text.range(of: "<part>"), pTag.lowerBound < firstMeasure.lowerBound {
                    if let existing = partRange {
                        if pTag.lowerBound < existing.lowerBound {
                            partRange = pTag
                        }
                    } else {
                        partRange = pTag
                    }
                }
                
                if let partStart = partRange {
                    // <part> is already present before <measure>. Place <part-list> outside and before <part>.
                    let prefix = text[..<partStart.lowerBound]
                    let suffix = text[partStart.lowerBound...]
                    text = "\(prefix)\n  <part-list>\n    <score-part id=\"P1\"><part-name>Piano</part-name></score-part>\n  </part-list>\n\(suffix)"
                } else {
                    // No <part> exists before <measure>. Insert both <part-list> and <part id="P1">.
                    let prefix = text[..<firstMeasure.lowerBound]
                    let suffix = text[firstMeasure.lowerBound...]
                    text = "\(prefix)\n  <part-list>\n    <score-part id=\"P1\"><part-name>Piano</part-name></score-part>\n  </part-list>\n  <part id=\"P1\">\n\(suffix)"
                }
            }
        }
        
        // 6. Check if </score-partwise> is already properly closed
        if let endScoreTag = text.range(of: "</score-partwise>", options: .backwards) {
            text = String(text[..<endScoreTag.upperBound])
            return text
        }
        
        // 7. Response was truncated by token limit mid-stream:
        // Locate the last complete </measure>
        guard let lastMeasureEnd = text.range(of: "</measure>", options: .backwards) else {
            // When no complete </measure> exists, synthesize a valid minimal XML envelope
            if text.contains("<measure") {
                return """
                <?xml version="1.0" encoding="UTF-8"?>
                <score-partwise version="3.1">
                  <part-list>
                    <score-part id="P1"><part-name>Piano</part-name></score-part>
                  </part-list>
                  <part id="P1"></part>
                </score-partwise>
                """
            }
            return ""
        }
        
        // Truncate cleanly after the last complete </measure>
        var repaired = String(text[..<lastMeasureEnd.upperBound])
        
        // Count unclosed <part> tags
        let openPartCount = countOccurrences(of: "<part ", in: repaired) + countOccurrences(of: "<part>", in: repaired)
        let closePartCount = countOccurrences(of: "</part>", in: repaired)
        if openPartCount > closePartCount {
            repaired += "\n  </part>"
        }
        
        // Close root </score-partwise>
        if !repaired.contains("</score-partwise>") {
            repaired += "\n</score-partwise>"
        }
        
        return repaired
    }
    
    /// Sanitizes naked ampersands and illegal control characters in XML text.
    public static func sanitizeEntities(_ xml: String) -> String {
        // Replace unescaped & with &amp;
        // Matches '&' that is NOT followed by (amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);
        let pattern = "&(?!(amp|lt|gt|quot|apos|#\\d+|#x[0-9a-fA-F]+);)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return xml
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "&amp;")
    }
    
    /// Validates whether the given XML string has balanced tags and valid structure.
    public static func validateMusicXMLStructure(_ xml: String) -> Bool {
        guard let data = xml.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        return parser.parse()
    }
    
    private static func countOccurrences(of substring: String, in string: String) -> Int {
        var count = 0
        var searchRange = string.startIndex..<string.endIndex
        while let range = string.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<string.endIndex
        }
        return count
    }
}
