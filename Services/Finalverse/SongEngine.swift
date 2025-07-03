//
//  SongEngine.swift
//  FinalStorm-S
//
//  Implements the Song of Creation mechanics - the core magic system of Finalverse
//

import Foundation
import RealityKit
import Combine

@MainActor
class SongEngine: ObservableObject {
    // MARK: - Properties
    @Published var activeMelodies: [Melody] = []
    @Published var globalHarmony: Float = 1.0
    @Published var availableSongs: [Song] = []
    
    private let networkClient: FinalverseNetworkClient
    private let audioEngine: SongweavingAudioEngine
    private var harmonyCancellable: AnyCancellable?
    
    init() {
        self.networkClient = FinalverseNetworkClient(service: .songEngine)
        self.audioEngine = SongweavingAudioEngine()
    }
    
    // MARK: - Initialization
    func initialize() async {
        // Connect to Finalverse Song Engine service
        do {
            try await networkClient.connect()
            
            // Load available songs from server
            availableSongs = try await fetchAvailableSongs()
            
            // Start harmony monitoring
            startHarmonyMonitoring()
        } catch {
            print("Failed to initialize Song Engine: \(error)")
        }
    }
    
    // MARK: - Songweaving
    func weaveSong(_ song: Song, caster: AvatarEntity, target: Entity?) async throws {
        // Validate caster has required resonance
        guard let songweaver = caster.components[SongweaverComponent.self],
              songweaver.resonanceLevel.totalResonance >= song.requiredResonance else {
            throw SongError.insufficientResonance
        }
        
        // Create melody from song
        let melody = createMelody(from: song, caster: caster)
        
        // Play audio representation
        await audioEngine.playMelody(melody)
        
        // Apply visual effects
        let visualEffect = createVisualEffect(for: melody)
        caster.addChild(visualEffect)
        
        // Send to server for validation and world state update
        let response = try await networkClient.request(
            .weaveSong(songId: song.id, casterId: caster.id, targetId: target?.id)
        )
        
        // Apply effects based on server response
        if response.success {
            applyMelodyEffects(melody, caster: caster, target: target)
            
            // Update local harmony
            updateLocalHarmony(melody.harmonyContribution)
        }
        
        // Clean up visual effect after duration
        Task {
            try await Task.sleep(nanoseconds: UInt64(melody.duration * 1_000_000_000))
            visualEffect.removeFromParent()
        }
    }
    
    // MARK: - Harmony System
    func createHarmony(_ melodies: [Melody], participants: [AvatarEntity]) async throws -> Harmony {
        // Validate all participants can contribute
        let validParticipants = participants.filter { avatar in
            guard let songweaver = avatar.components[SongweaverComponent.self] else { return false }
            return melodies.allSatisfy { melody in
                songweaver.canPerform(melody)
            }
        }
        
        guard validParticipants.count >= melodies.count else {
            throw SongError.insufficientParticipants
        }
        
        // Calculate harmony strength based on participant resonance
        let harmonyStrength = calculateHarmonyStrength(melodies: melodies, participants: validParticipants)
        
        // Create harmony effect
        let harmony = Harmony(
            id: UUID(),
            melodies: melodies,
            participants: validParticipants.map { $0.id },
            strength: harmonyStrength,
            duration: 60.0 // 1 minute base duration
        )
        
        // Apply harmony to world
        await applyHarmonyToWorld(harmony)
        
        return harmony
    }
    
    // MARK: - Effect Creation
    private func createMelody(from song: Song, caster: AvatarEntity) -> Melody {
        return Melody(
            id: UUID(),
            type: song.melodyType,
            strength: song.baseStrength * caster.resonanceMultiplier,
            duration: song.duration,
            harmonyColor: song.harmonyColor,
            requiredResonance: song.requiredResonance,
            harmonyBoost: song.harmonyBoost,
            dissonanceReduction: song.dissonanceReduction
        )
    }
    
    private func createVisualEffect(for melody: Melody) -> Entity {
        let effect = Entity()
        
        // Add particle system
        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterPosition = [0, 1, 0] // Above caster
        particles.birthRate = 100
        particles.mainEmitter.lifeSpan = 2.0
        particles.mainEmitter.size = 0.05
        
        // Color based on melody type
        let startColor: UIColor
        let endColor: UIColor
        
        switch melody.type {
        case .restoration:
            startColor = .systemGreen
            endColor = .systemMint
        case .exploration:
            startColor = .systemBlue
            endColor = .systemCyan
        case .creation:
            startColor = .systemPurple
            endColor = .systemPink
        }
        
        particles.mainEmitter.color = .evolving(
            start: .single(startColor),
            end: .single(endColor.withAlphaComponent(0))
        )
        
        // Add light source
        let light = PointLight()
        light.color = startColor
        light.intensity = 1000
        light.attenuationRadius = 5.0
        
        effect.components.set(particles)
        effect.components.set(PointLightComponent(light: light))
        
        return effect
    }
    
    // MARK: - Effect Application
    private func applyMelodyEffects(_ melody: Melody, caster: AvatarEntity, target: Entity?) {
        // Apply to target if specified
        if let target = target {
            if var harmony = target.components[HarmonyComponent.self] {
                harmony.applyMelody(melody)
                target.components.set(harmony)
            }
        }
        
        // Apply area effect
        let areaOfEffect = melody.type.effectRadius
        let nearbyEntities = findEntitiesInRadius(center: caster.position, radius: areaOfEffect)
        
        for entity in nearbyEntities {
            if var harmony = entity.components[HarmonyComponent.self] {
                // Reduced effect based on distance
                let distance = simd_distance(caster.position, entity.position)
                let effectMultiplier = 1.0 - (distance / areaOfEffect)
                
                var reducedMelody = melody
                reducedMelody.strength *= effectMultiplier
                harmony.applyMelody(reducedMelody)
                entity.components.set(harmony)
            }
        }
        
        // Update caster's resonance
        if var songweaver = caster.components[SongweaverComponent.self] {
            songweaver.activeHarmonies.append(Harmony(from: melody))
            caster.components.set(songweaver)
        }
    }
    
    // MARK: - Network Communication
    private func fetchAvailableSongs() async throws -> [Song] {
        let response = try await networkClient.request(.getAvailableSongs)
        return response.songs
    }
    
    // MARK: - Harmony Monitoring
    private func startHarmonyMonitoring() {
        harmonyCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateGlobalHarmony()
            }
    }
    
    private func updateGlobalHarmony() {
        // Calculate global harmony from all active melodies and harmonies
        var totalHarmony: Float = 1.0
        
        for melody in activeMelodies {
            totalHarmony += melody.harmonyBoost
        }
        
        // Apply decay over time
        totalHarmony *= 0.99
        
        globalHarmony = max(0.1, min(2.0, totalHarmony))
    }
    
    // MARK: - Helper Methods
    private func calculateHarmonyStrength(melodies: [Melody], participants: [AvatarEntity]) -> Float {
        let baseStrength = melodies.reduce(0) { $0 + $1.strength }
        let participantBonus = Float(participants.count) * 0.2
        let resonanceMultiplier = participants.reduce(0) { sum, avatar in
            sum + (avatar.components[SongweaverComponent.self]?.resonanceLevel.totalResonance ?? 0) / 1000
        } / Float(participants.count)
        
        return baseStrength * (1 + participantBonus) * (1 + resonanceMultiplier)
    }
    
    private func findEntitiesInRadius(center: SIMD3<Float>, radius: Float) -> [Entity] {
        // This would query the spatial index in the world manager
        // For now, return empty array
        return []
    }
    
    private func updateLocalHarmony(_ contribution: Float) {
        globalHarmony = max(0.1, min(2.0, globalHarmony + contribution))
    }
    
    private func applyHarmonyToWorld(_ harmony: Harmony) async {
        // Send harmony update to world engine
        let worldEngine = WorldEngineService()
        await worldEngine.applyHarmony(harmony)
    }
}

// MARK: - Supporting Types
struct Song: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let melodyType: MelodyType
    let requiredResonance: Float
    let baseStrength: Float
    let duration: TimeInterval
    let harmonyColor: UIColor
    let harmonyBoost: Float
    let dissonanceReduction: Float
    
    // Predefined songs
    static let restorationMelody = Song(
        id: UUID(),
        name: "Melody of Restoration",
        description: "Heals and restores harmony to the touched",
        melodyType: .restoration,
        requiredResonance: 10,
        baseStrength: 1.0,
        duration: 3.0,
        harmonyColor: .systemGreen,
        harmonyBoost: 0.1,
        dissonanceReduction: 0.2
    )
}

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

struct Harmony: Identifiable {
    let id: UUID
    let melodies: [Melody]
    let participants: [UUID]
    let strength: Float
    let duration: TimeInterval
    
    init(id: UUID, melodies: [Melody], participants: [UUID], strength: Float, duration: TimeInterval) {
        self.id = id
        self.melodies = melodies
        self.participants = participants
        self.strength = strength
        self.duration = duration
    }
    
    init(from melody: Melody) {
        self.id = UUID()
        self.melodies = [melody]
        self.participants = []
        self.strength = melody.strength
        self.duration = melody.duration
    }
}

enum SongError: Error {
    case insufficientResonance
    case insufficientParticipants
    case invalidTarget
    case songOnCooldown
}

struct HarmonyEffect {
    let type: MelodyType
    let strength: Float
    let duration: TimeInterval
    let appliedAt: Date = Date()
    
    var isActive: Bool {
        Date().timeIntervalSince(appliedAt) < duration
    }
}
