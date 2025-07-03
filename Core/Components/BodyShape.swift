//
//  BodyShape.swift
//  FinalStorm
//
//  Avatar body shape definitions
//

import Foundation

enum BodyShape: String, CaseIterable, Codable {
    case slim = "Slim"
    case average = "Average"
    case athletic = "Athletic"
    case muscular = "Muscular"
    case heavy = "Heavy"
    
    var scaleModifiers: SIMD3<Float> {
        switch self {
        case .slim:
            return SIMD3<Float>(0.9, 1.0, 0.9)
        case .average:
            return SIMD3<Float>(1.0, 1.0, 1.0)
        case .athletic:
            return SIMD3<Float>(1.05, 1.0, 1.05)
        case .muscular:
            return SIMD3<Float>(1.15, 1.0, 1.15)
        case .heavy:
            return SIMD3<Float>(1.25, 0.95, 1.25)
        }
    }
}

// Remove the CodableColor redeclaration - it's already defined in CodableColor.swift
// typealias Color = CodableColor  // REMOVED

enum HairStyle: String, CaseIterable, Codable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"
    case ponytail = "Ponytail"
    case bald = "Bald"
}

struct ClothingItem: Codable {
    let id: String
    let name: String
    let type: ClothingType
    
    static let defaultShirt = ClothingItem(
        id: "default_shirt",
        name: "Simple Shirt",
        type: .top
    )
    
    static let defaultPants = ClothingItem(
        id: "default_pants",
        name: "Simple Pants",
        type: .bottom
    )
}

enum ClothingType: String, Codable {
    case top
    case bottom
    case shoes
    case accessory
}

struct Accessory: Codable {
    let id: String
    let name: String
    let attachPoint: AttachPoint
}

enum AttachPoint: String, Codable {
    case head
    case neck
    case leftHand
    case rightHand
    case back
}
