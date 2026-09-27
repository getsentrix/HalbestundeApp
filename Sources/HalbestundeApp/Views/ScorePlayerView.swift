//
//  ScorePlayerView.swift
//  HalbestundeApp
//
//  Minimal, focused native player for sheet music playback.
//  Clean iOS typography, cover / score preview, smooth scrubbing,
//  elapsed/remaining timestamps, AirPlay routing, and distraction-free audio controls
//  inspired by Feather and Apple Music.
//

import SwiftUI
#if os(iOS)
import AVKit
#endif

public struct ScorePlayerView: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    @State private var isDraggingScrubber: Bool = false
    @State private var scrubBeat: Double = 0.0
    @State private var showRemainingTime: Bool = true
    @State private var previewMode: Int = 0 // 0: Score Preview, 1: Cover Artwork
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    private var totalBeats: Double {
        max(1.0, viewModel.currentScore.totalBeats)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // 1. Cover / Score Preview Switcher
                    Picker("Preview Mode", selection: $previewMode) {
                        Text("Score").tag(0)
                        Text("Cover").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .padding(.top, 4)
                    
                    // 1. Cover / Score Preview Container
                    if previewMode == 0 {
                        // Interactive Sheet Music Score Preview
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Score Preview", systemImage: "doc.text")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Measure \(viewModel.currentMeasureIndex + 1) of \(max(1, viewModel.currentScore.measures.count))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 4)
                            
                            ScoreCanvasView(viewModel: viewModel)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
                        }
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                    } else {
                        // Minimalist Apple Music / Feather-Style Cover Artwork
                        ScoreCoverCardView(
                            score: viewModel.currentScore,
                            isPlaying: viewModel.isPlaying
                        )
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                    }
                    
                    // 2. Title & Composer Metadata
                    VStack(spacing: 6) {
                        Text(viewModel.currentScore.title)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        Text(viewModel.currentScore.composer)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            Text(viewModel.currentScore.keySignature.name)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill))
                                .clipShape(Capsule())
                            
                            Text(viewModel.currentScore.timeSignature.displayString)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill))
                                .clipShape(Capsule())
                            
                            Text("\(Int(viewModel.tempoBPM)) BPM")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill))
                                .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    
                    // 3. Clean Scrub Progress Bar (Time Elapsed / Remaining)
                    VStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: {
                                    isDraggingScrubber ? scrubBeat : viewModel.currentBeat
                                },
                                set: { newValue in
                                    scrubBeat = newValue
                                }
                            ),
                            in: 0...totalBeats,
                            onEditingChanged: { editing in
                                isDraggingScrubber = editing
                                if !editing {
                                    viewModel.seek(toBeat: scrubBeat)
                                }
                            }
                        )
                        .tint(.accentColor)
                        
                        HStack {
                            Text(viewModel.formattedCurrentTime)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                showRemainingTime.toggle()
                            }) {
                                Text(showRemainingTime ? viewModel.formattedRemainingTime : viewModel.formattedTotalTime)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // 4. Primary Playback Controls
                    HStack(spacing: 38) {
                        // Previous Measure
                        Button(action: {
                            let prev = max(0, viewModel.currentMeasureIndex - 1)
                            viewModel.seek(toMeasure: prev)
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        
                        // Large Play / Pause
                        Button(action: {
                            viewModel.togglePlayPause()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                                
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: viewModel.isPlaying ? 0 : 2)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Next Measure
                        Button(action: {
                            let next = min(max(0, viewModel.currentScore.measures.count - 1), viewModel.currentMeasureIndex + 1)
                            viewModel.seek(toMeasure: next)
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    
                    // 5. Speed / Tempo Controls & Restart
                    HStack(spacing: 16) {
                        Menu {
                            Button("0.5x Speed") { viewModel.tempoBPM = viewModel.currentScore.defaultBPM * 0.5 }
                            Button("0.75x Speed") { viewModel.tempoBPM = viewModel.currentScore.defaultBPM * 0.75 }
                            Button("1.0x Normal") { viewModel.tempoBPM = viewModel.currentScore.defaultBPM }
                            Button("1.25x Speed") { viewModel.tempoBPM = viewModel.currentScore.defaultBPM * 1.25 }
                            Button("1.5x Speed") { viewModel.tempoBPM = viewModel.currentScore.defaultBPM * 1.5 }
                            Button("2.0x Double") { viewModel.tempoBPM = viewModel.currentScore.defaultBPM * 2.0 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                Text(String(format: "%.2fx", viewModel.tempoBPM / max(1.0, viewModel.currentScore.defaultBPM)))
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemFill))
                            .clipShape(Capsule())
                        }
                        
                        Button(action: {
                            viewModel.seek(toBeat: 0.0)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "backward.end")
                                Text("Restart")
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemFill))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(.primary)
                    
                    // 6. AirPlay & Master Volume Control
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $viewModel.audioEngine.masterVolume, in: 0...1)
                            .tint(.accentColor)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        #if os(iOS)
                        AirRoutePickerRepresentable()
                            .frame(width: 30, height: 30)
                        #else
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                        #endif
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Looping", isOn: $viewModel.isLoopingEnabled)
                        Toggle("Solo Right Hand", isOn: $viewModel.isRightHandSolo)
                        Toggle("Solo Left Hand", isOn: $viewModel.isLeftHandSolo)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Minimalist Apple Music / Feather-Style Cover Artwork Card
private struct ScoreCoverCardView: View {
    let score: Score
    let isPlaying: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemGroupedBackground),
                            Color(.tertiarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
            
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)
                    
                    Image(systemName: isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
                
                VStack(spacing: 3) {
                    Text(score.title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    
                    Text(score.composer)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    Label("\(score.measures.count) Measures", systemImage: "music.pages")
                    Text("•")
                    Label(score.keySignature.name, systemImage: "key.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(24)
        }
        .frame(height: 184)
    }
}

// MARK: - Native iOS AirPlay / Audio Route Picker
#if os(iOS)
public struct AirRoutePickerRepresentable: UIViewRepresentable {
    public init() {}
    
    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.secondaryLabel
        picker.activeTintColor = UIColor.systemBlue
        picker.prioritizesVideoDevices = false
        return picker
    }
    
    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
