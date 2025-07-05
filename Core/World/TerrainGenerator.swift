//
//  Core/World/TerrainGenerator.swift (ENHANCED)
//  FinalStorm
//
//  Complete terrain generation with all missing supporting structures
//

import Foundation
import RealityKit
import simd
import Combine

// MARK: - Missing Vegetation and Water Systems

struct VegetationMap {
    let grassDensity: [[Float]]
    let treePlacements: [TreePlacement]
    let flowerClusters: [FlowerCluster]
    let bushes: [BushPlacement]
    
    init() {
        // Initialize with empty data - will be populated by generator
        self.grassDensity = []
        self.treePlacements = []
        self.flowerClusters = []
        self.bushes = []
    }
    
    init(grassDensity: [[Float]], treePlacements: [TreePlacement] = [],
         flowerClusters: [FlowerCluster] = [], bushes: [BushPlacement] = []) {
        self.grassDensity = grassDensity
        self.treePlacements = treePlacements
        self.flowerClusters = flowerClusters
        self.bushes = bushes
    }
    
    struct TreePlacement {
        let position: SIMD3<Float>
        let species: TreeSpecies
        let scale: Float
        let rotation: Float
        let health: Float
        let age: Float
        
        init(position: SIMD3<Float>, species: TreeSpecies = .oak, scale: Float = 1.0) {
            self.position = position
            self.species = species
            self.scale = scale
            self.rotation = Float.random(in: 0...(2 * Float.pi))
            self.health = Float.random(in: 0.7...1.0)
            self.age = Float.random(in: 0.1...1.0)
        }
    }
    
    struct FlowerCluster {
        let center: SIMD3<Float>
        let radius: Float
        let species: FlowerSpecies
        let density: Float
        let bloomLevel: Float
        let seasonalMultiplier: Float
        
        init(center: SIMD3<Float>, species: FlowerSpecies = .wildflower) {
            self.center = center
            self.radius = Float.random(in: 2.0...8.0)
            self.species = species
            self.density = Float.random(in: 0.3...0.9)
            self.bloomLevel = Float.random(in: 0.0...1.0)
            self.seasonalMultiplier = 1.0
        }
    }
    
    struct BushPlacement {
        let position: SIMD3<Float>
        let species: BushSpecies
        let scale: Float
        let density: Float
        let fruitStage: Float
        
        init(position: SIMD3<Float>, species: BushSpecies = .berry) {
            self.position = position
            self.species = species
            self.scale = Float.random(in: 0.5...1.5)
            self.density = Float.random(in: 0.4...1.0)
            self.fruitStage = Float.random(in: 0.0...1.0)
        }
    }
    
    enum TreeSpecies: String, CaseIterable {
        case oak = "Oak"
        case pine = "Pine"
        case birch = "Birch"
        case willow = "Willow"
        case crystalTree = "Crystal Tree"
        case corruptedTree = "Corrupted Tree"
        case harmonyTree = "Harmony Tree"
        case ancientTree = "Ancient Tree"
        
        var defaultHeight: Float {
            switch self {
            case .oak: return 12.0
            case .pine: return 18.0
            case .birch: return 10.0
            case .willow: return 8.0
            case .crystalTree: return 15.0
            case .corruptedTree: return 14.0
            case .harmonyTree: return 20.0
            case .ancientTree: return 25.0
            }
        }
        
        var preferredBiomes: [BiomeType] {
            switch self {
            case .oak, .birch: return [.grassland, .forest]
            case .pine: return [.forest, .mountain, .tundra]
            case .willow: return [.swamp, .forest]
            case .crystalTree: return [.crystal, .ethereal]
            case .corruptedTree: return [.corrupted]
            case .harmonyTree: return [.ethereal, .grassland]
            case .ancientTree: return [.forest, .ethereal]
            }
        }
    }
    
    enum FlowerSpecies: String, CaseIterable {
        case wildflower = "Wildflower"
        case harmonyBlossom = "Harmony Blossom"
        case voidFlower = "Void Flower"
        case crystalBloom = "Crystal Bloom"
        case echoFlower = "Echo Flower"
        case sunBurst = "Sun Burst"
        case moonPetal = "Moon Petal"
        
        var bloomSeasons: [Season] {
            switch self {
            case .wildflower: return [.spring, .summer]
            case .harmonyBlossom: return [.spring, .summer, .autumn]
            case .voidFlower: return [.autumn, .winter]
            case .crystalBloom: return Season.allCases
            case .echoFlower: return [.summer, .autumn]
            case .sunBurst: return [.summer]
            case .moonPetal: return [.autumn, .winter]
            }
        }
        
        var harmonyEffect: Float {
            switch self {
            case .wildflower: return 0.05
            case .harmonyBlossom: return 0.3
            case .voidFlower: return -0.2
            case .crystalBloom: return 0.4
            case .echoFlower: return 0.15
            case .sunBurst: return 0.2
            case .moonPetal: return 0.1
            }
        }
    }
    
    enum BushSpecies: String, CaseIterable {
        case berry = "Berry Bush"
        case thorn = "Thorn Bush"
        case herb = "Herb Bush"
        case luminous = "Luminous Bush"
        case crystal = "Crystal Bush"
        case harmony = "Harmony Bush"
        
        var isEdible: Bool {
            switch self {
            case .berry, .herb: return true
            case .thorn, .luminous, .crystal, .harmony: return false
            }
        }
        
        var defensiveRating: Float {
            switch self {
            case .thorn: return 0.8
            case .crystal: return 0.4
            case .berry, .herb, .luminous, .harmony: return 0.0
            }
        }
    }
}

struct WaterBody {
    let id: UUID
    let type: WaterType
    let vertices: [SIMD3<Float>]
    let depth: Float
    let flow: WaterFlow?
    let clarity: Float
    let temperature: Float
    let harmonyLevel: Float
    let salinity: Float
    let oxygenLevel: Float
    
    enum WaterType: String, CaseIterable {
        case lake = "Lake"
        case river = "River"
        case stream = "Stream"
        case pond = "Pond"
        case spring = "Spring"
        case waterfall = "Waterfall"
        case ocean = "Ocean"
        case hotspring = "Hot Spring"
        case harmonicPool = "Harmonic Pool"
        case voidWater = "Void Water"
        
        var defaultDepth: Float {
            switch self {
            case .lake, .ocean: return 5.0
            case .river: return 2.0
            case .stream: return 0.5
            case .pond: return 1.5
            case .spring, .hotspring, .harmonicPool: return 1.0
            case .waterfall: return 0.3
            case .voidWater: return 3.0
            }
        }
        
        var flowRate: Float {
            switch self {
            case .river: return 2.0
            case .stream: return 1.0
            case .waterfall: return 5.0
            case .lake, .pond, .ocean, .spring, .hotspring, .harmonicPool, .voidWater: return 0.0
            }
        }
    }
    
    struct WaterFlow {
        let direction: SIMD3<Float>
        let speed: Float
        let turbulence: Float
        let seasonal: Bool
        
        init(direction: SIMD3<Float>, speed: Float = 1.0, turbulence: Float = 0.1) {
            self.direction = normalize(direction)
            self.speed = speed
            self.turbulence = turbulence
            self.seasonal = false
        }
    }
    
    init(type: WaterType, vertices: [SIMD3<Float>]) {
        self.id = UUID()
        self.type = type
        self.vertices = vertices
        self.depth = type.defaultDepth
        
        // Create flow if applicable
        if type.flowRate > 0 {
            self.flow = WaterFlow(
                direction: SIMD3<Float>(1, 0, 0), // Default east flow
                speed: type.flowRate,
                turbulence: type == .waterfall ? 0.8 : 0.2
            )
        } else {
            self.flow = nil
        }
        
        // Set water properties based on type
        switch type {
        case .harmonicPool:
            self.clarity = 1.0
            self.temperature = 0.7
            self.harmonyLevel = 1.5
            self.salinity = 0.0
            self.oxygenLevel = 1.0
        case .voidWater:
            self.clarity = 0.2
            self.temperature = 0.1
            self.harmonyLevel = 0.1
            self.salinity = 0.0
            self.oxygenLevel = 0.3
        case .hotspring:
            self.clarity = 0.7
            self.temperature = 0.9
            self.harmonyLevel = 1.2
            self.salinity = 0.1
            self.oxygenLevel = 0.6
        case .ocean:
            self.clarity = 0.6
            self.temperature = 0.5
            self.harmonyLevel = 0.9
            self.salinity = 0.9
            self.oxygenLevel = 0.8
        default:
            self.clarity = 0.8
            self.temperature = 0.5
            self.harmonyLevel = 1.0
            self.salinity = 0.0
            self.oxygenLevel = 0.9
        }
    }
    
    func getVolume() -> Float {
        // Simple volume calculation based on area and depth
        let area = calculateSurfaceArea()
        return area * depth
    }
    
    private func calculateSurfaceArea() -> Float {
        // Simplified area calculation for polygon
        guard vertices.count >= 3 else { return 0.0 }
        
        var area: Float = 0.0
        for i in 0..<vertices.count {
            let current = vertices[i]
            let next = vertices[(i + 1) % vertices.count]
            area += (current.x * next.z - next.x * current.z)
        }
        return abs(area) / 2.0
    }
}

struct TerrainMetadata {
    let generationTime: Date
    let generationMethod: GenerationMethod
    let noiseSettings: NoiseSettings
    let processingTime: TimeInterval
    let memoryUsage: Int
    let optimizationLevel: Int
    let vertexCount: Int
    let triangleCount: Int
    let textureResolution: Int
    
    enum GenerationMethod: String, CaseIterable {
        case procedural = "Procedural"
        case heightmapBased = "Heightmap Based"
        case voxelBased = "Voxel Based"
        case hybrid = "Hybrid"
        case imported = "Imported"
    }
    
    struct NoiseSettings {
        let octaves: Int
        let frequency: Float
        let amplitude: Float
        let lacunarity: Float
        let persistence: Float
        let seed: UInt64
        let noiseType: NoiseType
        
        enum NoiseType: String, CaseIterable {
            case perlin = "Perlin"
            case simplex = "Simplex"
            case ridged = "Ridged"
            case fractal = "Fractal"
            case cellular = "Cellular"
        }
        
        init(octaves: Int = 6, frequency: Float = 0.01, amplitude: Float = 20.0) {
            self.octaves = octaves
            self.frequency = frequency
            self.amplitude = amplitude
            self.lacunarity = 2.0
            self.persistence = 0.5
            self.seed = UInt64.random(in: 0...UInt64.max)
            self.noiseType = .perlin
        }
    }
    
    init() {
        self.generationTime = Date()
        self.generationMethod = .procedural
        self.noiseSettings = NoiseSettings()
        self.processingTime = 0.0
        self.memoryUsage = 0
        self.optimizationLevel = 1
        self.vertexCount = 0
        self.triangleCount = 0
        self.textureResolution = 512
    }
    
    init(vertexCount: Int, triangleCount: Int, processingTime: TimeInterval) {
        self.generationTime = Date()
        self.generationMethod = .procedural
        self.noiseSettings = NoiseSettings()
        self.processingTime = processingTime
        self.memoryUsage = (vertexCount * 32 + triangleCount * 12) // Rough memory estimate
        self.optimizationLevel = 1
        self.vertexCount = vertexCount
        self.triangleCount = triangleCount
        self.textureResolution = 512
    }
}

// MARK: - Enhanced TerrainGenerator with Complete Implementation

extension TerrainGenerator {
    
    // MARK: - Advanced Generation Methods
    
    private func calculateTemperature(_ coordinate: GridCoordinate) -> Float {
        // Use noise and latitude-like calculation for realistic temperature distribution
        let latitudeEffect = abs(Float(coordinate.z)) * 0.01
        let noiseEffect = noiseEngine.generateTemperatureNoise(coordinate: coordinate)
        let seasonalEffect = getCurrentSeasonalTemperatureModifier()
        
        return (0.5 - latitudeEffect + noiseEffect * 0.3 + seasonalEffect).clamped(to: -1.0...1.0)
    }
    
    private func calculateHumidity(_ coordinate: GridCoordinate) -> Float {
        // Generate humidity based on distance from water bodies and elevation
        let baseHumidity = noiseEngine.generateHumidityNoise(coordinate: coordinate)
        let elevationEffect = calculateAverageElevation(coordinate) * -0.2 // Higher elevation = lower humidity
        let waterProximityEffect = calculateWaterProximityEffect(coordinate)
        
        return (baseHumidity + elevationEffect + waterProximityEffect).clamped(to: 0.0...1.0)
    }
    
    private func calculateAverageElevation(_ coordinate: GridCoordinate) -> Float {
        // Quick elevation estimation for humidity calculation
        let worldX = Float(coordinate.x * 100)
        let worldZ = Float(coordinate.z * 100)
        return noiseEngine.generateHeight(x: worldX, z: worldZ) / 50.0 // Normalize to 0-1 range
    }
    
    private func calculateWaterProximityEffect(_ coordinate: GridCoordinate) -> Float {
        // Simplified water proximity - in real implementation, this would check actual water bodies
        let proximityNoise = sin(Float(coordinate.x) * 0.03) * cos(Float(coordinate.z) * 0.03)
        return max(0, proximityNoise) * 0.3
    }
    
    private func getCurrentSeasonalTemperatureModifier() -> Float {
        // Get current season and apply temperature modifier
        let currentSeason = WorldConfiguration.season(daysPassed: getCurrentGameDay())
        return currentSeason.temperatureModifier
    }
    
    private func getCurrentGameDay() -> Int {
        // Calculate game day based on real time elapsed
        return Int(Date().timeIntervalSince1970 / WorldConfiguration.dayDuration)
    }
    
    // MARK: - Cache Management
    
    func getCacheHitRate() -> Float {
        let totalRequests = Float(cacheHits + cacheMisses)
        return totalRequests > 0 ? Float(cacheHits) / totalRequests : 0.0
    }
    
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
    private func recordCacheHit() {
        cacheHits += 1
    }
    
    private func recordCacheMiss() {
        cacheMisses += 1
    }
    
    func preloadTerrain(around centerCoordinate: GridCoordinate, radius: Int) async {
        let coordinates = centerCoordinate.surrounding(radius: radius)
        
        await withTaskGroup(of: Void.self) { group in
            for coord in coordinates {
                group.addTask {
                    do {
                        _ = try await self.generateTerrain(
                            for: coord,
                            worldMetabolism: WorldMetabolism.balanced,
                            playerPosition: centerCoordinate.toWorldPosition()
                        )
                    } catch {
                        print("Failed to preload terrain for \(coord): \(error)")
                    }
                }
            }
        }
    }
    
    func optimizeCache() {
        // Remove old cache entries based on last access time
        let now = Date()
        terrainCache = terrainCache.filter { _, patch in
            now.timeIntervalSince(patch.metadata.generationTime) < 3600 // Keep for 1 hour
        }
    }
}

// MARK: - Enhanced Supporting Systems

extension NoiseEngine {
    
    func generateAdvancedHeight(x: Float, z: Float, settings: TerrainMetadata.NoiseSettings) -> Float {
        var height: Float = 0.0
        var amplitude = settings.amplitude
        var frequency = settings.frequency
        
        for _ in 0..<settings.octaves {
            switch settings.noiseType {
            case .perlin:
                height += amplitude * perlinNoise(x: x * frequency, z: z * frequency)
            case .simplex:
                height += amplitude * simplexNoise(x: x * frequency, z: z * frequency)
            case .ridged:
                height += amplitude * ridgedNoise(x: x * frequency, z: z * frequency)
            case .fractal:
                height += amplitude * fractalNoise(x: x * frequency, z: z * frequency)
            case .cellular:
                height += amplitude * cellularNoise(x: x * frequency, z: z * frequency)
            }
            
            amplitude *= settings.persistence
            frequency *= settings.lacunarity
        }
        
        return height
    }
    
    private func perlinNoise(x: Float, z: Float) -> Float {
        // Simplified Perlin noise implementation
        return sin(x) * cos(z)
    }
    
    private func simplexNoise(x: Float, z: Float) -> Float {
        // Simplified simplex noise
        return sin(x * 1.2) * cos(z * 0.8) * 0.8
    }
    
    private func ridgedNoise(x: Float, z: Float) -> Float {
        // Ridged noise for mountain ridges
        let noise = sin(x * 0.5) * cos(z * 0.5)
        return abs(noise) * 2.0 - 1.0
    }
    
    private func fractalNoise(x: Float, z: Float) -> Float {
        // Fractal brownian motion
        let base = sin(x * 0.1) * cos(z * 0.1)
        let detail = sin(x * 0.3) * cos(z * 0.3) * 0.5
        let fine = sin(x * 0.7) * cos(z * 0.7) * 0.25
        return base + detail + fine
    }
    
    private func cellularNoise(x: Float, z: Float) -> Float {
        // Cellular automata-like noise for cave systems
        let cellX = floor(x)
        let cellZ = floor(z)
        let hash = sin(cellX * 12.9898 + cellZ * 78.233) * 43758.5453
        return fract(hash) * 2.0 - 1.0
    }
    
    private func fract(_ value: Float) -> Float {
        return value - floor(value)
    }
}

// MARK: - Enhanced Vegetation Generator

class VegetationGenerator {
    private let densityNoiseEngine = NoiseEngine()
    
    func generateVegetation(
        heightmap: [[Float]],
        biome: BiomeType,
        harmonyLevel: Float,
        coordinate: GridCoordinate
    ) async -> VegetationMap {
        
        let resolution = heightmap.count
        
        // Generate grass density map
        let grassDensity = generateGrassDensity(
            resolution: resolution,
            biome: biome,
            harmonyLevel: harmonyLevel,
            coordinate: coordinate
        )
        
        // Generate tree placements
        let trees = await generateTreePlacements(
            heightmap: heightmap,
            biome: biome,
            harmonyLevel: harmonyLevel,
            coordinate: coordinate
        )
        
        // Generate flower clusters
        let flowers = generateFlowerClusters(
            heightmap: heightmap,
            biome: biome,
            harmonyLevel: harmonyLevel
        )
        
        // Generate bushes
        let bushes = generateBushPlacements(
            heightmap: heightmap,
            biome: biome,
            harmonyLevel: harmonyLevel
        )
        
        return VegetationMap(
            grassDensity: grassDensity,
            treePlacements: trees,
            flowerClusters: flowers,
            bushes: bushes
        )
    }
    
    private func generateGrassDensity(
        resolution: Int,
        biome: BiomeType,
        harmonyLevel: Float,
        coordinate: GridCoordinate
    ) -> [[Float]] {
        
        var grassDensity: [[Float]] = []
        let baseDensity = biome.grassDensityMultiplier
        
        for z in 0..<resolution {
            var row: [Float] = []
            for x in 0..<resolution {
                let worldX = Float(coordinate.x * 100 + x)
                let worldZ = Float(coordinate.z * 100 + z)
                
                let noiseValue = densityNoiseEngine.generateHeight(x: worldX * 0.1, z: worldZ * 0.1)
                let harmonyMultiplier = 0.5 + harmonyLevel * 0.5
                
                let density = (baseDensity + noiseValue * 0.3) * harmonyMultiplier
                row.append(max(0, min(1, density)))
            }
            grassDensity.append(row)
        }
        
        return grassDensity
    }
    
    private func generateTreePlacements(
        heightmap: [[Float]],
        biome: BiomeType,
        harmonyLevel: Float,
        coordinate: GridCoordinate
    ) async -> [VegetationMap.TreePlacement] {
        
        var trees: [VegetationMap.TreePlacement] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        let treeDensity = biome.treeDensity * (0.5 + harmonyLevel * 0.5)
        let targetTreeCount = Int(treeDensity * 20) // Base tree count per grid
        
        for _ in 0..<targetTreeCount {
            let x = Int.random(in: 1..<(resolution-1))
            let z = Int.random(in: 1..<(resolution-1))
            
            let height = heightmap[z][x]
            let slope = calculateSlope(x: x, z: z, heightmap: heightmap)
            
            // Don't place trees on steep slopes or in water
            if slope < 0.5 && height > -1.0 {
                let worldX = (Float(x) / Float(resolution)) * gridSize
                let worldZ = (Float(z) / Float(resolution)) * gridSize
                let position = SIMD3<Float>(worldX, height, worldZ)
                
                let species = selectTreeSpecies(biome: biome, harmonyLevel: harmonyLevel)
                let tree = VegetationMap.TreePlacement(position: position, species: species)
                trees.append(tree)
            }
        }
        
        return trees
    }
    
    private func calculateSlope(x: Int, z: Int, heightmap: [[Float]]) -> Float {
        let resolution = heightmap.count
        guard x > 0 && x < resolution-1 && z > 0 && z < resolution-1 else { return 0 }
        
        let left = heightmap[z][x-1]
        let right = heightmap[z][x+1]
        let up = heightmap[z-1][x]
        let down = heightmap[z+1][x]
        
        let dx = abs(right - left)
        let dz = abs(down - up)
        
        return sqrt(dx * dx + dz * dz)
    }
    
    private func selectTreeSpecies(biome: BiomeType, harmonyLevel: Float) -> VegetationMap.TreeSpecies {
        let availableSpecies = VegetationMap.TreeSpecies.allCases.filter { species in
            species.preferredBiomes.contains(biome)
        }
        
        if availableSpecies.isEmpty {
            return .oak // Fallback
        }
        
        // Special species based on harmony level
        if harmonyLevel > 1.5 && availableSpecies.contains(.harmonyTree) {
            return .harmonyTree
        } else if harmonyLevel < 0.3 && availableSpecies.contains(.corruptedTree) {
            return .corruptedTree
        }
        
        return availableSpecies.randomElement() ?? .oak
    }
    
    private func generateFlowerClusters(
        heightmap: [[Float]],
        biome: BiomeType,
        harmonyLevel: Float
    ) -> [VegetationMap.FlowerCluster] {
        
        var clusters: [VegetationMap.FlowerCluster] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        let flowerDensity = biome.flowerDensity * harmonyLevel
        let targetClusterCount = Int(flowerDensity * 5)
        
        for _ in 0..<targetClusterCount {
            let x = Int.random(in: 0..<resolution)
            let z = Int.random(in: 0..<resolution)
            
            let height = heightmap[z][x]
            if height > 0 { // Only place flowers above water level
                let worldX = (Float(x) / Float(resolution)) * gridSize
                let worldZ = (Float(z) / Float(resolution)) * gridSize
                let center = SIMD3<Float>(worldX, height, worldZ)
                
                let species = selectFlowerSpecies(biome: biome, harmonyLevel: harmonyLevel)
                let cluster = VegetationMap.FlowerCluster(center: center, species: species)
                clusters.append(cluster)
            }
        }
        
        return clusters
    }
    
    private func selectFlowerSpecies(biome: BiomeType, harmonyLevel: Float) -> VegetationMap.FlowerSpecies {
        if harmonyLevel > 1.3 {
            return .harmonyBlossom
        } else if harmonyLevel < 0.5 {
            return .voidFlower
        } else if biome == .crystal || biome == .ethereal {
            return .crystalBloom
        } else {
            return .wildflower
        }
    }
    
    private func generateBushPlacements(
        heightmap: [[Float]],
        biome: BiomeType,
        harmonyLevel: Float
    ) -> [VegetationMap.BushPlacement] {
        
        var bushes: [VegetationMap.BushPlacement] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        let bushDensity = biome.bushDensity
        let targetBushCount = Int(bushDensity * 10)
        
        for _ in 0..<targetBushCount {
            let x = Int.random(in: 0..<resolution)
            let z = Int.random(in: 0..<resolution)
            
            let height = heightmap[z][x]
            if height > -0.5 {
                let worldX = (Float(x) / Float(resolution)) * gridSize
                let worldZ = (Float(z) / Float(resolution)) * gridSize
                let position = SIMD3<Float>(worldX, height, worldZ)
                
                let species = selectBushSpecies(biome: biome, harmonyLevel: harmonyLevel)
                let bush = VegetationMap.BushPlacement(position: position, species: species)
                bushes.append(bush)
            }
        }
        
        return bushes
    }
    
    private func selectBushSpecies(biome: BiomeType, harmonyLevel: Float) -> VegetationMap.BushSpecies {
        switch biome {
        case .forest, .grassland:
            return Float.random(in: 0...1) > 0.7 ? .berry : .herb
        case .corrupted:
            return .thorn
        case .ethereal, .crystal:
            return harmonyLevel > 1.0 ? .harmony : .luminous
        default:
            return .herb
        }
    }
}

// MARK: - BiomeType Extensions for Vegetation

extension BiomeType {
    var grassDensityMultiplier: Float {
        switch self {
        case .grassland: return 0.9
        case .forest: return 0.7
        case .desert, .arctic, .volcanic: return 0.1
        case .ocean: return 0.0
        case .mountain, .mesa: return 0.3
        case .corrupted: return 0.2
        case .swamp: return 0.6
        case .tundra: return 0.4
        case .ethereal: return 1.0
        case .crystal: return 0.5
        case .jungle: return 0.8
        }
    }
    
    var treeDensity: Float {
        switch self {
        case .forest, .jungle: return 1.0
        case .grassland: return 0.3
        case .swamp: return 0.6
        case .ethereal: return 0.4
        case .mountain: return 0.2
        case .corrupted: return 0.1
        case .desert, .arctic, .tundra, .ocean, .volcanic, .mesa: return 0.0
        case .crystal: return 0.2
        }
    }
    
    var flowerDensity: Float {
        switch self {
        case .grassland: return 0.8
        case .ethereal: return 1.2
        case .forest: return 0.6
        case .jungle: return 0.7
        case .crystal: return 0.9
        case .swamp: return 0.4
        case .mountain, .mesa: return 0.3
        case .tundra: return 0.2
        case .corrupted: return 0.1
        case .desert, .arctic, .volcanic, .ocean: return 0.0
        }
    }
    
    var bushDensity: Float {
        switch self {
        case .forest, .jungle: return 0.7
        case .grassland: return 0.5
        case .swamp: return 0.6
        case .mountain, .mesa: return 0.4
        case .tundra: return 0.3
        case .ethereal: return 0.4
        case .crystal: return 0.3
        case .corrupted: return 0.2
        case .desert: return 0.1
        case .arctic, .volcanic, .ocean: return 0.0
        }
    }
 }
