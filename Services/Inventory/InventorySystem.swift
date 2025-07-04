//
//  Services/Inventory/InventorySystem.swift
//  FinalStorm
//
//  Complete inventory management system for items, assets, and equipment
//  Handles item creation, modification, storage, and synchronization
//

import Foundation
import RealityKit
import Combine

@MainActor
class InventorySystem: ObservableObject {
    // MARK: - Properties
    @Published var items: [InventoryItem] = []
    @Published var selectedItems: Set<UUID> = []
    @Published var sortOrder: SortOrder = .name
    @Published var filterCategory: ItemCategory = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    
    private let assetManager: AssetManager
    private let itemRenderer: ItemRenderer
    private let persistenceManager: InventoryPersistenceManager
    private var cancellables = Set<AnyCancellable>()
    
    // Inventory limits
    private let maxItems: Int = 1000
    private let maxWeight: Float = 100.0
    
    enum SortOrder {
        case name
        case type
        case rarity
        case dateAdded
        case quantity
    }
    
    // MARK: - Initialization
    init() {
        self.assetManager = AssetManager()
        self.itemRenderer = ItemRenderer()
        self.persistenceManager = InventoryPersistenceManager()
        
        setupBindings()
        loadInventory()
    }
    
    private func setupBindings() {
        // Auto-save when items change
        $items
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] items in
                Task {
                    await self?.saveInventory()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Item Management
    func addItem(_ item: InventoryItem) throws {
        // Check inventory limits
        guard items.count < maxItems else {
            throw InventoryError.inventoryFull
        }
        
        let totalWeight = items.reduce(0) { $0 + $1.weight * Float($1.quantity) }
        let newWeight = item.weight * Float(item.quantity)
        guard totalWeight + newWeight <= maxWeight else {
            throw InventoryError.tooHeavy
        }
        
        // Check if stackable item already exists
        if item.isStackable,
           let existingIndex = items.firstIndex(where: { $0.templateId == item.templateId }) {
            items[existingIndex].quantity += item.quantity
        } else {
            items.append(item)
        }
        
        // Generate icon if needed
        Task {
            await generateItemIcon(item)
        }
    }
    
    func removeItem(_ itemId: UUID, quantity: Int = 1) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        if items[index].quantity <= quantity {
            items.remove(at: index)
        } else {
            items[index].quantity -= quantity
        }
    }
    
    func moveItem(_ itemId: UUID, to targetSlot: Int) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == itemId }),
              targetSlot < items.count else { return }
        
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: targetSlot)
    }
    
    func updateItemQuantity(_ itemId: UUID, newQuantity: Int) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        guard newQuantity > 0 else {
            items.remove(at: index)
            return
        }
        
        items[index].quantity = newQuantity
    }
    
    func equipItem(_ itemId: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        guard items[index].isEquippable else {
            throw InventoryError.cannotEquip
        }
        
        items[index].isEquipped = true
        
        // Unequip conflicting items
        if let equipSlot = items[index].equipSlot {
            for i in items.indices {
                if i != index && items[i].equipSlot == equipSlot && items[i].isEquipped {
                    items[i].isEquipped = false
                }
            }
        }
    }
    
    func unequipItem(_ itemId: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        items[index].isEquipped = false
    }
    
    // MARK: - Item Creation
    func createItem(from template: ItemTemplate, quantity: Int = 1) -> InventoryItem {
        return InventoryItem(
            id: UUID(),
            templateId: template.id,
            name: template.name,
            description: template.description,
            category: template.category,
            rarity: template.rarity,
            quantity: quantity,
            weight: template.weight,
            value: template.value,
            iconAssetId: template.iconAssetId,
            meshAssetId: template.meshAssetId,
            isStackable: template.isStackable,
            isEquippable: template.isEquippable,
            equipSlot: template.equipSlot,
            stats: template.stats,
            effects: template.effects,
            requirements: template.requirements,
            durability: template.maxDurability,
            maxDurability: template.maxDurability,
            isEquipped: false,
            dateAdded: Date(),
            customData: [:]
        )
    }
    
    func craftItem(recipe: CraftingRecipe) throws -> InventoryItem {
        // Check if player has required materials
        for material in recipe.materials {
            let availableQuantity = items
                .filter { $0.templateId == material.templateId }
                .reduce(0) { $0 + $1.quantity }
            
            guard availableQuantity >= material.quantity else {
                throw InventoryError.insufficientMaterials
            }
        }
        
        // Remove materials
        for material in recipe.materials {
            try consumeMaterial(templateId: material.templateId, quantity: material.quantity)
        }
        
        // Create result item
        let resultTemplate = try getItemTemplate(recipe.resultTemplateId)
        let resultItem = createItem(from: resultTemplate, quantity: recipe.resultQuantity)
        
        try addItem(resultItem)
        
        return resultItem
    }
    
    private func consumeMaterial(templateId: UUID, quantity: Int) throws {
        var remainingToConsume = quantity
        
        for i in items.indices.reversed() {
            if items[i].templateId == templateId {
                let consumeFromThis = min(remainingToConsume, items[i].quantity)
                
                if items[i].quantity <= consumeFromThis {
                    items.remove(at: i)
                } else {
                    items[i].quantity -= consumeFromThis
                }
                
                remainingToConsume -= consumeFromThis
                
                if remainingToConsume <= 0 {
                    break
                }
            }
        }
        
        if remainingToConsume > 0 {
            throw InventoryError.insufficientMaterials
        }
    }
    
    // MARK: - Filtering and Sorting
    var filteredAndSortedItems: [InventoryItem] {
        let filtered = filteredItems
        return sortItems(filtered)
    }
    
    private var filteredItems: [InventoryItem] {
        var filtered = items
        
        // Apply category filter
        if filterCategory != .all {
            filtered = filtered.filter { $0.category == filterCategory }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    private func sortItems(_ items: [InventoryItem]) -> [InventoryItem] {
        switch sortOrder {
        case .name:
            return items.sorted { $0.name < $1.name }
        case .type:
            return items.sorted { $0.category.rawValue < $1.category.rawValue }
        case .rarity:
            return items.sorted { $0.rarity.sortOrder > $1.rarity.sortOrder }
        case .dateAdded:
            return items.sorted { $0.dateAdded > $1.dateAdded }
        case .quantity:
            return items.sorted { $0.quantity > $1.quantity }
        }
    }
    
    // MARK: - Item Information
    func getItemStats(_ itemId: UUID) -> [ItemStat] {
        guard let item = items.first(where: { $0.id == itemId }) else { return [] }
        return item.stats
    }
    
    func getItemEffects(_ itemId: UUID) -> [ItemEffect] {
        guard let item = items.first(where: { $0.id == itemId }) else { return [] }
        return item.effects
    }
    
    func getTotalValue() -> Int {
        return items.reduce(0) { $0 + ($1.value * $1.quantity) }
    }
    
    func getTotalWeight() -> Float {
        return items.reduce(0) { $0 + ($1.weight * Float($1.quantity)) }
    }
    
    func getEquippedItems() -> [InventoryItem] {
        return items.filter { $0.isEquipped }
    }
    
    func getItemsByCategory(_ category: ItemCategory) -> [InventoryItem] {
        return items.filter { $0.category == category }
    }
    
    // MARK: - Item Operations
    func useItem(_ itemId: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        let item = items[index]
        
        guard item.isUsable else {
            throw InventoryError.cannotUse
        }
        
        // Apply item effects
        for effect in item.effects {
            applyItemEffect(effect)
        }
        
        // Consume item if it's consumable
        if item.category == .consumable {
            try removeItem(itemId, quantity: 1)
        }
        
        // Reduce durability for equipment
        if item.category == .equipment && item.durability > 0 {
            items[index].durability -= 1
            
            // Break item if durability reaches 0
            if items[index].durability <= 0 {
                items[index].isBroken = true
            }
        }
    }
    
    func repairItem(_ itemId: UUID, repairAmount: Int) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        guard items[index].category == .equipment else {
            throw InventoryError.cannotRepair
        }
        
        items[index].durability = min(
            items[index].maxDurability,
            items[index].durability + repairAmount
        )
        
        if items[index].durability > 0 {
            items[index].isBroken = false
        }
    }
    
    func enhanceItem(_ itemId: UUID, enhancement: ItemEnhancement) throws {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw InventoryError.itemNotFound
        }
        
        guard items[index].canBeEnhanced else {
            throw InventoryError.cannotEnhance
        }
        
        // Apply enhancement
        items[index].enhancements.append(enhancement)
        
        // Update item stats based on enhancement
        applyEnhancementToItem(&items[index], enhancement)
    }
    
    private func applyItemEffect(_ effect: ItemEffect) {
        switch effect.type {
        case .healHealth(let amount):
            // Notify health system
            NotificationCenter.default.post(
                name: .healPlayer,
                object: amount
            )
            
        case .restoreMana(let amount):
            // Notify mana system
            NotificationCenter.default.post(
                name: .restorePlayerMana,
                object: amount
            )
            
        case .buffStat(let stat, let amount, let duration):
            // Apply temporary stat buff
            NotificationCenter.default.post(
                name: .applyStatBuff,
                object: StatBuff(stat: stat, amount: amount, duration: duration)
            )
            
        case .grantAbility(let abilityId):
            // Grant temporary ability
            NotificationCenter.default.post(
                name: .grantTemporaryAbility,
                object: abilityId
            )
        }
    }
    
    private func applyEnhancementToItem(_ item: inout InventoryItem, _ enhancement: ItemEnhancement) {
        switch enhancement.type {
        case .statBonus(let stat, let amount):
            // Add or update stat
            if let existingIndex = item.stats.firstIndex(where: { $0.type == stat }) {
                item.stats[existingIndex].value += amount
            } else {
                item.stats.append(ItemStat(type: stat, value: amount))
            }
            
        case .durabilityBonus(let amount):
            item.maxDurability += amount
            item.durability += amount
            
        case .specialEffect(let effect):
            item.effects.append(effect)
        }
    }
    
    // MARK: - Asset Management
    private func generateItemIcon(_ item: InventoryItem) async {
        if let iconAssetId = item.iconAssetId {
            // Load existing icon
            do {
                let texture = try await assetManager.loadTexture(iconAssetId)
                await itemRenderer.cacheIcon(for: item.id, texture: texture)
            } catch {
                print("Failed to load item icon: \(error)")
                await generateDefaultIcon(for: item)
            }
        } else {
            // Generate default icon based on item type
            await generateDefaultIcon(for: item)
        }
    }
    
    private func generateDefaultIcon(for item: InventoryItem) async {
        let icon = await itemRenderer.generateDefaultIcon(
            for: item.category,
            rarity: item.rarity
        )
        await itemRenderer.cacheIcon(for: item.id, texture: icon)
    }
    
    func getItemIcon(_ itemId: UUID) async -> TextureResource? {
        return await itemRenderer.getIcon(for: itemId)
    }
    
    func getItem3DModel(_ itemId: UUID) async -> MeshResource? {
        guard let item = items.first(where: { $0.id == itemId }),
              let meshAssetId = item.meshAssetId else {
            return nil
        }
        
        do {
            return try await assetManager.loadMesh(meshAssetId)
        } catch {
            print("Failed to load item 3D model: \(error)")
            return nil
        }
    }
    
    // MARK: - Persistence
    private func loadInventory() {
        Task {
            isLoading = true
            do {
                let loadedItems = try await persistenceManager.loadInventory()
                items = loadedItems
            } catch {
                print("Failed to load inventory: \(error)")
                items = createDefaultItems()
            }
            isLoading = false
        }
    }
    
    private func saveInventory() async {
        do {
            try await persistenceManager.saveInventory(items)
        } catch {
            print("Failed to save inventory: \(error)")
        }
    }
    
    private func createDefaultItems() -> [InventoryItem] {
        // Create some default starting items
        let templates = ItemTemplateLibrary.shared.getStartingItems()
        return templates.map { createItem(from: $0) }
    }
    
    // MARK: - Helper Methods
    private func getItemTemplate(_ templateId: UUID) throws -> ItemTemplate {
        guard let template = ItemTemplateLibrary.shared.getTemplate(templateId) else {
            throw InventoryError.templateNotFound
        }
        return template
    }
 }

 // MARK: - Supporting Types
 struct InventoryItem: Identifiable, Codable {
    let id: UUID
    let templateId: UUID
    var name: String
    var description: String
    let category: ItemCategory
    let rarity: ItemRarity
    var quantity: Int
    let weight: Float
    var value: Int
    
    // Assets
    let iconAssetId: UUID?
    let meshAssetId: UUID?
    
    // Properties
    let isStackable: Bool
    let isEquippable: Bool
    let equipSlot: EquipSlot?
    var stats: [ItemStat]
    var effects: [ItemEffect]
    let requirements: [ItemRequirement]
    
    // State
    var durability: Int
    let maxDurability: Int
    var isBroken: Bool = false
    var isEquipped: Bool
    let dateAdded: Date
    var enhancements: [ItemEnhancement] = []
    var customData: [String: String]
    
    var isUsable: Bool {
        return category == .consumable || !effects.isEmpty
    }
    
    var canBeEnhanced: Bool {
        return category == .equipment && enhancements.count < 3
    }
    
    var durabilityPercentage: Float {
        guard maxDurability > 0 else { return 1.0 }
        return Float(durability) / Float(maxDurability)
    }
 }

 enum ItemCategory: String, Codable, CaseIterable {
    case all = "All"
    case equipment = "Equipment"
    case consumable = "Consumables"
    case material = "Materials"
    case quest = "Quest Items"
    case tool = "Tools"
    case misc = "Miscellaneous"
 }

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

 struct ItemStat: Codable {
    let type: StatType
    var value: Int
    
    enum StatType: String, Codable, CaseIterable {
        case attack = "Attack"
        case defense = "Defense"
        case speed = "Speed"
        case health = "Health"
        case mana = "Mana"
        case luck = "Luck"
        case criticalChance = "Critical Chance"
        case resonance = "Resonance"
    }
 }

 struct ItemEffect: Codable {
    let type: EffectType
    let duration: TimeInterval
    let description: String
    
    enum EffectType: Codable {
        case healHealth(amount: Int)
        case restoreMana(amount: Int)
        case buffStat(stat: ItemStat.StatType, amount: Int, duration: TimeInterval)
        case grantAbility(abilityId: UUID)
    }
 }

 struct ItemRequirement: Codable {
    let type: RequirementType
    let value: Int
    
    enum RequirementType: String, Codable {
        case level = "Level"
        case stat = "Stat"
        case skill = "Skill"
        case quest = "Quest"
    }
 }

 struct ItemEnhancement: Codable {
    let id: UUID
    let type: EnhancementType
    let name: String
    let description: String
    let appliedAt: Date
    
    enum EnhancementType: Codable {
        case statBonus(stat: ItemStat.StatType, amount: Int)
        case durabilityBonus(amount: Int)
        case specialEffect(effect: ItemEffect)
    }
 }

 struct ItemTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let category: ItemCategory
    let rarity: ItemRarity
    let weight: Float
    let value: Int
    let iconAssetId: UUID?
    let meshAssetId: UUID?
    let isStackable: Bool
    let isEquippable: Bool
    let equipSlot: EquipSlot?
    let stats: [ItemStat]
    let effects: [ItemEffect]
    let requirements: [ItemRequirement]
    let maxDurability: Int
    let craftingRecipe: CraftingRecipe?
 }

 struct CraftingRecipe: Codable {
    let id: UUID
    let name: String
    let description: String
    let materials: [CraftingMaterial]
    let resultTemplateId: UUID
    let resultQuantity: Int
    let skillRequired: String?
    let skillLevel: Int
    let craftingTime: TimeInterval
 }

 struct CraftingMaterial: Codable {
    let templateId: UUID
    let quantity: Int
    let name: String
 }

 struct StatBuff {
    let stat: ItemStat.StatType
    let amount: Int
    let duration: TimeInterval
 }

 // MARK: - Item Template Library
 class ItemTemplateLibrary {
    static let shared = ItemTemplateLibrary()
    
    private var templates: [UUID: ItemTemplate] = [:]
    
    private init() {
        loadDefaultTemplates()
    }
    
    func getTemplate(_ id: UUID) -> ItemTemplate? {
        return templates[id]
    }
    
    func getStartingItems() -> [ItemTemplate] {
        return Array(templates.values.prefix(5))
    }
    
    private func loadDefaultTemplates() {
        // Create some default item templates
        let basicSword = ItemTemplate(
            id: UUID(),
            name: "Basic Sword",
            description: "A simple iron sword for beginning adventurers",
            category: .equipment,
            rarity: .common,
            weight: 2.5,
            value: 100,
            iconAssetId: nil,
            meshAssetId: nil,
            isStackable: false,
            isEquippable: true,
            equipSlot: .mainHand,
            stats: [ItemStat(type: .attack, value: 10)],
            effects: [],
            requirements: [ItemRequirement(type: .level, value: 1)],
            maxDurability: 100,
            craftingRecipe: nil
        )
        
        let healthPotion = ItemTemplate(
            id: UUID(),
            name: "Health Potion",
            description: "Restores 50 health points when consumed",
            category: .consumable,
            rarity: .common,
            weight: 0.5,
            value: 25,
            iconAssetId: nil,
            meshAssetId: nil,
            isStackable: true,
            isEquippable: false,
            equipSlot: nil,
            stats: [],
            effects: [ItemEffect(type: .healHealth(amount: 50), duration: 0, description: "Heals 50 HP")],
            requirements: [],
            maxDurability: 1,
            craftingRecipe: nil
        )
        
        templates[basicSword.id] = basicSword
        templates[healthPotion.id] = healthPotion
    }
 }

 // MARK: - Persistence Manager
 class InventoryPersistenceManager {
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    
    init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    func saveInventory(_ items: [InventoryItem]) async throws {
        let url = documentsDirectory.appendingPathComponent("inventory.json")
        let data = try JSONEncoder().encode(items)
        try data.write(to: url)
    }
    
    func loadInventory() async throws -> [InventoryItem] {
        let url = documentsDirectory.appendingPathComponent("inventory.json")
        
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([InventoryItem].self, from: data)
    }
 }

 // MARK: - Error Types
 enum InventoryError: Error, LocalizedError {
    case inventoryFull
    case tooHeavy
    case itemNotFound
    case cannotEquip
    case cannotUse
    case cannotRepair
    case cannotEnhance
    case insufficientMaterials
    case templateNotFound
    
    var errorDescription: String? {
        switch self {
        case .inventoryFull:
            return "Inventory is full"
        case .tooHeavy:
            return "Item is too heavy to carry"
        case .itemNotFound:
            return "Item not found"
        case .cannotEquip:
            return "Item cannot be equipped"
        case .cannotUse:
            return "Item cannot be used"
        case .cannotRepair:
            return "Item cannot be repaired"
        case .cannotEnhance:
            return "Item cannot be enhanced"
        case .insufficientMaterials:
            return "Insufficient materials for crafting"
        case .templateNotFound:
            return "Item template not found"
        }
    }
 }

 // MARK: - Notification Names
 extension Notification.Name {
    static let healPlayer = Notification.Name("healPlayer")
    static let restorePlayerMana = Notification.Name("restorePlayerMana")
    static let applyStatBuff = Notification.Name("applyStatBuff")
    static let grantTemporaryAbility = Notification.Name("grantTemporaryAbility")
 }
