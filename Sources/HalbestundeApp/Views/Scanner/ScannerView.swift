//
//  ScannerView.swift
//  HalbestundeApp
//
//  Clean, minimal native iOS sheet music scanner view.
//  Captures or imports sheet music photos and parses them into playable audio
//  using Apple VisionKit document scanning, Vision contour detection, and OMR parsing.
//

import SwiftUI
import PhotosUI
#if os(iOS) && canImport(VisionKit)
import VisionKit
#endif

public struct ScannerView: View {
    @StateObject var viewModel = ScannerViewModel()
    var onScoreAccepted: (Score) -> Void
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraDocumentScanner: Bool = false
    
    public init(onScoreAccepted: @escaping (Score) -> Void) {
        self.onScoreAccepted = onScoreAccepted
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
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text(viewModel.statusMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
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
                                
                                Text("Align printed notation or import an image")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                // Scanner Action Deck
                VStack(spacing: 12) {
                    // Primary Camera / Scan Button
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
                            Text(viewModel.isProcessing ? "Analyzing..." : "Scan Sheet Music")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessing)
                    
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
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data),
                                   let cgImage = uiImage.cgImage {
                                    await MainActor.run {
                                        viewModel.processCapturedImage(cgImage, title: "Imported Sheet Music")
                                    }
                                }
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
            #if os(iOS) && canImport(VisionKit)
            .sheet(isPresented: $showCameraDocumentScanner) {
                DocumentCameraScannerRepresentable(
                    onScan: { image in
                        if let cgImage = image.cgImage {
                            viewModel.processCapturedImage(cgImage, title: "Scanned Sheet Music")
                        }
                    },
                    onCancel: {
                        showCameraDocumentScanner = false
                    }
                )
                .ignoresSafeArea()
            }
            #endif
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
private struct ScanReviewSheet: View {
    let scanResult: ScanResult
    let onAccept: () -> Void
    let onRetake: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
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
    
    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    public class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: (UIImage) -> Void
        let onCancel: () -> Void
        
        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }
        
        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                let image = scan.imageOfPage(at: 0)
                onScan(image)
            }
            controller.dismiss(animated: true)
        }
        
        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
            controller.dismiss(animated: true)
        }
        
        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
            controller.dismiss(animated: true)
        }
    }
}
#endif
