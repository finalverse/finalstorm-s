//
//  Melody.swift
//  FinalStorm
//
//  Melody types for songweaving
//

import Foundation
import UIKit

struct Melody: Identifiable {
    let id: UUID
    let type: MelodyType
    var strength: Float
    let duration: TimeInterval
    let harmonyColor: UIColor
    let requiredResonance: Float
    let harmonyBoost: Float
    let dissonanceReduction: Float
    
    var harmonyContribution: Float {
        harmonyBoost * strength
    }
    
    // Predefined melodies
    static let restoration = Melody(
        id: UUID(),
        type: .restoration,
        strength: 1.0,
        duration: 3.0,
        harmonyColor: .systemGreen,
        requiredResonance: 10,
        harmonyBoost: 0.1,
        dissonanceReduction: 0.2
    )
    
    static let exploration = Melody(
        id: UUID(),
        type: .exploration,
        strength: 1.0,
        duration: 3.0,
        harmonyColor: .systemBlue,
        requiredResonance: 5,
        harmonyBoost: 0.05,
        dissonanceReduction: 0.1
    )
    
    static let creation = Melody(
        id: UUID(),
        type: .creation,
        strength: 1.5,
        duration: 5.0,
        harmonyColor: .systemPurple,
        requiredResonance: 20,
        harmonyBoost: 0.2,
        dissonanceReduction: 0.3
    )
    
    static let greeting = Melody(
        id: UUID(),
        type: .exploration,
        strength: 0.5,
        duration: 2.0,
        harmonyColor: .systemYellow,
        requiredResonance: 0,
        harmonyBoost: 0.02,
        dissonanceReduction: 0.05
    )
    
    static let purification = Melody(
        id: UUID(),
        type: .restoration,
        strength: 2.0,
        duration: 4.0,
        harmonyColor: .white,
        requiredResonance: 30,
        harmonyBoost: 0.3,
        dissonanceReduction: 0.5
    )
    
    static let illumination = exploration
    static let analysis = exploration
    static let growth = restoration
    static let forge = creation
}

enum MelodyType: String, Codable {
    case restoration
    case exploration
    case creation
    
    var effectRadius: Float {
        switch self {
        case .restoration: return 10.0
        case .exploration: return 15.0
        case .creation: return 20.0
        }
    }
}
