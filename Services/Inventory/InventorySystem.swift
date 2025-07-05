//
//  Services/Inventory/InventorySystem.swift
//  FinalStorm
//
//  Complete inventory management system for items, assets, and equipment
//  Handles item creation, modification, storage, crafting, and synchronization
//

import Foundation
import RealityKit
import Combine
import SwiftUI

@MainActor
class InventorySystem: ObservableObject {
   // MARK: - Published Properties
   @Published var items: [InventoryItem] = []
   @Published var selectedItems: Set<UUID> = []
   @Published var sortOrder: SortOrder = .name
   @Published var filterCategory: ItemCategory = .all
   @Published var searchText: String = ""
   @Published var isLoading: Bool = false
   @Published var operationInProgress: Bool = false
   @Published var lastError: InventoryError?
   
   // Inventory statistics
   @Published var totalValue: Int = 0
   @Published var totalWeight: Float = 0.0
   @Published var usedSlots: Int = 0
   
   private let assetManager: AssetManager
   private let itemRenderer: ItemRenderer
   private let persistenceManager: InventoryPersistenceManager
   private let craftingSystem: CraftingSystem
   private var cancellables = Set<AnyCancellable>()
   
   // Inventory limits and settings
   private let maxItems: Int = 1000
   private let maxWeight: Float = 100.0
   private let autoSaveInterval: TimeInterval = 30.0
   
   // MARK: - Sort Orders
   enum SortOrder: String, CaseIterable {
       case name = "Name"
       case type = "Type"
       case rarity = "Rarity"
       case dateAdded = "Date Added"
       case quantity = "Quantity"
       case value = "Value"
       case weight = "Weight"
   }
   
   // MARK: - Initialization
   init() {
       self.assetManager = AssetManager()
       self.itemRenderer = ItemRenderer(assetManager: assetManager)
       self.persistenceManager = InventoryPersistenceManager()
       self.craftingSystem = CraftingSystem()
       
       setupBindings()
       setupAutoSave()
       loadInventory()
   }
   
   private func setupBindings() {
       // Update statistics when items change
       $items
           .sink { [weak self] items in
               self?.updateStatistics(items)
           }
           .store(in: &cancellables)
       
       // Clear selection when filtering changes
       Publishers.CombineLatest3($filterCategory, $searchText, $sortOrder)
           .sink { [weak self] _, _, _ in
               self?.selectedItems.removeAll()
           }
           .store(in: &cancellables)
       
       // Clear errors after a delay
       $lastError
           .compactMap { $0 }
           .delay(for: .seconds(5), scheduler: RunLoop.main)
           .sink { [weak self] _ in
               self?.lastError = nil
           }
           .store(in: &cancellables)
   }
   
   private func setupAutoSave() {
       Timer.publish(every: autoSaveInterval, on: .main, in: .common)
           .autoconnect()
           .sink { [weak self] _ in
               Task {
                   await self?.saveInventory()
               }
           }
           .store(in: &cancellables)
   }
   
   private func updateStatistics(_ items: [InventoryItem]) {
       totalValue = items.reduce(0) { $0 + ($1.value * $1.quantity) }
       totalWeight = items.reduce(0) { $0 + ($1.weight * Float($1.quantity)) }
       usedSlots = items.count
   }
   
   // MARK: - Item Management
   func addItem(_ item: InventoryItem) throws {
       // Validation checks
       guard items.count < maxItems else {
           throw InventoryError.inventoryFull
       }
       
       let newWeight = item.weight * Float(item.quantity)
       guard totalWeight + newWeight <= maxWeight else {
           throw InventoryError.tooHeavy
       }
       
       // Check if stackable item already exists
       if item.isStackable,
          let existingIndex = items.firstIndex(where: { $0.templateId == item.templateId && !$0.isEquipped }) {
           items[existingIndex] = items[existingIndex].withUpdatedQuantity(
               items[existingIndex].quantity + item.quantity
           )
       } else {
           items.append(item)
       }
       
       // Preload assets for the new item
       Task {
           await preloadItemAssets([item])
       }
       
       // Notify observers
       NotificationCenter.default.post(
           name: .itemAdded,
           object: item
       )
   }
   
   func removeItem(_ itemId: UUID, quantity: Int = 1) throws {
       guard let index = items.firstIndex(where: { $0.id == itemId }) else {
           throw InventoryError.itemNotFound
       }
       
       let item = items[index]
       
       // Check if item is equipped and prevent removal
       if item.isEquipped && quantity >= item.quantity {
           throw InventoryError.cannotRemoveEquippedItem
       }
       
       if item.quantity <= quantity {
           items.remove(at: index)
       } else {
           items[index] = item.withUpdatedQuantity(item.quantity - quantity)
       }
       
       // Notify observers
       NotificationCenter.default.post(
           name: .itemRemoved,
           object: item
       )
   }
   
   func moveItem(_ itemId: UUID, to targetSlot: Int) {
       guard let sourceIndex = items.firstIndex(where: { $0.id == itemId }),
             targetSlot < items.count && targetSlot >= 0 else { return }
       
       let item = items.remove(at: sourceIndex)
       let adjustedTarget = targetSlot > sourceIndex ? targetSlot - 1 : targetSlot
       items.insert(item, at: adjustedTarget)
   }
   
   func updateItemQuantity(_ itemId: UUID, newQuantity: Int) throws {
       guard let index = items.firstIndex(where: { $0.id == itemId }) else {
           throw InventoryError.itemNotFound
       }
       
       guard newQuantity > 0 else {
           try removeItem(itemId, quantity: items[index].quantity)
           return
       }
       
       items[index] = items[index].withUpdatedQuantity(newQuantity)
   }
   
   // MARK: - Equipment Management
   func equipItem(_ itemId: UUID) throws {
       guard let index = items.firstIndex(where: { $0.id == itemId }) else {
           throw InventoryError.itemNotFound
       }
       
       let item = items[index]
       
       guard item.isEquippable else {
           throw InventoryError.cannotEquip
       }
       
       guard item.durability > 0 else {
           throw InventoryError.itemBroken
       }
       
       // Check requirements
       if !meetsRequirements(item.requirements) {
           throw InventoryError.requirementsNotMet
       }
       
       // Unequip conflicting items
       if let equipSlot = item.equipSlot {
           unequipItemsInSlot(equipSlot)
       }
       
       items[index] = item.withEquippedState(true)
       
       // Apply item effects
       applyItemEffects(item.effects, isEquipping: true)
       
       // Preload 3D model for equipped item
       Task {
           if let meshAssetId = item.meshAssetId {
               do {
                   _ = try await assetManager.loadMesh(meshAssetId)
               } catch {
                   print("Failed to preload mesh for equipped item: \(error)")
               }
           }
       }
       
       NotificationCenter.default.post(
           name: .itemEquipped,
           object: item
       )
   }
   
   func unequipItem(_ itemId: UUID) throws {
       guard let index = items.firstIndex(where: { $0.id == itemId }) else {
           throw InventoryError.itemNotFound
       }
       
       let item = items[index]
       
       guard item.isEquipped else {
           throw InventoryError.itemNotEquipped
       }
       
       items[index] = item.withEquippedState(false)
       
       // Remove item effects
       applyItemEffects(item.effects, isEquipping: false)
       
       NotificationCenter.default.post(
           name: .itemUnequipped,
           object: item
       )
   }
   
   private func unequipItemsInSlot(_ slot: EquipSlot) {
       for i in items.indices {
           if items[i].equipSlot == slot && items[i].isEquipped {
               items[i] = items[i].withEquippedState(false)
               applyItemEffects(items[i].effects, isEquipping: false)
               
               NotificationCenter.default.post(
                   name: .itemUnequipped,
                   object: items[i]
               )
           }
       }
   }
   
   private func meetsRequirements(_ requirements: [ItemRequirement]) -> Bool {
       for requirement in requirements {
           switch requirement.type {
           case .level:
               // Check player level (would need player system integration)
               // For now, assume requirements are met
               continue
           case .stat:
               // Check player stats
               continue
           case .skill:
               // Check player skills
               continue
           case .quest:
               // Check quest completion
               continue
           }
       }
       return true
   }
   
   // MARK: - Item Creation and Crafting
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
           enhancements: [],
           customData: [:]
       )
   }
   
   func craftItem(recipe: CraftingRecipe) async throws -> InventoryItem {
       operationInProgress = true
       defer { operationInProgress = false }
       
       do {
           // Validate materials
           try validateCraftingMaterials(recipe.materials)
           
           // Check crafting requirements
           if let skillRequired = recipe.skillRequired,
              !hasRequiredSkill(skillRequired, level: recipe.skillLevel) {
               throw InventoryError.insufficientSkill
           }
           
           // Consume materials
           try consumeCraftingMaterials(recipe.materials)
           
           // Create result item
           guard let resultTemplate = ItemTemplateLibrary.shared.getTemplate(recipe.resultTemplateId) else {
               throw InventoryError.templateNotFound
           }
           
           let resultItem = createItem(from: resultTemplate, quantity: recipe.resultQuantity)
           
           // Apply crafting quality bonus based on skill
           let qualityBonusItem = applyCraftingQualityBonus(resultItem, recipe: recipe)
           
           try addItem(qualityBonusItem)
           
           // Simulate crafting time
           if recipe.craftingTime > 0 {
               try await Task.sleep(nanoseconds: UInt64(recipe.craftingTime * 1_000_000_000))
           }
           
           NotificationCenter.default.post(
               name: .itemCrafted,
               object: CraftingResult(item: qualityBonusItem, recipe: recipe)
           )
           
           return qualityBonusItem
           
       } catch {
           lastError = error as? InventoryError ?? .operationFailed
           throw error
       }
   }
   
   private func validateCraftingMaterials(_ materials: [CraftingMaterial]) throws {
       for material in materials {
           let availableQuantity = items
               .filter { $0.templateId == material.templateId && !$0.isEquipped }
               .reduce(0) { $0 + $1.quantity }
           
           guard availableQuantity >= material.quantity else {
               throw InventoryError.insufficientMaterials
           }
       }
   }
   
   private func consumeCraftingMaterials(_ materials: [CraftingMaterial]) throws {
       for material in materials {
           try consumeMaterial(templateId: material.templateId, quantity: material.quantity)
       }
   }
   
   private func consumeMaterial(templateId: UUID, quantity: Int) throws {
       var remainingToConsume = quantity
       
       for i in items.indices.reversed() {
           if items[i].templateId == templateId && !items[i].isEquipped {
               let consumeFromThis = min(remainingToConsume, items[i].quantity)
               
               if items[i].quantity <= consumeFromThis {
                   items.remove(at: i)
               } else {
                   items[i] = items[i].withUpdatedQuantity(items[i].quantity - consumeFromThis)
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
   
   private func hasRequiredSkill(_ skill: String, level: Int) -> Bool {
       // Integration point with skill system
       return true // For now, assume player has required skills
   }
   
   private func applyCraftingQualityBonus(_ item: InventoryItem, recipe: CraftingRecipe) -> InventoryItem {
       // Apply quality bonuses based on crafting skill level
       // This could modify stats, durability, or add special effects
       var enhancedItem = item
       
       // Simulate skill-based quality improvement
       let skillLevel = 50 // Would get from player's skill system
       let qualityMultiplier = 1.0 + (Float(skillLevel) / 1000.0) // Small bonus based on skill
       
       // Enhance item stats
       let enhancedStats = item.stats.map { stat in
           ItemStat(type: stat.type, value: Int(Float(stat.value) * qualityMultiplier))
       }
       
       enhancedItem = enhancedItem.withUpdatedStats(enhancedStats)
       
       return enhancedItem
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
       applyItemEffects(item.effects, isEquipping: true)
       
       // Handle consumable items
       if item.category == .consumable {
           try removeItem(itemId, quantity: 1)
       }
       
       // Reduce durability for equipment
       if item.category == .equipment && item.durability > 0 {
           let newDurability = max(0, item.durability - 1)
           items[index] = item.withUpdatedDurability(newDurability)
           
           // Break item if durability reaches 0
           if newDurability <= 0 {
               items[index] = items[index].withBrokenState(true)
               
               // Auto-unequip broken items
               if item.isEquipped {
                   try unequipItem(itemId)
               }
           }
       }
       
       NotificationCenter.default.post(
           name: .itemUsed,
           object: item
       )
   }
   
   func repairItem(_ itemId: UUID, repairAmount: Int = 0) throws {
       guard let index = items.firstIndex(where: { $0.id == itemId }) else {
           throw InventoryError.itemNotFound
       }
       
       let item = items[index]
       
       guard item.category == .equipment else {
           throw InventoryError.cannotRepair
       }
       
       let actualRepairAmount = repairAmount > 0 ? repairAmount : item.maxDurability
       let newDurability = min(item.maxDurability, item.durability + actualRepairAmount)
       
       items[index] = item.withUpdatedDurability(newDurability).withBrokenState(false)
       
       NotificationCenter.default.post(
           name: .itemRepaired,
           object: items[index]
       )
   }
   
   func enhanceItem(_ itemId: UUID, enhancement: ItemEnhancement) throws {
       guard let index = items.firstIndex(where: { $0.id == itemId }) else {
           throw InventoryError.itemNotFound
       }
       
       let item = items[index]
       
       guard item.canBeEnhanced else {
           throw InventoryError.cannotEnhance
       }
       
       var enhancedItem = item
       enhancedItem.enhancements.append(enhancement)
       
       // Apply enhancement effects
       enhancedItem = applyEnhancementToItem(enhancedItem, enhancement)
       
       items[index] = enhancedItem
       
       NotificationCenter.default.post(
           name: .itemEnhanced,
           object: EnhancementResult(item: enhancedItem, enhancement: enhancement)
       )
   }
   
   private func applyItemEffects(_ effects: [ItemEffect], isEquipping: Bool) {
       for effect in effects {
           applyItemEffect(effect, isEquipping: isEquipping)
       }
   }
   
   private func applyItemEffect(_ effect: ItemEffect, isEquipping: Bool) {
       let multiplier: Float = isEquipping ? 1.0 : -1.0
       
       switch effect.type {
       case .healHealth(let amount):
           if isEquipping {
               NotificationCenter.default.post(
                   name: .healPlayer,
                   object: amount
               )
           }
           
       case .restoreMana(let amount):
           if isEquipping {
               NotificationCenter.default.post(
                   name: .restorePlayerMana,
                   object: amount
               )
           }
           
       case .buffStat(let stat, let amount, let duration):
           let effectiveAmount = Int(Float(amount) * multiplier)
           NotificationCenter.default.post(
               name: .applyStatBuff,
               object: StatBuff(stat: stat, amount: effectiveAmount, duration: duration)
           )
           
       case .grantAbility(let abilityId):
           NotificationCenter.default.post(
               name: isEquipping ? .grantTemporaryAbility : .removeTemporaryAbility,
               object: abilityId
           )
       }
   }
   
   private func applyEnhancementToItem(_ item: InventoryItem, _ enhancement: ItemEnhancement) -> InventoryItem {
       var enhancedItem = item
       
       switch enhancement.type {
       case .statBonus(let stat, let amount):
           // Add or update stat
           if let existingIndex = enhancedItem.stats.firstIndex(where: { $0.type == stat }) {
               let newValue = enhancedItem.stats[existingIndex].value + amount
               enhancedItem.stats[existingIndex] = ItemStat(type: stat, value: newValue)
           } else {
               enhancedItem.stats.append(ItemStat(type: stat, value: amount))
           }
           
       case .durabilityBonus(let amount):
           let newMaxDurability = enhancedItem.maxDurability + amount
           let newDurability = enhancedItem.durability + amount
           enhancedItem = enhancedItem
               .withUpdatedDurability(newDurability)
               .withUpdatedMaxDurability(newMaxDurability)
           
       case .specialEffect(let effect):
           enhancedItem.effects.append(effect)
       }
       
       return enhancedItem
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
               item.description.localizedCaseInsensitiveContains(searchText) ||
               item.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
               item.rarity.rawValue.localizedCaseInsensitiveContains(searchText)
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
       case .value:
           return items.sorted { $0.value > $1.value }
       case .weight:
           return items.sorted { $0.weight > $1.weight }
       }
   }
   
   // MARK: - Item Information Getters
   func getItemStats(_ itemId: UUID) -> [ItemStat] {
       guard let item = items.first(where: { $0.id == itemId }) else { return [] }
       return item.stats
   }
   
   func getItemEffects(_ itemId: UUID) -> [ItemEffect] {
       guard let item = items.first(where: { $0.id == itemId }) else { return [] }
       return item.effects
   }
   
   func getEquippedItems() -> [InventoryItem] {
       return items.filter { $0.isEquipped }
   }
   
   func getItemsByCategory(_ category: ItemCategory) -> [InventoryItem] {
       return items.filter { $0.category == category }
   }
   
   func getItemsByRarity(_ rarity: ItemRarity) -> [InventoryItem] {
       return items.filter { $0.rarity == rarity }
   }
   
   func getBrokenItems() -> [InventoryItem] {
       return items.filter { $0.isBroken }
   }
   
   func getRepairableItems() -> [InventoryItem] {
       return items.filter { $0.category == .equipment && $0.durability < $0.maxDurability }
   }
   
   // MARK: - Asset Management
   private func preloadItemAssets(_ items: [InventoryItem]) async {
       await assetManager.preloadItemAssets(items)
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
   
   func generateItemPreview(_ itemId: UUID) async -> ModelEntity? {
       guard let item = items.first(where: { $0.id == itemId }) else { return nil }
       return await itemRenderer.generate3DPreview(for: item)
   }
   
   // MARK: - Persistence
   private func loadInventory() {
       Task {
           isLoading = true
           do {
               let loadedItems = try await persistenceManager.loadInventory()
               items = loadedItems
               
               // Preload assets for equipped items
               let equippedItems = items.filter { $0.isEquipped }
               await preloadItemAssets(equippedItems)
               
           } catch {
               print("Failed to load inventory: \(error)")
               items = createDefaultItems()
               lastError = .loadFailed
           }
           isLoading = false
       }
   }
   
   private func saveInventory() async {
       do {
           try await persistenceManager.saveInventory(items)
       } catch {
           print("Failed to save inventory: \(error)")
           lastError = .saveFailed
       }
   }
   
   func forceSave() async {
       await saveInventory()
   }
   
   private func createDefaultItems() -> [InventoryItem] {
       let templates = ItemTemplateLibrary.shared.getStartingItems()
       return templates.map { createItem(from: $0) }
   }
   
   // MARK: - Bulk Operations
   func selectAllVisibleItems() {
       selectedItems = Set(filteredAndSortedItems.map { $0.id })
   }
   
   func clearSelection() {
       selectedItems.removeAll()
   }
   
   func deleteSelectedItems() throws {
       operationInProgress = true
       defer { operationInProgress = false }
       
       for itemId in selectedItems {
           if let item = items.first(where: { $0.id == itemId }),
              !item.isEquipped {
               try removeItem(itemId, quantity: item.quantity)
           }
       }
       selectedItems.removeAll()
   }
   
   func getInventoryUtilization() -> InventoryUtilization {
       return InventoryUtilization(
           usedSlots: usedSlots,
           maxSlots: maxItems,
           usedWeight: totalWeight,
           maxWeight: maxWeight,
           totalValue: totalValue,
           itemsByCategory: Dictionary(grouping: items, by: { $0.category })
               .mapValues { $0.count },
           itemsByRarity: Dictionary(grouping: items, by: { $0.rarity })
               .mapValues { $0.count }
       )
   }
}

// MARK: - Supporting Types

struct InventoryUtilization {
   let usedSlots: Int
   let maxSlots: Int
   let usedWeight: Float
   let maxWeight: Float
   let totalValue: Int
   let itemsByCategory: [ItemCategory: Int]
   let itemsByRarity: [ItemRarity: Int]
   
   var slotUtilization: Float {
       return Float(usedSlots) / Float(maxSlots)
   }
   
   var weightUtilization: Float {
       return usedWeight / maxWeight
   }
}

struct CraftingResult {
   let item: InventoryItem
   let recipe: CraftingRecipe
}

struct EnhancementResult {
   let item: InventoryItem
   let enhancement: ItemEnhancement
}

struct StatBuff {
   let stat: ItemStat.StatType
   let amount: Int
   let duration: TimeInterval
}

// MARK: - Crafting System

class CraftingSystem {
   private var recipes: [UUID: CraftingRecipe] = [:]
   
   init() {
       loadDefaultRecipes()
   }
   
   func getAvailableRecipes(for items: [InventoryItem]) -> [CraftingRecipe] {
       return recipes.values.filter { recipe in
           canCraftRecipe(recipe, with: items)
       }
   }
   
   func canCraftRecipe(_ recipe: CraftingRecipe, with items: [InventoryItem]) -> Bool {
       for material in recipe.materials {
           let availableQuantity = items
               .filter { $0.templateId == material.templateId && !$0.isEquipped }
               .reduce(0) { $0 + $1.quantity }
           
           if availableQuantity < material.quantity {
               return false
           }
       }
       return true
   }
   
   private func loadDefaultRecipes() {
       // Load default crafting recipes
       let healthPotionRecipe = CraftingRecipe(
           id: UUID(),
           name: "Health Potion",
           description: "Restores health when consumed",
           materials: [
               CraftingMaterial(templateId: UUID(), quantity: 2, name: "Herb")
           ],
           resultTemplateId: UUID(),
           resultQuantity: 1,
           skillRequired: "Alchemy",
           skillLevel: 10,
           craftingTime: 3.0
       )
       
       recipes[healthPotionRecipe.id] = healthPotionRecipe
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
   case cannotRemoveEquippedItem
   case itemNotEquipped
   case itemBroken
   case requirementsNotMet
   case insufficientMaterials
   case insufficientSkill
   case templateNotFound
   case operationFailed
   case loadFailed
   case saveFailed
   
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
       case .cannotRemoveEquippedItem:
           return "Cannot remove equipped item"
       case .itemNotEquipped:
           return "Item is not equipped"
       case .itemBroken:
           return "Item is broken and cannot be used"
       case .requirementsNotMet:
           return "Requirements not met to equip this item"
       case .insufficientMaterials:
           return "Insufficient materials for crafting"
       case .insufficientSkill:
           return "Insufficient skill level for crafting"
       case .templateNotFound:
           return "Item template not found"
       case .operationFailed:
           return "Operation failed"
       case .loadFailed:
           return "Failed to load inventory"
       case .saveFailed:
           return "Failed to save inventory"
       }
   }
}

// MARK: -
