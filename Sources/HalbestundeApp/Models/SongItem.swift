//
//  SongItem.swift
//  HalbestundeApp
//
//  Repertoire item and scan metadata model.
//

import Foundation

public enum DifficultyLevel: String, Codable, CaseIterable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case virtuoso = "Virtuoso"
    
    public var id: String { rawValue }
    
    public var stars: Int {
        switch self {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        case .virtuoso: return 4
        }
    }
    
    public var colorHex: String {
        switch self {
        case .beginner: return "#00E5FF" // Cyan
        case .intermediate: return "#00E676" // Emerald
        case .advanced: return "#FFB300" // Amber
        case .virtuoso: return "#FF1744" // Scarlet
        }
    }
}

public struct SongItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var composer: String
    public var difficulty: DifficultyLevel
    public var isScanned: Bool
    public var isFavorite: Bool
    public var dateAdded: Date
    public var durationSeconds: Double
    public var estimatedMeasureCount: Int
    public var keySignatureName: String
    public var timeSignatureDisplay: String
    public var previewScore: Score?
    
    public init(
        id: UUID = UUID(),
        title: String,
        composer: String,
        difficulty: DifficultyLevel = .intermediate,
        isScanned: Bool = false,
        isFavorite: Bool = false,
        dateAdded: Date = Date(),
        durationSeconds: Double = 90.0,
        estimatedMeasureCount: Int = 32,
        keySignatureName: String = "C Major",
        timeSignatureDisplay: String = "4/4",
        previewScore: Score? = nil
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.difficulty = difficulty
        self.isScanned = isScanned
        self.isFavorite = isFavorite
        self.dateAdded = dateAdded
        self.durationSeconds = durationSeconds
        self.estimatedMeasureCount = estimatedMeasureCount
        self.keySignatureName = keySignatureName
        self.timeSignatureDisplay = timeSignatureDisplay
        self.previewScore = previewScore
    }
}
