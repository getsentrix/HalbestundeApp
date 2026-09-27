//
//  ScanResult.swift
//  HalbestundeApp
//
//  Data model representing the results of an Optical Music Recognition scan.
//

import Foundation
import CoreGraphics

public struct RecognizedStaffLine: Identifiable, Codable {
    public let id: UUID
    public let yPosition: CGFloat
    public let staffIndex: Int // 0 to 4 within a 5-line staff
    public let systemIndex: Int // Grand staff system index (0, 1, 2...)
    
    public init(id: UUID = UUID(), yPosition: CGFloat, staffIndex: Int, systemIndex: Int) {
        self.id = id
        self.yPosition = yPosition
        self.staffIndex = staffIndex
        self.systemIndex = systemIndex
    }
}

public struct RecognizedStaffSystem: Identifiable, Codable {
    public let id: UUID
    public let systemIndex: Int
    public let trebleStaffLines: [CGFloat]
    public let bassStaffLines: [CGFloat]
    public let staffLineSpacing: CGFloat
    public let barlineXPositions: [CGFloat]
    public let bounds: CGRect
    
    public init(
        id: UUID = UUID(),
        systemIndex: Int,
        trebleStaffLines: [CGFloat] = [],
        bassStaffLines: [CGFloat] = [],
        staffLineSpacing: CGFloat = 10.0,
        barlineXPositions: [CGFloat] = [],
        bounds: CGRect = .zero
    ) {
        self.id = id
        self.systemIndex = systemIndex
        self.trebleStaffLines = trebleStaffLines
        self.bassStaffLines = bassStaffLines
        self.staffLineSpacing = staffLineSpacing
        self.barlineXPositions = barlineXPositions
        self.bounds = bounds
    }
    
    public var trebleStaffBoundingBox: CGRect {
        guard let first = trebleStaffLines.first, let last = trebleStaffLines.last else { return bounds }
        let minY = min(first, last)
        let maxY = max(first, last)
        return CGRect(x: bounds.minX, y: minY, width: bounds.width, height: max(1.0, maxY - minY))
    }
    
    public var bassStaffBoundingBox: CGRect {
        guard let first = bassStaffLines.first, let last = bassStaffLines.last else { return bounds }
        let minY = min(first, last)
        let maxY = max(first, last)
        return CGRect(x: bounds.minX, y: minY, width: bounds.width, height: max(1.0, maxY - minY))
    }
}

public struct ScanConfidenceScore: Codable {
    public let staffDetectionConfidence: Float
    public let noteheadConfidence: Float
    public let rhythmConsistencyConfidence: Float
    
    public var overallConfidence: Float {
        (staffDetectionConfidence * 0.4) + (noteheadConfidence * 0.4) + (rhythmConsistencyConfidence * 0.2)
    }
    
    public init(staffDetectionConfidence: Float = 0.95, noteheadConfidence: Float = 0.92, rhythmConsistencyConfidence: Float = 0.90) {
        self.staffDetectionConfidence = staffDetectionConfidence
        self.noteheadConfidence = noteheadConfidence
        self.rhythmConsistencyConfidence = rhythmConsistencyConfidence
    }
}

public struct ScanResult: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let recognizedScore: Score
    public let confidence: ScanConfidenceScore
    public let staffSystems: [RecognizedStaffSystem]
    public let rawNoteCount: Int
    public let processingDurationSeconds: Double
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        recognizedScore: Score,
        confidence: ScanConfidenceScore = ScanConfidenceScore(),
        staffSystems: [RecognizedStaffSystem] = [],
        rawNoteCount: Int = 0,
        processingDurationSeconds: Double = 0.0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.recognizedScore = recognizedScore
        self.confidence = confidence
        self.staffSystems = staffSystems
        self.rawNoteCount = rawNoteCount
        self.processingDurationSeconds = processingDurationSeconds
    }
}
