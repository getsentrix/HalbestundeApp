//
//  ScannerViewModel.swift
//  HalbestundeApp
//
//  ViewModel handling the scanning camera interface, photo import, OMR pipeline,
//  and scan review workflow.
//

import Foundation
import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
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
    @Published public var scanConfidence: Float = 0.0
    @Published public var flashEnabled: Bool = false
    @Published public var showPhotoPicker: Bool = false
    @Published public var capturedScore: Score?
    
    public init(
        scannerService: MusicScannerService = .shared,
        storageService: ScanStorageService = .shared
    ) {
        self.scannerService = scannerService
        self.storageService = storageService
    }
    
    /// Processes a captured or imported CGImage
    public func processCapturedImage(_ cgImage: CGImage, title: String = "Scanned Score") {
        isProcessing = true
        currentStep = .processing
        statusMessage = "Analyzing staves & musical notation..."
        
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.scannerService.processImage(cgImage, scoreTitle: title)
            
            await MainActor.run {
                self.isProcessing = false
                switch result {
                case .success(let scanResult):
                    self.scanConfidence = scanResult.confidence.overallConfidence
                    self.capturedScore = scanResult.recognizedScore
                    self.currentStep = .review(scanResult)
                    self.statusMessage = "Recognition Complete (Confidence: \(Int(scanResult.confidence.overallConfidence * 100))%)"
                    
                case .failure(let error):
                    self.statusMessage = "Recognition Failed: \(error.localizedDescription)"
                    self.currentStep = .camera
                }
            }
        }
    }
    
    /// Simulates a high-fidelity sheet scan for simulator testing or demo scans
    public func triggerDemoScan(title: String = "Scanned Etude in C") {
        isProcessing = true
        currentStep = .processing
        statusMessage = "Enhancing image & recognizing notation..."
        
        Task { [weak self] in
            guard let self = self else { return }
            // Synthetic test CGImage
            let width = 800
            let height = 1000
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let demoCGImage = context.makeImage()!
            
            let result = await self.scannerService.processImage(demoCGImage, scoreTitle: title)
            
            await MainActor.run {
                self.isProcessing = false
                switch result {
                case .success(let scanResult):
                    self.scanConfidence = scanResult.confidence.overallConfidence
                    self.capturedScore = scanResult.recognizedScore
                    self.currentStep = .review(scanResult)
                    self.statusMessage = "Recognition Complete (Confidence: \(Int(scanResult.confidence.overallConfidence * 100))%)"
                case .failure(let error):
                    self.statusMessage = "Scan Error: \(error.localizedDescription)"
                    self.currentStep = .camera
                }
            }
        }
    }
    
    public func saveAndOpenScore() -> Score? {
        guard let score = capturedScore else { return nil }
        let songItem = SongItem(
            title: score.title,
            composer: score.composer,
            difficulty: .intermediate,
            isScanned: true,
            isFavorite: false,
            durationSeconds: score.durationSeconds(at: score.defaultBPM),
            estimatedMeasureCount: score.measures.count,
            keySignatureName: score.keySignature.name,
            timeSignatureDisplay: score.timeSignature.displayString,
            previewScore: score
        )
        storageService.saveScannedSong(songItem)
        return score
    }
    
    public func retake() {
        scannerService.reset()
        capturedScore = nil
        currentStep = .camera
        statusMessage = "Align piano sheet music within glass frame"
    }
}
