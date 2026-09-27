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
        
        // Deskew image before processing to ensure horizontal staff lines
        let (deskewedImage, _) = VisionStaffDetector.deskewCGImage(cgImage)
        let workingImage = deskewedImage
        
        // 0. Tier 1: Direct On-Device Multimodal AI with Gemini 3.8 Flash / 3.5 Flash-Lite
        let geminiKey = UserDefaults.standard.string(forKey: "geminiAPIKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !geminiKey.isEmpty, let jpegData = cgImageToJPEGData(workingImage, maxDimension: 2048) {
            do {
                await updateState(.enhancingContrast, progress: 0.20)
                await updateState(.detectingStaffSystems, progress: 0.40)
                await updateState(.recognizingNotesAndClefs, progress: 0.70)
                
                if let score = try await transcribeWithGeminiAI(
                    data: jpegData,
                    mimeType: "image/jpeg",
                    apiKey: geminiKey,
                    scoreTitle: scoreTitle
                ) {
                    let duration = Date().timeIntervalSince(startTime)
                    let scanResult = ScanResult(
                        recognizedScore: score,
                        confidence: ScanConfidenceScore(
                            staffDetectionConfidence: 0.99,
                            noteheadConfidence: 0.99,
                            rhythmConsistencyConfidence: 0.98
                        ),
                        staffSystems: [],
                        rawNoteCount: score.allNotes.count,
                        processingDurationSeconds: duration
                    )
                    await updateState(.completed(score), progress: 1.0)
                    return .success(scanResult)
                }
            } catch {
                #if DEBUG
                print("[MusicScannerService] Direct Gemini AI notice: \(error.localizedDescription). Proceeding to remote/local engine.")
                #endif
            }
        }
        
        // 1. Try remote neural OMR backend next if enabled
        let useRemote = UserDefaults.standard.object(forKey: "useRemoteOMR") as? Bool ?? true
        let serverURL = UserDefaults.standard.string(forKey: "omrBackendURL") ?? "http://localhost:8000"
        
        var canAttemptRemote = useRemote && !serverURL.isEmpty
        #if !targetEnvironment(simulator)
        // On physical iOS devices, localhost / 127.0.0.1 is unreachable and hangs on timeout.
        if serverURL.contains("localhost") || serverURL.contains("127.0.0.1") {
            canAttemptRemote = false
        }
        #endif
        
        if canAttemptRemote, let imgData = cgImageToData(workingImage) {
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
        let geminiKey = UserDefaults.standard.string(forKey: "geminiAPIKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Tier 1: Direct On-Device Multimodal AI with Gemini 3.8 Flash / 3.5 Flash-Lite
        if !geminiKey.isEmpty {
            do {
                await updateState(.enhancingContrast, progress: 0.20)
                await updateState(.detectingStaffSystems, progress: 0.40)
                await updateState(.recognizingNotesAndClefs, progress: 0.70)
                
                if let score = try await transcribeWithGeminiAI(
                    data: data,
                    mimeType: mimeType,
                    apiKey: geminiKey,
                    scoreTitle: scoreTitle
                ) {
                    let duration = Date().timeIntervalSince(startTime)
                    let scanResult = ScanResult(
                        recognizedScore: score,
                        confidence: ScanConfidenceScore(
                            staffDetectionConfidence: 0.99,
                            noteheadConfidence: 0.99,
                            rhythmConsistencyConfidence: 0.98
                        ),
                        staffSystems: [],
                        rawNoteCount: score.allNotes.count,
                        processingDurationSeconds: duration
                    )
                    await updateState(.completed(score), progress: 1.0)
                    return .success(scanResult)
                }
            } catch {
                #if DEBUG
                print("[MusicScannerService] Direct Gemini AI notice for document: \(error.localizedDescription). Proceeding to remote OMR.")
                #endif
            }
        }
        
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
    
    private func normalizeBackendURL(_ input: String) -> URL? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "http://" + raw
        }
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        return URL(string: raw)
    }
    
    private func sendToRemoteOMR(
        data: Data,
        mimeType: String,
        fileName: String,
        scoreTitle: String,
        backendURLString: String
    ) async throws -> RemoteTranscribeResponse {
        guard let baseURL = normalizeBackendURL(backendURLString),
              let endpoint = URL(string: "\(baseURL.absoluteString)/api/transcribe") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45.0
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Attach Gemini API key and model headers if configured
        let geminiKey = UserDefaults.standard.string(forKey: "geminiAPIKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let geminiModel = UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-3.8-flash"
        if !geminiKey.isEmpty {
            request.setValue(geminiKey, forHTTPHeaderField: "X-Gemini-API-Key")
            request.setValue(geminiModel, forHTTPHeaderField: "X-Gemini-Model")
        }
        
        var body = Data()
        
        // Add title form field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(scoreTitle)\r\n".data(using: .utf8)!)
        
        // Add gemini_api_key and gemini_model form fields if present
        if !geminiKey.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"gemini_api_key\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(geminiKey)\r\n".data(using: .utf8)!)
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"gemini_model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(geminiModel)\r\n".data(using: .utf8)!)
        }
        
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
    
    private func cgImageToJPEGData(_ cgImage: CGImage, maxDimension: CGFloat = 2048) -> Data? {
        #if canImport(UIKit)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let maxSide = max(width, height)
        let targetImage: CGImage
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newWidth = Int(width * scale)
            let newHeight = Int(height * scale)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            if let ctx = CGContext(data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8, bytesPerRow: newWidth * 4, space: colorSpace, bitmapInfo: bitmapInfo) {
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
                targetImage = ctx.makeImage() ?? cgImage
            } else {
                targetImage = cgImage
            }
        } else {
            targetImage = cgImage
        }
        return UIImage(cgImage: targetImage).jpegData(compressionQuality: 0.90)
        #else
        return nil
        #endif
    }
    
    private func transcribeWithGeminiAI(
        data: Data,
        mimeType: String,
        apiKey: String,
        scoreTitle: String
    ) async throws -> Score? {
        let preferredModel = UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-3.8-flash"
        let fallbackModel = (preferredModel == "gemini-3.8-flash") ? "gemini-3.5-flash-lite" : "gemini-3.8-flash"
        
        let candidateModels = [preferredModel, fallbackModel]
        var lastError: Error?
        
        for model in candidateModels {
            do {
                if let score = try await executeGeminiRequest(
                    data: data,
                    mimeType: mimeType,
                    apiKey: apiKey,
                    scoreTitle: scoreTitle,
                    model: model
                ) {
                    return score
                }
            } catch {
                #if DEBUG
                print("[MusicScannerService] Gemini model '\(model)' returned: \(error.localizedDescription). Trying next candidate if available.")
                #endif
                lastError = error
            }
        }
        
        if let err = lastError {
            throw err
        }
        return nil
    }
    
    private func executeGeminiRequest(
        data: Data,
        mimeType: String,
        apiKey: String,
        scoreTitle: String,
        model: String
    ) async throws -> Score? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        
        let base64String = data.base64EncodedString()
        let prompt = "You are an expert Optical Music Recognition (OMR) system and master musicologist.\n" +
            "Transcribe this piano sheet music score into valid, fully compliant, playable MusicXML 3.1 (<score-partwise>).\n\n" +
            "Strict MusicXML Formatting Requirements:\n" +
            "1. Document Structure: Root must be <score-partwise version=\"3.1\"> with <part-list> defining <score-part id=\"P1\"><part-name>Piano</part-name></score-part></part-list>.\n" +
            "2. Staves & Clefs: Piano grand staff with <staves>2</staves>. In measure 1 attributes, define clef 1 as Treble (<sign>G</sign><line>2</line><staff>1</staff>) and clef 2 as Bass (<sign>F</sign><line>4</line><staff>2</staff>).\n" +
            "3. Timing & Divisions: Explicitly define <divisions>4</divisions> in measure 1 attributes (4 divisions = 1 quarter note). All note durations must be exact integers: whole=16, dotted half=12, half=8, dotted quarter=6, quarter=4, dotted eighth=3, eighth=2, sixteenth=1. Always include <duration> and <type>.\n" +
            "4. Rests: Every silent beat or pause MUST be explicitly encoded with <note><rest/><duration>...</duration><type>...</type><staff>1 or 2</staff></note> with correct duration so rhythm and notes do not bunch up.\n" +
            "5. Exact Pitches: Every note pitch must contain exact uppercase <step> (A-G), <octave> (e.g. C4 is Middle C, treble notes typically octaves 4-5, bass notes octaves 2-3), and <alter> (-1 for flat, 1 for sharp, 0 for natural) whenever accidentals appear or when altered by the key signature.\n" +
            "6. Grand Staff Polyphony: In each measure, specify all staff 1 (treble, voice 1) notes and rests first. Then write <backup><duration>STAFF_1_TOTAL_DIVISIONS</duration></backup> (for example in 4/4 with divisions=4, write <backup><duration>16</duration></backup>), followed by all staff 2 (bass, voice 2) notes and rests. Every note and rest must specify <staff>1</staff> or <staff>2</staff>.\n" +
            "7. Chords: When multiple notes sound together at the exact same beat on the same staff, the first note is standard and every subsequent simultaneous note MUST include <chord/> with identical <duration> and <staff>.\n" +
            "8. Measures & Ties: Number measures sequentially starting at 1 (<measure number=\"1\">). Encode tied notes with <tie type=\"start\"/> / <tie type=\"stop\"/> and <notations><tied type=\"start\"/></notations>.\n" +
            "9. Output Format: Output ONLY raw valid XML starting with <?xml version=\"1.0\" encoding=\"UTF-8\"?> and ending with </score-partwise>. Do NOT include markdown formatting, code fences (```), commentary, or conversational text."
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64String
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.05,
                "maxOutputTokens": 8192
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 35.0
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "PianoGlassOMR", code: code, userInfo: [NSLocalizedDescriptionKey: "Gemini API (\(model)) returned HTTP \(code)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let rawText = firstPart["text"] as? String else {
            throw NSError(domain: "PianoGlassOMR", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not parse Gemini response JSON."])
        }
        
        var cleanXML = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanXML.contains("```xml") {
            if let start = cleanXML.range(of: "```xml") {
                cleanXML = String(cleanXML[start.upperBound...])
            }
        } else if cleanXML.contains("```") {
            if let start = cleanXML.range(of: "```") {
                cleanXML = String(cleanXML[start.upperBound...])
            }
        }
        if let end = cleanXML.range(of: "```") {
            cleanXML = String(cleanXML[..<end.lowerBound])
        }
        cleanXML = cleanXML.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let startTag = cleanXML.range(of: "<?xml") {
            cleanXML = String(cleanXML[startTag.lowerBound...])
        } else if let startTag = cleanXML.range(of: "<score-partwise") {
            cleanXML = String(cleanXML[startTag.lowerBound...])
        }
        if let endTag = cleanXML.range(of: "</score-partwise>", options: .backwards) {
            cleanXML = String(cleanXML[..<endTag.upperBound])
        }
        
        guard cleanXML.contains("<score-partwise") else {
            throw NSError(domain: "PianoGlassOMR", code: 4, userInfo: [NSLocalizedDescriptionKey: "Response did not contain valid MusicXML notation."])
        }
        
        await updateState(.assemblingScore, progress: 0.90)
        let parser = MusicXMLParser()
        if var parsedScore = parser.parse(xmlString: cleanXML), !parsedScore.measures.isEmpty {
            if parsedScore.title.isEmpty || parsedScore.title == "Untitled Score" {
                parsedScore.title = scoreTitle
            }
            return parsedScore
        }
        return nil
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
