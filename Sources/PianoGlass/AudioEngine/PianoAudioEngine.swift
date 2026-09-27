//
//  PianoAudioEngine.swift
//  PianoGlass
//
//  High-performance polyphonic piano audio engine using AVAudioEngine
//  with physical acoustic piano modeling and AVAudioUnitSampler fallback.
//

import Foundation
import AVFoundation
import os

public final class PianoAudioEngine: ObservableObject {
    public static let shared = PianoAudioEngine()
    
    private let engine = AVAudioEngine()
    private var samplerNode = AVAudioUnitSampler()
    private var isEngineRunning = false
    
    // Internal procedural synth voice bank for reliable sound without external asset dependencies
    private var synthNode: AVAudioSourceNode?
    
    // Active voices state
    private struct ActiveVoice {
        let pitch: Int
        let frequency: Double
        let velocity: Float
        var phase: Double = 0.0
        var detunePhase: Double = 0.0
        var harmonicPhase: Double = 0.0
        var ageSeconds: Double = 0.0
        var isReleased: Bool = false
        var releaseTime: Double = 0.0
    }
    
    private let voiceLock = os_unfair_lock_t.allocate(capacity: 1)
    private var activeVoices = [Int: ActiveVoice]()
    private let sampleRate: Double = 44100.0
    
    // Metronome click state
    private var metronomeClickCountdown: Int = 0
    private var metronomeIsDownbeat: Bool = false
    private var metronomePhase: Double = 0.0
    
    @Published public var masterVolume: Float = 0.85
    @Published public var isMuted: Bool = false
    
    public init() {
        voiceLock.initialize(to: os_unfair_lock())
        setupAudioSession()
        setupAudioEngine()
    }
    
    deinit {
        stop()
        voiceLock.deallocate()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PianoAudioEngine] Failed to setup audio session: \(error)")
        }
        #endif
    }
    
    private func setupAudioEngine() {
        // Build Procedural Acoustic Grand Piano Synthesizer Source Node
        let synth = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let leftChannel = ablPointer[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let rightChannel = ablPointer.count > 1 ? ablPointer[1].mData?.assumingMemoryBound(to: Float.self) : nil
            
            let samplePeriod = 1.0 / self.sampleRate
            
            os_unfair_lock_lock(self.voiceLock)
            var voicesToRemove = [Int]()
            
            for frame in 0..<Int(frameCount) {
                var mixedSample: Float = 0.0
                
                // Synthesize active piano voices
                for (pitch, var voice) in self.activeVoices {
                    voice.ageSeconds += samplePeriod
                    let freq = voice.frequency
                    
                    // Inharmonicity detuning characteristic of piano strings
                    let inharmonicFactor = 1.0 + 0.0001 * pow(freq / 440.0, 1.8)
                    let baseStep = 2.0 * Double.pi * freq * samplePeriod
                    let detunedStep = 2.0 * Double.pi * (freq * 1.0008) * samplePeriod
                    let harmonicStep = 2.0 * Double.pi * (freq * 2.0 * inharmonicFactor) * samplePeriod
                    
                    voice.phase += baseStep
                    voice.detunePhase += detunedStep
                    voice.harmonicPhase += harmonicStep
                    
                    if voice.phase > 2.0 * Double.pi { voice.phase -= 2.0 * Double.pi }
                    if voice.detunePhase > 2.0 * Double.pi { voice.detunePhase -= 2.0 * Double.pi }
                    if voice.harmonicPhase > 2.0 * Double.pi { voice.harmonicPhase -= 2.0 * Double.pi }
                    
                    // Piano envelope: sharp percussive hammer attack + exponential multi-stage decay
                    let attackTime = 0.005
                    let attackGain: Float = voice.ageSeconds < attackTime ? Float(voice.ageSeconds / attackTime) : 1.0
                    
                    // Pitch-dependent decay (higher notes decay faster than deep bass)
                    let decayConstant = 0.6 + (Double(pitch) / 127.0) * 2.4
                    var amplitude = exp(-decayConstant * voice.ageSeconds)
                    
                    if voice.isReleased {
                        let releaseAge = voice.ageSeconds - voice.releaseTime
                        amplitude *= exp(-18.0 * releaseAge) // rapid damper damping
                        if releaseAge > 0.15 {
                            voicesToRemove.append(pitch)
                        }
                    } else if amplitude < 0.0005 || voice.ageSeconds > 8.0 {
                        voicesToRemove.append(pitch)
                    }
                    
                    // Unison chorus + 2nd and 3rd harmonics + warm felt fundamental
                    let s1 = sin(voice.phase)
                    let s2 = sin(voice.detunePhase) * 0.7
                    let s3 = sin(voice.harmonicPhase) * 0.35 * exp(-3.0 * decayConstant * voice.ageSeconds)
                    let s4 = sin(voice.phase * 3.0) * 0.15 * exp(-5.0 * decayConstant * voice.ageSeconds)
                    
                    let voiceSample = Float(s1 + s2 + s3 + s4) * attackGain * Float(amplitude) * voice.velocity * 0.35
                    mixedSample += voiceSample
                    
                    self.activeVoices[pitch] = voice
                }
                
                // Metronome click generation
                if self.metronomeClickCountdown > 0 {
                    let clickFreq = self.metronomeIsDownbeat ? 1200.0 : 800.0
                    let clickSample = Float(sin(self.metronomePhase)) * (Float(self.metronomeClickCountdown) / 800.0) * 0.3
                    self.metronomePhase += 2.0 * Double.pi * clickFreq * samplePeriod
                    self.metronomeClickCountdown -= 1
                    mixedSample += clickSample
                }
                
                let finalSample = max(-0.98, min(0.98, mixedSample * self.masterVolume))
                leftChannel[frame] = finalSample
                rightChannel?[frame] = finalSample
            }
            
            // Cleanup decayed voices
            for pitch in voicesToRemove {
                self.activeVoices.removeValue(forKey: pitch)
            }
            os_unfair_lock_unlock(self.voiceLock)
            
            return noErr
        }
        
        self.synthNode = synth
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(synth)
        engine.attach(samplerNode)
        
        engine.connect(synth, to: engine.mainMixerNode, format: format)
        engine.connect(samplerNode, to: engine.mainMixerNode, format: format)
        
        start()
    }
    
    public func start() {
        guard !isEngineRunning else { return }
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            print("[PianoAudioEngine] Error starting audio engine: \(error)")
        }
    }
    
    public func stop() {
        guard isEngineRunning else { return }
        engine.stop()
        isEngineRunning = false
    }
    
    // MARK: - Piano Playing API
    
    public func noteOn(pitch: Int, velocity: Float = 0.8) {
        guard !isMuted else { return }
        let clampedPitch = max(21, min(108, pitch)) // Standard 88-key range
        let freq = 440.0 * pow(2.0, Double(clampedPitch - 69) / 12.0)
        
        os_unfair_lock_lock(voiceLock)
        activeVoices[clampedPitch] = ActiveVoice(
            pitch: clampedPitch,
            frequency: freq,
            velocity: max(0.1, min(1.0, velocity)),
            ageSeconds: 0.0,
            isReleased: false,
            releaseTime: 0.0
        )
        os_unfair_lock_unlock(voiceLock)
    }
    
    public func noteOff(pitch: Int) {
        os_unfair_lock_lock(voiceLock)
        if var voice = activeVoices[pitch] {
            voice.isReleased = true
            voice.releaseTime = voice.ageSeconds
            activeVoices[pitch] = voice
        }
        os_unfair_lock_unlock(voiceLock)
    }
    
    public func allNotesOff() {
        os_unfair_lock_lock(voiceLock)
        activeVoices.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(voiceLock)
    }
    
    public func triggerMetronomeClick(isDownbeat: Bool) {
        self.metronomeIsDownbeat = isDownbeat
        self.metronomePhase = 0.0
        self.metronomeClickCountdown = 800 // ~18ms transient burst
    }
    
    /// Optional: Load external SoundFont (.sf2) file
    public func loadSoundFont(url: URL) -> Bool {
        do {
            try samplerNode.loadInstrument(at: url)
            return true
        } catch {
            print("[PianoAudioEngine] Failed to load soundfont at \(url): \(error)")
            return false
        }
    }
}
