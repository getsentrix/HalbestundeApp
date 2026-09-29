//
//  ScannerView.swift
//  PianoGlass
//
//  Clean, minimal native iOS sheet music scanner view.
//  Captures or imports sheet music photos and files (MusicXML, images, PDF)
//  and parses them into playable audio using Apple VisionKit, OMR parsing,
//  and native persistent storage.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS) && canImport(VisionKit)
import VisionKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS) && canImport(CoreMotion)
import CoreMotion
#endif

#if canImport(UIKit)
public extension UIImage {
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cg = self.cgImage {
            return cg
        }
        let pixelSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let normalized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        return normalized.cgImage ?? self.cgImage
    }
}
#endif

public struct ScannerView: View {
    @StateObject var viewModel: ScannerViewModel
    var onScoreAccepted: (Score) -> Void
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraDocumentScanner: Bool = false
    @State private var showFileImporter: Bool = false
    
    #if os(iOS) && canImport(CoreMotion)
    @State private var motionManager: CMMotionManager? = nil
    #endif
    
    public init(onScoreAccepted: @escaping (Score) -> Void) {
        self.onScoreAccepted = onScoreAccepted
        self._viewModel = StateObject(wrappedValue: ScannerViewModel(onScoreAccepted: onScoreAccepted))
    }
    
    // MARK: - Viewfinder Guidance Computed Helpers
    
    private var lightingColor: Color {
        if viewModel.currentLuminance < 0.30 {
            return .orange
        } else if viewModel.currentLuminance > 0.95 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var lightingLabel: String {
        if viewModel.currentLuminance < 0.30 {
            return "Too Dark • Increase Light"
        } else if viewModel.currentLuminance > 0.95 {
            return "High Glare • Angle Camera"
        } else {
            return "Lighting Optimal"
        }
    }
    
    private var lightingIcon: String {
        if viewModel.currentLuminance < 0.30 {
            return "moon.fill"
        } else if viewModel.currentLuminance > 0.95 {
            return "sun.max.trianglebadge.exclamationmark.fill"
        } else {
            return "sun.max.fill"
        }
    }
    
    private var levelIsAligned: Bool {
        abs(viewModel.currentTiltDegrees) <= 12.0
    }
    
    private var tiltLabel: String {
        if levelIsAligned {
            return String(format: "%.1f° Level", abs(viewModel.currentTiltDegrees))
        } else {
            return String(format: "Tilt: %.1f° • Hold Parallel", abs(viewModel.currentTiltDegrees))
        }
    }
    
    private var bubbleOffset: CGSize {
        let maxOffset: CGFloat = 26.0
        let factor: CGFloat = 2.2
        let offsetVal = CGFloat(viewModel.currentTiltDegrees) * factor
        return CGSize(
            width: min(maxOffset, max(-maxOffset, offsetVal)),
            height: min(maxOffset, max(-maxOffset, offsetVal * 0.7))
        )
    }
    
    private var distanceColor: Color {
        if viewModel.currentFillRatio < 0.70 || viewModel.currentFillRatio > 0.98 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var distanceLabel: String {
        if viewModel.currentFillRatio < 0.70 {
            return "Move Closer (Target 70%+)"
        } else if viewModel.currentFillRatio > 0.98 {
            return "Move Back (Score Touches Edge)"
        } else {
            return "Ideal Distance (Score in Frame)"
        }
    }
    
    private var distanceIcon: String {
        if viewModel.currentFillRatio < 0.70 {
            return "arrow.up.left.and.arrow.down.right"
        } else if viewModel.currentFillRatio > 0.98 {
            return "arrow.down.right.and.arrow.up.left"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Viewfinder Frame
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        .overlay(
                            ViewfinderCornerBrackets()
                                .stroke(Color.accentColor, lineWidth: 2.5)
                                .padding(18)
                        )
                    
                    if viewModel.isProcessing {
                        MultiStageProgressStepperView(viewModel: viewModel)
                            .transition(.opacity)
                    } else {
                        // F11: Real-Time Guided Capture Overlay
                        VStack(spacing: 0) {
                            // Top HUD Bar: Lighting pill & Flash
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: lightingIcon)
                                        .font(.caption2)
                                        .foregroundColor(lightingColor)
                                    Text(lightingLabel)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(lightingColor)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(lightingColor.opacity(0.16))
                                .cornerRadius(12)
                                
                                Spacer()
                                
                                Button(action: {
                                    viewModel.flashEnabled.toggle()
                                }) {
                                    Image(systemName: viewModel.flashEnabled ? "bolt.fill" : "bolt.slash")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(viewModel.flashEnabled ? .yellow : .secondary)
                                        .padding(6)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.top, 14)
                            .padding(.horizontal, 16)
                            
                            Spacer()
                            
                            // Center: Level Reticle & Orientation Indicator
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(levelIsAligned ? Color.green.opacity(0.8) : Color.orange.opacity(0.8), lineWidth: 2)
                                        .frame(width: 70, height: 70)
                                    
                                    Rectangle()
                                        .fill(levelIsAligned ? Color.green.opacity(0.4) : Color.secondary.opacity(0.3))
                                        .frame(width: 48, height: 1)
                                    Rectangle()
                                        .fill(levelIsAligned ? Color.green.opacity(0.4) : Color.secondary.opacity(0.3))
                                        .frame(width: 1, height: 48)
                                    
                                    Circle()
                                        .fill(levelIsAligned ? Color.green : Color.orange)
                                        .frame(width: 14, height: 14)
                                        .offset(bubbleOffset)
                                }
                                
                                HStack(spacing: 6) {
                                    Image(systemName: levelIsAligned ? "checkmark.circle.fill" : "gyroscope")
                                        .font(.caption2)
                                        .foregroundColor(levelIsAligned ? .green : .orange)
                                    Text(tiltLabel)
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundColor(levelIsAligned ? .green : .orange)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemBackground).opacity(0.9))
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            // Bottom: Distance & Fill Ratio Indicator and Guidance Message
                            VStack(spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: distanceIcon)
                                        .font(.caption2)
                                        .foregroundColor(distanceColor)
                                    Text(distanceLabel)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(distanceColor)
                                    Spacer()
                                    Text("\(Int(viewModel.currentFillRatio * 100))% Fill")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(distanceColor.opacity(0.14))
                                .cornerRadius(8)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: viewModel.currentGuidanceState.systemIcon)
                                        .font(.caption2)
                                        .foregroundColor(viewModel.currentGuidanceState == .readyToCapture ? .green : .orange)
                                    Text(viewModel.currentGuidanceState.message)
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemBackground).opacity(0.95))
                                .cornerRadius(8)
                            }
                            .padding(.bottom, 12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .frame(maxHeight: 380)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Scanner Action Deck
                VStack(spacing: 12) {
                    // 1. Primary Camera / Scan Button
                    Button(action: {
                        #if os(iOS) && canImport(VisionKit)
                        if VNDocumentCameraViewController.isSupported {
                            showCameraDocumentScanner = true
                        } else {
                            viewModel.triggerDemoScan(title: "Scanned Sheet Music")
                        }
                        #else
                        viewModel.triggerDemoScan(title: "Scanned Sheet Music")
                        #endif
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text(viewModel.isProcessing ? "Processing..." : "Scan Sheet Music")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessing)
                    
                    // 2. Photos Import Button
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                            Text("Import from Photos")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isProcessing)
                    .onChange(of: selectedPhotoItem) { _, item in
                        guard let item = item else { return }
                        viewModel.isProcessing = true
                        viewModel.statusMessage = "Loading photo from library..."
                        viewModel.progressFraction = 0.05
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                #if canImport(UIKit)
                                if let uiImage = UIImage(data: data) {
                                    await MainActor.run {
                                        if let cgImage = uiImage.normalizedCGImage ?? uiImage.cgImage {
                                            viewModel.processCapturedImage(cgImage, title: "Imported Sheet Music")
                                        } else {
                                            viewModel.handleUnrecognizedImport(title: "Imported Sheet Music")
                                        }
                                    }
                                    return
                                }
                                #endif
                            }
                            await MainActor.run {
                                viewModel.handleUnrecognizedImport(title: "Imported Sheet Music")
                            }
                        }
                    }
                    
                    // 3. Document / File Picker (MusicXML, Images, PDF)
                    Button(action: {
                        showFileImporter = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                            Text("Import File (MusicXML / Images)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isProcessing)
                    .fileImporter(
                        isPresented: $showFileImporter,
                        allowedContentTypes: [
                            .item,
                            .content,
                            .data,
                            .image,
                            .pdf,
                            .xml,
                            UTType(filenameExtension: "musicxml") ?? .data,
                            UTType(filenameExtension: "mxl") ?? .data
                        ],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            viewModel.processImportedFile(at: url)
                        case .failure(let error):
                            viewModel.handleFileImportError(error)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        viewModel.flashEnabled.toggle()
                    }) {
                        Image(systemName: viewModel.flashEnabled ? "bolt.fill" : "bolt.slash")
                            .foregroundColor(viewModel.flashEnabled ? .yellow : .secondary)
                    }
                }
            }
            .onAppear {
                viewModel.onScoreAccepted = onScoreAccepted
                if !viewModel.isProcessing && !viewModel.showReviewSheet {
                    viewModel.retake()
                }
                #if os(iOS) && canImport(CoreMotion)
                startMotionUpdates()
                #endif
            }
            .onDisappear {
                #if os(iOS) && canImport(CoreMotion)
                stopMotionUpdates()
                #endif
            }
            #if os(iOS) && canImport(VisionKit)
            .sheet(isPresented: $showCameraDocumentScanner) {
                DocumentCameraScannerRepresentable(
                    onScan: { image in
                        showCameraDocumentScanner = false
                        #if canImport(UIKit)
                        if let cgImage = image.normalizedCGImage ?? image.cgImage {
                            viewModel.processCapturedImage(cgImage, title: "Scanned Sheet Music")
                        } else {
                            viewModel.triggerDemoScan(title: "Scanned Sheet Music")
                        }
                        #else
                        viewModel.triggerDemoScan(title: "Scanned Sheet Music")
                        #endif
                    },
                    onCancel: {
                        showCameraDocumentScanner = false
                    }
                )
                .ignoresSafeArea()
            }
            #endif
            // F14: Scan Review & Confirmation Sheet
            .sheet(isPresented: $viewModel.showReviewSheet) {
                if let result = viewModel.activeScanResult {
                    ScanReviewSheet(
                        scanResult: result,
                        onAccept: {
                            viewModel.acceptScanResult(result)
                        },
                        onRetake: {
                            viewModel.retakeFromReview()
                        }
                    )
                }
            }
            // F13: Detailed Diagnostics Sheet
            .sheet(isPresented: $viewModel.showDetailedDiagnostics) {
                if let diagnostic = viewModel.lastDiagnostic {
                    ScanDiagnosticSheet(
                        diagnostic: diagnostic,
                        onPlayFallback: {
                            if let fallback = diagnostic.fallbackScore {
                                viewModel.acceptFallbackScore(fallback)
                            }
                        },
                        onRetake: {
                            viewModel.retake()
                        }
                    )
                }
            }
            // F13: Diagnostic Failure Dialog
            .alert("Scan & Import Notice", isPresented: $viewModel.showErrorAlert) {
                if let fallback = viewModel.pendingFallbackScore {
                    Button("Play Practice Score") {
                        viewModel.acceptFallbackScore(fallback)
                    }
                }
                Button("Retake Scan") {
                    viewModel.retake()
                }
                Button("View Details") {
                    viewModel.showDetailedDiagnostics = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
    
    #if os(iOS) && canImport(CoreMotion)
    private func startMotionUpdates() {
        let manager = CMMotionManager()
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 0.1
            manager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let motion = motion else { return }
                let pitch = motion.attitude.pitch * 180.0 / .pi
                let roll = motion.attitude.roll * 180.0 / .pi
                let totalTilt = Float(sqrt(pitch * pitch + roll * roll))
                viewModel.updateViewfinderGuidance(
                    luminance: viewModel.currentLuminance,
                    fillRatio: viewModel.currentFillRatio,
                    tiltDegrees: totalTilt
                )
            }
            self.motionManager = manager
        }
    }
    
    private func stopMotionUpdates() {
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
    }
    #endif
}

// MARK: - Viewfinder Corner Reticle Brackets
private struct ViewfinderCornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 28.0
        
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

// MARK: - Native Scan Review Sheet
public struct ScanReviewSheet: View {
    let scanResult: ScanResult
    let onAccept: () -> Void
    let onRetake: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var previewScheduler = AudioScheduler()
    @State private var isPlayingPreview: Bool = false
    
    public init(scanResult: ScanResult, onAccept: @escaping () -> Void, onRetake: @escaping () -> Void) {
        self.scanResult = scanResult
        self.onAccept = onAccept
        self.onRetake = onRetake
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recognition Complete")
                                .font(.headline)
                            Text("Notation successfully parsed into audio")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Recognized Piece") {
                    LabeledContent("Title", value: scanResult.recognizedScore.title)
                    LabeledContent("Composer", value: scanResult.recognizedScore.composer)
                    LabeledContent("Key Signature", value: scanResult.recognizedScore.keySignature.name)
                    LabeledContent("Time Signature", value: scanResult.recognizedScore.timeSignature.displayString)
                }
                
                Section("Recognition Metrics") {
                    LabeledContent("Measures", value: "\(scanResult.recognizedScore.measures.count)")
                    LabeledContent("Notes", value: "\(scanResult.rawNoteCount)")
                    LabeledContent("Confidence", value: "\(Int(scanResult.confidence.overallConfidence * 100))%")
                }
                
                Section("Audio Preview") {
                    HStack(spacing: 14) {
                        Button(action: {
                            if isPlayingPreview {
                                previewScheduler.pause()
                                isPlayingPreview = false
                            } else {
                                previewScheduler.play()
                                isPlayingPreview = true
                            }
                        }) {
                            Image(systemName: isPlayingPreview ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isPlayingPreview ? "Playing score preview..." : "Listen to Transcription")
                                .font(.subheadline.weight(.semibold))
                            Text("\(scanResult.recognizedScore.measures.count) measures • \(Int(scanResult.recognizedScore.defaultBPM)) BPM")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Button(action: {
                        previewScheduler.stop()
                        dismiss()
                        onAccept()
                    }) {
                        HStack {
                            Spacer()
                            Label("Open in Player", systemImage: "play.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.accentColor)
                    .foregroundColor(.white)
                    
                    Button("Scan Another") {
                        previewScheduler.stop()
                        dismiss()
                        onRetake()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Scan Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        previewScheduler.stop()
                        dismiss()
                        onRetake()
                    }
                }
            }
            .onAppear {
                previewScheduler.loadScore(scanResult.recognizedScore)
            }
            .onDisappear {
                previewScheduler.stop()
                isPlayingPreview = false
            }
        }
    }
}

// MARK: - F13: Scan Diagnostic Sheet
public struct ScanDiagnosticSheet: View {
    let diagnostic: ScanDiagnostic
    let onPlayFallback: () -> Void
    let onRetake: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    public init(
        diagnostic: ScanDiagnostic,
        onPlayFallback: @escaping () -> Void,
        onRetake: @escaping () -> Void
    ) {
        self.diagnostic = diagnostic
        self.onPlayFallback = onPlayFallback
        self.onRetake = onRetake
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Diagnostics")
                                    .font(.headline)
                                Text("Analysis details for notation recovery")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(diagnostic.failureReason)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Diagnostic Telemetry") {
                    LabeledContent("Lighting Quality", value: diagnostic.lightingQuality.capitalized)
                    LabeledContent("Staff Systems Found", value: "\(diagnostic.staffCount)")
                    LabeledContent("API / Engine Status", value: diagnostic.apiStatus)
                    LabeledContent("Error Category", value: diagnostic.errorCategory.capitalized)
                }
                
                Section("Suggested Action") {
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.accentColor)
                        Text(diagnostic.suggestedAction)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    if let _ = diagnostic.fallbackScore {
                        Button(action: {
                            dismiss()
                            onPlayFallback()
                        }) {
                            HStack {
                                Spacer()
                                Label("Play Practice Score", systemImage: "play.circle.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.accentColor)
                        .foregroundColor(.white)
                    }
                    
                    Button("Retake Scan") {
                        dismiss()
                        onRetake()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - F12: Multi-Stage Progress Stepper View
public struct MultiStageProgressStepperView: View {
    @ObservedObject var viewModel: ScannerViewModel
    
    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // Stage Items
            VStack(spacing: 8) {
                ForEach(ProgressStage.allCases) { stage in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(circleColor(for: stage))
                                .frame(width: 24, height: 24)
                            
                            if stage.rawValue < viewModel.currentStage.rawValue || (stage == .audioReady && viewModel.progressFraction >= 0.99) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            } else if stage == viewModel.currentStage {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.65)
                                    .tint(.white)
                            } else {
                                Text("\(stage.rawValue)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.title)
                                .font(.system(size: 12, weight: stage == viewModel.currentStage ? .bold : .medium))
                                .foregroundColor(stage.rawValue <= viewModel.currentStage.rawValue ? .primary : .secondary)
                            
                            Text(stage.description)
                                .font(.system(size: 10))
                                .foregroundColor(stage == viewModel.currentStage ? .accentColor : .secondary.opacity(0.8))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground).opacity(0.8))
            .cornerRadius(12)
            
            // Monotonic Progress Bar & Percent
            VStack(spacing: 4) {
                ProgressView(value: max(0.05, viewModel.progressFraction))
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.progressFraction * 100))%")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            
            Button(role: .cancel, action: {
                viewModel.retake()
            }) {
                Text("Cancel Recognition")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
    }
    
    private func circleColor(for stage: ProgressStage) -> Color {
        if stage.rawValue < viewModel.currentStage.rawValue || (stage == .audioReady && viewModel.progressFraction >= 0.99) {
            return .green
        } else if stage == viewModel.currentStage {
            return Color.accentColor
        } else {
            return Color(.systemFill)
        }
    }
}

// MARK: - Apple VisionKit Document Camera Representable
#if os(iOS) && canImport(VisionKit)
public struct DocumentCameraScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (UIImage) -> Void
    var onCancel: () -> Void
    
    public init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onScan = onScan
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }
    
    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.onCancel = onCancel
    }
    
    public class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onScan: (UIImage) -> Void
        var onCancel: () -> Void
        
        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }
        
        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let capturedImage: UIImage? = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            if let image = capturedImage {
                onScan(image)
            } else {
                onCancel()
            }
        }
        
        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }
        
        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}
#endif
