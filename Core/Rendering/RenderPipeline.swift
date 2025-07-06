//
// File Path: Core/Rendering/RenderPipeline.swift
// Description: Advanced rendering pipeline for FinalStorm
// Manages the complete rendering process with multiple passes and effects
//

import Foundation
import Metal
import MetalKit
import simd

class RenderPipeline {
    // MARK: - Properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let shaderLibrary: ShaderLibrary
    
    // Render Passes
    private var shadowPass: ShadowRenderPass!
    private var geometryPass: GeometryRenderPass!
    private var lightingPass: LightingRenderPass!
    private var postProcessPass: PostProcessRenderPass!
    private var uiPass: UIRenderPass!
    
    // Frame Data
    private var frameData = FrameData()
    private var renderStats = RenderStatistics()
    
    // Resources
    private let bufferPool: BufferPool
    private let textureCache: TextureCache
    private let meshCache: MeshCache
    
    // Performance
    private(set) var currentFPS: Double = 0
    private(set) var gpuUsage: Float = 0
    private var frameTimer = FrameTimer()
    
    // Settings
    var renderSettings = RenderSettings()
    
    // MARK: - Initialization
    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = ShaderLibrary(device: device)
        self.bufferPool = BufferPool(device: device)
        self.textureCache = TextureCache(device: device)
        self.meshCache = MeshCache(device: device)
        
        setupRenderPasses()
    }
    
    private func setupRenderPasses() {
        // Initialize render passes
        shadowPass = ShadowRenderPass(
            device: device,
            shaderLibrary: shaderLibrary,
            size: renderSettings.shadowMapSize
        )
        
        geometryPass = GeometryRenderPass(
            device: device,
            shaderLibrary: shaderLibrary
        )
        
        lightingPass = LightingRenderPass(
            device: device,
            shaderLibrary: shaderLibrary
        )
        
        postProcessPass = PostProcessRenderPass(
            device: device,
            shaderLibrary: shaderLibrary
        )
        
        uiPass = UIRenderPass(
            device: device,
            shaderLibrary: shaderLibrary
        )
    }
    
    // MARK: - Initialization
    func initialize() async {
        // Precompile shaders
        await shaderLibrary.precompileShaders()
        
        // Initialize passes
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.shadowPass.initialize() }
            group.addTask { await self.geometryPass.initialize() }
            group.addTask { await self.lightingPass.initialize() }
            group.addTask { await self.postProcessPass.initialize() }
            group.addTask { await self.uiPass.initialize() }
        }
    }
    
    func start() async {
        frameTimer.start()
    }
    
    func pause() {
        frameTimer.pause()
    }
    
    func resume() {
        frameTimer.resume()
    }
    
    // MARK: - Rendering
    func render(
        scene: RenderScene,
        camera: Camera,
        in view: MTKView,
        deltaTime: TimeInterval
    ) {
        frameTimer.beginFrame()
        
        // Update frame data
        updateFrameData(scene: scene, camera: camera, deltaTime: deltaTime)
        
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            frameTimer.endFrame()
            return
        }
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameTimer.endFrame()
            return
        }
        
        commandBuffer.label = "Frame Command Buffer"
        
        // Execute render passes
        executeRenderPasses(
            scene: scene,
            commandBuffer: commandBuffer,
            drawable: drawable,
            renderPassDescriptor: renderPassDescriptor
        )
        
        // Present drawable
        commandBuffer.present(drawable)
        
        // Commit command buffer
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameTimer.endFrame()
            self?.updateStatistics()
        }
        
        commandBuffer.commit()
    }
    
    private func executeRenderPasses(
        scene: RenderScene,
        commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable,
        renderPassDescriptor: MTLRenderPassDescriptor
    ) {
        // 1. Shadow Pass
        if renderSettings.shadowsEnabled {
            shadowPass.execute(
                scene: scene,
                frameData: frameData,
                commandBuffer: commandBuffer
            )
        }
        
        // 2. Geometry Pass (G-Buffer)
        let gBufferTextures = geometryPass.execute(
            scene: scene,
            frameData: frameData,
            commandBuffer: commandBuffer,
            viewportSize: drawable.texture.size
        )
        
        // 3. Lighting Pass
        let litTexture = lightingPass.execute(
            gBufferTextures: gBufferTextures,
            shadowMap: renderSettings.shadowsEnabled ? shadowPass.shadowMap : nil,
            frameData: frameData,
            commandBuffer: commandBuffer
        )
        
        // 4. Post-Processing Pass
        let finalTexture = postProcessPass.execute(
            inputTexture: litTexture,
            frameData: frameData,
            commandBuffer: commandBuffer,
            settings: renderSettings.postProcessSettings
        )
        
        // 5. Final Composite + UI Pass
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0
        )
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) {
            renderEncoder.label = "Final Pass"
            
            // Composite final image
            compositeToScreen(
                texture: finalTexture,
                encoder: renderEncoder,
                viewportSize: drawable.texture.size
            )
            
            // Render UI on top
            uiPass.execute(
                scene: scene,
                encoder: renderEncoder,
                viewportSize: drawable.texture.size
            )
            
            renderEncoder.endEncoding()
        }
    }
    
    // MARK: - Frame Data Update
    private func updateFrameData(
        scene: RenderScene,
        camera: Camera,
        deltaTime: TimeInterval
    ) {
        frameData.deltaTime = Float(deltaTime)
        frameData.time += Float(deltaTime)
        frameData.frameIndex += 1
        
        // Update camera matrices
        frameData.viewMatrix = camera.viewMatrix
        frameData.projectionMatrix = camera.projectionMatrix
        frameData.viewProjectionMatrix = camera.projectionMatrix * camera.viewMatrix
        frameData.cameraPosition = camera.position
        frameData.cameraDirection = camera.forward
        
        // Update lighting
        frameData.lights = scene.lights
        frameData.lightCount = scene.lights.count
        frameData.ambientLight = scene.ambientLight
        
        // Update render settings
        frameData.renderSettings = renderSettings
    }
    
    // MARK: - Screen Composition
    private func compositeToScreen(
        texture: MTLTexture,
        encoder: MTLRenderCommandEncoder,
        viewportSize: CGSize
    ) {
        encoder.setRenderPipelineState(shaderLibrary.getScreenQuadPipeline())
        encoder.setFragmentTexture(texture, index: 0)
        
        // Draw fullscreen quad
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }
    
    // MARK: - Visible Region Update
    func updateVisibleRegion(_ region: WorldRegion?) {
        // Update culling bounds
        if let region = region {
            geometryPass.setCullingBounds(region.getBounds())
        }
    }
    
    // MARK: - Performance Statistics
    private func updateStatistics() {
        currentFPS = frameTimer.averageFPS
        gpuUsage = frameTimer.gpuTime / frameTimer.frameTime
        
        renderStats.drawCalls = geometryPass.drawCallCount
        renderStats.trianglesRendered = geometryPass.triangleCount
        renderStats.textureMemoryUsed = textureCache.memoryUsage
        renderStats.bufferMemoryUsed = bufferPool.memoryUsage
    }
    
    func getStatistics() -> RenderStatistics {
        return renderStats
    }
}

// MARK: - Render Settings
struct RenderSettings {
    // Quality Settings
    var renderScale: Float = 1.0
    var msaaSampleCount: Int = 4
    
    // Shadow Settings
    var shadowsEnabled: Bool = true
    var shadowMapSize: Int = 2048
    var shadowCascades: Int = 4
    var shadowDistance: Float = 100.0
    
    // Post-Processing Settings
    var postProcessSettings = PostProcessSettings()
    
    // Performance Settings
    var maxDrawDistance: Float = 1000.0
    var lodBias: Float = 0.0
    var occlusionCullingEnabled: Bool = true
}

struct PostProcessSettings {
    var bloomEnabled: Bool = true
    var bloomIntensity: Float = 0.5
    var bloomThreshold: Float = 1.0
    
    var toneMappingEnabled: Bool = true
    var exposure: Float = 1.0
    
    var vignetteEnabled: Bool = true
    var vignetteIntensity: Float = 0.3
    
    var chromaticAberrationEnabled: Bool = false
    var chromaticAberrationIntensity: Float = 0.005
    
    var fxaaEnabled: Bool = true
    
    var depthOfFieldEnabled: Bool = false
    var focusDistance: Float = 10.0
    var aperture: Float = 1.4
}

// MARK: - Frame Data
struct FrameData {
    var deltaTime: Float = 0
    var time: Float = 0
    var frameIndex: UInt32 = 0
    
    var viewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    var viewProjectionMatrix = matrix_identity_float4x4
    
    var cameraPosition = SIMD3<Float>.zero
    var cameraDirection = SIMD3<Float>(0, 0, -1)
    
    var lights: [Light] = []
    var lightCount: Int = 0
    var ambientLight = SIMD3<Float>(0.1, 0.1, 0.1)
    
    var renderSettings = RenderSettings()
}

// MARK: - Render Statistics
struct RenderStatistics {
    var drawCalls: Int = 0
    var trianglesRendered: Int = 0
    var textureMemoryUsed: Int = 0
    var bufferMemoryUsed: Int = 0
    var shaderComplexity: Float = 0
    
    var description: String {
        return """
        Draw Calls: \(drawCalls)
        Triangles: \(trianglesRendered)
        Texture Memory: \(textureMemoryUsed / 1024 / 1024) MB
        Buffer Memory: \(bufferMemoryUsed / 1024 / 1024) MB
        """
    }
}

// MARK: - Frame Timer
class FrameTimer {
    private var startTime: CFAbsoluteTime = 0
    private var endTime: CFAbsoluteTime = 0
    private var frameTimes: [CFAbsoluteTime] = []
    private let maxSamples = 60
    
    private(set) var frameTime: CFAbsoluteTime = 0
    private(set) var gpuTime: CFAbsoluteTime = 0
    private(set) var cpuTime: CFAbsoluteTime = 0
    
    var averageFPS: Double {
        guard !frameTimes.isEmpty else { return 0 }
        let average = frameTimes.reduce(0, +) / Double(frameTimes.count)
        return average > 0 ? 1.0 / average : 0
    }
    
    func start() {
        frameTimes.removeAll()
    }
    
    func pause() {
        // Pause timing
    }
    
    func resume() {
        // Resume timing
    }
    
    func beginFrame() {
        startTime = CFAbsoluteTimeGetCurrent()
    }
    
    func endFrame() {
        endTime = CFAbsoluteTimeGetCurrent()
        frameTime = endTime - startTime
        
        frameTimes.append(frameTime)
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }
    }
}
