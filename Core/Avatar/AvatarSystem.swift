//
//  AvatarSystem.swift
//  FinalStorm-S
//
//  Core avatar management system supporting both OpenSim and Finalverse avatars
//

import RealityKit
import Combine
import simd

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
        let avatar = AvatarEntity(profile: profile)
        
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
        
        // Smooth movement with interpolation
        let duration: TimeInterval = 0.1
        avatar.move(to: Transform(translation: position, rotation: rotation),
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
    
    // MARK: - Appearance Management
    func updateAppearance(_ newAppearance: AvatarAppearance) async {
        appearance = newAppearance
        
        guard let avatar = localAvatar else { return }
        
        // Update mesh and textures
        do {
            let mesh = try await loadAvatarMesh(for: newAppearance)
            avatar.components[ModelComponent.self]?.mesh = mesh
            
            // Apply new textures
            let materials = try await appearanceManager.generateMaterials(for: newAppearance)
            avatar.components[ModelComponent.self]?.materials = materials
        } catch {
            print("Failed to update appearance: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    private func loadAvatarMesh(for appearance: AvatarAppearance) async throws -> MeshResource {
        // Load base mesh from resources
        let baseMesh = try await MeshResource.load(named: "avatar_base")
        
        // Apply morphs based on appearance parameters
        // This would integrate with OpenSim's appearance system
        return appearanceManager.applyMorphs(to: baseMesh, appearance: appearance)
    }
    
    private func createSongweavingEffect(melody: Melody) -> Entity {
        let effect = Entity()
        
        // Add particle system for visual feedback
        var particleEmitter = ParticleEmitterComponent()
        particleEmitter.emitterShape = .sphere
        particleEmitter.birthRate = 100
        particleEmitter.mainEmitter.color = .evolving(
            start: .single(melody.harmonyColor),
            end: .single(melody.harmonyColor.withAlphaComponent(0))
        )
        
        effect.components.set(particleEmitter)
        
        // Add spatial audio for the melody
        effect.components.set(SpatialAudioComponent(melody: melody))
        
        return effect
    }
    
    private func applyHarmonyEffect(melody: Melody, to target: Entity) {
        // Apply Finalverse harmony mechanics
        if var harmony = target.components[HarmonyComponent.self] {
            harmony.applyMelody(melody)
            target.components.set(harmony)
            
            // Visual feedback on target
            highlightWithHarmony(target, color: melody.harmonyColor)
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
        }
    }
    
    private func highlightWithHarmony(_ entity: Entity, color: UIColor) {
        // Add glow effect
        var material = PhysicallyBasedMaterial()
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 2.0
        
        if let modelComponent = entity.components[ModelComponent.self] {
            entity.components.set(ModelComponent(
                mesh: modelComponent.mesh,
                materials: [material]
            ))
        }
        
        // Fade out after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Reset material
            self.resetEntityMaterial(entity)
        }
    }
    
    private func resetEntityMaterial(_ entity: Entity) {
        // Reset to original material
        // Implementation depends on material management system
    }
}

// MARK: - Supporting Types
struct AvatarAppearance: Codable {
    var bodyShape: BodyShape
    var skinTone: Color
    var hairStyle: HairStyle
    var clothing: [ClothingItem]
    var accessories: [Accessory]
    
    static let `default` = AvatarAppearance(
        bodyShape: .average,
        skinTone: .medium,
        hairStyle: .medium,
        clothing: [.defaultShirt, .defaultPants],
        accessories: []
    )
}

struct ResonanceLevel {
    var creativeResonance: Float = 0
    var explorationResonance: Float = 0
    var restorationResonance: Float = 0
    
    var totalResonance: Float {
        creativeResonance + explorationResonance + restorationResonance
    }
    
    static let novice = ResonanceLevel()
}

// Custom components for Finalverse integration
struct SongweaverComponent: Component {
    var resonanceLevel: ResonanceLevel
    var knownMelodies: [Melody] = []
    var activeHarmonies: [Harmony] = []
    
    func canPerform(_ melody: Melody) -> Bool {
        // Check if resonance level meets requirements
        switch melody.type {
        case .restoration:
            return resonanceLevel.restorationResonance >= melody.requiredResonance
        case .exploration:
            return resonanceLevel.explorationResonance >= melody.requiredResonance
        case .creation:
            return resonanceLevel.creativeResonance >= melody.requiredResonance
        }
    }
}

struct HarmonyComponent: Component {
    var harmonyLevel: Float = 1.0
    var dissonanceLevel: Float = 0.0
    var activeEffects: [HarmonyEffect] = []
    
    mutating func applyMelody(_ melody: Melody) {
        // Apply melody effects to harmony
        harmonyLevel += melody.harmonyBoost
        dissonanceLevel = max(0, dissonanceLevel - melody.dissonanceReduction)
        
        // Add time-based effect
        let effect = HarmonyEffect(
            type: melody.type,
            strength: melody.strength,
            duration: melody.duration
        )
        activeEffects.append(effect)
    }
}
