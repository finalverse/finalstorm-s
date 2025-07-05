//
//  Core/Components/ComponentTypes.swift
//  FinalStorm
//
//  Central definition of all RealityKit components for the Finalverse
//  Single source of truth for component definitions - prevents conflicts
//

import Foundation
import RealityKit
import Combine

// MARK: - Core Game Components

/// Component for entities that can be interacted with by players
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
        case conversation, activate, pickup, songweave
        case `default`, talk, questGive, teach, accompany
        case examine, trade, craft
    }
}

/// Component for entities with health and damage systems
struct HealthComponent: Component, Codable {
    var current: Float
    var maximum: Float
    var regenerationRate: Float = 0
    var isInvulnerable: Bool = false
    var lastDamageTime: Date = Date()
    
    init(current: Float, maximum: Float, regenerationRate: Float = 0) {
        self.current = current
        self.maximum = maximum
        self.regenerationRate = regenerationRate
    }
    
    var healthPercentage: Float {
        guard maximum > 0 else { return 0 }
        return current / maximum
    }
    
    var isDead: Bool { current <= 0 }
    
    mutating func takeDamage(_ amount: Float) {
        guard !isInvulnerable else { return }
        current = max(0, current - amount)
        lastDamageTime = Date()
    }
    
    mutating func heal(_ amount: Float) {
        current = min(maximum, current + amount)
    }
}

/// Component for entities that can cast songweaving melodies
struct SongweaverComponent: Component, Codable {
    var resonanceLevel: ResonanceLevel
    var knownMelodies: Set<UUID> = []
    var activeHarmonies: Set<UUID> = []
    var lastCastTime: Date = Date.distantPast
    var castingCooldown: TimeInterval = 1.0
    
    init(resonanceLevel: ResonanceLevel) {
        self.resonanceLevel = resonanceLevel
    }
    
    func canPerform(_ melody: Melody) -> Bool {
        let timeSinceLastCast = Date().timeIntervalSince(lastCastTime)
        guard timeSinceLastCast >= castingCooldown else { return false }
        return resonanceLevel.canPerform(melodyType: melody.type, requiredLevel: melody.requiredResonance)
    }
    
    mutating func learnMelody(id: UUID) {
        knownMelodies.insert(id)
    }
    
    mutating func updateCastTime() {
        lastCastTime = Date()
    }
}

/// Component for tracking harmony and dissonance effects
struct HarmonyComponent: Component, Codable {
    var harmonyLevel: Float = 1.0
    var dissonanceLevel: Float = 0.0
    var activeEffects: Set<UUID> = []
    var baseHarmony: Float = 1.0
    var lastUpdate: Date = Date()
    
    init(harmonyLevel: Float = 1.0) {
        self.harmonyLevel = harmonyLevel
        self.baseHarmony = harmonyLevel
    }
    
    mutating func applyMelody(_ melody: Melody) {
        harmonyLevel += melody.harmonyBoost
        dissonanceLevel = max(0, dissonanceLevel - melody.dissonanceReduction)
        lastUpdate = Date()
        
        // Clamp values to reasonable ranges
        harmonyLevel = max(0.1, min(3.0, harmonyLevel))
        dissonanceLevel = max(0.0, min(2.0, dissonanceLevel))
    }
    
    var netHarmony: Float {
        return max(0.1, harmonyLevel - dissonanceLevel)
    }
}

/// Component for spatial audio positioning and effects
struct SpatialAudioComponent: Component, Codable {
    var volume: Float = 1.0
    var pitch: Float = 1.0
    var spatialization: AudioSpatialization
    var audioCategory: AudioCategory
    var isPlaying: Bool = false
    var audioFileId: String?
    var loop: Bool = false
    
    init(
        volume: Float = 1.0,
        spatialization: AudioSpatialization = .positional(radius: 10.0),
        audioCategory: AudioCategory = .effects,
        audioFileId: String? = nil
    ) {
        self.volume = volume
        self.spatialization = spatialization
        self.audioCategory = audioCategory
        self.audioFileId = audioFileId
    }
}

/// Component for movement and pathfinding
struct MovementComponent: Component, Codable {
    var velocity: SIMD3<Float> = [0, 0, 0]
    var acceleration: SIMD3<Float> = [0, 0, 0]
    var maxSpeed: Float = 5.0
    var rotationSpeed: Float = 1.0
    var isGrounded: Bool = true
    var canFly: Bool = false
    var currentTarget: SIMD3<Float>?
    var stoppingDistance: Float = 0.5
    
    init(maxSpeed: Float = 5.0, canFly: Bool = false) {
        self.maxSpeed = maxSpeed
        self.canFly = canFly
    }
    
    mutating func setTarget(_ target: SIMD3<Float>) {
        currentTarget = target
    }
    
    func hasReachedTarget(currentPosition: SIMD3<Float>) -> Bool {
        guard let target = currentTarget else { return true }
        let distance = simd_distance(currentPosition, target)
        return distance <= stoppingDistance
    }
}

/// Component for AI behavior states
struct AIBehaviorComponent: Component, Codable {
    var currentState: AIState = .idle
    var personalityType: PersonalityType = .neutral
    var detectionRadius: Float = 10.0
    var lastPlayerInteraction: Date?
    var currentEmotion: Emotion = .neutral
    
    init(personalityType: PersonalityType = .neutral, detectionRadius: Float = 10.0) {
        self.personalityType = personalityType
        self.detectionRadius = detectionRadius
    }
}

// MARK: - Supporting Enums

enum AIState: String, Codable, CaseIterable {
    case idle, patrolling, investigating, conversing
    case following, teaching, fleeing, attacking
}

enum PersonalityType: String, Codable, CaseIterable {
    case neutral, friendly, hostile, curious
    case shy, wise, playful, protective
}
