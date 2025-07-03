//
//  EchoEntity.swift
//  FinalStorm-S
//
//  First Echoes entity implementation
//

import RealityKit

class EchoEntity: BaseEntity {
    let echoType: EchoType
    let echoName: String
    
    private var glowIntensity: Float = 1.0
    private var isTeaching: Bool = false
    
    init(type: EchoType, name: String) {
        self.echoType = type
        self.echoName = name
        super.init()
        
        self.name = name
        setupEchoComponents()
    }
    
    required init() {
        fatalError("Use init(type:name:)")
    }
    
    private func setupEchoComponents() {
        // Echo-specific components
        isInteractable = true
        
        components.set(InteractionComponent(
            interactionRadius: 3.0,
            requiresLineOfSight: false,
            interactionType: .talk,
            onInteract: { [weak self] in
                self?.onEchoInteraction()
            }
        ))
        
        // No collision for ethereal beings
        components.remove(CollisionComponent.self)
        
        // Add constant floating animation
        startFloatingAnimation()
    }
    
    private func startFloatingAnimation() {
        // Create smooth up-down floating motion
        let floatHeight: Float = 0.2
        let floatDuration: Double = 3.0
        
        let floatUp = Transform(
            scale: scale,
            rotation: orientation,
            translation: position + [0, floatHeight, 0]
        )
        
        let floatDown = Transform(
            scale: scale,
            rotation: orientation,
            translation: position - [0, floatHeight, 0]
        )
        
        // Create animation sequence
        let upAnimation = FromToByAnimation(
            from: floatDown,
            to: floatUp,
            duration: floatDuration / 2,
            bindTarget: .transform
        )
        
        let downAnimation = FromToByAnimation(
            from: floatUp,
            to: floatDown,
            duration: floatDuration / 2,
            bindTarget: .transform
        )
        
        // This would be implemented with proper animation sequencing
        Task {
            while parent != nil {
                move(to: floatUp, relativeTo: nil, duration: floatDuration / 2)
                try? await Task.sleep(nanoseconds: UInt64(floatDuration / 2 * 1_000_000_000))
                
                move(to: floatDown, relativeTo: nil, duration: floatDuration / 2)
                try? await Task.sleep(nanoseconds: UInt64(floatDuration / 2 * 1_000_000_000))
            }
        }
    }
    
    func setAppearance(_ appearance: EchoAppearance) async {
        do {
            // Load echo-specific mesh
            let mesh = try await MeshResource.load(named: appearance.meshName)
            
            // Create glowing material
            let material = createEchoMaterial()
            
            components.set(ModelComponent(mesh: mesh, materials: [material]))
            scale = appearance.baseScale
            
            // Add particle aura
            addParticleAura(type: appearance.particleType)
            
            // Add light source
            addEchoLight(intensity: appearance.glowIntensity)
            
        } catch {
            // Use default sphere
            let mesh = MeshResource.generateSphere(radius: 0.3)
            let material = createEchoMaterial()
            components.set(ModelComponent(mesh: mesh, materials: [material]))
        }
    }
    
    private func createEchoMaterial() -> Material {
        var material = UnlitMaterial()
        
        let color: UIColor
        switch echoType {
        case .lumi:
            color = .systemYellow
        case .kai:
            color = .systemBlue
        case .terra:
            color = .systemGreen
        case .ignis:
            color = .systemOrange
        }
        
        material.color = .init(tint: color.withAlphaComponent(0.8))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        
        return material
    }
    
    private func addParticleAura(type: ParticleType) {
        var particles = ParticleEmitterComponent()
        
        switch type {
        case .sparkles:
            particles.birthRate = 20
            particles.mainEmitter.size = 0.01
            particles.mainEmitter.sizeVariation = 0.005
            particles.mainEmitter.lifeSpan = 2.0
            particles.mainEmitter.speed = 0.2
            particles.mainEmitter.color = .single(.yellow)
            
        case .data:
            particles.birthRate = 30
            particles.mainEmitter.size = 0.005
            particles.mainEmitter.lifeSpan = 1.5
            particles.mainEmitter.speed = 0.5
            particles.mainEmitter.color = .single(.cyan)
            particles.mainEmitter.birthDirection = .normal
            
        case .leaves:
            particles.birthRate = 10
            particles.mainEmitter.size = 0.02
            particles.mainEmitter.lifeSpan = 3.0
            particles.mainEmitter.speed = 0.3
            particles.mainEmitter.color = .single(.green)
            particles.mainEmitter.angularSpeed = .constant(180)
            
        case .fire:
            particles.birthRate = 40
            particles.mainEmitter.size = 0.015
            particles.mainEmitter.lifeSpan = 1.0
            particles.mainEmitter.speed = 1.0
            particles.mainEmitter.acceleration = [0, 1, 0]
            particles.mainEmitter.color = .evolving(
                start: .single(.orange),
                end: .single(.red)
            )
        }
        
        particles.emitterShape = .sphere
        particles.emitterPosition = [0, 0, 0]
        particles.mainEmitter.opacityOverLife = .linearFade
        
        components.set(particles)
    }
    
    private func addEchoLight(intensity: Float) {
        let lightColor: UIColor
        switch echoType {
        case .lumi:
            lightColor = .systemYellow
        case .kai:
            lightColor = .systemBlue
        case .terra:
            lightColor = .systemGreen
        case .ignis:
            lightColor = .systemOrange
        }
        
        let light = PointLight()
        light.color = lightColor
        light.intensity = intensity * 1000
        light.attenuationRadius = 5.0
        
        components.set(PointLightComponent(light: light))
        
        // Store for pulsing effects
        self.glowIntensity = intensity
    }
    
    // MARK: - Speech and Communication
    func speak(_ dialogue: Dialogue) async {
        // Create speech bubble
        let bubble = createSpeechBubble(text: dialogue.text)
        bubble.position = [0, 1.5, 0]
        addChild(bubble)
        
        // Pulse while speaking
        startSpeakingAnimation()
        
        // Play audio if available
        if let audioURL = dialogue.audioURL {
            await playDialogueAudio(audioURL)
        }
        
        // Wait for dialogue duration
        try? await Task.sleep(nanoseconds: UInt64(dialogue.duration * 1_000_000_000))
        
        // Cleanup
        stopSpeakingAnimation()
        bubble.removeFromParent()
    }
    
    private func createSpeechBubble(text: String) -> Entity {
        let bubble = Entity()
        
        // Background plane
        let background = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 0.5),
            materials: [createBubbleMaterial()]
        )
        background.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        bubble.addChild(background)
        
        // Text mesh
        if let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.1),
            containerFrame: CGRect(x: -0.9, y: -0.2, width: 1.8, height: 0.4),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        ) {
            let textEntity = ModelEntity(
                mesh: textMesh,
                materials: [UnlitMaterial(color: .black)]
            )
            textEntity.position = [0, 0, 0.01]
            bubble.addChild(textEntity)
        }
        
        // Billboard behavior to face camera
        bubble.components.set(BillboardComponent())
        
        return bubble
    }
    
    private func createBubbleMaterial() -> Material {
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.9))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        return material
    }
    
    private func startSpeakingAnimation() {
        // Pulse light while speaking
        if var light = components[PointLightComponent.self] {
            let originalIntensity = light.light.intensity
            
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard self != nil else {
                    timer.invalidate()
                    return
                }
                
                let pulse = sin(Date().timeIntervalSinceReferenceDate * 4)
                light.light.intensity = originalIntensity * (1 + Float(pulse) * 0.3)
                self?.components.set(light)
            }
        }
    }
    
    private func stopSpeakingAnimation() {
        // Reset light to original intensity
        if var light = components[PointLightComponent.self] {
            light.light.intensity = glowIntensity * 1000
            components.set(light)
        }
    }
    
    private func playDialogueAudio(_ url: URL) async {
        // Play spatial audio
        do {
            let audioResource = try await AudioFileResource.load(contentsOf: url)
            playAudio(audioResource)
        } catch {
            print("Failed to play dialogue audio: \(error)")
        }
    }
    
    // MARK: - Interactions
    private func onEchoInteraction() {
        // Notify echo engine of interaction
        NotificationCenter.default.post(
            name: .echoInteracted,
            object: self,
            userInfo: ["echoType": echoType]
        )
    }
    
    func performTeachingSequence(melody: Melody) async {
        isTeaching = true
        
        // Create visual representation of melody
        let melodyVisual = createMelodyVisualization(melody)
        melodyVisual.position = [0, 2, 0]
        addChild(melodyVisual)
        
        // Demonstrate melody pattern
        await demonstrateMelodyPattern(melody)
        
        // Cleanup
        melodyVisual.removeFromParent()
        isTeaching = false
    }
    
    private func createMelodyVisualization(_ melody: Melody) -> Entity {
        let visual = Entity()
        
        // Create note representations
        let noteCount = 5
        for i in 0..<noteCount {
            let angle = Float(i) * 2 * .pi / Float(noteCount)
            let note = createMusicalNote(color: melody.harmonyColor)
            note.position = [
                cos(angle) * 0.5,
                0,
                sin(angle) * 0.5
            ]
            visual.addChild(note)
        }
        
        // Rotating animation
        let rotation = FromToByAnimation(
            by: Transform(rotation: simd_quatf(angle: 2 * .pi, axis: [0, 1, 0])),
            duration: 5,
            bindTarget: .transform
        )
        
        if let animation = try? AnimationResource.generate(with: rotation) {
            visual.playAnimation(animation.repeat())
        }
        
        return visual
    }
    
    private func createMusicalNote(color: UIColor) -> Entity {
        let note = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [UnlitMaterial(color: color)]
        )
        
        // Add glow
        note.components.set(PointLightComponent(
            color: .init(color),
            intensity: 100,
            attenuationRadius: 0.5
        ))
        
        return note
    }
    
    private func demonstrateMelodyPattern(_ melody: Melody) async {
        // Play melody audio pattern
        let notes = generateMelodyNotes(for: melody.type)
        
        for note in notes {
            // Visual pulse
            pulseEffect()
            
            // Play note sound
            playNote(frequency: note.frequency, duration: note.duration)
            
            // Wait
            try? await Task.sleep(nanoseconds: UInt64(note.duration * 1_000_000_000))
        }
    }
    
    private func generateMelodyNotes(for type: MelodyType) -> [(frequency: Float, duration: TimeInterval)] {
        switch type {
        case .restoration:
            return [
                (440, 0.5),    // A4
                (523, 0.5),    // C5
                (659, 0.5),    // E5
                (523, 0.5),    // C5
                (440, 1.0)     // A4
            ]
        case .exploration:
            return [
                (392, 0.3),    // G4
                (440, 0.3),    // A4
                (494, 0.3),    // B4
                (523, 0.3),    // C5
                (587, 0.6)     // D5
            ]
        case .creation:
            return [
                (523, 0.4),    // C5
                (659, 0.4),    // E5
                (784, 0.4),    // G5
                (659, 0.4),    // E5
                (523, 0.8)     // C5
            ]
        }
    }
    
    private func playNote(frequency: Float, duration: TimeInterval) {
        // Generate and play tone
        // This would use spatial audio
    }
    
    private func pulseEffect() {
        // Quick scale pulse
        let originalScale = scale
        
        move(to: Transform(scale: originalScale * 1.2), relativeTo: nil, duration: 0.1)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.move(to: Transform(scale: originalScale), relativeTo: nil, duration: 0.1)
        }
    }
    
    // MARK: - Behavior Actions
    func moveToNearestSadEntity() async {
        // Find entities with low harmony
        // This would query the world manager
        let target = SIMD3<Float>(5, 0, 5) // Placeholder
        
        await moveToPosition(target)
    }
    
    func offerEncouragement() async {
        // Play encouraging animation
        playAnimation(.gesturing)
        
        // Emit positive particles
        emitEncouragementParticles()
        
        // Speak encouragement
        let dialogue = Dialogue(
            text: "Don't lose hope! The Song still flows through you.",
            emotion: .happy,
            duration: 3.0,
            audioURL: nil
        )
        await speak(dialogue)
    }
    
    func wanderPlayfully() async {
        // Random movement in small area
        let randomOffset = SIMD3<Float>(
            Float.random(in: -3...3),
            0,
            Float.random(in: -3...3)
        )
        
        let targetPosition = position + randomOffset
        await moveToPosition(targetPosition)
    }
    
    func provideAnalysis() async {
        // KAI-specific behavior
        playAnimation(.gesturing)
        
        // Create holographic display
        let display = createAnalysisDisplay()
        display.position = [0, 2, 1]
        addChild(display)
        
        // Analytical dialogue
        let dialogue = Dialogue(
            text: "My analysis indicates a 87.3% probability of Silence influence in this sector.",
            emotion: .neutral,
            duration: 4.0,
            audioURL: nil
        )
        await speak(dialogue)
        
        // Cleanup
        display.removeFromParent()
    }
    
    func studyEnvironment() async {
        // Scanning animation
        let scanEffect = createScanEffect()
        addChild(scanEffect)
        
        // Rotate slowly while scanning
        let rotation = Transform(rotation: orientation * simd_quatf(angle: 2 * .pi, axis: [0, 1, 0]))
        move(to: rotation, relativeTo: nil, duration: 5.0)
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        scanEffect.removeFromParent()
    }
    
    func healNearbyEntities() async {
        // Terra-specific behavior
        playAnimation(.gesturing)
        
        // Create healing aura
        let aura = createHealingAura()
        addChild(aura)
        
        // Healing particles
        emitHealingParticles()
        
        // Apply healing to nearby entities
        // This would interact with world manager
        
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        aura.removeFromParent()
    }
    
    func tendToNature() async {
        // Find nearest plant/nature entity
        // Create growth effect
        let growthEffect = createGrowthEffect()
        growthEffect.position = [2, 0, 0]
        parent?.addChild(growthEffect)
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        growthEffect.removeFromParent()
    }
    
    func defendArea() async {
        // Ignis-specific behavior
        playAnimation(.gesturing)
        
        // Create fire shield
        let shield = createFireShield()
        addChild(shield)
        
        // Defensive stance
        let dialogue = Dialogue(
            text: "Stand behind me! I'll hold them back!",
            emotion: .excited,
            duration: 3.0,
            audioURL: nil
        )
        await speak(dialogue)
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        shield.removeFromParent()
    }
    
    func rallyAllies() async {
        // Inspiring animation
        playAnimation(.gesturing)
        
        // Rally effect
        let rallyEffect = createRallyEffect()
        addChild(rallyEffect)
        
        // Inspiring dialogue
        let dialogue = Dialogue(
            text: "Together we are stronger! Let the Song guide our courage!",
            emotion: .excited,
            duration: 4.0,
            audioURL: nil
        )
        await speak(dialogue)
        
        rallyEffect.removeFromParent()
    }
    
    // MARK: - Effect Creation
    private func emitEncouragementParticles() {
        let particles = Entity()
        
        var emitter = ParticleEmitterComponent()
        emitter.birthRate = 0
        emitter.burstCount = 50
        emitter.emitterShape = .sphere
        emitter.mainEmitter.lifeSpan = 2.0
        emitter.mainEmitter.speed = 1.0
        emitter.mainEmitter.color = .single(.yellow)
        emitter.mainEmitter.size = 0.02
        emitter.mainEmitter.opacityOverLife = .linearFade
        
        particles.components.set(emitter)
        particles.position = [0, 1, 0]
        addChild(particles)
        
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            particles.removeFromParent()
        }
    }
    
    private func createAnalysisDisplay() -> Entity {
        let display = Entity()
        
        // Holographic grid
        let grid = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1),
            materials: [createHologramMaterial()]
        )
        grid.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        display.addChild(grid)
        
        // Data points
        for _ in 0..<10 {
            let point = ModelEntity(
                mesh: .generateSphere(radius: 0.02),
                materials: [UnlitMaterial(color: .cyan)]
            )
            point.position = [
                Float.random(in: -0.4...0.4),
                Float.random(in: -0.4...0.4),
                0.01
            ]
            display.addChild(point)
        }
        
        return display
    }
    
    private func createHologramMaterial() -> Material {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.cyan.withAlphaComponent(0.3))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        return material
    }
    
    private func createScanEffect() -> Entity {
        let scan = Entity()
        
        // Scanning beam
        let beam = ModelEntity(
            mesh: .generateCylinder(height: 3, radius: 0.01),
            materials: [UnlitMaterial(color: .blue)]
        )
        beam.position = [0, 0, 1.5]
        beam.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        scan.addChild(beam)
        
        // Rotating animation
        let rotation = FromToByAnimation(
            by: Transform(rotation: simd_quatf(angle: 2 * .pi, axis: [0, 1, 0])),
            duration: 2,
            bindTarget: .transform
        )
        
        if let animation = try? AnimationResource.generate(with: rotation) {
            scan.playAnimation(animation.repeat())
        }
        
        return scan
    }
    
    private func createHealingAura() -> Entity {
        let aura = Entity()
        
        // Green glow sphere
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 3),
            materials: [createAuraMaterial(color: .green)]
        )
        aura.addChild(sphere)
        
        // Pulsing animation
        let pulse = FromToByAnimation(
            from: Transform(scale: [1, 1, 1]),
            to: Transform(scale: [1.2, 1.2, 1.2]),
            duration: 1.5,
            bindTarget: .transform
        )
        
        if let animation = try? AnimationResource.generate(with: pulse) {
            sphere.playAnimation(animation.repeat(autoreverses: true))
        }
        
        return aura
    }
    
    private func createAuraMaterial(color: UIColor) -> Material {
        var material = UnlitMaterial()
        material.color = .init(tint: color.withAlphaComponent(0.2))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.2))
        return material
    }
    
    private func emitHealingParticles() {
        let particles = Entity()
        
        var emitter = ParticleEmitterComponent()
        emitter.birthRate = 100
        emitter.emitterShape = .sphere
        emitter.emitterPosition = [0, 0, 0]
        emitter.emitterPositionVariation = [3, 0, 3]
        emitter.mainEmitter.lifeSpan = 3.0
        emitter.mainEmitter.speed = 0.5
        emitter.mainEmitter.acceleration = [0, 1, 0]
        emitter.mainEmitter.color = .evolving(
            start: .single(.green),
            end: .single(.white)
        )
        emitter.mainEmitter.size = 0.03
        emitter.mainEmitter.opacityOverLife = .linearFade
        
        particles.components.set(emitter)
        addChild(particles)
        
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            particles.removeFromParent()
        }
    }
    
    private func createGrowthEffect() -> Entity {
        let growth = Entity()
        
        // Sprouting plants
        for i in 0..<5 {
            let angle = Float(i) * 2 * .pi / 5
            let plant = createPlantSprite()
            plant.position = [
                cos(angle) * 0.5,
                0,
                sin(angle) * 0.5
            ]
            
            // Growing animation
            plant.scale = [0.01, 0.01, 0.01]
            plant.move(to: Transform(scale: [1, 1, 1]), relativeTo: nil, duration: 2.0)
            
            growth.addChild(plant)
        }
        
        return growth
    }
    
    private func createPlantSprite() -> Entity {
        let plant = ModelEntity(
            mesh: .generateCone(height: 0.3, radius: 0.1),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        return plant
    }
    
    private func createFireShield() -> Entity {
        let shield = Entity()
        
        // Fire ring
        let ring = ModelEntity(
            mesh: .generateTorus(meanRadius: 2, tubeRadius: 0.1),
            materials: [UnlitMaterial(color: .orange)]
        )
        ring.position = [0, 0.5, 0]
        shield.addChild(ring)
        
        // Fire particles
        var particles = ParticleEmitterComponent()
        particles.birthRate = 200
        particles.emitterShape = .torus
        particles.emitterPosition = [0, 0.5, 0]
        particles.mainEmitter.lifeSpan = 1.0
        particles.mainEmitter.speed = 2.0
        particles.mainEmitter.acceleration = [0, 3, 0]
        particles.mainEmitter.color = .evolving(
            start: .single(.orange),
            end: .single(.red)
        )
        particles.mainEmitter.size = 0.05
        particles.mainEmitter.opacityOverLife = .linearFade
        
        shield.components.set(particles)
        
        // Rotation
        let rotation = FromToByAnimation(
            by: Transform(rotation: simd_quatf(angle: 2 * .pi, axis: [0, 1, 0])),
            duration: 3,
            bindTarget: .transform
        )
        
        if let animation = try? AnimationResource.generate(with: rotation) {
            shield.playAnimation(animation.repeat())
        }
        
        return shield
    }
    
    private func createRallyEffect() -> Entity {
        let rally = Entity()
        
        // Banner or flag effect
        let banner = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1.5),
            materials: [createBannerMaterial()]
        )
        banner.position = [0, 2, 0]
        rally.addChild(banner)
        
        // Inspiring particles
        var particles = ParticleEmitterComponent()
        particles.birthRate = 50
        particles.emitterShape = .point
        particles.emitterPosition = [0, 3, 0]
        particles.mainEmitter.lifeSpan = 3.0
        particles.mainEmitter.speed = 0.5
        particles.mainEmitter.acceleration = [0, -0.5, 0]
        particles.mainEmitter.color = .single(.systemOrange)
        particles.mainEmitter.size = 0.02
        particles.mainEmitter.opacityOverLife = .linearFade
        
        rally.components.set(particles)
        
        return rally
    }
    
    private func createBannerMaterial() -> Material {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.systemOrange.withAlphaComponent(0.8))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        return material
    }
    
    private func moveToPosition(_ target: SIMD3<Float>) async {
        let duration: TimeInterval = 3.0
        move(to: Transform(translation: target), relativeTo: nil, duration: duration)
        
        // Play movement animation
        playAnimation(.floating)
        
        // Wait for movement to complete
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        
        // Return to idle
        playAnimation(.idle)
    }
    
    func playAnimation(_ animation: EchoAnimation) {
        // Animation implementation
        // This would load and play specific animations
    }
}

// MARK: - Extensions
extension Notification.Name {
    static let echoInteracted = Notification.Name("echoInteracted")
}

// MARK: - Supporting Components
struct BillboardComponent: Component {
    // Makes entity always face camera
}

struct SpatialAudioComponent: Component {
    let melody: Melody
    let volume: Float = 1.0
    let falloffDistance: Float = 10.0
}
