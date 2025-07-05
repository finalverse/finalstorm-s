//
//  Core/Graphics/ProceduralMeshGenerator.swift
//  FinalStorm
//
//  Advanced procedural mesh generation system
//

import Foundation
import RealityKit
import simd

class ProceduralMeshGenerator {
    private var quality: GraphicsConfiguration.QualityLevel = .high
    
    func updateQuality(_ newQuality: GraphicsConfiguration.QualityLevel) {
        quality = newQuality
    }
    
    func generateMesh(type: ProceduralMeshType, parameters: [String: Any]) async -> MeshResource {
        return await Task {
            switch type {
            case .cube:
                return generateCube(parameters: parameters)
            case .sphere:
                return generateSphere(parameters: parameters)
            case .cylinder:
                return generateCylinder(parameters: parameters)
            case .plane:
                return generatePlane(parameters: parameters)
            case .avatarBase, .character:
                return generateAvatarBase(parameters: parameters)
            case .harmonyBlossom, .flower:
                return generateFlower(parameters: parameters)
            case .crystal, .gem:
                return generateCrystal(parameters: parameters)
            case .tree:
                return generateTree(parameters: parameters)
            case .rock:
                return generateRock(parameters: parameters)
            case .building:
                return generateBuilding(parameters: parameters)
            case .terrain:
                return generateTerrain(parameters: parameters)
            }
        }.value
    }
    
    // MARK: - Basic Shapes
    
    private func generateCube(parameters: [String: Any]) -> MeshResource {
        let size = parameters["size"] as? SIMD3<Float> ?? SIMD3<Float>(1, 1, 1)
        return MeshResource.generateBox(size: size)
    }
    
    private func generateSphere(parameters: [String: Any]) -> MeshResource {
        let radius = parameters["radius"] as? Float ?? 0.5
        let resolution = getResolutionForQuality()
        return MeshResource.generateSphere(radius: radius, radialSegments: resolution, verticalSegments: resolution)
    }
    
    private func generateCylinder(parameters: [String: Any]) -> MeshResource {
        let height = parameters["height"] as? Float ?? 1.0
        let radius = parameters["radius"] as? Float ?? 0.5
        let resolution = getResolutionForQuality()
        return MeshResource.generateCylinder(height: height, radius: radius, radialSegments: resolution)
    }
    
    private func generatePlane(parameters: [String: Any]) -> MeshResource {
        let width = parameters["width"] as? Float ?? 1.0
        let height = parameters["height"] as? Float ?? 1.0
        return MeshResource.generatePlane(width: width, height: height)
    }
    
    // MARK: - Complex Shapes
    
    private func generateAvatarBase(parameters: [String: Any]) -> MeshResource {
        let height = parameters["height"] as? Float ?? 1.8
        let width = parameters["width"] as? Float ?? 0.5
        let depth = parameters["depth"] as? Float ?? 0.3
        
        // Create a humanoid-like shape with head, torso, arms, legs
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Simplified humanoid shape
        let bodyHeight = height * 0.6
        let headHeight = height * 0.15
        let legHeight = height * 0.4
        
        // Torso
        addBox(to: &vertices, indices: &indices,
               center: SIMD3<Float>(0, bodyHeight/2, 0),
               size: SIMD3<Float>(width, bodyHeight, depth))
        
        // Head
        let headY = bodyHeight + headHeight/2
        addBox(to: &vertices, indices: &indices,
               center: SIMD3<Float>(0, headY, 0),
               size: SIMD3<Float>(width*0.7, headHeight, depth*0.7))
        
        // Arms
        let armWidth = width * 0.2
        let armHeight = bodyHeight * 0.8
        let armY = bodyHeight * 0.7
        
        addBox(to: &vertices, indices: &indices,
               center: SIMD3<Float>(-width*0.6, armY, 0),
               size: SIMD3<Float>(armWidth, armHeight, depth*0.5))
        
        addBox(to: &vertices, indices: &indices,
               center: SIMD3<Float>(width*0.6, armY, 0),
               size: SIMD3<Float>(armWidth, armHeight, depth*0.5))
        
        // Legs
        let legWidth = width * 0.3
        let legY = -legHeight/2
        
        addBox(to: &vertices, indices: &indices,
               center: SIMD3<Float>(-width*0.2, legY, 0),
               size: SIMD3<Float>(legWidth, legHeight, depth*0.8))
        
        addBox(to: &vertices, indices: &indices,
               center: SIMD3<Float>(width*0.2, legY, 0),
               size: SIMD3<Float>(legWidth, legHeight, depth*0.8))
        
        return createMeshFromVertices(vertices: vertices, indices: indices)
    }
    
    private func generateFlower(parameters: [String: Any]) -> MeshResource {
        let petalCount = parameters["petalCount"] as? Int ?? 8
        let size = parameters["size"] as? Float ?? 0.3
        
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Center
        vertices.append(SIMD3<Float>(0, 0, 0))
        
        // Petals
        for i in 0..<petalCount {
            let angle = Float(i) * 2 * .pi / Float(petalCount)
            let petalTip = SIMD3<Float>(cos(angle) * size, 0.1, sin(angle) * size)
            let petalBase = SIMD3<Float>(cos(angle) * size * 0.5, 0, sin(angle) * size * 0.5)
            
            vertices.append(petalBase)
            vertices.append(petalTip)
        }
        
        // Create petal triangles
        for i in 0..<petalCount {
            let next = (i + 1) % petalCount
            let center: UInt32 = 0
            let currentBase = UInt32(1 + i * 2)
            let currentTip = UInt32(2 + i * 2)
            let nextBase = UInt32(1 + next * 2)
            
            // Center to base triangles
            indices.append(contentsOf: [center, currentBase, nextBase])
            
            // Petal triangles
            indices.append(contentsOf: [currentBase, currentTip, nextBase])
        }
        
        return createMeshFromVertices(vertices: vertices, indices: indices)
    }
    
    private func generateCrystal(parameters: [String: Any]) -> MeshResource {
        let height = parameters["height"] as? Float ?? 1.0
        let baseRadius = parameters["baseRadius"] as? Float ?? 0.3
        let sides = parameters["sides"] as? Int ?? 6
        
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Bottom point
        vertices.append(SIMD3<Float>(0, -height * 0.3, 0))
        
        // Base ring
        for i in 0..<sides {
            let angle = Float(i) * 2 * .pi / Float(sides)
            vertices.append(SIMD3<Float>(cos(angle) * baseRadius, 0, sin(angle) * baseRadius))
        }
        
        // Top point
        vertices.append(SIMD3<Float>(0, height * 0.7, 0))
        
        // Bottom triangles
        for i in 0..<sides {
            let next = (i + 1) % sides
            indices.append(contentsOf: [0, UInt32(1 + i), UInt32(1 + next)])
        }
        
        // Top triangles
        let topIndex = UInt32(1 + sides)
        for i in 0..<sides {
            let next = (i + 1) % sides
            indices.append(contentsOf: [topIndex, UInt32(1 + next), UInt32(1 + i)])
        }
        
        return createMeshFromVertices(vertices: vertices, indices: indices)
    }
    
    private func generateTree(parameters: [String: Any]) -> MeshResource {
        let height = parameters["height"] as? Float ?? 4.0
        let trunkRadius = parameters["trunkRadius"] as? Float ?? 0.2
        let crownRadius = parameters["crownRadius"] as? Float ?? 1.5
        
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        let trunkHeight = height * 0.5
        let crownHeight = height * 0.5
        let resolution = getResolutionForQuality()
        
        // Generate trunk (cylinder)
        generateCylinderVertices(
            vertices: &vertices, indices: &indices,
            center: SIMD3<Float>(0, trunkHeight/2, 0),
            radius: trunkRadius, height: trunkHeight,
            segments: resolution
        )
        
        // Generate crown (sphere)
        generateSphereVertices(
            vertices: &vertices, indices: &indices,
            center: SIMD3<Float>(0, trunkHeight + crownHeight/2, 0),
            radius: crownRadius,
            segments: resolution
        )
        
        return createMeshFromVertices(vertices: vertices, indices: indices)
    }
    
    private func generateRock(parameters: [String: Any]) -> MeshResource {
        let size = parameters["size"] as? Float ?? 1.0
        let roughness = parameters["roughness"] as? Float ?? 0.3
        
        // Start with a sphere and deform it for rock-like appearance
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        let resolution = getResolutionForQuality()
        
        // Generate sphere vertices with random deformation
        for v in 0...resolution {
            for u in 0...resolution {
                let phi = Float(v) * .pi / Float(resolution)
                let theta = Float(u) * 2 * .pi / Float(resolution)
                
                let radius = size * (1.0 + roughness * (Float.random(in: -1...1)))
                
                let x = radius * sin(phi) * cos(theta)
                let y = radius * cos(phi)
                let z = radius * sin(phi) * sin(theta)
                
                vertices.append(SIMD3<Float>(x, y, z))
            }
        }
        
        // Generate indices for sphere topology
        for v in 0..<resolution {
            for u in 0..<resolution {
                let current = UInt32(v * (resolution + 1) + u)
                let next = current + 1
                let below = UInt32((v + 1) * (resolution + 1) + u)
                let belowNext = below + 1
                
                indices.append(contentsOf: [current, below, next])
                indices.append(contentsOf: [next, below, belowNext])
            }
        }
        
        return createMeshFromVertices(vertices: vertices, indices: indices)
    }
    
    private func generateBuilding(parameters: [String: Any]) -> MeshResource {
        let width = parameters["width"] as? Float ?? 3.0
        let height = parameters["height"] as? Float ?? 6.0
        let depth = parameters["depth"] as? Float ?? 3.0
        let floors = parameters["floors"] as? Int ?? 3
        
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        let floorHeight = height / Float(floors)
        
        // Generate each floor
        for floor in 0..<floors {
            let floorY = Float(floor) * floorHeight
            let floorSize = SIMD3<Float>(width, floorHeight, depth)
            let floorCenter = SIMD3<Float>(0, floorY + floorHeight/2, 0)
            
            addBox(to: &vertices, indices: &indices, center: floorCenter, size: floorSize)
        }
        
        return createMeshFromVertices(vertices: vertices, indices: indices)
    }
    
    private func generateTerrain(parameters: [String: Any]) -> MeshResource {
        let size = parameters["size"] as? Int ?? 32
        let height = parameters["height"] as? Float ?? 10.0
        let seed = parameters["seed"] as? UInt32 ?? UInt32.random(in: 0...UInt32.max)
        
        // Generate heightmap
        var heightmap: [[Float]] = []
        for z in 0..<size {
            var row: [Float] = []
            for x in 0..<size {
                let h = generateHeightValue(x: x, z: z, size: size, seed: seed) * height
                row.append(h)
            }
            heightmap.append(row)
        }
        
        // Convert heightmap to mesh
        return createTerrainMesh(from: heightmap)
    }
    
    // MARK: - Helper Methods
    
    private func getResolutionForQuality() -> Int {
        switch quality {
        case .low: return 8
        case .medium: return 16
        case .high: return 24
        case .ultra: return 32
        case .adaptive: return 20
        }
    }
    
    private func addBox(to vertices: inout [SIMD3<Float>], indices: inout [UInt32],
                       center: SIMD3<Float>, size: SIMD3<Float>) {
        let baseIndex = UInt32(vertices.count)
        let half = size * 0.5
        
        // Add 8 vertices for a box
        let positions: [SIMD3<Float>] = [
            center + SIMD3<Float>(-half.x, -half.y, -half.z), // 0
            center + SIMD3<Float>( half.x, -half.y, -half.z), // 1
            center + SIMD3<Float>( half.x,  half.y, -half.z), // 2
            center + SIMD3<Float>(-half.x,  half.y, -half.z), // 3
            center + SIMD3<Float>(-half.x, -half.y,  half.z), // 4
            center + SIMD3<Float>( half.x, -half.y,  half.z), // 5
            center + SIMD3<Float>( half.x,  half.y,  half.z), // 6
            center + SIMD3<Float>(-half.x,  half.y,  half.z)  // 7
        ]
        
        vertices.append(contentsOf: positions)
        
        // Add 12 triangles (2 per face, 6 faces)
        let boxIndices: [UInt32] = [
            // Front face
            0, 1, 2,  0, 2, 3,
            // Back face
            4, 6, 5,  4, 7, 6,
            // Left face
            0, 3, 7,  0, 7, 4,
            // Right face
            1, 5, 6,  1, 6, 2,
            // Top face
            3, 2, 6,  3, 6, 7,
            // Bottom face
            0, 4, 5,  0, 5, 1
        ]
        
        // Add indices with base offset
        for index in boxIndices {
            indices.append(baseIndex + index)
        }
    }
    
    private func generateCylinderVertices(
        vertices: inout [SIMD3<Float>], indices: inout [UInt32],
        center: SIMD3<Float>, radius: Float, height: Float, segments: Int
    ) {
        let baseIndex = UInt32(vertices.count)
        let halfHeight = height * 0.5
        
        // Bottom center
        vertices.append(center + SIMD3<Float>(0, -halfHeight, 0))
        
        // Bottom ring
        for i in 0..<segments {
            let angle = Float(i) * 2 * .pi / Float(segments)
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            vertices.append(center + SIMD3<Float>(x, -halfHeight, z))
        }
        
        // Top ring
        for i in 0..<segments {
            let angle = Float(i) * 2 * .pi / Float(segments)
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            vertices.append(center + SIMD3<Float>(x, halfHeight, z))
        }
        
        // Top center
        vertices.append(center + SIMD3<Float>(0, halfHeight, 0))
        
        // Bottom face triangles
        for i in 0..<segments {
            let next = (i + 1) % segments
            indices.append(contentsOf: [
                baseIndex, // Bottom center
                baseIndex + 1 + UInt32(i), // Current bottom
                baseIndex + 1 + UInt32(next) // Next bottom
            ])
        }
        
        // Side triangles
        for i in 0..<segments {
            let next = (i + 1) % segments
            let bottomCurrent = baseIndex + 1 + UInt32(i)
            let bottomNext = baseIndex + 1 + UInt32(next)
            let topCurrent = baseIndex + 1 + UInt32(segments) + UInt32(i)
            let topNext = baseIndex + 1 + UInt32(segments) + UInt32(next)
            
            indices.append(contentsOf: [bottomCurrent, topCurrent, bottomNext])
            indices.append(contentsOf: [bottomNext, topCurrent, topNext])
        }
        
        // Top face triangles
        let topCenter = baseIndex + 1 + UInt32(segments * 2)
        for i in 0..<segments {
            let next = (i + 1) % segments
            indices.append(contentsOf: [
                topCenter, // Top center
                baseIndex + 1 + UInt32(segments) + UInt32(next), // Next top
                baseIndex + 1 + UInt32(segments) + UInt32(i) // Current top
            ])
        }
    }
    
    private func generateSphereVertices(
        vertices: inout [SIMD3<Float>], indices: inout [UInt32],
        center: SIMD3<Float>, radius: Float, segments: Int
    ) {
        let baseIndex = UInt32(vertices.count)
        
        // Generate sphere vertices
        for v in 0...segments {
            for u in 0...segments {
                let phi = Float(v) * .pi / Float(segments)
                let theta = Float(u) * 2 * .pi / Float(segments)
                
                let x = radius * sin(phi) * cos(theta)
                let y = radius * cos(phi)
                let z = radius * sin(phi) * sin(theta)
                
                vertices.append(center + SIMD3<Float>(x, y, z))
            }
        }
        
        // Generate sphere indices
        for v in 0..<segments {
            for u in 0..<segments {
                let current = baseIndex + UInt32(v * (segments + 1) + u)
                let next = current + 1
                let below = baseIndex + UInt32((v + 1) * (segments + 1) + u)
                let belowNext = below + 1
                
                indices.append(contentsOf: [current, below, next])
                indices.append(contentsOf: [next, below, belowNext])
            }
        }
    }
    
    private func generateHeightValue(x: Int, z: Int, size: Int, seed: UInt32) -> Float {
        // Simple noise function for terrain generation
        let fx = Float(x) / Float(size)
        let fz = Float(z) / Float(size)
        
        // Multiple octaves of noise
        var height: Float = 0.0
        var amplitude: Float = 1.0
        var frequency: Float = 0.1
        
        for _ in 0..<4 {
            height += amplitude * sin(fx * frequency * .pi) * cos(fz * frequency * .pi)
            amplitude *= 0.5
            frequency *= 2.0
        }
        
        return height * 0.5 + 0.5 // Normalize to 0-1
    }
    
    private func createTerrainMesh(from heightmap: [[Float]]) -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        
        let resolution = heightmap.count
        let scale: Float = 1.0
        
        // Generate vertices
        for z in 0..<resolution {
            for x in 0..<resolution {
                let height = heightmap[z][x]
                let worldX = Float(x) * scale
                let worldZ = Float(z) * scale
                
                vertices.append(SIMD3<Float>(worldX, height, worldZ))
                uvs.append(SIMD2<Float>(Float(x) / Float(resolution - 1), Float(z) / Float(resolution - 1)))
                
                // Calculate normal
                let normal = calculateTerrainNormal(x: x, z: z, heightmap: heightmap)
                normals.append(normal)
            }
        }
        
        // Generate indices
        for z in 0..<(resolution - 1) {
            for x in 0..<(resolution - 1) {
                let topLeft = UInt32(z * resolution + x)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((z + 1) * resolution + x)
                let bottomRight = bottomLeft + 1
                
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return MeshResource.generateBox(size: [1, 1, 1])
        }
    }
    
    private func calculateTerrainNormal(x: Int, z: Int, heightmap: [[Float]]) -> SIMD3<Float> {
        let resolution = heightmap.count
        
        let left = x > 0 ? heightmap[z][x-1] : heightmap[z][x]
        let right = x < resolution-1 ? heightmap[z][x+1] : heightmap[z][x]
        let up = z > 0 ? heightmap[z-1][x] : heightmap[z][x]
        let down = z < resolution-1 ? heightmap[z+1][x] : heightmap[z][x]
        
        let dx = SIMD3<Float>(2.0, right - left, 0.0)
        let dz = SIMD3<Float>(0.0, down - up, 2.0)
        
        return normalize(cross(dz, dx))
    }
    
    private func createMeshFromVertices(vertices: [SIMD3<Float>], indices: [UInt32]) -> MeshResource {
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("Failed to create mesh: \(error)")
            return MeshResource.generateBox(size: [1, 1, 1])
        }
    }
 }
