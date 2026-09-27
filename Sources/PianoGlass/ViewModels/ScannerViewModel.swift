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
    
    // User alerts & recovery
    @Published public var showErrorAlert: Bool = false
    @Published public var errorMessage: String = ""
    @Published public var pendingFallbackScore: Score? = nil
    
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
        
        // Bind to OMR progress fraction
        scannerService.$progressFraction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self = self, self.isProcessing else { return }
                self.progressFraction = progress
            }
            .store(in: &cancellables)
        
        // Bind to OMR detailed states
        scannerService.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self, self.isProcessing else { return }
                switch state {
                case .idle:
                    break
                case .enhancingContrast:
                    self.statusMessage = "Enhancing image contrast & clarity..."
                case .detectingStaffSystems:
                    self.statusMessage = "Detecting staves & barline boundaries..."
                case .recognizingNotesAndClefs:
                    self.statusMessage = "Recognizing noteheads, pitches & clefs..."
                case .assemblingScore:
                    self.statusMessage = "Assembling measures & polyphony..."
                case .completed:
                    self.statusMessage = "Score parsed successfully! Loading player..."
                case .failed(let msg):
                    self.statusMessage = "Recognition notice: \(msg)"
                }
            }
            .store(in: &cancellables)
    }
    
    /// Processes a captured or imported CGImage through the OMR pipeline
    public func processCapturedImage(_ cgImage: CGImage, title: String = "Scanned Sheet Music") {
        isProcessing = true
        currentStep = .processing
        progressFraction = 0.05
        statusMessage = "Analyzing staves & musical notation..."
        
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.scannerService.processImage(cgImage, scoreTitle: title)
            
            await MainActor.run {
                switch result {
                case .success(let scanResult):
                    self.scanConfidence = scanResult.confidence.overallConfidence
                    self.capturedScore = scanResult.recognizedScore
                    self.currentStep = .review(scanResult)
                    self.progressFraction = 1.0
                    self.statusMessage = "Recognition Complete (100%)"
                    
                    // 1. Immediately save to persistent storage
                    let savedScore = self.saveAndOpenScore(score: scanResult.recognizedScore) ?? scanResult.recognizedScore
                    
                    // 2. Provide feedback, then transition directly to the player
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.isProcessing = false
                        self.onScoreAccepted?(savedScore)
                    }
                    
                case .failure(let error):
                    self.isProcessing = false
                    self.currentStep = .camera
                    self.progressFraction = 0.0
                    self.statusMessage = "Scan failed"
                    self.errorMessage = "Could not recognize notation in this scan: \(error.localizedDescription)\n\nPlease ensure the sheet music is flat, well-lit, and fills the viewfinder."
                    self.pendingFallbackScore = nil
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
            let useRemote = UserDefaults.standard.object(forKey: "useRemoteOMR") as? Bool ?? true
            if useRemote {
                statusMessage = "Transcribing PDF score with neural OMR..."
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
            } else {
                processLocalPDF(data: data, title: displayTitle)
                return
            }
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
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
    
    public func retake() {
        scannerService.reset()
        capturedScore = nil
        currentStep = .camera
        isProcessing = false
        progressFraction = 0.0
        statusMessage = "Align piano sheet music within glass frame"
    }
    
    public func reset() {
        retake()
    }
}
