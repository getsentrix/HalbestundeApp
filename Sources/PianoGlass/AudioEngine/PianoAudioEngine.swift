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
            var voices = Array(self.activeVoices.values)
            let voiceCount = voices.count
            var voicesToRemove = Set<Int>()
            let twoPi = 2.0 * Double.pi
            
            for frame in 0..<Int(frameCount) {
                var mixedSample: Float = 0.0
                
                // Synthesize active piano voices from local array
                for i in 0..<voiceCount {
                    voices[i].ageSeconds += samplePeriod
                    let freq = voices[i].frequency
                    let pitch = voices[i].pitch
                    
                    // Inharmonicity detuning characteristic of piano strings
                    let inharmonicFactor = 1.0 + 0.0001 * pow(freq / 440.0, 1.8)
                    let baseStep = twoPi * freq * samplePeriod
                    let detunedStep = twoPi * (freq * 1.0008) * samplePeriod
                    let harmonicStep = twoPi * (freq * 2.0 * inharmonicFactor) * samplePeriod
                    
                    voices[i].phase += baseStep
                    voices[i].detunePhase += detunedStep
                    voices[i].harmonicPhase += harmonicStep
                    
                    if voices[i].phase > twoPi { voices[i].phase -= twoPi }
                    if voices[i].detunePhase > twoPi { voices[i].detunePhase -= twoPi }
                    if voices[i].harmonicPhase > twoPi { voices[i].harmonicPhase -= twoPi }
                    
                    // Piano envelope: sharp percussive hammer attack + exponential multi-stage decay
                    let attackTime = 0.004
                    let attackGain: Float = voices[i].ageSeconds < attackTime ? Float(voices[i].ageSeconds / attackTime) : 1.0
                    
                    // Pitch-dependent decay (higher notes decay faster than deep bass)
                    let decayConstant = 0.6 + (Double(pitch) / 127.0) * 2.4
                    var amplitude = exp(-decayConstant * voices[i].ageSeconds)
                    
                    if voices[i].isReleased {
                        let releaseAge = voices[i].ageSeconds - voices[i].releaseTime
                        amplitude *= exp(-18.0 * releaseAge) // rapid damper damping
                        if releaseAge > 0.15 {
                            voicesToRemove.insert(pitch)
                        }
                    } else if amplitude < 0.0005 || voices[i].ageSeconds > 8.0 {
                        voicesToRemove.insert(pitch)
                    }
                    
                    // Unison chorus + 2nd and 3rd harmonics + warm felt fundamental
                    let s1 = sin(voices[i].phase)
                    let s2 = sin(voices[i].detunePhase) * 0.7
                    let s3 = sin(voices[i].harmonicPhase) * 0.35 * exp(-3.0 * decayConstant * voices[i].ageSeconds)
                    let s4 = sin(voices[i].phase * 3.0) * 0.15 * exp(-5.0 * decayConstant * voices[i].ageSeconds)
                    
                    let voiceSample = Float(s1 + s2 + s3 + s4) * attackGain * Float(amplitude) * voices[i].velocity * 0.28
                    mixedSample += voiceSample
                }
                
                // Metronome click generation
                if self.metronomeClickCountdown > 0 {
                    let clickFreq = self.metronomeIsDownbeat ? 1200.0 : 800.0
                    let clickSample = Float(sin(self.metronomePhase)) * (Float(self.metronomeClickCountdown) / 800.0) * 0.3
                    self.metronomePhase += twoPi * clickFreq * samplePeriod
                    self.metronomeClickCountdown -= 1
                    mixedSample += clickSample
                }
                
                // Warm, analog soft-saturation limiter (tanh) prevents digital clipping on chords
                let driven = mixedSample * self.masterVolume
                let finalSample = Float(tanh(Double(driven * 0.85))) * 0.98
                leftChannel[frame] = finalSample
                rightChannel?[frame] = finalSample
            }
            
            // Write back updated voice states once per audio buffer
            for voice in voices {
                if !voicesToRemove.contains(voice.pitch) {
                    self.activeVoices[voice.pitch] = voice
                }
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
        if activeVoices.count >= 32 {
            // Voice stealing: steal oldest voice to prevent CPU overload and keep polyphony clean
            if let oldest = activeVoices.values.max(by: { $0.ageSeconds < $1.ageSeconds }) {
                activeVoices.removeValue(forKey: oldest.pitch)
            }
        }
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
