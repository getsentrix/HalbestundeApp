//
//  ScanStorageService.swift
//  HalbestundeApp
//
//  Local JSON persistence for user-scanned sheet music.
//

import Foundation

public final class ScanStorageService {
    public static let shared = ScanStorageService()
    
    private let storageKey = "com.halbestunde.scannedSongs"
    private let fileManager = FileManager.default
    
    private var storageFileURL: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("scanned_scores.json")
    }
    
    public init() {}
    
    public func saveScannedSong(_ song: SongItem) {
        var existing = loadScannedSongs()
        if let index = existing.firstIndex(where: { $0.id == song.id }) {
            existing[index] = song
        } else {
            existing.insert(song, at: 0)
        }
        persist(existing)
    }
    
    public func loadScannedSongs() -> [SongItem] {
        guard let url = storageFileURL, fileManager.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let songs = try JSONDecoder().decode([SongItem].self, data: data)
            return songs
        } catch {
            print("[ScanStorageService] Error loading songs: \(error)")
            return []
        }
    }
    
    public func deleteScannedSong(withId id: UUID) {
        var existing = loadScannedSongs()
        existing.removeAll { $0.id == id }
        persist(existing)
    }
    
    private func persist(_ songs: [SongItem]) {
        guard let url = storageFileURL else { return }
        do {
            let data = try JSONEncoder().encode(songs)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[ScanStorageService] Error saving songs: \(error)")
        }
    }
}
