//
//  MusicScannerService.swift
//  PianoGlass
//
//  Optical Music Recognition coordinator service handling document capture,
//  remote neural OMR pipeline (oemer + music21 via FastAPI),
//  image enhancement, staff detection, and musical score synthesis.
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum ScanProgressState: Equatable {
    case idle
    case enhancingContrast
    case detectingStaffSystems
    case recognizingNotesAndClefs
    case assemblingScore
    case completed(Score)
    case failed(String)
}

private struct RemoteTranscribeResponse: Codable {
    let id: String?
    let title: String?
    let status: String?
    let engine: String?
    let duration: Double?
    let bpm: Double?
    let musicxml: String
    let midi_base64: String?
    let midi_url: String?
    let musicxml_url: String?
}

public final class MusicScannerService: ObservableObject {
    public static let shared = MusicScannerService()
    
    @Published public private(set) var currentState: ScanProgressState = .idle
    @Published public private(set) var progressFraction: Double = 0.0
    
    private let staffDetector = VisionStaffDetector()
    private let noteEngine = NoteRecognitionEngine()
    
    public init() {}
    
    /// Processes a sheet music CGImage through the OMR pipeline.
    /// When an OMR backend is configured and reachable, uses neural oemer + music21.
    /// Gracefully falls back to on-device Vision detection if offline.
    public func processImage(
        _ cgImage: CGImage,
        scoreTitle: String = "Scanned Sheet Music",
        composer: String = "Unknown Composer"
    ) async -> Result<ScanResult, Error> {
        let startTime = Date()
        
        // 1. Try remote neural OMR backend first if enabled
        let useRemote = UserDefaults.standard.object(forKey: "useRemoteOMR") as? Bool ?? true
        let serverURL = UserDefaults.standard.string(forKey: "omrBackendURL") ?? "http://localhost:8000"
        
        var canAttemptRemote = useRemote && !serverURL.isEmpty
        #if !targetEnvironment(simulator)
        // On physical iOS devices, localhost / 127.0.0.1 is unreachable and hangs on timeout.
        if serverURL.contains("localhost") || serverURL.contains("127.0.0.1") {
            canAttemptRemote = false
        }
        #endif
        
        if canAttemptRemote, let imgData = cgImageToData(cgImage) {
            do {
                await updateState(.enhancingContrast, progress: 0.20)
                await updateState(.detectingStaffSystems, progress: 0.50)
                
                let response = try await sendToRemoteOMR(
                    data: imgData,
                    mimeType: "image/png",
                    fileName: "sheet_music.png",
                    scoreTitle: scoreTitle,
                    backendURLString: serverURL
                )
                
                await updateState(.assemblingScore, progress: 0.85)
                let parser = MusicXMLParser()
                if let parsedScore = parser.parse(xmlString: response.musicxml), !parsedScore.measures.isEmpty {
                    var finalScore = parsedScore
                    if finalScore.title.isEmpty || finalScore.title == "Untitled Score" {
                        finalScore.title = (response.title?.isEmpty == false) ? response.title! : scoreTitle
                    }
                    if let bpm = response.bpm, bpm > 0 {
                        finalScore.defaultBPM = bpm
                    }
                    let duration = Date().timeIntervalSince(startTime)
                    let scanResult = ScanResult(
                        recognizedScore: finalScore,
                        confidence: ScanConfidenceScore(
                            staffDetectionConfidence: 0.99,
                            noteheadConfidence: 0.98,
                            rhythmConsistencyConfidence: 0.97
                        ),
                        staffSystems: [],
                        rawNoteCount: finalScore.allNotes.count,
                        processingDurationSeconds: duration
                    )
                    await updateState(.completed(finalScore), progress: 1.0)
                    return .success(scanResult)
                }
            } catch {
                #if DEBUG
                print("[MusicScannerService] Remote OMR notice: \(error.localizedDescription). Falling back to local engine.")
                #endif
            }
        }
        
        // 2. On-device local OMR fallback pipeline
        await updateState(.enhancingContrast, progress: 0.15)
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        await updateState(.detectingStaffSystems, progress: 0.45)
        let systems = await staffDetector.detectStaves(in: cgImage)
        
        #if DEBUG
        print("[MusicScannerService] Local OMR: detected \(systems.count) staff system(s).")
        for (i, sys) in systems.enumerated() {
            print("  System \(i): treble=\(sys.trebleStaffLines.count) lines, bass=\(sys.bassStaffLines.count) lines, barlines=\(sys.barlineXPositions.count), spacing=\(String(format: "%.1f", sys.staffLineSpacing))px")
        }
        #endif
        
        await updateState(.recognizingNotesAndClefs, progress: 0.75)
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        await updateState(.assemblingScore, progress: 0.90)
        let recognizedScore = noteEngine.recognizeScore(
            from: systems,
            image: cgImage,
            title: scoreTitle,
            composer: composer
        )
        
        #if DEBUG
        print("[MusicScannerService] Local OMR result: \(recognizedScore.measures.count) measures, \(recognizedScore.allNotes.count) notes.")
        #endif
        
        // If recognition produced no notes, surface a real error instead of silently
        // succeeding with an empty score (which would play nothing or fake fallback music).
        if recognizedScore.measures.isEmpty || recognizedScore.allNotes.isEmpty {
            let errorMsg = "On-device OMR could not detect any musical notation in this image. " +
                           "Ensure the image shows clearly printed sheet music with visible staff lines. " +
                           "For best results, use the remote OMR backend (Settings > OMR Backend)."
            #if DEBUG
            print("[MusicScannerService] Local OMR FAILED: no notes detected. Returning error.")
            #endif
            await updateState(.failed(errorMsg), progress: 0.0)
            return .failure(NSError(
                domain: "PianoGlassOMR",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: errorMsg]
            ))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let noteheadConf: Float = recognizedScore.allNotes.count > 10 ? 0.78 : 0.55
        let scanResult = ScanResult(
            recognizedScore: recognizedScore,
            confidence: ScanConfidenceScore(
                staffDetectionConfidence: systems.isEmpty ? 0.0 : 0.82,
                noteheadConfidence: noteheadConf,
                rhythmConsistencyConfidence: 0.70
            ),
            staffSystems: systems.map {
                RecognizedStaffSystem(
                    systemIndex: $0.systemIndex,
                    trebleStaffLines: $0.trebleStaffLines,
                    bassStaffLines: $0.bassStaffLines,
                    staffLineSpacing: $0.staffLineSpacing,
                    barlineXPositions: $0.barlineXPositions,
                    bounds: $0.bounds
                )
            },
            rawNoteCount: recognizedScore.allNotes.count,
            processingDurationSeconds: duration
        )
        
        await updateState(.completed(recognizedScore), progress: 1.0)
        return .success(scanResult)
    }

    
    /// Processes raw document data (PDF or image) by sending to the OMR backend.
    public func processDocumentData(
        _ data: Data,
        mimeType: String,
        fileName: String = "document.pdf",
        scoreTitle: String = "Scanned Sheet Music",
        composer: String = "Unknown Composer"
    ) async -> Result<ScanResult, Error> {
        let startTime = Date()
        let serverURL = UserDefaults.standard.string(forKey: "omrBackendURL") ?? "http://localhost:8000"
        
        do {
            await updateState(.enhancingContrast, progress: 0.20)
            await updateState(.detectingStaffSystems, progress: 0.50)
            
            let response = try await sendToRemoteOMR(
                data: data,
                mimeType: mimeType,
                fileName: fileName,
                scoreTitle: scoreTitle,
                backendURLString: serverURL
            )
            
            await updateState(.assemblingScore, progress: 0.85)
            let parser = MusicXMLParser()
            guard let parsedScore = parser.parse(xmlString: response.musicxml), !parsedScore.measures.isEmpty else {
                throw NSError(domain: "PianoGlassOMR", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse MusicXML from server."])
            }
            
            var finalScore = parsedScore
            if finalScore.title.isEmpty || finalScore.title == "Untitled Score" {
                finalScore.title = (response.title?.isEmpty == false) ? response.title! : scoreTitle
            }
            if let bpm = response.bpm, bpm > 0 {
                finalScore.defaultBPM = bpm
            }
            
            let duration = Date().timeIntervalSince(startTime)
            let scanResult = ScanResult(
                recognizedScore: finalScore,
                confidence: ScanConfidenceScore(
                    staffDetectionConfidence: 0.99,
                    noteheadConfidence: 0.98,
                    rhythmConsistencyConfidence: 0.97
                ),
                staffSystems: [],
                rawNoteCount: finalScore.allNotes.count,
                processingDurationSeconds: duration
            )
            
            await updateState(.completed(finalScore), progress: 1.0)
            return .success(scanResult)
        } catch {
            await updateState(.failed(error.localizedDescription), progress: 0.0)
            return .failure(error)
        }
    }
    
    // MARK: - Networking
    
    private func sendToRemoteOMR(
        data: Data,
        mimeType: String,
        fileName: String,
        scoreTitle: String,
        backendURLString: String
    ) async throws -> RemoteTranscribeResponse {
        guard let baseURL = URL(string: backendURLString) else {
            throw URLError(.badURL)
        }
        let endpoint = baseURL.appendingPathComponent("api/transcribe")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45.0
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add title form field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(scoreTitle)\r\n".data(using: .utf8)!)
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "PianoGlassOMR", code: code, userInfo: [NSLocalizedDescriptionKey: "Server returned error code \(code)"])
        }
        
        let decoded = try JSONDecoder().decode(RemoteTranscribeResponse.self, from: responseData)
        return decoded
    }
    
    private func cgImageToData(_ cgImage: CGImage) -> Data? {
        // Use PNG (lossless) to preserve full pixel fidelity for OMR accuracy.
        // JPEG compression at any quality level degrades fine-grained ink strokes
        // (staff lines, noteheads, accidentals) causing false pitch detections.
        #if canImport(UIKit)
        if let pngData = UIImage(cgImage: cgImage).pngData() {
            return pngData
        }
        // PNG fallback: high-quality JPEG only if PNG fails (memory pressure)
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.98)
        #elseif canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
        #else
        return nil
        #endif
    }
    
    @MainActor
    private func updateState(_ state: ScanProgressState, progress: Double) {
        self.currentState = state
        self.progressFraction = progress
    }
    
    public func reset() {
        self.currentState = .idle
        self.progressFraction = 0.0
    }
}
