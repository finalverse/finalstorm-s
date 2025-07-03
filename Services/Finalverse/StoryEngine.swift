//
//  StoryEngine.swift
//  FinalStorm
//
//  Manages dynamic storytelling and quest generation
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
        // For now, create sample quests
        availableQuests = [
            Quest(
                id: UUID(),
                title: "The Fading Melody",
                description: "Help Anya restore her artistic inspiration",
                objectives: [
                    QuestObjective(
                        id: UUID(),
                        description: "Find the Resonant Blossom in Whisperwood Grove",
                        isCompleted: false
                    ),
                    QuestObjective(
                        id: UUID(),
                        description: "Return the Blossom to Anya",
                        isCompleted: false
                    )
                ],
                rewards: [
                    QuestReward(type: .resonance(amount: 10))
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
                activeQuests[questIndex].objectives[objIndex].isCompleted = true
                
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
    }
}
