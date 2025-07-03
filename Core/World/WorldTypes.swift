//
//  Core/World/WorldTypes.swift
//  FinalStorm
//
//  Shared world-related types for all world services
//

import Foundation
import RealityKit

// MARK: - World Event System
struct WorldEvent: Identifiable {
    let id = UUID()
    let type: WorldEventType
    let location: SIMD3<Float>
    let duration: TimeInterval
    let effects: [WorldEffect]
    
    init(type: WorldEventType, location: SIMD3<Float>, duration: TimeInterval, effects: [WorldEffect] = []) {
        self.type = type
        self.location = location
        self.duration = duration
        self.effects = effects
    }
}

enum WorldEventType {
    case celestialBloom
    case silenceRift
    case harmonyWave
    case none
}

struct WorldEffect {
    let type: EffectType
    let magnitude: Float
    
    enum EffectType {
        case spawnEntity(String, Int)
        case ambientParticles(String)
        case terrainTransform(String)
        case weatherOverride(Weather)
    }
}

enum Weather {
    case clear
    case rain
    case storm
    case discordantStorm
}

// MARK: - Metabolism System
struct MetabolismState {
    var harmony: Float = 1.0
    var dissonance: Float = 0.0
    
    var shouldTriggerEvent: Bool {
        harmony > 1.5 || dissonance > 0.7
    }
}

class MetabolismSimulator {
    private var globalState = MetabolismState()
    
    func calculateState() async -> MetabolismState {
        // Simulate metabolism calculations
        return globalState
    }
    
    func applyHarmony(_ harmony: Harmony) async {
        globalState.harmony += harmony.strength * 0.1
        globalState.dissonance = max(0, globalState.dissonance - harmony.strength * 0.05)
    }
}

class ProvidenceEngine {
    func generateEvent(for state: MetabolismState) async -> WorldEvent {
        let eventType: WorldEventType
        if state.harmony > 1.5 {
            eventType = .celestialBloom
        } else if state.dissonance > 0.7 {
            eventType = .silenceRift
        } else {
            eventType = .harmonyWave
        }
        
        return WorldEvent(
            type: eventType,
            location: SIMD3<Float>(
                Float.random(in: -100...100),
                0,
                Float.random(in: -100...100)
            ),
            duration: 3600,
            effects: []
        )
    }
    
    func generateHeightmap(coordinate: GridCoordinate, worldSeed: Int) async -> [[Float]] {
        // Generate procedural heightmap
        let size = 32
        var heightmap: [[Float]] = []
        
        for z in 0..<size {
            var row: [Float] = []
            for x in 0..<size {
                // Simple noise generation
                let height = sin(Float(x + coordinate.x) * 0.1) * cos(Float(z + coordinate.z) * 0.1) * 2.0
                row.append(height)
            }
            heightmap.append(row)
        }
        
        return heightmap
    }
    
    func generateDynamicEntities(for coordinate: GridCoordinate, metabolism: GridMetabolism) async -> [Entity] {
        // Generate entities based on metabolism
        var entities: [Entity] = []
        
        // High harmony spawns blossoms
        if metabolism.harmony > 1.2 {
            let blossom = HarmonyBlossomEntity()
            blossom.position = SIMD3<Float>(
                Float.random(in: -10...10),
                0,
                Float.random(in: -10...10)
            )
            entities.append(blossom)
        }
        
        // High dissonance spawns corruption
        if metabolism.dissonance > 0.5 {
            let corruption = CorruptedEntity()
            corruption.position = SIMD3<Float>(
                Float.random(in: -10...10),
                0,
                Float.random(in: -10...10)
            )
            entities.append(corruption)
        }
        
        return entities
    }
}

// MARK: - Grid System Types
struct GridCoordinate: Hashable {
    let x: Int
    let z: Int
    
    func surrounding(radius: Int) -> [GridCoordinate] {
        var coords: [GridCoordinate] = []
        for dx in -radius...radius {
            for dz in -radius...radius {
                if dx != 0 || dz != 0 {
                    coords.append(GridCoordinate(x: x + dx, z: z + dz))
                }
            }
        }
        return coords
    }
    
    func toWorldPosition() -> SIMD3<Float> {
        return SIMD3<Float>(Float(x) * 256, 0, Float(z) * 256)
    }
}

struct GridMetabolism {
    var harmony: Float
    var dissonance: Float
    
    static let neutral = GridMetabolism(harmony: 1.0, dissonance: 0.0)
}

// MARK: - World Metabolism System
struct WorldMetabolism {
    var globalHarmony: Float = 1.0
    var globalDissonance: Float = 0.0
    var gridStates: [GridCoordinate: GridMetabolism] = [:]
    var lastEventTime: Date = Date()
    
    static let balanced = WorldMetabolism()
    
    var shouldTriggerEvent: Bool {
        // Trigger events based on harmony thresholds or time
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)
        return timeSinceLastEvent > 300 && (globalHarmony > 1.5 || globalDissonance > 0.7)
    }
    
    mutating func updateHarmony(_ delta: Float) {
        globalHarmony = max(0, min(2.0, globalHarmony + delta))
        globalDissonance = max(0, min(1.0, globalDissonance - delta * 0.5))
    }
    
    func determineEventType() -> WorldEventType {
        if globalHarmony > 1.5 {
            return .celestialBloom
        } else if globalDissonance > 0.7 {
            return .silenceRift
        } else {
            return .harmonyWave
        }
    }
}
