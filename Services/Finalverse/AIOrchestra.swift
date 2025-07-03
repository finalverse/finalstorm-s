//
//  AIOrchestra.swift
//  FinalStorm-S
//
//  Integrates LLM services for dynamic dialogue, quest generation, and narrative
//

import Foundation
import Combine

class AIOrchestra: ObservableObject {
    // MARK: - Properties
    @Published var isConnected = false
    @Published var activeConversations: [UUID: Conversation] = [:]
    
    private let networkClient: FinalverseNetworkClient
    private let promptEngine: PromptEngine
    private var llmEndpoint: URL?
    
    init() {
        self.networkClient = FinalverseNetworkClient(service: .aiOrchestra)
        self.promptEngine = PromptEngine()
    }
    
    // MARK: - Initialization
    func initialize() async {
        do {
            try await networkClient.connect()
            isConnected = true
            
            // Get LLM endpoint from service
            llmEndpoint = try await fetchLLMEndpoint()
        } catch {
            print("Failed to initialize AI Orchestra: \(error)")
        }
    }
    
    // MARK: - Dialogue Generation
    func generateDialogue(context: DialogueContext) async -> Dialogue {
        let prompt = promptEngine.createDialoguePrompt(context: context)
        
        do {
            let response = try await requestLLM(prompt: prompt, maxTokens: 150)
            
            // Parse response and create dialogue
            let dialogue = Dialogue(
                text: response.text,
                emotion: detectEmotion(from: response.text),
                duration: calculateDuration(for: response.text),
                audioURL: nil // Audio generation would happen here
            )
            
            // Cache conversation if needed
            if let conversationId = context.conversationId {
                updateConversation(conversationId, with: dialogue)
            }
            
            return dialogue
        } catch {
            // Return fallback dialogue
            return Dialogue(
                text: "I sense something is amiss with the Song...",
                emotion: .concerned,
                duration: 3.0,
                audioURL: nil
            )
        }
    }
    
    // MARK: - Quest Generation
    func generateQuest(parameters: QuestParameters) async -> Quest? {
        let prompt = promptEngine.createQuestPrompt(parameters: parameters)
        
        do {
            let response = try await requestLLM(prompt: prompt, maxTokens: 500)
            
            // Parse quest structure from response
            return parseQuest(from: response.text, parameters: parameters)
        } catch {
            print("Failed to generate quest: \(error)")
            return nil
        }
    }
    
    // MARK: - Dynamic Story Events
    func generateStoryEvent(worldState: WorldState, playerHistory: PlayerHistory) async -> StoryEvent? {
        let prompt = promptEngine.createStoryEventPrompt(
            worldState: worldState,
            playerHistory: playerHistory
        )
        
        do {
            let response = try await requestLLM(prompt: prompt, maxTokens: 300)
            
            return parseStoryEvent(from: response.text)
        } catch {
            return nil
        }
    }
    
    // MARK: - NPC Personality
    func generateNPCPersonality(baseTemplate: NPCTemplate) async -> NPCPersonality {
        let prompt = promptEngine.createPersonalityPrompt(template: baseTemplate)
        
        do {
            let response = try await requestLLM(prompt: prompt, maxTokens: 200)
            
            return parsePersonality(from: response.text, template: baseTemplate)
        } catch {
            // Return default personality
            return NPCPersonality(template: baseTemplate)
        }
    }
    
    // MARK: - LLM Communication
    private func requestLLM(prompt: String, maxTokens: Int) async throws -> LLMResponse {
        guard let endpoint = llmEndpoint else {
            throw AIError.noEndpoint
        }
        
        let request = LLMRequest(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: 0.8,
            topP: 0.9
        )
        
        let response = try await networkClient.request(.generateText(request))
        return response
    }
    
    // MARK: - Parsing Methods
    private func detectEmotion(from text: String) -> Emotion {
        // Simple emotion detection based on keywords
        let lowercased = text.lowercased()
        
        if lowercased.contains("happy") || lowercased.contains("joy") {
            return .happy
        } else if lowercased.contains("sad") || lowercased.contains("sorrow") {
            return .sad
        } else if lowercased.contains("angry") || lowercased.contains("furious") {
            return .angry
        } else if lowercased.contains("afraid") || lowercased.contains("scared") {
            return .fearful
        } else if lowercased.contains("concern") || lowercased.contains("worry") {
            return .concerned
        }
        
        return .neutral
    }
    
    private func calculateDuration(for text: String) -> TimeInterval {
        // Estimate based on word count
        let wordCount = text.split(separator: " ").count
        let wordsPerSecond: Double = 3.0
        return Double(wordCount) / wordsPerSecond + 1.0 // Add buffer
    }
    
    private func parseQuest(from text: String, parameters: QuestParameters) -> Quest? {
        // Parse LLM response into quest structure
        // This would use more sophisticated parsing in production
        
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 3 else { return nil }
        
        return Quest(
            id: UUID(),
            title: lines[0].trimmingCharacters(in: .whitespacesAndNewlines),
            description: lines[1].trimmingCharacters(in: .whitespacesAndNewlines),
            objectives: parseObjectives(from: Array(lines.dropFirst(2))),
            rewards: parameters.suggestedRewards ?? [],
            questGiver: parameters.questGiver,
            location: parameters.location
        )
    }
    
    private func parseObjectives(from lines: [String]) -> [QuestObjective] {
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            
            return QuestObjective(
                id: UUID(),
                description: trimmed,
                isCompleted: false
            )
        }
    }
    
    private func parseStoryEvent(from text: String) -> StoryEvent? {
        // Parse narrative event from LLM response
        return StoryEvent(
            id: UUID(),
            title: "A Shift in the Song",
            description: text,
            triggerConditions: [],
            consequences: []
        )
    }
    
    private func parsePersonality(from text: String, template: NPCTemplate) -> NPCPersonality {
        // Extract personality traits from LLM response
        var personality = NPCPersonality(template: template)
        
        // Parse traits, quirks, speech patterns
        // This would be more sophisticated in production
        
        return personality
    }
    
    // MARK: - Conversation Management
    private func updateConversation(_ id: UUID, with dialogue: Dialogue) {
        if var conversation = activeConversations[id] {
            conversation.addDialogue(dialogue)
            activeConversations[id] = conversation
        } else {
            let conversation = Conversation(id: id)
            conversation.addDialogue(dialogue)
            activeConversations[id] = conversation
        }
    }
    
    // MARK: - Helper Methods
    private func fetchLLMEndpoint() async throws -> URL {
        let response = try await networkClient.request(.getServiceInfo)
        guard let urlString = response.llmEndpoint,
              let url = URL(string: urlString) else {
            throw AIError.invalidEndpoint
        }
        return url
    }
}

// MARK: - Prompt Engine
class PromptEngine {
    func createDialoguePrompt(context: DialogueContext) -> String {
        return """
        You are \(context.speaker.rawValue), one of the First Echoes in Finalverse.
        
        Character traits:
        - Lumi: Childlike, hopeful, encouraging, speaks with wonder
        - KAI: Logical, analytical, helpful, speaks precisely
        - Terra: Nurturing, wise, patient, speaks warmly
        - Ignis: Passionate, brave, inspiring, speaks boldly
        
        Context:
        - Topic: \(context.topic)
        - Player state: \(context.playerState.description)
        - World state: \(context.worldState.description)
        
        Generate a single response that:
        1. Stays in character
        2. Addresses the topic helpfully
        3. Reflects the current world state
        4. Is concise (1-2 sentences)
        
        Response:
        """
    }
    
    func createQuestPrompt(parameters: QuestParameters) -> String {
        return """
        Generate a quest for Finalverse with these parameters:
        - Type: \(parameters.questType)
        - Difficulty: \(parameters.difficulty)
        - Location: \(parameters.location)
        - Quest giver: \(parameters.questGiver)
        
        Format:
        Title: [Quest title]
        Description: [1-2 sentence description]
        Objectives:
        - [Objective 1]
        - [Objective 2]
        - [Optional: Objective 3]
        
        Make it thematically appropriate for a world where music and harmony have magical power.
        """
    }
    
    func createStoryEventPrompt(worldState: WorldState, playerHistory: PlayerHistory) -> String {
        return """
        Generate a dynamic story event for Finalverse.
        
        World state:
        - Harmony level: \(worldState.harmonyLevel)
        - Active threats: \(worldState.activeThreats)
        - Recent events: \(worldState.recentEvents)
        
        Player history:
        - Completed quests: \(playerHistory.completedQuests.count)
        - Resonance level: \(playerHistory.resonanceLevel)
        - Recent actions: \(playerHistory.recentActions)
        
        Create a brief event (2-3 sentences) that:
        1. Reflects the current world state
        2. Provides an opportunity for player engagement
        3. Advances the narrative of harmony vs. silence
        """
    }
    
    func createPersonalityPrompt(template: NPCTemplate) -> String {
        return """
        Create a unique personality for an NPC in Finalverse.
        
        Base template:
        - Role: \(template.role)
        - Location: \(template.location)
        - Background: \(template.background)
        
        Generate:
        1. Two personality traits
        2. One quirk or habit
        3. A speech pattern or catchphrase
        4. Their view on the Song of Creation
        
        Make them memorable but believable within the world.
        """
    }
}

// MARK: - Supporting Types
struct DialogueContext {
    let speaker: EchoType
    let topic: GuidanceTopic
    let playerState: PlayerState
    let worldState: WorldState
    let conversationId: UUID?
    
    init(speaker: EchoType, topic: GuidanceTopic, playerState: PlayerState, worldState: WorldState, conversationId: UUID? = nil) {
        self.speaker = speaker
        self.topic = topic
        self.playerState = playerState
        self.worldState = worldState
        self.conversationId = conversationId
    }
}

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

struct LLMRequest: Codable {
    let prompt: String
    let maxTokens: Int
    let temperature: Double
    let topP: Double
}

struct LLMResponse: Codable {
    let text: String
    let tokensUsed: Int
}

struct Quest: Identifiable {
    let id: UUID
    let title: String
    let description: String
    var objectives: [QuestObjective]
    let rewards: [QuestReward]
    let questGiver: String
    let location: String
}

struct QuestObjective: Identifiable {
    let id: UUID
    let description: String
    var isCompleted: Bool
}

struct QuestReward {
    enum RewardType {
        case resonance(amount: Float)
        case item(id: String)
        case melody(type: MelodyType)
    }
    
    let type: RewardType
}

struct QuestParameters {
    let questType: String
    let difficulty: Int
    let location: String
    let questGiver: String
    let suggestedRewards: [QuestReward]?
}

class Conversation {
    let id: UUID
    var dialogues: [Dialogue] = []
    var participants: [String] = []
    
    init(id: UUID) {
        self.id = id
    }
    
    func addDialogue(_ dialogue: Dialogue) {
        dialogues.append(dialogue)
    }
}

struct NPCTemplate {
    let role: String
    let location: String
    let background: String
}

struct NPCPersonality {
    let template: NPCTemplate
    var traits: [String] = []
    var quirks: [String] = []
    var speechPattern: String?
    var songView: String?
}

struct StoryEvent: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let triggerConditions: [String]
    let consequences: [String]
}

struct PlayerState {
    var health: Float = 1.0
    var resonance: ResonanceLevel = .novice
    var currentMood: Emotion = .neutral
    
    var description: String {
        "Health: \(Int(health * 100))%, Resonance: \(resonance.totalResonance), Mood: \(currentMood)"
    }
}

struct WorldState {
    var harmonyLevel: Float = 1.0
    var activeThreats: [String] = []
    var recentEvents: [String] = []
    
    var description: String {
        "Harmony: \(harmonyLevel), Threats: \(activeThreats.count), Recent events: \(recentEvents.count)"
    }
}

struct PlayerHistory {
    var completedQuests: [UUID] = []
    var resonanceLevel: Float = 0
    var recentActions: [String] = []
}

enum AIError: Error {
    case noEndpoint
    case invalidEndpoint
    case requestFailed
    case parsingFailed
}
