//
//  Core/Graphics/AssetLoader.swift
//  FinalStorm
//
//  Advanced asset loading system with format detection and optimization
//

import Foundation
import RealityKit
import simd

class AssetLoader {
    private let formatLoaders: [MeshFormat: MeshFormatLoader] = [
        .usdz: USDZLoader(),
        .usd: USDZLoader(),
        .obj: OBJLoader(),
        .gltf: GLTFLoader()
    ]
    
    func loadMesh(from url: URL, format: MeshFormat, lodLevel: Int?) async throws -> MeshResource {
        guard let loader = formatLoaders[format] else {
            throw AssetError.unsupportedFormat(format.rawValue)
        }
        
        return try await loader.loadMesh(from: url, lodLevel: lodLevel)
    }
    
    func detectFormat(from url: URL) -> MeshFormat {
        let ext = url.pathExtension.lowercased()
        return MeshFormat(rawValue: ext) ?? .obj
    }
    
    func getSupportedFormats() -> [MeshFormat] {
        return Array(formatLoaders.keys)
    }
}

// MARK: - Format Loaders

protocol MeshFormatLoader {
    func loadMesh(from url: URL, lodLevel: Int?) async throws -> MeshResource
    func getSupportedFeatures() -> Set<MeshFeature>
}

class USDZLoader: MeshFormatLoader {
    func loadMesh(from url: URL, lodLevel: Int?) async throws -> MeshResource {
        do {
            // Try RealityKit's native USDZ loading
            let entity = try await Entity.load(contentsOf: url)
            
            if let modelEntity = findModelEntity(in: entity) {
                return modelEntity.model!.mesh
            }
            
            throw AssetError.noMeshFound
        } catch {
            throw AssetError.loadingFailed(error.localizedDescription)
        }
    }
    
    func getSupportedFeatures() -> Set<MeshFeature> {
        return [.materials, .animations, .physics, .textures, .normals, .uvs]
    }
    
    private func findModelEntity(in entity: Entity) -> ModelEntity? {
        if let modelEntity = entity as? ModelEntity, modelEntity.model != nil {
            return modelEntity
        }
        
        for child in entity.children {
            if let found = findModelEntity(in: child) {
                return found
            }
        }
        
        return nil
    }
}

class OBJLoader: MeshFormatLoader {
    func loadMesh(from url: URL, lodLevel: Int?) async throws -> MeshResource {
        let content = try String(contentsOf: url)
        return try parseOBJ(content: content)
    }
    
    func getSupportedFeatures() -> Set<MeshFeature> {
        return [.materials, .textures, .normals, .uvs]
    }
    
    private func parseOBJ(content: String) throws -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            
            guard !parts.isEmpty else { continue }
            
            switch parts[0] {
            case "v": // Vertex
                if parts.count >= 4 {
                    let x = Float(parts[1]) ?? 0
                    let y = Float(parts[2]) ?? 0
                    let z = Float(parts[3]) ?? 0
                    vertices.append(SIMD3<Float>(x, y, z))
                }
                
            case "vn": // Normal
                if parts.count >= 4 {
                    let x = Float(parts[1]) ?? 0
                    let y = Float(parts[2]) ?? 0
                    let z = Float(parts[3]) ?? 0
                    normals.append(normalize(SIMD3<Float>(x, y, z)))
                }
                
            case "vt": // Texture coordinate
                if parts.count >= 3 {
                    let u = Float(parts[1]) ?? 0
                    let v = Float(parts[2]) ?? 0
                    uvs.append(SIMD2<Float>(u, v))
                }
                
            case "f": // Face
                try parseFace(parts: Array(parts[1...]), indices: &indices, vertices: vertices)
                
            default:
                continue
            }
        }
        
        return try createMeshResource(
            vertices: vertices,
            normals: normals,
            uvs: uvs,
            indices: indices
        )
    }
    
    private func parseFace(parts: [String], indices: inout [UInt32], vertices: [SIMD3<Float>]) throws {
        guard parts.count >= 3 else { throw AssetError.invalidFormat("Face must have at least 3 vertices") }
        
        var faceIndices: [UInt32] = []
        
        for part in parts {
            let components = part.components(separatedBy: "/")
            guard let vertexIndex = Int(components[0]) else {
                throw AssetError.invalidFormat("Invalid vertex index")
            }
            
            // OBJ indices are 1-based
            faceIndices.append(UInt32(vertexIndex - 1))
        }
        
        // Triangulate face (simple fan triangulation)
        for i in 1..<(faceIndices.count - 1) {
            indices.append(contentsOf: [faceIndices[0], faceIndices[i], faceIndices[i + 1]])
        }
    }
    
    private func createMeshResource(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        indices: [UInt32]
    ) throws -> MeshResource {
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        
        if !normals.isEmpty && normals.count == vertices.count {
            descriptor.normals = MeshBuffer(normals)
        }
        
        if !uvs.isEmpty && uvs.count == vertices.count {
            descriptor.textureCoordinates = MeshBuffer(uvs)
        }
        
        descriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [descriptor])
    }
}

class GLTFLoader: MeshFormatLoader {
    func loadMesh(from url: URL, lodLevel: Int?) async throws -> MeshResource {
        // GLTF loading would require a dedicated parser
        // For now, throw unsupported
        throw AssetError.unsupportedFormat("gltf")
    }
    
    func getSupportedFeatures() -> Set<MeshFeature> {
        return [.materials, .animations, .textures, .normals, .uvs, .physics]
    }
}

// MARK: - Asset Errors

enum AssetError: Error, LocalizedError {
    case unsupportedFormat(String)
    case noMeshFound
    case loadingFailed(String)
    case invalidFormat(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported mesh format: \(format)"
        case .noMeshFound:
            return "No mesh found in the loaded asset"
        case .loadingFailed(let reason):
            return "Failed to load asset: \(reason)"
        case .invalidFormat(let reason):
            return "Invalid file format: \(reason)"
        case .fileNotFound(let name):
            return "File not found: \(name)"
        }
    }
}
