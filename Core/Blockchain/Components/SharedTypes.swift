//
//  Core/Components/SharedTypes.swift
//  FinalStorm
//
//  Cross-cutting types used throughout the application
//  Platform-agnostic definitions and utility types
//

import Foundation
import SwiftUI
import simd
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform-Agnostic Color System

/// Universal color representation that works across all platforms
struct CodableColor: Codable, Equatable, Hashable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float
    
    init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    /// Convert to SwiftUI Color
    var swiftUIColor: Color {
        return Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }
    
    #if canImport(UIKit)
    var uiColor: UIColor {
        return UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
    #endif
    
    #if canImport(AppKit)
    var nsColor: NSColor {
        return NSColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
    #endif
    
    /// Get platform-specific native color
    var nativeColor: Any {
        #if canImport(UIKit)
        return uiColor
        #elseif canImport(AppKit)
        return nsColor
        #else
        return swiftUIColor
        #endif
    }
    
    /// Convert to SIMD4 for RealityKit
    var simd4: SIMD4<Float> {
        return SIMD4<Float>(red, green, blue, alpha)
    }
    
    /// Convert to CGColor for Core Graphics
    var cgColor: CGColor {
        #if canImport(UIKit)
        return uiColor.cgColor
        #elseif canImport(AppKit)
        return nsColor.cgColor
        #else
        return CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
        #endif
    }
}

// MARK: - Predefined Colors

extension CodableColor {
    static let white = CodableColor(red: 1.0, green: 1.0, blue: 1.0)
    static let black = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
    static let clear = CodableColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    
    // Primary colors
    static let red = CodableColor(red: 1.0, green: 0.0, blue: 0.0)
    static let green = CodableColor(red: 0.0, green: 1.0, blue: 0.0)
    static let blue = CodableColor(red: 0.0, green: 0.0, blue: 1.0)
    
    // Secondary colors
    static let cyan = CodableColor(red: 0.0, green: 1.0, blue: 1.0)
    static let magenta = CodableColor(red: 1.0, green: 0.0, blue: 1.0)
    static let yellow = CodableColor(red: 1.0, green: 1.0, blue: 0.0)
    
    // Common UI colors
    static let orange = CodableColor(red: 1.0, green: 0.6, blue: 0.0)
    static let purple = CodableColor(red: 0.6, green: 0.0, blue: 0.8)
    static let brown = CodableColor(red: 0.6, green: 0.4, blue: 0.2)
    static let pink = CodableColor(red: 1.0, green: 0.8, blue: 0.8)
    static let gray = CodableColor(red: 0.5, green: 0.5, blue: 0.5)
    static let lightGray = CodableColor(red: 0.8, green: 0.8, blue: 0.8)
    static let darkGray = CodableColor(red: 0.3, green: 0.3, blue: 0.3)
    
    // Finalverse-specific colors
    static let harmony = CodableColor(red: 0.0, green: 0.8, blue: 0.6)
    static let dissonance = CodableColor(red: 0.8, green: 0.2, blue: 0.2)
    static let resonance = CodableColor(red: 0.6, green: 0.4, blue: 1.0)
    static let corruption = CodableColor(red: 0.4, green: 0.1, blue: 0.4)
    static let song = CodableColor(red: 0.9, green: 0.9, blue: 0.3)
    
    // Echo colors
    static let lumi = CodableColor(red: 1.0, green: 0.9, blue: 0.0)
    static let kai = CodableColor(red: 0.0, green: 0.5, blue: 1.0)
    static let terra = CodableColor(red: 0.0, green: 0.8, blue: 0.0)
    static let ignis = CodableColor(red: 1.0, green: 0.6, blue: 0.0)
    static let gold = CodableColor(red: 1.0, green: 0.8, blue: 0.0)
    static let silver = CodableColor(red: 0.8, green: 0.8, blue: 0.8)
}

// MARK: - Echo System Types

enum EchoType: String, CaseIterable, Codable {
    case lumi = "Lumi"
    case kai = "KAI"
    case terra = "Terra"
    case ignis = "Ignis"
    
    var primaryColor: CodableColor {
        switch self {
        case .lumi: return .lumi
        case .kai: return .kai
        case .terra: return .terra
        case .ignis: return .ignis
        }
    }
    
    var personality: PersonalityType {
        switch self {
        case .lumi: return .playful
        case .kai: return .wise
        case .terra: return .protective
        case .ignis: return .friendly
        }
    }
    
    var voiceProfile: VoiceProfile {
        switch self {
        case .lumi: return VoiceProfile(pitch: 1.3, speed: 1.1, timbre: .bright)
        case .kai: return VoiceProfile(pitch: 0.9, speed: 0.95, timbre: .digital)
        case .terra: return VoiceProfile(pitch: 0.7, speed: 0.85, timbre: .warm)
        case .ignis: return VoiceProfile(pitch: 1.0, speed: 1.15, timbre: .bold)
        }
    }
}

struct VoiceProfile: Codable {
    let pitch: Float
    let speed: Float
    let timbre: VoiceTimbre
    
    enum VoiceTimbre: String, CaseIterable, Codable {
        case bright = "bright"
        case digital = "digital"
        case warm = "warm"
        case bold = "bold"
    }
}

// MARK: - Emotion System

enum Emotion: String, CaseIterable, Codable {
    case happy = "happy"
    case sad = "sad"
    case angry = "angry"
    case fearful = "fearful"
    case concerned = "concerned"
    case excited = "excited"
    case neutral = "neutral"
    case curious = "curious"
    case confused = "confused"
    case determined = "determined"
    
    var intensity: Float {
        switch self {
        case .excited, .angry: return 1.0
        case .happy, .fearful, .determined: return 0.8
        case .concerned, .sad, .curious: return 0.6
        case .confused: return 0.4
        case .neutral: return 0.5
        }
    }
    
    var color: CodableColor {
        switch self {
        case .happy: return .yellow
        case .sad: return .blue
        case .angry: return .red
        case .fearful: return .purple
        case .concerned: return .orange
        case .excited: return .magenta
        case .curious: return .green
        case .determined: return .cyan
        case .confused: return .gray
        case .neutral: return .lightGray
        }
    }
}

// MARK: - Guidance and Topics

enum GuidanceTopic: String, CaseIterable, Codable {
    case firstSteps = "firstSteps"
    case songweaving = "songweaving"
    case exploration = "exploration"
    case combat = "combat"
    case lore = "lore"
    case quests = "quests"
    case harmony = "harmony"
    case corruption = "corruption"
    case crafting = "crafting"
    case social = "social"
    
    var priority: Int {
        switch self {
        case .firstSteps: return 100
        case .songweaving: return 90
        case .combat: return 80
        case .quests: return 70
        case .exploration: return 60
        case .harmony: return 50
        case .corruption: return 40
        case .crafting: return 35
        case .social: return 30
        case .lore: return 20
        }
    }
    
    var description: String {
        switch self {
        case .firstSteps: return "Basic game mechanics and getting started"
        case .songweaving: return "Melody casting and harmony creation"
        case .exploration: return "World discovery and navigation"
        case .combat: return "Fighting and defensive strategies"
        case .lore: return "World history and background knowledge"
        case .quests: return "Mission objectives and progression"
        case .harmony: return "Balance and resonance management"
        case .corruption: return "Understanding and cleansing dissonance"
        case .crafting: return "Item creation and enhancement"
        case .social: return "NPC interactions and relationships"
        }
    }
}

// MARK: - Songweaving Core Types

enum MelodyType: String, Codable, CaseIterable {
    case restoration = "Restoration"
    case exploration = "Exploration"
    case creation = "Creation"
    case protection = "Protection"
    case transformation = "Transformation"
    
    var primaryColor: CodableColor {
        switch self {
        case .restoration: return .green
        case .exploration: return .blue
        case .creation: return .purple
        case .protection: return .yellow
        case .transformation: return .orange
        }
    }
    
    var effectRadius: Float {
        switch self {
        case .restoration: return 10.0
        case .exploration: return 15.0
        case .creation: return 20.0
        case .protection: return 12.0
        case .transformation: return 8.0
        }
    }
    
    var description: String {
        switch self {
        case .restoration: return "Heals wounds, cures ailments, and restores harmony"
        case .exploration: return "Reveals hidden paths, uncovers secrets, and enhances perception"
        case .creation: return "Manifests objects, constructs, and magical effects"
        case .protection: return "Creates barriers, shields, and defensive wards"
        case .transformation: return "Changes the nature of objects, creatures, or environments"
        }
    }
}

// MARK: - Resonance System

struct ResonanceLevel: Codable {
    var creativeResonance: Float = 0
    var explorationResonance: Float = 0
    var restorationResonance: Float = 0
    var protectionResonance: Float = 0
    var transformationResonance: Float = 0
    
    var totalResonance: Float {
        return creativeResonance + explorationResonance + restorationResonance + protectionResonance + transformationResonance
    }
    
    static let novice = ResonanceLevel()
    
    static let apprentice = ResonanceLevel(
        creativeResonance: 25,
        explorationResonance: 25,
        restorationResonance: 25,
        protectionResonance: 25,
        transformationResonance: 25
    )
    
    static let adept = ResonanceLevel(
        creativeResonance: 75,
        explorationResonance: 75,
        restorationResonance: 75,
        protectionResonance: 75,
        transformationResonance: 75
    )
    
    static let master = ResonanceLevel(
        creativeResonance: 150,
        explorationResonance: 150,
        restorationResonance: 150,
        protectionResonance: 150,
        transformationResonance: 150
    )
    
    func canPerform(melodyType: MelodyType, requiredLevel: Float) -> Bool {
        switch melodyType {
        case .creation:
            return creativeResonance >= requiredLevel
        case .exploration:
            return explorationResonance >= requiredLevel
        case .restoration:
            return restorationResonance >= requiredLevel
        case .protection:
            return protectionResonance >= requiredLevel
        case .transformation:
            return transformationResonance >= requiredLevel
        }
    }
    
    mutating func increaseResonance(for type: MelodyType, by amount: Float) {
        switch type {
        case .restoration:
            restorationResonance = min(200.0, restorationResonance + amount)
        case .exploration:
            explorationResonance = min(200.0, explorationResonance + amount)
        case .creation:
            creativeResonance = min(200.0, creativeResonance + amount)
        case .protection:
            protectionResonance = min(200.0, protectionResonance + amount)
        case .transformation:
            transformationResonance = min(200.0, transformationResonance + amount)
        }
    }
    
    var rank: ResonanceRank {
        let total = totalResonance
        switch total {
        case 0..<50:
            return .novice
        case 50..<150:
            return .apprentice
        case 150..<350:
            return .adept
        case 350..<650:
            return .expert
        default:
            return .master
        }
    }
 }

 enum ResonanceRank: String, CaseIterable {
    case novice = "Novice"
    case apprentice = "Apprentice"
    case adept = "Adept"
    case expert = "Expert"
    case master = "Master"
    
    var color: CodableColor {
        switch self {
        case .novice: return .gray
        case .apprentice: return .green
        case .adept: return .blue
        case .expert: return .purple
        case .master: return .gold
        }
    }
 }

 // MARK: - Melody and Harmony Core

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

    // Melody Collection Helpers
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

 struct Harmony: Identifiable, Codable {
    let id: UUID
    let melodies: [UUID]
    let participants: [UUID]
    let strength: Float
    let duration: TimeInterval
    let createdAt: Date
    
    init(id: UUID = UUID(), melodies: [UUID], participants: [UUID], strength: Float, duration: TimeInterval) {
        self.id = id
        self.melodies = melodies
        self.participants = participants
        self.strength = strength
        self.duration = duration
        self.createdAt = Date()
    }
    
    var isActive: Bool {
        let elapsedTime = Date().timeIntervalSince(createdAt)
        return elapsedTime < duration
    }
    
    var remainingDuration: TimeInterval {
        let elapsedTime = Date().timeIntervalSince(createdAt)
        return max(0, duration - elapsedTime)
    }
    
    var effectiveness: Float {
        let participantBonus = Float(participants.count) * 0.1
        let melodyBonus = Float(melodies.count) * 0.15
        return strength * (1.0 + participantBonus + melodyBonus)
    }
 }

 // MARK: - Error Types

 enum SongweavingError: Error, LocalizedError {
    case insufficientResonance
    case insufficientParticipants
    case incompatibleMelodies
    case cooldownActive
    case targetOutOfRange
    case harmonyExpired
    
    var errorDescription: String? {
        switch self {
        case .insufficientResonance:
            return "Not enough resonance to cast this melody"
        case .insufficientParticipants:
            return "Not enough participants to create harmony"
        case .incompatibleMelodies:
            return "These melodies cannot be harmonized together"
        case .cooldownActive:
            return "Must wait before casting another melody"
        case .targetOutOfRange:
            return "Target is too far away"
        case .harmonyExpired:
            return "The harmony has expired"
        }
    }
 }

 // MARK: - Utility Extensions

 extension Array where Element == Melody {
    static var allPredefinedMelodies: [Melody] {
        return [.restoration, .exploration, .creation, .protection, .transformation]
    }
    
    func melodies(ofType type: MelodyType) -> [Melody] {
        return self.filter { $0.type == type }
    }
    
    func availableMelodies(forResonance resonance: ResonanceLevel) -> [Melody] {
        return self.filter { $0.canBeCast(withResonance: resonance) }
    }
 }

 // MARK: - Predefined Melodies

 extension Melody {
    static let restoration = Melody(
        type: .restoration,
        strength: 1.0,
        duration: 3.0,
        harmonyColor: .green,
        requiredResonance: 10,
        harmonyBoost: 0.15,
        dissonanceReduction: 0.20
    )
    
    static let exploration = Melody(
        type: .exploration,
        strength: 0.9,
        duration: 3.0,
        harmonyColor: .blue,
        requiredResonance: 5,
        harmonyBoost: 0.10,
        dissonanceReduction: 0.08
    )
    
    static let creation = Melody(
        type: .creation,
        strength: 1.5,
        duration: 5.0,
        harmonyColor: .purple,
        requiredResonance: 25,
        harmonyBoost: 0.20,
        dissonanceReduction: 0.05
    )
    
    static let protection = Melody(
        type: .protection,
        strength: 1.2,
        duration: 4.0,
        harmonyColor: .yellow,
        requiredResonance: 15,
        harmonyBoost: 0.12,
        dissonanceReduction: 0.15
    )
    
    static let transformation = Melody(
        type: .transformation,
        strength: 1.3,
        duration: 3.2,
        harmonyColor: .orange,
        requiredResonance: 30,
        harmonyBoost: 0.25,
        dissonanceReduction: 0.20
    )
 }
