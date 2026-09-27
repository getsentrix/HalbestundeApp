//
//  VirtualPianoKeyboardView.swift
//  PianoGlass
//
//  Interactive 61/88-key piano keyboard with liquid glass keycaps,
//  real-time dual-hand illumination (Cyan for LH, Amber for RH),
//  and responsive touch audition.
//

import SwiftUI

public struct VirtualPianoKeyboardView: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    
    // Configurable key dimensions
    private let whiteKeyWidth: CGFloat = 40.0
    private let whiteKeyHeight: CGFloat = 170.0
    private var blackKeyWidth: CGFloat { whiteKeyWidth * 0.62 }
    private var blackKeyHeight: CGFloat { whiteKeyHeight * 0.62 }
    
    // MIDI bounds based on key count selection
    private var startPitch: Int {
        viewModel.keyboardKeyCount == 88 ? 21 : 36 // A0 (21) vs C2 (36)
    }
    private var endPitch: Int {
        viewModel.keyboardKeyCount == 88 ? 108 : 96 // C8 (108) vs C7 (96)
    }
    
    @State private var touchedPitch: Int? = nil
    
    public init(viewModel: ScorePlayerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                // Octave quick navigation pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(octaveAnchors, id: \.self) { octave in
                            let targetPitch = min(endPitch, max(startPitch, (octave + 1) * 12))
                            OctaveAnchorPill(
                                octave: octave,
                                isActive: currentVisibleOctave == octave,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(targetPitch, anchor: .center)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 30)
                
                // Piano Keys Horizontal Scroll Container
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // White keys layer
                        HStack(spacing: 1.5) {
                            ForEach(whitePitches, id: \.self) { pitch in
                                WhiteKeyView(
                                    pitch: pitch,
                                    width: whiteKeyWidth,
                                    height: whiteKeyHeight,
                                    handState: handState(for: pitch),
                                    isTouched: touchedPitch == pitch,
                                    onDown: {
                                        touchedPitch = pitch
                                        viewModel.userTappedKey(pitch: pitch)
                                    },
                                    onUp: {
                                        if touchedPitch == pitch { touchedPitch = nil }
                                        viewModel.userReleasedKey(pitch: pitch)
                                    }
                                )
                                .id(pitch)
                            }
                        }
                        
                        // Black keys layer placed at precise geometric offsets
                        ForEach(blackPitches, id: \.self) { pitch in
                            if let xOffset = calculateBlackKeyXOffset(for: pitch) {
                                BlackKeyView(
                                    pitch: pitch,
                                    width: blackKeyWidth,
                                    height: blackKeyHeight,
                                    handState: handState(for: pitch),
                                    isTouched: touchedPitch == pitch,
                                    onDown: {
                                        touchedPitch = pitch
                                        viewModel.userTappedKey(pitch: pitch)
                                    },
                                    onUp: {
                                        if touchedPitch == pitch { touchedPitch = nil }
                                        viewModel.userReleasedKey(pitch: pitch)
                                    }
                                )
                                .offset(x: xOffset, y: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    // Default focus near Middle C (C4 = 60)
                    proxy.scrollTo(60, anchor: .center)
                }
                .frame(height: whiteKeyHeight + 20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LiquidGlassTheme.midnightBackground.opacity(0.95))
                        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(LiquidGlassTheme.specularRimGradient, lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private var whitePitches: [Int] {
        (startPitch...endPitch).filter { !Pitch(midiNumber: $0).isBlackKey }
    }
    
    private var blackPitches: [Int] {
        (startPitch...endPitch).filter { Pitch(midiNumber: $0).isBlackKey }
    }
    
    private var octaveAnchors: [Int] {
        let first = Pitch(midiNumber: startPitch).octave
        let last = Pitch(midiNumber: endPitch).octave
        return Array(first...last)
    }
    
    private var currentVisibleOctave: Int {
        Pitch(midiNumber: 60).octave
    }
    
    private func handState(for pitch: Int) -> Hand? {
        return viewModel.activePitches[pitch]
    }
    
    private func calculateBlackKeyXOffset(for pitch: Int) -> CGFloat? {
        // Find which white key this black key sits to the right of
        let precedingWhite = pitch - 1
        guard let whiteIndex = whitePitches.firstIndex(of: precedingWhite) else {
            return nil
        }
        let whiteSpacing: CGFloat = 1.5
        let x = CGFloat(whiteIndex) * (whiteKeyWidth + whiteSpacing) + (whiteKeyWidth - blackKeyWidth / 2.0)
        return x
    }
}

// MARK: - White Piano Key
private struct WhiteKeyView: View {
    let pitch: Int
    let width: CGFloat
    let height: CGFloat
    let handState: Hand?
    let isTouched: Bool
    let onDown: () -> Void
    let onUp: () -> Void
    
    private var isIlluminated: Bool {
        handState != nil || isTouched
    }
    
    private var glowColor: Color {
        if isTouched { return LiquidGlassTheme.rightHandAmber }
        guard let hand = handState else { return .clear }
        return hand == .right ? LiquidGlassTheme.rightHandAmber : LiquidGlassTheme.leftHandCyan
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Key body with liquid glass sheen
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isIlluminated ?
                        glowColor.opacity(0.35) :
                        Color.white.opacity(0.92)
                )
                .overlay(
                    // Gloss reflection gradient
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isIlluminated ? glowColor : Color.black.opacity(0.15),
                            lineWidth: isIlluminated ? 2.0 : 0.8
                        )
                )
                .glowing(color: glowColor, radius: 14, active: isIlluminated)
            
            // Middle C / Octave pitch label
            if pitch % 12 == 0 {
                Text(Pitch(midiNumber: pitch).fullDisplayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isIlluminated ? .white : Color.black.opacity(0.5))
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onDown() }
                .onEnded { _ in onUp() }
        )
    }
}

// MARK: - Black Piano Key
private struct BlackKeyView: View {
    let pitch: Int
    let width: CGFloat
    let height: CGFloat
    let handState: Hand?
    let isTouched: Bool
    let onDown: () -> Void
    let onUp: () -> Void
    
    private var isIlluminated: Bool {
        handState != nil || isTouched
    }
    
    private var glowColor: Color {
        if isTouched { return LiquidGlassTheme.rightHandAmber }
        guard let hand = handState else { return .clear }
        return hand == .right ? LiquidGlassTheme.rightHandAmber : LiquidGlassTheme.leftHandCyan
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Black keycap with specular 3D bevel
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    isIlluminated ?
                        glowColor.opacity(0.55) :
                        Color(red: 0.12, green: 0.13, blue: 0.16)
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(
                            isIlluminated ? glowColor : Color.white.opacity(0.18),
                            lineWidth: isIlluminated ? 2.0 : 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 4, x: 0, y: 3)
                .glowing(color: glowColor, radius: 14, active: isIlluminated)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onDown() }
                .onEnded { _ in onUp() }
        )
    }
}

// MARK: - Octave Anchor Pill
private struct OctaveAnchorPill: View {
    let octave: Int
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("C\(octave)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(isActive ? LiquidGlassTheme.leftHandCyan : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isActive ? LiquidGlassTheme.leftHandCyan.opacity(0.2) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isActive ? LiquidGlassTheme.leftHandCyan.opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(SpringPressStyle(glowColor: LiquidGlassTheme.leftHandCyan))
    }
}
