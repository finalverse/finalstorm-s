//
//  Quest.swift
//  FinalStorm
//
//  Quest system types for dynamic storytelling and player progression
//  Manages objectives, rewards, and quest state tracking
//

import Foundation

// MARK: - Quest System Core

/// Represents a quest that players can undertake in the Finalverse
/// Quests drive narrative progression and provide structured objectives
struct Quest: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    var objectives: [QuestObjective]     // Individual tasks to complete
    let rewards: [QuestReward]          // What players receive upon completion
    let questGiver: String              // NPC or entity that provided the quest
    let location: String                // Where the quest takes place
    let category: QuestCategory         // Type of quest for organization
    let difficulty: QuestDifficulty     // How challenging the quest is
    let estimatedDuration: TimeInterval // Expected time to complete in seconds
    let prerequisites: [UUID]           // Required completed quest IDs
    var status: QuestStatus            // Current completion state
    let createdAt: Date               // When the quest was created/accepted
    var completedAt: Date?            // When the quest was finished (nil if not complete)
    
    /// Initialize a new quest with all required parameters
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
        estimatedDuration: TimeInterval = 1800, // 30 minutes default
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
    
    /// Check if all required objectives are completed
    var isCompleted: Bool {
        let requiredObjectives = objectives.filter { !$0.isOptional }
        return requiredObjectives.allSatisfy { $0.isCompleted }
    }
    
    /// Get completion percentage (0.0 to 1.0) based on required objectives
    var completionPercentage: Float {
        let requiredObjectives = objectives.filter { !$0.isOptional }
        guard !requiredObjectives.isEmpty else { return 0.0 }
        let completedCount = requiredObjectives.filter { $0.isCompleted }.count
        return Float(completedCount) / Float(requiredObjectives.count)
    }
    
    /// Get all objectives that still need to be completed
    var remainingObjectives: [QuestObjective] {
        return objectives.filter { !$0.isCompleted }
    }
    
    /// Calculate total experience reward value from all rewards
    var totalExperienceReward: Int {
        return rewards.compactMap { reward in
            if case .experience(let amount) = reward.type {
                return amount
            }
            return nil
        }.reduce(0, +)
    }
    
    /// Mark a specific objective as completed and update quest status
    mutating func completeObjective(withId objectiveId: UUID) {
        if let index = objectives.firstIndex(where: { $0.id == objectiveId }) {
            objectives[index].isCompleted = true
            objectives[index].completedAt = Date()
            
            // Update quest status if all required objectives are done
            if isCompleted {
                status = .completed
                completedAt = Date()
            }
        }
    }
    
    /// Add a new objective to the quest (for dynamic quest expansion)
    mutating func addObjective(_ objective: QuestObjective) {
        objectives.append(objective)
    }
    
    /// Update quest status manually (for special cases)
    mutating func updateStatus(_ newStatus: QuestStatus) {
        status = newStatus
        if newStatus == .completed {
            completedAt = Date()
        }
    }
}

// MARK: - Quest Objective
struct QuestObjective: Identifiable, Codable {
    let id: UUID
    let description: String              // Human-readable objective description
    let targetType: ObjectiveTargetType  // What type of objective this is
    let targetCount: Int                // How many of something to accomplish
    var currentCount: Int              // Current progress toward target
    var isCompleted: Bool             // Whether this objective is done
    let isOptional: Bool              // Whether this objective is required for quest completion
    var completedAt: Date?           // When this objective was finished
    
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
    
    /// Get completion progress as percentage (0.0 to 1.0)
    var progress: Float {
        guard targetCount > 0 else { return 1.0 }
        return Float(currentCount) / Float(targetCount)
    }
    
    /// Get remaining amount needed to complete this objective
    var remainingCount: Int {
        return max(0, targetCount - currentCount)
    }
    
    /// Update progress toward objective completion
    mutating func updateProgress(by amount: Int = 1) {
        currentCount = min(targetCount, currentCount + amount)
        if currentCount >= targetCount && !isCompleted {
            isCompleted = true
            completedAt = Date()
        }
    }
    
    /// Reset objective progress (for repeatable objectives)
    mutating func reset() {
        currentCount = 0
        isCompleted = false
        completedAt = nil
    }
}

// MARK: - Quest Reward
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
    
    /// Get a short display string for this reward
    var displayText: String {
        switch type {
        case .resonance(let melodyType, let amount):
            return "\(Int(amount)) \(melodyType.rawValue) Resonance"
        case .experience(let amount):
            return "\(amount) XP"
        case .item(let itemId, let quantity):
            return "\(quantity)x \(itemId)"
        case .melody(let melodyType):
            return "Melody: \(melodyType.rawValue)"
        case .currency(let currencyType, let amount):
            return "\(amount) \(currencyType.rawValue)"
        case .reputation(let faction, let amount):
            return "\(amount) \(faction) Reputation"
        case .unlock(let feature):
            return "Unlock: \(feature)"
        }
    }
}

// MARK: - Quest Reward Types
enum QuestRewardType: Codable {
    case experience(amount: Int)           // XP points
    case resonance(type: MelodyType, amount: Float)  // Resonance increase
    case item(id: String, quantity: Int)   // Inventory items
    case melody(type: MelodyType)          // New melody abilities
    case currency(type: CurrencyType, amount: Int)  // Gold, crystals, etc.
    case reputation(faction: String, amount: Int)   // Faction standing
    case unlock(feature: String)           // New features/areas
    
    /// Human-readable description of the reward type
    var typeDescription: String {
        switch self {
        case .experience(let amount):
            return "\(amount) experience points"
        case .resonance(let type, let amount):
            return "\(Int(amount)) \(type.rawValue) resonance"
        case .item(let id, let quantity):
            return "\(quantity)x \(id)"
        case .melody(let type):
            return "\(type.rawValue) melody"
        case .currency(let type, let amount):
            return "\(amount) \(type.rawValue)"
        case .reputation(let faction, let amount):
            return "\(amount) \(faction) reputation"
        case .unlock(let feature):
            return "Unlock: \(feature)"
        }
    }
}

// MARK: - Supporting Enums
enum CurrencyType: String, Codable {
    case gold = "Gold"
    case harmonyCrystals = "Harmony Crystals"
    case ancientNotes = "Ancient Notes"
    case echoShards = "Echo Shards"
}

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
    
    /// Icon name for UI display
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
    
    /// Priority level for quest ordering
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
    
    /// Suggested player level for this difficulty
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
    
    /// Experience multiplier for rewards
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
    
    /// Color indicator for UI
    var color: String {
        switch self {
        case .trivial: return "gray"
        case .easy: return "green"
        case .normal: return "blue"
        case .hard: return "orange"
        case .expert: return "red"
        case .legendary: return "purple"
        }
    }
}

enum QuestStatus: String, Codable, CaseIterable {
    case locked = "Locked"           // Prerequisites not met
    case available = "Available"     // Can be started
    case active = "Active"          // Currently being worked on
    case completed = "Completed"    // Successfully finished
    case failed = "Failed"         // Could not be completed
    case abandoned = "Abandoned"   // Player gave up
    case expired = "Expired"       // Time-limited quest ran out
    
    /// Whether this status allows the quest to be worked on
    var isWorkable: Bool {
        return self == .active
    }
    
    /// Whether this status represents a finished state
    var isFinished: Bool {
        return [.completed, .failed, .abandoned, .expired].contains(self)
    }
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
    
    /// Description of what this objective type involves
    var description: String {
        switch self {
        case .killEnemies: return "Defeat hostile creatures or entities"
        case .collectItems: return "Gather specific items from the world"
        case .reachLocation: return "Travel to a designated area"
        case .interactWith: return "Use or activate objects in the world"
        case .songweaveSpell: return "Cast specific songweaving abilities"
        case .deliverItem: return "Bring items to specific NPCs or locations"
        case .solveSecret: return "Uncover hidden knowledge or mysteries"
        case .restoreHarmony: return "Heal corruption and restore balance"
        case .talkToNPC: return "Have conversations with specific characters"
        case .exploreArea: return "Discover new regions or points of interest"
        case .craftItem: return "Create items using crafting systems"
        case .learnMelody: return "Master new songweaving techniques"
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
    
    /// Color associated with this rarity for UI
    var color: String {
        switch self {
        case .common: return "gray"
        case .uncommon: return "green"
        case .rare: return "blue"
        case .epic: return "purple"
        case .legendary: return "orange"
        case .mythic: return "gold"
        }
    }
    
    /// Relative value multiplier for this rarity
    var valueMultiplier: Float {
        switch self {
        case .common: return 1.0
        case .uncommon: return 1.5
        case .rare: return 2.0
        case .epic: return 3.0
        case .legendary: return 5.0
        case .mythic: return 10.0
        }
    }
}

// MARK: - Quest Factory
struct QuestFactory {
    /// Create a simple collection quest
    static func createCollectionQuest(
        title: String,
        itemName: String,
        quantity: Int,
        location: String,
        questGiver: String,
        rewards: [QuestReward]
    ) -> Quest {
        let objective = QuestObjective(
            description: "Collect \(quantity) \(itemName)",
            targetType: .collectItems,
            targetCount: quantity
        )
        
        return Quest(
            title: title,
            description: "Gather \(quantity) \(itemName) for \(questGiver).",
            objectives: [objective],
            rewards: rewards,
            questGiver: questGiver,
            location: location,
            category: .collection
        )
    }
    
    /// Create a songweaving practice quest
    static func createSongweavingQuest(
        title: String,
        melodyType: String,
        castCount: Int,
        location: String,
        questGiver: String
    ) -> Quest {
        let objective = QuestObjective(
            description: "Cast \(castCount) \(melodyType) melodies",
            targetType: .songweaveSpell,
            targetCount: castCount
        )
        
        let reward = QuestReward(
            type: .experience(amount: 200),
            description: "Learn advanced \(melodyType) techniques",
            rarity: .uncommon
        )
        
        return Quest(
            title: title,
            description: "Practice your \(melodyType) songweaving skills.",
            objectives: [objective],
            rewards: [reward],
            questGiver: questGiver,
            location: location,
            category: .songweaving
        )
    }
    
    /// Create a social interaction quest
    static func createSocialQuest(
        title: String,
        npcName: String,
        location: String,
        questGiver: String,
        experienceReward: Int = 100
    ) -> Quest {
        let objective = QuestObjective(
            description: "Speak with \(npcName)",
            targetType: .talkToNPC,
            targetCount: 1
        )
        
        let reward = QuestReward(
            type: .experience(amount: experienceReward),
            description: "Social interaction experience",
            rarity: .common
        )
        
        return Quest(
            title: title,
            description: "Find and have a conversation with \(npcName) in \(location).",
            objectives: [objective],
            rewards: [reward],
            questGiver: questGiver,
            location: location,
            category: .social
        )
    }
}

// MARK: - Collection Extensions
extension Array where Element == Quest {
    /// Get all active quests from the collection
    var activeQuests: [Quest] {
        return self.filter { $0.status == .active }
    }
    
    /// Get all completed quests from the collection
    var completedQuests: [Quest] {
        return self.filter { $0.status == .completed }
    }
    
    /// Get quests by specific category
    func quests(in category: QuestCategory) -> [Quest] {
        return self.filter { $0.category == category }
    }
    
    /// Get quests by difficulty level
    func quests(withDifficulty difficulty: QuestDifficulty) -> [Quest] {
        return self.filter { $0.difficulty == difficulty }
    }
    
    /// Get quests by status
    func quests(withStatus status: QuestStatus) -> [Quest] {
        return self.filter { $0.status == status }
    }
    
    /// Get quests sorted by priority (main quests first, etc.)
    var prioritySorted: [Quest] {
        return self.sorted { quest1, quest2 in
            // First sort by category priority
            if quest1.category.priority != quest2.category.priority {
                return quest1.category.priority > quest2.category.priority
            }
            // Then by difficulty
            if quest1.difficulty != quest2.difficulty {
                return quest1.difficulty.experienceMultiplier > quest2.difficulty.experienceMultiplier
            }
            // Finally by creation date (newest first)
            return quest1.createdAt > quest2.createdAt
        }
    }
}

extension Array where Element == QuestObjective {
    /// Get all incomplete objectives
    var incompleteObjectives: [QuestObjective] {
        return self.filter { !$0.isCompleted }
    }
    
    /// Get all completed objectives
    var completedObjectives: [QuestObjective] {
        return self.filter { $0.isCompleted }
    }
    
    /// Get all required (non-optional) objectives
    var requiredObjectives: [QuestObjective] {
        return self.filter { !$0.isOptional }
    }
}
