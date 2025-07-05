//
//  Core/World/WorldTypes.swift
//  FinalStorm
//
//  Consolidated world generation, biomes, weather, and environmental systems
//  This file consolidates all world-related types and mechanics into a single location
//  Includes world generation, biome systems, weather, time cycles, events, and metabolism
//

import Foundation
import RealityKit
import simd

// MARK: - World Generation System

/// Contains the seed value and metadata for procedural world generation
struct WorldSeed {
    let value: UInt64
    let createdAt: Date
    let version: String
    
    init(value: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.value = value
        self.createdAt = Date()
        self.version = "1.0"
    }
    
    /// Generate a pseudo-random float value based on the seed
    func generateRandom() -> Float {
        // Simple pseudo-random based on seed value
        return Float(value % 1000) / 1000.0
    }
    
    /// Generate a random value for a specific coordinate to ensure consistency
    func generateRandom(x: Int, z: Int) -> Float {
        let combined = UInt64(x) ^ (UInt64(z) << 16) ^ value
        return Float(combined % 1000) / 1000.0
    }
}

/// Represents a chunk of the world that can be loaded/unloaded dynamically
struct WorldChunk {
    let coordinates: SIMD2<Int>        // Grid coordinates in world space
    let size: Float                    // Size of chunk in world units
    let biome: BiomeType              // Primary biome for this chunk
    let heightmap: [[Float]]          // Terrain height data
    let features: [WorldFeature]      // Notable features in this chunk
    let harmonyLevel: Float           // Current harmony level
    let lastGenerated: Date           // When chunk was last generated
    
    init(coordinates: SIMD2<Int>, size: Float = 100.0, biome: BiomeType) {
        self.coordinates = coordinates
        self.size = size
        self.biome = biome
        self.heightmap = Self.generateHeightmap(size: Int(size), coordinates: coordinates)
        self.features = []
        self.harmonyLevel = biome.defaultHarmonyLevel
        self.lastGenerated = Date()
    }
    
    /// Generate heightmap data for this chunk using procedural generation
    private static func generateHeightmap(size: Int, coordinates: SIMD2<Int>) -> [[Float]] {
        var heightmap: [[Float]] = []
        
        // Apply world coordinate offset for seamless chunk generation
        let offsetX = Float(coordinates.x * size)
        let offsetZ = Float(coordinates.y * size)
        
        for z in 0..<size {
            var row: [Float] = []
            for x in 0..<size {
                let worldX = Float(x) + offsetX
                let worldZ = Float(z) + offsetZ
                
                // Multi-octave noise for realistic terrain
                let baseHeight = sin(worldX * 0.01) * cos(worldZ * 0.01) * 20.0
                let detailHeight = sin(worldX * 0.1) * cos(worldZ * 0.1) * 5.0
                let microDetail = sin(worldX * 0.3) * cos(worldZ * 0.3) * 1.0
                
                let height = baseHeight + detailHeight + microDetail
                row.append(height)
            }
            heightmap.append(row)
        }
        return heightmap
    }
    
    /// Get the height at a specific local coordinate within the chunk
    func getHeight(at localPosition: SIMD2<Float>) -> Float {
        let x = Int(localPosition.x.clamped(to: 0..<Float(heightmap[0].count)))
        let z = Int(localPosition.y.clamped(to: 0..<Float(heightmap.count)))
        return heightmap[z][x]
    }
}

/// Represents a notable feature or point of interest within a world chunk
struct WorldFeature {
    let id: UUID
    let type: FeatureType
    let position: SIMD3<Float>
    let scale: SIMD3<Float>
    let rotation: simd_quatf
    let metadata: [String: String]
    
    enum FeatureType: String, CaseIterable, Codable {
        case tree = "Tree"
        case rock = "Rock"
        case crystal = "Crystal"
        case ruin = "Ancient Ruin"
        case spring = "Harmony Spring"
        case corruption = "Corruption Node"
        case shrine = "Echo Shrine"
        case portal = "Travel Portal"
        case settlement = "Settlement"
        case landmark = "Landmark"
        case monument = "Monument"
        case bridge = "Bridge"
        case cave = "Cave Entrance"
        case tower = "Watchtower"
        case garden = "Celestial Garden"
        
        var defaultScale: SIMD3<Float> {
            switch self {
            case .tree: return SIMD3<Float>(1.0, 2.0, 1.0)
            case .rock: return SIMD3<Float>(1.5, 1.0, 1.5)
            case .crystal: return SIMD3<Float>(0.8, 3.0, 0.8)
            case .ruin, .shrine, .portal: return SIMD3<Float>(5.0, 5.0, 5.0)
            case .settlement: return SIMD3<Float>(20.0, 8.0, 20.0)
            case .landmark, .monument: return SIMD3<Float>(10.0, 15.0, 10.0)
            case .spring: return SIMD3<Float>(3.0, 1.0, 3.0)
            case .corruption: return SIMD3<Float>(2.0, 4.0, 2.0)
            case .bridge: return SIMD3<Float>(15.0, 3.0, 5.0)
            case .cave: return SIMD3<Float>(4.0, 3.0, 4.0)
            case .tower: return SIMD3<Float>(3.0, 20.0, 3.0)
            case .garden: return SIMD3<Float>(8.0, 2.0, 8.0)
            }
        }
    }
    
    init(type: FeatureType, position: SIMD3<Float>, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.scale = type.defaultScale
        self.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        self.metadata = metadata
    }
}

// MARK: - Biome System

/// Defines the different biome types and their characteristics
enum BiomeType: String, CaseIterable, Codable {
    case grassland = "Grassland"
    case forest = "Forest"
    case desert = "Desert"
    case ocean = "Ocean"
    case mountain = "Mountain"
    case corrupted = "Corrupted"
    case tundra = "Tundra"
    case swamp = "Swamp"
    case volcanic = "Volcanic"
    case ethereal = "Ethereal"
    case arctic = "Arctic"
    case jungle = "Jungle"
    case mesa = "Mesa"
    case crystal = "Crystal Fields"
    
    /// The default harmony level for this biome type
    var defaultHarmonyLevel: Float {
        switch self {
        case .grassland, .forest: return 0.8
        case .desert, .tundra, .arctic: return 0.5
        case .ocean: return 0.9
        case .mountain, .mesa: return 0.6
        case .corrupted: return 0.1
        case .swamp: return 0.4
        case .volcanic: return 0.3
        case .ethereal, .crystal: return 1.2
        case .jungle: return 0.7
        }
    }
    
    /// The primary color associated with this biome
    var primaryColor: CodableColor {
        switch self {
        case .grassland: return CodableColor(red: 0.4, green: 0.8, blue: 0.2, alpha: 1.0)
        case .forest: return CodableColor(red: 0.2, green: 0.6, blue: 0.1, alpha: 1.0)
        case .desert: return CodableColor(red: 0.9, green: 0.8, blue: 0.4, alpha: 1.0)
        case .ocean: return CodableColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0)
        case .mountain: return CodableColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1.0)
        case .corrupted: return CodableColor(red: 0.5, green: 0.1, blue: 0.5, alpha: 1.0)
        case .tundra: return CodableColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
        case .swamp: return CodableColor(red: 0.3, green: 0.5, blue: 0.2, alpha: 1.0)
        case .volcanic: return CodableColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1.0)
        case .ethereal: return CodableColor(red: 0.8, green: 0.8, blue: 1.0, alpha: 1.0)
        case .arctic: return CodableColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1.0)
        case .jungle: return CodableColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1.0)
        case .mesa: return CodableColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1.0)
        case .crystal: return CodableColor(red: 0.7, green: 0.9, blue: 0.9, alpha: 1.0)
        }
    }
    
    /// Features commonly found in this biome
    var commonFeatures: [WorldFeature.FeatureType] {
        switch self {
        case .grassland: return [.tree, .rock, .settlement, .garden]
        case .forest: return [.tree, .spring, .shrine, .cave]
        case .desert: return [.rock, .ruin, .crystal, .tower]
        case .ocean: return [.rock, .portal, .crystal, .settlement]
        case .mountain: return [.rock, .ruin, .crystal, .cave, .tower]
        case .corrupted: return [.corruption, .ruin, .portal]
        case .tundra: return [.rock, .crystal, .shrine, .monument]
        case .swamp: return [.tree, .spring, .corruption, .ruin]
        case .volcanic: return [.rock, .crystal, .portal, .ruin]
        case .ethereal: return [.shrine, .portal, .crystal, .garden]
        case .arctic: return [.crystal, .shrine, .cave, .monument]
        case .jungle: return [.tree, .spring, .ruin, .bridge]
        case .mesa: return [.rock, .cave, .tower, .ruin]
        case .crystal: return [.crystal, .shrine, .portal, .garden]
        }
    }
    
    /// Modify terrain heightmap based on biome characteristics
    func modifyTerrain(_ heightmap: [[Float]]) -> [[Float]] {
        var modified = heightmap
        
        switch self {
        case .ocean:
            // Lower terrain and add wave patterns
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] = min(modified[z][x], 0.5)
                    // Add wave-like undulation
                    let waveOffset = sin(Float(x) * 0.2) * cos(Float(z) * 0.2) * 2.0
                    modified[z][x] += waveOffset
                }
            }
        case .mountain, .mesa:
            // Amplify height differences and add peaks
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] *= 2.0
                    // Add sharp peaks for mountains
                    if self == .mountain {
                        let peakNoise = sin(Float(x) * 0.05) * cos(Float(z) * 0.05) * 15.0
                        modified[z][x] += max(0, peakNoise)
                    }
                }
            }
        case .corrupted:
            // Add jagged, discordant patterns
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    let noise = sin(Float(x) * 0.5) * cos(Float(z) * 0.5) * 0.3
                    let corruptionSpikes = sin(Float(x) * 0.3) * sin(Float(z) * 0.3) * 8.0
                    modified[z][x] += noise + max(0, corruptionSpikes)
                }
            }
        case .volcanic:
            // Add volcanic peaks and valleys
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    let distance = sqrt(Float(x * x + z * z))
                    let peak = max(0, 20.0 - distance * 0.5)
                    modified[z][x] += peak
                    // Add lava flow valleys
                    let valley = sin(Float(x) * 0.1) * 5.0
                    modified[z][x] -= abs(valley)
                }
            }
        case .swamp:
            // Create low, wet terrain with occasional mounds
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] *= 0.3
                    let mound = sin(Float(x) * 0.08) * cos(Float(z) * 0.08) * 3.0
                    modified[z][x] += max(0, mound)
                }
            }
        case .crystal:
            // Add crystalline spire formations
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    let spireNoise = sin(Float(x) * 0.2) * cos(Float(z) * 0.2) * 12.0
                    modified[z][x] += max(0, spireNoise - 8.0)
                }
            }
        default:
            break
        }
        
        return modified
    }
    
    /// Get the temperature modifier for this biome
    var temperatureModifier: Float {
        switch self {
        case .arctic, .tundra: return -0.8
        case .mountain: return -0.4
        case .volcanic: return 0.9
        case .desert: return 0.7
        case .jungle: return 0.5
        case .swamp: return 0.3
        case .ocean: return 0.1
        case .grassland, .forest: return 0.0
        case .corrupted: return -0.2
        case .ethereal, .crystal: return 0.2
        case .mesa: return 0.4
        }
    }
}

// MARK: - Weather System

/// Different types of weather that can occur in the world
enum WeatherType: String, CaseIterable, Codable {
    case clear = "Clear"
    case rain = "Rain"
    case storm = "Storm"
    case discordantStorm = "Discordant Storm"
    case fog = "Fog"
    case snow = "Snow"
    case sandstorm = "Sandstorm"
    case auroras = "Auroras"
    case harmonyShower = "Harmony Shower"
    case voidMist = "Void Mist"
    case blizzard = "Blizzard"
    case heatWave = "Heat Wave"
    case meteor = "Meteor Shower"
    case eclipse = "Solar Eclipse"
    
    /// The range of intensities this weather can have
    var intensityRange: ClosedRange<Float> {
        switch self {
        case .clear: return 0.0...0.0
        case .rain, .fog, .snow: return 0.3...0.8
        case .storm, .sandstorm, .blizzard: return 0.6...1.0
        case .discordantStorm: return 0.8...1.2
        case .auroras, .harmonyShower: return 0.2...0.5
        case .voidMist: return 0.4...0.9
        case .heatWave: return 0.5...0.9
        case .meteor: return 0.1...0.3
        case .eclipse: return 0.0...0.0
        }
    }
    
    /// How this weather affects harmony levels
    var harmonyEffect: Float {
        switch self {
        case .clear, .auroras: return 0.1
        case .rain, .snow: return 0.05
        case .fog, .eclipse: return 0.0
        case .storm: return -0.1
        case .discordantStorm, .voidMist: return -0.3
        case .sandstorm, .blizzard: return -0.15
        case .harmonyShower: return 0.3
        case .heatWave: return -0.05
        case .meteor: return 0.2
        }
    }
    
    /// Visual effects associated with this weather
    var visualEffects: [WeatherEffect] {
        switch self {
        case .clear: return []
        case .rain: return [.particles(.rain), .skyColor(.gray)]
        case .storm: return [.particles(.rain), .particles(.lightning), .skyColor(.darkGray)]
        case .discordantStorm: return [.particles(.corruption), .skyColor(.purple)]
        case .fog: return [.particles(.fog), .visibility(.reduced)]
        case .snow: return [.particles(.snow), .skyColor(.lightGray)]
        case .sandstorm: return [.particles(.sand), .visibility(.poor)]
        case .auroras: return [.particles(.aurora), .skyColor(.ethereal)]
        case .harmonyShower: return [.particles(.harmony), .skyColor(.golden)]
        case .voidMist: return [.particles(.void), .visibility(.minimal)]
        case .blizzard: return [.particles(.snow), .particles(.wind), .visibility(.poor)]
        case .heatWave: return [.skyColor(.red), .particles(.heat)]
        case .meteor: return [.particles(.meteor), .skyColor(.darkGray)]
        case .eclipse: return [.skyColor(.darkGray), .visibility(.reduced)]
        }
    }
    
    /// Check if this weather type is compatible with the given biome
    func isCompatible(with biome: BiomeType) -> Bool {
        switch self {
        case .snow, .blizzard: return [.tundra, .arctic, .mountain].contains(biome)
        case .sandstorm: return [.desert, .mesa].contains(biome)
        case .heatWave: return [.desert, .volcanic, .mesa].contains(biome)
        case .harmonyShower: return [.ethereal, .crystal, .grassland].contains(biome)
        case .discordantStorm, .voidMist: return [.corrupted].contains(biome)
        case .auroras: return [.tundra, .arctic, .ethereal].contains(biome)
        default: return true // Most weather can occur anywhere
        }
    }
}

/// Visual effects that weather can produce
enum WeatherEffect {
    case particles(ParticleType)
    case skyColor(CodableColor)
    case visibility(VisibilityLevel)
    case temperature(Float)
    case lighting(Float)
    
    enum ParticleType {
        case rain, snow, sand, fog, lightning, aurora, harmony, corruption, void
        case wind, heat, meteor
    }
    
    enum VisibilityLevel {
        case clear, reduced, poor, minimal
        
        var distance: Float {
            switch self {
            case .clear: return 100.0
            case .reduced: return 50.0
            case .poor: return 20.0
            case .minimal: return 5.0
            }
        }
    }
}

// MARK: - Time System

/// Different times of day with their own characteristics
enum TimeOfDay: String, CaseIterable, Codable {
    case dawn = "Dawn"
    case morning = "Morning"
    case day = "Day"
    case afternoon = "Afternoon"
    case dusk = "Dusk"
    case night = "Night"
    case lateNight = "Late Night"
    case midnight = "Midnight"
    
    /// Light intensity for this time of day
    var lightLevel: Float {
        switch self {
        case .dawn: return 0.6
        case .morning: return 0.9
        case .day: return 1.0
        case .afternoon: return 0.8
        case .dusk: return 0.7
        case .night: return 0.3
        case .lateNight: return 0.1
        case .midnight: return 0.05
        }
    }
    
    /// Sky color for this time of day
    var skyColor: CodableColor {
        switch self {
        case .dawn: return CodableColor(red: 1.0, green: 0.7, blue: 0.5, alpha: 1.0)
        case .morning: return CodableColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 1.0)
        case .day: return CodableColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0)
        case .afternoon: return CodableColor(red: 0.8, green: 0.8, blue: 0.9, alpha: 1.0)
        case .dusk: return CodableColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0)
        case .night: return CodableColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1.0)
        case .lateNight: return CodableColor(red: 0.05, green: 0.05, blue: 0.2, alpha: 1.0)
        case .midnight: return CodableColor(red: 0.02, green: 0.02, blue: 0.1, alpha: 1.0)
        }
    }
    
    /// How this time affects harmony levels
    var harmonyModifier: Float {
        switch self {
        case .dawn: return 0.1
        case .morning, .day: return 0.0
        case .afternoon: return -0.02
        case .dusk: return 0.05
        case .night: return -0.05
        case .lateNight: return -0.1
        case .midnight: return -0.15
        }
    }
    
    /// Get the next time period in the cycle
    var next: TimeOfDay {
        switch self {
        case .dawn: return .morning
        case .morning: return .day
        case .day: return .afternoon
        case .afternoon: return .dusk
        case .dusk: return .night
        case .night: return .lateNight
        case .lateNight: return .midnight
        case .midnight: return .dawn
        }
    }
}

// MARK: - World Events

/// Represents a dynamic event occurring in the world
struct WorldEvent: Identifiable, Codable {
    let id: UUID
    let type: EventType
    let location: SIMD3<Float>
    let radius: Float
    let duration: TimeInterval
    let intensity: Float
    let startTime: Date
    var isActive: Bool
    let metadata: [String: String]
    
    enum EventType: String, CaseIterable, Codable {
        case harmonyBloom = "Harmony Bloom"
        case corruptionSpread = "Corruption Spread"
        case echoGathering = "Echo Gathering"
        case ancientAwakening = "Ancient Awakening"
        case songResonance = "Song Resonance"
        case weatherShift = "Weather Shift"
        case temporalFlux = "Temporal Flux"
        case interdimensionalRift = "Interdimensional Rift"
        case celestialAlignment = "Celestial Alignment"
        case crystallineConvergence = "Crystalline Convergence"
        case harmonyStorm = "Harmony Storm"
        case silenceVoid = "Silence Void"
        case memoryFragment = "Memory Fragment"
        case songbirdMigration = "Songbird Migration"
        
        /// How this event affects the surrounding area
        var areaEffect: AreaEffect {
            switch self {
            case .harmonyBloom: return AreaEffect(harmonyDelta: 0.5, dissonanceDelta: -0.2, radius: 50.0)
            case .corruptionSpread: return AreaEffect(harmonyDelta: -0.3, dissonanceDelta: 0.4, radius: 30.0)
            case .echoGathering: return AreaEffect(harmonyDelta: 0.2, dissonanceDelta: 0.0, radius: 40.0)
            case .ancientAwakening: return AreaEffect(harmonyDelta: 0.3, dissonanceDelta: 0.1, radius: 60.0)
            case .songResonance: return AreaEffect(harmonyDelta: 0.4, dissonanceDelta: -0.1, radius: 35.0)
            case .weatherShift: return AreaEffect(harmonyDelta: 0.0, dissonanceDelta: 0.0, radius: 100.0)
            case .temporalFlux: return AreaEffect(harmonyDelta: 0.1, dissonanceDelta: 0.2, radius: 25.0)
            case .interdimensionalRift: return AreaEffect(harmonyDelta: -0.1, dissonanceDelta: 0.3, radius: 20.0)
            case .celestialAlignment: return AreaEffect(harmonyDelta: 0.6, dissonanceDelta: -0.3, radius: 80.0)
            case .crystallineConvergence: return AreaEffect(harmonyDelta: 0.3, dissonanceDelta: 0.0, radius: 45.0)
            case .harmonyStorm: return AreaEffect(harmonyDelta: 0.8, dissonanceDelta: -0.5, radius: 70.0)
            case .silenceVoid: return AreaEffect(harmonyDelta: -0.4, dissonanceDelta: 0.6, radius: 30.0)
            case .memoryFragment: return AreaEffect(harmonyDelta: 0.1, dissonanceDelta: 0.1, radius: 15.0)
            case .songbirdMigration: return AreaEffect(harmonyDelta: 0.2, dissonanceDelta: -0.1, radius: 55.0)
            }
        }
    }
    
    struct AreaEffect {
        let harmonyDelta: Float
        let dissonanceDelta: Float
        let radius: Float
    }
    
    /// Time remaining for this event
    var remainingTime: TimeInterval {
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, duration - elapsed)
    }
    
    /// Whether this event has expired
    var isExpired: Bool {
        return remainingTime <= 0
    }
    
    /// Calculate the effect strength at a given distance from the event center
    func effectStrength(at position: SIMD3<Float>) -> Float {
        let distance = simd_length(position - location)
        let normalizedDistance = distance / radius
        
        // Effect falls off quadratically with distance
        let falloff = max(0, 1.0 - normalizedDistance * normalizedDistance)
        return intensity * falloff
    }
    
    init(type: EventType, location: SIMD3<Float>, intensity: Float = 1.0, duration: TimeInterval = 300.0) {
        self.id = UUID()
        self.type = type
        self.location = location
        self.radius = type.areaEffect.radius
        self.duration = duration
        self.intensity = intensity
        self.startTime = Date()
        self.isActive = true
        self.metadata = [:]
    }
}

// MARK: - World Metabolism System

/// Manages the overall health and energy flow of the world
struct WorldMetabolism {
    var globalHarmony: Float = 1.0
    var globalDissonance: Float = 0.0
    var energyFlow: Float = 1.0
    var stabilityIndex: Float = 1.0
    var lastUpdate: Date = Date()
    
    // Balanced state preset
    static let balanced = WorldMetabolism(
        globalHarmony: 1.0,
        globalDissonance: 0.0,
        energyFlow: 1.0,
        stabilityIndex: 1.0
    )
    
    /// Update the world metabolism based on elapsed time
    mutating func update(deltaTime: TimeInterval) {
        let dt = Float(deltaTime)
        
        // Natural harmony restoration over time
        if globalHarmony < 1.0 {
            globalHarmony = min(1.0, globalHarmony + dt * 0.01)
        }
        
        // Natural dissonance decay over time
        if globalDissonance > 0.0 {
            globalDissonance = max(0.0, globalDissonance - dt * 0.02)
        }
        
        // Calculate energy flow based on harmony/dissonance balance
        energyFlow = globalHarmony / (1.0 + globalDissonance)
        
        // Calculate stability based on overall balance
        let imbalance = abs(globalHarmony - 1.0) + globalDissonance
        stabilityIndex = max(0.1, 1.0 - imbalance * 0.5)
        
        lastUpdate = Date()
    }
    
    /// Apply a harmony effect to the world
    mutating func applyHarmonyEffect(_ effect: Float) {
        globalHarmony = max(0.1, min(2.0, globalHarmony + effect))
    }
    
    /// Apply a dissonance effect to the world
    mutating func applyDissonanceEffect(_ effect: Float) {
        globalDissonance = max(0.0, min(2.0, globalDissonance + effect))
    }
    
    /// Apply effects from a world event
    mutating func applyEventEffect(_ event: WorldEvent, at position: SIMD3<Float>) {
        let strength = event.effectStrength(at: position)
        let areaEffect = event.type.areaEffect
        
        applyHarmonyEffect(areaEffect.harmonyDelta * strength)
        applyDissonanceEffect(areaEffect.dissonanceDelta * strength)
    }
    
    /// Check if conditions warrant triggering a new world event
    var shouldTriggerEvent: Bool {
        return globalDissonance > 1.5 || globalHarmony > 1.8 || stabilityIndex < 0.3
    }
    
    /// Get the current health status of the world
    var healthStatus: HealthStatus {
        let balance = globalHarmony - globalDissonance
        switch balance {
        case 1.5...:
            return .flourishing
        case 0.5..<1.5:
            return .healthy
        case -0.5..<0.5:
            return .unstable
        case -1.5..<(-0.5):
            return .corrupted
        default:
            return .critical
        }
    }
    
    enum HealthStatus: String, CaseIterable {
        case flourishing = "Flourishing"
        case healthy = "Healthy"
        case unstable = "Unstable"
        case corrupted = "Corrupted"
        case critical = "Critical"
        
        var color: CodableColor {
            switch self {
            case .flourishing: return .gold
            case .healthy: return .green
            case .unstable: return .yellow
            case .corrupted: return .purple
            case .critical: return .red
            }
        }
        
        var description: String {
            switch self {
            case .flourishing: return "The world thrives with abundant harmony"
            case .healthy: return "The world maintains a stable balance"
            case .unstable: return "The world experiences fluctuating energies"
            case .corrupted: return "Dissonance spreads through the world"
            case .critical: return "The world faces dire imbalance"
            }
        }
    }
}

// MARK: - Grid Coordinate System

/// Represents coordinates in the world grid system
struct GridCoordinate: Hashable, Codable {
    let x: Int
    let z: Int
    
    init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }
    
    /// Convert grid coordinate to world position
    func toWorldPosition(gridSize: Float = 100.0) -> SIMD3<Float> {
        return SIMD3<Float>(Float(x) * gridSize, 0.0, Float(z) * gridSize)
    }
    
    /// Get neighboring grid coordinates
    var neighbors: [GridCoordinate] {
        return [
            GridCoordinate(x: x - 1, z: z),     // West
            GridCoordinate(x: x + 1, z: z),     // East
            GridCoordinate(x: x, z: z - 1),     // North
            GridCoordinate(x: x, z: z + 1),     // South
            GridCoordinate(x: x - 1, z: z - 1), // Northwest
            GridCoordinate(x: x + 1, z: z - 1), // Northeast
            GridCoordinate(x: x - 1, z: z + 1), // Southwest
            GridCoordinate(x: x + 1, z: z + 1)  // Southeast
        ]
    }
    
    /// Calculate distance to another grid coordinate
    func distance(to other: GridCoordinate) -> Float {
        let dx = Float(x - other.x)
        let dz = Float(z - other.z)
        return sqrt(dx * dx + dz * dz)
    }
}

/// Manages the metabolism of individual grid cells
struct GridMetabolism {
    var harmony: Float = 1.0
    var dissonance: Float = 0.0
    var energyDensity: Float = 1.0
    var lastUpdate: Date = Date()
    
    /// Update grid metabolism based on surrounding influences
    mutating func update(deltaTime: TimeInterval, worldMetabolism: WorldMetabolism) {
        let dt = Float(deltaTime)
        
        // Gradually sync with world metabolism
        let harmonyTarget = worldMetabolism.globalHarmony
        let dissonanceTarget = worldMetabolism.globalDissonance
        
        harmony += (harmonyTarget - harmony) * dt * 0.1
        dissonance += (dissonanceTarget - dissonance) * dt * 0.1
        
        // Calculate local energy density
        energyDensity = harmony / (1.0 + dissonance * 0.5)
        
        lastUpdate = Date()
    }
    
    /// Apply local effects from nearby features or events
    mutating func applyLocalEffect(harmonyDelta: Float, dissonanceDelta: Float) {
        harmony = max(0.1, min(2.0, harmony + harmonyDelta))
        dissonance = max(0.0, min(2.0, dissonance + dissonanceDelta))
    }
}

// MARK: - Environmental Audio System

/// Different environmental events that can produce audio
enum EnvironmentalEvent: String, CaseIterable, Codable {
    case thunderStrike = "Thunder Strike"
    case windGust = "Wind Gust"
    case animalCall = "Animal Call"
    case waterDrop = "Water Drop"
    case leafFall = "Leaf Fall"
    case stoneShift = "Stone Shift"
    case magicalResonance = "Magical Resonance"
    case corruptionPulse = "Corruption Pulse"
    case songweaving = "Songweaving"
    case harmonyBoost = "Harmony Boost"
    case silenceWhisper = "Silence Whisper"
    case echoCall = "Echo Call"
    case crystalChime = "Crystal Chime"
    case voidRipple = "Void Ripple"
    case birdSong = "Bird Song"
    case waterFlow = "Water Flow"
    case firecrackle = "Fire Crackle"
    case iceShatter = "Ice Shatter"
    
    /// Default intensity for this environmental event
    var defaultIntensity: Float {
        switch self {
        case .thunderStrike, .corruptionPulse, .voidRipple: return 1.0
        case .windGust, .songweaving, .magicalResonance: return 0.7
        case .animalCall, .harmonyBoost, .echoCall, .birdSong: return 0.6
        case .waterDrop, .leafFall, .crystalChime: return 0.3
        case .stoneShift, .silenceWhisper: return 0.5
        case .waterFlow: return 0.4
        case .firecrackle: return 0.6
        case .iceShatter: return 0.8
        }
    }
    
    /// Distance at which this sound effect falls off
    var falloffDistance: Float {
        switch self {
        case .thunderStrike, .voidRipple: return 100.0
        case .windGust, .corruptionPulse: return 50.0
        case .animalCall, .echoCall, .magicalResonance: return 30.0
        case .songweaving, .harmonyBoost: return 25.0
        case .waterDrop, .leafFall, .crystalChime: return 10.0
        case .stoneShift, .silenceWhisper: return 15.0
        case .birdSong: return 20.0
        case .waterFlow: return 35.0
        case .firecrackle: return 18.0
        case .iceShatter: return 40.0
        }
    }
    
    /// Which biomes this event is most likely to occur in
    var preferredBiomes: [BiomeType] {
        switch self {
        case .thunderStrike: return [.mountain, .ocean, .corrupted]
        case .windGust: return [.mountain, .desert, .tundra]
        case .animalCall, .birdSong: return [.forest, .grassland, .jungle]
        case .waterDrop, .waterFlow: return [.ocean, .swamp, .forest]
        case .leafFall: return [.forest, .jungle]
        case .stoneShift: return [.mountain, .mesa, .desert]
        case .magicalResonance: return [.ethereal, .crystal]
        case .corruptionPulse, .voidRipple: return [.corrupted]
        case .songweaving, .harmonyBoost: return [.ethereal, .grassland]
        case .silenceWhisper: return [.corrupted, .tundra]
        case .echoCall: return [.mountain, .mesa]
        case .crystalChime: return [.crystal, .ethereal]
        case .firecrackle: return [.volcanic, .desert]
        case .iceShatter: return [.arctic, .tundra]
        }
    }
}

// MARK: - Season System

/// Represents different seasons that affect world behavior
enum Season: String, CaseIterable, Codable {
    case spring = "Spring"
    case summer = "Summer"
    case autumn = "Autumn"
    case winter = "Winter"
    
    /// Temperature modifier for this season
    var temperatureModifier: Float {
        switch self {
        case .spring: return 0.1
        case .summer: return 0.4
        case .autumn: return -0.1
        case .winter: return -0.4
        }
    }
    
    /// Harmony modifier for this season
    var harmonyModifier: Float {
        switch self {
        case .spring: return 0.2
        case .summer: return 0.1
        case .autumn: return 0.0
        case .winter: return -0.1
        }
    }
    
    /// Primary color associated with this season
    var primaryColor: CodableColor {
        switch self {
        case .spring: return CodableColor(red: 0.7, green: 1.0, blue: 0.7, alpha: 1.0)
        case .summer: return CodableColor(red: 1.0, green: 1.0, blue: 0.3, alpha: 1.0)
        case .autumn: return CodableColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case .winter: return CodableColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
        }
    }
    
    /// Get the next season in the cycle
    var next: Season {
        switch self {
        case .spring: return .summer
        case .summer: return .autumn
        case .autumn: return .winter
        case .winter: return .spring
        }
    }
}

// MARK: - Utility Extensions

extension Float {
    /// Clamp a float value to a given range
    func clamped(to range: Range<Float>) -> Float {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound - Float.ulpOfOne, self))
    }
    
    /// Clamp a float value to a given closed range
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

extension SIMD3 where Scalar == Float {
    /// Create a SIMD3 with all components set to the same value
    init(repeating value: Float) {
        self.init(value, value, value)
    }
    
    /// Get the horizontal distance (ignoring Y component)
    func horizontalDistance(to other: SIMD3<Float>) -> Float {
        let dx = self.x - other.x
        let dz = self.z - other.z
        return sqrt(dx * dx + dz * dz)
    }
}

// MARK: - Configuration and Constants

/// Global configuration values for the world system
struct WorldConfiguration {
    static let defaultChunkSize: Float = 100.0
    static let maxLoadedChunks: Int = 25
    static let worldSeed: WorldSeed = WorldSeed()
    static let defaultBiome: BiomeType = .grassland
    static let metabolismUpdateInterval: TimeInterval = 1.0
    static let weatherChangeInterval: TimeInterval = 300.0
    static let dayDuration: TimeInterval = 1200.0 // 20 minutes real time = 1 day game time
    
    /// Calculate time of day based on elapsed time
    static func timeOfDay(elapsedSeconds: TimeInterval) -> TimeOfDay {
        let cyclePosition = (elapsedSeconds.truncatingRemainder(dividingBy: dayDuration)) / dayDuration
        let timeIndex = Int(cyclePosition * Double(TimeOfDay.allCases.count))
        return TimeOfDay.allCases[min(timeIndex, TimeOfDay.allCases.count - 1)]
    }
    
    /// Calculate current season based on elapsed days
    static func season(daysPassed: Int) -> Season {
        let seasonIndex = (daysPassed / 90) % Season.allCases.count
        return Season.allCases[seasonIndex]
    }
}
