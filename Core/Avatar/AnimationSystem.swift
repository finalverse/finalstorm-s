//
//  Core/Avatar/AnimationSystem.swift
//  FinalStorm
//
//  Manages avatar animations
//

import RealityKit

class AnimationSystem {
    private var animations: [String: AnimationResource] = [:]
    
    func setupAvatar(_ avatar: AvatarEntity) {
        // Load default animations
        loadDefaultAnimations()
    }

    func loadAnimations() async {
        // Public interface to trigger animation loading from outside
        loadDefaultAnimations()
    }

    func setupAnimations(for avatar: AvatarEntity) {
        setupAvatar(avatar)
    }
    
    private func loadDefaultAnimations() {
        // Load animation resources
        Task {
            do {
                // These would be actual animation files in production
                // For now, create placeholder animations
                animations["idle"] = try await createIdleAnimation()
                animations["walking"] = try await createWalkingAnimation()
                animations["running"] = try await createRunningAnimation()
            } catch {
                print("Failed to load animations: \(error)")
            }
        }
    }
    
    func playAnimation(_ type: AnimationType, on avatar: AvatarEntity) {
        guard let animation = animations[type.rawValue] else { return }
        
        avatar.playAnimation(animation.repeat())
    }

    /// Transitions the avatar to the provided animation state.
    func transitionToState(_ type: AnimationType, for avatar: AvatarEntity) {
        switch type {
        case .idle:
            playAnimation(.idle, on: avatar)
        case .walk:
            playAnimation(.walk, on: avatar)
        case .run:
            playAnimation(.run, on: avatar)
        case .jump:
            playAnimation(.jump, on: avatar) // Placeholder, not yet implemented
        case .emote(let emote):
            print("Playing emote animation: \(emote)")
        case .combat(let action):
            print("Playing combat animation: \(action)")
        case .interact(let interaction):
            print("Playing interaction animation: \(interaction)")
        }
    }
    
    private func createIdleAnimation() async throws -> AnimationResource {
        // Create a simple idle animation
        let idleAnimation = FromToByAnimation(
            from: Transform(translation: [0, 0, 0]),
            to: Transform(translation: [0, 0.02, 0]),
            duration: 2,
            bindTarget: .transform
        )
        
        return try AnimationResource.generate(with: idleAnimation)
    }
    
    private func createWalkingAnimation() async throws -> AnimationResource {
        // Create walking animation
        let walkAnimation = FromToByAnimation(
            from: Transform(rotation: simd_quatf(angle: -0.1, axis: [0, 0, 1])),
            to: Transform(rotation: simd_quatf(angle: 0.1, axis: [0, 0, 1])),
            duration: 0.5,
            bindTarget: .transform
        )
        
        return try AnimationResource.generate(with: walkAnimation)
    }
    
    private func createRunningAnimation() async throws -> AnimationResource {
        // Create running animation
        let runAnimation = FromToByAnimation(
            from: Transform(rotation: simd_quatf(angle: -0.2, axis: [0, 0, 1])),
            to: Transform(rotation: simd_quatf(angle: 0.2, axis: [0, 0, 1])),
            duration: 0.3,
            bindTarget: .transform
        )
        
        return try AnimationResource.generate(with: runAnimation)
    }
}

enum AnimationType: Equatable {
    case idle
    case walk
    case run
    case jump
    case emote(EmoteType)
    case combat(CombatAction)
    case interact(InteractionType)

    var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .walk: return "walking"
        case .run: return "running"
        case .jump: return "jumping"
        case .emote: return "emote"
        case .combat: return "combat"
        case .interact: return "interact"
        }
    }
}

    func playOneShot(_ type: AnimationType, on avatar: AvatarEntity) {
        guard let animation = animations[type.rawValue] else { return }
        avatar.playAnimation(animation)
    }
