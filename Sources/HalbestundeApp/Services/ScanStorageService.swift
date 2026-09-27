//
//  ScanStorageService.swift
//  HalbestundeApp
//
//  Secure local JSON persistence for user-scanned sheet music scores.
//  Uses Application Support with hardware Data Protection encryption.
//

import Foundation

public final class ScanStorageService {
    public static let shared = ScanStorageService()
    
    private let fileManager = FileManager.default
    
    private var storageDirectoryURL: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        let dir = appSupport.appendingPathComponent("Scores", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
                .protectionKey: FileProtectionType.complete
            ])
        }
        return dir
    }
    
    private var storageFileURL: URL? {
        storageDirectoryURL?.appendingPathComponent("scanned_scores.json")
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
            let songs = try JSONDecoder().decode([SongItem].self, from: data)
            return songs
        } catch {
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
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // Silently fail without exposing sensitive paths
        }
    }
}
