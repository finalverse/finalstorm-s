//
//  Entities/BaseEntity.swift
//  FinalStorm
//
//  Base entity class for all game objects with proper Entity inheritance
//

import RealityKit
import Combine

class BaseEntity: Entity {
    // Common properties
    var health: Float = 100
    var maxHealth: Float = 100
    var isInteractable: Bool = false
    
    // Event publishers
    let onDamage = PassthroughSubject<Float, Never>()
    let onHeal = PassthroughSubject<Float, Never>()
    let onInteract = PassthroughSubject<Entity?, Never>()
    
    // Single required init for Entity inheritance
    required init() {
        super.init()
        setupComponents()
    }
    
    func setupComponents() {
        // Override in subclasses
    }
    
    func takeDamage(_ amount: Float) {
        health = max(0, health - amount)
        onDamage.send(amount)
        
        if health <= 0 {
            onDeath()
        }
    }
    
    func heal(_ amount: Float) {
        let previousHealth = health
        health = min(maxHealth, health + amount)
        let actualHealing = health - previousHealth
        
        if actualHealing > 0 {
            onHeal.send(actualHealing)
        }
    }
    
    func interact(with entity: Entity?) {
        if isInteractable {
            onInteract.send(entity)
        }
    }
    
    func onDeath() {
        // Override in subclasses
        removeFromParent()
    }
}

// MARK: - Health Component (InteractionComponent is defined in AvatarComponents.swift)
struct HealthComponent: Component {
    var current: Float
    var maximum: Float
    var regenerationRate: Float = 0
    var isInvulnerable: Bool = false
}
