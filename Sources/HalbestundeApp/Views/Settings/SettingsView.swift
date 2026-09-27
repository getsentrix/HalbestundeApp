//
//  SettingsView.swift
//  HalbestundeApp
//
//  Clean, minimal native iOS settings view with inset grouped list styling.
//  Configures audio engine acoustics, OMR recognition filters, and app preferences.
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var audioEngine: PianoAudioEngine
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("audioLatencyLow") private var audioLatencyLow: Bool = true
    @AppStorage("omrSensitivityHigh") private var omrSensitivityHigh: Bool = true
    
    public init(audioEngine: PianoAudioEngine = .shared) {
        self.audioEngine = audioEngine
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Audio Engine Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Master Volume")
                            Spacer()
                            Text("\(Int(audioEngine.masterVolume * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Slider(value: $audioEngine.masterVolume, in: 0...1)
                                .tint(.accentColor)
                            
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Low-Latency Audio Buffer", isOn: $audioLatencyLow)
                    
                    LabeledContent("Acoustic Model", value: "Procedural Grand Piano")
                } header: {
                    Text("Audio & Acoustics")
                } footer: {
                    Text("Real-time physical acoustic model using high-resolution harmonic sine synthesis and polyphonic envelope shaping.")
                }
                
                // OMR Section
                Section {
                    Toggle("High-Sensitivity Notehead Filter", isOn: $omrSensitivityHigh)
                } header: {
                    Text("Optical Music Recognition (OMR)")
                } footer: {
                    Text("Uses Apple Vision contour detection and horizontal staff projection to recognize staves, accidentals, and rhythms from sheet music.")
                }
                
                // Haptics Section
                Section {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                } header: {
                    Text("Haptics & Touch")
                }
                
                // About Section
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "music.note.tv.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Halbestunde iOS")
                                .font(.headline)
                            Text("Version 1.0.0 (Build 1)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    LabeledContent("Architecture", value: "Pure Native Swift & SwiftUI")
                    LabeledContent("Compatibility", value: "iOS 17.0+ • iPhone & iPad")
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
}
