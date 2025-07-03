//
//  Quest.swift
//  FinalStorm
//
//  Quest system types
//

import Foundation

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
