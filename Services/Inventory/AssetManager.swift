//
//  Services/Inventory/AssetManager.swift
//  FinalStorm
//
//  Enhanced asset management for inventory items with caching and optimization
//  Handles texture loading, mesh caching, procedural generation, and asset lifecycle
//

import Foundation
import RealityKit
import Combine
import Metal

@MainActor
class AssetManager: ObservableObject {
    // MARK: - Properties
    @Published var loadingAssets: Set<UUID> = []
    @Published var failedAssets: Set<UUID> = []
    @Published var isInitialized = false
    
    private let assetCache: AssetCache
    private let assetService: AssetService
    private var loadingTasks: [UUID: Task<Any, Error>] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Asset generation settings
    private let iconSize: CGSize = CGSize(width: 128, height: 128)
    private let previewSize: CGSize = CGSize(width: 256, height: 256)
    private let maxConcurrentLoads = 5
    private var currentLoads = 0
    
    // MARK: - Initialization
    init() {
        self.assetCache = AssetCache()
        self.assetService = AssetService()
        setupErrorHandling()
        initializeDefaults()
    }
    
    private func setupErrorHandling() {
        // Monitor failed assets and retry with exponential backoff
        $failedAssets
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] failedIds in
                self?.retryFailedAssets(Array(failedIds))
            }
            .store(in: &cancellables)
    }
    
    private func initializeDefaults() {
        Task {
            await loadDefaultAssets()
            isInitialized = true
        }
    }
    
    // MARK: - Asset Loading
    func loadTexture(_ assetId: UUID) async throws -> TextureResource {
        // Check cache first
        if let cached = assetCache.getAsset(assetId, type: TextureAsset.self) {
            return cached.textureResource
        }
        
        // Check if already loading
        if let existingTask = loadingTasks[assetId] as? Task<TextureResource, Error> {
            return try await existingTask.value
        }
        
        // Throttle concurrent loads
        while currentLoads >= maxConcurrentLoads {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        loadingAssets.insert(assetId)
        failedAssets.remove(assetId)
        currentLoads += 1
        
        let task = Task<TextureResource, Error> {
            defer {
                Task { @MainActor in
                    self.loadingAssets.remove(assetId)
                    self.loadingTasks.removeValue(forKey: assetId)
                    self.currentLoads -= 1
                }
            }
            
            do {
                let texture = try await assetService.loadTexture(assetId)
                let asset = TextureAsset(
                    id: assetId,
                    textureResource: texture,
                    originalData: Data() // Would contain actual data in real implementation
                )
                
                await MainActor.run {
                    assetCache.storeAsset(asset, for: assetId)
                }
                
                return texture
            } catch {
                await MainActor.run {
                    failedAssets.insert(assetId)
                }
                throw error
            }
        }
        
        loadingTasks[assetId] = task
        return try await task.value
    }
    
    func loadMesh(_ assetId: UUID) async throws -> MeshResource {
        // Check cache first
        if let cached = assetCache.getAsset(assetId, type: MeshAsset.self) {
            return cached.meshResource
        }
        
        // Check if already loading
        if let existingTask = loadingTasks[assetId] as? Task<MeshResource, Error> {
            return try await existingTask.value
        }
        
        // Throttle concurrent loads
        while currentLoads >= maxConcurrentLoads {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        loadingAssets.insert(assetId)
        failedAssets.remove(assetId)
        currentLoads += 1
        
        let task = Task<MeshResource, Error> {
            defer {
                Task { @MainActor in
                    self.loadingAssets.remove(assetId)
                    self.loadingTasks.removeValue(forKey: assetId)
                    self.currentLoads -= 1
                }
            }
            
            do {
                let mesh = try await assetService.loadMesh(assetId)
                let asset = MeshAsset(
                    id: assetId,
                    meshResource: mesh,
                    originalData: Data()
                )
                
                await MainActor.run {
                    assetCache.storeAsset(asset, for: assetId)
                }
                
                return mesh
            } catch {
                await MainActor.run {
                    failedAssets.insert(assetId)
                }
                throw error
            }
        }
        
        loadingTasks[assetId] = task
        return try await task.value
    }
    
    // MARK: - Procedural Generation
    func generateProceduralIcon(category: ItemCategory, rarity: ItemRarity) async -> TextureResource {
        let cacheKey = UUID() // In real implementation, would use deterministic key
        
        if let cached = assetCache.getAsset(cacheKey, type: TextureAsset.self) {
            return cached.textureResource
        }
        
        return await withCheckedContinuation { continuation in
            Task.detached {
                let texture = await self.createProceduralIcon(category: category, rarity: rarity)
                let asset = TextureAsset(
                    id: cacheKey,
                    textureResource: texture,
                    originalData: Data()
                )
                
                await MainActor.run {
                    self.assetCache.storeAsset(asset, for: cacheKey)
                }
                
                continuation.resume(returning: texture)
            }
        }
    }
    
    private func createProceduralIcon(category: ItemCategory, rarity: ItemRarity) async -> TextureResource {
        // Create procedural texture based on category and rarity
        let backgroundColor = getCategoryColor(category)
        let rarityColor = rarity.color
        
        // Use Metal to generate the texture
        return createTextureWithMetal(
            backgroundColor: backgroundColor,
            accentColor: rarityColor,
            pattern: getPatternForCategory(category)
        )
    }
    
    private func getCategoryColor(_ category: ItemCategory) -> CodableColor {
        switch category {
        case .equipment:
            return CodableColor(red: 0.7, green: 0.7, blue: 0.8, alpha: 1.0)
        case .consumable:
            return CodableColor(red: 0.8, green: 0.3, blue: 0.3, alpha: 1.0)
        case .material:
            return CodableColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
        case .quest:
            return CodableColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        case .tool:
            return CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        case .misc:
            return CodableColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
        case .all:
            return CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        }
    }
    
    private func getPatternForCategory(_ category: ItemCategory) -> IconPattern {
        switch category {
        case .equipment: return .geometric
        case .consumable: return .organic
        case .material: return .crystalline
        case .quest: return .mystical
        case .tool: return .mechanical
        default: return .simple
        }
    }
    
    private func createTextureWithMetal(
        backgroundColor: CodableColor,
        accentColor: CodableColor,
        pattern: IconPattern
    ) -> TextureResource {
        // Metal texture generation implementation
        let device = MTLCreateSystemDefaultDevice()!
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(iconSize.width),
            height: Int(iconSize.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return createFallbackTexture(color: backgroundColor)
        }
        
        // Render procedural pattern using Metal shaders
        renderProceduralPattern(
            device: device,
            texture: texture,
            backgroundColor: backgroundColor,
            accentColor: accentColor,
            pattern: pattern
        )
        
        do {
            return try TextureResource(from: texture)
        } catch {
            return createFallbackTexture(color: backgroundColor)
        }
    }
    
    private func renderProceduralPattern(
        device: MTLDevice,
        texture: MTLTexture,
        backgroundColor: CodableColor,
        accentColor: CodableColor,
        pattern: IconPattern
    ) {
        // Metal rendering implementation for procedural patterns
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = createRenderPassDescriptor(texture: texture),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Set up shaders and render state based on pattern
        setupRenderStateForPattern(pattern, renderEncoder: renderEncoder, device: device)
        
        // Pass colors as uniforms
        var uniforms = IconUniforms(
            backgroundColor: backgroundColor.simd4,
            accentColor: accentColor.simd4,
            time: Float(Date().timeIntervalSince1970),
            pattern: pattern.rawValue
        )
        
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<IconUniforms>.size, index: 0)
        
        // Render fullscreen quad
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func createRenderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }
    
    private func setupRenderStateForPattern(
        _ pattern: IconPattern,
        renderEncoder: MTLRenderCommandEncoder,
        device: MTLDevice
    ) {
        // Load appropriate shaders for the pattern
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "icon_vertex"),
              let fragmentFunction = library.makeFunction(name: "icon_fragment_\(pattern.shaderName)") else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            renderEncoder.setRenderPipelineState(pipelineState)
        } catch {
            print("Failed to create render pipeline state: \(error)")
        }
    }
    
    private func createFallbackTexture(color: CodableColor) -> TextureResource {
        // Create a simple solid color texture as fallback
        do {
            return try TextureResource.generate(
                from: color.cgColor,
                width: Int(iconSize.width),
                height: Int(iconSize.height)
            )
        } catch {
            // Last resort - return a default system texture
            return try! TextureResource.load(named: "DefaultIcon")
        }
    }
    
    // MARK: - Batch Operations
    func preloadItemAssets(_ items: [InventoryItem]) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    // Preload icon
                    if let iconAssetId = item.iconAssetId {
                        group.addTask {
                            do {
                                _ = try await self.loadTexture(iconAssetId)
                            } catch {
                                print("Failed to preload icon for \(item.name): \(error)")
                            }
                        }
                    }
                    
                    // Preload mesh for equipped items
                    if item.isEquipped, let meshAssetId = item.meshAssetId {
                        group.addTask {
                            do {
                                _ = try await self.loadMesh(meshAssetId)
                            } catch {
                                print("Failed to preload mesh for \(item.name): \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func retryFailedAssets(_ assetIds: [UUID]) {
        Task {
            for assetId in assetIds {
                do {
                    // Retry with exponential backoff
                    try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...5_000_000_000))
                    _ = try await loadTexture(assetId)
                } catch {
                    print("Retry failed for asset \(assetId): \(error)")
                }
            }
        }
    }
    
    private func loadDefaultAssets() async {
        // Load essential default assets
        let defaultAssets = [
            "default_equipment_icon",
            "default_consumable_icon",
            "default_material_icon",
            "default_quest_icon"
        ]
        
        for assetName in defaultAssets {
            do {
                let texture = try TextureResource.load(named: assetName)
                let asset = TextureAsset(
                    id: UUID(),
                    textureResource: texture,
                    originalData: Data()
                )
                assetCache.storeAsset(asset, for: asset.id)
            } catch {
                print("Failed to load default asset \(assetName): \(error)")
            }
        }
    }
    
    // MARK: - Cache Management
    func clearAssetCache() {
        assetCache.clearAll()
        loadingAssets.removeAll()
        failedAssets.removeAll()
        
        // Cancel ongoing tasks
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
        currentLoads = 0
    }
    
    func getCacheSize() -> Int64 {
        return assetCache.getTotalSize()
    }
    
    func getCacheInfo() -> AssetCacheInfo {
        return AssetCacheInfo(
            totalAssets: assetCache.getAssetCount(),
            totalSize: assetCache.getTotalSize(),
            loadingAssets: loadingAssets.count,
            failedAssets: failedAssets.count
        )
    }
}

// MARK: - Supporting Types

enum IconPattern: Int, CaseIterable {
    case simple = 0
    case geometric = 1
    case organic = 2
    case crystalline = 3
    case mystical = 4
    case mechanical = 5
    
    var shaderName: String {
        switch self {
        case .simple: return "simple"
        case .geometric: return "geometric"
        case .organic: return "organic"
        case .crystalline: return "crystalline"
        case .mystical: return "mystical"
        case .mechanical: return "mechanical"
        }
    }
}

struct IconUniforms {
    let backgroundColor: SIMD4<Float>
    let accentColor: SIMD4<Float>
    let time: Float
    let pattern: Int32
}

struct AssetCacheInfo {
    let totalAssets: Int
    let totalSize: Int64
    let loadingAssets: Int
    let failedAssets: Int
}

// MARK: - Asset Protocol and Types

protocol Asset {
    var id: UUID { get }
    var originalData: Data { get }
    var createdAt: Date { get }
}

struct TextureAsset: Asset {
    let id: UUID
    let textureResource: TextureResource
    let originalData: Data
    let createdAt: Date = Date()
}

struct MeshAsset: Asset {
    let id: UUID
    let meshResource: MeshResource
    let originalData: Data
    let createdAt: Date = Date()
}

// MARK: - Asset Cache Implementation

class AssetCache {
    private var cache: [UUID: Any] = [:]
    private let cacheQueue = DispatchQueue(label: "asset.cache", attributes: .concurrent)
    private let maxCacheSize: Int64 = 1024 * 1024 * 1024 // 1GB
    private var currentSize: Int64 = 0
    private var accessTimes: [UUID: Date] = [:]
    
    func getAsset<T: Asset>(_ id: UUID, type: T.Type) -> T? {
        return cacheQueue.sync {
            accessTimes[id] = Date()
            return cache[id] as? T
        }
    }
    
    func storeAsset<T: Asset>(_ asset: T, for id: UUID) {
        cacheQueue.async(flags: .barrier) {
            self.cache[id] = asset
            self.accessTimes[id] = Date()
            self.currentSize += Int64(asset.originalData.count)
            
            if self.currentSize > self.maxCacheSize {
                self.performCacheCleanup()
            }
        }
    }
    
    func removeAsset(_ id: UUID) {
        cacheQueue.async(flags: .barrier) {
            if let asset = self.cache[id] as? Asset {
                self.currentSize -= Int64(asset.originalData.count)
            }
            self.cache.removeValue(forKey: id)
            self.accessTimes.removeValue(forKey: id)
        }
    }
    
    func clearAll() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
            self.accessTimes.removeAll()
            self.currentSize = 0
        }
    }
    
    func getTotalSize() -> Int64 {
        return cacheQueue.sync { currentSize }
    }
    
    func getAssetCount() -> Int {
        return cacheQueue.sync { cache.count }
    }
    
    private func performCacheCleanup() {
        // Remove least recently used assets
        let sortedByAccess = accessTimes.sorted { $0.value < $1.value }
        let toRemove = sortedByAccess.prefix(cache.count / 4) // Remove 25% of cache
        
        for (id, _) in toRemove {
            if let asset = cache[id] as? Asset {
                currentSize -= Int64(asset.originalData.count)
            }
            cache.removeValue(forKey: id)
            accessTimes.removeValue(forKey: id)
        }
    }
}

// MARK: - Asset Service

class AssetService {
    func loadTexture(_ assetId: UUID) async throws -> TextureResource {
        // In real implementation, this would load from network/disk
        try await Task.sleep(nanoseconds: 100_000_000) // Simulate network delay
        
        // For now, return a procedurally generated texture
        return try TextureResource.generate(
            from: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
            width: 128,
            height: 128
        )
    }
    
    func loadMesh(_ assetId: UUID) async throws -> MeshResource {
        // In real implementation, this would load from network/disk
        try await Task.sleep(nanoseconds: 200_000_000) // Simulate network delay
        
        // For now, return a simple box mesh
        return try .generateBox(size: 0.1)
    }
}
