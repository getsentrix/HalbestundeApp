//
//  ContentView.swift
//  HalbestundeApp
//
//  Streamlined native iOS navigation container inspired by Feather (feather.claration.dev).
//  Hosts Library, Document Scanner, Focused Player, and Inset Grouped Settings tabs
//  with an optional native mini-player bar for quick audio control.
//

import SwiftUI

public struct ContentView: View {
    @State private var selectedTab: Int = 0
    @StateObject private var playerViewModel = ScorePlayerViewModel()
    @State private var isMiniPlayerDismissed: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // 1. Library / Scans Tab
                SongLibraryView { selectedScore in
                    playerViewModel.loadScore(selectedScore)
                    playerViewModel.play()
                    isMiniPlayerDismissed = false
                    selectedTab = 2
                }
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }
                .tag(0)
                
                // 2. Document Scanner Tab
                ScannerView { scannedScore in
                    playerViewModel.loadScore(scannedScore)
                    playerViewModel.play()
                    isMiniPlayerDismissed = false
                    selectedTab = 2
                }
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(1)
                
                // 3. Focused Audio Player Tab
                ScorePlayerView(viewModel: playerViewModel)
                    .tabItem {
                        Label("Player", systemImage: "play.circle")
                    }
                    .tag(2)
                
                // 4. Inset Grouped Settings Tab
                SettingsView(audioEngine: playerViewModel.audioEngine)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(3)
            }
            
            // Native Mini Player Bar (docked cleanly above tab bar when playing on other tabs)
            if selectedTab != 2 && !isMiniPlayerDismissed && (playerViewModel.isPlaying || playerViewModel.currentBeat > 0) {
                MiniPlayerBar(
                    viewModel: playerViewModel,
                    onOpenPlayer: {
                        selectedTab = 2
                    },
                    onDismiss: {
                        playerViewModel.pause()
                        isMiniPlayerDismissed = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 62)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Native Apple Music / Feather-Style Mini Player Bar
private struct MiniPlayerBar: View {
    @ObservedObject var viewModel: ScorePlayerViewModel
    let onOpenPlayer: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Tap area for opening player
            Button(action: onOpenPlayer) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentScore.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(viewModel.currentScore.composer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Play / Pause Toggle
            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            
            // Close / Stop button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        )
    }
}
