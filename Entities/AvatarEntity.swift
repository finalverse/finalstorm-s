//
//  AvatarEntity.swift
//  FinalStorm-S
//
//  Player and NPC avatar entities
//

import RealityKit
import Combine

class AvatarEntity: BaseEntity {
    let profile: UserProfile
    var level: Int = 1
    var experience: Float = 0
    
    // Avatar state
    var movementSpeed: Float = 5.0
    var isMoving: Bool = false
    var targetPosition: SIMD3<Float>?
    
    // Animation state
    private var currentAnimation: AnimationType = .idle
    private var animationResource: AnimationResource?
    
    init(profile: UserProfile) {
        self.profile = profile
        super.init()
        self.name = profile.displayName
    }
    
    required init() {
        fatalError("init() has not been implemented - use init(profile:)")
    }
    
    override func setupComponents() {
        super.setupComponents()
        
        // Health component
        components.set(HealthComponent(
            current: 100,
            maximum: 100,
            regenerationRate: 1.0,
            isInvulnerable: false
        ))
        
        // Interaction component
        components.set(InteractionComponent(
            interactionRadius: 3.0,
            requiresLineOfSight: false,
            interactionType: .talk
        ))
        
        // Collision
        components.set(CollisionComponent(shapes: [
            .generateCapsule(height: 1.8, radius: 0.3)
        ]))
    }
    
    // MARK: - Movement
    func moveTo(_ position: SIMD3<Float>) {
        targetPosition = position
        isMoving = true
        
        // Play walk animation
        playAnimation(.walking)
    }
    
    func update(deltaTime: TimeInterval) {
        guard isMoving, let target = targetPosition else { return }
        
        let direction = normalize(target - position)
        let distance = length(target - position)
        
        if distance < 0.1 {
            // Reached target
            isMoving = false
            targetPosition = nil
            playAnimation(.idle)
        } else {
            // Move towards target
            let moveDistance = min(Float(deltaTime) * movementSpeed, distance)
            position += direction * moveDistance
            
            // Update rotation to face movement direction
            if length(direction) > 0 {
                look(at: position + direction, from: position, relativeTo: nil)
            }
        }
    }
    
    // MARK: - Animation
    func playAnimation(_ type: AnimationType) {
        guard currentAnimation != type else { return }
        
        currentAnimation = type
        
        // Load and play animation
        Task {
            do {
                let animation = try await AnimationResource.load(
                    named: "\(type.rawValue)_animation"
                )
                self.playAnimation(animation.repeat())
                animationResource = animation
            } catch {
                print("Failed to load animation \(type.rawValue): \(error)")
            }
        }
    }
    
    func stopAnimation() {
        stopAllAnimations()
        currentAnimation = .idle
    }
    
    // MARK: - Abilities
    func canPerformAbility(_ ability: Ability) -> Bool {
        // Check cooldowns, resonance requirements, etc.
        return true
    }
    
    func performAbility(_ ability: Ability, target: Entity? = nil) {
        guard canPerformAbility(ability) else { return }
        
        // Play ability animation
        playAnimation(.casting)
        
        // Create visual effect
        let effect = createAbilityEffect(ability)
        addChild(effect)
        
        // Apply ability effects
        Task {
            await applyAbilityEffects(ability, to: target)
            
            // Cleanup
            try? await Task.sleep(nanoseconds: UInt64(ability.duration * 1_000_000_000))
            effect.removeFromParent()
            playAnimation(.idle)
        }
    }
    
    private func createAbilityEffect(_ ability: Ability) -> Entity {
        let effect = Entity()
        
        // Add particles based on ability type
        var particles = ParticleEmitterComponent()
        particles.birthRate = 100
        particles.mainEmitter.lifeSpan = ability.duration
        
        // Customize based on ability
        switch ability.type {
        case .restoration:
            particles.mainEmitter.color = .evolving(
                start: .single(.green),
                end: .single(.white)
            )
        case .offensive:
            particles.mainEmitter.color = .evolving(
                start: .single(.red),
                end: .single(.orange)
            )
        case .utility:
            particles.mainEmitter.color = .evolving(
                start: .single(.blue),
                end: .single(.cyan)
            )
        }
        
        effect.components.set(particles)
        return effect
    }
    
    private func applyAbilityEffects(_ ability: Ability, to target: Entity?) async {
        // Apply ability logic
        switch ability.effect {
        case .heal(let amount):
            if let target = target as? BaseEntity {
                target.heal(amount)
            } else {
                heal(amount)
            }
            
        case .damage(let amount):
            if let target = target as? BaseEntity {
                target.takeDamage(amount)
            }
            
        case .buff(let stat, let amount, let duration):
            // Apply buff
            applyBuff(stat: stat, amount: amount, duration: duration)
        }
    }
    
    private func applyBuff(stat: String, amount: Float, duration: TimeInterval) {
        // Implement buff system
    }
    
    // Extension for player-specific features
    var resonanceMultiplier: Float {
        guard let songweaver = components[SongweaverComponent.self] else { return 1.0 }
        return 1.0 + (songweaver.resonanceLevel.totalResonance / 1000)
    }
    
    func learnMelody(_ melody: Melody) {
        guard var songweaver = components[SongweaverComponent.self] else { return }
        
        if !songweaver.knownMelodies.contains(where: { $0.id == melody.id }) {
            songweaver.knownMelodies.append(melody)
            components.set(songweaver)
            
            // Visual feedback
            let learnEffect = createLearnEffect()
            addChild(learnEffect)
            
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                learnEffect.removeFromParent()
            }
        }
    }
    
    private func createLearnEffect() -> Entity {
        let effect = Entity()
        
        // Spiral of light moving upward
        var particles = ParticleEmitterComponent()
        particles.emitterShape = .point
        particles.birthRate = 50
        particles.mainEmitter.lifeSpan = 2.0
        particles.mainEmitter.speed = 2.0
        particles.mainEmitter.speedVariation = 0.5
        particles.mainEmitter.color = .evolving(
            start: .single(.purple),
            end: .single(.white)
        )
        particles.mainEmitter.opacityOverLife = .linearFade
        
        effect.components.set(particles)
        effect.position = [0, 2, 0]
        
        // Add ascending motion
        effect.move(to: Transform(translation: [0, 4, 0]),
                   relativeTo: self,
                   duration: 2.0)
        
        return effect
    }
}

// MARK: - Supporting Types
enum AnimationType: String {
    case idle
    case walking
    case running
    case jumping
    case casting
    case interacting
    case sitting
    case dancing
}

struct Ability {
    enum AbilityType {
        case restoration
        case offensive
        case utility
    }
    
    enum Effect {
        case heal(Float)
        case damage(Float)
        case buff(stat: String, amount: Float, duration: TimeInterval)
    }
    
    let id = UUID()
    let name: String
    let type: AbilityType
    let effect: Effect
    let cooldown: TimeInterval
    let duration: TimeInterval
    let resonanceCost: Float
}
