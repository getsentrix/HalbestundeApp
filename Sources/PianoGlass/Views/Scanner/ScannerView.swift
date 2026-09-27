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
    
    public init(onScoreAccepted: @escaping (Score) -> Void) {
        self.onScoreAccepted = onScoreAccepted
        self._viewModel = StateObject(wrappedValue: ScannerViewModel(onScoreAccepted: onScoreAccepted))
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
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
                                .padding(20)
                        )
                    
                    if viewModel.isProcessing {
                        VStack(spacing: 16) {
                            ProgressView(value: max(0.05, viewModel.progressFraction))
                                .progressViewStyle(.linear)
                                .tint(Color.accentColor)
                                .frame(width: 220)
                            
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("\(Int(viewModel.progressFraction * 100))%")
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                                    .foregroundColor(.accentColor)
                            }
                            
                            Text(viewModel.statusMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.6))
                            
                            VStack(spacing: 4) {
                                Text("Sheet Music Viewfinder")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Scan printed notation or import MusicXML & photos")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                }
                .frame(maxHeight: 340)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
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
                if !viewModel.isProcessing {
                    viewModel.retake()
                }
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
            .alert("Scan & Import Notice", isPresented: $viewModel.showErrorAlert) {
                if let fallback = viewModel.pendingFallbackScore {
                    Button("Play Practice Score") {
                        viewModel.acceptFallbackScore(fallback)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
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
                
                Section {
                    Button(action: {
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
                        dismiss()
                        onRetake()
                    }
                }
            }
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
