//
//  Services/Finalverse/StoryEngine.swift
//  FinalStorm
//
//  Manages dynamic storytelling and quest generation with correct initializers
//

import Foundation
import Combine

@MainActor
class StoryEngine: ObservableObject {
    @Published var activeQuests: [Quest] = []
    @Published var completedQuests: [Quest] = []
    @Published var availableQuests: [Quest] = []
    
    private let networkClient: FinalverseNetworkClient
    
    init() {
        self.networkClient = FinalverseNetworkClient(service: .storyEngine)
    }
    
    func initialize() async {
        do {
            try await networkClient.connect()
            // Load initial quests
            await loadAvailableQuests()
        } catch {
            print("Failed to initialize Story Engine: \(error)")
        }
    }
    
    func loadAvailableQuests() async {
        // For now, create sample quests with CORRECT initializers
        availableQuests = [
            Quest(
                id: UUID(),
                title: "The Fading Melody",
                description: "Help Anya restore her artistic inspiration",
                objectives: [
                    // FIXED: Use correct QuestObjective initializer
                    QuestObjective(
                        description: "Find the Resonant Blossom in Whisperwood Grove",
                        targetType: .collectItems,  // ADDED: Required targetType parameter
                        targetCount: 1
                    ),
                    QuestObjective(
                        description: "Return the Blossom to Anya",
                        targetType: .deliverItem,  // ADDED: Required targetType parameter
                        targetCount: 1
                    )
                ],
                rewards: [
                    // FIXED: Use correct QuestReward initializer
                    QuestReward(
                        type: .resonance(type: .restoration, amount: 10),  // ADDED: Required type parameter
                        description: "Restoration melody resonance boost"  // ADDED: Required description parameter
                    )
                ],
                questGiver: "Anya",
                location: "Weaver's Landing"
            )
        ]
    }
    
    func acceptQuest(_ quest: Quest) {
        if let index = availableQuests.firstIndex(where: { $0.id == quest.id }) {
            availableQuests.remove(at: index)
            activeQuests.append(quest)
        }
    }
    
    func completeObjective(_ objectiveId: UUID, in questId: UUID) {
        if let questIndex = activeQuests.firstIndex(where: { $0.id == questId }) {
            if let objIndex = activeQuests[questIndex].objectives.firstIndex(where: { $0.id == objectiveId }) {
                activeQuests[questIndex].objectives[objIndex].updateProgress()
                
                // Check if quest is complete
                if activeQuests[questIndex].objectives.allSatisfy({ $0.isCompleted }) {
                    completeQuest(activeQuests[questIndex])
                }
            }
        }
    }
    
    private func completeQuest(_ quest: Quest) {
        if let index = activeQuests.firstIndex(where: { $0.id == quest.id }) {
            activeQuests.remove(at: index)
            completedQuests.append(quest)
            
            // Grant rewards
            for reward in quest.rewards {
                grantReward(reward)
            }
        }
    }
    
    private func grantReward(_ reward: QuestReward) {
        // Implement reward granting
        print("Granting reward: \(reward.description)")
    }
}
