//
//  RegionManager.swift
//  FinalStorm
//
//  Manages region loading and caching
//

import Foundation

@MainActor
class RegionManager {
    private var loadedRegions: [UUID: Region] = [:]
    
    func loadRegion(_ regionInfo: RegionInfo) async throws -> Region {
        // Check cache
        if let cachedRegion = loadedRegions[regionInfo.id] {
            return cachedRegion
        }
        
        // Create new region
        let region = Region(
            id: regionInfo.id,
            name: regionInfo.name,
            coordinate: regionInfo.coordinate,
            grids: [:],
            currentGrid: GridCoordinate(x: 0, z: 0)
        )
        
        loadedRegions[regionInfo.id] = region
        
        return region
    }
    
    func unloadRegion(_ regionId: UUID) {
        loadedRegions.removeValue(forKey: regionId)
    }
}
