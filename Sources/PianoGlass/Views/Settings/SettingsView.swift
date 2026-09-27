//
//  SettingsView.swift
//  PianoGlass
//
//  Clean, minimal native iOS settings view with inset grouped list styling.
//  Simple controls, zero jargon, and link to GitHub repository.
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var audioEngine: PianoAudioEngine
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("enhanceScanContrast") private var enhanceScanContrast: Bool = true
    
    public init(audioEngine: PianoAudioEngine = .shared) {
        self.audioEngine = audioEngine
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Audio Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
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
                } header: {
                    Text("Audio")
                }
                
                // Scanner Section
                Section {
                    Toggle("Enhance Scan Contrast", isOn: $enhanceScanContrast)
                } header: {
                    Text("Scanner")
                } footer: {
                    Text("Improves recognition on faintly printed sheet music.")
                }
                
                // Touch & Feedback
                Section {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                } header: {
                    Text("Preferences")
                }
                
                // Source Code & Links Section
                Section {
                    Link(destination: URL(string: "https://github.com/getsentrix/PianoGlass")!) {
                        HStack {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.primary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("GitHub")
                                    .foregroundColor(.secondary)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Link(destination: URL(string: "https://getsentrix.github.io/PianoGlass/")!) {
                        HStack {
                            Label("Website", systemImage: "safari")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Open Source")
                }
                
                // About Section
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PianoGlass")
                                .font(.headline)
                            Text("Version 1.0.0")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    LabeledContent("Compatibility", value: "iOS 17.0+")
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
}
