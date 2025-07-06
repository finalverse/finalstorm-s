//
// File Path: Core/Avatar/AvatarSystem.swift
// Description: Core avatar management and control system
// Handles avatar creation, customization, animation, and behavior
//

import Foundation
import RealityKit
import Combine

@MainActor
class AvatarSystem: ObservableObject {
    // MARK: - Published Properties
    @Published var currentAvatar: AvatarEntity?
    @Published var avatarState: AvatarState = .idle
    @Published var avatarHealth: Float = 100.0
    @Published var avatarEnergy: Float = 100.0
    @Published var avatarLevel: Int = 1
    @Published var avatarExperience: Float = 0
    
    // MARK: - Private Properties
    private let animationSystem: AnimationSystem
    private let appearanceManager: AppearanceManager
    private let avatarPhysics: AvatarPhysicsController
    private let avatarInventory: AvatarInventoryManager
    
    private var movementController: MovementController?
    private var stateUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Avatar State
    enum AvatarState {
        case idle
        case walking
        case running
        case jumping
        case flying
        case swimming
        case sitting
        case dancing
        case combat
        case crafting
        case dead
    }
    
    // MARK: - Initialization
    init() {
        self.animationSystem = AnimationSystem()
        self.appearanceManager = AppearanceManager()
        self.avatarPhysics = AvatarPhysicsController()
        self.avatarInventory = AvatarInventoryManager()
        
        setupBindings()
    }
    
    // MARK: - Setup
    func initialize() async {
        await animationSystem.loadAnimations()
        await appearanceManager.loadAppearanceData()
        
        // Start state monitoring
        startStateMonitoring()
    }
    
    func start() async {
        stateUpdateTimer?.fire()
    }
    
    private func setupBindings() {
        // Bind avatar state changes to animation system
        $avatarState
            .sink { [weak self] state in
                self?.animationSystem.transitionToState(state)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Avatar Creation
    func createAvatar(with config: AvatarConfiguration) async throws -> AvatarEntity {
        // Create base avatar entity
        let avatar = AvatarEntity()
        
        // Apply appearance
        await appearanceManager.applyAppearance(config.appearance, to: avatar)
        
        // Setup physics
        avatarPhysics.setupPhysics(for: avatar)
        
        // Setup animations
        animationSystem.setupAnimations(for: avatar)
        
        // Initialize movement controller
        movementController = MovementController(avatar: avatar)
        
        // Set as current avatar
        currentAvatar = avatar
        
        // Apply initial stats
        applyInitialStats(from: config)
        
        return avatar
    }
    
    private func applyInitialStats(from config: AvatarConfiguration) {
        avatarLevel = config.startingLevel
        avatarHealth = config.baseHealth
        avatarEnergy = config.baseEnergy
        avatarExperience = 0
    }
    
    // MARK: - Avatar Movement
    enum MovementModifier {
        case normal
        case boost
    }

    func moveAvatar(direction: SIMD3<Float>, speed: Float = 1.0, modifier: MovementModifier = .normal) {
        guard let avatar = currentAvatar,
              let controller = movementController else { return }

        let finalSpeed = (modifier == .boost) ? speed * 2.0 : speed

        if finalSpeed == 0 {
            avatarState = .idle
        } else if finalSpeed < 0.5 {
            avatarState = .walking
        } else {
            avatarState = .running
        }

        controller.move(direction: direction, speed: finalSpeed)
    }
    
    func triggerJumpEffect() {
        // Placeholder for VFX or sound
        print("Jump effect triggered")
    }

    func triggerFlightEffect() {
        // Placeholder for VFX or sound
        print("Flight effect triggered")
    }

    func jumpAvatar() {
        guard avatarState != .jumping && avatarState != .flying else { return }
        avatarState = .jumping
        movementController?.jump()
        triggerJumpEffect()
        // Return to previous state after jump
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.avatarState == .jumping {
                self?.avatarState = .idle
            }
        }
    }

    func toggleFlying() {
        if avatarState == .flying {
            avatarState = .idle
            movementController?.setFlying(false)
        } else {
            avatarState = .flying
            movementController?.setFlying(true)
            triggerFlightEffect()
        }
    }
    
    func ascendWhileFlying() {
        movementController?.ascend()
    }
    
    func descendWhileFlying() {
        movementController?.descend()
    }
    
    // MARK: - Avatar Interaction
    func interactWithObject(_ object: Entity) {
        // Determine interaction type
        if let interactable = object as? InteractableEntity {
            switch interactable.interactionType {
            case .pickup:
                pickupItem(interactable)
            case .activate:
                activateObject(interactable)
            case .talk:
                startConversation(with: interactable)
            case .craft:
                openCraftingInterface(with: interactable)
            }
        }
    }
    
    private func pickupItem(_ item: InteractableEntity) {
        if avatarInventory.canAddItem(item) {
            avatarInventory.addItem(item)
            item.removeFromParent()
            
            // Play pickup animation
            animationSystem.playOneShot(.pickup)
        }
    }
    
    private func activateObject(_ object: InteractableEntity) {
        object.activate()
        animationSystem.playOneShot(.interact)
    }
    
    private func startConversation(with npc: InteractableEntity) {
        avatarState = .idle
        // Trigger conversation UI
        NotificationCenter.default.post(
            name: .startConversation,
            object: nil,
            userInfo: ["npc": npc]
        )
    }
    
    private func openCraftingInterface(with station: InteractableEntity) {
        avatarState = .crafting
        // Open crafting UI
        NotificationCenter.default.post(
            name: .openCrafting,
            object: nil,
            userInfo: ["station": station]
        )
    }
    
    // MARK: - Avatar Customization
    func updateAppearance(_ appearance: AvatarAppearance) async {
        guard let avatar = currentAvatar else { return }
        
        await appearanceManager.updateAppearance(appearance, for: avatar)
        
        // Save appearance preferences
        saveAvatarPreferences()
    }
    
    func equipItem(_ item: EquipmentItem, slot: EquipmentSlot) {
        guard let avatar = currentAvatar else { return }
        
        // Update visual
        appearanceManager.equipItem(item, on: avatar, slot: slot)
        
        // Update stats
        applyEquipmentStats(item)
        
        // Play equip animation
        animationSystem.playOneShot(.equip)
    }
    
    private func applyEquipmentStats(_ item: EquipmentItem) {
        // Apply item bonuses
        avatarHealth = min(avatarHealth + item.healthBonus, getMaxHealth())
        avatarEnergy = min(avatarEnergy + item.energyBonus, getMaxEnergy())
    }
    
    // MARK: - Avatar Stats
    func takeDamage(_ amount: Float) {
        avatarHealth = max(0, avatarHealth - amount)
        
        if avatarHealth == 0 {
            avatarState = .dead
            handleDeath()
        } else {
            // Play hurt animation
            animationSystem.playOneShot(.hurt)
        }
    }
    
    func heal(_ amount: Float) {
        avatarHealth = min(avatarHealth + amount, getMaxHealth())
        
        // Visual feedback
        animationSystem.playOneShot(.heal)
    }
    
    func useEnergy(_ amount: Float) -> Bool {
        if avatarEnergy >= amount {
            avatarEnergy -= amount
            return true
        }
        return false
    }
    
    func gainExperience(_ amount: Float) {
        avatarExperience += amount
        
        // Check for level up
        while avatarExperience >= getExperienceForNextLevel() {
            levelUp()
        }
    }
    
    private func levelUp() {
        avatarLevel += 1
        avatarExperience -= getExperienceForNextLevel()
        
        // Increase stats
        let healthIncrease: Float = 10
        let energyIncrease: Float = 5
        
        avatarHealth = getMaxHealth() + healthIncrease
        avatarEnergy = getMaxEnergy() + energyIncrease
        
        // Visual feedback
        animationSystem.playOneShot(.levelUp)
        
        // Notify UI
        NotificationCenter.default.post(name: .avatarLevelUp, object: nil)
    }
    
    private func getMaxHealth() -> Float {
        return 100 + Float(avatarLevel - 1) * 10
    }
    
    private func getMaxEnergy() -> Float {
        return 100 + Float(avatarLevel - 1) * 5
    }
    
    private func getExperienceForNextLevel() -> Float {
        return Float(avatarLevel * 100)
    }
    
    // MARK: - State Monitoring
    private func startStateMonitoring() {
        stateUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateAvatarState()
        }
    }
    
    private func updateAvatarState() {
        // Regenerate energy over time
        if avatarState == .idle || avatarState == .sitting {
            avatarEnergy = min(avatarEnergy + 1, getMaxEnergy())
        }
        
        // Check for state-specific updates
        switch avatarState {
        case .swimming:
            // Consume energy while swimming
            if !useEnergy(0.5) {
                // Exit water if no energy
                avatarState = .idle
            }
        case .flying:
            // Consume energy while flying
            if !useEnergy(1.0) {
                toggleFlying()
            }
        case .combat:
            // Combat-specific updates
            break
        default:
            break
        }
    }
    
    // MARK: - Death Handling
    private func handleDeath() {
        // Stop all animations
        animationSystem.stopAllAnimations()
        
        // Play death animation
        animationSystem.playOneShot(.death)
        
        // Notify game systems
        NotificationCenter.default.post(name: .avatarDied, object: nil)
        
        // Schedule respawn
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.respawn()
        }
    }
    
    private func respawn() {
        // Reset stats
        avatarHealth = getMaxHealth() * 0.5
        avatarEnergy = getMaxEnergy() * 0.5
        avatarState = .idle
        
        // Move to spawn point
        currentAvatar?.position = SIMD3<Float>(0, 0, 0)
        
        // Play respawn effect
        animationSystem.playOneShot(.respawn)
    }
    
    // MARK: - Persistence
    private func saveAvatarPreferences() {
        guard let avatar = currentAvatar else { return }
        
        let preferences = AvatarPreferences(
            appearance: appearanceManager.getCurrentAppearance(),
            level: avatarLevel,
            experience: avatarExperience
        )
        
        // Save to user defaults or cloud
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: "avatarPreferences")
        }
    }
    
    func loadAvatarPreferences() -> AvatarPreferences? {
        guard let data = UserDefaults.standard.data(forKey: "avatarPreferences"),
              let preferences = try? JSONDecoder().decode(AvatarPreferences.self, from: data) else {
            return nil
        }
        
        return preferences
    }
}

// MARK: - Supporting Types
struct AvatarConfiguration {
    let name: String
    let appearance: AvatarAppearance
    let startingLevel: Int
    let baseHealth: Float
    let baseEnergy: Float
    let startingClass: AvatarClass?
}

struct AvatarAppearance: Codable {
    var bodyType: BodyType
    var skinTone: SIMD3<Float>
    var hairStyle: HairStyle
    var hairColor: SIMD3<Float>
    var faceShape: FaceShape
    var eyeColor: SIMD3<Float>
    var height: Float
    var build: Float
}

enum BodyType: String, Codable, CaseIterable {
    case masculine
    case feminine
    case androgynous
}

enum HairStyle: String, Codable, CaseIterable {
    case short
    case medium
    case long
    case ponytail
    case mohawk
    case bald
    case curly
    case braided
}

enum FaceShape: String, Codable, CaseIterable {
    case round
    case oval
    case square
    case heart
    case diamond
}

enum AvatarClass: String, Codable {
    case warrior
    case mage
    case ranger
    case rogue
    case healer
    case bard
}

struct AvatarPreferences: Codable {
    let appearance: AvatarAppearance
    let level: Int
    let experience: Float
}

// MARK: - Movement Controller
class MovementController {
    weak var avatar: AvatarEntity?
    private var velocity = SIMD3<Float>.zero
    private var isFlying = false
    private var isGrounded = true
    
    init(avatar: AvatarEntity) {
        self.avatar = avatar
    }
    
    func move(direction: SIMD3<Float>, speed: Float) {
        guard let avatar = avatar else { return }
        
        let normalizedDirection = normalize(direction)
        let movement = normalizedDirection * speed * 0.1
        
        if isFlying {
            // Full 3D movement when flying
            avatar.position += movement
        } else {
            // Ground-based movement
            avatar.position.x += movement.x
            avatar.position.z += movement.z
            
            // Apply gravity if not grounded
            if !isGrounded {
                velocity.y -= 0.02 // Gravity
                avatar.position.y += velocity.y
            }
        }
    }
    
    func jump() {
        guard isGrounded else { return }
        
        velocity.y = 0.3
        isGrounded = false
    }
    
    func setFlying(_ flying: Bool) {
        isFlying = flying
        if flying {
            velocity.y = 0
        }
    }
    
    func ascend() {
        guard isFlying, let avatar = avatar else { return }
        avatar.position.y += 0.1
    }
    
    func descend() {
        guard isFlying, let avatar = avatar else { return }
        avatar.position.y -= 0.1
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let avatarLevelUp = Notification.Name("avatarLevelUp")
    static let avatarDied = Notification.Name("avatarDied")
    static let startConversation = Notification.Name("startConversation")
    static let openCrafting = Notification.Name("openCrafting")
}
