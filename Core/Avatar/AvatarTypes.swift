// MARK: - CodableColor Static Constants
extension CodableColor {
    static let blue = CodableColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
    static let brown = CodableColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
    static let gray = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
}

//
//  Core/Avatar/AvatarTypes.swift
//  FinalStorm
//
//  Consolidated avatar appearance and customization types
//  Single source of truth for avatar-related data structures
//

import Foundation
import RealityKit

// MARK: - Avatar Appearance System

struct AvatarAppearance: Codable, Equatable {
    var bodyShape: BodyShape
    var skinTone: SkinTone
    var hairStyle: HairStyle
    var hairColor: CodableColor
    var eyeColor: CodableColor
    var clothing: [ClothingItem]
    var accessories: [Accessory]
    
    static let `default` = AvatarAppearance(
        bodyShape: .average,
        skinTone: .medium,
        hairStyle: .medium,
        hairColor: .brown,
        eyeColor: .brown,
        clothing: [.defaultShirt, .defaultPants],
        accessories: []
    )
}

// MARK: - Physical Attributes

enum BodyShape: String, CaseIterable, Codable {
    case slim = "Slim"
    case average = "Average"
    case athletic = "Athletic"
    case muscular = "Muscular"
    case heavy = "Heavy"
    
    var scaleModifiers: SIMD3<Float> {
        switch self {
        case .slim: return SIMD3<Float>(0.9, 1.0, 0.9)
        case .average: return SIMD3<Float>(1.0, 1.0, 1.0)
        case .athletic: return SIMD3<Float>(1.05, 1.0, 1.05)
        case .muscular: return SIMD3<Float>(1.15, 1.0, 1.15)
        case .heavy: return SIMD3<Float>(1.25, 0.95, 1.25)
        }
    }
}

enum SkinTone: String, CaseIterable, Codable {
    case pale, light, medium, tan, dark, ebony
    
    var colorValues: (red: Float, green: Float, blue: Float) {
        switch self {
        case .pale: return (0.95, 0.92, 0.88)
        case .light: return (0.85, 0.78, 0.70)
        case .medium: return (0.75, 0.65, 0.55)
        case .tan: return (0.65, 0.50, 0.40)
        case .dark: return (0.45, 0.35, 0.25)
        case .ebony: return (0.25, 0.20, 0.15)
        }
    }
}

enum HairStyle: String, CaseIterable, Codable {
    case bald, short, medium, long, ponytail, braided
    
    var meshAssetName: String {
        return "hair_\(rawValue.lowercased())"
    }
}

// MARK: - Clothing System

struct ClothingItem: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let type: ClothingType
    let primaryColor: CodableColor
    let secondaryColor: CodableColor?
    let meshAssetName: String
    let rarity: ItemRarity
    
    static let defaultShirt = ClothingItem(
        id: UUID(),
        name: "Simple Shirt",
        type: .shirt,
        primaryColor: .blue,
        secondaryColor: nil,
        meshAssetName: "shirt_default",
        rarity: .common
    )
    
    static let defaultPants = ClothingItem(
        id: UUID(),
        name: "Simple Pants",
        type: .pants,
        primaryColor: .gray,
        secondaryColor: nil,
        meshAssetName: "pants_default",
        rarity: .common
    )
}

enum ClothingType: String, CaseIterable, Codable {
    case shirt, pants, dress, robe, armor
    case boots, shoes, gloves, hat, cloak
    
    var equipSlot: EquipSlot {
        switch self {
        case .shirt, .dress, .robe, .armor: return .chest
        case .pants: return .legs
        case .boots, .shoes: return .feet
        case .gloves: return .hands
        case .hat: return .head
        case .cloak: return .back
        }
    }
}

struct Accessory: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let type: AccessoryType
    let attachPoint: AttachPoint
    let color: CodableColor
    
    enum AccessoryType: String, CaseIterable, Codable {
        case necklace, ring, bracelet, earring, headpiece
    }
    
    enum AttachPoint: String, CaseIterable, Codable {
        case head, neck, leftHand, rightHand, back
    }
}

// MARK: - Animation Support Types

enum EmoteType: String, CaseIterable, Codable {
    case wave
    case cheer
    case sit
    case dance
    case laugh
}

enum CombatAction: String, CaseIterable, Codable {
    case attack
    case block
    case dodge
    case cast
    case parry
}

enum InteractionType: String, CaseIterable, Codable {
    case pickup
    case activate
    case talk
    case trade
}

// MARK: - EquipSlot Enum
enum EquipSlot: String, Codable, CaseIterable {
    case head, chest, legs, feet, hands, back
}
