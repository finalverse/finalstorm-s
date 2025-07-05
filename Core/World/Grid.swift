//
//  Core/World/Grid.swift
//  FinalStorm
//
//  Enhanced grid system with proper terrain integration
//

import Foundation
import RealityKit

struct Grid {
    let coordinate: GridCoordinate
    var terrain: TerrainPatch?
    var entities: [Entity] = []
    var localHarmony: Float = 1.0
    var localDissonance: Float = 0.0
    var lastUpdate: Date = Date()
    var isLoaded: Bool = false
    
    init(coordinate: GridCoordinate) {
        self.coordinate = coordinate
        self.isLoaded = false
    }
    
    mutating func updateMetabolism(_ metabolism: GridMetabolism) {
        localHarmony = metabolism.harmony
        localDissonance = metabolism.dissonance
        lastUpdate = Date()
    }
    
    mutating func addEntity(_ entity: Entity) {
        entities.append(entity)
    }
    
    mutating func removeEntity(_ entity: Entity) {
        entities.removeAll { $0.id == entity.id }
    }
    
    func getEntitiesOfType<T: Entity>(_ type: T.Type) -> [T] {
        return entities.compactMap { $0 as? T }
    }
}
