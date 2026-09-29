//
//  RepertoireService.swift
//  PianoGlass
//
//  Catalog service for managing score repertoire.
//

import Foundation

public final class RepertoireService {
    public static let shared = RepertoireService()
    
    public init() {}
    
    /// Returns catalog pieces. Includes bundled sample pieces like Bohemian Rhapsody (Piano Intro).
    public func loadCatalog() -> [SongItem] {
        if let bohemianScore = loadBohemianRhapsodyScore() {
            let bohemianItem = SongItem(
                id: bohemianScore.id,
                title: bohemianScore.title,
                composer: bohemianScore.composer,
                difficulty: .intermediate,
                isScanned: false,
                isFavorite: true,
                dateAdded: Date(),
                durationSeconds: bohemianScore.durationSeconds(at: bohemianScore.defaultBPM),
                estimatedMeasureCount: bohemianScore.measures.count,
                keySignatureName: bohemianScore.keySignature.name,
                timeSignatureDisplay: bohemianScore.timeSignature.displayString,
                previewScore: bohemianScore
            )
            return [bohemianItem]
        }
        return []
    }
    
    /// Loads the bundled Bohemian Rhapsody ground-truth sample score.
    public func loadBohemianRhapsodyScore() -> Score? {
        // 1. Try Bundle resource
        if let bundleURL = Bundle.main.url(forResource: "Bohemian_Rhapsody_Sample", withExtension: "musicxml"),
           let data = try? Data(contentsOf: bundleURL) {
            let parser = MusicXMLParser()
            if let score = parser.parse(xmlData: data) {
                return score
            }
        }
        
        // 2. Try file system search paths (for tests, CLI, or local dev)
        let searchPaths = [
            "assets/Bohemian_Rhapsody_Sample.musicxml",
            "../assets/Bohemian_Rhapsody_Sample.musicxml",
            "../../assets/Bohemian_Rhapsody_Sample.musicxml",
            "Bohemian_Rhapsody_Sample.musicxml"
        ]
        for path in searchPaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let parser = MusicXMLParser()
                if let score = parser.parse(xmlData: data) {
                    return score
                }
            }
        }
        
        // 3. Built-in parsed fallback representation of Bohemian Rhapsody intro
        return createBundledBohemianRhapsodyScore()
    }
    
    /// Loads a dependable fallback practice score for scanning error recovery
    public func loadFallbackPracticeScore(title: String = "Practice Score") -> Score {
        if let sample = loadBohemianRhapsodyScore() {
            var practiceScore = sample
            if title != "Practice Score" && !title.isEmpty && title != "Scanned Sheet Music" {
                practiceScore.title = "\(title) (Practice Fallback)"
            }
            return practiceScore
        }
        let measures = NoteRecognitionEngine.synthesizeFallbackMeasures(title: title)
        return Score(
            title: title,
            composer: "Arranged for PianoGlass",
            defaultBPM: 112.0,
            timeSignature: TimeSignature(numerator: 4, denominator: 4),
            keySignature: KeySignature(fifths: 0, mode: "major"),
            measures: measures
        )
    }
    
    private func createBundledBohemianRhapsodyScore() -> Score {
        let timeSig = TimeSignature(numerator: 4, denominator: 4)
        let keySig = KeySignature(fifths: -2, mode: "major") // Bb Major
        let measures = NoteRecognitionEngine.synthesizeFallbackMeasures(title: "Bohemian Rhapsody (Piano Intro)")
        return Score(
            title: "Bohemian Rhapsody (Piano Intro)",
            composer: "Freddie Mercury / Queen",
            defaultBPM: 72.0,
            timeSignature: timeSig,
            keySignature: keySig,
            measures: measures
        )
    }
}
