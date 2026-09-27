//
//  ScoreCanvasView.swift
//  PianoGlass
//
//  Vector-rendered interactive sheet music score with animated liquid glass playhead,
//  dual-hand glowing notes, and touch-to-seek measure selection.
//

import SwiftUI

public struct ScoreCanvasView: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    
    // Layout parameters
    private let staffSpacing: CGFloat = 8.0
    private let measureWidth: CGFloat = 200.0
    private let systemHeight: CGFloat = 160.0
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Clef & Key signature header
                    ScoreHeaderView()
                        .frame(width: 80, height: systemHeight)
                    
                    // Measures
                    ForEach(viewModel.currentScore.measures) { measure in
                        MeasureView(
                            measure: measure,
                            viewModel: viewModel,
                            staffSpacing: staffSpacing,
                            systemHeight: systemHeight
                        )
                        .frame(width: measureWidth, height: systemHeight)
                        .id(measure.index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            #if canImport(UIKit)
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            #endif
                            viewModel.seek(toMeasure: measure.index)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                )
            }
            .onChange(of: viewModel.currentMeasureIndex) { _, newMeasure in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newMeasure, anchor: .center)
                }
            }
        }
        .frame(height: systemHeight + 24)
    }
}

// MARK: - Score Header (Clefs & Time Signature)
private struct ScoreHeaderView: View {
    var body: some View {
        VStack(spacing: 28) {
            // Treble clef
            Text(Clef.treble.symbol)
                .font(.system(size: 38, weight: .regular, design: .serif))
                .foregroundColor(.primary.opacity(0.85))
                .offset(y: 4)
            
            // Bass clef
            Text(Clef.bass.symbol)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundColor(.primary.opacity(0.85))
                .offset(y: -4)
        }
    }
}

// MARK: - Individual Measure View
private struct MeasureView: View {
    let measure: Measure
    @ObservedObject var viewModel: ScorePlayerViewModel
    let staffSpacing: CGFloat
    let systemHeight: CGFloat
    
    private var isCurrentMeasure: Bool {
        viewModel.currentMeasureIndex == measure.index
    }
    
    private var isInLoopRange: Bool {
        guard viewModel.isLoopingEnabled,
              let loop = viewModel.audioScheduler.practiceSettings.loopRange else { return false }
        return loop.contains(measureIndex: measure.index)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Active measure / Loop background highlight
                if isInLoopRange {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                        )
                } else if isCurrentMeasure {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.05))
                }
                
                // Grand Staff Lines (Treble & Bass)
                VStack(spacing: 34) {
                    // Treble Staff (5 lines)
                    StaffLinesShape(spacing: staffSpacing)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        .frame(height: staffSpacing * 4)
                    
                    // Bass Staff (5 lines)
                    StaffLinesShape(spacing: staffSpacing)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        .frame(height: staffSpacing * 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Measure index badge
                Text("\(measure.index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isCurrentMeasure ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .offset(x: 4, y: 4)
                
                // Notes rendering
                ForEach(measure.notes) { note in
                    NoteGlyphView(
                        note: note,
                        measure: measure,
                        staffSpacing: staffSpacing,
                        measureWidth: geo.size.width,
                        systemHeight: geo.size.height,
                        isActive: viewModel.activeNoteEventIds.contains(note.id)
                    )
                }
                
                // Measure right barline
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .offset(x: geo.size.width - 1)
                
                // Animated Playhead cursor across current measure
                if isCurrentMeasure {
                    let measureProgress = max(0.0, min(1.0, (viewModel.currentBeat - measure.startBeat) / measure.durationBeats))
                    PlayheadCursorView()
                        .offset(x: geo.size.width * CGFloat(measureProgress))
                }
            }
        }
    }
}

// MARK: - Playhead Cursor Line
private struct PlayheadCursorView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Glowing vertical playhead track
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.85),
                            Color.accentColor,
                            Color.accentColor.opacity(0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2.5)
                .shadow(color: Color.accentColor.opacity(0.45), radius: 3, x: 0, y: 0)
            
            // Refined glowing indicator bead
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .shadow(color: Color.accentColor.opacity(0.6), radius: 4, y: 1)
                .offset(y: -4)
        }
    }
}

// MARK: - Staff Lines Shape
private struct StaffLinesShape: Shape {
    let spacing: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<5 {
            let y = CGFloat(i) * spacing
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

// MARK: - Note Glyph View
private struct NoteGlyphView: View {
    let note: NoteEvent
    let measure: Measure
    let staffSpacing: CGFloat
    let measureWidth: CGFloat
    let systemHeight: CGFloat
    let isActive: Bool
    
    var body: some View {
        if !note.isRest {
            let activeColor = Color.accentColor
            let restingColor = Color.primary.opacity(0.85)
            let relativeBeat = note.startBeat - measure.startBeat
            let xOffset = 25.0 + (measureWidth - 45.0) * CGFloat(relativeBeat / measure.durationBeats)
            let yOffset = calculateYOffset()
            
            ZStack {
                // Notehead ellipse
                Ellipse()
                    .fill(isActive ? activeColor : restingColor)
                    .frame(width: 12, height: 9)
                    .rotationEffect(.degrees(-18))
                    .shadow(color: isActive ? activeColor.opacity(0.6) : Color.clear, radius: 4, y: 1)
                
                // Stem
                Rectangle()
                    .fill(isActive ? activeColor : restingColor)
                    .frame(width: 1.5, height: 26)
                    .offset(x: 5, y: -13)
                
                // Tied note indicator arc
                if note.isTiedContinuation {
                    Image(systemName: "link")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isActive ? activeColor : restingColor.opacity(0.6))
                        .offset(x: -8, y: -6)
                }
            }
            .position(x: xOffset, y: yOffset)
        }
    }
    
    private func calculateYOffset() -> CGFloat {
        // Approximate visual staff positioning relative to MIDI pitch
        if note.hand == .right {
            // Treble: E4 (64) is at bottom line of top staff (~y = 48)
            let pitchDiff = Double(note.pitch.midiNumber - 64)
            return 58.0 - CGFloat(pitchDiff * 2.8)
        } else {
            // Bass: G2 (43) is at bottom line of bottom staff (~y = 126)
            let pitchDiff = Double(note.pitch.midiNumber - 43)
            return 134.0 - CGFloat(pitchDiff * 2.8)
        }
    }
}
