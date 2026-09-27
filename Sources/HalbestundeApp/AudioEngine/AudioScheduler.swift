//
//  AudioScheduler.swift
//  HalbestundeApp
//
//  High-precision musical score playback clock and note dispatcher.
//  Coordinates audio events, illuminated keyboard keys, and visual score playhead.
//

import Foundation
import Combine
import QuartzCore

public final class AudioScheduler: ObservableObject {
    private let audioEngine: PianoAudioEngine
    
    // Playback state
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentBeat: Double = 0.0
    @Published public private(set) var currentMeasureIndex: Int = 0
    @Published public private(set) var activePitches: [Int: Hand] = [:] // Pitch -> Hand mapping for keyboard glow
    @Published public private(set) var activeNoteEventIds: Set<UUID> = []
    
    // Configuration
    public var currentScore: Score?
    public var practiceSettings = PracticeSettings()
    
    // Precision timer
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.halbestunde.audioscheduler", qos: .userInteractive)
    private var lastTickTime: TimeInterval = 0.0
    private var internalBeat: Double = 0.0
    private var activeSoundingNoteIds = Set<UUID>()
    private var activeSoundingPitchMap = [UUID: Int]()
    private var lastMetronomeBeatFired: Int = -1
    
    public init(audioEngine: PianoAudioEngine = .shared) {
        self.audioEngine = audioEngine
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Playback Control
    
    public func loadScore(_ score: Score) {
        stop()
        self.currentScore = score
        self.practiceSettings.tempoBPM = score.defaultBPM
        seek(toBeat: 0.0)
    }
    
    public func play() {
        guard let score = currentScore, !score.measures.isEmpty else { return }
        guard !isPlaying else { return }
        
        audioEngine.start()
        isPlaying = true
        lastTickTime = CACurrentMediaTime()
        lastMetronomeBeatFired = Int(floor(internalBeat))
        
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        // 120 Hz tick resolution (~8.3ms) for ultra-fluid playhead animation and tight note quantization
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }
    
    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        timer?.cancel()
        timer = nil
        timerQueue.async { [weak self] in
            self?.silenceAllVoices()
        }
    }
    
    public func stop() {
        pause()
        seek(toBeat: 0.0)
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func seek(toBeat beat: Double) {
        let clampedBeat = max(0.0, min(totalBeats, beat))
        timerQueue.async { [weak self] in
            guard let self = self else { return }
            self.internalBeat = clampedBeat
            self.silenceAllVoices()
            
            DispatchQueue.main.async {
                self.currentBeat = clampedBeat
                self.currentMeasureIndex = self.measureIndex(forBeat: clampedBeat)
                self.updateActiveNotes(atBeat: clampedBeat)
            }
        }
    }
    
    public func seek(toMeasure measureIndex: Int) {
        guard let score = currentScore, !score.measures.isEmpty else { return }
        let validIndex = max(0, min(score.measures.count - 1, measureIndex))
        let targetMeasure = score.measures[validIndex]
        seek(toBeat: targetMeasure.startBeat)
    }
    
    // MARK: - Loop Boundaries & Measure Math
    
    public var totalBeats: Double {
        currentScore?.totalBeats ?? 0.0
    }
    
    public func measureIndex(forBeat beat: Double) -> Int {
        guard let score = currentScore else { return 0 }
        for measure in score.measures {
            if beat >= measure.startBeat && beat < (measure.startBeat + measure.durationBeats) {
                return measure.index
            }
        }
        return score.measures.last?.index ?? 0
    }
    
    // MARK: - Internal Clock Tick
    
    private func tick() {
        let now = CACurrentMediaTime()
        let deltaSeconds = now - lastTickTime
        lastTickTime = now
        
        let beatsPerSecond = practiceSettings.tempoBPM / 60.0
        let deltaBeats = deltaSeconds * beatsPerSecond
        var nextBeat = internalBeat + deltaBeats
        
        // Loop boundary evaluation
        if practiceSettings.isLoopingEnabled, let loop = practiceSettings.loopRange, let score = currentScore {
            let loopStartBeat = score.measures.indices.contains(loop.startMeasure) ? score.measures[loop.startMeasure].startBeat : 0.0
            let loopEndMeasure = score.measures.indices.contains(loop.endMeasure) ? score.measures[loop.endMeasure] : score.measures.last
            let loopEndBeat = (loopEndMeasure?.startBeat ?? 0.0) + (loopEndMeasure?.durationBeats ?? 4.0)
            
            if nextBeat >= loopEndBeat {
                nextBeat = loopStartBeat
                silenceAllVoices()
            }
        } else if nextBeat >= totalBeats && totalBeats > 0 {
            // Reached score end
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }
        
        internalBeat = nextBeat
        
        // Metronome check
        let integerBeat = Int(floor(nextBeat))
        if integerBeat > lastMetronomeBeatFired {
            lastMetronomeBeatFired = integerBeat
            if practiceSettings.isMetronomeEnabled {
                let timeSig = currentScore?.timeSignature ?? .commonTime
                let isDownbeat = (integerBeat % timeSig.numerator) == 0
                audioEngine.triggerMetronomeClick(isDownbeat: isDownbeat)
            }
        }
        
        // Dispatch note events
        processNotes(atBeat: nextBeat)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentBeat = nextBeat
            self.currentMeasureIndex = self.measureIndex(forBeat: nextBeat)
        }
    }
    
    private func processNotes(atBeat beat: Double) {
        guard let score = currentScore else { return }
        
        var newlyActivePitches = [Int: Hand]()
        var activeIds = Set<UUID>()
        let transpose = practiceSettings.transpositionSemitones
        
        for measure in score.measures {
            // Only check measures near current beat
            if beat >= measure.startBeat - 1.0 && beat <= measure.startBeat + measure.durationBeats + 1.0 {
                for note in measure.notes {
                    if !note.isRest && beat >= note.startBeat && beat < note.endBeat {
                        let finalPitch = note.pitch.transposed(by: transpose).midiNumber
                        activeIds.insert(note.id)
                        newlyActivePitches[finalPitch] = note.hand
                        
                        // Check if hand is allowed to play sound
                        if practiceSettings.shouldPlay(hand: note.hand) {
                            if !activeSoundingNoteIds.contains(note.id) {
                                // Clean re-trigger of note (even if pitch was previously sounding)
                                audioEngine.noteOff(pitch: finalPitch)
                                let handVol = practiceSettings.volume(for: note.hand)
                                audioEngine.noteOn(pitch: finalPitch, velocity: note.velocity * handVol)
                                activeSoundingNoteIds.insert(note.id)
                                activeSoundingPitchMap[note.id] = finalPitch
                            }
                        }
                    }
                }
            }
        }
        
        // NoteOff notes whose duration has elapsed
        let expiredNoteIds = activeSoundingNoteIds.subtracting(activeIds)
        for expiredId in expiredNoteIds {
            activeSoundingNoteIds.remove(expiredId)
            if let pitch = activeSoundingPitchMap.removeValue(forKey: expiredId) {
                // Only send noteOff if no other active note is currently sounding this pitch
                if !activeSoundingPitchMap.values.contains(pitch) {
                    audioEngine.noteOff(pitch: pitch)
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.activePitches = newlyActivePitches
            self?.activeNoteEventIds = activeIds
        }
    }
    
    private func updateActiveNotes(atBeat beat: Double) {
        guard let score = currentScore else {
            activePitches = [:]
            activeNoteEventIds = []
            return
        }
        var active = [Int: Hand]()
        var ids = Set<UUID>()
        for measure in score.measures {
            for note in measure.notes where !note.isRest {
                if beat >= note.startBeat && beat < note.endBeat {
                    let finalPitch = note.pitch.transposed(by: practiceSettings.transpositionSemitones).midiNumber
                    active[finalPitch] = note.hand
                    ids.insert(note.id)
                }
            }
        }
        self.activePitches = active
        self.activeNoteEventIds = ids
    }
    
    private func silenceAllVoices() {
        for pitch in activeSoundingPitchMap.values {
            audioEngine.noteOff(pitch: pitch)
        }
        activeSoundingNoteIds.removeAll()
        activeSoundingPitchMap.removeAll()
        audioEngine.allNotesOff()
        
        DispatchQueue.main.async { [weak self] in
            self?.activePitches = [:]
            self?.activeNoteEventIds = []
        }
    }
}
