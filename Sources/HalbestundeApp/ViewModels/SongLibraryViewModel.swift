//
//  SongLibraryViewModel.swift
//  HalbestundeApp
//
//  ViewModel for managing repertoire, search filtering, and scan history.
//

import Foundation
import SwiftUI

public final class SongLibraryViewModel: ObservableObject {
    public let repertoireService: RepertoireService
    public let storageService: ScanStorageService
    
    @Published public var allSongs: [SongItem] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedDifficulty: DifficultyLevel?
    @Published public var showFavoritesOnly: Bool = false
    @Published public var showScannedOnly: Bool = false
    
    public init(
        repertoireService: RepertoireService = .shared,
        storageService: ScanStorageService = .shared
    ) {
        self.repertoireService = repertoireService
        self.storageService = storageService
        loadLibrary()
    }
    
    public func loadLibrary() {
        let catalog = repertoireService.loadCatalog()
        let scanned = storageService.loadScannedSongs()
        self.allSongs = scanned + catalog
    }
    
    public var filteredSongs: [SongItem] {
        allSongs.filter { song in
            let matchesQuery = searchQuery.isEmpty ||
                song.title.localizedCaseInsensitiveContains(searchQuery) ||
                song.composer.localizedCaseInsensitiveContains(searchQuery)
            
            let matchesDifficulty = selectedDifficulty == nil || song.difficulty == selectedDifficulty
            let matchesFavorites = !showFavoritesOnly || song.isFavorite
            let matchesScanned = !showScannedOnly || song.isScanned
            
            return matchesQuery && matchesDifficulty && matchesFavorites && matchesScanned
        }
    }
    
    public func toggleFavorite(for song: SongItem) {
        if let idx = allSongs.firstIndex(where: { $0.id == song.id }) {
            allSongs[idx].isFavorite.toggle()
            if allSongs[idx].isScanned {
                storageService.saveScannedSong(allSongs[idx])
            }
        }
    }
    
    public func deleteSong(_ song: SongItem) {
        guard song.isScanned else { return }
        allSongs.removeAll { $0.id == song.id }
        storageService.deleteScannedSong(withId: song.id)
    }
}
