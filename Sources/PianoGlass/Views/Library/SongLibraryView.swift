//
//  SongLibraryView.swift
//  PianoGlass
//
//  Clean, minimal native iOS sheet music library and scan history view.
//  Uses native Inset Grouped list styling inspired by Feather and iOS system apps.
//

import SwiftUI
import UniformTypeIdentifiers

public struct SongLibraryView: View {
    @StateObject var viewModel = SongLibraryViewModel()
    @State private var filterMode: Int = 0 // 0: All, 1: Scans, 2: Favorites
    @State private var showScannerSheet: Bool = false
    @State private var showFileImporter: Bool = false
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
                
                // Live File Importing Banner
                if viewModel.isImporting {
                    Section {
                        VStack(spacing: 10) {
                            ProgressView(value: max(0.05, viewModel.importProgress))
                                .progressViewStyle(.linear)
                                .tint(Color.accentColor)
                            
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.85)
                                Text(viewModel.importStatus)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Songs List Section
                if displayedSongs.isEmpty && !viewModel.isImporting {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.6))
                            
                            Text("No Scores Found")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(viewModel.searchQuery.isEmpty ? "Scan sheet music or import a MusicXML file to add it to your library." : "No results matching \"\(viewModel.searchQuery)\".")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 8) {
                                Button(action: {
                                    showScannerSheet = true
                                }) {
                                    Label("Scan Sheet Music", systemImage: "doc.viewfinder")
                                        .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button(action: {
                                    showFileImporter = true
                                }) {
                                    Label("Import MusicXML or Image", systemImage: "folder.badge.plus")
                                        .fontWeight(.medium)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
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
                    HStack(spacing: 12) {
                        Button(action: {
                            showScannerSheet = true
                        }) {
                            Label("Scan", systemImage: "doc.viewfinder")
                                .font(.subheadline.weight(.semibold))
                        }
                        
                        Button(action: {
                            showFileImporter = true
                        }) {
                            Label("Import", systemImage: "folder.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onSongSelected(scannedScore)
                    }
                }
            }
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
                    viewModel.importFile(at: url) { newScore in
                        onSongSelected(newScore)
                    }
                case .failure:
                    break
                }
            }
            .onAppear {
                viewModel.loadLibrary()
            }
        }
    }
    
    private func playSong(_ song: SongItem) {
        guard let score = song.previewScore else { return }
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
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onPlay()
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
