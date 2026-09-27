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
    
    // Live import state & progress feedback
    @Published public var isImporting: Bool = false
    @Published public var importStatus: String = ""
    @Published public var importProgress: Double = 0.0
    
    // Retain active scanner during import to prevent ARC deallocation
    private var activeImportScanner: ScannerViewModel?
    
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
    
    /// Imports a MusicXML, Image, or PDF file into the library, saves it, and invokes completion
    public func importFile(at url: URL, completion: @escaping (Score) -> Void) {
        isImporting = true
        importProgress = 0.1
        importStatus = "Reading \(url.lastPathComponent)..."
        
        let scanner = ScannerViewModel(storageService: storageService)
        self.activeImportScanner = scanner // Retained!
        
        scanner.onScoreAccepted = { [weak self] score in
            guard let self = self else { return }
            self.loadLibrary()
            self.importProgress = 1.0
            self.importStatus = "Score ready!"
            self.isImporting = false
            self.activeImportScanner = nil
            completion(score)
        }
        
        // Mirror progress to view model
        scanner.$progressFraction
            .receive(on: DispatchQueue.main)
            .assign(to: &$importProgress)
        scanner.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$importStatus)
            
        scanner.processImportedFile(at: url)
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
