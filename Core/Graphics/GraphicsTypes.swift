//
//  Core/Graphics/GraphicsTypes.swift
//  FinalStorm
//
//  Foundation types for the graphics system
//

import Foundation
import RealityKit
import simd

// MARK: - Graphics Configuration

struct GraphicsConfiguration {
    var renderingPipeline: RenderingPipeline
    var qualityLevel: QualityLevel
    var shadowQuality: ShadowQuality
    var textureQuality: TextureQuality
    var meshLODSettings: MeshLODSettings
    var particleSettings: ParticleSettings
    var lightingSettings: LightingSettings
    
    enum RenderingPipeline {
        case forward
        case deferred
        case clusteredForward
        case adaptive
    }
    
    enum QualityLevel: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case ultra = "Ultra"
        case adaptive = "Adaptive"
        
        var meshResolution: Int {
            switch self {
            case .low: return 32
            case .medium: return 64
            case .high: return 128
            case .ultra: return 256
            case .adaptive: return 128 // Base level
            }
        }
        
        var maxDrawCalls: Int {
            switch self {
            case .low: return 500
            case .medium: return 1000
            case .high: return 2000
            case .ultra: return 4000
            case .adaptive: return 1500
            }
        }
    }
    
    enum ShadowQuality {
        case off, low, medium, high, ultra
        
        var mapSize: Int {
            switch self {
            case .off: return 0
            case .low: return 512
            case .medium: return 1024
            case .high: return 2048
            case .ultra: return 4096
            }
        }
    }
    
    enum TextureQuality {
        case quarter, half, full, enhanced
        
        var maxResolution: Int {
            switch self {
            case .quarter: return 256
            case .half: return 512
            case .full: return 1024
            case .enhanced: return 2048
            }
        }
    }
    
    struct MeshLODSettings {
        var enableLOD: Bool = true
        var lodDistances: [Float] = [50, 100, 200, 500]
        var lodBias: Float = 1.0
        var maxLODLevel: Int = 4
    }
    
    struct ParticleSettings {
        var maxParticles: Int = 10000
        var enableGPUParticles: Bool = true
        var particleLOD: Bool = true
    }
    
    struct LightingSettings {
        var maxLights: Int = 32
        var enablePBR: Bool = true
        var enableIBL: Bool = true
        var enableSSAO: Bool = true
    }
}

// MARK: - Mesh Asset Types

protocol MeshAsset {
    var id: UUID { get }
    var name: String { get }
    var format: MeshFormat { get }
    var lodLevels: [MeshLODLevel] { get }
    var boundingBox: BoundingBox { get }
    var vertexCount: Int { get }
    var triangleCount: Int { get }
    var memoryFootprint: Int { get }
}

enum MeshFormat: String, CaseIterable {
    case usdz = "usdz"
    case usd = "usd"
    case obj = "obj"
    case fbx = "fbx"
    case dae = "dae"
    case gltf = "gltf"
    case procedural = "procedural"
    
    var supportedFeatures: Set<MeshFeature> {
        switch self {
        case .usdz, .usd:
            return [.materials, .animations, .physics, .textures, .normals, .uvs]
        case .obj:
            return [.materials, .textures, .normals, .uvs]
        case .fbx:
            return [.materials, .animations, .textures, .normals, .uvs, .bones]
        case .dae:
            return [.materials, .animations, .textures, .normals, .uvs]
        case .gltf:
            return [.materials, .animations, .textures, .normals, .uvs, .physics]
        case .procedural:
            return [.materials, .textures, .normals, .uvs, .physics]
        }
    }
}

enum MeshFeature {
    case materials, animations, physics, textures, normals, uvs, bones, morphTargets
}

struct MeshLODLevel {
    let level: Int
    let vertexCount: Int
    let distance: Float
    let mesh: MeshResource?
}

struct BoundingBox {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
    
    var center: SIMD3<Float> {
        return (min + max) * 0.5
    }
    
    var size: SIMD3<Float> {
        return max - min
    }
    
    var radius: Float {
        return simd_length(size) * 0.5
    }
}

// MARK: - Material System Types

protocol MaterialAsset {
    var id: UUID { get }
    var name: String { get }
    var type: MaterialType { get }
    var properties: MaterialProperties { get }
}

enum MaterialType {
    case pbr
    case unlit
    case toon
    case harmonyShader
    case corruptionShader
    case etherealShader
}

struct MaterialProperties {
    var baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var metallic: Float = 0.0
    var roughness: Float = 0.5
    var emission: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var normal: Float = 1.0
    var ao: Float = 1.0
    var textureScale: SIMD2<Float> = SIMD2<Float>(1, 1)
    var customProperties: [String: Any] = [:]
}
