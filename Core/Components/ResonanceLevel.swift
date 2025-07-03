//
//  ResonanceLevel.swift
//  FinalStorm
//
//  Single definition for ResonanceLevel to avoid redeclaration
//

import Foundation

// MARK: - Resonance Level
struct ResonanceLevel: Codable {
    var creativeResonance: Float = 0
    var explorationResonance: Float = 0
    var restorationResonance: Float = 0
    
    var totalResonance: Float {
        creativeResonance + explorationResonance + restorationResonance
    }
    
    static let novice = ResonanceLevel()
    
    // Predefined levels for different stages
    static let apprentice = ResonanceLevel(
        creativeResonance: 25,
        explorationResonance: 25,
        restorationResonance: 25
    )
    
    static let adept = ResonanceLevel(
        creativeResonance: 75,
        explorationResonance: 75,
        restorationResonance: 75
    )
    
    static let master = ResonanceLevel(
        creativeResonance: 150,
        explorationResonance: 150,
        restorationResonance: 150
    )
    
    // Helper methods
    func canPerform(melodyType: MelodyType, requiredLevel: Float) -> Bool {
        switch melodyType {
        case .creation:
            return creativeResonance >= requiredLevel
        case .exploration:
            return explorationResonance >= requiredLevel
        case .restoration:
            return restorationResonance >= requiredLevel
        case .protection:
            return restorationResonance >= requiredLevel
        case .transformation:
            return creativeResonance >= requiredLevel
        }
    }
    
    mutating func gainExperience(type: MelodyType, amount: Float) {
        switch type {
        case .creation, .transformation:
            creativeResonance += amount
        case .exploration:
            explorationResonance += amount
        case .restoration, .protection:
            restorationResonance += amount
        }
    }
}
