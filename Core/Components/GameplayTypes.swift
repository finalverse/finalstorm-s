//
//  Core/Components/GameplayTypes.swift
//  FinalStorm
//
//  Quest, dialogue, inventory, and gameplay-related types
//  Consolidates all gameplay mechanics in one place
//

import Foundation
import RealityKit
import Combine

// MARK: - Quest System

struct Quest: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    var objectives: [QuestObjective]
    let rewards: [QuestReward]
    let questGiver: String
    let location: String
    let category: QuestCategory
    let difficulty: QuestDifficulty
    let estimatedDuration: TimeInterval
    let prerequisites: [UUID]
    var status: QuestStatus
    let createdAt: Date
    var completedAt: Date?
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        objectives: [QuestObjective],
        rewards: [QuestReward],
        questGiver: String,
        location: String,
        category: QuestCategory = .main,
        difficulty: QuestDifficulty = .normal,
        estimatedDuration: TimeInterval = 1800,
        prerequisites: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.objectives = objectives
        self.rewards = rewards
        self.questGiver = questGiver
        self.location = location
        self.category = category
        self.difficulty = difficulty
        self.estimatedDuration = estimatedDuration
        self.prerequisites = prerequisites
        self.status = .available
        self.createdAt = Date()
        self.completedAt = nil
    }
    
    var isCompleted: Bool {
        let requiredObjectives = objectives.filter { !$0.isOptional }
        return requiredObjectives.allSatisfy { $0.isCompleted }
    }
    
    var completionPercentage: Float {
        let requiredObjectives = objectives.filter { !$0.isOptional }
        guard !requiredObjectives.isEmpty else { return 0.0 }
        let completedCount = requiredObjectives.filter { $0.isCompleted }.count
        return Float(completedCount) / Float(requiredObjectives.count)
    }
    
    mutating func completeObjective(withId objectiveId: UUID) {
        if let index = objectives.firstIndex(where: { $0.id == objectiveId }) {
            objectives[index].isCompleted = true
            objectives[index].completedAt = Date()
            
            if isCompleted {
                status = .completed
                completedAt = Date()
            }
        }
    }
}

struct QuestObjective: Identifiable, Codable {
    let id: UUID
    let description: String
    let targetType: ObjectiveTargetType
    let targetCount: Int
    var currentCount: Int
    var isCompleted: Bool
    let isOptional: Bool
    var completedAt: Date?
    
    init(
        id: UUID = UUID(),
        description: String,
        targetType: ObjectiveTargetType,
        targetCount: Int = 1,
        isOptional: Bool = false
    ) {
        self.id = id
        self.description = description
        self.targetType = targetType
        self.targetCount = targetCount
        self.currentCount = 0
        self.isCompleted = false
        self.isOptional = isOptional
        self.completedAt = nil
    }
    
    var progress: Float {
        guard targetCount > 0 else { return 1.0 }
        return Float(currentCount) / Float(targetCount)
    }
    
    mutating func updateProgress(by amount: Int = 1) {
        currentCount = min(targetCount, currentCount + amount)
        if currentCount >= targetCount && !isCompleted {
            isCompleted = true
            completedAt = Date()
        }
    }
}

struct QuestReward: Identifiable, Codable {
    let id: UUID
    let type: QuestRewardType
    let description: String
    let rarity: RewardRarity
    
    init(
        id: UUID = UUID(),
        type: QuestRewardType,
        description: String,
        rarity: RewardRarity = .common
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.rarity = rarity
    }
}

// MARK: - Quest Enums

enum QuestCategory: String, Codable, CaseIterable {
    case main = "Main Story"
    case side = "Side Quest"
    case exploration = "Exploration"
    case collection = "Collection"
    case social = "Social"
    case songweaving = "Songweaving"
    case worldEvent = "World Event"
    case daily = "Daily Quest"
    case weekly = "Weekly Quest"
    
    var iconName: String {
        switch self {
        case .main: return "star.fill"
        case .side: return "circle.fill"
        case .exploration: return "map.fill"
        case .collection: return "bag.fill"
        case .social: return "person.2.fill"
        case .songweaving: return "music.note"
        case .worldEvent: return "globe"
        case .daily: return "calendar"
        case .weekly: return "calendar.badge.clock"
        }
    }
    
    var priority: Int {
        switch self {
        case .main: return 10
        case .worldEvent: return 9
        case .daily: return 8
        case .weekly: return 7
        case .side: return 6
        case .songweaving: return 5
        case .social: return 4
        case .exploration: return 3
        case .collection: return 2
        }
    }
}

enum QuestDifficulty: String, Codable, CaseIterable {
    case trivial = "Trivial"
    case easy = "Easy"
    case normal = "Normal"
    case hard = "Hard"
    case expert = "Expert"
    case legendary = "Legendary"
    
    var suggestedLevel: Int {
        switch self {
        case .trivial: return 1
        case .easy: return 5
        case .normal: return 10
        case .hard: return 20
        case .expert: return 35
        case .legendary: return 50
        }
    }
    
    var experienceMultiplier: Float {
        switch self {
        case .trivial: return 0.5
        case .easy: return 0.8
        case .normal: return 1.0
        case .hard: return 1.5
        case .expert: return 2.0
        case .legendary: return 3.0
        }
    }
}

enum QuestStatus: String, Codable, CaseIterable {
    case locked = "Locked"
    case available = "Available"
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"
    case abandoned = "Abandoned"
    case expired = "Expired"
    
    var isWorkable: Bool { self == .active }
    var isFinished: Bool { [.completed, .failed, .abandoned, .expired].contains(self) }
}

enum ObjectiveTargetType: String, Codable, CaseIterable {
    case killEnemies = "Kill Enemies"
    case collectItems = "Collect Items"
    case reachLocation = "Reach Location"
    case interactWith = "Interact With"
    case songweaveSpell = "Cast Songweave"
    case deliverItem = "Deliver Item"
    case solveSecret = "Solve Secret"
    case restoreHarmony = "Restore Harmony"
    case talkToNPC = "Talk to NPC"
    case exploreArea = "Explore Area"
    case craftItem = "Craft Item"
    case learnMelody = "Learn Melody"
}

enum QuestRewardType: Codable {
    case experience(amount: Int)
    case resonance(type: MelodyType, amount: Float)
    case item(id: String, quantity: Int)
    case melody(type: MelodyType)
    case currency(type: CurrencyType, amount: Int)
    case reputation(faction: String, amount: Int)
    case unlock(feature: String)
    
    var typeDescription: String {
        switch self {
        case .experience(let amount): return "\(amount) experience points"
        case .resonance(let type, let amount): return "\(Int(amount)) \(type.rawValue) resonance"
        case .item(let id, let quantity): return "\(quantity)x \(id)"
        case .melody(let type): return "\(type.rawValue) melody"
        case .currency(let type, let amount): return "\(amount) \(type.rawValue)"
        case .reputation(let faction, let amount): return "\(amount) \(faction) reputation"
        case .unlock(let feature): return "Unlock: \(feature)"
        }
    }
}

enum RewardRarity: String, Codable, CaseIterable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"
    case mythic = "Mythic"
    
    var color: CodableColor {
        switch self {
        case .common: return CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        case .uncommon: return CodableColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        case .rare: return CodableColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0)
        case .epic: return CodableColor(red: 0.6, green: 0.0, blue: 1.0, alpha: 1.0)
        case .legendary: return CodableColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        case .mythic: return CodableColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        }
    }
}

// MARK: - Dialogue System

struct DialogueContext {
    let speaker: EchoType
    let topic: GuidanceTopic
    let playerState: PlayerState
    let worldState: WorldState
    let conversationId: UUID?
    let emotion: Emotion?
}

struct Dialogue {
    let text: String
    let emotion: Emotion
    let duration: TimeInterval
    let audioURL: URL?
}

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
}

// MARK: - Inventory System

struct InventorySlot: Codable {
    let itemId: UUID
    let quantity: Int
}

struct InventoryComponent: Component, Codable {
    var items: [UUID: InventorySlot] = [:]
    var maxSlots: Int = 20
    var equippedItems: [EquipSlot: UUID] = [:]
    var currencyAmounts: [CurrencyType: Int] = [:]
    
    init(maxSlots: Int = 20) {
        self.maxSlots = maxSlots
        CurrencyType.allCases.forEach { currencyType in
            currencyAmounts[currencyType] = 0
        }
    }
    
    var usedSlots: Int { items.count }
    var availableSlots: Int { maxSlots - usedSlots }
    var hasSpace: Bool { usedSlots < maxSlots }
    
    mutating func addItem(id: UUID, quantity: Int = 1) -> Bool {
        if let existingSlot = items[id] {
            items[id] = InventorySlot(itemId: id, quantity: existingSlot.quantity + quantity)
            return true
        } else if hasSpace {
            items[id] = InventorySlot(itemId: id, quantity: quantity)
            return true
        }
        return false
    }
    
    mutating func removeItem(id: UUID, quantity: Int = 1) -> Bool {
        guard let slot = items[id], slot.quantity >= quantity else { return false }
        
        if slot.quantity == quantity {
            items.removeValue(forKey: id)
        } else {
            items[id] = InventorySlot(itemId: id, quantity: slot.quantity - quantity)
        }
        return true
    }
}

// MARK: - Currency System

enum CurrencyType: String, Codable, CaseIterable {
    case gold = "Gold"
    case harmonyCrystals = "Harmony Crystals"
    case ancientNotes = "Ancient Notes"
    case echoShards = "Echo Shards"
}

// MARK: - Item System

enum ItemRarity: String, Codable, CaseIterable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"
    case artifact = "Artifact"
    
    var color: CodableColor {
        switch self {
        case .common: return CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        case .uncommon: return CodableColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        case .rare: return CodableColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0)
        case .epic: return CodableColor(red: 0.6, green: 0.0, blue: 1.0, alpha: 1.0)
        case .legendary: return CodableColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        case .artifact: return CodableColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .artifact: return 6
        case .legendary: return 5
        case .epic: return 4
        case .rare: return 3
        case .uncommon: return 2
        case .common: return 1
        }
    }
}

enum EquipSlot: String, Codable, CaseIterable {
    case head = "Head"
    case chest = "Chest"
    case legs = "Legs"
    case feet = "Feet"
    case hands = "Hands"
    case mainHand = "Main Hand"
    case offHand = "Off Hand"
    case ring = "Ring"
    case necklace = "Necklace"
    case back = "Back"
}

// MARK: - Player and World State

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
