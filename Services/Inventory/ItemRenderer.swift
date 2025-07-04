//
//  Services/Inventory/ItemRenderer.swift
//  FinalStorm
//
//  Handles rendering of inventory items, icons, and 3D previews
//  Creates procedural icons and manages item visualization
//

import Foundation
import RealityKit
import Combine

@MainActor
class ItemRenderer: ObservableObject {
    // MARK: - Properties
    private var iconCache: [UUID: TextureResource] = [:]
    private var previewCache: [UUID: ModelEntity] = [:]
    private let renderQueue = DispatchQueue(label: "item.renderer", qos: .utility)
    
    // Icon generation settings
    private let iconSize: CGSize = CGSize(width: 128, height: 128)
    private let previewSize: CGSize = CGSize(width: 256, height: 256)
    
    // MARK: - Icon Management
    func getIcon(for itemId: UUID) async -> TextureResource? {
        return iconCache[itemId]
    }
    
    func cacheIcon(for itemId: UUID, texture: TextureResource) async {
        iconCache[itemId] = texture
    }
    
    func generateDefaultIcon(for category: ItemCategory, rarity: ItemRarity) async -> TextureResource {
        return await withCheckedContinuation { continuation in
            renderQueue.async {
                let icon = self.createProceduralIcon(category: category, rarity: rarity)
                
                Task { @MainActor in
                    continuation.resume(returning: icon)
                }
            }
        }
    }
    
    private func createProceduralIcon(category: ItemCategory, rarity: ItemRarity) -> TextureResource {
        // Create a simple colored icon based on category and rarity
        let backgroundColor = getCategoryColor(category)
        let borderColor = rarity.color
        
        // This would typically use Core Graphics to generate the icon
        // For now, return a simple colored texture
        return createSolidColorTexture(color: backgroundColor, borderColor: borderColor)
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
        default:
            return CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        }
    }
    
    private func createSolidColorTexture(color: CodableColor, borderColor: CodableColor) -> TextureResource {
        // Create a simple solid color texture with border
        // In a real implementation, this would use Core Graphics or Metal
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(iconSize.width),
            height: Int(iconSize.height),
            mipmapped: false
        )
        
        // For now, return a placeholder
        do {
            return try TextureResource.generate(from: CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha), width: Int(iconSize.width), height: Int(iconSize.height))
        } catch {
            // Fallback to a default texture
            return try! TextureResource.load(named: "DefaultIcon", in: .main)
        }
    }
    
    // MARK: - 3D Preview Generation
    func generate3DPreview(for item: InventoryItem, meshResource: MeshResource) async -> ModelEntity {
        if let cached = previewCache[item.id] {
            return cached
        }
        
        let model = ModelEntity(
            mesh: meshResource,
            materials: [createItemMaterial(for: item)]
        )
        
        // Add item-specific effects
        applyItemEffects(to: model, item: item)
        
        previewCache[item.id] = model
        return model
    }
    
    private func createItemMaterial(for item: InventoryItem) -> Material {
        var material = PhysicallyBasedMaterial()
        
        // Base color based on rarity
        let rarityColor = item.rarity.color
        material.baseColor = PhysicallyBasedMaterial.BaseColor(
            tint: UIColor(
                red: CGFloat(rarityColor.red),
                green: CGFloat(rarityColor.green),
                blue: CGFloat(rarityColor.blue),
                alpha: CGFloat(rarityColor.alpha)
            )
        )
        
        // Material properties based on item category
        switch item.category {
        case .equipment:
            material.metallic = 0.8
            material.roughness = 0.2
        case .material:
            material.metallic = 0.1
            material.roughness = 0.9
        default:
            material.metallic = 0.3
            material.roughness = 0.5
        }
        
        // Add glow for magical items
        if item.rarity == .legendary || item.rarity == .artifact {
            material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: UIColor(
                red: CGFloat(rarityColor.red),
                green: CGFloat(rarityColor.green),
                blue: CGFloat(rarityColor.blue),
                alpha: 1.0
            ))
            material.emissiveIntensity = 0.3
        }
        
        return material
    }
    
    private func applyItemEffects(to model: ModelEntity, item: InventoryItem) {
        // Add particle effects for special items
        if item.rarity.sortOrder >= ItemRarity.epic.sortOrder {
            addParticleEffect(to: model, rarity: item.rarity)
        }
        
        // Add rotation animation
        let rotation = FromToByAnimation(
            by: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
            duration: 8.0,
            bindTarget: .transform
        )
        
        if let rotationResource = try? AnimationResource.generate(with: rotation) {
            model.playAnimation(rotationResource.repeat())
        }
        
        // Adjust scale based on item type
        let scale = getItemScale(for: item.category)
        model.scale = scale
    }
    
    private func addParticleEffect(to model: ModelEntity, rarity: ItemRarity) {
        var particles = ParticleEmitterComponent()
        particles.birthRate = 20
        particles.emitterShape = .box
        particles.mainEmitter.lifeSpan = 2.0
        particles.mainEmitter.speed = 0.1
        particles.mainEmitter.size = 0.01
        
        // Color based on rarity
        let rarityColor = rarity.color
        particles.mainEmitter.color = .single(UIColor(
            red: CGFloat(rarityColor.red),
            green: CGFloat(rarityColor.green),
            blue: CGFloat(rarityColor.blue),
            alpha: 1.0
        ))
        
        particles.mainEmitter.opacityOverLife = .linearFade
        model.components.set(particles)
    }
    
    private func getItemScale(for category: ItemCategory) -> SIMD3<Float> {
        switch category {
        case .equipment:
            return SIMD3<Float>(1.2, 1.2, 1.2)
        case .consumable:
            return SIMD3<Float>(0.8, 0.8, 0.8)
        case .material:
            return SIMD3<Float>(0.6, 0.6, 0.6)
        default:
            return SIMD3<Float>(1.0, 1.0, 1.0)
        }
    }
    
    // MARK: - Cache Management
    func clearCache() {
        iconCache.removeAll()
        previewCache.removeAll()
    }
    
    func getCacheInfo() -> (iconCount: Int, previewCount: Int) {
        return (iconCache.count, previewCache.count)
    }
}
