//
//  ScannerView.swift
//  HalbestundeApp
//
//  Camera-based sheet music scanner with liquid glass reticle,
//  laser sweep animation, photo picker, and OMR review workflow.
//

import SwiftUI
import PhotosUI

public struct ScannerView: View {
    @StateObject var viewModel = ScannerViewModel()
    var onScoreAccepted: (Score) -> Void
    
    @State private var scanLaserYOffset: CGFloat = -150.0
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    public init(onScoreAccepted: @escaping (Score) -> Void) {
        self.onScoreAccepted = onScoreAccepted
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassTheme.ambientConcertBackdrop
                
                VStack(spacing: 24) {
                    // Title Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sheet Music Scanner")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Optical Music Recognition Engine")
                                .font(.caption)
                                .foregroundColor(LiquidGlassTheme.leftHandCyan)
                        }
                        Spacer()
                        
                        // Flashlight Toggle
                        GlassIconButton(
                            icon: viewModel.flashEnabled ? "bolt.fill" : "bolt.slash.fill",
                            size: 40,
                            tint: viewModel.flashEnabled ? LiquidGlassTheme.rightHandAmber : .white.opacity(0.8),
                            isActive: viewModel.flashEnabled,
                            action: { viewModel.flashEnabled.toggle() }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Center Camera Viewfinder with Glass Frame & Laser
                    ZStack {
                        // Viewfinder Glass Card Frame
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LiquidGlassTheme.obsidianSurface.opacity(0.75))
                            .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        viewModel.isProcessing ?
                                            LiquidGlassTheme.cyanRimGradient :
                                            LiquidGlassTheme.specularRimGradient,
                                        lineWidth: 1.5
                                    )
                            )
                            .overlay(
                                // Document alignment corner brackets
                                ViewfinderCornerBrackets()
                                    .stroke(LiquidGlassTheme.leftHandCyan, lineWidth: 3)
                                    .padding(16)
                            )
                            .shadow(color: LiquidGlassTheme.leftHandCyan.opacity(0.2), radius: 20)
                        
                        // Simulated/Preview Sheet Music in Viewfinder
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.image")
                                .font(.system(size: 64))
                                .foregroundColor(.white.opacity(0.3))
                            
                            Text(viewModel.statusMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        
                        // Animated Sweeping Laser Bar
                        if viewModel.isProcessing {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            LiquidGlassTheme.leftHandCyan.opacity(0.0),
                                            LiquidGlassTheme.leftHandCyan.opacity(0.9),
                                            LiquidGlassTheme.leftHandCyan.opacity(0.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 6)
                                .glowing(color: LiquidGlassTheme.leftHandCyan, radius: 14)
                                .offset(y: scanLaserYOffset)
                                .onAppear {
                                    withAnimation(
                                        .easeInOut(duration: 1.2)
                                        .repeatForever(autoreverses: true)
                                    ) {
                                        scanLaserYOffset = 150.0
                                    }
                                }
                        }
                    }
                    .frame(height: 380)
                    .padding(.horizontal, 20)
                    
                    // Controls Deck
                    VStack(spacing: 14) {
                        // Capture / Scan Button
                        GlassButton(
                            title: viewModel.isProcessing ? "Analyzing..." : "Scan Sheet Music",
                            icon: "camera.viewfinder",
                            accentColor: LiquidGlassTheme.leftHandCyan,
                            isFullWidth: true,
                            action: {
                                viewModel.triggerDemoScan(title: "Scanned Beethoven Sonata")
                            }
                        )
                        .disabled(viewModel.isProcessing)
                        
                        HStack(spacing: 14) {
                            // Photo Library Picker Button
                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                    Text("Import Photo")
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                        .background(Capsule().fill(.ultraThinMaterial))
                                )
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            .onChange(of: selectedPhotoItem) { _, item in
                                if item != nil {
                                    viewModel.triggerDemoScan(title: "Imported Sheet Score")
                                }
                            }
                            
                            // Sample Repertoire Scan Button
                            Button(action: {
                                viewModel.triggerDemoScan(title: "Scanned Chopin Nocturne")
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note.list")
                                    Text("Sample Scan")
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(LiquidGlassTheme.rightHandAmber)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(LiquidGlassTheme.rightHandAmber.opacity(0.12))
                                        .background(Capsule().fill(.ultraThinMaterial))
                                )
                                .overlay(Capsule().stroke(LiquidGlassTheme.rightHandAmber.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
            }
            .sheet(isPresented: Binding(
                get: {
                    if case .review = viewModel.currentStep { return true }
                    return false
                },
                set: { if !$0 { viewModel.retake() } }
            )) {
                if case .review(let result) = viewModel.currentStep {
                    ScanReviewSheet(
                        scanResult: result,
                        onAccept: {
                            if let savedScore = viewModel.saveAndOpenScore() {
                                onScoreAccepted(savedScore)
                            }
                        },
                        onRetake: {
                            viewModel.retake()
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Viewfinder Corner Brackets
private struct ViewfinderCornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 30.0
        
        // Top-Left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        
        // Top-Right
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        
        // Bottom-Right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        
        // Bottom-Left
        path.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        
        return path
    }
}

// MARK: - Scan Review Sheet
private struct ScanReviewSheet: View {
    let scanResult: ScanResult
    let onAccept: () -> Void
    let onRetake: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassTheme.ambientConcertBackdrop
                
                VStack(spacing: 24) {
                    // Success Banner
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 52))
                            .foregroundColor(LiquidGlassTheme.emeraldGreen)
                            .glowing(color: LiquidGlassTheme.emeraldGreen, radius: 14)
                        
                        Text("Recognition Successful!")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 20)
                    
                    // Metadata Glass Card
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(scanResult.recognizedScore.title)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                            
                            Text("Composer: \(scanResult.recognizedScore.composer)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            
                            Divider().background(Color.white.opacity(0.2))
                            
                            HStack {
                                StatPill(title: "Measures", value: "\(scanResult.recognizedScore.measures.count)")
                                Spacer()
                                StatPill(title: "Notes", value: "\(scanResult.rawNoteCount)")
                                Spacer()
                                StatPill(title: "Confidence", value: "\(Int(scanResult.confidence.overallConfidence * 100))%")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        GlassButton(
                            title: "Open in Practice Player",
                            icon: "play.circle.fill",
                            accentColor: LiquidGlassTheme.emeraldGreen,
                            isFullWidth: true
                        ) {
                            dismiss()
                            onAccept()
                        }
                        
                        Button("Retake Scan") {
                            dismiss()
                            onRetake()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Scan Review")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(LiquidGlassTheme.leftHandCyan)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
