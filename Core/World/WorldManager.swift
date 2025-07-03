//
//  WorldManager.swift
//  FinalStorm-S
//
//  Manages world, region, and grid systems for both OpenSim and Finalverse
//

import RealityKit
import Combine
import CoreLocation

@MainActor
class WorldManager: ObservableObject {
    // MARK: - Properties
    @Published var currentWorld: World?
    @Published var currentRegion: Region?
    @Published var loadedGrids: [GridCoordinate: Grid] = [:]
    @Published var visibleEntities: Set<Entity> = []
    @Published var worldMetabolism: WorldMetabolism = .balanced
    
    private let sceneManager = SceneManager()
    private let regionManager = RegionManager()
    private let gridSystem = GridSystem()
    private var worldUpdateCancellable: AnyCancellable?
    
    // Finalverse integration
    private let metabolismSimulator = MetabolismSimulator()
    private let providenceEngine = ProvidenceEngine()
    
    // MARK: - World Loading
    func loadWorld(named worldName: String, server: ServerInfo) async throws {
        // Create world instance
        let world = World(name: worldName, server: server)
        
        // Initialize world with server data
        try await initializeWorld(world)
        
        // Load initial region
        if let defaultRegion = world.defaultRegion {
            try await loadRegion(defaultRegion)
        }
        
        currentWorld = world
        
        // Start world metabolism simulation (Finalverse feature)
        startMetabolismSimulation()
    }
    
    func loadRegion(_ regionInfo: RegionInfo) async throws {
        // Create region instance
        let region = try await regionManager.loadRegion(regionInfo)
        
        // Load terrain and static objects
        try await loadRegionTerrain(region)
        try await loadRegionObjects(region)
        
        // Apply Finalverse world state
        applyWorldMetabolism(to: region)
        
        currentRegion = region
        
        // Load surrounding grids for seamless experience
        await loadSurroundingGrids(for: region.currentGrid)
    }
    
    // MARK: - Grid Management
    func loadGrid(at coordinate: GridCoordinate) async throws -> Grid {
        // Check cache first
        if let cachedGrid = loadedGrids[coordinate] {
            return cachedGrid
        }
        
        // Create new grid
        let grid = Grid(coordinate: coordinate)
        
        // Load terrain patch
        grid.terrain = try await generateTerrain(for: coordinate)
        
        // Load entities in grid
        let entities = try await loadEntitiesForGrid(coordinate)
        grid.entities = entities
        
        // Apply Finalverse dynamics
        if let metabolism = worldMetabolism.gridStates[coordinate] {
            applyMetabolismToGrid(grid, metabolism: metabolism)
        }
        
        loadedGrids[coordinate] = grid
        
        // Add to scene
        await sceneManager.addGrid(grid)
        
        return grid
    }
    
    private func loadSurroundingGrids(for centerGrid: GridCoordinate) async {
        let surroundingCoords = centerGrid.surrounding(radius: 2)
        
        await withTaskGroup(of: Void.self) { group in
            for coord in surroundingCoords {
                group.addTask {
                    do {
                        _ = try await self.loadGrid(at: coord)
                    } catch {
                        print("Failed to load grid \(coord): \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Terrain Generation
    private func generateTerrain(for coordinate: GridCoordinate) async throws -> TerrainPatch {
        // Use Finalverse's procedural generation with harmony influence
        let baseHeightmap = await providenceEngine.generateHeightmap(
            coordinate: coordinate,
            worldSeed: currentWorld?.seed ?? 0
        )
        
        // Apply biome-specific modifications
        let biome = determineBiome(for: coordinate)
        let modifiedTerrain = biome.modifyTerrain(baseHeightmap)
        
        // Create RealityKit terrain mesh
        let terrainMesh = try await createTerrainMesh(from: modifiedTerrain)
        
        return TerrainPatch(
            mesh: terrainMesh,
            heightmap: modifiedTerrain,
            biome: biome
        )
    }
    
    private func createTerrainMesh(from heightmap: [[Float]]) async throws -> MeshResource {
        // Generate vertices from heightmap
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let gridSize = heightmap.count
        let scale: Float = 1.0 // 1 meter per grid unit
        
        // Generate vertices
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let height = heightmap[z][x]
                vertices.append(SIMD3<Float>(Float(x) * scale, height, Float(z) * scale))
                uvs.append(SIMD2<Float>(Float(x) / Float(gridSize - 1), Float(z) / Float(gridSize - 1)))
                
                // Calculate normal (simplified)
                let normal = calculateNormal(x: x, z: z, heightmap: heightmap)
                normals.append(normal)
            }
        }
        
        // Generate indices for triangle mesh
        for z in 0..<(gridSize - 1) {
            for x in 0..<(gridSize - 1) {
                let topLeft = UInt32(z * gridSize + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((z + 1) * gridSize + x)
                let bottomRight = bottomLeft + 1
                
                // First triangle
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                // Second triangle
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        // Create mesh descriptor
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        
        return try await MeshResource.generate(from: [descriptor])
    }
    
    // MARK: - Finalverse Integration
    private func startMetabolismSimulation() {
        worldUpdateCancellable = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateWorldMetabolism()
            }
    }
    
    private func updateWorldMetabolism() {
        guard let region = currentRegion else { return }
        
        // Calculate harmony/dissonance changes
        let harmonyDelta = calculateHarmonyDelta(for: region)
        
        // Update metabolism state
        worldMetabolism.updateHarmony(harmonyDelta)
        
        // Trigger world events based on metabolism
        if worldMetabolism.shouldTriggerEvent {
            triggerWorldEvent()
        }
    }
    
    private func triggerWorldEvent() {
        let eventType = worldMetabolism.determineEventType()
        
        switch eventType {
        case .celestialBloom:
            createCelestialBloomEvent()
        case .silenceRift:
            createSilenceRiftEvent()
        case .harmonyWave:
            createHarmonyWaveEvent()
        default:
            break
        }
    }
    
    private func createCelestialBloomEvent() {
        guard let region = currentRegion else { return }
        
        // Create bloom effect at high-harmony locations
        let bloomLocations = region.findHighHarmonyPoints()
        
        for location in bloomLocations {
            let bloom = CelestialBloomEntity()
            bloom.position = location
            
            // Add particle effects
            var particles = ParticleEmitterComponent()
            particles.birthRate = 50
            particles.mainEmitter.lifeSpan = 10
            particles.mainEmitter.color = .evolving(
                start: .single(.systemPink),
                end: .single(.systemPurple)
            )
            
            bloom.components.set(particles)
            
            // Add to scene
            sceneManager.addEntity(bloom)
            
            // Spawn harmony-boosting flora
            Task {
                await spawnHarmonyFlora(around: location)
            }
        }
    }
    
    // MARK: - Entity Management
    private func loadEntitiesForGrid(_ coordinate: GridCoordinate) async throws -> [Entity] {
        var entities: [Entity] = []
        
        // Load static objects from server
        let serverObjects = try await fetchObjectsFromServer(for: coordinate)
        for objData in serverObjects {
            let entity = try await createEntity(from: objData)
            entities.append(entity)
        }
        
        // Add Finalverse dynamic entities
        let dynamicEntities = await providenceEngine.generateDynamicEntities(
            for: coordinate,
            metabolism: worldMetabolism.gridStates[coordinate] ?? .neutral
        )
        entities.append(contentsOf: dynamicEntities)
        
        return entities
    }
    
    private func createEntity(from data: ObjectData) async throws -> Entity {
        let entity = ObjectEntity()
        
        // Load mesh
        if let meshURL = data.meshURL {
            let mesh = try await MeshResource.load(contentsOf: meshURL)
            entity.components.set(ModelComponent(mesh: mesh, materials: []))
        }
        
        // Set transform
        entity.position = data.position
        entity.orientation = data.rotation
        entity.scale = data.scale
        
        // Add physics if needed
        if data.hasPhysics {
            entity.components.set(PhysicsBodyComponent(
                massProperties: .init(mass: data.mass),
                material: nil,
                mode: data.isDynamic ? .dynamic : .static
            ))
        }
        
        // Add Finalverse components
        if data.isInteractive {
            entity.components.set(HarmonyComponent())
            entity.components.set(InteractionComponent(
                onInteract: { [weak self] in
                    self?.handleEntityInteraction(entity)
                }
            ))
        }
        
        return entity
    }
    
    // MARK: - Helper Methods
    private func calculateNormal(x: Int, z: Int, heightmap: [[Float]]) -> SIMD3<Float> {
        let gridSize = heightmap.count
        
        // Get surrounding heights
        let left = x > 0 ? heightmap[z][x-1] : heightmap[z][x]
        let right = x < gridSize-1 ? heightmap[z][x+1] : heightmap[z][x]
        let up = z > 0 ? heightmap[z-1][x] : heightmap[z][x]
        let down = z < gridSize-1 ? heightmap[z+1][x] : heightmap[z][x]
        
        // Calculate normal using cross product
        let dx = SIMD3<Float>(2.0, right - left, 0.0)
        let dz = SIMD3<Float>(0.0, down - up, 2.0)
        
        return normalize(cross(dz, dx))
    }
    
    private func handleEntityInteraction(_ entity: Entity) {
        // Handle Finalverse-style interactions
        if let avatarSystem = (UIApplication.shared.delegate as? FinalStormSApp)?.avatarSystem {
            // Check if player can interact based on proximity and resonance
            if let avatar = avatarSystem.localAvatar,
               distance(avatar.position, entity.position) < 5.0 {
                
                // Trigger interaction based on entity type
                if entity is HarmonyBlossomEntity {
                    avatarSystem.performSongweaving(.restoration, target: entity)
                } else if entity is CorruptedEntity {
                    avatarSystem.performSongweaving(.purification, target: entity)
                }
            }
        }
    }
}

// MARK: - Supporting Types
struct World {
    let id: UUID = UUID()
    let name: String
    let server: ServerInfo
    let seed: Int = Int.random(in: 0...Int.max)
    var regions: [RegionInfo] = []
    var defaultRegion: RegionInfo?
    
    // =============================
    
}

// MARK: - Supporting Types (continued)
struct Region {
    let id: UUID
    let name: String
    let coordinate: RegionCoordinate
    var grids: [GridCoordinate: Grid] = [:]
    var currentGrid: GridCoordinate
    var harmonyLevel: Float = 1.0
    var biome: Biome = .grassland
    
    func findHighHarmonyPoints() -> [SIMD3<Float>] {
        // Find locations with high harmony concentration
        var points: [SIMD3<Float>] = []
        
        for (coord, grid) in grids {
            if grid.localHarmony > 0.8 {
                // Add center point of high harmony grid
                let worldPos = coord.toWorldPosition()
                points.append(worldPos)
            }
        }
        
        return points
    }
}

struct Grid {
    let coordinate: GridCoordinate
    var terrain: TerrainPatch?
    var entities: [Entity] = []
    var localHarmony: Float = 1.0
    var localDissonance: Float = 0.0
    
    mutating func updateMetabolism(_ metabolism: GridMetabolism) {
        localHarmony = metabolism.harmony
        localDissonance = metabolism.dissonance
    }
}

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

struct TerrainPatch {
    let mesh: MeshResource
    let heightmap: [[Float]]
    let biome: Biome
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

struct GridMetabolism {
    var harmony: Float
    var dissonance: Float
    
    static let neutral = GridMetabolism(harmony: 1.0, dissonance: 0.0)
}

enum WorldEventType {
    case celestialBloom
    case silenceRift
    case harmonyWave
    case none
}

enum Biome {
    case grassland
    case forest
    case desert
    case ocean
    case mountain
    case corrupted
    
    func modifyTerrain(_ heightmap: [[Float]]) -> [[Float]] {
        var modified = heightmap
        
        switch self {
        case .ocean:
            // Lower terrain and add wave patterns
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] = min(modified[z][x], 0.5)
                }
            }
        case .mountain:
            // Amplify height differences
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] *= 2.0
                }
            }
        case .corrupted:
            // Add jagged, discordant patterns
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    let noise = sin(Float(x) * 0.5) * cos(Float(z) * 0.5) * 0.3
                    modified[z][x] += noise
                }
            }
        default:
            break
        }
        
        return modified
    }
}
