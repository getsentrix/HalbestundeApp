//
//  PracticeSettingsSheet.swift
//  PianoGlass
//
//  Comprehensive practice tools: tempo dial, transposition, A-B looping,
//  hand isolation faders, and keyboard layout configuration.
//

import SwiftUI

public struct PracticeSettingsSheet: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassTheme.ambientConcertBackdrop
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Tempo BPM Control
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Tempo", systemImage: "metronome")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(Int(viewModel.tempoBPM)) BPM")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(LiquidGlassTheme.rightHandAmber)
                                }
                                
                                Slider(value: $viewModel.tempoBPM, in: 40...240, step: 1)
                                    .tint(LiquidGlassTheme.rightHandAmber)
                                
                                // Tempo Presets
                                HStack(spacing: 8) {
                                    TempoPresetPill(title: "Largo (52)", bpm: 52, currentBPM: $viewModel.tempoBPM)
                                    TempoPresetPill(title: "Andante (76)", bpm: 76, currentBPM: $viewModel.tempoBPM)
                                    TempoPresetPill(title: "Mod (108)", bpm: 108, currentBPM: $viewModel.tempoBPM)
                                    TempoPresetPill(title: "Allegro (132)", bpm: 132, currentBPM: $viewModel.tempoBPM)
                                    TempoPresetPill(title: "Presto (172)", bpm: 172, currentBPM: $viewModel.tempoBPM)
                                }
                            }
                        }
                        
                        // 2. Transposition (+/- 12 Semitones)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Transposition", systemImage: "tuningfork")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    let sign = viewModel.transpositionSemitones > 0 ? "+" : ""
                                    Text("\(sign)\(viewModel.transpositionSemitones) semitones")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(LiquidGlassTheme.leftHandCyan)
                                }
                                
                                Stepper(
                                    value: $viewModel.transpositionSemitones,
                                    in: -12...12,
                                    step: 1
                                ) {
                                    Text("Key: \(transposedKeyName)")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                        
                        // 3. A-B Measure Practice Looping
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle(isOn: $viewModel.isLoopingEnabled) {
                                    Label("A-B Measure Loop", systemImage: "repeat")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .tint(LiquidGlassTheme.leftHandCyan)
                                
                                if viewModel.isLoopingEnabled {
                                    HStack(spacing: 20) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Start (Measure A)")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                            Stepper(
                                                "M\(viewModel.loopStartMeasure + 1)",
                                                value: $viewModel.loopStartMeasure,
                                                in: 0...max(0, viewModel.currentScore.measures.count - 1)
                                            )
                                            .foregroundColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("End (Measure B)")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                            Stepper(
                                                "M\(viewModel.loopEndMeasure + 1)",
                                                value: $viewModel.loopEndMeasure,
                                                in: viewModel.loopStartMeasure...max(0, viewModel.currentScore.measures.count - 1)
                                            )
                                            .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 4. Hand Isolation & Part Volume
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Hand Isolation & Balance", systemImage: "hands.sparkles.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                // Right Hand (Treble)
                                HStack {
                                    Text("Right Hand (Treble)")
                                        .font(.subheadline)
                                        .foregroundColor(LiquidGlassTheme.rightHandAmber)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { !viewModel.isRightHandMuted },
                                        set: { viewModel.isRightHandMuted = !$0 }
                                    ))
                                    .tint(LiquidGlassTheme.rightHandAmber)
                                }
                                
                                // Left Hand (Bass)
                                HStack {
                                    Text("Left Hand (Bass)")
                                        .font(.subheadline)
                                        .foregroundColor(LiquidGlassTheme.leftHandCyan)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { !viewModel.isLeftHandMuted },
                                        set: { viewModel.isLeftHandMuted = !$0 }
                                    ))
                                    .tint(LiquidGlassTheme.leftHandCyan)
                                }
                            }
                        }
                        
                        // 5. Visualizer & Keyboard Settings
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Visualizer & Keyboard", systemImage: "pianokeys")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Toggle("Falling Notes Visualizer", isOn: $viewModel.showFallingNotes)
                                    .tint(LiquidGlassTheme.rightHandAmber)
                                
                                Picker("Keyboard Size", selection: $viewModel.keyboardKeyCount) {
                                    Text("61 Keys").tag(61)
                                    Text("88 Keys (Full Grand)").tag(88)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Practice Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundColor(LiquidGlassTheme.leftHandCyan)
                }
            }
        }
    }
    
    private var transposedKeyName: String {
        let baseFifths = viewModel.currentScore.keySignature.fifths
        let semitones = viewModel.transpositionSemitones
        guard semitones != 0 else {
            return viewModel.currentScore.keySignature.name
        }
        var fifthsDelta = (semitones * 7) % 12
        if fifthsDelta > 6 { fifthsDelta -= 12 }
        if fifthsDelta < -6 { fifthsDelta += 12 }
        var newFifths = baseFifths + fifthsDelta
        if newFifths > 7 { newFifths -= 12 }
        if newFifths < -7 { newFifths += 12 }
        return KeySignature(fifths: newFifths, mode: viewModel.currentScore.keySignature.mode).name
    }
}

// MARK: - Tempo Preset Pill
private struct TempoPresetPill: View {
    let title: String
    let bpm: Double
    @Binding var currentBPM: Double
    
    var body: some View {
        Button(action: { currentBPM = bpm }) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Int(currentBPM) == Int(bpm) ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Int(currentBPM) == Int(bpm) ? LiquidGlassTheme.rightHandAmber : Color.white.opacity(0.1))
                )
        }
    }
}
