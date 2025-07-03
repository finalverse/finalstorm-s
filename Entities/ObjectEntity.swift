//
//  ObjectEntity.swift
//  FinalStorm-S
//
//  Base class for world objects
//

import RealityKit

class ObjectEntity: BaseEntity {
    var objectType: ObjectType = .prop
    var isPickupable: Bool = false
    var isUsable: Bool = false
    
    override func setupComponents() {
        super.setupComponents()
        
        // Default interaction for objects
        isInteractable = true
        
        components.set(InteractionComponent(
            interactionRadius: 1.5,
            requiresLineOfSight: true,
            interactionType: .activate,
            onInteract: { [weak self] in
                self?.onActivate()
            }
        ))
    }
    
    func onActivate() {
        // Override in subclasses
    }
    
    func onPickup(by entity: Entity) {
        guard isPickupable else { return }
        
        // Add to inventory
        if let avatar = entity as? AvatarEntity {
            // Add to avatar's inventory
            removeFromParent()
        }
    }
}

// MARK: - Specific Object Types
class HarmonyBlossomEntity: ObjectEntity {
    override func setupComponents() {
        super.setupComponents()
        
        objectType = .interactable
        
        // Visual setup
        Task {
            await setupBlossomVisuals()
        }
    }
    
    private func setupBlossomVisuals() async {
        do {
            // Load blossom mesh
            let mesh = try await MeshResource.load(named: "harmony_blossom")
            
            // Create material that responds to harmony
            var material = PhysicallyBasedMaterial()
            material.baseColor = .color(.systemPink)
            material.emissiveColor = .color(.systemPink)
            material.emissiveIntensity = 0.5
            
            components.set(ModelComponent(mesh: mesh, materials: [material]))
            
            // Add gentle glow
            components.set(PointLightComponent(
                color: .init(red: 1.0, green: 0.5, blue: 0.7),
                intensity: 200,
                attenuationRadius: 3
            ))
            
            // Pulsing animation
            startPulsingAnimation()
        } catch {
            // Use placeholder
            let mesh = MeshResource.generateSphere(radius: 0.2)
            components.set(ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .systemPink, isMetallic: false)]))
        }
    }
    
    private func startPulsingAnimation() {
        let scaleAnimation = FromToByAnimation(
            from: scale,
            to: scale * 1.1,
            duration: 2,
            bindTarget: .scale
        )
        
        if let animation = try? AnimationResource.generate(with: scaleAnimation) {
            playAnimation(animation.repeat(autoreverses: true))
        }
    }
    
    override func onActivate() {
        // Bloom when harmonized
        bloom()
    }
    
    private func bloom() {
        // Stop pulsing
        stopAllAnimations()
        
        // Expand and brighten
        move(to: Transform(scale: scale * 1.5), relativeTo: nil, duration: 1.0)
        
        // Update material
        if var modelComponent = components[ModelComponent.self],
           var material = modelComponent.materials.first as? PhysicallyBasedMaterial {
            material.emissiveIntensity = 2.0
            modelComponent.materials = [material]
            components.set(modelComponent)
        }
        
        // Update light
        if var light = components[PointLightComponent.self] {
            light.light.intensity = 1000
            light.light.attenuationRadius = 5
            components.set(light)
        }
        
        // Emit harmony particles
        emitHarmonyParticles()
    }
    
    private func emitHarmonyParticles() {
        let particleEntity = Entity()
        
        var particles = ParticleEmitterComponent()
        particles.birthRate = 200
        particles.burstCount = 200
        particles.emitterShape = .sphere
        particles.mainEmitter.lifeSpan = 3.0
        particles.mainEmitter.speed = 2.0
        particles.mainEmitter.color = .evolving(
            start: .single(.systemPink),
            end: .single(.white)
        )
        particles.mainEmitter.size = 0.05
        particles.mainEmitter.sizeVariation = 0.02
        particles.mainEmitter.opacityOverLife = .linearFade
        
        particleEntity.components.set(particles)
        addChild(particleEntity)
        
        // Remove after emission
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            particleEntity.removeFromParent()
        }
    }
}

class CorruptedEntity: ObjectEntity {
    var corruptionLevel: Float = 1.0
    
    override func setupComponents() {
        super.setupComponents()
        
        objectType = .hostile
        
        // Corruption visuals
        Task {
            await setupCorruptionVisuals()
        }
        
        // Damage nearby entities
        startCorruptionAura()
    }
    
    private func setupCorruptionVisuals() async {
        // Dark, twisted appearance
        let mesh = MeshResource.generateBox(size: [0.5, 0.5, 0.5])
        
        var material = SimpleMaterial()
        material.color = .init(tint: .darkGray)
        material.roughness = .float(0.9)
        material.metallic = .float(0.1)
        
        components.set(ModelComponent(mesh: mesh, materials: [material]))
        
        // Add corruption particles
        var particles = ParticleEmitterComponent()
        particles.birthRate = 50
        particles.emitterShape = .box
        particles.mainEmitter.color = .evolving(
            start: .single(.purple),
            end: .single(.black)
        )
        particles.mainEmitter.lifeSpan = 2.0
        particles.mainEmitter.size = 0.02
        particles.mainEmitter.speed = 0.5
        particles.mainEmitter.acceleration = [0, -0.5, 0]
        
        components.set(particles)
    }
    
    private func startCorruptionAura() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.damageNearbyEntities()
        }
    }
    
    private func damageNearbyEntities() {
        // Find entities within corruption radius
        let corruptionRadius: Float = 3.0
        
        // This would query the spatial index
        // For now, simplified implementation
    }
    
    func purify(amount: Float) {
        corruptionLevel = max(0, corruptionLevel - amount)
        
        if corruptionLevel <= 0 {
            // Transform into purified entity
            transformToPurified()
        } else {
            // Update visuals based on corruption level
            updateCorruptionVisuals()
        }
    }
    
    private func transformToPurified() {
        // Remove corruption effects
        components.remove(ParticleEmitterComponent.self)
        
        // Change to purified appearance
        if var modelComponent = components[ModelComponent.self] {
            var material = SimpleMaterial()
            material.color = .init(tint: .white)
            material.roughness = .float(0.3)
            material.metallic = .float(0.7)
            modelComponent.materials = [material]
            components.set(modelComponent)
        }
        
        // Add celebration particles
        celebratePurification()
    }
    
    private func celebratePurification() {
        let celebration = Entity()
        
        var particles = ParticleEmitterComponent()
        particles.birthRate = 0
        particles.burstCount = 100
        particles.emitterShape = .sphere
        particles.mainEmitter.lifeSpan = 2.0
        particles.mainEmitter.speed = 3.0
        particles.mainEmitter.color = .evolving(
            start: .single(.white),
            end: .single(.yellow)
        )
        particles.mainEmitter.size = 0.03
        particles.mainEmitter.opacityOverLife = .linearFade
        
        celebration.components.set(particles)
        addChild(celebration)
        
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            celebration.removeFromParent()
        }
    }
    
    private func updateCorruptionVisuals() {
        // Update material darkness based on corruption level
        if var modelComponent = components[ModelComponent.self],
           var material = modelComponent.materials.first as? SimpleMaterial {
            let darkness = corruptionLevel
            material.color = .init(tint: UIColor(white: 1.0 - darkness * 0.7, alpha: 1.0))
            modelComponent.materials = [material]
            components.set(modelComponent)
        }
    }
}

class CelestialBloomEntity: ObjectEntity {
    override func setupComponents() {
        super.setupComponents()
        
        objectType = .environmental
        isInteractable = false
        
        // Celestial appearance
        Task {
            await setupCelestialVisuals()
        }
        
        // Boost nearby harmony
        startHarmonyAura()
    }
    
    private func setupCelestialVisuals() async {
        // Ethereal flower appearance
        let petalCount = 8
        
        for i in 0..<petalCount {
            let angle = Float(i) * 2 * .pi / Float(petalCount)
            let petal = createPetal()
            petal.position = [
                cos(angle) * 0.3,
                0,
                sin(angle) * 0.3
            ]
            petal.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            addChild(petal)
        }
        
        // Central glow
        let center = Entity()
        center.components.set(PointLightComponent(
            color: .init(red: 1.0, green: 0.9, blue: 0.7),
            intensity: 2000,
            attenuationRadius: 10
        ))
        addChild(center)
        
        // Floating particles
        var particles = ParticleEmitterComponent()
        particles.birthRate = 30
        particles.emitterShape = .sphere
        particles.emitterPosition = [0, 0.5, 0]
        particles.mainEmitter.lifeSpan = 5.0
        particles.mainEmitter.speed = 0.3
        particles.mainEmitter.acceleration = [0, 0.1, 0]
        particles.mainEmitter.color = .evolving(
            start: .single(.yellow),
            end: .single(.white)
        )
        particles.mainEmitter.size = 0.01
        particles.mainEmitter.sizeVariation = 0.005
        particles.mainEmitter.opacityOverLife = .linearFade
        
        components.set(particles)
    }
    
    private func createPetal() -> Entity {
        let petal = ModelEntity(
            mesh: .generatePlane(width: 0.2, depth: 0.4),
            materials: [createPetalMaterial()]
        )
        
        // Gentle swaying animation
        let swayAnimation = FromToByAnimation(
            from: petal.orientation,
            to: petal.orientation * simd_quatf(angle: .pi / 12, axis: [0, 0, 1]),
            duration: 3,
            bindTarget: .orientation
        )
        
        if let animation = try? AnimationResource.generate(with: swayAnimation) {
            petal.playAnimation(animation.repeat(autoreverses: true))
        }
        
        return petal
    }
    
    private func createPetalMaterial() -> Material {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 0.8))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        return material
    }
    
    private func startHarmonyAura() {
        // Periodically boost harmony in the area
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.emitHarmonyWave()
        }
    }
    
    private func emitHarmonyWave() {
        // Create expanding ring effect
        let wave = ModelEntity(
            mesh: .generateSphere(radius: 0.1),
            materials: [UnlitMaterial(color: .init(tint: .yellow.withAlphaComponent(0.3)))]
        )
        
        addChild(wave)
        
        // Expand and fade
        wave.move(to: Transform(scale: [20, 0.1, 20]), relativeTo: nil, duration: 3.0)
        
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            wave.removeFromParent()
        }
        
        // Apply harmony boost to nearby entities
        // This would interact with the world manager
    }
}

// MARK: - Supporting Types
enum ObjectType {
    case prop
    case interactable
    case pickup
    case environmental
    case hostile
}
