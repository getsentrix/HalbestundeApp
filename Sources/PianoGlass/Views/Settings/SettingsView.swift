//
//  SettingsView.swift
//  PianoGlass
//
//  Clean, minimal native iOS settings view with inset grouped list styling.
//  Simple controls, zero jargon, and link to GitHub repository.
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var audioEngine: PianoAudioEngine
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("enhanceScanContrast") private var enhanceScanContrast: Bool = true
    @AppStorage("omrBackendURL") private var omrBackendURL: String = "http://localhost:8000"
    @AppStorage("useRemoteOMR") private var useRemoteOMR: Bool = true
    @AppStorage("geminiAPIKey") private var geminiAPIKey: String = ""
    @AppStorage("geminiModel") private var geminiModel: String = "gemini-3.8-flash"
    @State private var isShowingAPIKey: Bool = false
    @State private var isTestingGeminiKey: Bool = false
    @State private var geminiTestStatus: String? = nil
    @State private var isTestingConnection: Bool = false
    @State private var testStatus: String? = nil
    
    public init(audioEngine: PianoAudioEngine = .shared) {
        self.audioEngine = audioEngine
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Audio Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text("\(Int(audioEngine.masterVolume * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Slider(value: $audioEngine.masterVolume, in: 0...1)
                                .tint(.accentColor)
                            
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Audio")
                }
                
                // Scanner Section
                Section {
                    Toggle("Enhance Scan Contrast", isOn: $enhanceScanContrast)
                    Toggle("Use OMR Backend Server", isOn: $useRemoteOMR)
                    if useRemoteOMR {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OMR Backend Server")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("http://192.168.1.100:8000", text: $omrBackendURL)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            
                            Button(action: testBackendConnection) {
                                HStack {
                                    if isTestingConnection {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "network")
                                    }
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingConnection || omrBackendURL.isEmpty)
                            .padding(.top, 2)
                            
                            if let status = testStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(status.contains("Online") ? .green : .orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Scanner & Recognition")
                } footer: {
                    Text("Connects to Python OMR backend (oemer + music21). On physical iPhone, enter your computer's local WiFi IP (e.g. http://192.168.x.x:8000). Falls back to on-device recognition when offline.")
                }
                
                // Neural AI Recognition Section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Google Gemini API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if isShowingAPIKey {
                                TextField("AIzaSy...", text: $geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("AIzaSy...", text: $geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            
                            Button {
                                isShowingAPIKey.toggle()
                            } label: {
                                Image(systemName: isShowingAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        HStack {
                            Button(action: testGeminiKey) {
                                HStack(spacing: 6) {
                                    if isTestingGeminiKey {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text("Verify Key")
                                }
                            }
                            .disabled(isTestingGeminiKey || geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Spacer()
                            
                            Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                                HStack(spacing: 4) {
                                    Text("Get Free Key")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.top, 2)
                        
                        if let status = geminiTestStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(status.contains("Active") ? .green : .red)
                        }
                    }
                    .padding(.vertical, 2)
                    
                    Picker("Model", selection: $geminiModel) {
                        Text("Gemini 3.8 Flash (High Intelligence)").tag("gemini-3.8-flash")
                        Text("Gemini 3.5 Flash-Lite (Fast)").tag("gemini-3.5-flash-lite")
                    }
                } header: {
                    Text("Neural Music Recognition (AI)")
                } footer: {
                    Text("Uses Google Gemini 3.8 Flash or Gemini 3.5 Flash-Lite to transcribe complex polyphonic piano sheet music with exact chords, accidentals, and measures. Free API keys are available at Google AI Studio.")
                }
                
                // Touch & Feedback
                Section {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                } header: {
                    Text("Preferences")
                }
                
                // Source Code & Links Section
                Section {
                    Link(destination: URL(string: "https://github.com/getsentrix/PianoGlass")!) {
                        HStack {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.primary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("GitHub")
                                    .foregroundColor(.secondary)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Link(destination: URL(string: "https://getsentrix.github.io/PianoGlass/")!) {
                        HStack {
                            Label("Website", systemImage: "safari")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Open Source")
                }
                
                // About Section
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PianoGlass")
                                .font(.headline)
                            Text("Version 1.0.0")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    LabeledContent("Compatibility", value: "iOS 17.0+")
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
    
    private func normalizeURL(_ input: String) -> URL? {
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
    
    private func testBackendConnection() {
        guard let baseURL = normalizeURL(omrBackendURL),
              let healthURL = URL(string: "\(baseURL.absoluteString)/api/health") else {
            testStatus = "Invalid server URL"
            return
        }
        isTestingConnection = true
        testStatus = nil
        
        Task {
            do {
                var request = URLRequest(url: healthURL)
                request.timeoutInterval = 5.0
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    await MainActor.run {
                        self.testStatus = "Online: Server connected"
                        self.isTestingConnection = false
                    }
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    await MainActor.run {
                        self.testStatus = "Server error (HTTP \(code))"
                        self.isTestingConnection = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.testStatus = "Unreachable. Ensure server is running on PC."
                    self.isTestingConnection = false
                }
            }
        }
    }
    
    private func testGeminiKey() {
        let key = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            geminiTestStatus = "Key cannot be empty"
            return
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)") else {
            geminiTestStatus = "Invalid URL"
            return
        }
        isTestingGeminiKey = true
        geminiTestStatus = nil
        
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8.0
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse {
                    if httpResp.statusCode == 200 {
                        await MainActor.run {
                            self.geminiTestStatus = "Active: Key verified successfully"
                            self.isTestingGeminiKey = false
                        }
                    } else {
                        let _ = String(data: data, encoding: .utf8)
                        await MainActor.run {
                            if httpResp.statusCode == 400 || httpResp.statusCode == 403 {
                                self.geminiTestStatus = "Invalid API Key (HTTP \(httpResp.statusCode))"
                            } else {
                                self.geminiTestStatus = "Verification failed (HTTP \(httpResp.statusCode))"
                            }
                            self.isTestingGeminiKey = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.geminiTestStatus = "Network error: \(error.localizedDescription)"
                    self.isTestingGeminiKey = false
                }
            }
        }
    }
}
