//
//  Melody.swift
//  FinalStorm
//
//  Melody types for songweaving in the Finalverse
//  Represents the musical abilities players can use to interact with the world
//

import Foundation
import SwiftUI  // Use SwiftUI for cross-platform Color support

// MARK: - Melody Type
/// Categories of melodies that determine their effects and requirements
enum MelodyType: String, Codable, CaseIterable {
    case restoration = "Restoration"    // Healing and renewal
    case exploration = "Exploration"    // Discovery and revelation
    case creation = "Creation"         // Manifestation and crafting
    case protection = "Protection"     // Shielding and defense
    case transformation = "Transformation"  // Change and evolution
    
    /// Get the primary effect color for UI representation
    var primaryColor: CodableColor {
        switch self {
        case .restoration: return .green
        case .exploration: return .blue
        case .creation: return .purple
        case .protection: return .yellow
        case .transformation: return .orange
        }
    }
    
    /// Base radius of effect for this melody type
    var effectRadius: Float {
        switch self {
        case .restoration: return 10.0
        case .exploration: return 15.0
        case .creation: return 20.0
        case .protection: return 12.0
        case .transformation: return 8.0
        }
    }
    
    /// Description of what this melody type does
    var description: String {
        switch self {
        case .restoration:
            return "Heals wounds, cures ailments, and restores harmony"
        case .exploration:
            return "Reveals hidden paths, uncovers secrets, and enhances perception"
        case .creation:
            return "Manifests objects, constructs, and magical effects"
        case .protection:
            return "Creates barriers, shields, and defensive wards"
        case .transformation:
            return "Changes the nature of objects, creatures, or environments"
        }
    }
}

// MARK: - Melody Struct
/// Represents a melody that can be woven by Songweavers
/// Each melody has different effects on the world's harmony and dissonance levels
struct Melody: Identifiable, Codable {
    let id: UUID
    let type: MelodyType
    var strength: Float              // Current power level (0.0 to 3.0)
    let duration: TimeInterval       // How long effects last in seconds
    let harmonyColor: CodableColor   // Visual representation color
    let requiredResonance: Float     // Minimum resonance needed to cast
    let harmonyBoost: Float          // Amount of harmony added to world
    let dissonanceReduction: Float   // Amount of dissonance removed
    
    /// Calculates the total harmony contribution based on current melody strength
    var harmonyContribution: Float {
        return harmonyBoost * strength
    }
    
    /// Determines if this melody can be cast with given resonance level
    func canBeCast(withResonance resonance: Float) -> Bool {
        return resonance >= requiredResonance
    }
    
    // MARK: - Predefined Melodies
    
    /// Melody of Restoration - heals and restores harmony to corrupted areas
    /// Primary healing melody for environmental and entity restoration
    static let restoration: Melody = {
        return Melody(
            id: UUID(),
            type: MelodyType.restoration,
            strength: 1.0,
            duration: 3.0,
            harmonyColor: CodableColor.green,
            requiredResonance: 10,
            harmonyBoost: 0.1,
            dissonanceReduction: 0.2
        )
    }()
    
    /// Melody of Exploration - reveals hidden paths and secrets
    /// Used for discovering ancient ruins, hidden passages, and lost knowledge
    static let exploration: Melody = {
        return Melody(
            id: UUID(),
            type: MelodyType.exploration,
            strength: 1.0,
            duration: 3.0,
            harmonyColor: CodableColor.blue,
            requiredResonance: 5,
            harmonyBoost: 0.05,
            dissonanceReduction: 0.1
        )
    }()
    
    /// Melody of Creation - forges new items and structures
    /// Powerful melody for crafting and building in the world
    static let creation: Melody = {
        return Melody(
            id: UUID(),
            type: MelodyType.creation,
            strength: 1.5,
            duration: 5.0,
            harmonyColor: CodableColor.purple,
            requiredResonance: 20,
            harmonyBoost: 0.2,
            dissonanceReduction: 0.3
        )
    }()
    
    /// Melody of Greeting - a simple melody for social interactions
    /// Low-power melody for NPC interactions and basic communication
    static let greeting: Melody = {
        return Melody(
            id: UUID(),
            type: MelodyType.exploration,
            strength: 0.5,
            duration: 2.0,
            harmonyColor: CodableColor.yellow,
            requiredResonance: 0,
            harmonyBoost: 0.02,
            dissonanceReduction: 0.05
        )
    }()
    
    /// Melody of Purification - powerful melody to cleanse deep corruption
    /// Advanced restoration melody for severe dissonance removal
    static let purification: Melody = {
        return Melody(
            id: UUID(),
            type: MelodyType.restoration,
            strength: 2.0,
            duration: 4.0,
            harmonyColor: CodableColor.white,
            requiredResonance: 30,
            harmonyBoost: 0.3,
            dissonanceReduction: 0.5
        )
    }()
    
    // MARK: - Melody Aliases
    // Convenient aliases for specific use cases to improve code readability
    
    /// Reveals hidden objects and secrets - alias for exploration
    static let illumination: Melody = exploration
    
    /// Analyzes unknown artifacts and ancient items - alias for exploration
    static let analysis: Melody = exploration
    
    /// Accelerates natural growth and healing - alias for restoration
    static let growth: Melody = restoration
    
    /// Used in crafting and item creation - alias for creation
    static let forge: Melody = creation
}

// MARK: - Supporting Color Extension
/// Cross-platform color support for melody visualization
extension CodableColor {
    /// Predefined colors for common melody types
    static let green = CodableColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
    static let blue = CodableColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0)
    static let purple = CodableColor(red: 0.6, green: 0.0, blue: 0.8, alpha: 1.0)
    static let yellow = CodableColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0)
    static let orange = CodableColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
    static let white = CodableColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    static let gray = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    
}

// MARK: - Melody Collection Helpers
extension Melody {
    /// Returns all predefined melodies for selection UI
    static var allPredefinedMelodies: [Melody] {
        return [restoration, exploration, creation, greeting, purification]
    }
    
    /// Returns melodies filtered by type for categorized UI
    static func melodies(ofType type: MelodyType) -> [Melody] {
        return allPredefinedMelodies.filter { $0.type == type }
    }
    
    /// Returns melodies that can be cast with given resonance level
    static func availableMelodies(forResonance resonance: Float) -> [Melody] {
        return allPredefinedMelodies.filter { $0.canBeCast(withResonance: resonance) }
    }
}
