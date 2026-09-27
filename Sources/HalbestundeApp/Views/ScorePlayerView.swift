//
//  ScorePlayerView.swift
//  HalbestundeApp
//
//  Main interactive score practice view integrating the animated score,
//  illuminated virtual piano keyboard, falling notes, and practice dock.
//

import SwiftUI

public struct ScorePlayerView: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassTheme.ambientConcertBackdrop
                
                VStack(spacing: 12) {
                    // Header Card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.currentScore.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            HStack(spacing: 8) {
                                Text(viewModel.currentScore.composer)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text("•")
                                    .foregroundColor(.white.opacity(0.3))
                                
                                Text(viewModel.currentScore.keySignature.name)
                                    .font(.subheadline)
                                    .foregroundColor(LiquidGlassTheme.leftHandCyan)
                                
                                if viewModel.transpositionSemitones != 0 {
                                    let sign = viewModel.transpositionSemitones > 0 ? "+" : ""
                                    Text("(\(sign)\(viewModel.transpositionSemitones))")
                                        .font(.caption.bold())
                                        .foregroundColor(LiquidGlassTheme.rightHandAmber)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Active Practice Mode Pill
                        if viewModel.isLoopingEnabled {
                            GlassBadge(
                                text: "LOOP M\(viewModel.loopStartMeasure + 1)-M\(viewModel.loopEndMeasure + 1)",
                                color: LiquidGlassTheme.leftHandCyan
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // 1. Interactive Vector Score Canvas with Animated Playhead
                    ScoreCanvasView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                    
                    // 2. Optional Waterfall Notes Stream (Synthesia Mode)
                    if viewModel.showFallingNotes {
                        WaterfallNotesView(viewModel: viewModel)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // 3. Interactive Virtual Piano Keyboard (Dual Hand Illumination)
                    VirtualPianoKeyboardView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                    
                    // 4. Floating Practice Dock (Controls, Tempo, Loops, Hand Isolation)
                    PracticeDockView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
