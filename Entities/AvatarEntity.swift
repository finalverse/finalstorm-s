//
//  Entities/AvatarEntity.swift
//  FinalStorm
//
//  Player avatar entity with custom UUID for harmony system
//

import RealityKit
import Combine
import Foundation

class AvatarEntity: BaseEntity {
    // FIXED: Add custom UUID for our systems since Entity.id is UInt64
    let customId = UUID()
    
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
    
    // Add profile property
    var userProfile: UserProfile?
    
    // Single required init for Entity inheritance
    required init() {
        super.init()
        setupAvatarComponents()
    }
    
    // Setup method to configure with profile
    func setupForProfile(_ profile: UserProfile) {
        self.userProfile = profile
        self.name = profile.displayName
    }
    
    private func setupAvatarComponents() {
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
    
    override func setupComponents() {
        super.setupComponents()
        // Additional setup if needed
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

// MARK: - Supporting Error Types
enum SongError: Error {
    case insufficientResonance
    case insufficientParticipants
    case invalidTarget
    case songOnCooldown
}
