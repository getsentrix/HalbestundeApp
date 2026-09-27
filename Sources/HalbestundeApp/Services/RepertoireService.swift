//
//  RepertoireService.swift
//  HalbestundeApp
//
//  Catalog service for managing score repertoire.
//

import Foundation

public final class RepertoireService {
    public static let shared = RepertoireService()
    
    public init() {}
    
    /// Returns catalog pieces. Default is empty — user populates library through scanning.
    public func loadCatalog() -> [SongItem] {
        return []
    }
}
