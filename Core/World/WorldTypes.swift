//
//  Core/World/WorldTypes.swift (ENHANCED)
//  FinalStorm
//
//  Complete world system types with all missing definitions
//

import Foundation
import RealityKit
import simd

// MARK: - Missing Core Types

// Remove the old ServerInfo struct and replace with this consolidated version:

// MARK: - Enhanced Server Information

struct ServerInfo: Codable, Identifiable {
    let id: UUID
    let name: String
    let url: URL
    let address: String  // Keep for backward compatibility
    let port: Int
    let isSecure: Bool
    let region: String
    let capacity: Int
    let currentPlayers: Int
    let serverType: ServerType
    
    enum ServerType: String, Codable, CaseIterable {
        case finalverse = "finalverse"
        case openSim = "opensim"
        case test = "test"
        
        var defaultPort: Int {
            switch self {
            case .finalverse: return 3000
            case .openSim: return 9000
            case .test: return 8080
            }
        }
    }
    
    init(name: String, url: URL, port: Int? = nil, isSecure: Bool = true, region: String = "US-West", serverType: ServerType = .finalverse) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.address = url.host ?? "localhost" // For backward compatibility
        self.port = port ?? serverType.defaultPort
        self.isSecure = isSecure
        self.region = region
        self.capacity = 1000
        self.currentPlayers = 0
        self.serverType = serverType
    }
    
    // MARK: - Predefined Servers
    
    static let finalverseLocal = ServerInfo(
        name: "Finalverse Local",
        url: URL(string: "http://localhost")!,
        port: 3000,
        isSecure: false,
        serverType: .finalverse
    )
    
    static let finalverseProduction = ServerInfo(
        name: "Finalverse Production",
        url: URL(string: "https://finalverse.com")!,
        port: 443,
        isSecure: true,
        serverType: .finalverse
    )
    
    static let openSimLocal = ServerInfo(
        name: "OpenSim Local",
        url: URL(string: "http://localhost")!,
        port: 9000,
        isSecure: false,
        serverType: .openSim
    )
    
    static let testServer = ServerInfo(
        name: "Test Server",
        url: URL(string: "http://test.finalverse.com")!,
        port: 8080,
        isSecure: false,
        serverType: .test
    )
    
    // MARK: - Computed Properties
    
    var fullURL: URL {
        let scheme = isSecure ? "https" : "http"
        return URL(string: "\(scheme)://\(address):\(port)")!
    }
    
    var webSocketURL: URL {
        let scheme = isSecure ? "wss" : "ws"
        return URL(string: "\(scheme)://\(address):\(port)/ws")!
    }
    
    var isLocal: Bool {
        return address == "localhost" || address == "127.0.0.1"
    }
}

struct RegionInfo: Codable, Identifiable {
    let id: UUID
    let name: String
    let coordinate: RegionCoordinate
    let biomeDistribution: [BiomeType: Float]
    let harmonyLevel: Float
    let weatherPattern: WeatherType
    let isActive: Bool
    
    init(name: String, coordinate: RegionCoordinate) {
        self.id = UUID()
        self.name = name
        self.coordinate = coordinate
        self.biomeDistribution = [.grassland: 1.0]
        self.harmonyLevel = 1.0
        self.weatherPattern = .clear
        self.isActive = true
    }
}

struct RegionCoordinate: Hashable, Codable {
    let x: Int
    let z: Int
    
    init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }
    
    func toWorldPosition(regionSize: Float = 1000.0) -> SIMD3<Float> {
        return SIMD3<Float>(Float(x) * regionSize, 0.0, Float(z) * regionSize)
    }
}

// MARK: - Enhanced Grid System

extension GridCoordinate {
    /// Get surrounding coordinates within a radius
    func surrounding(radius: Int) -> [GridCoordinate] {
        var coords: [GridCoordinate] = []
        for dx in -radius...radius {
            for dz in -radius...radius {
                if dx != 0 || dz != 0 { // Exclude center
                    coords.append(GridCoordinate(x: x + dx, z: z + dz))
                }
            }
        }
        return coords
    }
}

// MARK: - Enhanced World Metabolism

// MARK: - Enhanced World Metabolism

/// Manages the overall health and energy flow of the world
struct WorldMetabolism {
    var globalHarmony: Float = 1.0
    var globalDissonance: Float = 0.0
    var energyFlow: Float = 1.0
    var stabilityIndex: Float = 1.0
    var lastUpdate: Date = Date()
    
    // Grid states storage
    private var _gridStates: [GridCoordinate: GridMetabolism] = [:]
    
    // MARK: - Grid States Access
    
    var gridStates: [GridCoordinate: GridMetabolism] {
        get { return _gridStates }
        set { _gridStates = newValue }
    }
    
    mutating func setGridState(_ state: GridMetabolism, for coordinate: GridCoordinate) {
        _gridStates[coordinate] = state
    }
    
    func getGridState(for coordinate: GridCoordinate) -> GridMetabolism {
        return _gridStates[coordinate] ?? .neutral
    }
    
    mutating func updateGridState(for coordinate: GridCoordinate, deltaTime: TimeInterval) {
        var gridState = getGridState(for: coordinate)
        gridState.update(deltaTime: deltaTime, worldMetabolism: self)
        _gridStates[coordinate] = gridState
    }
    
    // MARK: - Balanced State Preset
    
    static let balanced = WorldMetabolism(
        globalHarmony: 1.0,
        globalDissonance: 0.0,
        energyFlow: 1.0,
        stabilityIndex: 1.0
    )
    
    // MARK: - Initialization
    
    init(globalHarmony: Float = 1.0, globalDissonance: Float = 0.0, energyFlow: Float = 1.0, stabilityIndex: Float = 1.0) {
        self.globalHarmony = globalHarmony
        self.globalDissonance = globalDissonance
        self.energyFlow = energyFlow
        self.stabilityIndex = stabilityIndex
        self.lastUpdate = Date()
        self._gridStates = [:]
    }
    
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
        
        // Update all grid states
        for coordinate in _gridStates.keys {
            updateGridState(for: coordinate, deltaTime: deltaTime)
        }
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
    
    mutating func updateHarmony(_ delta: Float) {
        applyHarmonyEffect(delta)
    }
    
    func determineEventType() -> WorldEventType {
        let balance = globalHarmony - globalDissonance
        
        if balance > 1.5 {
            return .celestialBloom
        } else if balance < -1.0 {
            return .silenceRift
        } else if abs(balance - 1.0) < 0.1 {
            return .harmonyWave
        } else {
            return .none
        }
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

enum WorldEventType: String, CaseIterable {
    case celestialBloom = "Celestial Bloom"
    case silenceRift = "Silence Rift"
    case harmonyWave = "Harmony Wave"
    case none = "None"
}

// MARK: - Finalverse Engine Stubs

class ProvidenceEngine {
    func generateHeightmap(coordinate: GridCoordinate, worldSeed: Int) async -> [[Float]] {
        // Generate heightmap using world seed
        let resolution = 128
        var heightmap: [[Float]] = []
        
        for z in 0..<resolution {
            var row: [Float] = []
            for x in 0..<resolution {
                let worldX = Float(coordinate.x * 100 + x)
                let worldZ = Float(coordinate.z * 100 + z)
                let height = sin(worldX * 0.01) * cos(worldZ * 0.01) * 20.0
                row.append(height)
            }
            heightmap.append(row)
        }
        
        return heightmap
    }
    
    func generateDynamicEntities(for coordinate: GridCoordinate, metabolism: GridMetabolism) async -> [Entity] {
        // Generate dynamic entities based on metabolism
        return []
    }
}

class MetabolismSimulator {
    func simulate(worldMetabolism: inout WorldMetabolism, deltaTime: TimeInterval) {
        worldMetabolism.update(deltaTime: deltaTime)
    }
}

// MARK: - Missing Components and Entities

class ObjectEntity: Entity {
    // Finalverse object entity
}

class HarmonyBlossomEntity: Entity {
    // Harmony blossom entity
}

class CorruptedEntity: Entity {
    // Corrupted entity
}

// MARK: - Avatar System Stubs

struct AvatarSystemStub {
    var localAvatar: Avatar?
    
    func performSongweaving(_ type: SongweavingType, target: Entity) {
        // Perform songweaving
    }
}

struct Avatar {
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
}

enum SongweavingType {
    case restoration, purification, harmony, creation
}

// MARK: - Mesh Factory

struct MeshFactory {
    static func createTerrainMesh(from heightmap: [[Float]]) async throws -> MeshResource {
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        let vertexSpacing = gridSize / Float(resolution - 1)
        
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        // Generate vertices and UVs
        for z in 0..<resolution {
            for x in 0..<resolution {
                let worldX = Float(x) * vertexSpacing
                let worldZ = Float(z) * vertexSpacing
                let height = heightmap[z][x]
                
                vertices.append(SIMD3<Float>(worldX, height, worldZ))
                uvs.append(SIMD2<Float>(Float(x) / Float(resolution - 1), Float(z) / Float(resolution - 1)))
                
                // Calculate normal
                let normal = calculateNormal(x: x, z: z, heightmap: heightmap)
                normals.append(normal)
            }
        }
        
        // Generate indices
        for z in 0..<(resolution - 1) {
            for x in 0..<(resolution - 1) {
                let topLeft = UInt32(z * resolution + x)
                let topRight = UInt32(z * resolution + x + 1)
                let bottomLeft = UInt32((z + 1) * resolution + x)
                let bottomRight = UInt32((z + 1) * resolution + x + 1)
                
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [descriptor])
    }
    
    private static func calculateNormal(x: Int, z: Int, heightmap: [[Float]]) -> SIMD3<Float> {
        let resolution = heightmap.count
        
        let left = x > 0 ? heightmap[z][x-1] : heightmap[z][x]
        let right = x < resolution-1 ? heightmap[z][x+1] : heightmap[z][x]
        let up = z > 0 ? heightmap[z-1][x] : heightmap[z][x]
        let down = z < resolution-1 ? heightmap[z+1][x] : heightmap[z][x]
        
        let dx = SIMD3<Float>(2.0, right - left, 0.0)
        let dz = SIMD3<Float>(0.0, down - up, 2.0)
        
        return normalize(cross(dz, dx))
    }
}

// Object data for world entities
struct ObjectData {
    let id: UUID
    let name: String
    let meshURL: URL?
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>
    let hasPhysics: Bool
    let isDynamic: Bool
    let mass: Float
    let isInteractive: Bool
}

// MARK: - Enhanced Grid Metabolism

/// Manages the metabolism of individual grid cells
struct GridMetabolism {
    var harmony: Float = 1.0
    var dissonance: Float = 0.0
    var energyDensity: Float = 1.0
    var lastUpdate: Date = Date()
    
    // MARK: - Predefined States
    
    static let neutral = GridMetabolism(
        harmony: 1.0,
        dissonance: 0.0,
        energyDensity: 1.0
    )
    
    static let harmonious = GridMetabolism(
        harmony: 1.5,
        dissonance: 0.0,
        energyDensity: 1.3
    )
    
    static let corrupted = GridMetabolism(
        harmony: 0.3,
        dissonance: 1.2,
        energyDensity: 0.7
    )
    
    static let energized = GridMetabolism(
        harmony: 1.2,
        dissonance: 0.1,
        energyDensity: 1.8
    )
    
    // MARK: - Initialization
    
    init(harmony: Float = 1.0, dissonance: Float = 0.0, energyDensity: Float = 1.0) {
        self.harmony = harmony
        self.dissonance = dissonance
        self.energyDensity = energyDensity
        self.lastUpdate = Date()
    }
    
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
