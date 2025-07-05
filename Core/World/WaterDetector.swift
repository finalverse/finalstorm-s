//
//  Core/World/WaterDetector.swift
//  FinalStorm
//
//  Advanced water body detection and generation system
//

import Foundation
import simd

class WaterDetector {
    private let minimumWaterDepth: Float = -1.0
    private let minimumPoolSize: Int = 9 // Minimum 3x3 area
    
    func detectWaterBodies(
        heightmap: [[Float]],
        biome: BiomeType
    ) async -> [WaterBody] {
        
        var waterBodies: [WaterBody] = []
        let resolution = heightmap.count
        var visited: [[Bool]] = Array(repeating: Array(repeating: false, count: resolution), count: resolution)
        
        // Find all water areas using flood fill
        for z in 0..<resolution {
            for x in 0..<resolution {
                if !visited[z][x] && heightmap[z][x] < minimumWaterDepth {
                    let waterVertices = floodFillWater(
                        x: x, z: z,
                        heightmap: heightmap,
                        visited: &visited
                    )
                    
                    if waterVertices.count >= minimumPoolSize {
                        let waterType = determineWaterType(
                            vertices: waterVertices,
                            biome: biome,
                            heightmap: heightmap
                        )
                        
                        let worldVertices = convertToWorldCoordinates(
                            vertices: waterVertices,
                            heightmap: heightmap,
                            resolution: resolution
                        )
                        
                        let waterBody = WaterBody(type: waterType, vertices: worldVertices)
                        waterBodies.append(waterBody)
                    }
                }
            }
        }
        
        // Add biome-specific water features
        waterBodies.append(contentsOf: generateBiomeSpecificWater(biome: biome, heightmap: heightmap))
        
        return waterBodies
    }
    
    private func floodFillWater(
        x: Int, z: Int,
        heightmap: [[Float]],
        visited: inout [[Bool]]
    ) -> [(Int, Int)] {
        
        let resolution = heightmap.count
        var waterCells: [(Int, Int)] = []
        var stack: [(Int, Int)] = [(x, z)]
        
        while !stack.isEmpty {
            let (currentX, currentZ) = stack.removeLast()
            
            // Check bounds
            guard currentX >= 0 && currentX < resolution &&
                  currentZ >= 0 && currentZ < resolution &&
                  !visited[currentZ][currentX] &&
                  heightmap[currentZ][currentX] < minimumWaterDepth else {
                continue
            }
            
            visited[currentZ][currentX] = true
            waterCells.append((currentX, currentZ))
            
            // Add neighboring cells
            stack.append(contentsOf: [
                (currentX + 1, currentZ),
                (currentX - 1, currentZ),
                (currentX, currentZ + 1),
                (currentX, currentZ - 1)
            ])
        }
        
        return waterCells
    }
    
    private func determineWaterType(
        vertices: [(Int, Int)],
        biome: BiomeType,
        heightmap: [[Float]]
    ) -> WaterBody.WaterType {
        
        let area = vertices.count
        let avgDepth = vertices.reduce(0.0) { sum, vertex in
            sum + abs(heightmap[vertex.1][vertex.0])
        } / Float(vertices.count)
        
        // Determine water type based on size, depth, and biome
        switch biome {
        case .ocean:
            return .ocean
        case .swamp:
            return area > 50 ? .lake : .pond
        case .mountain:
            return avgDepth > 3.0 ? .lake : (area > 25 ? .lake : .pond)
        case .ethereal:
            return .harmonicPool
        case .corrupted:
            return .voidWater
        case .volcanic:
            return .hotspring
        default:
            if area > 100 {
                return .lake
            } else if area > 25 {
                return .pond
            } else {
                return .spring
            }
        }
    }
    
    private func convertToWorldCoordinates(
        vertices: [(Int, Int)],
        heightmap: [[Float]],
        resolution: Int
    ) -> [SIMD3<Float>] {
        
        let gridSize: Float = 100.0
        let vertexSpacing = gridSize / Float(resolution - 1)
        
        return vertices.map { (x, z) in
            let worldX = Float(x) * vertexSpacing
            let worldZ = Float(z) * vertexSpacing
            let height = heightmap[z][x]
            return SIMD3<Float>(worldX, height, worldZ)
        }
    }
    
    private func generateBiomeSpecificWater(
        biome: BiomeType,
        heightmap: [[Float]]
    ) -> [WaterBody] {
        
        var waterBodies: [WaterBody] = []
        
        switch biome {
        case .mountain:
            // Add mountain streams
            waterBodies.append(contentsOf: generateMountainStreams(heightmap: heightmap))
            
        case .forest:
            // Add forest springs
            waterBodies.append(contentsOf: generateForestSprings(heightmap: heightmap))
            
        case .ethereal:
            // Add harmonic pools
            waterBodies.append(contentsOf: generateHarmonicPools(heightmap: heightmap))
            
        case .volcanic:
            // Add hot springs
            waterBodies.append(contentsOf: generateHotSprings(heightmap: heightmap))
            
        default:
            break
        }
        
        return waterBodies
    }
    
    private func generateMountainStreams(heightmap: [[Float]]) -> [WaterBody] {
        var streams: [WaterBody] = []
        let resolution = heightmap.count
        
        // Find high elevation areas and create streams flowing downward
        for _ in 0..<3 { // Generate up to 3 streams
            let startX = Int.random(in: 0..<resolution)
            let startZ = Int.random(in: 0..<resolution)
            
            if heightmap[startZ][startX] > 10.0 { // High elevation
                let streamVertices = traceStreamPath(
                    startX: startX, startZ: startZ,
                    heightmap: heightmap
                )
                
                if streamVertices.count > 5 {
                    let stream = WaterBody(type: .stream, vertices: streamVertices)
                    streams.append(stream)
                }
            }
        }
        
        return streams
    }
    
    private func traceStreamPath(
        startX: Int, startZ: Int,
        heightmap: [[Float]]
    ) -> [SIMD3<Float>] {
        
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        let vertexSpacing = gridSize / Float(resolution - 1)
        
        var path: [SIMD3<Float>] = []
        var currentX = startX
        var currentZ = startZ
        var visited: Set<String> = []
        
        for _ in 0..<20 { // Maximum stream length
            let key = "\(currentX),\(currentZ)"
            if visited.contains(key) { break }
            visited.insert(key)
            
            let worldX = Float(currentX) * vertexSpacing
            let worldZ = Float(currentZ) * vertexSpacing
            let height = heightmap[currentZ][currentX] - 0.5 // Stream bed slightly lower
            
            path.append(SIMD3<Float>(worldX, height, worldZ))
            
            // Find lowest neighboring cell
            var nextX = currentX
            var nextZ = currentZ
            var lowestHeight = heightmap[currentZ][currentX]
            
            for dx in -1...1 {
                for dz in -1...1 {
                    let neighborX = currentX + dx
                    let neighborZ = currentZ + dz
                    
                    if neighborX >= 0 && neighborX < resolution &&
                       neighborZ >= 0 && neighborZ < resolution &&
                       heightmap[neighborZ][neighborX] < lowestHeight {
                        lowestHeight = heightmap[neighborZ][neighborX]
                        nextX = neighborX
                        nextZ = neighborZ
                    }
                }
            }
            
            // If no lower neighbor found, stream ends
            if nextX == currentX && nextZ == currentZ { break }
            
            currentX = nextX
            currentZ = nextZ
        }
        
        return path
    }
    
    private func generateForestSprings(heightmap: [[Float]]) -> [WaterBody] {
        var springs: [WaterBody] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        // Place a few small springs in the forest
        for _ in 0..<2 {
            let x = Int.random(in: 10..<(resolution-10))
            let z = Int.random(in: 10..<(resolution-10))
            
            // Create small circular spring
            let centerX = (Float(x) / Float(resolution)) * gridSize
            let centerZ = (Float(z) / Float(resolution)) * gridSize
            let height = heightmap[z][x] - 0.3
            
            var springVertices: [SIMD3<Float>] = []
            let radius: Float = 2.0
            let segments = 8
            
            for i in 0..<segments {
                let angle = Float(i) * 2.0 * Float.pi / Float(segments)
                let x = centerX + cos(angle) * radius
                let z = centerZ + sin(angle) * radius
                springVertices.append(SIMD3<Float>(x, height, z))
            }
            
            let spring = WaterBody(type: .spring, vertices: springVertices)
            springs.append(spring)
        }
        
        return springs
    }
    
    private func generateHarmonicPools(heightmap: [[Float]]) -> [WaterBody] {
        var pools: [WaterBody] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        // Create mystical harmonic pools
        let poolX = resolution / 2
        let poolZ = resolution / 2
        
        let centerX = (Float(poolX) / Float(resolution)) * gridSize
        let centerZ = (Float(poolZ) / Float(resolution)) * gridSize
        let height = heightmap[poolZ][poolX] - 1.0
        
        // Create hexagonal pool
        var poolVertices: [SIMD3<Float>] = []
        let radius: Float = 4.0
        
        for i in 0..<6 {
            let angle = Float(i) * Float.pi / 3.0
            let x = centerX + cos(angle) * radius
            let z = centerZ + sin(angle) * radius
            poolVertices.append(SIMD3<Float>(x, height, z))
        }
        
        let pool = WaterBody(type: .harmonicPool, vertices: poolVertices)
        pools.append(pool)
        
        return pools
    }
    
    private func generateHotSprings(heightmap: [[Float]]) -> [WaterBody] {
        var hotSprings: [WaterBody] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        // Place hot springs near high heat areas
        for _ in 0..<3 {
            let x = Int.random(in: 5..<(resolution-5))
            let z = Int.random(in: 5..<(resolution-5))
            
            let centerX = (Float(x) / Float(resolution)) * gridSize
            let centerZ = (Float(z) / Float(resolution)) * gridSize
            let height = heightmap[z][x] - 0.8
            
            // Create irregular hot spring shape
            var springVertices: [SIMD3<Float>] = []
            let baseRadius: Float = 3.0
            
            for i in 0..<12 {
                let angle = Float(i) * 2.0 * Float.pi / 12.0
                let radiusVariation = Float.random(in: 0.7...1.3)
                let radius = baseRadius * radiusVariation
                let x = centerX + cos(angle) * radius
                let z = centerZ + sin(angle) * radius
                springVertices.append(SIMD3<Float>(x, height, z))
            }
            
            let hotSpring = WaterBody(type: .hotspring, vertices: springVertices)
            hotSprings.append(hotSpring)
        }
        
        return hotSprings
    }
}
