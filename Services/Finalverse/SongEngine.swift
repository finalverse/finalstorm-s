//
//  Services/Finalverse/SongEngine.swift
//  FinalStorm
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
    
    private let networkClient: FinalverseClient
    private let audioEngine: SongweavingAudioEngine
    private var harmonyCancellable: AnyCancellable?
    
    // MARK: - Initialization
    init() {
        self.networkClient = FinalverseClient(service: .songEngine)
        self.audioEngine = SongweavingAudioEngine()
    }
    
    // MARK: - Public Methods
    func initialize() async {
        do {
            try await networkClient.connect()
            await loadAvailableSongs()
            startHarmonyMonitoring()
        } catch {
            print("Failed to initialize Song Engine: \(error)")
        }
    }
    
    func castMelody(_ melody: Melody, by caster: Entity, target: Entity? = nil) async throws {
        // Validate caster can perform melody
        guard let songweaver = caster.components[SongweaverComponent.self],
              songweaver.canPerform(melody) else {
            throw SongEngineError.insufficientResonance
        }
        
        // Add to active melodies
        activeMelodies.append(melody)
        
        // Play audio
        await audioEngine.playMelody(melody)
        
        // Apply melody effects
        applyMelodyEffects(melody, caster: caster, target: target)
        
        // Remove melody after duration - FIXED: Correct closure syntax
        Task {
            try await Task.sleep(nanoseconds: UInt64(melody.duration * 1_000_000_000))
            // FIX: The closure should return Bool, comparing melody IDs
            if let index = activeMelodies.firstIndex(where: { $0.id == melody.id }) {
                activeMelodies.remove(at: index)
            }
        }
    }
    
    func createHarmony(melodies: [Melody], participants: [AvatarEntity]) async throws -> Harmony {
        // Validate participants can sustain harmony
        guard participants.count >= 2 else {
            throw SongEngineError.insufficientParticipants
        }
        
        // Calculate combined strength
        let strength = calculateHarmonyStrength(melodies: melodies, participants: participants)
        
        // Get melody IDs and participant IDs - both as UUID arrays
        let melodyIds: [UUID] = melodies.map { $0.id }
        let participantIds: [UUID] = participants.map { $0.customId }
        
        // Create harmony using the Harmony type from Components
        let harmony = Harmony(
            melodies: melodyIds,
            participants: participantIds,
            strength: strength,
            duration: 30.0 // Base duration
        )
        
        // Apply harmony effects to world
        await applyHarmonyToWorld(harmony)
        
        return harmony
    }
    
    func silenceMelody(_ melodyId: UUID) {
        activeMelodies.removeAll { $0.id == melodyId }
    }
    
    // MARK: - Private Methods
    private func loadAvailableSongs() async {
        do {
            let response: SongsResponse = try await networkClient.request(.getAvailableSongs)
            availableSongs = response.songs
        } catch {
            print("Failed to load songs: \(error)")
            // Load default songs
            availableSongs = [Song.restorationMelody]
        }
    }
    
    private func applyMelodyEffects(_ melody: Melody, caster: Entity, target: Entity?) {
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
            // Add harmony ID to active harmonies
            let harmonyRef = Harmony(fromMelodyId: melody.id, strength: melody.strength, duration: melody.duration)
            songweaver.activeHarmonies.append(harmonyRef.id)
            caster.components.set(songweaver)
        }
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
    let harmonyColor: CodableColor
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
        harmonyColor: .green,
        harmonyBoost: 0.1,
        dissonanceReduction: 0.2
    )
}

// MARK: - Error Types (renamed to avoid conflicts)
enum SongEngineError: Error {
    case insufficientResonance
    case insufficientParticipants
    case invalidTarget
    case songOnCooldown
}
