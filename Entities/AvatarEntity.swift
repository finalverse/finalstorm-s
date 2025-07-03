//
//  Entities/AvatarEntity.swift
//  FinalStorm-S
//
//  Player avatar entity
//

import RealityKit
import Combine

class AvatarEntity: BaseEntity {
    // Properties
    var isLocalPlayer: Bool = false
    var avatarState: AvatarState = .idle
    var movementSpeed: Float = 2.0
    
    // Components
    private var songweaverComponent: SongweaverComponent?
    private var harmonyComponent: HarmonyComponent?
    
    // Appearance
    var appearance: AvatarAppearance = .default {
        didSet {
            Task {
                await updateAppearance()
            }
        }
    }
    
    // Publishers for state changes
    @Published var resonanceLevel: ResonanceLevel = .novice
    @Published var currentHarmony: Float = 1.0
    
    override func setupComponents() {
        super.setupComponents()
        
        // Add avatar-specific components
        songweaverComponent = SongweaverComponent(resonanceLevel: resonanceLevel)
        harmonyComponent = HarmonyComponent()
        
        components.set(songweaverComponent!)
        components.set(harmonyComponent!)
        
        // Setup interaction with proper initializer
        let interactionClosure: () -> Void = { [weak self] in
            self?.onInteraction()
        }
        
        components.set(InteractionComponent(
            interactionRadius: 2.0,
            requiresLineOfSight: false,
            interactionType: .conversation,
            onInteract: interactionClosure
        ))
    }
    
    func updateResonance(_ newLevel: ResonanceLevel) {
        resonanceLevel = newLevel
        songweaverComponent?.resonanceLevel = newLevel
        if let component = songweaverComponent {
            components.set(component)
        }
    }
    
    func castMelody(_ melody: Melody) async throws {
        guard songweaverComponent?.canPerform(melody) == true else {
            throw SongError.insufficientResonance
        }
        
        // Notify SongEngine
        let songEngine = SongEngine()
        try await songEngine.castMelody(melody, by: self)
    }
    
    private func updateAppearance() async {
        do {
            // Generate materials based on appearance
            let materials = try await AppearanceManager().generateMaterials(for: appearance)
            
            // Apply to model - create new ModelComponent
            if var modelComponent = components[ModelComponent.self] {
                let newModelComponent = ModelComponent(
                    mesh: modelComponent.mesh,
                    materials: materials
                )
                components.set(newModelComponent)
            }
        } catch {
            print("Failed to update appearance: \(error)")
        }
    }
    
    private func onInteraction() {
        print("Avatar \(name) was interacted with")
    }
}

// MARK: - Avatar State
enum AvatarState {
    case idle
    case walking
    case running
    case jumping
    case songweaving
    case interacting
}
