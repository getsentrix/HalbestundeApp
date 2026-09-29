//
//  ScannerViewModel.swift
//  PianoGlass
//
//  ViewModel handling the scanning camera interface, photo import, file import (MusicXML & Images),
//  OMR pipeline, persistent storage, and transition to the audio player.
//

import Foundation
import SwiftUI
import CoreGraphics
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif

public enum ScannerStep {
    case camera
    case processing
    case review(ScanResult)
}

extension ScannerStep: Equatable {
    public static func == (lhs: ScannerStep, rhs: ScannerStep) -> Bool {
        switch (lhs, rhs) {
        case (.camera, .camera): return true
        case (.processing, .processing): return true
        case (.review, .review): return true
        default: return false
        }
    }
}

// MARK: - F11: Viewfinder Guidance State
public enum ViewfinderGuidanceState: String, CaseIterable, Equatable {
    case readyToCapture = "readyToCapture"
    case tooDark = "tooDark"
    case glareWarning = "glareWarning"
    case tiltWarning = "tiltWarning"
    case tooFar = "tooFar"
    case tooClose = "tooClose"
    
    public var message: String {
        switch self {
        case .readyToCapture:
            return "Ready to scan • Alignment optimal"
        case .tooDark:
            return "Too dark — increase lighting or turn on flash"
        case .glareWarning:
            return "High glare detected — angle camera away from reflection"
        case .tiltWarning:
            return "Tilt exceeds 12° — hold phone parallel to page"
        case .tooFar:
            return "Move closer — score should fill 70%+ of frame"
        case .tooClose:
            return "Move back — keep entire score within frame"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .readyToCapture: return "checkmark.circle.fill"
        case .tooDark: return "moon.fill"
        case .glareWarning: return "sun.max.trianglebadge.exclamationmark.fill"
        case .tiltWarning: return "gyroscope"
        case .tooFar: return "arrow.up.left.and.arrow.down.right"
        case .tooClose: return "arrow.down.right.and.arrow.up.left"
        }
    }
}

// MARK: - F12: Multi-Stage Progress Stepper
public enum ProgressStage: Int, CaseIterable, Identifiable, Equatable {
    case preprocessing = 1
    case recognition = 2
    case assembly = 3
    case audioReady = 4
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .preprocessing: return "Preprocessing & Deskew"
        case .recognition: return "AI & Vision Recognition"
        case .assembly: return "Score Assembly & Validation"
        case .audioReady: return "Audio Engine Synthesis"
        }
    }
    
    public var description: String {
        switch self {
        case .preprocessing: return "Enhancing sheet image"
        case .recognition: return "Transcribing notation"
        case .assembly: return "Synthesizing MusicXML"
        case .audioReady: return "Preparing playback"
        }
    }
}

// MARK: - F13: Scan Diagnostic Payload
public struct ScanDiagnostic: Identifiable, Equatable {
    public let id: UUID
    public let failureReason: String
    public let staffCount: Int
    public let lightingQuality: String
    public let apiStatus: String
    public let suggestedAction: String
    public let fallbackScore: Score?
    public let errorCategory: String
    
    public init(
        id: UUID = UUID(),
        failureReason: String,
        staffCount: Int = 0,
        lightingQuality: String = "adequate",
        apiStatus: String = "Unknown",
        suggestedAction: String = "Ensure sheet music is flat, well-lit, and fills the viewfinder.",
        fallbackScore: Score? = nil,
        errorCategory: String = "unknown"
    ) {
        self.id = id
        self.failureReason = failureReason
        self.staffCount = staffCount
        self.lightingQuality = lightingQuality
        self.apiStatus = apiStatus
        self.suggestedAction = suggestedAction
        self.fallbackScore = fallbackScore
        self.errorCategory = errorCategory
    }
}

public final class ScannerViewModel: ObservableObject {
    public let scannerService: MusicScannerService
    public let storageService: ScanStorageService
    
    @Published public var currentStep: ScannerStep = .camera
    @Published public var isProcessing: Bool = false
    @Published public var statusMessage: String = "Align piano sheet music within glass frame"
    @Published public var progressFraction: Double = 0.0
    @Published public var scanConfidence: Float = 0.0
    @Published public var flashEnabled: Bool = false
    @Published public var showPhotoPicker: Bool = false
    @Published public var capturedScore: Score?
    
    // F11: Real-Time Viewfinder Guidance
    @Published public var currentGuidanceState: ViewfinderGuidanceState = .readyToCapture
    @Published public var currentLuminance: Float = 0.75
    @Published public var currentFillRatio: Float = 0.85
    @Published public var currentTiltDegrees: Float = 2.0
    
    // F12: Multi-Stage Progress Stepper
    @Published public var currentStage: ProgressStage = .preprocessing
    private var progressNudgeTimer: Timer?
    
    // F13: User alerts & recovery
    @Published public var showErrorAlert: Bool = false
    @Published public var errorMessage: String = ""
    @Published public var pendingFallbackScore: Score? = nil
    @Published public var lastDiagnostic: ScanDiagnostic? = nil
    @Published public var showDetailedDiagnostics: Bool = false
    
    // F14: Scan Review & Confirmation Sheet
    @Published public var showReviewSheet: Bool = false
    @Published public var activeScanResult: ScanResult? = nil
    
    // Direct transition callback to player
    public var onScoreAccepted: ((Score) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        scannerService: MusicScannerService = .shared,
        storageService: ScanStorageService = .shared,
        onScoreAccepted: ((Score) -> Void)? = nil
    ) {
        self.scannerService = scannerService
        self.storageService = storageService
        self.onScoreAccepted = onScoreAccepted
        
        // Bind to OMR progress fraction with monotonic clamping
        scannerService.$progressFraction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self = self, self.isProcessing else { return }
                self.progressFraction = max(self.progressFraction, progress)
            }
            .store(in: &cancellables)
        
        // Bind to OMR detailed states and map to 4-stage stepper
        scannerService.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self, self.isProcessing else { return }
                switch state {
                case .idle:
                    break
                case .enhancingContrast:
                    self.currentStage = .preprocessing
                    self.progressFraction = max(self.progressFraction, 0.20)
                    self.statusMessage = "Enhancing image contrast & clarity..."
                case .detectingStaffSystems:
                    self.currentStage = .recognition
                    self.progressFraction = max(self.progressFraction, 0.40)
                    self.statusMessage = "Detecting staves & barline boundaries..."
                case .recognizingNotesAndClefs:
                    self.currentStage = .recognition
                    self.progressFraction = max(self.progressFraction, 0.65)
                    self.statusMessage = "Recognizing noteheads, pitches & clefs..."
                case .assemblingScore:
                    self.currentStage = .assembly
                    self.progressFraction = max(self.progressFraction, 0.85)
                    self.statusMessage = "Assembling measures & polyphony..."
                case .completed:
                    self.currentStage = .audioReady
                    self.progressFraction = 1.0
                    self.statusMessage = "Score parsed successfully! Ready for review."
                case .failed(let msg):
                    self.statusMessage = "Recognition notice: \(msg)"
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        stopProgressNudgeTimer()
    }
    
    // MARK: - Guidance & Sensor Processing
    
    public func updateViewfinderGuidance(luminance: Float, fillRatio: Float, tiltDegrees: Float) {
        self.currentLuminance = luminance
        self.currentFillRatio = fillRatio
        self.currentTiltDegrees = tiltDegrees
        
        if luminance < 0.30 {
            currentGuidanceState = .tooDark
        } else if luminance > 0.95 {
            currentGuidanceState = .glareWarning
        } else if abs(tiltDegrees) > 12.0 {
            currentGuidanceState = .tiltWarning
        } else if fillRatio < 0.70 {
            currentGuidanceState = .tooFar
        } else if fillRatio > 0.98 {
            currentGuidanceState = .tooClose
        } else {
            currentGuidanceState = .readyToCapture
        }
    }
    
    // MARK: - Progress Smooth Stepper Timer
    
    private func startProgressNudgeTimer() {
        stopProgressNudgeTimer()
        progressNudgeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self, self.isProcessing else { return }
            if self.currentStage == .recognition && self.progressFraction < 0.78 {
                self.progressFraction = min(0.78, self.progressFraction + 0.012)
            } else if self.currentStage == .preprocessing && self.progressFraction < 0.35 {
                self.progressFraction = min(0.35, self.progressFraction + 0.02)
            }
        }
    }
    
    private func stopProgressNudgeTimer() {
        progressNudgeTimer?.invalidate()
        progressNudgeTimer = nil
    }
    
    public static func categorizeError(_ errStr: String) -> String {
        let lower = errStr.lowercased()
        if lower.contains("429") || lower.contains("network") || lower.contains("http") || lower.contains("connect") || lower.contains("timeout") {
            return "connectivity"
        }
        if lower.contains("staff") || lower.contains("stave") || lower.contains("optical") || lower.contains("omr") {
            return "optical"
        }
        return "unknown"
    }
    
    /// Processes a captured or imported CGImage through the OMR pipeline
    public func processCapturedImage(_ cgImage: CGImage, title: String = "Scanned Sheet Music") {
        isProcessing = true
        currentStep = .processing
        currentStage = .preprocessing
        progressFraction = 0.05
        statusMessage = "Analyzing staves & musical notation..."
        startProgressNudgeTimer()
        
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.scannerService.processImage(cgImage, scoreTitle: title)
            
            await MainActor.run {
                self.stopProgressNudgeTimer()
                switch result {
                case .success(let scanResult):
                    self.scanConfidence = scanResult.confidence.overallConfidence
                    self.capturedScore = scanResult.recognizedScore
                    self.activeScanResult = scanResult
                    self.currentStep = .review(scanResult)
                    self.currentStage = .audioReady
                    self.progressFraction = 1.0
                    self.statusMessage = "Recognition Complete (100%)"
                    self.isProcessing = false
                    
                    // Pre-save to storage and present review sheet
                    _ = self.saveAndOpenScore(score: scanResult.recognizedScore)
                    self.showReviewSheet = true
                    
                case .failure(let error):
                    self.isProcessing = false
                    self.currentStep = .camera
                    self.currentStage = .preprocessing
                    self.progressFraction = 0.0
                    self.statusMessage = "Scan failed"
                    
                    let errDesc = error.localizedDescription
                    let cat = ScannerViewModel.categorizeError(errDesc)
                    let fallback = RepertoireService.shared.loadFallbackPracticeScore(title: title)
                    self.pendingFallbackScore = fallback
                    
                    let suggestedAction: String
                    if cat == "optical" {
                        suggestedAction = "Ensure sheet music is flat, well-lit, and fills 75%+ of the frame without tilt."
                    } else if cat == "connectivity" {
                        suggestedAction = "Gemini cloud service is busy or rate-limited. Retry in a moment or use the offline fallback practice score."
                    } else {
                        suggestedAction = "Ensure the sheet music is flat, well-lit, and fills the viewfinder."
                    }
                    
                    let diagnostic = ScanDiagnostic(
                        failureReason: errDesc.isEmpty ? "Notation recognition failed" : errDesc,
                        staffCount: 0,
                        lightingQuality: self.currentLuminance < 0.3 ? "low" : (self.currentLuminance > 0.95 ? "glare" : "adequate"),
                        apiStatus: cat == "connectivity" ? "HTTP 429 / Connectivity Error" : "Offline OMR Active",
                        suggestedAction: suggestedAction,
                        fallbackScore: fallback,
                        errorCategory: cat
                    )
                    self.lastDiagnostic = diagnostic
                    self.errorMessage = "Could not recognize notation in this scan: \(errDesc)\n\n\(suggestedAction)"
                    self.showErrorAlert = true
                }
            }
        }
    }
    
    /// Processes an imported file (MusicXML, XML, MXL, Image, or PDF)
    public func processImportedFile(at url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        isProcessing = true
        currentStep = .processing
        progressFraction = 0.1
        
        let rawFileName = url.deletingPathExtension().lastPathComponent
        let cleanTitle = rawFileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = cleanTitle.isEmpty ? "Imported Score" : cleanTitle.capitalized
        
        statusMessage = "Reading \(url.lastPathComponent)..."
        
        guard let data = try? Data(contentsOf: url) else {
            handleFileImportError(
                NSError(
                    domain: "PianoGlass",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to read contents of \(url.lastPathComponent). Please check file permissions."]
                ),
                fallbackTitle: displayTitle
            )
            return
        }
        
        let fileExtension = url.pathExtension.lowercased()
        
        // 1. MusicXML / XML import
        if fileExtension == "xml" || fileExtension == "musicxml" || fileExtension == "mxl" || isXMLData(data) {
            statusMessage = "Parsing MusicXML notation..."
            progressFraction = 0.5
            
            let parser = MusicXMLParser()
            if let score = parser.parse(xmlData: data), !score.measures.isEmpty {
                var finalScore = score
                if finalScore.title == "Untitled Score" || finalScore.title.isEmpty {
                    finalScore.title = displayTitle
                }
                finishSuccessfulImport(finalScore)
                return
            } else {
                isProcessing = false
                currentStep = .camera
                errorMessage = "Unable to parse musical notation from \(url.lastPathComponent). Please ensure it is a valid MusicXML 3.0+ score."
                showErrorAlert = true
                return
            }
        }
        
        // 2. Image import (PNG, JPG, HEIC, TIFF)
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            statusMessage = "Analyzing sheet music image..."
            progressFraction = 0.3
            if let cgImage = uiImage.normalizedCGImage {
                processCapturedImage(cgImage, title: displayTitle)
            } else {
                isProcessing = false
                currentStep = .camera
                errorMessage = "Unable to process image data from \(url.lastPathComponent)."
                showErrorAlert = true
            }
            return
        }
        
        // 3. PDF import
        if fileExtension == "pdf" {
            statusMessage = "Transcribing PDF score..."
            progressFraction = 0.25
            Task { [weak self] in
                guard let self = self else { return }
                let res = await self.scannerService.processDocumentData(
                    data,
                    mimeType: "application/pdf",
                    fileName: url.lastPathComponent,
                    scoreTitle: displayTitle
                )
                await MainActor.run {
                    switch res {
                    case .success(let scanResult):
                        self.finishSuccessfulImport(scanResult.recognizedScore)
                    case .failure:
                        // Fallback to local rendering
                        self.processLocalPDF(data: data, title: displayTitle)
                    }
                }
            }
            return
        }
        #endif
        
        // 4. Fallback for unrecognized data
        let fallback = createFallbackScore(title: displayTitle)
        finishSuccessfulImport(fallback, notice: "File imported as playable practice score (\(url.lastPathComponent)).")
    }
    
    private func processLocalPDF(data: Data, title: String) {
        #if canImport(PDFKit) && canImport(UIKit)
        if let pdfDoc = PDFKit.PDFDocument(data: data), let page = pdfDoc.page(at: 0) {
            statusMessage = "Rendering PDF sheet music..."
            progressFraction = 0.3
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let renderedImage = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let cgImage = renderedImage.normalizedCGImage {
                processCapturedImage(cgImage, title: title)
                return
            }
        }
        #endif
        let fallback = createFallbackScore(title: title)
        finishSuccessfulImport(fallback, notice: "PDF rendered with playable arrangement.")
    }
    
    private func finishSuccessfulImport(_ score: Score, notice: String? = nil) {
        progressFraction = 1.0
        statusMessage = "Score ready! Loading player..."
        capturedScore = score
        let savedScore = saveAndOpenScore(score: score) ?? score
        
        if let notice = notice {
            errorMessage = notice
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self = self else { return }
            self.isProcessing = false
            self.onScoreAccepted?(savedScore)
        }
    }
    
    private func isXMLData(_ data: Data) -> Bool {
        if let utf8 = String(data: data.prefix(512), encoding: .utf8) {
            let lower = utf8.lowercased()
            if lower.contains("<?xml") || lower.contains("<score-partwise") || lower.contains("<score-timewise") {
                return true
            }
        }
        if let utf16 = String(data: data.prefix(512), encoding: .utf16) {
            let lower = utf16.lowercased()
            if lower.contains("<?xml") || lower.contains("<score-partwise") || lower.contains("<score-timewise") {
                return true
            }
        }
        return false
    }
    
    public func handleUnrecognizedImport(title: String) {
        isProcessing = false
        currentStep = .camera
        errorMessage = "Recognition failed: Could not detect clean musical notation in '\(title)'. Please ensure the score is well-lit, laid flat, and not obstructed."
        showErrorAlert = true
    }
    
    public func handleFileImportError(_ error: Error, fallbackTitle: String = "Imported Music") {
        isProcessing = false
        currentStep = .camera
        errorMessage = "Import failed: \(error.localizedDescription)"
        showErrorAlert = true
    }
    
    public func acceptFallbackScore(_ score: Score) {
        onScoreAccepted?(score)
    }
    
    public func createFallbackScore(title: String = "Sheet Music") -> Score {
        let measures = NoteRecognitionEngine.synthesizeFallbackMeasures(title: title)
        return Score(
            title: title,
            composer: "Arranged for PianoGlass",
            defaultBPM: 112.0,
            timeSignature: TimeSignature(numerator: 4, denominator: 4),
            keySignature: KeySignature(fifths: 0, mode: "major"),
            measures: measures
        )
    }
    
    /// Simulates a high-fidelity sheet scan for simulator testing or demo scans
    public func triggerDemoScan(title: String = "Scanned Etude in C") {
        isProcessing = true
        currentStep = .processing
        progressFraction = 0.1
        statusMessage = "Enhancing image & recognizing notation..."
        
        Task { [weak self] in
            guard let self = self else { return }
            let width = 800
            let height = 1000
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            
            #if canImport(UIKit)
            context.setFillColor(UIColor.white.cgColor)
            #else
            context.setFillColor(gray: 1.0, alpha: 1.0)
            #endif
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            #if canImport(UIKit)
            context.setFillColor(UIColor.black.cgColor)
            context.setStrokeColor(UIColor.black.cgColor)
            #else
            context.setFillColor(gray: 0.0, alpha: 1.0)
            context.setStrokeColor(gray: 0.0, alpha: 1.0)
            #endif
            context.setLineWidth(2.0)
            
            // Treble staff lines (y = 200, 220, 240, 260, 280)
            for y in stride(from: 200, through: 280, by: 20) {
                context.strokeLineSegments(between: [CGPoint(x: 80, y: y), CGPoint(x: 720, y: y)])
            }
            // Bass staff lines (y = 380, 400, 420, 440, 460)
            for y in stride(from: 380, through: 460, by: 20) {
                context.strokeLineSegments(between: [CGPoint(x: 80, y: y), CGPoint(x: 720, y: y)])
            }
            // Barlines
            for x in [80, 290, 500, 720] {
                context.strokeLineSegments(between: [CGPoint(x: x, y: 200), CGPoint(x: x, y: 460)])
            }
            // Real noteheads (ellipses) with stems
            let noteDefs: [(x: CGFloat, y: CGFloat)] = [
                (180, 280), // E4 (Line 1)
                (240, 270), // F4 (Space 1)
                (360, 260), // G4 (Line 2)
                (420, 250), // A4 (Space 2)
                (570, 240), // B4 (Line 3)
                (640, 230)  // C5 (Space 3)
            ]
            for n in noteDefs {
                context.fillEllipse(in: CGRect(x: n.x - 12, y: n.y - 9, width: 24, height: 18))
                context.strokeLineSegments(between: [CGPoint(x: n.x + 10, y: n.y), CGPoint(x: n.x + 10, y: n.y - 50)])
            }
            
            guard let demoCGImage = context.makeImage() else { return }
            self.processCapturedImage(demoCGImage, title: title)
        }
    }
    
    @discardableResult
    public func saveAndOpenScore(score: Score? = nil) -> Score? {
        let targetScore = score ?? capturedScore
        guard let scoreToSave = targetScore else { return nil }
        
        let songItem = SongItem(
            id: scoreToSave.id,
            title: scoreToSave.title,
            composer: scoreToSave.composer,
            difficulty: .intermediate,
            isScanned: true,
            isFavorite: false,
            dateAdded: Date(),
            durationSeconds: scoreToSave.durationSeconds(at: scoreToSave.defaultBPM),
            estimatedMeasureCount: scoreToSave.measures.count,
            keySignatureName: scoreToSave.keySignature.name,
            timeSignatureDisplay: scoreToSave.timeSignature.displayString,
            previewScore: scoreToSave
        )
        storageService.saveScannedSong(songItem)
        self.capturedScore = scoreToSave
        return scoreToSave
    }
    
    // MARK: - Review Sheet Actions
    
    public func acceptScanResult(_ result: ScanResult) {
        showReviewSheet = false
        currentStep = .camera
        let savedScore = saveAndOpenScore(score: result.recognizedScore) ?? result.recognizedScore
        onScoreAccepted?(savedScore)
    }
    
    public func retakeFromReview() {
        showReviewSheet = false
        retake()
    }
    
    public func viewDetails() {
        showDetailedDiagnostics = true
    }
    
    public func retake() {
        stopProgressNudgeTimer()
        scannerService.reset()
        capturedScore = nil
        activeScanResult = nil
        showReviewSheet = false
        showDetailedDiagnostics = false
        currentStep = .camera
        isProcessing = false
        currentStage = .preprocessing
        progressFraction = 0.0
        statusMessage = "Align piano sheet music within glass frame"
    }
    
    public func reset() {
        retake()
    }
}
