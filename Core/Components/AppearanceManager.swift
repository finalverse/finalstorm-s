//
//  AppearanceManager.swift
//  FinalStorm
//
//  Manages avatar appearance and customization
//

import RealityKit

class AppearanceManager {
    func generateMaterials(for appearance: AvatarAppearance) async throws -> [Material] {
        var materials: [Material] = []
        
        // Skin material
        var skinMaterial = PhysicallyBasedMaterial()
        skinMaterial.baseColor = .color(appearance.skinTone.toUIColor())
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
    
    private func createClothingMaterial(for item: ClothingItem) -> Material {
        var material = PhysicallyBasedMaterial()
        
        // Set color based on clothing type
        switch item.type {
        case .top:
            material.baseColor = .color(.systemBlue)
        case .bottom:
            material.baseColor = .color(.systemGray)
        case .shoes:
            material.baseColor = .color(.black)
        case .accessory:
            material.baseColor = .color(.systemPurple)
        }
        
        material.roughness = 0.8
        material.metallic = 0.1
        
        return material
    }
}

extension CodableColor {
    func toUIColor() -> UIColor {
        return UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
