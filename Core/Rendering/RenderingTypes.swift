//
//  Core/Rendering/RenderingTypes.swift
//  FinalStorm
//
//  Low-level rendering pipeline types and configurations
//

import Foundation
import RealityKit
import simd

// MARK: - Rendering Pipeline

enum RenderingBackend {
    case realityKit
    case metal
    case custom
}

struct RenderingConfiguration {
    var backend: RenderingBackend = .realityKit
    var renderScale: Float = 1.0
    var enableHDR: Bool = true
    var enableMSAA: Bool = true
    var msaaSamples: Int = 4
    var shadowConfiguration: ShadowConfiguration
    var lightingConfiguration: LightingConfiguration
    var postProcessingChain: [PostProcessingEffect]
    
    struct ShadowConfiguration {
        var enableShadows: Bool = true
        var shadowMapSize: Int = 2048
        var cascadeCount: Int = 4
        var shadowDistance: Float = 100.0
    }
    
    struct LightingConfiguration {
        var maxDirectionalLights: Int = 4
        var maxPointLights: Int = 32
        var maxSpotLights: Int = 16
        var enableIBL: Bool = true
        var enableSSAO: Bool = true
    }
}

enum PostProcessingEffect {
    case bloom(intensity: Float)
    case tonemap(exposure: Float)
    case colorGrading(lut: String)
    case fxaa
    case taa
    case harmonyEffect(strength: Float)
    case corruptionEffect(intensity: Float)
}

// MARK: - Render Passes

protocol RenderPass {
    var name: String { get }
    var isEnabled: Bool { get set }
    func execute(context: RenderContext) async throws
}

struct RenderContext {
    let commandBuffer: Any // Would be MTLCommandBuffer in Metal
    let renderTargets: [RenderTarget]
    let camera: CameraData
    let scene: SceneData
    let deltaTime: TimeInterval
}

struct RenderTarget {
    let width: Int
    let height: Int
    let format: PixelFormat
    let usage: RenderTargetUsage
}

enum PixelFormat {
    case rgba8
    case rgba16f
    case rgba32f
    case depth32f
    case depth24stencil8
}

enum RenderTargetUsage {
    case colorAttachment
    case depthAttachment
    case texture
    case storage
}

struct CameraData {
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let projectionMatrix: simd_float4x4
    let viewMatrix: simd_float4x4
    let nearPlane: Float
    let farPlane: Float
    let fieldOfView: Float
}

struct SceneData {
    let renderables: [Renderable]
    let lights: [LightData]
    let environmentData: EnvironmentData
}

protocol Renderable {
    var mesh: MeshResource { get }
    var material: Material { get }
    var transform: simd_float4x4 { get }
    var boundingBox: BoundingBox { get }
    var renderingLayer: RenderingLayer { get }
}

enum RenderingLayer: Int {
    case opaque = 0
    case transparent = 1
    case ui = 2
    case debug = 3
}

struct LightData {
    let type: LightType
    let position: SIMD3<Float>
    let direction: SIMD3<Float>
    let color: SIMD3<Float>
    let intensity: Float
    let range: Float
    let spotAngle: Float
    
    enum LightType {
        case directional
        case point
        case spot
        case area
    }
}

struct EnvironmentData {
    let skybox: String?
    let ambientColor: SIMD3<Float>
    let fogColor: SIMD3<Float>
    let fogDensity: Float
    let harmonyLevel: Float
}
