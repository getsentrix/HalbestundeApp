//
//  PracticeDockView.swift
//  HalbestundeApp
//
//  Floating liquid glass practice dock with playhead scrubbing, tempo controls,
//  hand isolation toggles (LH/RH), and A-B loop activation.
//

import SwiftUI

public struct PracticeDockView: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Playhead Scrub Slider & Time Display
            HStack(spacing: 10) {
                Text(viewModel.formattedCurrentTime)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 42, alignment: .leading)
                
                // Scrub progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [LiquidGlassTheme.leftHandCyan, LiquidGlassTheme.rightHandAmber],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * CGFloat(viewModel.playbackProgress)), height: 6)
                            .glowing(color: LiquidGlassTheme.leftHandCyan, radius: 6)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = max(0.0, min(1.0, Double(value.location.x / geo.size.width)))
                                viewModel.seek(toBeat: progress * viewModel.currentScore.totalBeats)
                            }
                    )
                }
                .frame(height: 18)
                
                Text(viewModel.formattedTotalTime)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            
            // Primary Control Deck
            HStack(spacing: 16) {
                // Rewind to start
                GlassIconButton(
                    icon: "backward.end.fill",
                    size: 38,
                    tint: .white.opacity(0.85),
                    action: { viewModel.seek(toBeat: 0.0) }
                )
                
                // Play / Pause Master Button
                Button(action: { viewModel.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(
                                viewModel.isPlaying ?
                                    LiquidGlassTheme.rightHandAmber.opacity(0.3) :
                                    LiquidGlassTheme.emeraldGreen.opacity(0.3)
                            )
                            .background(Circle().fill(.ultraThinMaterial))
                        
                        Circle()
                            .stroke(
                                viewModel.isPlaying ? LiquidGlassTheme.amberRimGradient : LiquidGlassTheme.specularRimGradient,
                                lineWidth: 2
                            )
                        
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: viewModel.isPlaying ? 0 : 2)
                    }
                    .frame(width: 54, height: 54)
                    .modifier(
                        GlowModifier(
                            color: viewModel.isPlaying ? LiquidGlassTheme.rightHandAmber : LiquidGlassTheme.emeraldGreen,
                            radius: 14,
                            active: true
                        )
                    )
                }
                .buttonStyle(SpringPressStyle())
                
                // Hand Isolation Toggles (Left Hand / Right Hand)
                HStack(spacing: 8) {
                    // Left Hand (Cyan) Solo/Mute
                    HandToggleButton(
                        label: "LH",
                        subtitle: "Bass",
                        color: LiquidGlassTheme.leftHandCyan,
                        isMuted: viewModel.isLeftHandMuted,
                        isSolo: viewModel.isLeftHandSolo,
                        onToggleMute: { viewModel.isLeftHandMuted.toggle() },
                        onToggleSolo: { viewModel.isLeftHandSolo.toggle() }
                    )
                    
                    // Right Hand (Amber) Solo/Mute
                    HandToggleButton(
                        label: "RH",
                        subtitle: "Treble",
                        color: LiquidGlassTheme.rightHandAmber,
                        isMuted: viewModel.isRightHandMuted,
                        isSolo: viewModel.isRightHandSolo,
                        onToggleMute: { viewModel.isRightHandMuted.toggle() },
                        onToggleSolo: { viewModel.isRightHandSolo.toggle() }
                    )
                }
                
                Spacer()
                
                // Loop A-B Quick Toggle
                GlassIconButton(
                    icon: "repeat",
                    size: 38,
                    tint: viewModel.isLoopingEnabled ? LiquidGlassTheme.leftHandCyan : .white.opacity(0.7),
                    isActive: viewModel.isLoopingEnabled,
                    action: { viewModel.isLoopingEnabled.toggle() }
                )
                
                // Metronome Quick Toggle
                GlassIconButton(
                    icon: "metronome.fill",
                    size: 38,
                    tint: viewModel.isMetronomeEnabled ? LiquidGlassTheme.emeraldGreen : .white.opacity(0.7),
                    isActive: viewModel.isMetronomeEnabled,
                    action: { viewModel.isMetronomeEnabled.toggle() }
                )
                
                // Detailed Practice Settings Sheet Button
                GlassIconButton(
                    icon: "slider.horizontal.3",
                    size: 38,
                    tint: .white.opacity(0.85),
                    action: { viewModel.showPracticeSettings = true }
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .liquidGlass(
            cornerRadius: 24,
            tintColor: LiquidGlassTheme.obsidianSurface.opacity(0.8),
            borderGradient: LiquidGlassTheme.specularRimGradient,
            shadowRadius: 20
        )
        .sheet(isPresented: $viewModel.showPracticeSettings) {
            PracticeSettingsSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Hand Toggle Button
private struct HandToggleButton: View {
    let label: String
    let subtitle: String
    let color: Color
    let isMuted: Bool
    let isSolo: Bool
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    
    var body: some View {
        Button(action: onToggleMute) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isMuted ? .white.opacity(0.3) : color)
                
                Text(isMuted ? "MUTE" : (isSolo ? "SOLO" : subtitle))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(isMuted ? .red.opacity(0.8) : .white.opacity(0.6))
            }
            .frame(width: 46, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isMuted ? Color.red.opacity(0.12) : color.opacity(0.15))
                    .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isMuted ? Color.red.opacity(0.5) : color.opacity(0.5),
                        lineWidth: 1
                    )
            )
            .glowing(color: color, radius: 8, active: !isMuted)
        }
        .buttonStyle(SpringPressStyle(glowColor: color))
        .contextMenu {
            Button(isSolo ? "Disable Solo" : "Solo \(label)") {
                onToggleSolo()
            }
            Button(isMuted ? "Unmute \(label)" : "Mute \(label)") {
                onToggleMute()
            }
        }
    }
}
