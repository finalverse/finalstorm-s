//
//  Core/Components/SharedTypes.swift
//  FinalStorm
//
//  Shared types used across multiple services (Non-audio types)
//  Audio-related types have been moved to Services/Audio/AudioTypes.swift
//

import Foundation
import simd
import RealityKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Dialogue System Types
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

struct Dialogue {
    let text: String
    let emotion: Emotion
    let duration: TimeInterval
    let audioURL: URL?
}

enum Emotion: String, CaseIterable, Codable {
    case happy = "happy"
    case sad = "sad"
    case angry = "angry"
    case fearful = "fearful"
    case concerned = "concerned"
    case excited = "excited"
    case neutral = "neutral"
    
    var intensity: Float {
        switch self {
        case .excited, .angry:
            return 1.0
        case .happy, .fearful:
            return 0.8
        case .concerned, .sad:
            return 0.6
        case .neutral:
            return 0.5
        }
    }
}

// MARK: - Echo System Types
enum EchoType: String, CaseIterable, Codable {
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
    
    var personality: PersonalityType {
        switch self {
        case .lumi:
            return .hopeful
        case .kai:
            return .logical
        case .terra:
            return .nurturing
        case .ignis:
            return .passionate
        }
    }
}

struct VoiceProfile {
    let pitch: Float
    let speed: Float
    let timbre: VoiceTimbre
    
    enum VoiceTimbre: String, CaseIterable {
        case bright = "bright"
        case digital = "digital"
        case warm = "warm"
        case bold = "bold"
    }
}

enum PersonalityType: String, CaseIterable, Codable {
    case hopeful = "hopeful"
    case logical = "logical"
    case nurturing = "nurturing"
    case passionate = "passionate"
    
    func respondToInteraction() -> Emotion {
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
    
    var defaultDialogueStyle: DialogueStyle {
        switch self {
        case .hopeful:
            return DialogueStyle(enthusiasm: 0.8, formality: 0.3, empathy: 0.9)
        case .logical:
            return DialogueStyle(enthusiasm: 0.4, formality: 0.8, empathy: 0.5)
        case .nurturing:
            return DialogueStyle(enthusiasm: 0.6, formality: 0.4, empathy: 1.0)
        case .passionate:
            return DialogueStyle(enthusiasm: 1.0, formality: 0.2, empathy: 0.7)
        }
    }
}

struct DialogueStyle {
    let enthusiasm: Float
    let formality: Float
    let empathy: Float
}

enum GuidanceTopic: String, CaseIterable, Codable {
    case firstSteps = "firstSteps"
    case songweaving = "songweaving"
    case exploration = "exploration"
    case combat = "combat"
    case lore = "lore"
    case quests = "quests"
    case harmony = "harmony"
    case corruption = "corruption"
    
    var priority: Int {
        switch self {
        case .firstSteps:
            return 100
        case .songweaving:
            return 90
        case .combat:
            return 80
        case .quests:
            return 70
        case .exploration:
            return 60
        case .harmony:
            return 50
        case .corruption:
            return 40
        case .lore:
            return 30
        }
    }
}

// MARK: - Quest System Types
struct QuestParameters {
    let questType: String
    let difficulty: Int
    let location: String
    let questGiver: String
    let suggestedRewards: [QuestReward]?
    let requiredLevel: Int
    let estimatedDuration: TimeInterval
    
    init(questType: String, difficulty: Int, location: String, questGiver: String, suggestedRewards: [QuestReward]? = nil, requiredLevel: Int = 1, estimatedDuration: TimeInterval = 600) {
        self.questType = questType
        self.difficulty = difficulty
        self.location = location
        self.questGiver = questGiver
        self.suggestedRewards = suggestedRewards
        self.requiredLevel = requiredLevel
        self.estimatedDuration = estimatedDuration
    }
}

struct QuestReward: Codable {
    let type: RewardType
    let amount: Int
    let itemId: String?
    
    enum RewardType: String, CaseIterable, Codable {
        case experience = "experience"
        case resonance = "resonance"
        case item = "item"
        case melody = "melody"
        case harmony = "harmony"
    }
}

// MARK: - Conversation Management
class Conversation: ObservableObject {
    let id: UUID
    @Published var dialogues: [Dialogue] = []
    @Published var participants: [String] = []
    @Published var currentTopic: GuidanceTopic?
    @Published var isActive: Bool = false
    
    init(id: UUID = UUID()) {
        self.id = id
    }
    
    func addDialogue(_ dialogue: Dialogue) {
        dialogues.append(dialogue)
    }
    
    func addParticipant(_ participant: String) {
        if !participants.contains(participant) {
            participants.append(participant)
        }
    }
    
    func setTopic(_ topic: GuidanceTopic) {
        currentTopic = topic
    }
    
    func startConversation() {
        isActive = true
    }
    
    func endConversation() {
        isActive = false
    }
}

// MARK: - NPC System Types
struct NPCTemplate {
    let role: String
    let location: String
    let background: String
    let level: Int
    let faction: String?
    
    init(role: String, location: String, background: String, level: Int = 1, faction: String? = nil) {
        self.role = role
        self.location = location
        self.background = background
        self.level = level
        self.faction = faction
    }
}

struct NPCPersonality {
    let template: NPCTemplate
    var traits: [String] = []
    var quirks: [String] = []
    var speechPattern: String?
    var songView: String?
    var relationshipToPlayer: RelationshipType = .neutral
    
    enum RelationshipType: String, CaseIterable {
        case hostile = "hostile"
        case unfriendly = "unfriendly"
        case neutral = "neutral"
        case friendly = "friendly"
        case allied = "allied"
    }
}

// MARK: - World State Types
struct PlayerState {
    var currentLocation: String = "Unknown"
    var harmonyLevel: Float = 1.0
    var resonanceLevel: ResonanceLevel = .novice
    var knownMelodies: [String] = []
    var completedQuests: [String] = []
    var reputation: [String: Float] = [:]
    
    mutating func updateHarmony(_ delta: Float) {
        harmonyLevel = max(0.0, min(2.0, harmonyLevel + delta))
    }
    
    mutating func learnMelody(_ melodyId: String) {
        if !knownMelodies.contains(melodyId) {
            knownMelodies.append(melodyId)
        }
    }
    
    mutating func completeQuest(_ questId: String) {
        if !completedQuests.contains(questId) {
            completedQuests.append(questId)
        }
    }
}

struct WorldState {
    var globalHarmony: Float = 1.0
    var activeEvents: [String] = []
    var corruptionLevel: Float = 0.0
    var regionStates: [String: RegionState] = [:]
    var weatherConditions: [String: String] = [:]
    
    mutating func updateGlobalHarmony(_ delta: Float) {
        globalHarmony = max(0.0, min(2.0, globalHarmony + delta))
    }
    
    mutating func addEvent(_ eventId: String) {
        if !activeEvents.contains(eventId) {
            activeEvents.append(eventId)
        }
    }
    
    mutating func removeEvent(_ eventId: String) {
        activeEvents.removeAll { $0 == eventId }
    }
}

struct RegionState {
    let regionId: String
    var harmonyLevel: Float
    var population: Int
    var stability: Float
    var lastUpdate: Date
    
    init(regionId: String, harmonyLevel: Float = 1.0, population: Int = 0, stability: Float = 1.0) {
        self.regionId = regionId
        self.harmonyLevel = harmonyLevel
        self.population = population
        self.stability = stability
        self.lastUpdate = Date()
    }
}

// MARK: - LLM Integration Types
struct LLMRequest: Codable {
    let prompt: String
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let context: LLMContext?
    
    init(prompt: String, maxTokens: Int = 150, temperature: Double = 0.7, topP: Double = 0.9, context: LLMContext? = nil) {
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.context = context
    }
}

struct LLMResponse: Codable {
    let text: String
    let tokensUsed: Int
    let confidence: Float?
    let metadata: [String: String]?
}

struct LLMContext: Codable {
    let speaker: EchoType?
    let topic: GuidanceTopic?
    let playerState: String?
    let worldState: String?
    let conversationHistory: [String]?
}

// MARK: - Platform UI Color Extension
extension CodableColor {
    var platformUIColor: CGColor {
        #if canImport(UIKit)
        return UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha)).cgColor
        #elseif canImport(AppKit)
        return NSColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha)).cgColor
        #else
        return CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
        #endif
    }
    
    #if canImport(UIKit)
    var uiColor: UIColor {
        return UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    #elseif canImport(AppKit)
    var nsColor: NSColor {
        return NSColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    #endif
}
