//
//  Core/Avatar/AvatarSystem.swift
//  FinalStorm
//
//  Core avatar management system with proper platform-specific handling
//

import RealityKit
import Combine
import simd
import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

@MainActor
class AvatarSystem: ObservableObject {
    // MARK: - Properties
    @Published var localAvatar: AvatarEntity?
    @Published var remoteAvatars: [UUID: AvatarEntity] = [:]
    @Published var appearance: AvatarAppearance = .default
    @Published var resonanceLevel: ResonanceLevel = .novice
    
    private var avatarUpdateCancellables = Set<AnyCancellable>()
    private let animationSystem = AnimationSystem()
    private let appearanceManager = AppearanceManager()
    
    // MARK: - Avatar Creation
    func createLocalAvatar(profile: UserProfile) async throws -> AvatarEntity {
        // Create base avatar entity with RealityKit
        let avatar = AvatarEntity()
        avatar.setupForProfile(profile)
        
        // Load avatar mesh based on appearance settings
        let mesh = try await loadAvatarMesh(for: appearance)
        avatar.components.set(ModelComponent(mesh: mesh, materials: []))
        
        // Add physics for movement
        avatar.components.set(PhysicsBodyComponent(
            massProperties: .init(mass: 70.0),
            material: .generate(friction: 0.5, restitution: 0.1),
            mode: .kinematic
        ))
        
        // Add collision for interaction
        avatar.components.set(CollisionComponent(shapes: [
            .generateCapsule(height: 1.8, radius: 0.3)
        ]))
        
        // Initialize Finalverse-specific components
        avatar.components.set(SongweaverComponent(resonanceLevel: resonanceLevel))
        avatar.components.set(HarmonyComponent())
        
        // Setup animation controller
        animationSystem.setupAvatar(avatar)
        
        self.localAvatar = avatar
        return avatar
    }
    
    // MARK: - Avatar Movement
    func moveAvatar(to position: SIMD3<Float>, rotation: simd_quatf) {
        guard let avatar = localAvatar else { return }
        
        // Smooth movement with interpolation - correct parameter order
        let duration: TimeInterval = 0.1
        avatar.move(to: Transform(rotation: rotation, translation: position),
                   relativeTo: nil,
                   duration: duration)
        
        // Trigger walking animation if moving
        if distance(avatar.position, position) > 0.01 {
            animationSystem.playAnimation(.walking, on: avatar)
        }
    }
    
    // MARK: - Songweaving Integration
    func performSongweaving(_ melody: Melody, target: Entity?) {
        guard let avatar = localAvatar,
              let songweaver = avatar.components[SongweaverComponent.self] else { return }
        
        // Check if avatar has required resonance level
        guard songweaver.canPerform(melody) else {
            // Show feedback that resonance is too low
            return
        }
        
        // Create visual effect for songweaving
        let effect = createSongweavingEffect(melody: melody)
        avatar.addChild(effect)
        
        // Apply harmony changes to target
        if let target = target {
            applyHarmonyEffect(melody: melody, to: target)
        }
        
        // Update resonance based on action
        updateResonance(for: melody.type)
    }
    
    // MARK: - Helper Methods
    private func loadAvatarMesh(for appearance: AvatarAppearance) async throws -> MeshResource {
        // BASIC IMPLEMENTATION - just use generated mesh for now
        // TODO: Load actual avatar meshes when assets are available
        return MeshResource.generateBox(size: [0.5, 1.8, 0.3])
    }
    
    private func createSongweavingEffect(melody: Melody) -> Entity {
        let effect = Entity()
        
        // SIMPLIFIED PARTICLE SYSTEM - avoid advanced APIs that might not exist
        #if os(iOS) || os(macOS) || os(visionOS)
        var particleEmitter = ParticleEmitterComponent()
        particleEmitter.emitterShape = .sphere
        
        // Use basic configuration only
        particleEmitter.mainEmitter.birthRate = 100
        particleEmitter.mainEmitter.lifeSpan = 3.0
        
        // Skip advanced color configuration for now - use basic approach
        effect.components.set(particleEmitter)
        #endif
        
        // Add basic spatial audio component
        effect.components.set(SpatialAudioComponent(melody: melody))
        
        return effect
    }
    
    private func applyHarmonyEffect(melody: Melody, to target: Entity) {
        // Apply Finalverse harmony mechanics
        if var harmony = target.components[HarmonyComponent.self] {
            harmony.applyMelody(melody)
            target.components.set(harmony)
        }
    }
    
    private func updateResonance(for actionType: MelodyType) {
        switch actionType {
        case .restoration:
            resonanceLevel.restorationResonance += 10
        case .exploration:
            resonanceLevel.explorationResonance += 5
        case .creation:
            resonanceLevel.creativeResonance += 15
        case .protection:
            resonanceLevel.restorationResonance += 8
        case .transformation:
            resonanceLevel.creativeResonance += 12
        }
    }
    
    // MARK: - Appearance Management
    func updateAppearance(_ newAppearance: AvatarAppearance) async {
        appearance = newAppearance
        
        guard let avatar = localAvatar else { return }
        
        // SIMPLIFIED - just update basic properties for now
        do {
            let mesh = try await loadAvatarMesh(for: newAppearance)
            if var modelComponent = avatar.components[ModelComponent.self] {
                modelComponent.mesh = mesh
                avatar.components.set(modelComponent)
            }
        } catch {
            print("Failed to update appearance: \(error)")
        }
    }
    
    // Add method to learn new melodies
    func learnMelody(_ melody: Melody) {
        guard let avatar = localAvatar,
              var songweaver = avatar.components[SongweaverComponent.self] else { return }
        
        // Add melody ID to known melodies
        if !songweaver.knownMelodies.contains(melody.id) {
            songweaver.knownMelodies.append(melody.id)
            avatar.components.set(songweaver)
        }
    }
}
