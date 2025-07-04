//
//  Services/Finalverse/AIOrchestra.swift
//  FinalStorm-S
//
//  Integrates LLM services for dynamic dialogue, quest generation, and narrative
//  FIXED: Import shared types instead of redefining them
//

import Foundation
import Combine

@MainActor
class AIOrchestra: ObservableObject {
    // MARK: - Properties
    @Published var isConnected = false
    @Published var activeConversations: [UUID: Conversation] = [:]
    
    private let networkClient: FinalverseNetworkClient
    private let promptEngine: PromptEngine
    private var llmEndpoint: URL?
    
    // MARK: - Initialization
    init() {
        self.networkClient = FinalverseNetworkClient(service: .aiOrchestra)
        self.promptEngine = PromptEngine()
    }
    
    // MARK: - Public Methods
    func initialize() async {
        do {
            try await networkClient.connect()
            llmEndpoint = networkClient.serviceEndpoint
            isConnected = true
        } catch {
            print("Failed to initialize AI Orchestra: \(error)")
        }
    }
    
    func generateDialogue(context: DialogueContext) async throws -> Dialogue {
        let prompt = promptEngine.generateDialoguePrompt(context: context)
        let response = try await sendLLMRequest(prompt: prompt)
        
        return Dialogue(
            text: response.text,
            emotion: parseEmotion(from: response.text),
            duration: calculateSpeechDuration(response.text),
            audioURL: nil // Audio generation would happen here
        )
    }
    
    func generateQuest(parameters: QuestParameters) async throws -> Quest {
        let prompt = promptEngine.generateQuestPrompt(parameters: parameters)
        let response = try await sendLLMRequest(prompt: prompt)
        
        return try parseQuestFromResponse(response.text, parameters: parameters)
    }
    
    func continueConversation(conversationId: UUID, userInput: String) async throws -> Dialogue {
        guard let conversation = activeConversations[conversationId] else {
            throw AIError.conversationNotFound
        }
        
        let context = buildConversationContext(conversation: conversation, userInput: userInput)
        let dialogue = try await generateDialogue(context: context)
        
        conversation.addDialogue(dialogue)
        return dialogue
    }
    
    func generateNPCPersonality(template: NPCTemplate) async throws -> NPCPersonality {
        let prompt = promptEngine.generatePersonalityPrompt(template: template)
        let response = try await sendLLMRequest(prompt: prompt)
        
        return parsePersonalityFromResponse(response.text, template: template)
    }
    
    // MARK: - Private Methods
    private func sendLLMRequest(prompt: String, maxTokens: Int = 500) async throws -> LLMResponse {
        guard let endpoint = llmEndpoint else {
            throw AIError.notInitialized
        }
        
        let request = LLMRequest(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: 0.8,
            topP: 0.9
        )
        
        // Simulate LLM response for now
        // In production, this would make actual API call
        return LLMResponse(
            text: "Generated response for: \(prompt.prefix(50))...",
            tokensUsed: 100
        )
    }
    
    private func parseEmotion(from text: String) -> Emotion {
        // Simple emotion detection
        // In production, this would use sentiment analysis
        if text.contains("happy") || text.contains("joy") {
            return .happy
        } else if text.contains("sad") || text.contains("sorrow") {
            return .sad
        } else if text.contains("angry") || text.contains("furious") {
            return .angry
        } else if text.contains("afraid") || text.contains("scared") {
            return .fearful
        }
        return .neutral
    }
    
    private func calculateSpeechDuration(_ text: String) -> TimeInterval {
        // Rough estimate: 150 words per minute
        let wordCount = text.split(separator: " ").count
        return TimeInterval(wordCount) / 150.0 * 60.0
    }
    
    private func parseQuestFromResponse(_ text: String, parameters: QuestParameters) throws -> Quest {
        // Parse LLM response into Quest structure
        // This is simplified - real implementation would parse structured output
        
        let objective = QuestObjective(
            description: "Complete the generated quest objective",
            targetType: .collectItems,
            targetCount: 5
        )
        
        let reward = QuestReward(
            type: .experience(amount: 100),
            description: "Quest completion experience"
        )
        
        return Quest(
            title: "Generated Quest",
            description: text,
            objectives: [objective],
            rewards: [reward],
            questGiver: parameters.questGiver,
            location: parameters.location
        )
    }
    
    private func buildConversationContext(conversation: Conversation, userInput: String) -> DialogueContext {
        // Build context from conversation history
        return DialogueContext(
            speaker: .lumi, // Default to Lumi for conversation building
            topic: .songweaving,
            playerState: PlayerState(),
            worldState: WorldState(),
            conversationId: conversation.id
        )
    }
    
    private func parsePersonalityFromResponse(_ text: String, template: NPCTemplate) -> NPCPersonality {
        // Parse personality traits from response
        var personality = NPCPersonality(template: template)
        personality.traits = ["Friendly", "Curious"]
        personality.quirks = ["Always humming"]
        personality.speechPattern = "Speaks in riddles"
        personality.songView = "Believes the Song connects all living things"
        return personality
    }
}

// MARK: - Error Types
enum AIError: Error {
    case notInitialized
    case conversationNotFound
    case invalidResponse
    case quotaExceeded
}

// MARK: - Prompt Engine
class PromptEngine {
    func generateDialoguePrompt(context: DialogueContext) -> String {
        return """
        Generate dialogue for a \(context.speaker) speaking about \(context.topic).
        The speaker should express \(context.emotion ?? .neutral) emotion.
        Keep the response under 100 words and in-character for the Finalverse setting.
        """
    }
    
    func generateQuestPrompt(parameters: QuestParameters) -> String {
        return """
        Create a quest for the Finalverse world with these parameters:
        Type: \(parameters.questType)
        Difficulty: \(parameters.difficulty)
        Location: \(parameters.location)
        Quest Giver: \(parameters.questGiver)
        
        Include:
        1. An engaging title
        2. A description that fits the world's lore
        3. Clear objectives
        4. Appropriate rewards
        
        Keep it concise and engaging.
        """
    }
    
    func generatePersonalityPrompt(template: NPCTemplate) -> String {
        return """
        Create a personality for an NPC in the Finalverse with this background:
        Role: \(template.role)
        Location: \(template.location)
        Background: \(template.background)
        
        Generate:
        1. Two personality traits
        2. One quirk or habit
        3. A speech pattern or catchphrase
        4. Their view on the Song of Creation
        
        Make them memorable but believable within the world.
        """
    }
}
