//
//  Core/Components/AvatarComponents.swift
//  FinalStorm
//
//  Shared avatar-related components and types - SINGLE DEFINITION of InteractionComponent
//

import Foundation
import RealityKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform-agnostic Color
struct PlatformColor {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float
    
    #if canImport(UIKit)
    var nativeColor: UIColor {
        return UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    #elseif canImport(AppKit)
    var nativeColor: NSColor {
        return NSColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    #endif
}

// MARK: - Avatar Appearance
struct AvatarAppearance: Codable {
    enum BodyShape: String, Codable {
        case slim, average, athletic, heavy
    }
    
    enum SkinTone: String, Codable {
        case pale, light, medium, tan, dark
        
        func toPlatformColor() -> PlatformColor {
            switch self {
            case .pale: return PlatformColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            case .light: return PlatformColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
            case .medium: return PlatformColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
            case .tan: return PlatformColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
            case .dark: return PlatformColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)
            }
        }
        
        // Direct color values for RealityKit
        func toColorValues() -> (red: Float, green: Float, blue: Float) {
            switch self {
            case .pale: return (0.95, 0.95, 0.95)
            case .light: return (0.85, 0.85, 0.85)
            case .medium: return (0.75, 0.75, 0.75)
            case .tan: return (0.65, 0.65, 0.65)
            case .dark: return (0.45, 0.45, 0.45)
            }
        }
    }
    
    enum HairStyle: String, Codable {
        case short, medium, long, braided, ponytail
    }
    
    struct ClothingItem: Codable {
        let type: ClothingType
        let primaryColor: CodableColor
        let secondaryColor: CodableColor?
        
        static let defaultShirt = ClothingItem(
            type: .shirt,
            primaryColor: .blue,
            secondaryColor: nil
        )
        
        static let defaultPants = ClothingItem(
            type: .pants,
            primaryColor: .gray,
            secondaryColor: nil
        )
    }
    
    enum ClothingType: String, Codable {
        case shirt, pants, robe, armor, boots, gloves
    }
    
    struct Accessory: Codable {
        let type: AccessoryType
        let materialName: String  // Reference to material by name instead of direct Material
    }
    
    enum AccessoryType: String, Codable {
        case necklace, ring, bracelet, earring, headpiece
    }
    
    var bodyShape: BodyShape
    var skinTone: SkinTone
    var hairStyle: HairStyle
    var clothing: [ClothingItem]
    var accessories: [Accessory]
    
    static let `default` = AvatarAppearance(
        bodyShape: .average,
        skinTone: .medium,
        hairStyle: .medium,
        clothing: [.defaultShirt, .defaultPants],
        accessories: []
    )
}

// MARK: - Songweaver Component
struct SongweaverComponent: Component, Codable {
    var resonanceLevel: ResonanceLevel
    var knownMelodies: [UUID] = []  // Store melody IDs instead of full objects
    var activeHarmonies: [UUID] = []  // Store harmony IDs instead of full objects
    
    func canPerform(_ melody: Melody) -> Bool {
        // Check if resonance level meets requirements
        switch melody.type {
        case .restoration:
            return resonanceLevel.restorationResonance >= melody.requiredResonance
        case .exploration:
            return resonanceLevel.explorationResonance >= melody.requiredResonance
        case .creation:
            return resonanceLevel.creativeResonance >= melody.requiredResonance
        default:
            return false
        }
    }
}

// MARK: - Harmony Component
struct HarmonyComponent: Component, Codable {
    var harmonyLevel: Float = 1.0
    var dissonanceLevel: Float = 0.0
    var activeEffects: [UUID] = []  // Store effect IDs instead of full objects
    
    mutating func applyMelody(_ melody: Melody) {
        // Apply melody effects to harmony
        harmonyLevel += melody.harmonyBoost
        dissonanceLevel = max(0, dissonanceLevel - melody.dissonanceReduction)
        
        // Add time-based effect (stored separately in an effect manager)
        // This would be handled by the HarmonyService
    }
}

// MARK: - Interaction Component - SINGLE DEFINITION
struct InteractionComponent: Component {
    let interactionRadius: Float
    let requiresLineOfSight: Bool
    let interactionType: InteractionType
    var onInteract: (() -> Void)?
    
    init(interactionRadius: Float = 2.0,
         requiresLineOfSight: Bool = true,
         interactionType: InteractionType = .default,
         onInteract: (() -> Void)? = nil) {
        self.interactionRadius = interactionRadius
        self.requiresLineOfSight = requiresLineOfSight
        self.interactionType = interactionType
        self.onInteract = onInteract
    }
    
    enum InteractionType: String, Codable {
        case conversation
        case activate
        case pickup
        case songweave
        case `default`
        case talk
        case questGive
        case teach
        case accompany
    }
}
