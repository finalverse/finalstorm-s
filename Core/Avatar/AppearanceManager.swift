//
//  Core/Avatar/AppearanceManager.swift
//  FinalStorm
//
//  Manages avatar appearance and customization
//

import RealityKit
import CoreFoundation

class AppearanceManager {
    func generateMaterials(for appearance: AvatarAppearance) async throws -> [Material] {
        var materials: [Material] = []
        
        // Skin material using direct color values
        var skinMaterial = PhysicallyBasedMaterial()
        let skinColors = appearance.skinTone.toColorValues()
        
        #if os(visionOS) || os(iOS) || os(macOS)
        skinMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(
            tint: .init(red: CGFloat(skinColors.red),
                       green: CGFloat(skinColors.green),
                       blue: CGFloat(skinColors.blue),
                       alpha: 1.0)
        )
        #else
        // Fallback for other platforms
        skinMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(
            tint: .white
        )
        #endif
        
        skinMaterial.roughness = 0.7
        skinMaterial.metallic = 0.0
        materials.append(skinMaterial)
        
        // Clothing materials
        for clothing in appearance.clothing {
            let clothingMaterial = createClothingMaterial(for: clothing)
            materials.append(clothingMaterial)
        }
        
        return materials
    }
    
    func applyMorphs(to baseMesh: MeshResource, appearance: AvatarAppearance) -> MeshResource {
        // In a real implementation, this would apply blend shapes/morphs
        // For now, return the base mesh
        return baseMesh
    }
    
    private func createClothingMaterial(for item: AvatarAppearance.ClothingItem) -> Material {
        var material = PhysicallyBasedMaterial()
        
        #if os(visionOS) || os(iOS) || os(macOS)
        material.baseColor = PhysicallyBasedMaterial.BaseColor(
            tint: .init(red: CGFloat(item.primaryColor.red),
                       green: CGFloat(item.primaryColor.green),
                       blue: CGFloat(item.primaryColor.blue),
                       alpha: CGFloat(item.primaryColor.alpha))
        )
        #else
        // Fallback
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white)
        #endif
        
        material.roughness = 0.8
        material.metallic = 0.1
        
        return material
    }
    func loadAppearanceData(for avatarID: String) async -> AvatarAppearance {
        // Placeholder: return a default appearance for now
        return AvatarAppearance.default
    }

    func applyAppearance(_ appearance: AvatarAppearance, to entity: Entity) {
        Task {
            do {
                let materials = try await generateMaterials(for: appearance)
                if let modelEntity = entity as? ModelEntity {
                    for (index, material) in materials.enumerated() {
                        if index < modelEntity.model?.materials.count ?? 0 {
                            modelEntity.model?.materials[index] = material
                        }
                    }
                }
            } catch {
                print("Failed to apply appearance: \(error)")
            }
        }
    }
}
