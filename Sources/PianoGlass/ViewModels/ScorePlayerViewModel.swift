//
//  ScorePlayerViewModel.swift
//  PianoGlass
//
//  ViewModel orchestrating audio playback, practice settings, score visualization,
//  and illuminated virtual keyboard interaction.
//

import Foundation
import SwiftUI
import Combine

public final class ScorePlayerViewModel: ObservableObject {
    public var audioEngine: PianoAudioEngine
    public var audioScheduler: AudioScheduler
    
    @Published public var currentScore: Score
    @Published public var isPlaying: Bool = false
    @Published public var currentBeat: Double = 0.0
    @Published public var currentMeasureIndex: Int = 0
    @Published public var activePitches: [Int: Hand] = [:]
    @Published public var activeNoteEventIds: Set<UUID> = []
    
    // Practice Settings
    @Published public var tempoBPM: Double = 120.0 {
        didSet {
            audioScheduler.practiceSettings.tempoBPM = tempoBPM
        }
    }
    
    @Published public var transpositionSemitones: Int = 0 {
        didSet {
            audioScheduler.practiceSettings.transpositionSemitones = transpositionSemitones
        }
    }
    
    @Published public var isLoopingEnabled: Bool = false {
        didSet {
            audioScheduler.practiceSettings.isLoopingEnabled = isLoopingEnabled
        }
    }
    
    @Published public var loopStartMeasure: Int = 0 {
        didSet { updateLoopRange() }
    }
    
    @Published public var loopEndMeasure: Int = 3 {
        didSet { updateLoopRange() }
    }
    
    // Hand Isolation
    @Published public var isLeftHandMuted: Bool = false {
        didSet { audioScheduler.practiceSettings.isLeftHandMuted = isLeftHandMuted }
    }
    
    @Published public var isRightHandMuted: Bool = false {
        didSet { audioScheduler.practiceSettings.isRightHandMuted = isRightHandMuted }
    }
    
    @Published public var isLeftHandSolo: Bool = false {
        didSet { audioScheduler.practiceSettings.isLeftHandSolo = isLeftHandSolo }
    }
    
    @Published public var isRightHandSolo: Bool = false {
        didSet { audioScheduler.practiceSettings.isRightHandSolo = isRightHandSolo }
    }
    
    @Published public var isMetronomeEnabled: Bool = false {
        didSet { audioScheduler.practiceSettings.isMetronomeEnabled = isMetronomeEnabled }
    }
    
    @Published public var showPracticeSettings: Bool = false
    @Published public var showFallingNotes: Bool = false
    @Published public var keyboardKeyCount: Int = 61 // 61 or 88 keys
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        score: Score = .empty,
        audioEngine: PianoAudioEngine = .shared
    ) {
        self.currentScore = score
        self.audioEngine = audioEngine
        self.audioScheduler = AudioScheduler(audioEngine: audioEngine)
        self.tempoBPM = score.defaultBPM
        
        bindScheduler()
        audioScheduler.loadScore(score)
        
        if score.measures.count > 0 {
            self.loopEndMeasure = min(3, score.measures.count - 1)
            updateLoopRange()
        }
    }
    
    private func bindScheduler() {
        audioScheduler.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
        
        audioScheduler.$currentBeat
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentBeat, on: self)
            .store(in: &cancellables)
        
        audioScheduler.$currentMeasureIndex
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentMeasureIndex, on: self)
            .store(in: &cancellables)
        
        audioScheduler.$activePitches
            .receive(on: DispatchQueue.main)
            .assign(to: \.activePitches, on: self)
            .store(in: &cancellables)
        
        audioScheduler.$activeNoteEventIds
            .receive(on: DispatchQueue.main)
            .assign(to: \.activeNoteEventIds, on: self)
            .store(in: &cancellables)
    }
    
    public func loadScore(_ score: Score) {
        self.currentScore = score
        self.tempoBPM = score.defaultBPM
        self.loopStartMeasure = 0
        self.loopEndMeasure = min(3, max(0, score.measures.count - 1))
        updateLoopRange()
        audioScheduler.loadScore(score)
    }
    
    public func togglePlayPause() {
        audioScheduler.togglePlayPause()
    }
    
    public func play() {
        audioScheduler.play()
    }
    
    public func pause() {
        audioScheduler.pause()
    }
    
    public func stop() {
        audioScheduler.stop()
    }
    
    public func seek(toBeat beat: Double) {
        audioScheduler.seek(toBeat: beat)
        if !isPlaying {
            previewNotes(atBeat: beat)
        }
    }
    
    public func seek(toMeasure measureIndex: Int) {
        audioScheduler.seek(toMeasure: measureIndex)
        if !isPlaying, let score = currentScore as Score?, score.measures.indices.contains(measureIndex) {
            previewNotes(atBeat: score.measures[measureIndex].startBeat)
        }
    }
    
    /// Provides immediate acoustic feedback by sounding the notes at the scrubbed beat
    public func previewNotes(atBeat beat: Double) {
        for measure in currentScore.measures {
            if beat >= measure.startBeat - 0.25 && beat <= (measure.startBeat + measure.durationBeats + 0.25) {
                for note in measure.notes where !note.isRest {
                    if beat >= note.startBeat && beat < note.endBeat {
                        let finalPitch = note.pitch.transposed(by: transpositionSemitones).midiNumber
                        audioEngine.noteOn(pitch: finalPitch, velocity: 0.65)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                            self?.audioEngine.noteOff(pitch: finalPitch)
                        }
                    }
                }
            }
        }
    }
    
    public func setLoopMeasureA(_ measure: Int) {
        self.loopStartMeasure = measure
        if self.loopEndMeasure < measure {
            self.loopEndMeasure = measure
        }
        self.isLoopingEnabled = true
        updateLoopRange()
    }
    
    public func setLoopMeasureB(_ measure: Int) {
        self.loopEndMeasure = measure
        if self.loopStartMeasure > measure {
            self.loopStartMeasure = measure
        }
        self.isLoopingEnabled = true
        updateLoopRange()
    }
    
    public func clearLoop() {
        self.isLoopingEnabled = false
        audioScheduler.practiceSettings.loopRange = nil
    }
    
    private func updateLoopRange() {
        let range = LoopRange(startMeasure: loopStartMeasure, endMeasure: loopEndMeasure)
        audioScheduler.practiceSettings.loopRange = range
    }
    
    // MARK: - Interactive Virtual Keyboard Touch Response
    
    public func userTappedKey(pitch: Int, velocity: Float = 0.85) {
        audioEngine.noteOn(pitch: pitch, velocity: velocity)
    }
    
    public func userReleasedKey(pitch: Int) {
        audioEngine.noteOff(pitch: pitch)
    }
    
    // MARK: - Progress Calculations
    
    public var playbackProgress: Double {
        let total = currentScore.totalBeats
        guard total > 0 else { return 0.0 }
        return min(1.0, max(0.0, currentBeat / total))
    }
    
    public func formatTime(forBeat beat: Double) -> String {
        let seconds = (beat / tempoBPM) * 60.0
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    public func formatRemainingTime(forBeat beat: Double) -> String {
        let total = currentScore.durationSeconds(at: tempoBPM)
        let current = (beat / tempoBPM) * 60.0
        let remaining = max(0.0, total - current)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "-%d:%02d", mins, secs)
    }
    
    public var formattedCurrentTime: String {
        formatTime(forBeat: currentBeat)
    }
    
    public var formattedTotalTime: String {
        let seconds = currentScore.durationSeconds(at: tempoBPM)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    public var formattedRemainingTime: String {
        formatRemainingTime(forBeat: currentBeat)
    }
}
