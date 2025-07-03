//
//  Core/World/WorldManager.swift
//  FinalStorm
//
//  Manages world, region, and grid systems - CLEANED: Using WorldTypes.swift
//

import RealityKit
import Combine
import CoreLocation
import Foundation
import simd

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
    
    // Finalverse integration - use shared types from WorldTypes.swift
    private let metabolismSimulator = MetabolismSimulator()
    private let providenceEngine = ProvidenceEngine()
    
    // MARK: - Initialization
    private func initializeWorld(_ world: World) async throws {
        // Initialize world systems
        print("Initializing world: \(world.name)")
    }
    
    private func loadRegionTerrain(_ region: Region) async throws {
        // Load terrain for region
        print("Loading terrain for region: \(region.name)")
    }
    
    private func loadRegionObjects(_ region: Region) async throws {
        // Load objects in region
        print("Loading objects for region: \(region.name)")
    }
    
    private func applyWorldMetabolism(to region: Region) {
        // Apply world metabolism effects
        print("Applying world metabolism to region: \(region.name)")
    }
    
    private func fetchObjectsFromServer(for coordinate: GridCoordinate) async throws -> [ObjectData] {
        // Fetch objects from server
        return []
    }
    
    private func calculateHarmonyDelta(for region: Region) -> Float {
        // Calculate harmony changes
        return 0.1
    }
    
    private func applyMetabolismToGrid(_ grid: inout Grid, metabolism: GridMetabolism) {
        // Apply metabolism effects to grid
        grid.updateMetabolism(metabolism)
    }
    
    private func createCelestialBloomEvent() {
        // Create celestial bloom
        print("Creating celestial bloom event")
    }
    
    private func createSilenceRiftEvent() {
        // Create silence rift
        print("Creating silence rift event")
    }
    
    private func createHarmonyWaveEvent() {
        // Create harmony wave
        print("Creating harmony wave event")
    }
    
    private func spawnHarmonyFlora(around location: SIMD3<Float>) async {
        // Spawn flora
        print("Spawning harmony flora at \(location)")
    }
    
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
        var grid = Grid(coordinate: coordinate)
        
        // Load terrain patch
        grid.terrain = try await generateTerrain(for: coordinate)
        
        // Load entities in grid
        let entities = try await loadEntitiesForGrid(coordinate)
        grid.entities = entities
        
        // Apply Finalverse dynamics
        if let metabolism = worldMetabolism.gridStates[coordinate] {
            applyMetabolismToGrid(&grid, metabolism: metabolism)
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
    
    private func determineBiome(for coordinate: GridCoordinate) -> Biome {
        // Determine biome based on coordinate
        // This would use noise functions and world rules
        return .grassland
    }
    
    private func createTerrainMesh(from heightmap: [[Float]]) async throws -> MeshResource {
        return try await MeshFactory.createTerrainMesh(from: heightmap)
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
        case .none:
            break
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
        
        // Load mesh using our sophisticated mesh system
        if let meshURL = data.meshURL {
            let mesh = try await MeshManager.shared.loadMesh(from: meshURL)
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
                interactionRadius: 2.0,
                requiresLineOfSight: true,
                interactionType: .activate,
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
        if let avatarSystem = getAvatarSystem() {
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
    
    private func getAvatarSystem() -> AvatarSystem? {
        // Get avatar system from app state
        return nil
    }
}

// MARK: - World Manager Specific Types (not duplicated in WorldTypes.swift)
struct World {
    let id: UUID = UUID()
    let name: String
    let server: ServerInfo
    let seed: Int = Int.random(in: 0...Int.max)
    var regions: [RegionInfo] = []
    var defaultRegion: RegionInfo?
}

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

// MARK: - Grid System
class GridSystem {
    // Grid management functionality
}

// REMOVED ALL DUPLICATED TYPES:
// - GridCoordinate (now in WorldTypes.swift)
// - WorldMetabolism (now in WorldTypes.swift)
// - GridMetabolism (now in WorldTypes.swift)
// - WorldEventType (now in WorldTypes.swift)
// - ProvidenceEngine (now in WorldTypes.swift)
// - MetabolismSimulator (now in WorldTypes.swift)
// - MetabolismState (now in WorldTypes.swift)
