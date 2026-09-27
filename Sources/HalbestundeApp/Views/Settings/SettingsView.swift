//
//  SettingsView.swift
//  HalbestundeApp
//
//  App preferences, audio engine settings, and soundfont management.
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var audioEngine: PianoAudioEngine
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("audioLatencyLow") private var audioLatencyLow: Bool = true
    @AppStorage("omrSensitivityHigh") private var omrSensitivityHigh: Bool = true
    @State private var showingSoundfontImporter: Bool = false
    @State private var soundfontStatus: String = "Procedural Grand Piano Active (Physical Acoustic Model)"
    
    public init(audioEngine: PianoAudioEngine = .shared) {
        self.audioEngine = audioEngine
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassTheme.ambientConcertBackdrop
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Audio Engine Section
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Audio Engine & Acoustics", systemImage: "speaker.wave.3.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                HStack {
                                    Text("Master Volume")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Text("\(Int(audioEngine.masterVolume * 100))%")
                                        .font(.subheadline.bold())
                                        .foregroundColor(LiquidGlassTheme.leftHandCyan)
                                }
                                Slider(value: $audioEngine.masterVolume, in: 0...1)
                                    .tint(LiquidGlassTheme.leftHandCyan)
                                
                                Divider().background(Color.white.opacity(0.2))
                                
                                Toggle("Ultra-Low Audio Latency Buffer", isOn: $audioLatencyLow)
                                    .tint(LiquidGlassTheme.emeraldGreen)
                                
                                Text("Acoustic Model: \(soundfontStatus)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        
                        // Scanner & OMR Section
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Optical Music Recognition (OMR)", systemImage: "viewfinder")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Toggle("High-Sensitivity Notehead Filter", isOn: $omrSensitivityHigh)
                                    .tint(LiquidGlassTheme.rightHandAmber)
                                
                                Text("Uses Apple Vision contour detection and horizontal staff projection to recognize staves, accidentals, and rhythms.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        
                        // Haptics & Feel
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Touch & Keyboard Response", systemImage: "hand.tap.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Toggle("Haptic Key Feedback", isOn: $hapticsEnabled)
                                    .tint(LiquidGlassTheme.leftHandCyan)
                            }
                        }
                        
                        // About Section
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("About Halbestunde iOS", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text("Version 1.0.0 • Pure Native Swift & SwiftUI")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text("Powered by Apple Vision, AVAudioEngine, and Liquid Glass Design System.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
