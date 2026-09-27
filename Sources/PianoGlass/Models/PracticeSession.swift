//
//  PracticeSession.swift
//  PianoGlass
//
//  Practice controls and session state model.
//

import Foundation

public struct LoopRange: Codable, Equatable {
    public var startMeasure: Int
    public var endMeasure: Int
    
    public init(startMeasure: Int, endMeasure: Int) {
        self.startMeasure = min(startMeasure, endMeasure)
        self.endMeasure = max(startMeasure, endMeasure)
    }
    
    public func contains(measureIndex: Int) -> Bool {
        return measureIndex >= startMeasure && measureIndex <= endMeasure
    }
}

public struct PracticeSettings: Codable, Equatable {
    /// Tempo in Beats Per Minute (40 - 240)
    public var tempoBPM: Double
    
    /// Transposition in semitones (-12 to +12)
    public var transpositionSemitones: Int
    
    /// Optional A-B looping range
    public var loopRange: LoopRange?
    public var isLoopingEnabled: Bool
    
    /// Hand isolation
    public var isLeftHandMuted: Bool
    public var isRightHandMuted: Bool
    public var isLeftHandSolo: Bool
    public var isRightHandSolo: Bool
    public var leftHandVolume: Float
    public var rightHandVolume: Float
    
    /// Metronome
    public var isMetronomeEnabled: Bool
    public var metronomeVolume: Float
    
    /// Count-in beats before playback starts
    public var countInBeats: Int
    
    /// Keyboard display mode: 61 keys vs 88 keys
    public var keyboardKeyCount: Int
    
    public init(
        tempoBPM: Double = 120.0,
        transpositionSemitones: Int = 0,
        loopRange: LoopRange? = nil,
        isLoopingEnabled: Bool = false,
        isLeftHandMuted: Bool = false,
        isRightHandMuted: Bool = false,
        isLeftHandSolo: Bool = false,
        isRightHandSolo: Bool = false,
        leftHandVolume: Float = 1.0,
        rightHandVolume: Float = 1.0,
        isMetronomeEnabled: Bool = false,
        metronomeVolume: Float = 0.7,
        countInBeats: Int = 0,
        keyboardKeyCount: Int = 61
    ) {
        self.tempoBPM = max(40.0, min(240.0, tempoBPM))
        self.transpositionSemitones = max(-12, min(12, transpositionSemitones))
        self.loopRange = loopRange
        self.isLoopingEnabled = isLoopingEnabled
        self.isLeftHandMuted = isLeftHandMuted
        self.isRightHandMuted = isRightHandMuted
        self.isLeftHandSolo = isLeftHandSolo
        self.isRightHandSolo = isRightHandSolo
        self.leftHandVolume = leftHandVolume
        self.rightHandVolume = rightHandVolume
        self.isMetronomeEnabled = isMetronomeEnabled
        self.metronomeVolume = metronomeVolume
        self.countInBeats = countInBeats
        self.keyboardKeyCount = keyboardKeyCount
    }
    
    /// Evaluates if a given hand should produce sound based on solo and mute settings
    public func shouldPlay(hand: Hand) -> Bool {
        if isLeftHandSolo && hand != .left { return false }
        if isRightHandSolo && hand != .right { return false }
        if hand == .left && isLeftHandMuted { return false }
        if hand == .right && isRightHandMuted { return false }
        return true
    }
    
    /// Returns the effective volume factor for a given hand
    public func volume(for hand: Hand) -> Float {
        guard shouldPlay(hand: hand) else { return 0.0 }
        switch hand {
        case .left: return leftHandVolume
        case .right: return rightHandVolume
        }
    }
}
