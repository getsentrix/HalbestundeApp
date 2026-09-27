//
//  SongLibraryView.swift
//  HalbestundeApp
//
//  Clean, minimal native iOS sheet music library and scan history view.
//  Uses native Inset Grouped list styling inspired by Feather and iOS system apps.
//

import SwiftUI

public struct SongLibraryView: View {
    @StateObject var viewModel = SongLibraryViewModel()
    @State private var filterMode: Int = 0 // 0: All, 1: Scans, 2: Favorites
    @State private var showScannerSheet: Bool = false
    var onSongSelected: (Score) -> Void
    
    public init(onSongSelected: @escaping (Score) -> Void) {
        self.onSongSelected = onSongSelected
    }
    
    private var displayedSongs: [SongItem] {
        viewModel.filteredSongs.filter { song in
            switch filterMode {
            case 1: return song.isScanned
            case 2: return song.isFavorite
            default: return true
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Filter Segment
                Section {
                    Picker("Filter Library", selection: $filterMode) {
                        Text("All").tag(0)
                        Text("Scans").tag(1)
                        Text("Favorites").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                
                // Songs List Section
                if displayedSongs.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.6))
                            
                            Text("No Scores Found")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(viewModel.searchQuery.isEmpty ? "No pieces in this category yet." : "No results matching \"\(viewModel.searchQuery)\".")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if filterMode == 1 {
                                Button("Scan Sheet Music") {
                                    showScannerSheet = true
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(displayedSongs) { song in
                            SongListRow(
                                song: song,
                                onSelect: {
                                    playSong(song)
                                },
                                onPlay: {
                                    playSong(song)
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if song.isScanned {
                                    Button(role: .destructive) {
                                        viewModel.deleteSong(song)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                
                                Button {
                                    viewModel.toggleFavorite(for: song)
                                } label: {
                                    Label(
                                        song.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: song.isFavorite ? "heart.slash" : "heart.fill"
                                    )
                                }
                                .tint(.pink)
                            }
                        }
                    } header: {
                        Text(headerTitle)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $viewModel.searchQuery, prompt: "Search title or composer")
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        showScannerSheet = true
                    }) {
                        Label("Scan", systemImage: "doc.viewfinder")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(displayedSongs.count) \(displayedSongs.count == 1 ? "piece" : "pieces")")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .sheet(isPresented: $showScannerSheet) {
                ScannerView { scannedScore in
                    showScannerSheet = false
                    viewModel.loadLibrary()
                    onSongSelected(scannedScore)
                }
            }
            .onAppear {
                viewModel.loadLibrary()
            }
        }
    }
    
    private func playSong(_ song: SongItem) {
        let score = song.previewScore ?? RepertoireService.shared.furEliseScore()
        onSongSelected(score)
    }
    
    private var headerTitle: String {
        switch filterMode {
        case 1: return "Scanned Scores"
        case 2: return "Favorite Scores"
        default: return "All Repertoire"
        }
    }
}

// MARK: - Minimal Song Row
private struct SongListRow: View {
    let song: SongItem
    let onSelect: () -> Void
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(song.isScanned ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: song.isScanned ? "doc.text.fill" : "music.quarternote.3")
                    .font(.system(size: 20))
                    .foregroundColor(song.isScanned ? .orange : .accentColor)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if song.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.pink)
                    }
                }
                
                Text(song.composer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(song.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text(song.durationFormatted)
                    Text("•")
                    Text(song.keySignatureName)
                }
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            // Play Button
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .padding(.vertical, 4)
    }
}
