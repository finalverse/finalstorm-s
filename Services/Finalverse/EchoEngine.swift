//
//  Services/Finalverse/EchoEngine.swift
//  FinalStorm-S
//
//  Manages the First Echoes (Lumi, KAI, Terra, Ignis) and other AI-driven NPCs
//  This service coordinates Echo behavior, interactions, and teaching sequences
//

import Foundation
import RealityKit
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
class EchoEngine: ObservableObject {
    // MARK: - Properties
    @Published var activeEchoes: [EchoEntityService] = []
    @Published var echoStates: [UUID: EchoState] = [:]
    
    private let networkClient: FinalverseNetworkClient
    private let aiOrchestra: AIOrchestra
    private let behaviorSystem: BehaviorSystem
    private var updateCancellable: AnyCancellable?
    
    // The First Echoes
    private var lumi: EchoEntityService?
    private var kai: EchoEntityService?
    private var terra: EchoEntityService?
    private var ignis: EchoEntityService?
    
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
            primaryColor: createPlatformColor(red: 1.0, green: 0.9, blue: 0.0)
        )
        
        // Create KAI - Echo of Knowledge and Understanding
        kai = await createFirstEcho(
            type: .kai,
            name: "KAI",
            appearance: .kaiAppearance,
            personality: .logical,
            primaryColor: createPlatformColor(red: 0.0, green: 0.5, blue: 1.0)
        )
        
        // Create Terra - Echo of Resilience and Growth
        terra = await createFirstEcho(
            type: .terra,
            name: "Terra",
            appearance: .terraAppearance,
            personality: .nurturing,
            primaryColor: createPlatformColor(red: 0.0, green: 0.8, blue: 0.0)
        )
        
        // Create Ignis - Echo of Courage and Creation
        ignis = await createFirstEcho(
            type: .ignis,
            name: "Ignis",
            appearance: .ignisAppearance,
            personality: .passionate,
            primaryColor: createPlatformColor(red: 1.0, green: 0.6, blue: 0.0)
        )
    }
    
    private func createFirstEcho(
        type: EchoType,
        name: String,
        appearance: EchoAppearance,
        personality: PersonalityType,
        primaryColor: CodableColor
    ) async -> EchoEntityService {
        let echo = EchoEntityService(type: type, name: name)
        
        // Set appearance
        await echo.setAppearance(appearance)
        
        // Initialize components
        echo.echoComponent = EchoComponent(
            type: type,
            personality: personality,
            primaryColor: primaryColor
        )
        
        echo.behaviorComponent = AIBehaviorComponent(
            behaviorTree: createBehaviorTree(for: type)
        )
        
        echo.dialogueComponent = DialogueComponent(
            voiceProfile: type.voiceProfile
        )
        
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
        await echo.addVisualEffect(appearanceEffect)
        
        // Animate to position
        await echo.animateTo(
            position: location,
            scale: SIMD3<Float>(1, 1, 1),
            duration: 2.0
        )
        
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
        
        do {
            let dialogue = try await aiOrchestra.generateDialogue(context: context)
            
            // Play dialogue with appropriate emotion
            await echo.speak(dialogue)
            
            return dialogue.text
        } catch {
            print("Failed to generate dialogue: \(error)")
            return nil
        }
    }
    
    // MARK: - Echo Interactions
    func interactWithEcho(_ echo: EchoEntityService, interaction: InteractionType) async {
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
        default:
            break
        }
    }
    
    private func handleConversation(with echo: EchoEntityService) async {
        // Update mood based on conversation
        if let component = echo.echoComponent {
            let newMood = component.personality.respondToInteraction()
            echoStates[echo.id]?.mood = newMood
            
            // Generate and play contextual dialogue
            let dialogue = await generateContextualDialogue(for: echo, mood: newMood)
            await echo.speak(dialogue)
        }
    }
    
    private func offerQuest(from echo: EchoEntityService) async {
        // Generate quest specific to the Echo type
        let questParameters = QuestParameters(
            questType: echo.echoComponent?.type.questType ?? "exploration",
            difficulty: 1,
            location: "Current Area",
            questGiver: echo.name,
            suggestedRewards: nil
        )
        
        do {
            let quest = try await aiOrchestra.generateQuest(parameters: questParameters)
            
            // Present quest to player
            await presentQuest(quest, from: echo)
        } catch {
            print("Failed to generate quest: \(error)")
        }
    }
    
    private func teachMelody(from echo: EchoEntityService) async {
        guard let echoComponent = echo.echoComponent else { return }
        
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
    
    private func toggleCompanion(_ echo: EchoEntityService) async {
        // Toggle companion mode for the Echo
        if let state = echoStates[echo.id] {
            if state.companionTarget != nil {
                // Stop being companion
                echoStates[echo.id]?.companionTarget = nil
                echoStates[echo.id]?.activity = .idle
                
                let dialogue = createFarewellDialogue(for: echo.echoComponent?.type ?? .lumi)
                await echo.speak(dialogue)
            } else {
                // Start being companion
                if let playerAvatar = getAvatarSystem()?.localAvatar {
                    echoStates[echo.id]?.companionTarget = playerAvatar.id
                    echoStates[echo.id]?.activity = .moving
                    
                    let dialogue = createCompanionDialogue(for: echo.echoComponent?.type ?? .lumi)
                    await echo.speak(dialogue)
                }
            }
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
                    ActionNode { echo in await self.handleLumiHelp(echo) },
                    ActionNode { echo in await self.handleLumiEncouragement(echo) }
                ]),
                ActionNode { echo in await self.handleLumiWander(echo) }
            ])
            
        case .kai:
            // KAI analyzes and provides information
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.playerHasQuestion },
                    ActionNode { echo in await self.handleKaiAnalysis(echo) }
                ]),
                ActionNode { echo in await self.handleKaiStudy(echo) }
            ])
            
        case .terra:
            // Terra nurtures and heals
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.nearbyEntitiesDamaged },
                    ActionNode { echo in await self.handleTerraHealing(echo) }
                ]),
                ActionNode { echo in await self.handleTerraNurture(echo) }
            ])
            
        case .ignis:
            // Ignis inspires and protects
            tree.root = SelectorNode(children: [
                SequenceNode(children: [
                    ConditionNode { state in state.threatDetected },
                    ActionNode { echo in await self.handleIgnisDefense(echo) }
                ]),
                ActionNode { echo in await self.handleIgnisRally(echo) }
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
                  let behavior = echo.behaviorComponent else { continue }
            
            // Execute behavior tree
            await behavior.behaviorTree.execute(echo: echo, state: state)
            
            // Update animations based on state
            updateEchoAnimation(echo, state: state)
        }
    }
    
    // MARK: - Visual Effects
    private func createAppearanceEffect(for type: EchoType) -> VisualEffect {
        let effect = VisualEffect()
        
        var particleConfig = ParticleConfiguration()
        particleConfig.birthRate = 200
        particleConfig.emitterShape = .sphere
        particleConfig.lifeSpan = 1.0
        
        // Customize per Echo
        switch type {
        case .lumi:
            particleConfig.color = createColorEvolution(
                start: CodableColor(red: 1.0, green: 0.9, blue: 0.0),
                end: CodableColor(red: 1.0, green: 1.0, blue: 1.0)
            )
            particleConfig.size = 0.02
            
        case .kai:
            particleConfig.color = createColorEvolution(
                start: CodableColor(red: 0.0, green: 0.5, blue: 1.0),
                end: CodableColor(red: 0.0, green: 1.0, blue: 1.0)
            )
            particleConfig.size = 0.01
            particleConfig.angularSpeed = 360
            
        case .terra:
            particleConfig.color = createColorEvolution(
                start: CodableColor(red: 0.0, green: 0.8, blue: 0.0),
                end: CodableColor(red: 0.4, green: 0.2, blue: 0.0)
            )
            particleConfig.size = 0.03
            
        case .ignis:
            particleConfig.color = createColorEvolution(
                start: CodableColor(red: 1.0, green: 0.6, blue: 0.0),
                end: CodableColor(red: 1.0, green: 0.0, blue: 0.0)
            )
            particleConfig.size = 0.04
        }
        
        effect.particleConfig = particleConfig
        return effect
    }
    
    // MARK: - Helper Methods
    private func getEcho(type: EchoType) -> EchoEntityService? {
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
    
    private func updateEchoAnimation(_ echo: EchoEntityService, state: EchoState) {
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
    
    private func playEchoGreeting(_ echo: EchoEntityService) async {
        let greetingText: String
        switch echo.echoComponent?.type {
        case .lumi:
            greetingText = "Hello! I'm Lumi! The light guides us forward together!"
        case .kai:
            greetingText = "Greetings. I am KAI. I'm here to help you understand the Song's mysteries."
        case .terra:
            greetingText = "Welcome, child of the Song. I am Terra, nurturer of all that grows."
        case .ignis:
            greetingText = "I am Ignis! Together we shall forge a path through any challenge!"
        default:
            greetingText = "Greetings, Songweaver."
        }
        
        let dialogue = Dialogue(
            text: greetingText,
            emotion: .happy,
            duration: 3.0,
            audioURL: nil
        )
        
        await echo.speak(dialogue)
    }
    
    private func generateContextualDialogue(for echo: EchoEntityService, mood: EchoState.Mood) async -> Dialogue {
        // Generate dialogue based on Echo type and mood
        let text: String
        let emotion: Emotion
        
        switch (echo.echoComponent?.type, mood) {
        case (.lumi, .happy):
            text = "Isn't this wonderful? I can feel the harmony growing stronger!"
            emotion = .happy
        case (.lumi, .concerned):
            text = "Don't worry, friend. The Song will show us the way."
            emotion = .concerned
        case (.kai, .neutral):
            text = "Interesting. The harmonic patterns here suggest ancient influences."
            emotion = .neutral
        case (.terra, .concerned):
            text = "I sense disturbance in the natural flow. We must restore balance."
            emotion = .concerned
        case (.ignis, .excited):
            text = "The fire in your heart burns bright! Let's channel that energy!"
            emotion = .excited
        default:
            text = "The Song flows through all things, connecting us in harmony."
            emotion = .neutral
        }
        
        return Dialogue(
            text: text,
            emotion: emotion,
            duration: 3.0,
            audioURL: nil
        )
    }
    
    private func performTeachingSequence(echo: EchoEntityService, melody: Melody) async {
        // Create visual representation of melody
        let melodyVisual = createMelodyVisualization(melody)
        await echo.addVisualEffect(melodyVisual)
        
        // Demonstrate melody pattern
        await demonstrateMelodyPattern(echo, melody: melody)
        
        // Teaching dialogue
        let teachingText = "Focus on the harmony within. Feel how the melody flows from your heart to the world."
        let dialogue = Dialogue(
            text: teachingText,
            emotion: .neutral,
            duration: 4.0,
            audioURL: nil
        )
        await echo.speak(dialogue)
        
        // Cleanup
        await echo.removeVisualEffect(melodyVisual)
    }
    
    private func createMelodyVisualization(_ melody: Melody) -> VisualEffect {
        let visual = VisualEffect()
        visual.visualType = .melodyNotes
        visual.primaryColor = melody.harmonyColor
        visual.duration = 5.0
        return visual
    }
    
    private func demonstrateMelodyPattern(_ echo: EchoEntityService, melody: Melody) async {
        // Play melody audio pattern with visual cues
        let notes = generateMelodyNotes(for: melody.type)
        
        for note in notes {
            // Visual pulse
            await echo.pulseEffect()
            
            // Play note sound (would implement with spatial audio)
            await playNote(frequency: note.frequency, duration: note.duration)
            
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
        default:
            return [(440, 0.5)]
        }
    }
    
    private func playNote(frequency: Float, duration: TimeInterval) async {
        // Generate and play spatial audio tone
        // Implementation would use platform-specific audio APIs
        print("Playing note at \(frequency) Hz for \(duration) seconds")
    }
    
    private func presentQuest(_ quest: Quest, from echo: EchoEntityService) async {
        let questText = "I have a task that might interest you: \(quest.title). \(quest.description)"
        let dialogue = Dialogue(
            text: questText,
            emotion: .neutral,
            duration: 6.0,
            audioURL: nil
        )
        await echo.speak(dialogue)
    }
    
    private func createCompanionDialogue(for type: EchoType) -> Dialogue {
        let text: String
        switch type {
        case .lumi:
            text = "Adventure together! I'll light the way!"
        case .kai:
            text = "I shall accompany you and provide analysis as needed."
        case .terra:
            text = "I will journey with you, tending to our needs along the path."
        case .ignis:
            text = "Together we are stronger! Let's forge ahead!"
        }
        
        return Dialogue(
            text: text,
            emotion: .happy,
            duration: 3.0,
            audioURL: nil
        )
    }
    
    private func createFarewellDialogue(for type: EchoType) -> Dialogue {
        let text: String
        switch type {
        case .lumi:
            text = "Until we meet again, may the light guide your steps!"
        case .kai:
            text = "Farewell. Remember what you have learned."
        case .terra:
            text = "May you grow strong in all your journeys."
        case .ignis:
            text = "Keep the fire burning bright until we meet again!"
        }
        
        return Dialogue(
            text: text,
            emotion: .neutral,
            duration: 3.0,
            audioURL: nil
        )
    }
    
    // MARK: - Behavior Action Handlers
    private func handleLumiHelp(_ echo: EchoEntityService) async {
        // Lumi-specific help behavior
        await echo.moveToNearestEntity(filter: .needsHelp)
    }
    
    private func handleLumiEncouragement(_ echo: EchoEntityService) async {
        // Lumi offers encouragement
        let dialogue = Dialogue(
            text: "Don't lose hope! The Song still flows through you.",
            emotion: .happy,
            duration: 3.0,
            audioURL: nil
        )
        await echo.speak(dialogue)
    }
    
    private func handleLumiWander(_ echo: EchoEntityService) async {
        // Lumi wanders playfully
        await echo.wanderPlayfully()
    }
    
    private func handleKaiAnalysis(_ echo: EchoEntityService) async {
        // KAI provides analysis
        let dialogue = Dialogue(
            text: "My analysis indicates a 87.3% probability of harmony disruption in this sector.",
            emotion: .neutral,
            duration: 4.0,
            audioURL: nil
        )
        await echo.speak(dialogue)
    }
    
    private func handleKaiStudy(_ echo: EchoEntityService) async {
        // KAI studies environment
        await echo.studyEnvironment()
    }
    
    private func handleTerraHealing(_ echo: EchoEntityService) async {
        // Terra heals nearby entities
        await echo.healNearbyEntities()
    }
    
    private func handleTerraNurture(_ echo: EchoEntityService) async {
        // Terra tends to nature
        await echo.tendToNature()
    }
    
    private func handleIgnisDefense(_ echo: EchoEntityService) async {
        // Ignis defends area
        await echo.defendArea()
    }
    
    private func handleIgnisRally(_ echo: EchoEntityService) async {
        // Ignis rallies allies
        await echo.rallyAllies()
    }
    
    // MARK: - Utility Methods
    private func createPlatformColor(red: Float, green: Float, blue: Float, alpha: Float = 1.0) -> CodableColor {
        return CodableColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    private func createColorEvolution(start: CodableColor, end: CodableColor) -> ColorEvolution {
        return ColorEvolution(start: start, end: end)
    }
}

// MARK: - Supporting Types
enum EchoType: String, CaseIterable {
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
    
    var questType: String {
        switch self {
        case .lumi:
            return "discovery"
        case .kai:
            return "knowledge"
        case .terra:
            return "restoration"
        case .ignis:
            return "action"
        }
    }
    
    var primaryColor: CodableColor {
        switch self {
        case .lumi:
            return CodableColor(red: 1.0, green: 0.9, blue: 0.0)
        case .kai:
            return CodableColor(red: 0.0, green: 0.5, blue: 1.0)
        case .terra:
            return CodableColor(red: 0.0, green: 0.8, blue: 0.0)
        case .ignis:
            return CodableColor(red: 1.0, green: 0.6, blue: 0.0)
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
    
    // Behavior state properties
    var nearbyEntitiesNeedHelp: Bool = false
    var playerHasQuestion: Bool = false
    var nearbyEntitiesDamaged: Bool = false
    var threatDetected: Bool = false
}

struct EchoComponent {
    let type: EchoType
    let personality: PersonalityType
    let primaryColor: CodableColor
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

// MARK: - Echo Entity Service Class
class EchoEntityService {
    let id = UUID()
    let echoType: EchoType
    let name: String
    
    // Components (stored as properties instead of Entity components for service layer)
    var echoComponent: EchoComponent?
    var behaviorComponent: AIBehaviorComponent?
    var dialogueComponent: DialogueComponent?
    
    // Transform properties
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    
    // State
    private var currentVisualEffects: [VisualEffect] = []
    private var currentAnimation: EchoAnimation = .idle
    
    init(type: EchoType, name: String) {
        self.echoType = type
        self.name = name
    }
    
    func setAppearance(_ appearance: EchoAppearance) async {
        // Load echo-specific appearance
        // In a full implementation, this would configure the visual representation
        print("Setting appearance for \(name) with mesh: \(appearance.meshName)")
    }
    
    func speak(_ dialogue: Dialogue) async {
        // Play dialogue with speech synthesis
        print("\(name): \(dialogue.text)")
        
        // Wait for speech duration
        try? await Task.sleep(nanoseconds: UInt64(dialogue.duration * 1_000_000_000))
    }
    
    func playAnimation(_ animation: EchoAnimation) {
        currentAnimation = animation
        print("\(name) playing animation: \(animation)")
    }
    
    func addVisualEffect(_ effect: VisualEffect) async {
           currentVisualEffects.append(effect)
           print("\(name) adding visual effect: \(effect.visualType)")
       }
       
       func removeVisualEffect(_ effect: VisualEffect) async {
           if let index = currentVisualEffects.firstIndex(where: { $0.id == effect.id }) {
               currentVisualEffects.remove(at: index)
               print("\(name) removing visual effect: \(effect.visualType)")
           }
       }
       
       func animateTo(position: SIMD3<Float>, scale: SIMD3<Float>, duration: TimeInterval) async {
           let startPosition = self.position
           let startScale = self.scale
           
           print("\(name) animating to position: \(position), scale: \(scale) over \(duration) seconds")
           
           // Simulate animation over time
           let steps = 10
           let stepDuration = duration / Double(steps)
           
           for i in 0...steps {
               let progress = Float(i) / Float(steps)
               
               // Interpolate position and scale
               self.position = simd_mix(startPosition, position, progress)
               self.scale = simd_mix(startScale, scale, progress)
               
               if i < steps {
                   try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
               }
           }
       }
       
       func pulseEffect() async {
           let originalScale = scale
           let pulseScale = originalScale * 1.2
           
           // Quick pulse animation
           await animateTo(position: position, scale: pulseScale, duration: 0.1)
           await animateTo(position: position, scale: originalScale, duration: 0.1)
       }
       
       func moveToNearestEntity(filter: EntityFilter) async {
           // Simulate finding and moving to nearest entity
           let targetPosition = SIMD3<Float>(
               position.x + Float.random(in: -5...5),
               position.y,
               position.z + Float.random(in: -5...5)
           )
           
           print("\(name) moving to nearest entity with filter: \(filter)")
           await animateTo(position: targetPosition, scale: scale, duration: 2.0)
       }
       
       func wanderPlayfully() async {
           // Random playful movement
           let wanderPosition = SIMD3<Float>(
               position.x + Float.random(in: -3...3),
               position.y,
               position.z + Float.random(in: -3...3)
           )
           
           print("\(name) wandering playfully")
           await animateTo(position: wanderPosition, scale: scale, duration: 3.0)
       }
       
       func studyEnvironment() async {
           print("\(name) studying environment")
           playAnimation(.gesturing)
           
           // Simulate studying time
           try? await Task.sleep(nanoseconds: 2_000_000_000)
       }
       
       func healNearbyEntities() async {
           print("\(name) healing nearby entities")
           playAnimation(.gesturing)
           
           // Create healing effect
           let healingEffect = VisualEffect()
           healingEffect.visualType = .healingAura
           healingEffect.primaryColor = CodableColor(red: 0.0, green: 1.0, blue: 0.0)
           healingEffect.duration = 3.0
           
           await addVisualEffect(healingEffect)
           try? await Task.sleep(nanoseconds: 3_000_000_000)
           await removeVisualEffect(healingEffect)
       }
       
       func tendToNature() async {
           print("\(name) tending to nature")
           playAnimation(.gesturing)
           
           // Create growth effect
           let growthEffect = VisualEffect()
           growthEffect.visualType = .plantGrowth
           growthEffect.primaryColor = CodableColor(red: 0.0, green: 0.8, blue: 0.0)
           growthEffect.duration = 5.0
           
           await addVisualEffect(growthEffect)
           try? await Task.sleep(nanoseconds: 5_000_000_000)
           await removeVisualEffect(growthEffect)
       }
       
       func defendArea() async {
           print("\(name) defending area")
           playAnimation(.gesturing)
           
           // Create fire shield effect
           let shieldEffect = VisualEffect()
           shieldEffect.visualType = .fireShield
           shieldEffect.primaryColor = CodableColor(red: 1.0, green: 0.6, blue: 0.0)
           shieldEffect.duration = 5.0
           
           await addVisualEffect(shieldEffect)
           try? await Task.sleep(nanoseconds: 5_000_000_000)
           await removeVisualEffect(shieldEffect)
       }
       
       func rallyAllies() async {
           print("\(name) rallying allies")
           playAnimation(.gesturing)
           
           // Create inspiration effect
           let rallyEffect = VisualEffect()
           rallyEffect.visualType = .inspirationAura
           rallyEffect.primaryColor = CodableColor(red: 1.0, green: 0.8, blue: 0.0)
           rallyEffect.duration = 4.0
           
           await addVisualEffect(rallyEffect)
           try? await Task.sleep(nanoseconds: 4_000_000_000)
           await removeVisualEffect(rallyEffect)
       }
    }

    // MARK: - Behavior Tree Components
    struct AIBehaviorComponent {
       let behaviorTree: BehaviorTree
    }

    struct DialogueComponent {
       let voiceProfile: VoiceProfile
    }

    // MARK: - Behavior Tree System
    class BehaviorSystem {
       // Behavior management functionality
       func processEchoBehavior(_ echo: EchoEntityService, state: EchoState) async {
           // Process Echo behavior based on current state
           print("Processing behavior for \(echo.name) in state: \(state.activity)")
       }
    }

    class BehaviorTree {
       var root: BehaviorNode?
       
       func execute(echo: EchoEntityService, state: EchoState) async {
           await root?.execute(echo: echo, state: state)
       }
    }

    protocol BehaviorNode {
       func execute(echo: EchoEntityService, state: EchoState) async -> Bool
    }

    class SelectorNode: BehaviorNode {
       let children: [BehaviorNode]
       
       init(children: [BehaviorNode]) {
           self.children = children
       }
       
       func execute(echo: EchoEntityService, state: EchoState) async -> Bool {
           for child in children {
               if await child.execute(echo: echo, state: state) {
                   return true
               }
           }
           return false
       }
    }

    class SequenceNode: BehaviorNode {
       let children: [BehaviorNode]
       
       init(children: [BehaviorNode]) {
           self.children = children
       }
       
       func execute(echo: EchoEntityService, state: EchoState) async -> Bool {
           for child in children {
               if !await child.execute(echo: echo, state: state) {
                   return false
               }
           }
           return true
       }
    }

    class ConditionNode: BehaviorNode {
       let condition: (EchoState) -> Bool
       
       init(condition: @escaping (EchoState) -> Bool) {
           self.condition = condition
       }
       
       func execute(echo: EchoEntityService, state: EchoState) async -> Bool {
           return condition(state)
       }
    }

    class ActionNode: BehaviorNode {
       let action: (EchoEntityService) async -> Void
       
       init(action: @escaping (EchoEntityService) async -> Void) {
           self.action = action
       }
       
       func execute(echo: EchoEntityService, state: EchoState) async -> Bool {
           await action(echo)
           return true
       }
    }

    // MARK: - Visual Effects System
    class VisualEffect {
       let id = UUID()
       var visualType: VisualEffectType = .particles
       var primaryColor: CodableColor = CodableColor(red: 1.0, green: 1.0, blue: 1.0)
       var duration: TimeInterval = 1.0
       var particleConfig: ParticleConfiguration?
       
       init() {}
    }

    enum VisualEffectType {
       case particles
       case melodyNotes
       case healingAura
       case plantGrowth
       case fireShield
       case inspirationAura
       case scanBeam
       case hologram
    }

    struct ParticleConfiguration {
       var birthRate: Float = 100
       var emitterShape: EmitterShape = .sphere
       var lifeSpan: TimeInterval = 1.0
       var size: Float = 0.01
       var angularSpeed: Float = 0
       var color: ColorEvolution = ColorEvolution(
           start: CodableColor(red: 1.0, green: 1.0, blue: 1.0),
           end: CodableColor(red: 1.0, green: 1.0, blue: 1.0)
       )
    }

    enum EmitterShape {
       case sphere
       case box
       case cone
       case torus
    }

    struct ColorEvolution {
       let start: CodableColor
       let end: CodableColor
    }

    enum EchoAnimation {
       case idle
       case floating
       case gesturing
       case demonstrating
    }

    enum EntityFilter {
       case needsHelp
       case damaged
       case friendly
       case hostile
    }

    // MARK: - Supporting Types from Other Services
    struct Dialogue {
       let text: String
       let emotion: Emotion
       let duration: TimeInterval
       let audioURL: URL?
    }

    enum Emotion {
       case happy
       case sad
       case angry
       case fearful
       case concerned
       case excited
       case neutral
    }

    struct QuestParameters {
       let questType: String
       let difficulty: Int
       let location: String
       let questGiver: String
       let suggestedRewards: [QuestReward]?
    }

    // Placeholder types for external dependencies
    struct PlayerState {
       var currentLocation: String = "Unknown"
       var harmonyLevel: Float = 1.0
    }

    struct WorldState {
       var globalHarmony: Float = 1.0
       var activeEvents: [String] = []
    }

    // MARK: - DialogueContext from AIOrchestra
    struct DialogueContext {
       let speaker: EchoType
       let topic: GuidanceTopic
       let playerState: PlayerState
       let worldState: WorldState
       let conversationId: UUID?
       let emotion: Emotion?
       
       init(speaker: EchoType, topic: GuidanceTopic, playerState: PlayerState, worldState: WorldState, conversationId: UUID? = nil, emotion: Emotion? = nil) {
           self.speaker = speaker
           self.topic = topic
           self.playerState = playerState
           self.worldState = worldState
           self.conversationId = conversationId
           self.emotion = emotion
       }
    }
