//
//  Core/Graphics/MeshSystem.swift
//  FinalStorm
//
//  Sophisticated mesh management system for Finalverse
//

import Foundation
import RealityKit
import simd

// MARK: - Mesh Manager
@MainActor
class MeshManager: ObservableObject {
    static let shared = MeshManager()
    
    private var meshCache: [String: MeshResource] = [:]
    private var loadingTasks: [String: Task<MeshResource, Error>] = [:]
    
    private init() {}
    
    func loadMesh(named name: String, from bundle: Bundle = .main) async throws -> MeshResource {
        // Check cache first
        if let cachedMesh = meshCache[name] {
            return cachedMesh
        }
        
        // Check if already loading
        if let existingTask = loadingTasks[name] {
            return try await existingTask.value
        }
        
        // Start loading
        let loadingTask = Task<MeshResource, Error> {
            let mesh = try await loadMeshFromBundle(named: name, bundle: bundle)
            await MainActor.run {
                meshCache[name] = mesh
                loadingTasks.removeValue(forKey: name)
            }
            return mesh
        }
        
        loadingTasks[name] = loadingTask
        return try await loadingTask.value
    }
    
    func loadMesh(from url: URL) async throws -> MeshResource {
        let cacheKey = url.absoluteString
        
        if let cachedMesh = meshCache[cacheKey] {
            return cachedMesh
        }
        
        if let existingTask = loadingTasks[cacheKey] {
            return try await existingTask.value
        }
        
        let loadingTask = Task<MeshResource, Error> {
            let mesh = try await loadMeshFromURL(url)
            await MainActor.run {
                meshCache[cacheKey] = mesh
                loadingTasks.removeValue(forKey: cacheKey)
            }
            return mesh
        }
        
        loadingTasks[cacheKey] = loadingTask
        return try await loadingTask.value
    }
    
    private func loadMeshFromBundle(named name: String, bundle: Bundle) async throws -> MeshResource {
        // Try different formats
        let extensions = ["usdz", "usd", "obj", "dae"]
        
        for ext in extensions {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return try await loadMeshFromURL(url)
            }
        }
        
        // Fallback to procedural generation
        return generateFallbackMesh(for: name)
    }
    
    private func loadMeshFromURL(_ url: URL) async throws -> MeshResource {
        // Load based on file extension
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "usdz", "usd":
            return try await loadUSDZMesh(from: url)
        case "obj":
            return try await loadOBJMesh(from: url)
        default:
            throw MeshError.unsupportedFormat(ext)
        }
    }
    
    private func loadUSDZMesh(from url: URL) async throws -> MeshResource {
        // Try to load USDZ using RealityKit's entity loading
        do {
            let entity = try await Entity.load(contentsOf: url)
            if let modelEntity = entity.findEntity(named: "model") as? ModelEntity,
               let modelComponent = modelEntity.components[ModelComponent.self] {
                return modelComponent.mesh
            }
            
            // If no named model, find first ModelComponent
            if let modelEntity = entity.children.first(where: { $0 is ModelEntity }) as? ModelEntity,
               let modelComponent = modelEntity.components[ModelComponent.self] {
                return modelComponent.mesh
            }
            
            throw MeshError.noMeshFound
        } catch {
            throw MeshError.loadingFailed(error)
        }
    }
    
    private func loadOBJMesh(from url: URL) async throws -> MeshResource {
        // Custom OBJ loader
        let objLoader = OBJLoader()
        return try await objLoader.loadMesh(from: url)
    }
    
    private func generateFallbackMesh(for name: String) -> MeshResource {
        // Generate procedural mesh based on name
        switch name.lowercased() {
        case "avatar_base", "character":
            return MeshResource.generateBox(size: [0.5, 1.8, 0.3])
        case "harmony_blossom", "flower":
            return createFlowerMesh()
        case "crystal", "gem":
            return createCrystalMesh()
        case "tree":
            return createTreeMesh()
        default:
            return MeshResource.generateBox(size: [1, 1, 1])
        }
    }
    
    // MARK: - Procedural Mesh Generation
    private func createFlowerMesh() -> MeshResource {
        // Create a simple flower shape
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Center
        vertices.append([0, 0, 0])
        
        // Petals (8 petals around center)
        let petalCount = 8
        for i in 0..<petalCount {
            let angle = Float(i) * 2 * .pi / Float(petalCount)
            vertices.append([cos(angle) * 0.3, 0.1, sin(angle) * 0.3])
            vertices.append([cos(angle) * 0.5, 0, sin(angle) * 0.5])
        }
        
        // Create triangles
        for i in 0..<petalCount {
            let next = (i + 1) % petalCount
            let center: UInt32 = 0
            let inner1 = UInt32(1 + i * 2)
            let outer1 = UInt32(2 + i * 2)
            let inner2 = UInt32(1 + next * 2)
            
            // Inner triangle
            indices.append(contentsOf: [center, inner1, inner2])
            // Petal triangle
            indices.append(contentsOf: [inner1, outer1, inner2])
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return MeshResource.generateBox(size: [0.3, 0.1, 0.3])
        }
    }
    
    private func createCrystalMesh() -> MeshResource {
        // Create a crystal/gem shape
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Bottom point
        vertices.append([0, -0.5, 0])
        
        // Middle ring
        let sides = 6
        for i in 0..<sides {
            let angle = Float(i) * 2 * .pi / Float(sides)
            vertices.append([cos(angle) * 0.3, 0, sin(angle) * 0.3])
        }
        
        // Top point
        vertices.append([0, 0.5, 0])
        
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
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return MeshResource.generateBox(size: [0.3, 1.0, 0.3])
        }
    }
    
    private func createTreeMesh() -> MeshResource {
        // Simple tree: trunk + crown
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Trunk (cylinder)
        let trunkSides = 8
        let trunkHeight: Float = 2.0
        let trunkRadius: Float = 0.2
        
        // Bottom ring
        for i in 0..<trunkSides {
            let angle = Float(i) * 2 * .pi / Float(trunkSides)
            vertices.append([cos(angle) * trunkRadius, 0, sin(angle) * trunkRadius])
        }
        
        // Top ring
        for i in 0..<trunkSides {
            let angle = Float(i) * 2 * .pi / Float(trunkSides)
            vertices.append([cos(angle) * trunkRadius, trunkHeight, sin(angle) * trunkRadius])
        }
        
        // Trunk triangles
        for i in 0..<trunkSides {
            let next = (i + 1) % trunkSides
            let bottom1 = UInt32(i)
            let bottom2 = UInt32(next)
            let top1 = UInt32(i + trunkSides)
            let top2 = UInt32(next + trunkSides)
            
            indices.append(contentsOf: [bottom1, top1, bottom2])
            indices.append(contentsOf: [bottom2, top1, top2])
        }
        
        // Crown (simple sphere approximation)
        let crownCenter = SIMD3<Float>(0, trunkHeight + 1, 0)
        let crownRadius: Float = 1.5
        let crownBaseIndex = UInt32(vertices.count)
        
        vertices.append(crownCenter)
        
        // Crown ring
        let crownSides = 12
        for i in 0..<crownSides {
            let angle = Float(i) * 2 * .pi / Float(crownSides)
            vertices.append([
                cos(angle) * crownRadius,
                trunkHeight + 0.5,
                sin(angle) * crownRadius
            ])
        }
        
        // Crown triangles
        for i in 0..<crownSides {
            let next = (i + 1) % crownSides
            indices.append(contentsOf: [
                crownBaseIndex,
                crownBaseIndex + 1 + UInt32(i),
                crownBaseIndex + 1 + UInt32(next)
            ])
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return MeshResource.generateBox(size: [3, 4, 3])
        }
    }
}

// MARK: - OBJ Loader
class OBJLoader {
    func loadMesh(from url: URL) async throws -> MeshResource {
        let content = try String(contentsOf: url)
        return try parseMesh(from: content)
    }
    
    private func parseMesh(from objContent: String) throws -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        
        let lines = objContent.components(separatedBy: .newlines)
        
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            guard !parts.isEmpty else { continue }
            
            switch parts[0] {
            case "v": // Vertex
                if parts.count >= 4 {
                    let x = Float(parts[1]) ?? 0
                    let y = Float(parts[2]) ?? 0
                    let z = Float(parts[3]) ?? 0
                    vertices.append([x, y, z])
                }
                
            case "vn": // Normal
                if parts.count >= 4 {
                    let x = Float(parts[1]) ?? 0
                    let y = Float(parts[2]) ?? 0
                    let z = Float(parts[3]) ?? 0
                    normals.append([x, y, z])
                }
                
            case "vt": // Texture coordinate
                if parts.count >= 3 {
                    let u = Float(parts[1]) ?? 0
                    let v = Float(parts[2]) ?? 0
                    uvs.append([u, v])
                }
                
            case "f": // Face
                for i in 1..<parts.count {
                    let faceData = parts[i].components(separatedBy: "/")
                    if let vertexIndex = Int(faceData[0]) {
                        indices.append(UInt32(vertexIndex - 1)) // OBJ indices are 1-based
                    }
                }
                
            default:
                continue
            }
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        if !normals.isEmpty {
            descriptor.normals = MeshBuffer(normals)
        }
        if !uvs.isEmpty {
            descriptor.textureCoordinates = MeshBuffer(uvs)
        }
        descriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [descriptor])
    }
}

// MARK: - Mesh Factory
struct MeshFactory {
    static func createAvatarMesh(for appearance: AvatarAppearance) async -> MeshResource {
        // Generate avatar mesh based on appearance
        let meshManager = MeshManager.shared
        
        do {
            return try await meshManager.loadMesh(named: "avatar_\(appearance.bodyShape.rawValue)")
        } catch {
            // Fallback to procedural generation
            return generateProceduralAvatar(appearance: appearance)
        }
    }
    
    static func createTerrainMesh(from heightmap: [[Float]]) async throws -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let gridSize = heightmap.count
        let scale: Float = 1.0      // 1 meter per grid unit
        
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
                
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }
        
        // Create mesh descriptor
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [descriptor])
    }
    
    private static func generateProceduralAvatar(appearance: AvatarAppearance) -> MeshResource {
        let scale = appearance.bodyShape.scaleModifiers
        return MeshResource.generateBox(size: [0.5 * scale.x, 1.8 * scale.y, 0.3 * scale.z])
    }
    
    private static func calculateNormal(x: Int, z: Int, heightmap: [[Float]]) -> SIMD3<Float> {
        let gridSize = heightmap.count
        
        let left = x > 0 ? heightmap[z][x-1] : heightmap[z][x]
        let right = x < gridSize-1 ? heightmap[z][x+1] : heightmap[z][x]
        let up = z > 0 ? heightmap[z-1][x] : heightmap[z][x]
        let down = z < gridSize-1 ? heightmap[z+1][x] : heightmap[z][x]
        
        let dx = SIMD3<Float>(2.0, right - left, 0.0)
        let dz = SIMD3<Float>(0.0, down - up, 2.0)
        
        return normalize(cross(dz, dx))
    }
}

// MARK: - Error Types
enum MeshError: Error {
    case unsupportedFormat(String)
    case noMeshFound
    case loadingFailed(Error)
    case invalidOBJFormat
    
    var localizedDescription: String {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported mesh format: \(format)"
        case .noMeshFound:
            return "No mesh found in the loaded entity"
        case .loadingFailed(let error):
            return "Failed to load mesh: \(error.localizedDescription)"
        case .invalidOBJFormat:
            return "Invalid OBJ file format"
        }
    }
}
