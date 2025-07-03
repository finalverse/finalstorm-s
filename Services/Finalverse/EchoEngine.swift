//
//  EchoEngine.swift
//  FinalStorm-S
//
//  Manages the First Echoes (Lumi, KAI, Terra, Ignis) and other AI-driven NPCs
//

import Foundation
import RealityKit
import Combine

@MainActor
class EchoEngine: ObservableObject {
    // MARK: - Properties
    @Published var activeEchoes: [EchoEntity] = []
    @Published var echoStates: [UUID: EchoState] = [:]
    
    private let networkClient: FinalverseNetworkClient
    private let aiOrchestra: AIOrchestra
    private let behaviorSystem: BehaviorSystem
    private var updateCancellable: AnyCancellable?
    
    // The First Echoes
    private var lumi: EchoEntity?
    private var kai: EchoEntity?
    private var terra: EchoEntity?
    private var ignis: EchoEntity?
    
    init() {
        self.networkClient = FinalverseNetworkClient(service: .echoEngine)
        self.aiOrchestra = AIOrchestra()
        self.behaviorSystem = BehaviorSystem()
    }
    
    // MARK: - Initialization
    func initialize() async {
        do {
            try await networkClient.connect()
            
            // Initialize First Echoes
            await initializeFirstEchoes()
            
            // Start behavior update loop
            startBehaviorUpdates()
        } catch {
            print("Failed to initialize Echo Engine: \(error)")
        }
    }
    
    // MARK: - First Echoes Creation
    private func initializeFirstEchoes() async {
        // Create Lumi - Echo of Hope and Discovery
        lumi = await createFirstEcho(
            type: .lumi,
            name: "Lumi",
            appearance: .lumiAppearance,
            personality: .hopeful,
            primaryColor: .systemYellow
        )
        
        // Create KAI - Echo of Knowledge and Understanding
        kai = await createFirstEcho(
            type: .kai,
            name: "KAI",
            appearance: .kaiAppearance,
            personality: .logical,
            primaryColor: .systemBlue
        )
        
        // Create Terra - Echo of Resilience and Growth
        terra = await createFirstEcho(
            type: .terra,
            name: "Terra",
            appearance: .terraAppearance,
            personality: .nurturing,
            primaryColor: .systemGreen
        )
        
        // Create Ignis - Echo of Courage and Creation
        ignis = await createFirstEcho(
            type: .ignis,
            name: "Ignis",
            appearance: .ignisAppearance,
            personality: .passionate,
            primaryColor: .systemOrange
        )
    }
    
    private func createFirstEcho(
        type: EchoType,
        name: String,
        appearance: EchoAppearance,
        personality: PersonalityType,
        primaryColor: UIColor
    ) async -> EchoEntity {
        let echo = EchoEntity(type: type, name: name)
        
        // Set appearance
        await echo.setAppearance(appearance)
        
        // Initialize components
        echo.components.set(EchoComponent(
            type: type,
            personality: personality,
            primaryColor: primaryColor
        ))
        
        echo.components.set(AIBehaviorComponent(
            behaviorTree: createBehaviorTree(for: type)
        ))
        
        echo.components.set(DialogueComponent(
            voiceProfile: type.voiceProfile
        ))
        
        // Add to active echoes
        activeEchoes.append(echo)
        echoStates[echo.id] = EchoState(mood: .neutral, activity: .idle)
        
        return echo
    }
    
    // MARK: - Echo Behavior
    func summonEcho(_ type: EchoType, at location: SIMD3<Float>) async {
        guard let echo = getEcho(type: type) else { return }
        
        // Animate appearance
        echo.position = location + SIMD3<Float>(0, 10, 0) // Start above
        echo.scale = SIMD3<Float>(repeating: 0.01)
        
        // Fade in with particles
        let appearanceEffect = createAppearanceEffect(for: type)
        echo.addChild(appearanceEffect)
        
        // Animate to position
        echo.move(to: Transform(scale: .one, translation: location),
                 relativeTo: nil,
                 duration: 2.0)
        
        // Update state
        echoStates[echo.id]?.activity = .interacting
        
        // Play greeting
        await playEchoGreeting(echo)
    }
    
    func requestGuidance(from echoType: EchoType, topic: GuidanceTopic) async -> String? {
        guard let echo = getEcho(type: echoType) else { return nil }
        
        // Generate contextual dialogue using AI Orchestra
        let context = DialogueContext(
            speaker: echoType,
            topic: topic,
            playerState: getCurrentPlayerState(),
            worldState: getCurrentWorldState()
        )
        
        let dialogue = await aiOrchestra.generateDialogue(context: context)
        
        // Play dialogue with appropriate emotion
        await echo.speak(dialogue)
        
        return dialogue.text
    }
    
    // MARK: - Echo Interactions
    func interactWithEcho(_ echo: EchoEntity, interaction: InteractionType) async {
        guard let state = echoStates[echo.id] else { return }
        
        switch interaction {
        case .talk:
            await handleConversation(with: echo)
        case .questGive:
            await offerQuest(from: echo)
        case .teach:
            await teachMelody(from: echo)
        case .accompany:
            await toggleCompanion(echo)
        }
    }
    
    private func handleConversation(with echo: EchoEntity) async {
        // Update mood based on conversation
        if let component = echo.components[EchoComponent.self] {
            let newMood = component.personality.respondToInteraction()
            echoStates[echo.id]?.mood = newMood
            
            // Generate and play contextual dialogue
            let dialogue = await generateContextualDialogue(for: echo, mood: newMood)
            await echo.speak(dialogue)
        }
    }
    
    private func teachMelody(from echo: EchoEntity) async {
        guard let echoComponent = echo.components[EchoComponent.self] else { return }
        
        // Each Echo teaches different melodies
        let melody: Melody
        switch echoComponent.type {
        case .lumi:
            melody = .illumination
        case .kai:
            melody = .analysis
        case .terra:
            melody = .growth
        case .ignis:
            melody = .forge
        }
        
        // Visual teaching sequence
        await performTeachingSequence(echo: echo, melody: melody)
        
        // Grant melody to player
        if let avatarSystem = getAvatarSystem() {
            avatarSystem.learnMelody(melody)
        }
    }
    
    // MARK: - Behavior System
    private func createBehaviorTree(for echoType: EchoType) -> BehaviorTree {
        let tree = BehaviorTree()
        
        switch echoType {
        case .lumi:
            // Lumi seeks out sad or lost entities to help
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.nearbyEntitiesNeedHelp },
                    ActionNode { echo in await echo.moveToNearestSadEntity() },
                    ActionNode { echo in await echo.offerEncouragement() }
                ]),
                ActionNode { echo in await echo.wanderPlayfully() }
            ])
            
        case .kai:
            // KAI analyzes and provides information
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.playerHasQuestion },
                    ActionNode { echo in await echo.provideAnalysis() }
                ]),
                ActionNode { echo in await echo.studyEnvironment() }
            ])
            
        case .terra:
            // Terra nurtures and heals
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.nearbyEntitiesDamaged },
                    ActionNode { echo in await echo.healNearbyEntities() }
                ]),
                ActionNode { echo in await echo.tendToNature() }
            ])
            
        case .ignis:
            // Ignis inspires and protects
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.threatDetected },
                    ActionNode { echo in await echo.defendArea() }
                ]),
                ActionNode { echo in await echo.rallyAllies() }
            ])
        }
        
        return tree
    }
    
    private func startBehaviorUpdates() {
        updateCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.updateEchoBehaviors()
                }
            }
    }
    
    private func updateEchoBehaviors() async {
        for echo in activeEchoes {
            guard let state = echoStates[echo.id],
                  let behavior = echo.components[AIBehaviorComponent.self] else { continue }
            
            // Execute behavior tree
            await behavior.behaviorTree.execute(echo: echo, state: state)
            
            // Update animations based on state
            updateEchoAnimation(echo, state: state)
        }
    }
    
    // MARK: - Visual Effects
    private func createAppearanceEffect(for type: EchoType) -> Entity {
        let effect = Entity()
        
        var particles = ParticleEmitterComponent()
        particles.birthRate = 200
        particles.emitterShape = .sphere
        particles.mainEmitter.lifeSpan = 1.0
        
        // Customize per Echo
        switch type {
        case .lumi:
            particles.mainEmitter.color = .evolving(
                start: .single(.systemYellow),
                end: .single(.white)
            )
            particles.mainEmitter.size = 0.02
            
        case .kai:
            particles.mainEmitter.color = .evolving(
                start: .single(.systemBlue),
                end: .single(.cyan)
            )
            particles.mainEmitter.size = 0.01
            particles.mainEmitter.angularSpeed = .constant(360)
            
        case .terra:
            particles.mainEmitter.color = .evolving(
                start: .single(.systemGreen),
                end: .single(.systemBrown)
            )
            particles.mainEmitter.size = 0.03
            
        case .ignis:
            particles.mainEmitter.color = .evolving(
                start: .single(.systemOrange),
                end: .single(.systemRed)
            )
            particles.mainEmitter.size = 0.04
            particles.mainEmitter.isEmitting = true
        }
        
        effect.components.set(particles)
        
        return effect
    }
    
    // MARK: - Helper Methods
    private func getEcho(type: EchoType) -> EchoEntity? {
        switch type {
        case .lumi: return lumi
        case .kai: return kai
        case .terra: return terra
        case .ignis: return ignis
        }
    }
    
    private func getCurrentPlayerState() -> PlayerState {
        // Get from avatar system
        return PlayerState()
    }
    
    private func getCurrentWorldState() -> WorldState {
        // Get from world manager
        return WorldState()
    }
    
    private func getAvatarSystem() -> AvatarSystem? {
        // Get from app state
        return nil
    }
    
    private func updateEchoAnimation(_ echo: EchoEntity, state: EchoState) {
        // Update animation based on activity
        switch state.activity {
        case .idle:
            echo.playAnimation(.idle)
        case .moving:
            echo.playAnimation(.floating)
        case .interacting:
            echo.playAnimation(.gesturing)
        case .teaching:
            echo.playAnimation(.demonstrating)
        }
    }
}

// MARK: - Supporting Types
enum EchoType: String {
    case lumi = "Lumi"
    case kai = "KAI"
    case terra = "Terra"
    case ignis = "Ignis"
    
    var voiceProfile: VoiceProfile {
        switch self {
        case .lumi:
            return VoiceProfile(pitch: 1.3, speed: 1.1, timbre: .bright)
        case .kai:
            return VoiceProfile(pitch: 0.9, speed: 0.95, timbre: .digital)
        case .terra:
            return VoiceProfile(pitch: 0.7, speed: 0.85, timbre: .warm)
        case .ignis:
            return VoiceProfile(pitch: 1.0, speed: 1.15, timbre: .bold)
        }
    }
}

struct EchoState {
    var mood: Mood
    var activity: EchoActivity
    var companionTarget: UUID?
    
    enum Mood {
        case happy, neutral, concerned, excited
    }
    
    enum EchoActivity {
        case idle, moving, interacting, teaching
    }
}

struct EchoComponent: Component {
    let type: EchoType
    let personality: PersonalityType
    let primaryColor: UIColor
    var knownMelodies: [Melody] = []
    var teachingCooldown: TimeInterval = 0
}

enum PersonalityType {
    case hopeful
    case logical
    case nurturing
    case passionate
    
    func respondToInteraction() -> EchoState.Mood {
        switch self {
        case .hopeful:
            return .happy
        case .logical:
            return .neutral
        case .nurturing:
            return .concerned
        case .passionate:
            return .excited
        }
    }
}

struct EchoAppearance {
    let meshName: String
    let baseScale: SIMD3<Float>
    let glowIntensity: Float
    let particleType: ParticleType
    
    static let lumiAppearance = EchoAppearance(
        meshName: "lumi_model",
        baseScale: SIMD3<Float>(0.3, 0.3, 0.3),
        glowIntensity: 2.0,
        particleType: .sparkles
    )
    
    static let kaiAppearance = EchoAppearance(
        meshName: "kai_model",
        baseScale: SIMD3<Float>(0.5, 0.5, 0.5),
        glowIntensity: 1.5,
        particleType: .data
    )
    
    static let terraAppearance = EchoAppearance(
        meshName: "terra_model",
        baseScale: SIMD3<Float>(0.8, 0.8, 0.8),
        glowIntensity: 1.0,
        particleType: .leaves
    )
    
    static let ignisAppearance = EchoAppearance(
        meshName: "ignis_model",
        baseScale: SIMD3<Float>(0.6, 0.6, 0.6),
        glowIntensity: 3.0,
        particleType: .fire
    )
}

enum ParticleType {
    case sparkles
    case data
    case leaves
    case fire
}

enum GuidanceTopic {
    case firstSteps
    case songweaving
    case exploration
    case combat
    case lore
    case quests
}

// MARK: - Echo Entity
class EchoEntity: Entity {
    let echoType: EchoType
    let echoName: String
    
    init(type: EchoType, name: String) {
        self.echoType = type
        self.echoName = name
        super.init()
        
        self.name = name
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
    func setAppearance(_ appearance: EchoAppearance) async {
        // Load mesh
        do {
            let mesh = try await MeshResource.load(named: appearance.meshName)
            
            // Create glowing material
            var material = PhysicallyBasedMaterial()
            material.baseColor = .color(.white)
            material.emissiveColor = .color(echoType.primaryColor)
            material.emissiveIntensity = appearance.glowIntensity
            
            self.components.set(ModelComponent(mesh: mesh, materials: [material]))
            self.scale = appearance.baseScale
            
            // Add floating animation
            startFloatingAnimation()
        } catch {
            print("Failed to load Echo appearance: \(error)")
        }
    }
    
    func speak(_ dialogue: Dialogue) async {
        // Create speech bubble
        let bubble = SpeechBubbleEntity(text: dialogue.text)
        bubble.position = [0, 1.5, 0] // Above echo
        self.addChild(bubble)
        
        // Play audio if available
        if let audioURL = dialogue.audioURL {
            let audioResource = try? await AudioFileResource.load(contentsOf: audioURL)
            if let audio = audioResource {
                self.playAudio(audio)
            }
        }
        
        // Remove bubble after duration
        Task {
            try await Task.sleep(nanoseconds: UInt64(dialogue.duration * 1_000_000_000))
            bubble.removeFromParent()
        }
    }
    
    func playAnimation(_ animation: EchoAnimation) {
        // Play predefined animations
        switch animation {
        case .idle:
            // Gentle bobbing
            break
        case .floating:
            // Smooth floating movement
            break
        case .gesturing:
            // Hand/appendage movements
            break
        case .demonstrating:
            // Teaching animations
            break
        }
    }
    
    private func startFloatingAnimation() {
        // Create gentle floating motion
        let floatUp = Transform(translation: self.position + [0, 0.1, 0])
        let floatDown = Transform(translation: self.position - [0, 0.1, 0])
        
        // Animate up
        self.move(to: floatUp, relativeTo: nil, duration: 2.0)
        
        // Continue floating
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if self.position.y > self.position.y {
                self.move(to: floatDown, relativeTo: nil, duration: 2.0)
            } else {
                self.move(to: floatUp, relativeTo: nil, duration: 2.0)
            }
        }
    }
}

enum EchoAnimation {
    case idle
    case floating
    case gesturing
    case demonstrating
}
