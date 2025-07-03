//
//  Harmony.swift
//  FinalStorm
//
//  Harmony system types for songweaving mechanics
//  Manages combined melodies and participant coordination
//

import Foundation

// MARK: - Harmony System
/// Represents a harmony created by combining multiple melodies
/// Harmonies are more powerful than individual melodies and require coordination
struct Harmony: Identifiable, Codable {
    let id: UUID
    let melodies: [UUID]          // References to melody IDs instead of full objects
    let participants: [UUID]      // Player/NPC participants in the harmony
    let strength: Float           // Combined strength of all melodies
    let duration: TimeInterval    // How long the harmony lasts
    let createdAt: Date          // When the harmony was formed
    
    /// Initialize a harmony with explicit parameters
    /// - Parameters:
    ///   - id: Unique identifier for the harmony
    ///   - melodies: Array of melody UUIDs participating in harmony
    ///   - participants: Array of participant UUIDs
    ///   - strength: Combined harmony strength
    ///   - duration: Duration in seconds
    init(id: UUID = UUID(), melodies: [UUID], participants: [UUID], strength: Float, duration: TimeInterval) {
        self.id = id
        self.melodies = melodies
        self.participants = participants
        self.strength = strength
        self.duration = duration
        self.createdAt = Date()
    }
    
    /// Create a simple harmony from a single melody
    /// Useful for solo songweaving that creates harmony effects
    /// - Parameter melodyId: The UUID of the melody to base harmony on
    init(fromMelodyId melodyId: UUID, strength: Float, duration: TimeInterval) {
        self.id = UUID()
        self.melodies = [melodyId]
        self.participants = []
        self.strength = strength
        self.duration = duration
        self.createdAt = Date()
    }
    
    /// Check if the harmony is still active based on creation time and duration
    var isActive: Bool {
        let elapsedTime = Date().timeIntervalSince(createdAt)
        return elapsedTime < duration
    }
    
    /// Calculate the remaining time for this harmony
    var remainingDuration: TimeInterval {
        let elapsedTime = Date().timeIntervalSince(createdAt)
        return max(0, duration - elapsedTime)
    }
    
    /// Calculate harmony effectiveness based on participant count and melody synergy
    var effectiveness: Float {
        let participantBonus = Float(participants.count) * 0.1 // 10% bonus per participant
        let melodyBonus = Float(melodies.count) * 0.15       // 15% bonus per melody
        return strength * (1.0 + participantBonus + melodyBonus)
    }
}

// MARK: - Harmony Effect
/// Represents an active harmony effect applied to an entity or area
struct HarmonyEffect: Identifiable, Codable {
    let id: UUID
    let harmonyId: UUID          // Reference to the harmony that created this effect
    let targetId: UUID?          // Entity or area affected (nil for global effects)
    let effectType: HarmonyEffectType
    let magnitude: Float         // Strength of the effect
    let appliedAt: Date         // When the effect was first applied
    let duration: TimeInterval  // How long the effect lasts
    
    /// Check if this effect is still active
    var isActive: Bool {
        let elapsedTime = Date().timeIntervalSince(appliedAt)
        return elapsedTime < duration
    }
    
    /// Calculate remaining effect time
    var remainingTime: TimeInterval {
        let elapsedTime = Date().timeIntervalSince(appliedAt)
        return max(0, duration - elapsedTime)
    }
    
    /// Calculate current effect strength (may decay over time)
    var currentStrength: Float {
        let progress = Date().timeIntervalSince(appliedAt) / duration
        // Linear decay - effect gets weaker as it approaches expiration
        return magnitude * Float(1.0 - progress)
    }
}

// MARK: - Supporting Enums
/// Types of effects that harmonies can create in the world
enum HarmonyEffectType: String, Codable, CaseIterable {
    case restoration     // Healing and corruption cleansing
    case enlightenment   // Knowledge and secret revelation
    case creation       // Matter and energy manipulation
    case protection     // Shielding and barrier creation
    case transformation // Environmental and entity changes
    case amplification  // Boosting other abilities and effects
    
    /// Description of what each effect type does
    var description: String {
        switch self {
        case .restoration:
            return "Heals damage and cleanses corruption from the affected area"
        case .enlightenment:
            return "Reveals hidden knowledge, secrets, and invisible elements"
        case .creation:
            return "Manifests new objects, structures, or magical constructs"
        case .protection:
            return "Creates barriers and shields against harmful forces"
        case .transformation:
            return "Changes the fundamental nature of matter and energy"
        case .amplification:
            return "Enhances the power and effectiveness of other abilities"
        }
    }
    
    /// Base duration multiplier for each effect type
    var durationMultiplier: Float {
        switch self {
        case .restoration: return 1.0      // Standard duration
        case .enlightenment: return 2.0    // Long-lasting revelation
        case .creation: return 3.0         // Permanent or semi-permanent
        case .protection: return 1.5       // Extended defense
        case .transformation: return 2.5   // Long-term changes
        case .amplification: return 0.8    // Shorter boost effects
        }
    }
}

// MARK: - Harmony Builder
/// Utility class for creating and validating harmonies
struct HarmonyBuilder {
    private var melodies: [UUID] = []
    private var participants: [UUID] = []
    private var baseStrength: Float = 1.0
    private var baseDuration: TimeInterval = 10.0
    
    /// Add a melody to the harmony being built
    mutating func addMelody(_ melodyId: UUID) -> HarmonyBuilder {
        melodies.append(melodyId)
        return self
    }
    
    /// Add a participant to the harmony
    mutating func addParticipant(_ participantId: UUID) -> HarmonyBuilder {
        participants.append(participantId)
        return self
    }
    
    /// Set the base strength for the harmony
    mutating func setStrength(_ strength: Float) -> HarmonyBuilder {
        baseStrength = max(0.1, min(3.0, strength)) // Clamp between 0.1 and 3.0
        return self
    }
    
    /// Set the base duration for the harmony
    mutating func setDuration(_ duration: TimeInterval) -> HarmonyBuilder {
        baseDuration = max(1.0, duration) // Minimum 1 second duration
        return self
    }
    
    /// Build the final harmony with validation
    func build() throws -> Harmony {
        guard !melodies.isEmpty else {
            throw HarmonyError.noMelodies
        }
        
        // Calculate final strength based on melody synergy
        let synergy = calculateMelodySynergy(melodies)
        let finalStrength = baseStrength * synergy
        
        // Calculate final duration with participant bonus
        let participantBonus = 1.0 + (Double(participants.count) * 0.2)
        let finalDuration = baseDuration * participantBonus
        
        return Harmony(
            melodies: melodies,
            participants: participants,
            strength: finalStrength,
            duration: finalDuration
        )
    }
    
    /// Calculate how well melodies work together (placeholder implementation)
    private func calculateMelodySynergy(_ melodyIds: [UUID]) -> Float {
        // In a real implementation, this would analyze melody compatibility
        // For now, return a simple bonus for multiple melodies
        let melodyCount = Float(melodyIds.count)
        return 1.0 + (melodyCount - 1.0) * 0.15 // 15% bonus per additional melody
    }
}

// MARK: - Error Types
/// Errors that can occur during harmony creation and management
enum HarmonyError: Error, LocalizedError {
    case noMelodies
    case insufficientParticipants
    case incompatibleMelodies
    case insufficientResonance
    case harmonyExpired
    
    var errorDescription: String? {
        switch self {
        case .noMelodies:
            return "Cannot create harmony without any melodies"
        case .insufficientParticipants:
            return "Not enough participants to sustain the harmony"
        case .incompatibleMelodies:
            return "The selected melodies are incompatible and cannot form harmony"
        case .insufficientResonance:
            return "Participants lack the resonance needed for this harmony"
        case .harmonyExpired:
            return "The harmony has expired and is no longer active"
        }
    }
}

// MARK: - Collection Extensions
extension Array where Element == Harmony {
    /// Get all active harmonies from the collection
    var activeHarmonies: [Harmony] {
        return self.filter { $0.isActive }
    }
    
    /// Get harmonies that will expire within the specified time
    func expiringWithin(_ timeInterval: TimeInterval) -> [Harmony] {
        return self.filter { $0.remainingDuration <= timeInterval }
    }
    
    /// Calculate total strength of all active harmonies
    var totalActiveStrength: Float {
        return activeHarmonies.reduce(0) { $0 + $1.effectiveness }
    }
}
