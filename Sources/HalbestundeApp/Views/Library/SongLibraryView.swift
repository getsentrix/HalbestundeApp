//
//  SongLibraryView.swift
//  HalbestundeApp
//
//  Repertoire library and scan history view with liquid glass cards,
//  difficulty filtering, and quick playback launching.
//

import SwiftUI

public struct SongLibraryView: View {
    @StateObject var viewModel = SongLibraryViewModel()
    var onSongSelected: (Score) -> Void
    
    public init(onSongSelected: @escaping (Score) -> Void) {
        self.onSongSelected = onSongSelected
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassTheme.ambientConcertBackdrop
                
                VStack(spacing: 16) {
                    // Glass Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Search title or composer...", text: $viewModel.searchQuery)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                        if !viewModel.searchQuery.isEmpty {
                            Button(action: { viewModel.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 20)
                    
                    // Filter Chips Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(
                                title: "All",
                                isSelected: viewModel.selectedDifficulty == nil && !viewModel.showFavoritesOnly && !viewModel.showScannedOnly,
                                action: {
                                    viewModel.selectedDifficulty = nil
                                    viewModel.showFavoritesOnly = false
                                    viewModel.showScannedOnly = false
                                }
                            )
                            
                            FilterChip(
                                title: "Favorites ❤️",
                                isSelected: viewModel.showFavoritesOnly,
                                action: { viewModel.showFavoritesOnly.toggle() }
                            )
                            
                            FilterChip(
                                title: "My Scans 📄",
                                isSelected: viewModel.showScannedOnly,
                                action: { viewModel.showScannedOnly.toggle() }
                            )
                            
                            ForEach(DifficultyLevel.allCases) { diff in
                                FilterChip(
                                    title: diff.rawValue,
                                    isSelected: viewModel.selectedDifficulty == diff,
                                    action: {
                                        if viewModel.selectedDifficulty == diff {
                                            viewModel.selectedDifficulty = nil
                                        } else {
                                            viewModel.selectedDifficulty = diff
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Song Cards Scroll List
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.filteredSongs) { song in
                                SongRowGlassCard(
                                    song: song,
                                    onPlay: {
                                        if let score = song.previewScore {
                                            onSongSelected(score)
                                        }
                                    },
                                    onToggleFavorite: {
                                        viewModel.toggleFavorite(for: song)
                                    },
                                    onDelete: song.isScanned ? {
                                        viewModel.deleteSong(song)
                                    } : nil
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Repertoire")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(viewModel.filteredSongs.count) pieces")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .onAppear {
                viewModel.loadLibrary()
            }
        }
    }
}

// MARK: - Filter Chip
private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? LiquidGlassTheme.leftHandCyan : Color.white.opacity(0.08))
                        .background(Capsule().fill(.ultraThinMaterial))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? LiquidGlassTheme.leftHandCyan : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
    }
}

// MARK: - Song Row Glass Card
private struct SongRowGlassCard: View {
    let song: SongItem
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    var onDelete: (() -> Void)?
    
    var body: some View {
        GlassCard(cornerRadius: 18) {
            HStack(spacing: 16) {
                // Musical clef badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: song.difficulty.colorHex).opacity(0.2))
                    Text(song.isScanned ? "📷" : "𝄞")
                        .font(.system(size: 26))
                }
                .frame(width: 52, height: 52)
                
                // Song Metadata
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(song.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if song.isScanned {
                            GlassBadge(text: "SCAN", color: LiquidGlassTheme.leftHandCyan)
                        }
                    }
                    
                    Text(song.composer)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(song.difficulty.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: song.difficulty.colorHex))
                        
                        Text("•")
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text(song.keySignatureName)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("•")
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text(song.timeSignatureDisplay)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Action Buttons: Favorite & Play
                HStack(spacing: 12) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(song.isFavorite ? .red : .white.opacity(0.5))
                            .font(.system(size: 18))
                    }
                    
                    Button(action: onPlay) {
                        ZStack {
                            Circle()
                                .fill(LiquidGlassTheme.rightHandAmber.opacity(0.25))
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(LiquidGlassTheme.rightHandAmber)
                                .offset(x: 1)
                        }
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(LiquidGlassTheme.rightHandAmber.opacity(0.6), lineWidth: 1))
                    }
                }
            }
        }
        .contextMenu {
            if let deleteAction = onDelete {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete Scan", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Color Hex Extension
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
