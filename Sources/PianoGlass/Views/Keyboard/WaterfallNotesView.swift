//
//  WaterfallNotesView.swift
//  PianoGlass
//
//  Synthesia-style vertical falling notes visualizer with liquid glass trails.
//

import SwiftUI

public struct WaterfallNotesView: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    
    // Lookahead window in beats
    private let lookaheadBeats: Double = 4.0
    private let waterfallHeight: CGFloat = 140.0
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background dark water glass gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                LiquidGlassTheme.midnightBackground.opacity(0.7),
                                LiquidGlassTheme.deepSlate.opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Falling note blocks
                ForEach(visibleNotes) { note in
                    let yOffset = calculateY(note: note)
                    let blockHeight = calculateHeight(note: note)
                    let xOffset = calculateX(note: note, width: geo.size.width)
                    let color = note.hand == .right ? LiquidGlassTheme.rightHandAmber : LiquidGlassTheme.leftHandCyan
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                        )
                        .glowing(color: color, radius: 8)
                        .frame(width: 14, height: max(6, blockHeight))
                        .position(x: xOffset, y: yOffset)
                }
                
                // Bottom strike line
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(height: 1.5)
            }
        }
        .frame(height: waterfallHeight)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(LiquidGlassTheme.specularRimGradient, lineWidth: 1)
        )
    }
    
    private var visibleNotes: [NoteEvent] {
        let current = viewModel.currentBeat
        let maxBeat = current + lookaheadBeats
        return viewModel.currentScore.allNotes.filter { note in
            !note.isRest && note.endBeat >= current && note.startBeat <= maxBeat
        }
    }
    
    private func calculateY(note: NoteEvent) -> CGFloat {
        let current = viewModel.currentBeat
        let beatDiff = note.startBeat - current
        let progress = beatDiff / lookaheadBeats
        // When beatDiff == 0, note is at the bottom strike line (y = waterfallHeight)
        return waterfallHeight - CGFloat(progress) * waterfallHeight
    }
    
    private func calculateHeight(note: NoteEvent) -> CGFloat {
        let beatFraction = note.durationBeats / lookaheadBeats
        return CGFloat(beatFraction) * waterfallHeight
    }
    
    private func calculateX(note: NoteEvent, width: CGFloat) -> CGFloat {
        // Map MIDI 21...108 across available width
        let minPitch = 21.0
        let maxPitch = 108.0
        let fraction = (Double(note.pitch.midiNumber) - minPitch) / (maxPitch - minPitch)
        return CGFloat(fraction) * (width - 40.0) + 20.0
    }
}
