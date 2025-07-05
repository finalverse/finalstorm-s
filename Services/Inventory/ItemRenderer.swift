//
//  Services/Inventory/ItemRenderer.swift
//  FinalStorm
//
//  Advanced item rendering system with procedural generation and 3D visualization
//  Handles icon creation, 3D model rendering, particle effects, and visual enhancement
//

import Foundation
import RealityKit
import Combine
import Metal
import MetalKit
import SwiftUI

@MainActor
class ItemRenderer: ObservableObject {
   // MARK: - Properties
   @Published var renderingProgress: Float = 0.0
   @Published var isRendering: Bool = false
   
   private let assetManager: AssetManager
   private var iconCache: [UUID: TextureResource] = [:]
   private var previewCache: [UUID: ModelEntity] = [:]
   private var materialCache: [String: Material] = [:]
   
   private let renderQueue = DispatchQueue(label: "item.renderer", qos: .utility)
   private let metalDevice: MTLDevice
   private let commandQueue: MTLCommandQueue
   
   // Rendering settings
   private let iconSize: CGSize = CGSize(width: 128, height: 128)
   private let previewSize: CGSize = CGSize(width: 512, height: 512)
   private let maxCacheSize = 200
   
   // Shader libraries
   private let iconShaderLibrary: MTLLibrary
   private let materialShaderLibrary: MTLLibrary
   
   // MARK: - Initialization
   init(assetManager: AssetManager) {
       self.assetManager = assetManager
       
       guard let device = MTLCreateSystemDefaultDevice() else {
           fatalError("Metal is not supported on this device")
       }
       self.metalDevice = device
       
       guard let queue = device.makeCommandQueue() else {
           fatalError("Could not create Metal command queue")
       }
       self.commandQueue = queue
       
       // Load shader libraries
       guard let iconLib = device.makeDefaultLibrary(),
             let materialLib = device.makeDefaultLibrary() else {
           fatalError("Could not load shader libraries")
       }
       self.iconShaderLibrary = iconLib
       self.materialShaderLibrary = materialLib
       
       setupDefaultMaterials()
   }
   
   private func setupDefaultMaterials() {
       // Create common materials for different item types
       materialCache["common"] = createMaterial(for: .common)
       materialCache["uncommon"] = createMaterial(for: .uncommon)
       materialCache["rare"] = createMaterial(for: .rare)
       materialCache["epic"] = createMaterial(for: .epic)
       materialCache["legendary"] = createMaterial(for: .legendary)
       materialCache["artifact"] = createMaterial(for: .artifact)
   }
   
   // MARK: - Icon Management
   func getIcon(for itemId: UUID) async -> TextureResource? {
       return iconCache[itemId]
   }
   
   func cacheIcon(for itemId: UUID, texture: TextureResource) {
       iconCache[itemId] = texture
       
       // Manage cache size
       if iconCache.count > maxCacheSize {
           performCacheCleanup()
       }
   }
   
   func generateIcon(for item: InventoryItem) async -> TextureResource {
       // Check if item has a custom icon asset
       if let iconAssetId = item.iconAssetId {
           do {
               let texture = try await assetManager.loadTexture(iconAssetId)
               cacheIcon(for: item.id, texture: texture)
               return texture
           } catch {
               print("Failed to load custom icon for \(item.name): \(error)")
           }
       }
       
       // Generate procedural icon
       let proceduralIcon = await generateProceduralIcon(for: item)
       cacheIcon(for: item.id, texture: proceduralIcon)
       return proceduralIcon
   }
   
   func generateDefaultIcon(for category: ItemCategory, rarity: ItemRarity) async -> TextureResource {
       return await withCheckedContinuation { continuation in
           renderQueue.async {
               let icon = self.createProceduralIcon(
                   category: category,
                   rarity: rarity,
                   customProperties: [:]
               )
               
               Task { @MainActor in
                   continuation.resume(returning: icon)
               }
           }
       }
   }
   
   private func generateProceduralIcon(for item: InventoryItem) async -> TextureResource {
       return await withCheckedContinuation { continuation in
           renderQueue.async {
               let customProperties = self.extractCustomProperties(from: item)
               let icon = self.createProceduralIcon(
                   category: item.category,
                   rarity: item.rarity,
                   customProperties: customProperties
               )
               
               Task { @MainActor in
                   continuation.resume(returning: icon)
               }
           }
       }
   }
   
   private func extractCustomProperties(from item: InventoryItem) -> [String: Any] {
       var properties: [String: Any] = [:]
       
       // Add item-specific visual properties
       properties["isEquipped"] = item.isEquipped
       properties["isBroken"] = item.isBroken
       properties["durabilityRatio"] = Float(item.durability) / Float(max(item.maxDurability, 1))
       properties["enhancementCount"] = item.enhancements.count
       properties["hasEffects"] = !item.effects.isEmpty
       properties["stackSize"] = item.quantity
       
       // Add stat influences
       if !item.stats.isEmpty {
           let totalStatValue = item.stats.reduce(0) { $0 + $1.value }
           properties["totalStatValue"] = totalStatValue
           properties["primaryStat"] = item.stats.max { $0.value < $1.value }?.type.rawValue
       }
       
       return properties
   }
   
   private func createProceduralIcon(
       category: ItemCategory,
       rarity: ItemRarity,
       customProperties: [String: Any]
   ) -> TextureResource {
       // Create texture descriptor
       let descriptor = MTLTextureDescriptor.texture2DDescriptor(
           pixelFormat: .rgba8Unorm,
           width: Int(iconSize.width),
           height: Int(iconSize.height),
           mipmapped: false
       )
       descriptor.usage = [.shaderRead, .renderTarget]
       
       guard let texture = metalDevice.makeTexture(descriptor: descriptor) else {
           return createFallbackTexture()
       }
       
       // Render the procedural icon
       renderProceduralIcon(
           texture: texture,
           category: category,
           rarity: rarity,
           properties: customProperties
       )
       
       do {
           return try TextureResource(from: texture)
       } catch {
           print("Failed to create TextureResource from Metal texture: \(error)")
           return createFallbackTexture()
       }
   }
   
   private func renderProceduralIcon(
       texture: MTLTexture,
       category: ItemCategory,
       rarity: ItemRarity,
       properties: [String: Any]
   ) {
       guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
       
       let renderPassDescriptor = MTLRenderPassDescriptor()
       renderPassDescriptor.colorAttachments[0].texture = texture
       renderPassDescriptor.colorAttachments[0].loadAction = .clear
       renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
       renderPassDescriptor.colorAttachments[0].storeAction = .store
       
       guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
           return
       }
       
       // Set up render pipeline for icon generation
       setupIconRenderPipeline(renderEncoder: renderEncoder, category: category)
       
       // Create and upload uniforms
       var uniforms = createIconUniforms(
           category: category,
           rarity: rarity,
           properties: properties
       )
       
       renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<IconUniforms>.size, index: 0)
       
       // Render fullscreen triangle
       renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
       renderEncoder.endEncoding()
       
       commandBuffer.commit()
       commandBuffer.waitUntilCompleted()
   }
   
   private func setupIconRenderPipeline(renderEncoder: MTLRenderCommandEncoder, category: ItemCategory) {
       let shaderName = "icon_fragment_\(category.shaderName)"
       
       guard let vertexFunction = iconShaderLibrary.makeFunction(name: "icon_vertex"),
             let fragmentFunction = iconShaderLibrary.makeFunction(name: shaderName) else {
           print("Failed to load shaders for category: \(category)")
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
           let pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
           renderEncoder.setRenderPipelineState(pipelineState)
       } catch {
           print("Failed to create render pipeline state: \(error)")
       }
   }
   
   private func createIconUniforms(
       category: ItemCategory,
       rarity: ItemRarity,
       properties: [String: Any]
   ) -> IconUniforms {
       let categoryColor = getCategoryColor(category)
       let rarityColor = rarity.color
       
       return IconUniforms(
           backgroundColor: categoryColor.simd4,
           accentColor: rarityColor.simd4,
           time: Float(Date().timeIntervalSince1970),
           pattern: category.iconPattern.rawValue,
           isEquipped: properties["isEquipped"] as? Bool ?? false,
           isBroken: properties["isBroken"] as? Bool ?? false,
           durabilityRatio: properties["durabilityRatio"] as? Float ?? 1.0,
           enhancementLevel: Float(properties["enhancementCount"] as? Int ?? 0),
           effectIntensity: properties["hasEffects"] as? Bool == true ? 1.0 : 0.0,
           stackSize: Float(properties["stackSize"] as? Int ?? 1)
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
           return CodableColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 1.0)
       case .misc:
           return CodableColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
       case .all:
           return CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
       }
   }
   
   private func createFallbackTexture() -> TextureResource {
       do {
           return try TextureResource.generate(
               from: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
               width: Int(iconSize.width),
               height: Int(iconSize.height)
           )
       } catch {
           fatalError("Could not create fallback texture")
       }
   }
   
   // MARK: - 3D Model Generation
   func generate3DPreview(for item: InventoryItem) async -> ModelEntity? {
       // Check cache first
       if let cached = previewCache[item.id] {
           return cached.clone(recursive: true)
       }
       
       isRendering = true
       renderingProgress = 0.0
       
       defer {
           isRendering = false
           renderingProgress = 1.0
       }
       
       // Load or generate mesh
       let mesh: MeshResource
       if let meshAssetId = item.meshAssetId {
           do {
               mesh = try await assetManager.loadMesh(meshAssetId)
               renderingProgress = 0.4
           } catch {
               print("Failed to load mesh for \(item.name): \(error)")
               mesh = generateDefaultMesh(for: item.category)
               renderingProgress = 0.4
           }
       } else {
           mesh = generateDefaultMesh(for: item.category)
           renderingProgress = 0.4
       }
       
       // Create materials
       let materials = createItemMaterials(for: item)
       renderingProgress = 0.6
       
       // Create model entity
       let model = ModelEntity(mesh: mesh, materials: materials)
       
       // Apply item-specific transformations and effects
       applyItemVisualEffects(to: model, item: item)
       renderingProgress = 0.8
       
       // Add to cache
       previewCache[item.id] = model
       
       // Manage cache size
       if previewCache.count > maxCacheSize {
           performPreviewCacheCleanup()
       }
       
       renderingProgress = 1.0
       
       return model.clone(recursive: true)
   }
   
   private func generateDefaultMesh(for category: ItemCategory) -> MeshResource {
       switch category {
       case .equipment:
           return try! .generateBox(size: [0.1, 0.15, 0.02])
       case .consumable:
           return try! .generateSphere(radius: 0.05)
       case .material:
           return try! .generateBox(size: [0.08, 0.08, 0.08])
       case .quest:
           return try! .generateBox(size: [0.12, 0.08, 0.02])
       case .tool:
           return try! .generateBox(size: [0.15, 0.05, 0.05])
       case .misc:
           return try! .generateBox(size: [0.1, 0.1, 0.1])
       case .all:
           return try! .generateBox(size: [0.1, 0.1, 0.1])
       }
   }
   
   private func createItemMaterials(for item: InventoryItem) -> [Material] {
       // Get base material for rarity
       var material = createMaterial(for: item.rarity)
       
       // Apply item-specific modifications
       material = applyItemModifications(to: material, item: item)
       
       return [material]
   }
   
   private func createMaterial(for rarity: ItemRarity) -> Material {
       if let cached = materialCache[rarity.rawValue.lowercased()] {
           return cached
       }
       
       var material = PhysicallyBasedMaterial()
       let rarityColor = rarity.color
       
       // Base color
       material.baseColor = PhysicallyBasedMaterial.BaseColor(
           tint: UIColor(
               red: CGFloat(rarityColor.red),
               green: CGFloat(rarityColor.green),
               blue: CGFloat(rarityColor.blue),
               alpha: CGFloat(rarityColor.alpha)
           )
       )
       
       // Material properties based on rarity
       switch rarity {
       case .common:
           material.metallic = 0.1
           material.roughness = 0.8
       case .uncommon:
           material.metallic = 0.2
           material.roughness = 0.6
       case .rare:
           material.metallic = 0.4
           material.roughness = 0.4
       case .epic:
           material.metallic = 0.6
           material.roughness = 0.3
           material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(
               color: UIColor(
                   red: CGFloat(rarityColor.red * 0.3),
                   green: CGFloat(rarityColor.green * 0.3),
                   blue: CGFloat(rarityColor.blue * 0.3),
                   alpha: 1.0
               )
           )
           material.emissiveIntensity = 0.2
       case .legendary:
           material.metallic = 0.8
           material.roughness = 0.2
           material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(
               color: UIColor(
                   red: CGFloat(rarityColor.red * 0.5),
                   green: CGFloat(rarityColor.green * 0.5),
                   blue: CGFloat(rarityColor.blue * 0.5),
                   alpha: 1.0
               )
           )
           material.emissiveIntensity = 0.4
       case .artifact:
           material.metallic = 1.0
           material.roughness = 0.1
           material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(
               color: UIColor(
                   red: CGFloat(rarityColor.red),
                   green: CGFloat(rarityColor.green),
                   blue: CGFloat(rarityColor.blue),
                   alpha: 1.0
               )
           )
           material.emissiveIntensity = 0.6
       }
       
       materialCache[rarity.rawValue.lowercased()] = material
       return material
   }
   
   private func applyItemModifications(to material: Material, item: InventoryItem) -> Material {
       guard var pbr = material as? PhysicallyBasedMaterial else { return material }
       
       // Apply durability effects
       let durabilityRatio = Float(item.durability) / Float(max(item.maxDurability, 1))
       if durabilityRatio < 0.5 {
           // Make item look worn/damaged
           pbr.roughness = pbr.roughness.scalar! + (1.0 - durabilityRatio) * 0.3
           
           // Reduce metallic appearance for damaged items
           pbr.metallic = pbr.metallic.scalar! * durabilityRatio
       }
       
       // Apply broken state
       if item.isBroken {
           pbr.baseColor = PhysicallyBasedMaterial.BaseColor(
               tint: UIColor.gray.withAlphaComponent(0.7)
           )
           pbr.emissiveIntensity = 0.0
       }
       
       // Apply enhancement effects
       if !item.enhancements.isEmpty {
           let enhancementIntensity = Float(item.enhancements.count) * 0.1
           pbr.emissiveIntensity = (pbr.emissiveIntensity ?? 0.0) + enhancementIntensity
           
           // Add sparkle effect for enhanced items
           if let emissiveColor = pbr.emissiveColor?.color {
               pbr.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(
                   color: emissiveColor.withAlphaComponent(0.8)
               )
           }
       }
       
       return pbr
   }
   
   private func applyItemVisualEffects(to model: ModelEntity, item: InventoryItem) {
       // Scale based on category
       let scale = getItemScale(for: item.category)
       model.scale = scale
       
       // Add rotation animation
       addRotationAnimation(to: model)
       
       // Add particle effects for special items
       if item.rarity.sortOrder >= ItemRarity.epic.sortOrder || !item.enhancements.isEmpty {
           addParticleEffects(to: model, item: item)
       }
       
       // Add glow effect for equipped items
       if item.isEquipped {
           addGlowEffect(to: model, intensity: 0.3)
       }
       
       // Add damage cracks for broken items
       if item.isBroken {
           addDamageEffects(to: model)
       }
       
       // Add enhancement aura
       if !item.enhancements.isEmpty {
           addEnhancementAura(to: model, level: item.enhancements.count)
       }
   }
   
   private func getItemScale(for category: ItemCategory) -> SIMD3<Float> {
       switch category {
       case .equipment:
           return SIMD3<Float>(1.2, 1.2, 1.2)
       case .consumable:
           return SIMD3<Float>(0.8, 0.8, 0.8)
       case .material:
           return SIMD3<Float>(0.6, 0.6, 0.6)
       case .quest:
           return SIMD3<Float>(1.0, 1.0, 1.0)
       case .tool:
           return SIMD3<Float>(1.1, 1.1, 1.1)
       default:
           return SIMD3<Float>(1.0, 1.0, 1.0)
       }
   }
   
   private func addRotationAnimation(to model: ModelEntity) {
       let rotation = FromToByAnimation(
           by: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
           duration: 8.0,
           bindTarget: .transform
       )
       
       if let rotationResource = try? AnimationResource.generate(with: rotation) {
           model.playAnimation(rotationResource.repeat())
       }
   }
   
   private func addParticleEffects(to model: ModelEntity, item: InventoryItem) {
       var particles = ParticleEmitterComponent()
       particles.birthRate = Float(item.rarity.sortOrder) * 5.0 + Float(item.enhancements.count) * 10.0
       particles.emitterShape = .sphere
       particles.mainEmitter.lifeSpan = 2.0
       particles.mainEmitter.speed = 0.05
       particles.mainEmitter.size = 0.005
       
       // Color based on rarity and enhancements
       let baseColor = item.rarity.color
       let particleColor = item.enhancements.isEmpty ? baseColor : CodableColor.gold
       
       particles.mainEmitter.color = .single(UIColor(
           red: CGFloat(particleColor.red),
           green: CGFloat(particleColor.green),
           blue: CGFloat(particleColor.blue),
           alpha: 1.0
       ))
       
       particles.mainEmitter.opacityOverLife = .linearFade
       particles.mainEmitter.sizeOverLife = .linearGrowth
       
       model.components.set(particles)
   }
   
   private func addGlowEffect(to model: ModelEntity, intensity: Float) {
       // Add a subtle glow effect using emissive properties
       if var material = model.model?.materials.first as? PhysicallyBasedMaterial {
           let currentIntensity = material.emissiveIntensity ?? 0.0
           material.emissiveIntensity = currentIntensity + intensity
           model.model?.materials = [material]
       }
   }
   
   private func addDamageEffects(to model: ModelEntity) {
       // Add visual damage indicators
       // This could include crack textures, reduced opacity, etc.
       if var material = model.model?.materials.first as? PhysicallyBasedMaterial {
           // Reduce overall opacity to show damage
           if let baseColor = material.baseColor.tint {
               material.baseColor = PhysicallyBasedMaterial.BaseColor(
                   tint: baseColor.withAlphaComponent(0.7)
               )
           }
           
           // Increase roughness to show wear
           material.roughness = 1.0
           material.metallic = 0.0
           
           model.model?.materials = [material]
       }
   }
   
   private func addEnhancementAura(to model: ModelEntity, level: Int) {
       // Add an aura effect around enhanced items
       let auraEntity = ModelEntity()
       
       // Create aura geometry (larger, transparent version of the item)
       if let mesh = model.model?.mesh {
           var auraMaterial = PhysicallyBasedMaterial()
           auraMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(
               tint: UIColor.cyan.withAlphaComponent(0.3)
           )
           auraMaterial.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: .cyan)
           auraMaterial.emissiveIntensity = Float(level) * 0.2
           
           auraEntity.model = ModelComponent(mesh: mesh, materials: [auraMaterial])
           auraEntity.scale = SIMD3<Float>(repeating: 1.1 + Float(level) * 0.05)
           
           model.addChild(auraEntity)
       }
   }
   
   // MARK: - Cache Management
   private func performCacheCleanup() {
       // Remove oldest entries when cache is full
       let keysToRemove = Array(iconCache.keys.prefix(iconCache.count - maxCacheSize + 10))
       for key in keysToRemove {
           iconCache.removeValue(forKey: key)
       }
   }
   
   private func performPreviewCacheCleanup() {
       // Remove oldest preview entries
       let keysToRemove = Array(previewCache.keys.prefix(previewCache.count - maxCacheSize + 10))
       for key in keysToRemove {
           previewCache.removeValue(forKey: key)
       }
   }
   
   func clearCache() {
       iconCache.removeAll()
       previewCache.removeAll()
       materialCache.removeAll()
       setupDefaultMaterials()
   }
   
   func getCacheInfo() -> (iconCount: Int, previewCount: Int, materialCount: Int) {
       return (iconCache.count, previewCache.count, materialCache.count)
   }
   
   // MARK: - Batch Operations
   func preloadIconsForItems(_ items: [InventoryItem]) async {
       await withTaskGroup(of: Void.self) { group in
           for item in items {
               group.addTask {
                   _ = await self.generateIcon(for: item)
               }
           }
       }
   }
   
   func generateIconsForCategory(_ category: ItemCategory, count: Int) async -> [TextureResource] {
       var icons: [TextureResource] = []
       
       for _ in 0..<count {
           let randomRarity = ItemRarity.allCases.randomElement() ?? .common
           let icon = await generateDefaultIcon(for: category, rarity: randomRarity)
           icons.append(icon)
       }
       
       return icons
   }
}

// MARK: - Supporting Types and Extensions

struct IconUniforms {
   let backgroundColor: SIMD4<Float>
   let accentColor: SIMD4<Float>
   let time: Float
   let pattern: Int32
   let isEquipped: Bool
   let isBroken: Bool
   let durabilityRatio: Float
   let enhancementLevel: Float
   let effectIntensity: Float
   let stackSize: Float
   
   // Padding for Metal alignment
   private let _padding: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
}

enum IconPattern: Int32, CaseIterable {
   case simple = 0
   case geometric = 1
   case organic = 2
   case crystalline = 3
   case mystical = 4
   case mechanical = 5
   case elemental = 6
   case ethereal = 7
   
   var shaderName: String {
       switch self {
       case .simple: return "simple"
       case .geometric: return "geometric"
       case .organic: return "organic"
       case .crystalline: return "crystalline"
       case .mystical: return "mystical"
       case .mechanical: return "mechanical"
       case .elemental: return "elemental"
       case .ethereal: return "ethereal"
       }
   }
}

extension ItemCategory {
   var iconPattern: IconPattern {
       switch self {
       case .equipment: return .geometric
       case .consumable: return .organic
       case .material: return .crystalline
       case .quest: return .mystical
       case .tool: return .mechanical
       case .misc: return .simple
       case .all: return .simple
       }
   }
   
   var shaderName: String {
       return iconPattern.shaderName
   }
}

extension ItemRarity {
   var sortOrder: Int {
       switch self {
       case .artifact: return 6
       case .legendary: return 5
       case .epic: return 4
       case .rare: return 3
       case .uncommon: return 2
       case .common: return 1
       }
   }
}

// MARK: - Additional Supporting Types for Inventory System

extension InventoryItem {
   var isUsable: Bool {
       return category == .consumable || !effects.isEmpty
   }
   
   var canBeEnhanced: Bool {
       return category == .equipment && enhancements.count < 3 && !isBroken
   }
   
   var durabilityPercentage: Float {
       guard maxDurability > 0 else { return 1.0 }
       return Float(durability) / Float(maxDurability)
   }
   
   func withUpdatedQuantity(_ newQuantity: Int) -> InventoryItem {
       var updated = self
       updated.quantity = newQuantity
       return updated
   }
   
   func withEquippedState(_ equipped: Bool) -> InventoryItem {
       var updated = self
       updated.isEquipped = equipped
       return updated
   }
   
   func withUpdatedDurability(_ newDurability: Int) -> InventoryItem {
       var updated = self
       updated.durability = newDurability
       return updated
   }
   
   func withUpdatedMaxDurability(_ newMaxDurability: Int) -> InventoryItem {
       var updated = self
       updated.maxDurability = newMaxDurability
       return updated
   }
   
   func withBrokenState(_ broken: Bool) -> InventoryItem {
       var updated = self
       updated.isBroken = broken
       return updated
   }
   
   func withUpdatedStats(_ newStats: [ItemStat]) -> InventoryItem {
       var updated = self
       updated.stats = newStats
       return updated
   }
}

// MARK: - Complete Item Data Structures

struct InventoryItem: Identifiable, Codable, Equatable {
   let id: UUID
   let templateId: UUID
   var name: String
   var description: String
   let category: ItemCategory
   let rarity: ItemRarity
   var quantity: Int
   let weight: Float
   var value: Int
   
   // Assets
   let iconAssetId: UUID?
   let meshAssetId: UUID?
   
   // Properties
   let isStackable: Bool
   let isEquippable: Bool
   let equipSlot: EquipSlot?
   var stats: [ItemStat]
   var effects: [ItemEffect]
   let requirements: [ItemRequirement]
   
   // State
   var durability: Int
   var maxDurability: Int
   var isBroken: Bool = false
   var isEquipped: Bool
   let dateAdded: Date
   var enhancements: [ItemEnhancement] = []
   var customData: [String: String]
   
   init(id: UUID = UUID(),
        templateId: UUID,
        name: String,
        description: String,
        category: ItemCategory,
        rarity: ItemRarity,
        quantity: Int = 1,
        weight: Float,
        value: Int,
        iconAssetId: UUID? = nil,
        meshAssetId: UUID? = nil,
        isStackable: Bool = false,
        isEquippable: Bool = false,
        equipSlot: EquipSlot? = nil,
        stats: [ItemStat] = [],
        effects: [ItemEffect] = [],
        requirements: [ItemRequirement] = [],
        durability: Int = 1,
        maxDurability: Int = 1,
        isEquipped: Bool = false,
        dateAdded: Date = Date(),
        enhancements: [ItemEnhancement] = [],
        customData: [String: String] = [:]) {
       
       self.id = id
       self.templateId = templateId
       self.name = name
       self.description = description
       self.category = category
       self.rarity = rarity
       self.quantity = quantity
       self.weight = weight
       self.value = value
       self.iconAssetId = iconAssetId
       self.meshAssetId = meshAssetId
       self.isStackable = isStackable
       self.isEquippable = isEquippable
       self.equipSlot = equipSlot
       self.stats = stats
       self.effects = effects
       self.requirements = requirements
       self.durability = durability
       self.maxDurability = maxDurability
       self.isEquipped = isEquipped
       self.dateAdded = dateAdded
       self.enhancements = enhancements
       self.customData = customData
   }
}

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
   case all = "All"
   case equipment = "Equipment"
   case consumable = "Consumables"
   case material = "Materials"
   case quest = "Quest Items"
   case tool = "Tools"
   case misc = "Miscellaneous"
   
   var id: String { rawValue }
   
   var iconSystemName: String {
       switch self {
       case .all: return "square.grid.2x2"
       case .equipment: return "shield"
       case .consumable: return "drop.fill"
       case .material: return "cube.fill"
       case .quest: return "scroll"
       case .tool: return "wrench.fill"
       case .misc: return "questionmark.circle"
       }
   }
   
   var displayColor: Color {
       switch self {
       case .all: return .primary
       case .equipment: return .blue
       case .consumable: return .green
       case .material: return .orange
       case .quest: return .yellow
       case .tool: return .purple
       case .misc: return .gray
       }
   }
}

enum ItemRarity: String, Codable, CaseIterable, Identifiable {
   case common = "Common"
   case uncommon = "Uncommon"
   case rare = "Rare"
   case epic = "Epic"
   case legendary = "Legendary"
   case artifact = "Artifact"
   
   var id: String { rawValue }
   
   var color: CodableColor {
       switch self {
       case .common: return CodableColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
       case .uncommon: return CodableColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
       case .rare: return CodableColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0)
       case .epic: return CodableColor(red: 0.6, green: 0.0, blue: 1.0, alpha: 1.0)
       case .legendary: return CodableColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
       case .artifact: return CodableColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
       }
   }
   
   var swiftUIColor: Color {
       return color.swiftUIColor
   }
}

enum EquipSlot: String, Codable, CaseIterable, Identifiable {
   case head = "Head"
   case chest = "Chest"
   case legs = "Legs"
   case feet = "Feet"
   case hands = "Hands"
   case mainHand = "Main Hand"
   case offHand = "Off Hand"
   case ring = "Ring"
   case necklace = "Necklace"
   case back = "Back"
   case belt = "Belt"
   case wrist = "Wrist"
   
   var id: String { rawValue }
   
   var iconSystemName: String {
       switch self {
       case .head: return "head.profile"
       case .chest: return "person.fill"
       case .legs: return "figure.walk"
       case .feet: return "shoe.fill"
       case .hands: return "hand.raised.fill"
       case .mainHand: return "sword"
       case .offHand: return "shield.fill"
       case .ring: return "circle"
       case .necklace: return "link"
       case .back: return "backpack.fill"
       case .belt: return "belt"
       case .wrist: return "watch"
       }
   }
}

struct ItemStat: Codable, Equatable, Identifiable {
   let id = UUID()
   let type: StatType
   var value: Int
   
   enum StatType: String, Codable, CaseIterable {
       case attack = "Attack"
       case defense = "Defense"
       case speed = "Speed"
       case health = "Health"
       case mana = "Mana"
       case luck = "Luck"
       case criticalChance = "Critical Chance"
       case criticalDamage = "Critical Damage"
       case resonance = "Resonance"
       case harmony = "Harmony"
       case durabilityBonus = "Durability Bonus"
       case experienceBonus = "Experience Bonus"
       case goldFind = "Gold Find"
       case magicFind = "Magic Find"
       
       var iconSystemName: String {
           switch self {
           case .attack: return "sword.fill"
           case .defense: return "shield.fill"
           case .speed: return "bolt.fill"
           case .health: return "heart.fill"
           case .mana: return "drop.fill"
           case .luck: return "star.fill"
           case .criticalChance: return "target"
           case .criticalDamage: return "burst.fill"
           case .resonance: return "waveform"
           case .harmony: return "music.note"
           case .durabilityBonus: return "hammer.fill"
           case .experienceBonus: return "chart.line.uptrend.xyaxis"
           case .goldFind: return "dollarsign.circle.fill"
           case .magicFind: return "sparkles"
           }
       }
       
       var displayColor: Color {
           switch self {
           case .attack: return .red
           case .defense: return .blue
           case .speed: return .green
           case .health: return .pink
           case .mana: return .cyan
           case .luck: return .yellow
           case .criticalChance, .criticalDamage: return .orange
           case .resonance, .harmony: return .purple
           case .durabilityBonus: return .brown
           case .experienceBonus: return .indigo
           case .goldFind: return .yellow
           case .magicFind: return .mint
           }
       }
   }
   
   private enum CodingKeys: String, CodingKey {
       case type, value
   }
}

struct ItemEffect: Codable, Equatable, Identifiable {
   let id = UUID()
   let type: EffectType
   let duration: TimeInterval
   let description: String
   
   enum EffectType: Codable, Equatable {
       case healHealth(amount: Int)
       case restoreMana(amount: Int)
       case buffStat(stat: ItemStat.StatType, amount: Int, duration: TimeInterval)
       case grantAbility(abilityId: UUID)
       case teleport(locationId: UUID)
       case summon(entityId: UUID)
       case transform(templateId: UUID)
       case areaEffect(radius: Float, effect: String)
       
       var displayName: String {
           switch self {
           case .healHealth(let amount):
               return "Heal \(amount) HP"
           case .restoreMana(let amount):
               return "Restore \(amount) MP"
           case .buffStat(let stat, let amount, _):
               return "+\(amount) \(stat.rawValue)"
           case .grantAbility:
               return "Grant Ability"
           case .teleport:
               return "Teleport"
           case .summon:
               return "Summon"
           case .transform:
               return "Transform"
           case .areaEffect(let radius, let effect):
               return "\(effect) (Radius: \(radius)m)"
           }
       }
   }
   
   private enum CodingKeys: String, CodingKey {
       case type, duration, description
   }
}

struct ItemRequirement: Codable, Equatable, Identifiable {
   let id = UUID()
   let type: RequirementType
   let value: Int
   let description: String
   
   enum RequirementType: String, Codable {
       case level = "Level"
       case stat = "Stat"
       case skill = "Skill"
       case quest = "Quest"
       case achievement = "Achievement"
       case reputation = "Reputation"
       case currency = "Currency"
       
       var iconSystemName: String {
           switch self {
           case .level: return "star.circle"
           case .stat: return "chart.bar"
           case .skill: return "graduationcap"
           case .quest: return "scroll"
           case .achievement: return "trophy"
           case .reputation: return "hand.thumbsup"
           case .currency: return "dollarsign.circle"
           }
       }
   }
   
   private enum CodingKeys: String, CodingKey {
       case type, value, description
   }
}

struct ItemEnhancement: Codable, Equatable, Identifiable {
   let id: UUID
   let type: EnhancementType
   let name: String
   let description: String
   let appliedAt: Date
   let appliedBy: String?
   
   enum EnhancementType: Codable, Equatable {
       case statBonus(stat: ItemStat.StatType, amount: Int)
       case durabilityBonus(amount: Int)
       case specialEffect(effect: ItemEffect)
       case socketGem(gemId: UUID)
       case enchantment(enchantmentId: UUID)
       case upgrade(level: Int)
       
       var displayName: String {
           switch self {
           case .statBonus(let stat, let amount):
               return "+\(amount) \(stat.rawValue)"
           case .durabilityBonus(let amount):
               return "+\(amount) Durability"
           case .specialEffect:
               return "Special Effect"
           case .socketGem:
               return "Socket Gem"
           case .enchantment:
               return "Enchantment"
           case .upgrade(let level):
               return "Upgrade +\(level)"
           }
       }
       
       var rarity: ItemRarity {
           switch self {
           case .statBonus(_, let amount):
               return amount > 20 ? .legendary : amount > 10 ? .epic : .rare
           case .durabilityBonus(let amount):
               return amount > 50 ? .epic : .rare
           case .specialEffect:
               return .legendary
           case .socketGem:
               return .epic
           case .enchantment:
               return .artifact
           case .upgrade(let level):
               return level > 10 ? .artifact : level > 5 ? .legendary : .epic
           }
       }
   }
}

// MARK: - Item Templates and Recipes

struct ItemTemplate: Identifiable, Codable {
   let id: UUID
   let name: String
   let description: String
   let category: ItemCategory
   let rarity: ItemRarity
   let weight: Float
   let value: Int
   let iconAssetId: UUID?
   let meshAssetId: UUID?
   let isStackable: Bool
   let isEquippable: Bool
   let equipSlot: EquipSlot?
   let stats: [ItemStat]
   let effects: [ItemEffect]
   let requirements: [ItemRequirement]
   let maxDurability: Int
   let craftingRecipe: CraftingRecipe?
   let dropRate: Float
   let vendorPrice: Int?
   let tags: [String]
}

struct CraftingRecipe: Codable, Identifiable {
   let id: UUID
   let name: String
   let description: String
   let materials: [CraftingMaterial]
   let resultTemplateId: UUID
   let resultQuantity: Int
   let skillRequired: String?
   let skillLevel: Int
   let craftingTime: TimeInterval
   let successRate: Float
   let experienceGained: Int
   let requiredTools: [UUID]
   let requiredLocation: String?
}

struct CraftingMaterial: Codable, Identifiable {
   let id = UUID()
   let templateId: UUID
   let quantity: Int
   let name: String
   let isConsumed: Bool
   let qualityMatters: Bool
   
   private enum CodingKeys: String, CodingKey {
       case templateId, quantity, name, isConsumed, qualityMatters
   }
}

// MARK: - Item Template Library

class ItemTemplateLibrary: ObservableObject {
   static let shared = ItemTemplateLibrary()
   
   @Published private var templates: [UUID: ItemTemplate] = [:]
   @Published private var templatesByCategory: [ItemCategory: [ItemTemplate]] = [:]
   @Published private var templatesByRarity: [ItemRarity: [ItemTemplate]] = [:]
   
   private init() {
       loadDefaultTemplates()
       organizeTemplates()
   }
   
   func getTemplate(_ id: UUID) -> ItemTemplate? {
       return templates[id]
   }
   
   func getTemplates(category: ItemCategory) -> [ItemTemplate] {
       return templatesByCategory[category] ?? []
   }
   
   func getTemplates(rarity: ItemRarity) -> [ItemTemplate] {
       return templatesByRarity[rarity] ?? []
   }
   
   func getStartingItems() -> [ItemTemplate] {
       return Array(templates.values.filter { $0.tags.contains("starter") }.prefix(5))
   }
   
   func getAllTemplates() -> [ItemTemplate] {
       return Array(templates.values)
   }
   
   func searchTemplates(_ query: String) -> [ItemTemplate] {
       let lowercaseQuery = query.lowercased()
       return templates.values.filter { template in
           template.name.lowercased().contains(lowercaseQuery) ||
           template.description.lowercased().contains(lowercaseQuery) ||
           template.tags.contains { $0.lowercased().contains(lowercaseQuery) }
       }
   }
   
   private func organizeTemplates() {
       templatesByCategory = Dictionary(grouping: templates.values) { $0.category }
       templatesByRarity = Dictionary(grouping: templates.values) { $0.rarity }
   }
   
   private func loadDefaultTemplates() {
       // Basic Sword
       let basicSwordId = UUID()
       let basicSword = ItemTemplate(
           id: basicSwordId,
           name: "Basic Sword",
           description: "A simple iron sword for beginning adventurers",
           category: .equipment,
           rarity: .common,
           weight: 2.5,
           value: 100,
           iconAssetId: nil,
           meshAssetId: nil,
           isStackable: false,
           isEquippable: true,
           equipSlot: .mainHand,
           stats: [ItemStat(type: .attack, value: 10)],
           effects: [],
           requirements: [ItemRequirement(type: .level, value: 1, description: "Requires level 1")],
           maxDurability: 100,
           craftingRecipe: nil,
           dropRate: 0.1,
           vendorPrice: 75,
           tags: ["starter", "weapon", "melee"]
       )
       
       // Health Potion
       let healthPotionId = UUID()
       let healthPotion = ItemTemplate(
           id: healthPotionId,
           name: "Health Potion",
           description: "Restores 50 health points when consumed",
           category: .consumable,
           rarity: .common,
           weight: 0.5,
           value: 25,
           iconAssetId: nil,
           meshAssetId: nil,
           isStackable: true,
           isEquippable: false,
           equipSlot: nil,
           stats: [],
           effects: [ItemEffect(type: .healHealth(amount: 50), duration: 0, description: "Heals 50 HP")],
           requirements: [],
           maxDurability: 1,
           craftingRecipe: nil,
           dropRate: 0.3,
           vendorPrice: 20,
           tags: ["starter", "healing", "potion"]
       )
       
       // Iron Ore
       let ironOreId = UUID()
       let ironOre = ItemTemplate(
           id: ironOreId,
           name: "Iron Ore",
           description: "Raw iron ore used in smithing",
           category: .material,
           rarity: .common,
           weight: 1.0,
           value: 5,
           iconAssetId: nil,
           meshAssetId: nil,
           isStackable: true,
           isEquippable: false,
           equipSlot: nil,
           stats: [],
           effects: [],
           requirements: [],
           maxDurability: 1,
           craftingRecipe: nil,
           dropRate: 0.4,
           vendorPrice: 3,
           tags: ["material", "smithing", "ore"]
       )
       
       // Ancient Scroll
       let ancientScrollId = UUID()
       let ancientScroll = ItemTemplate(
           id: ancientScrollId,
           name: "Ancient Scroll",
           description: "A mysterious scroll with unknown writing",
           category: .quest,
           rarity: .rare,
           weight: 0.1,
           value: 1000,
           iconAssetId: nil,
           meshAssetId: nil,
           isStackable: false,
           isEquippable: false,
           equipSlot: nil,
           stats: [],
           effects: [],
           requirements: [],
           maxDurability: 1,
           craftingRecipe: nil,
           dropRate: 0.01,
           vendorPrice: nil, // Cannot be sold
           tags: ["quest", "ancient", "scroll"]
       )
       
       // Mining Pick
       let miningPickId = UUID()
       let miningPick = ItemTemplate(
           id: miningPickId,
           name: "Mining Pick",
           description: "A sturdy tool for mining ore and gems",
           category: .tool,
           rarity: .common,
           weight: 3.0,
           value: 150,
           iconAssetId: nil,
           meshAssetId: nil,
           isStackable: false,
           isEquippable: true,
           equipSlot: .mainHand,
           stats: [ItemStat(type: .durabilityBonus, value: 25)],
           effects: [],
           requirements: [ItemRequirement(type: .skill, value: 10, description: "Requires Mining skill 10")],
           maxDurability: 200,
           craftingRecipe: nil,
           dropRate: 0.05,
           vendorPrice: 120,
           tags: ["tool", "mining", "pick"]
       )
       
       // Store templates
       templates[basicSwordId] = basicSword
       templates[healthPotionId] = healthPotion
       templates[ironOreId] = ironOre
       templates[ancientScrollId] = ancientScroll
       templates[miningPickId] = miningPick
   }
   
   func addTemplate(_ template: ItemTemplate) {
       templates[template.id] = template
       organizeTemplates()
   }
   
   func removeTemplate(_ id: UUID) {
       templates.removeValue(forKey: id)
       organizeTemplates()
   }
}

// MARK: - Persistence Manager

class InventoryPersistenceManager: ObservableObject {
   private let fileManager = FileManager.default
   private let documentsDirectory: URL
   private let inventoryFileName = "inventory.json"
   private let templatesFileName = "item_templates.json"
   
   init() {
       documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
       createDirectoryIfNeeded()
   }
   
   private func createDirectoryIfNeeded() {
       let inventoryDirectory = documentsDirectory.appendingPathComponent("Inventory")
       
       if !fileManager.fileExists(atPath: inventoryDirectory.path) {
           try? fileManager.createDirectory(at: inventoryDirectory, withIntermediateDirectories: true)
       }
   }
   
   func saveInventory(_ items: [InventoryItem]) async throws {
       let url = documentsDirectory.appendingPathComponent("Inventory").appendingPathComponent(inventoryFileName)
       
       let encoder = JSONEncoder()
       encoder.dateEncodingStrategy = .iso8601
       encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
       
       let data = try encoder.encode(items)
       try data.write(to: url)
   }
   
   func loadInventory() async throws -> [InventoryItem] {
       let url = documentsDirectory.appendingPathComponent("Inventory").appendingPathComponent(inventoryFileName)
       
       guard fileManager.fileExists(atPath: url.path) else {
           return []
       }
       
       let data = try Data(contentsOf: url)
       
       let decoder = JSONDecoder()
       decoder.dateDecodingStrategy = .iso8601
       
       return try decoder.decode([InventoryItem].self, from: data)
   }
   
   func saveTemplates(_ templates: [ItemTemplate]) async throws {
       let url = documentsDirectory.appendingPathComponent("Inventory").appendingPathComponent(templatesFileName)
       
       let encoder = JSONEncoder()
       encoder.dateEncodingStrategy = .iso8601
       encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
       
       let data = try encoder.encode(templates)
       try data.write(to: url)
   }
   
   func loadTemplates() async throws -> [ItemTemplate] {
       let url = documentsDirectory.appendingPathComponent("Inventory").appendingPathComponent(templatesFileName)
       
       guard fileManager.fileExists(atPath: url.path) else {
           return []
       }
       
       let data = try Data(contentsOf: url)
       
       let decoder = JSONDecoder()
       decoder.dateDecodingStrategy = .iso8601
       
       return try decoder.decode([ItemTemplate].self, from: data)
   }
   
   func exportInventory(_ items: [InventoryItem]) async throws -> URL {
       let timestamp = DateFormatter.filenameSafe.string(from: Date())
       let fileName = "inventory_export_\(timestamp).json"
       let url = documentsDirectory.appendingPathComponent(fileName)
       
       let encoder = JSONEncoder()
       encoder.dateEncodingStrategy = .iso8601
       encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
       
       let exportData = InventoryExport(
           version: "1.0",
           exportDate: Date(),
           itemCount: items.count,
           items: items
       )
       
       let data = try encoder.encode(exportData)
       try data.write(to: url)
       
       return url
   }
   
   func importInventory(from url: URL) async throws -> [InventoryItem] {
       let data = try Data(contentsOf: url)
       
       let decoder = JSONDecoder()
       decoder.dateDecodingStrategy = .iso8601
       
       let exportData = try decoder.decode(InventoryExport.self, from: data)
       return exportData.items
   }
}

struct InventoryExport: Codable {
   let version: String
   let exportDate: Date
   let itemCount: Int
   let items: [InventoryItem]
}

extension DateFormatter {
   static let filenameSafe: DateFormatter = {
       let formatter = DateFormatter()
       formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
       return formatter
   }()
}

// MARK: - Notification Names

extension Notification.Name {
   // Item events
   static let itemAdded = Notification.Name("itemAdded")
   static let itemRemoved = Notification.Name("itemRemoved")
   static let itemEquipped = Notification.Name("itemEquipped")
   static let itemUnequipped = Notification.Name("itemUnequipped")
   static let itemUsed = Notification.Name("itemUsed")
   static let itemRepaired = Notification.Name("itemRepaired")
   static let itemEnhanced = Notification.Name("itemEnhanced")
   static let itemCrafted = Notification.Name("itemCrafted")
   
   // Player effects
   static let healPlayer = Notification.Name("healPlayer")
   static let restorePlayerMana = Notification.Name("restorePlayerMana")
   static let applyStatBuff = Notification.Name("applyStatBuff")
   static let grantTemporaryAbility = Notification.Name("grantTemporaryAbility")
   static let removeTemporaryAbility = Notification.Name("removeTemporaryAbility")
   
   // Inventory events
   static let inventoryChanged = Notification.Name("inventoryChanged")
   static let inventoryFull = Notification.Name("inventoryFull")
   static let inventoryWeightLimitReached = Notification.Name("inventoryWeightLimitReached")
}
