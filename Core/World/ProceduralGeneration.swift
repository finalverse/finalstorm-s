//
// File Path: Core/World/ProceduralGeneration.swift
// Description: Advanced procedural world generation system
// Implements terrain, biomes, structures, and dynamic content generation
//

import Foundation
import simd
import GameplayKit

// MARK: - Procedural World Generator
/// Main procedural generation system for creating infinite worlds
class ProceduralWorldGenerator {
   
   // MARK: - Generator Components
   private var terrainGenerator: TerrainGenerator
   private var biomeGenerator: BiomeGenerator
   private var structureGenerator: StructureGenerator
   private var vegetationGenerator: VegetationGenerator
   private var caveGenerator: CaveSystemGenerator
   private var riverGenerator: RiverNetworkGenerator
   
   // MARK: - Noise Functions
   private var terrainNoise: GKPerlinNoiseSource
   private var biomeNoise: GKPerlinNoiseSource
   private var detailNoise: GKBillowNoiseSource
   
   init() {
       // Initialize noise sources
       self.terrainNoise = GKPerlinNoiseSource(
           frequency: 0.01,
           octaveCount: 6,
           persistence: 0.5,
           lacunarity: 2.0,
           seed: Int32.random(in: 0...Int32.max)
       )
       
       self.biomeNoise = GKPerlinNoiseSource(
           frequency: 0.005,
           octaveCount: 4,
           persistence: 0.6,
           lacunarity: 2.2,
           seed: Int32.random(in: 0...Int32.max)
       )
       
       self.detailNoise = GKBillowNoiseSource(
           frequency: 0.05,
           octaveCount: 3,
           persistence: 0.4,
           lacunarity: 2.5,
           seed: Int32.random(in: 0...Int32.max)
       )
       
       // Initialize generators
       self.terrainGenerator = TerrainGenerator(noiseSource: terrainNoise)
       self.biomeGenerator = BiomeGenerator(noiseSource: biomeNoise)
       self.structureGenerator = StructureGenerator()
       self.vegetationGenerator = VegetationGenerator()
       self.caveGenerator = CaveSystemGenerator()
       self.riverGenerator = RiverNetworkGenerator()
   }
   
   // MARK: - Terrain Generation
   func generateTerrain(seed: UInt64, center: SIMD3<Float>, radius: Float, biome: BiomeType) -> VoxelTerrain {
       // Set seed for deterministic generation
       setSeed(seed)
       
       // Generate height map
       let heightMap = terrainGenerator.generateHeightMap(
           center: center,
           size: Int(radius * 2),
           resolution: 1.0
       )
       
       // Generate biome map
       let biomeMap = biomeGenerator.generateBiomeMap(
           center: center,
           size: Int(radius * 2),
           primaryBiome: biome
       )
       
       // Generate material layers based on height and biome
       let materialLayers = generateMaterialLayers(heightMap: heightMap, biomeMap: biomeMap)
       
       // Generate vegetation data
       let vegetationData = vegetationGenerator.generateVegetation(
           heightMap: heightMap,
           biomeMap: biomeMap,
           density: 0.3
       )
       
       // Generate cave systems
       let caves = caveGenerator.generateCaves(
           bounds: BoundingBox(center: center, size: SIMD3<Float>(repeating: radius * 2)),
           density: 0.1
       )
       
       // Generate river networks
       let rivers = riverGenerator.generateRivers(
           heightMap: heightMap,
           biomeMap: biomeMap
       )
       
       // Convert to voxel representation
       let voxelTerrain = convertToVoxelTerrain(
           heightMap: heightMap,
           biomeMap: biomeMap,
           materialLayers: materialLayers,
           vegetationData: vegetationData,
           caves: caves,
           rivers: rivers
       )
       
       return voxelTerrain
   }
   
   // MARK: - Material Layer Generation
   private func generateMaterialLayers(heightMap: HeightMap, biomeMap: BiomeMap) -> [MaterialLayer] {
       var layers: [MaterialLayer] = []
       
       // Base rock layer
       layers.append(MaterialLayer(
           material: .rock,
           minHeight: -1000,
           maxHeight: heightMap.seaLevel - 10,
           noiseScale: 0.1,
           noiseStrength: 0.2
       ))
       
       // Sediment layer
       layers.append(MaterialLayer(
           material: .dirt,
           minHeight: heightMap.seaLevel - 10,
           maxHeight: heightMap.seaLevel + 50,
           noiseScale: 0.05,
           noiseStrength: 0.3
       ))
       
       // Biome-specific layers
       for biome in biomeMap.biomes {
           switch biome.type {
           case .desert:
               layers.append(MaterialLayer(
                   material: .sand,
                   minHeight: heightMap.seaLevel,
                   maxHeight: heightMap.seaLevel + 100,
                   noiseScale: 0.02,
                   noiseStrength: 0.1
               ))
           case .forest:
               layers.append(MaterialLayer(
                   material: .grass,
                   minHeight: heightMap.seaLevel + 1,
                   maxHeight: heightMap.seaLevel + 200,
                   noiseScale: 0.01,
                   noiseStrength: 0.05
               ))
           case .tundra:
               layers.append(MaterialLayer(
                   material: .snow,
                   minHeight: heightMap.seaLevel + 150,
                   maxHeight: 1000,
                   noiseScale: 0.03,
                   noiseStrength: 0.2
               ))
           default:
               break
           }
       }
       
       return layers
   }
   
   // MARK: - Voxel Conversion
   private func convertToVoxelTerrain(
       heightMap: HeightMap,
       biomeMap: BiomeMap,
       materialLayers: [MaterialLayer],
       vegetationData: VegetationData,
       caves: [CaveSystem],
       rivers: [RiverNetwork]
   ) -> VoxelTerrain {
       var chunks: [ChunkCoordinate: VoxelChunk] = [:]
       
       let chunkSize = 32
       let chunksPerSide = heightMap.size / chunkSize
       
       for x in 0..<chunksPerSide {
           for z in 0..<chunksPerSide {
               let chunkCoord = ChunkCoordinate(x: x, z: z)
               let chunk = generateVoxelChunk(
                   coordinate: chunkCoord,
                   chunkSize: chunkSize,
                   heightMap: heightMap,
                   materialLayers: materialLayers,
                   caves: caves
               )
               chunks[chunkCoord] = chunk
           }
       }
       
       return VoxelTerrain(
           chunks: chunks,
           biomeMap: biomeMap,
           heightMap: heightMap,
           materialLayers: materialLayers,
           vegetationSystem: vegetationData
       )
   }
   
   private func generateVoxelChunk(
       coordinate: ChunkCoordinate,
       chunkSize: Int,
       heightMap: HeightMap,
       materialLayers: [MaterialLayer],
       caves: [CaveSystem]
   ) -> VoxelChunk {
       var voxels = Array(repeating: Array(repeating: Array(repeating: Voxel.air, count: chunkSize), count: 256), count: chunkSize)
       
       let worldX = coordinate.x * chunkSize
       let worldZ = coordinate.z * chunkSize
       
       for x in 0..<chunkSize {
           for z in 0..<chunkSize {
               let height = heightMap.getHeight(x: worldX + x, z: worldZ + z)
               
               for y in 0..<Int(height) {
                   let material = getMaterialAtHeight(Float(y), layers: materialLayers)
                   voxels[x][y][z] = Voxel(material: material, density: 1.0)
               }
               
               // Apply cave carving
               for cave in caves {
                   if cave.affects(x: worldX + x, y: 0, z: worldZ + z) {
                       carveCave(at: (x, z), in: &voxels, cave: cave)
                   }
               }
           }
       }
       
       return VoxelChunk(
           coordinate: coordinate,
           voxels: voxels,
           isDirty: true
       )
   }
   
   private func getMaterialAtHeight(_ height: Float, layers: [MaterialLayer]) -> VoxelMaterial {
       for layer in layers.reversed() {
           if height >= layer.minHeight && height <= layer.maxHeight {
               return layer.material
           }
       }
       return .rock
   }
   
   private func carveCave(at position: (Int, Int), in voxels: inout [[[Voxel]]], cave: CaveSystem) {
       let (x, z) = position
       
       for y in 0..<voxels[0].count {
           let worldPos = SIMD3<Float>(Float(x), Float(y), Float(z))
           if cave.contains(point: worldPos) {
               voxels[x][y][z] = Voxel.air
           }
       }
   }
   
   // MARK: - Seed Management
   private func setSeed(_ seed: UInt64) {
       let randomSource = GKMersenneTwisterRandomSource(seed: seed)
       terrainNoise.seed = Int32(randomSource.nextInt())
       biomeNoise.seed = Int32(randomSource.nextInt())
       detailNoise.seed = Int32(randomSource.nextInt())
   }
}

// MARK: - Terrain Generator
class TerrainGenerator {
   private var noiseSource: GKPerlinNoiseSource
   private var erosionSimulator: ErosionSimulator
   
   init(noiseSource: GKPerlinNoiseSource) {
       self.noiseSource = noiseSource
       self.erosionSimulator = ErosionSimulator()
   }
   
   func generateHeightMap(center: SIMD3<Float>, size: Int, resolution: Float) -> HeightMap {
       var heights = Array(repeating: Array(repeating: Float(0), count: size), count: size)
       let noise = GKNoise(noiseSource)
       let noiseMap = GKNoiseMap(noise)
       
       // Generate base terrain
       for x in 0..<size {
           for z in 0..<size {
               let worldX = center.x + Float(x - size/2) * resolution
               let worldZ = center.z + Float(z - size/2) * resolution
               
               // Multi-octave noise for realistic terrain
               var height: Float = 0
               var amplitude: Float = 100
               var frequency: Float = 0.01
               
               for _ in 0..<6 {
                   let sample = noiseMap.value(at: vector_int2(Int32(worldX * frequency), Int32(worldZ * frequency)))
                   height += Float(sample) * amplitude
                   amplitude *= 0.5
                   frequency *= 2.0
               }
               
               // Apply terrain curve for more realistic mountains
               height = applyTerrainCurve(height)
               
               heights[x][z] = height
           }
       }
       
       // Apply erosion simulation
       heights = erosionSimulator.simulate(heightMap: heights, iterations: 50)
       
       return HeightMap(
           data: heights,
           size: size,
           seaLevel: 0,
           minHeight: heights.flatMap { $0 }.min() ?? 0,
           maxHeight: heights.flatMap { $0 }.max() ?? 100
       )
   }
   
   private func applyTerrainCurve(_ height: Float) -> Float {
       // Apply exponential curve for more dramatic terrain
       let normalized = (height + 100) / 200  // Normalize to 0-1
       let curved = pow(normalized, 2.5)       // Apply curve
       return curved * 300 - 100               // Scale back to world units
   }
}

// MARK: - Erosion Simulator
class ErosionSimulator {
   
   func simulate(heightMap: [[Float]], iterations: Int) -> [[Float]] {
       var eroded = heightMap
       let size = heightMap.count
       
       for _ in 0..<iterations {
           // Simulate water droplet
           let droplet = WaterDroplet(
               position: SIMD2<Float>(
                   Float.random(in: 0..<Float(size)),
                   Float.random(in: 0..<Float(size))
               ),
               velocity: .zero,
               water: 1.0,
               sediment: 0.0
           )
           
           simulateDroplet(droplet, on: &eroded)
       }
       
       return eroded
   }
   
   private func simulateDroplet(_ droplet: WaterDroplet, on heightMap: inout [[Float]]) {
       var drop = droplet
       let gravity: Float = 4.0
       let evaporationRate: Float = 0.01
       let depositionRate: Float = 0.01
       let erosionRate: Float = 0.01
       
       for _ in 0..<30 {  // Max lifetime
           let x = Int(drop.position.x)
           let z = Int(drop.position.y)
           
           guard x >= 0 && x < heightMap.count && z >= 0 && z < heightMap[0].count else { break }
           
           // Calculate flow direction
           let gradient = calculateGradient(at: drop.position, in: heightMap)
           drop.velocity = drop.velocity * 0.8 + gradient * gravity
           
           // Move droplet
           drop.position += drop.velocity
           
           // Erosion and deposition
           let currentHeight = bilinearInterpolate(drop.position, in: heightMap)
           let capacity = length(drop.velocity) * drop.water * erosionRate
           
           if drop.sediment > capacity {
               // Deposit sediment
               let deposit = (drop.sediment - capacity) * depositionRate
               heightMap[x][z] += deposit
               drop.sediment -= deposit
           } else {
               // Erode terrain
               let erosion = min((capacity - drop.sediment) * erosionRate, currentHeight)
               heightMap[x][z] -= erosion
               drop.sediment += erosion
           }
           
           // Evaporate water
           drop.water *= (1.0 - evaporationRate)
           if drop.water < 0.01 { break }
       }
   }
   
   private func calculateGradient(at position: SIMD2<Float>, in heightMap: [[Float]]) -> SIMD2<Float> {
       let x = Int(position.x)
       let z = Int(position.y)
       
       guard x > 0 && x < heightMap.count - 1 && z > 0 && z < heightMap[0].count - 1 else {
           return .zero
       }
       
       let dx = heightMap[x + 1][z] - heightMap[x - 1][z]
       let dz = heightMap[x][z + 1] - heightMap[x][z - 1]
       
       return normalize(SIMD2<Float>(-dx, -dz))
   }
   
   private func bilinearInterpolate(_ position: SIMD2<Float>, in heightMap: [[Float]]) -> Float {
       let x0 = Int(floor(position.x))
       let z0 = Int(floor(position.y))
       let x1 = min(x0 + 1, heightMap.count - 1)
       let z1 = min(z0 + 1, heightMap[0].count - 1)
       
       let fx = position.x - Float(x0)
       let fz = position.y - Float(z0)
       
       let h00 = heightMap[x0][z0]
       let h10 = heightMap[x1][z0]
       let h01 = heightMap[x0][z1]
       let h11 = heightMap[x1][z1]
       
       let h0 = mix(h00, h10, fx)
       let h1 = mix(h01, h11, fx)
       
       return mix(h0, h1, fz)
   }
}

// MARK: - Biome Generator
class BiomeGenerator {
   private var noiseSource: GKPerlinNoiseSource
   private var climateModel: ClimateModel
   
   init(noiseSource: GKPerlinNoiseSource) {
       self.noiseSource = noiseSource
       self.climateModel = ClimateModel()
   }
   
   func generateBiomeMap(center: SIMD3<Float>, size: Int, primaryBiome: BiomeType) -> BiomeMap {
       var biomes: [Biome] = []
       let noise = GKNoise(noiseSource)
       let noiseMap = GKNoiseMap(noise)
       
       // Generate temperature and moisture maps
       let temperatureMap = generateClimateMap(center: center, size: size, type: .temperature)
       let moistureMap = generateClimateMap(center: center, size: size, type: .moisture)
       
       // Determine biomes based on climate
       for x in 0..<size {
           for z in 0..<size {
               let temperature = temperatureMap[x][z]
               let moisture = moistureMap[x][z]
               
               let biomeType = climateModel.getBiomeType(
                   temperature: temperature,
                   moisture: moisture,
                   elevation: 0  // Will be filled by height map
               )
               
               // Check if we need to add this biome
               if !biomes.contains(where: { $0.type == biomeType }) {
                   biomes.append(Biome(
                       type: biomeType,
                       color: biomeType.color,
                       vegetationDensity: biomeType.vegetationDensity,
                       allowedStructures: biomeType.allowedStructures
                   ))
               }
           }
       }
       
       return BiomeMap(
           biomes: biomes,
           temperatureMap: temperatureMap,
           moistureMap: moistureMap,
           size: size
       )
   }
   
   private func generateClimateMap(center: SIMD3<Float>, size: Int, type: ClimateType) -> [[Float]] {
       var map = Array(repeating: Array(repeating: Float(0), count: size), count: size)
       
       let frequency: Float = type == .temperature ? 0.002 : 0.003
       let amplitude: Float = 1.0
       
       for x in 0..<size {
           for z in 0..<size {
               let worldX = center.x + Float(x - size/2)
               let worldZ = center.z + Float(z - size/2)
               
               // Add latitude-based temperature variation
               if type == .temperature {
                   let latitude = abs(worldZ) / 1000.0
                   map[x][z] = 1.0 - latitude  // Cooler at poles
               }
               
               // Add noise for variation
               let noise = Float(noiseSource.value(at: vector_double3(
                   Double(worldX * frequency),
                   0,
                   Double(worldZ * frequency)
               )))
               
               map[x][z] += noise * amplitude * 0.3
               map[x][z] = max(0, min(1, map[x][z]))  // Clamp to 0-1
           }
       }
       
       return map
   }
   
   enum ClimateType {
       case temperature
       case moisture
   }
}

// MARK: - Structure Generator
class StructureGenerator {
   private var structureTemplates: [StructureTemplate] = []
   private var placementRules: PlacementRules
   
   init() {
       self.placementRules = PlacementRules()
       loadStructureTemplates()
   }
   
   private func loadStructureTemplates() {
       // Load predefined structure templates
       structureTemplates = [
           StructureTemplate(
               name: "Ancient Tower",
               size: SIMD3<Int>(7, 20, 7),
               biomes: [.forest, .plains],
               rarity: 0.001
           ),
           StructureTemplate(
               name: "Desert Temple",
               size: SIMD3<Int>(15, 10, 15),
               biomes: [.desert],
               rarity: 0.002
           ),
           StructureTemplate(
               name: "Crystal Cave",
               size: SIMD3<Int>(20, 15, 20),
               biomes: [.mountains],
               rarity: 0.0005
           )
       ]
   }
   
   func generateStructures(for chunk: ChunkCoordinate, biome: BiomeType, heightMap: HeightMap) -> [Structure] {
       var structures: [Structure] = []
       
       let templates = structureTemplates.filter { $0.biomes.contains(biome) }
       
       for template in templates {
           if Float.random(in: 0...1) < template.rarity {
               if let structure = placeStructure(template, in: chunk, on: heightMap) {
                   structures.append(structure)
               }
           }
       }
       
       return structures
   }
   
   private func placeStructure(_ template: StructureTemplate, in chunk: ChunkCoordinate, on heightMap: HeightMap) -> Structure? {
       // Find suitable location
       let chunkWorldPos = chunk.worldPosition
       
       for attempt in 0..<10 {
           let x = Int.random(in: 0..<32) + chunkWorldPos.x
           let z = Int.random(in: 0..<32) + chunkWorldPos.z
           
           if placementRules.canPlace(template, at: (x, z), on: heightMap) {
               let y = Int(heightMap.getHeight(x: x, z: z))
               
               return Structure(
                   template: template,
                   position: SIMD3<Int>(x, y, z),
                   rotation: Float.random(in: 0..<Float.pi * 2),
                   variant: Int.random(in: 0..<template.variants)
               )
           }
       }
       
       return nil
   }
}

// MARK: - Vegetation Generator
class VegetationGenerator {
   private var vegetationTypes: [VegetationType] = []
   private var distributionNoise: GKPerlinNoiseSource
   
   init() {
       self.distributionNoise = GKPerlinNoiseSource(
           frequency: 0.1,
           octaveCount: 2,
           persistence: 0.5,
           lacunarity: 2.0,
           seed: Int32.random(in: 0...Int32.max)
       )
       loadVegetationTypes()
   }
   
   private func loadVegetationTypes() {
       vegetationTypes = [
           VegetationType(
               name: "Oak Tree",
               model: "oak_tree",
               biomes: [.forest, .plains],
               minHeight: 5.0,
               maxHeight: 200.0,
               clustering: 0.7
           ),
           VegetationType(
               name: "Pine Tree",
               model: "pine_tree",
               biomes: [.taiga, .mountains],
               minHeight: 50.0,
               maxHeight: 500.0,
               clustering: 0.8
           ),
           VegetationType(
               name: "Cactus",
               model: "cactus",
               biomes: [.desert],
               minHeight: 0.0,
               maxHeight: 100.0,
               clustering: 0.2
           ),
           VegetationType(
               name: "Crystal Flower",
               model: "crystal_flower",
               biomes: [.magical],
               minHeight: 0.0,
               maxHeight: 300.0,
               clustering: 0.5
           )
       ]
   }
   
   func generateVegetation(heightMap: HeightMap, biomeMap: BiomeMap, density: Float) -> VegetationData {
       var instances: [VegetationInstance] = []
       let noise = GKNoise(distributionNoise)
       let noiseMap = GKNoiseMap(noise)
       
       let spacing = Int(1.0 / density)
       
       for x in stride(from: 0, to: heightMap.size, by: spacing) {
           for z in stride(from: 0, to: heightMap.size, by: spacing) {
               let height = heightMap.getHeight(x: x, z: z)
               let biome = biomeMap.getBiome(at: (x, z))
               
               // Get suitable vegetation for this biome and height
               let suitable = vegetationTypes.filter { vegetation in
                   vegetation.biomes.contains(biome.type) &&
                   height >= vegetation.minHeight &&
                   height <= vegetation.maxHeight
               }
               
               if suitable.isEmpty { continue }
               
               // Use noise to determine if vegetation should be placed
               let noiseValue = noiseMap.value(at: vector_int2(Int32(x), Int32(z)))
               
               if Float(noiseValue) > 0.3 {
                   let vegetation = suitable.randomElement()!
                   
                   // Add some position variation
                   let offsetX = Float.random(in: -2...2)
                   let offsetZ = Float.random(in: -2...2)
                   
                   instances.append(VegetationInstance(
                       type: vegetation,
                       position: SIMD3<Float>(Float(x) + offsetX, height, Float(z) + offsetZ),
                       rotation: Float.random(in: 0..<Float.pi * 2),
                       scale: Float.random(in: 0.8...1.2)
                   ))
               }
           }
       }
       
       return VegetationData(instances: instances)
   }
}

// MARK: - Cave System Generator
class CaveSystemGenerator {
   private var worleyNoise: GKVoronoiNoiseSource
   private var perlinNoise: GKPerlinNoiseSource
   
   init() {
       self.worleyNoise = GKVoronoiNoiseSource(
           frequency: 0.02,
           displacement: 1.0,
           distanceEnabled: true,
           seed: Int32.random(in: 0...Int32.max)
       )
       
       self.perlinNoise = GKPerlinNoiseSource(
           frequency: 0.05,
           octaveCount: 3,
           persistence: 0.5,
           lacunarity: 2.0,
           seed: Int32.random(in: 0...Int32.max)
       )
   }
   
   func generateCaves(bounds: BoundingBox, density: Float) -> [CaveSystem] {
       var caves: [CaveSystem] = []
       
       let caveCount = Int(bounds.volume * density / 10000)
       
       for _ in 0..<caveCount {
           let origin = SIMD3<Float>(
               Float.random(in: bounds.min.x...bounds.max.x),
               Float.random(in: -50...50),
               Float.random(in: bounds.min.z...bounds.max.z)
           )
           
           let cave = generateCaveSystem(origin: origin)
           caves.append(cave)
       }
       
       return caves
   }
   
   private func generateCaveSystem(origin: SIMD3<Float>) -> CaveSystem {
       var tunnels: [CaveTunnel] = []
       var chambers: [CaveChamber] = []
       
       // Generate main chamber
       let mainChamber = CaveChamber(
           center: origin,
           radius: Float.random(in: 10...30),
           height: Float.random(in: 5...15)
       )
       chambers.append(mainChamber)
       
       // Generate connected tunnels
       let tunnelCount = Int.random(in: 2...5)
       for i in 0..<tunnelCount {
           let angle = Float(i) * (Float.pi * 2 / Float(tunnelCount))
           let direction = SIMD3<Float>(cos(angle), Float.random(in: -0.3...0.3), sin(angle))
           
           let tunnel = generateTunnel(
               start: origin,
               direction: direction,
               length: Float.random(in: 20...50)
           )
           tunnels.append(tunnel)
           
           // Chance for chamber at tunnel end
           if Float.random(in: 0...1) < 0.5 {
               let chamber = CaveChamber(
                   center: tunnel.points.last!,
                   radius: Float.random(in: 5...20),
                   height: Float.random(in: 3...10)
               )
               chambers.append(chamber)
           }
       }
       
       return CaveSystem(
           tunnels: tunnels,
           chambers: chambers,
           origin: origin
       )
   }
   
   private func generateTunnel(start: SIMD3<Float>, direction: SIMD3<Float>, length: Float) -> CaveTunnel {
       var points: [SIMD3<Float>] = [start]
       var radii: [Float] = [Float.random(in: 2...5)]
       
       var currentPos = start
       var currentDir = normalize(direction)
       let steps = Int(length / 2)
       
       for _ in 0..<steps {
           // Add some random variation to direction
           let variation = SIMD3<Float>(
               Float.random(in: -0.1...0.1),
               Float.random(in: -0.05...0.05),
               Float.random(in: -0.1...0.1)
           )
           currentDir = normalize(currentDir + variation)
           
           // Move forward
           currentPos += currentDir * 2
           
           // Vary radius
           let radius = radii.last! + Float.random(in: -0.5...0.5)
           
           points.append(currentPos)
           radii.append(max(1.0, radius))
       }
       
       return CaveTunnel(points: points, radii: radii)
   }
}

// MARK: - River Network Generator
class RiverNetworkGenerator {
   
   func generateRivers(heightMap: HeightMap, biomeMap: BiomeMap) -> [RiverNetwork] {
       var rivers: [RiverNetwork] = []
       
       // Find potential river sources (high elevation points)
       let sources = findRiverSources(heightMap: heightMap)
       
       for source in sources {
           if Float.random(in: 0...1) < 0.3 {  // 30% chance for river
               let river = traceRiver(from: source, heightMap: heightMap)
               if river.points.count > 10 {  // Only keep significant rivers
                   rivers.append(river)
               }
           }
       }
       
       return rivers
   }
   
   private func findRiverSources(heightMap: HeightMap) -> [SIMD2<Int>] {
       var sources: [SIMD2<Int>] = []
       
       for x in stride(from: 10, to: heightMap.size - 10, by: 20) {
           for z in stride(from: 10, to: heightMap.size - 10, by: 20) {
               let height = heightMap.getHeight(x: x, z: z)
               
               // Check if this is a local maximum (potential spring)
               if height > 100 && isLocalMaximum(x: x, z: z, heightMap: heightMap) {
                   sources.append(SIMD2<Int>(x, z))
               }
           }
       }
       
       return sources
   }
   
   private func isLocalMaximum(x: Int, z: Int, heightMap: HeightMap) -> Bool {
       let currentHeight = heightMap.getHeight(x: x, z: z)
       
       for dx in -5...5 {
           for dz in -5...5 {
               if dx == 0 && dz == 0 { continue }
               
               let neighborHeight = heightMap.getHeight(x: x + dx, z: z + dz)
               if neighborHeight > currentHeight {
                   return false
               }
           }
       }
       
       return true
   }
   
   private func traceRiver(from source: SIMD2<Int>, heightMap: HeightMap) -> RiverNetwork {
       var points: [SIMD3<Float>] = []
       var widths: [Float] = []
       var depths: [Float] = []
       
       var current = SIMD2<Float>(Float(source.x), Float(source.y))
       var width: Float = 1.0
       var depth: Float = 0.5
       
       let maxSteps = 500
       var steps = 0
       
       while steps < maxSteps {
           let x = Int(current.x)
           let z = Int(current.y)
           
           // Check bounds
           guard x >= 0 && x < heightMap.size && z >= 0 && z < heightMap.size else { break }
           
           let height = heightMap.getHeight(x: x, z: z)
           
           // Stop at sea level
           if height <= heightMap.seaLevel { break }
           
           points.append(SIMD3<Float>(current.x, height - depth, current.y))
           widths.append(width)
           depths.append(depth)
           
           // Find steepest descent
           let gradient = calculateGradient(at: current, in: heightMap)
           
           if length(gradient) < 0.001 { break }  // Reached flat area
           
           // Move downstream
           current += normalize(gradient) * 2
           
           // River gets wider and deeper as it flows
           width += 0.1
           depth += 0.05
           
           steps += 1
       }
       
       return RiverNetwork(
           points: points,
           widths: widths,
           depths: depths,
           flowRate: Float(points.count) * 0.1
       )
   }
   
   private func calculateGradient(at position: SIMD2<Float>, in heightMap: HeightMap) -> SIMD2<Float> {
       let x = Int(position.x)
       let z = Int(position.y)
       
       var steepest = SIMD2<Float>.zero
       var steepestDrop: Float = 0
       
       for dx in -1...1 {
           for dz in -1...1 {
               if dx == 0 && dz == 0 { continue }
               
               let nx = x + dx
               let nz = z + dz
               
               guard nx >= 0 && nx < heightMap.size && nz >= 0 && nz < heightMap.size else { continue }
               
               let currentHeight = heightMap.getHeight(x: x, z: z)
               let neighborHeight = heightMap.getHeight(x: nx, z: nz)
               let drop = currentHeight - neighborHeight
               
               if drop > steepestDrop {
                   steepestDrop = drop
                   steepest = SIMD2<Float>(Float(dx), Float(dz))
               }
           }
       }
       
       return steepest
   }
}

// MARK: - Supporting Types for Procedural Generation
struct HeightMap {
   let data: [[Float]]
   let size: Int
   let seaLevel: Float
   let minHeight: Float
   let maxHeight: Float
   
   func getHeight(x: Int, z: Int) -> Float {
       guard x >= 0 && x < size && z >= 0 && z < size else { return seaLevel }
       return data[x][z]
   }
}

struct BiomeMap {
   let biomes: [Biome]
   let temperatureMap: [[Float]]
   let moistureMap: [[Float]]
   let size: Int
   
   func getBiome(at position: (Int, Int)) -> Biome {
       let temperature = temperatureMap[position.0][position.1]
       let moisture = moistureMap[position.0][position.1]
       
       // Determine biome based on temperature and moisture
       if temperature < 0.2 {
           return biomes.first { $0.type == .tundra } ?? biomes[0]
       } else if temperature > 0.8 && moisture < 0.3 {
           return biomes.first { $0.type == .desert } ?? biomes[0]
       } else if moisture > 0.6 {
           return biomes.first { $0.type == .forest } ?? biomes[0]
       } else {
           return biomes.first { $0.type == .plains } ?? biomes[0]
       }
   }
}

struct Biome {
   let type: BiomeType
   let color: SIMD3<Float>
   let vegetationDensity: Float
   let allowedStructures: [String]
}

enum BiomeType {
   case desert
   case forest
   case plains
   case tundra
   case taiga
   case mountains
   case swamp
   case magical
   case mixed
   
   var color: SIMD3<Float> {
       switch self {
       case .desert: return SIMD3<Float>(0.9, 0.8, 0.6)
       case .forest: return SIMD3<Float>(0.2, 0.6, 0.2)
       case .plains: return SIMD3<Float>(0.5, 0.7, 0.3)
       case .tundra: return SIMD3<Float>(0.8, 0.8, 0.9)
       case .taiga: return SIMD3<Float>(0.3, 0.5, 0.4)
       case .mountains: return SIMD3<Float>(0.6, 0.6, 0.7)
       case .swamp: return SIMD3<Float>(0.3, 0.4, 0.3)
       case .magical: return SIMD3<Float>(0.7, 0.5, 0.9)
       case .mixed: return SIMD3<Float>(0.5, 0.5, 0.5)
       }
   }
   
   var vegetationDensity: Float {
       switch self {
       case .desert: return 0.1
       case .forest: return 0.8
       case .plains: return 0.4
       case .tundra: return 0.2
       case .taiga: return 0.6
       case .mountains: return 0.3
       case .swamp: return 0.7
       case .magical: return 0.5
       case .mixed: return 0.5
       }
   }
   
   var allowedStructures: [String] {
       switch self {
       case .desert: return ["pyramid", "oasis", "ruins"]
       case .forest: return ["tree_house", "ancient_grove", "fairy_circle"]
       case .plains: return ["village", "windmill", "stone_circle"]
       case .tundra: return ["ice_fortress", "frozen_ruins"]
       case .taiga: return ["lumber_camp", "hunter_lodge"]
       case .mountains: return ["dwarven_fortress", "crystal_cave", "monastery"]
       case .swamp: return ["witch_hut", "sunken_temple"]
       case .magical: return ["wizard_tower", "portal", "crystal_formation"]
       case .mixed: return ["outpost", "crossroads"]
       }
   }
}

struct MaterialLayer {
   let material: VoxelMaterial
   let minHeight: Float
   let maxHeight: Float
   let noiseScale: Float
   let noiseStrength: Float
}

struct VoxelChunk {
   let coordinate: ChunkCoordinate
   var voxels: [[[Voxel]]]
   var isDirty: Bool
}

struct Voxel {
   let material: VoxelMaterial
   let density: Float
   
   static let air = Voxel(material: .air, density: 0)
}

enum VoxelMaterial {
    case air
    case rock
    case dirt
    case grass
    case sand
    case snow
    case water
    case lava
    case crystal
    case ice
    case wood
    case leaves
    case metal
    case energy
    
    var color: SIMD4<Float> {
        switch self {
        case .air: return SIMD4<Float>(0, 0, 0, 0)
        case .rock: return SIMD4<Float>(0.5, 0.5, 0.5, 1)
        case .dirt: return SIMD4<Float>(0.4, 0.3, 0.2, 1)
        case .grass: return SIMD4<Float>(0.2, 0.6, 0.2, 1)
        case .sand: return SIMD4<Float>(0.9, 0.8, 0.6, 1)
        case .snow: return SIMD4<Float>(0.95, 0.95, 1.0, 1)
        case .water: return SIMD4<Float>(0.2, 0.5, 0.8, 0.8)
        case .lava: return SIMD4<Float>(1.0, 0.3, 0.1, 1)
        case .crystal: return SIMD4<Float>(0.7, 0.9, 1.0, 0.9)
        case .ice: return SIMD4<Float>(0.8, 0.9, 1.0, 0.9)
        case .wood: return SIMD4<Float>(0.5, 0.3, 0.1, 1)
        case .leaves: return SIMD4<Float>(0.3, 0.6, 0.2, 0.9)
        case .metal: return SIMD4<Float>(0.7, 0.7, 0.8, 1)
        case .energy: return SIMD4<Float>(0.9, 0.5, 1.0, 0.7)
        }
    }
    
    var hardness: Float {
        switch self {
        case .air: return 0
        case .rock: return 0.8
        case .dirt: return 0.3
        case .grass: return 0.3
        case .sand: return 0.2
        case .snow: return 0.1
        case .water: return 0
        case .lava: return 0
        case .crystal: return 0.9
        case .ice: return 0.6
        case .wood: return 0.5
        case .leaves: return 0.1
        case .metal: return 1.0
        case .energy: return 0.5
        }
    }
 }

 struct ChunkCoordinate: Hashable {
    let x: Int
    let z: Int
    
    var worldPosition: SIMD2<Int> {
        SIMD2<Int>(x * 32, z * 32)
    }
    
    init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }
    
    init(from worldPosition: SIMD3<Float>) {
        self.x = Int(floor(worldPosition.x / 32))
        self.z = Int(floor(worldPosition.z / 32))
    }
 }

 struct WaterDroplet {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var water: Float
    var sediment: Float
 }

 struct StructureTemplate {
    let name: String
    let size: SIMD3<Int>
    let biomes: [BiomeType]
    let rarity: Float
    let variants: Int = 3
 }

 struct Structure {
    let template: StructureTemplate
    let position: SIMD3<Int>
    let rotation: Float
    let variant: Int
 }

 struct VegetationType {
    let name: String
    let model: String
    let biomes: [BiomeType]
    let minHeight: Float
    let maxHeight: Float
    let clustering: Float
 }

 struct VegetationInstance {
    let type: VegetationType
    let position: SIMD3<Float>
    let rotation: Float
    let scale: Float
 }

 struct VegetationData {
    let instances: [VegetationInstance]
 }

 struct CaveSystem {
    let tunnels: [CaveTunnel]
    let chambers: [CaveChamber]
    let origin: SIMD3<Float>
    
    func contains(point: SIMD3<Float>) -> Bool {
        // Check chambers first
        for chamber in chambers {
            let distance = length(point - chamber.center)
            if distance < chamber.radius {
                return true
            }
        }
        
        // Check tunnels
        for tunnel in tunnels {
            if tunnel.contains(point: point) {
                return true
            }
        }
        
        return false
    }
    
    func affects(x: Int, y: Int, z: Int) -> Bool {
        let point = SIMD3<Float>(Float(x), Float(y), Float(z))
        let maxDistance: Float = 50 // Maximum cave influence
        return length(point - origin) < maxDistance
    }
 }

 struct CaveTunnel {
    let points: [SIMD3<Float>]
    let radii: [Float]
    
    func contains(point: SIMD3<Float>) -> Bool {
        for i in 0..<points.count - 1 {
            let segmentDistance = distanceToLineSegment(
                point: point,
                lineStart: points[i],
                lineEnd: points[i + 1]
            )
            
            let radius = (radii[i] + radii[i + 1]) / 2
            if segmentDistance < radius {
                return true
            }
        }
        return false
    }
    
    private func distanceToLineSegment(point: SIMD3<Float>, lineStart: SIMD3<Float>, lineEnd: SIMD3<Float>) -> Float {
        let line = lineEnd - lineStart
        let lineLength = length(line)
        
        if lineLength == 0 {
            return length(point - lineStart)
        }
        
        let t = max(0, min(1, dot(point - lineStart, line) / (lineLength * lineLength)))
        let projection = lineStart + t * line
        
        return length(point - projection)
    }
 }

 struct CaveChamber {
    let center: SIMD3<Float>
    let radius: Float
    let height: Float
 }

 struct RiverNetwork {
    let points: [SIMD3<Float>]
    let widths: [Float]
    let depths: [Float]
    let flowRate: Float
 }

 struct PlacementRules {
    func canPlace(_ template: StructureTemplate, at position: (Int, Int), on heightMap: HeightMap) -> Bool {
        let (x, z) = position
        
        // Check if area is relatively flat
        let baseHeight = heightMap.getHeight(x: x, z: z)
        let tolerance: Float = 5.0
        
        for dx in 0..<template.size.x {
            for dz in 0..<template.size.z {
                let height = heightMap.getHeight(x: x + dx, z: z + dz)
                if abs(height - baseHeight) > tolerance {
                    return false
                }
            }
        }
        
        // Check minimum height
        if baseHeight < heightMap.seaLevel + 5 {
            return false
        }
        
        return true
    }
 }

 struct ClimateModel {
    func getBiomeType(temperature: Float, moisture: Float, elevation: Float) -> BiomeType {
        // Elevation adjustment
        let adjustedTemp = temperature - (elevation / 1000.0) * 0.5
        
        // Biome determination matrix
        if adjustedTemp < 0.2 {
            if moisture < 0.3 {
                return .tundra
            } else {
                return .taiga
            }
        } else if adjustedTemp < 0.6 {
            if moisture < 0.3 {
                return .plains
            } else if moisture < 0.7 {
                return .forest
            } else {
                return .swamp
            }
        } else {
            if moisture < 0.3 {
                return .desert
            } else if moisture < 0.6 {
                return .plains
            } else {
                return .forest
            }
        }
    }
 }

