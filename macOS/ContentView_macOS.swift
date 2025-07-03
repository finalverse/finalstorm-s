//
//  ContentView_macOS.swift
//  FinalStorm-S
//
//  macOS-specific implementation with desktop features
//

import SwiftUI
import RealityKit
import AppKit

struct ContentView_macOS: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @EnvironmentObject var finalverseServices: FinalverseServicesManager
    
    @State private var showSidebar = true
    @State private var selectedPanel: SidebarPanel = .world
    @State private var showInventory = false
    @State private var cameraMode: CameraMode = .thirdPerson
    
    var body: some View {
        HSplitView {
            // Sidebar
            if showSidebar {
                SidebarView(selectedPanel: $selectedPanel)
                    .frame(width: 250)
            }
            
            // Main content
            ZStack {
                // World view
                MacWorldView(cameraMode: $cameraMode)
                    .overlay(alignment: .topTrailing) {
                        // Mini map
                        MiniMapView()
                            .frame(width: 200, height: 200)
                            .padding()
                    }
                    .overlay(alignment: .bottom) {
                        // Action bar
                        ActionBarView()
                            .padding()
                    }
                
                // Floating windows
                if showInventory {
                    FloatingWindow(title: "Inventory", isOpen: $showInventory) {
                        InventoryView()
                    }
                    .frame(width: 400, height: 500)
                    .position(x: 200, y: 300)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                
                Picker("Camera", selection: $cameraMode) {
                    ForEach(CameraMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { showInventory.toggle() }) {
                    Image(systemName: "bag")
                }
                
                Button(action: { /* Show map */ }) {
                    Image(systemName: "map")
                }
                
                Button(action: { /* Show settings */ }) {
                    Image(systemName: "gear")
                }
            }
        }
        .onAppear {
            setupMacOS()
        }
    }
    
    private func setupMacOS() {
        // Configure for macOS
        NSApplication.shared.presentationOptions = [.autoHideMenuBar]
        
        // Start world loading
        Task {
            await startFirstHourExperience()
        }
    }
    
    private func startFirstHourExperience() async {
        // Similar to iOS implementation
        do {
            try await worldManager.loadWorld(
                named: "Terra Nova",
                server: ServerInfo.finalverseLocal
            )
            
            let profile = UserProfile.default
            let avatar = try await avatarSystem.createLocalAvatar(profile: profile)
            avatar.position = SIMD3<Float>(128, 50, 128)
            
            await finalverseServices.echoEngine.summonEcho(.lumi, at: avatar.position + [2, 0, 0])
            
            appState.isLoggedIn = true
        } catch {
            print("Failed to start: \(error)")
        }
    }
}

// MARK: - macOS World View
struct MacWorldView: NSViewRepresentable {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @Binding var cameraMode: CameraMode
    
    func makeNSView(context: Context) -> RealityView {
        let realityView = RealityView()
        
        // Configure view
        realityView.environment.background = .color(.black)
        
        // Setup coordinator
        context.coordinator.realityView = realityView
        context.coordinator.setupScene()
        context.coordinator.setupInput()
        
        return realityView
    }
    
    func updateNSView(_ nsView: RealityView, context: Context) {
        context.coordinator.updateCamera(mode: cameraMode)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(worldManager: worldManager, avatarSystem: avatarSystem)
    }
    
    class Coordinator: NSObject {
        let worldManager: WorldManager
        let avatarSystem: AvatarSystem
        weak var realityView: RealityView?
        
        private var cameraController: DesktopCameraController?
        private var inputController: DesktopInputController?
        
        init(worldManager: WorldManager, avatarSystem: AvatarSystem) {
            self.worldManager = worldManager
            self.avatarSystem = avatarSystem
            super.init()
        }
        
        func setupScene() {
            guard let view = realityView else { return }
            
            // Create anchor for world
            let worldAnchor = AnchorEntity(world: .zero)
            view.scene.addAnchor(worldAnchor)
            
            // Setup camera
            cameraController = DesktopCameraController(view: view)
            
            // Add initial content
            loadWorldContent()
        }
        
        func setupInput() {
            guard let view = realityView else { return }
            
            inputController = DesktopInputController(view: view)
            inputController?.onMove = { [weak self] position in
                self?.avatarSystem.moveAvatar(to: position, rotation: .identity)
            }
            inputController?.onInteract = { [weak self] entity in
                self?.handleInteraction(with: entity)
            }
        }
        
        func updateCamera(mode: CameraMode) {
            cameraController?.setCameraMode(mode)
        }
        
        private func loadWorldContent() {
            // Load visible entities from world manager
            for entity in worldManager.visibleEntities {
                realityView?.scene.addAnchor(AnchorEntity(world: entity.position))
            }
        }
        
        private func handleInteraction(with entity: Entity) {
            // Handle entity interactions
            if let echo = entity as? EchoEntity {
                Task {
                    await avatarSystem.performSongweaving(.greeting, target: echo)
                }
            }
        }
    }
}

// MARK: - Desktop-specific Components
class RealityView: NSView {
    let arView: ARView
    
    override init(frame frameRect: NSRect) {
        self.arView = ARView(frame: frameRect)
        super.init(frame: frameRect)
        
        // Configure AR view for desktop
        arView.environment.background = .color(.black)
        arView.debugOptions = []
        
        addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: topAnchor),
            arView.leadingAnchor.constraint(equalTo: leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var scene: Scene {
        arView.scene
    }
    
    var environment: ARView.Environment {
        arView.environment
    }
}

class DesktopCameraController {
    private let view: RealityView
    private var cameraEntity: Entity?
    private var cameraMode: CameraMode = .thirdPerson
    private var targetEntity: Entity?
    
    init(view: RealityView) {
        self.view = view
        setupCamera()
    }
    
    private func setupCamera() {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(camera)
        view.scene.addAnchor(anchor)
        
        cameraEntity = camera
        updateCameraPosition()
    }
    
    func setCameraMode(_ mode: CameraMode) {
        cameraMode = mode
        updateCameraPosition()
    }
    
    func setTarget(_ entity: Entity) {
        targetEntity = entity
        updateCameraPosition()
    }
    
    private func updateCameraPosition() {
        guard let camera = cameraEntity else { return }
        
        switch cameraMode {
        case .firstPerson:
            if let target = targetEntity {
                camera.position = target.position + [0, 1.8, 0]
                camera.orientation = target.orientation
            }
            
        case .thirdPerson:
            if let target = targetEntity {
                let offset = SIMD3<Float>(0, 5, 10)
                camera.position = target.position + offset
                camera.look(at: target.position, from: camera.position, relativeTo: nil)
            }
            
        case .freeCam:
            // Allow free movement
            break
            
        case .tactical:
            camera.position = [0, 20, 0]
            camera.look(at: [0, 0, 0], from: camera.position, relativeTo: nil)
        }
    }
}

class DesktopInputController: NSObject {
    private let view: RealityView
    var onMove: ((SIMD3<Float>) -> Void)?
    var onInteract: ((Entity) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    init(view: RealityView) {
        self.view = view
        super.init()
        setupTracking()
        setupGestures()
    }
    
    private func setupTracking() {
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited
        ]
        
        trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        view.addTrackingArea(trackingArea!)
    }
    
    private func setupGestures() {
        // Click gesture
        let clickGesture = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleClick(_:))
        )
        view.addGestureRecognizer(clickGesture)
        
        // Right click for context menu
        let rightClickGesture = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleRightClick(_:))
        )
        rightClickGesture.buttonMask = 0x02
        view.addGestureRecognizer(rightClickGesture)
    }
    
    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: view)
        let arLocation = CGPoint(x: location.x, y: view.bounds.height - location.y)
        
        let results = view.arView.hitTest(arLocation)
        
        if let hit = results.first {
            onInteract?(hit.entity)
        } else if let raycast = view.arView.raycast(
            from: arLocation,
            allowing: .estimatedPlane,
            alignment: .horizontal
        ).first {
            let worldPos = raycast.worldTransform.columns.3.xyz
            onMove?(worldPos)
        }
    }
    
    @objc private func handleRightClick(_ gesture: NSClickGestureRecognizer) {
        // Show context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Inspect", action: #selector(inspect), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Interact", action: #selector(interact), keyEquivalent: ""))
        
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: view)
    }
    
    @objc private func inspect() {
        // Inspect entity
    }
    
    @objc private func interact() {
        // Interact with entity
    }
}

// MARK: - UI Components
struct SidebarView: View {
    @Binding var selectedPanel: SidebarPanel
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var finalverseServices: FinalverseServicesManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User info
            UserInfoSection()
                .padding()
            
            Divider()
            
            // Panel selection
            List(SidebarPanel.allCases, selection: $selectedPanel) { panel in
                Label(panel.rawValue, systemImage: panel.icon)
                    .tag(panel)
            }
            .listStyle(SidebarListStyle())
            
            Divider()
            
            // Panel content
            ScrollView {
                switch selectedPanel {
                case .world:
                    WorldInfoPanel()
                case .social:
                    SocialPanel()
                case .echoes:
                    EchoesPanel()
                case .quests:
                    QuestsPanel()
                case .services:
                    ServicesPanel()
                }
            }
            .padding()
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct UserInfoSection: View {
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading) {
                    Text("Songweaver")
                        .font(.headline)
                    Text("Level \(Int(avatarSystem.resonanceLevel.totalResonance / 100))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Resonance bars
            VStack(spacing: 5) {
                ResonanceBar(
                    type: "Creative",
                    value: avatarSystem.resonanceLevel.creativeResonance,
                    color: .purple
                )
                ResonanceBar(
                    type: "Exploration",
                    value: avatarSystem.resonanceLevel.explorationResonance,
                    color: .blue
                )
                ResonanceBar(
                    type: "Restoration",
                    value: avatarSystem.resonanceLevel.restorationResonance,
                    color: .green
                )
            }
        }
    }
}

struct ResonanceBar: View {
    let type: String
    let value: Float
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(type)
                    .font(.caption2)
                Spacer()
                Text("\(Int(value))")
                    .font(.caption2)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: CGFloat(value / 100) * geometry.size.width, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

struct FloatingWindow<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    let content: Content
    
    @State private var offset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Button(action: { isOpen = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                    }
            )
            
            Divider()
            
            // Content
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 10)
        .offset(offset)
    }
}

// MARK: - Supporting Types
enum SidebarPanel: String, CaseIterable, Identifiable {
    case world = "World"
    case social = "Social"
    case echoes = "Echoes"
    case quests = "Quests"
    case services = "Services"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .world: return "globe"
        case .social: return "person.2"
        case .echoes: return "sparkles"
        case .quests: return "scroll"
        case .services: return "server.rack"
        }
    }
}

enum CameraMode: String, CaseIterable, Identifiable {
    case firstPerson = "First Person"
    case thirdPerson = "Third Person"
    case freeCam = "Free Camera"
    case tactical = "Tactical"
    
    var id: String { rawValue }
}

struct ActionBarView: View {
    @State private var abilities: [Ability] = Ability.defaultAbilities
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(abilities) { ability in
                AbilityButton(ability: ability)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
}

struct AbilityButton: View {
    let ability: Ability
    @State private var cooldownProgress: Double = 0
    
    var body: some View {
        Button(action: { useAbility() }) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                Image(systemName: ability.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                
                if cooldownProgress > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 50, height: 50 * cooldownProgress)
                        .animation(.linear(duration: ability.cooldown), value: cooldownProgress)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(ability.name)
    }
    
    private func useAbility() {
        // Use ability
        cooldownProgress = 1.0
        
        withAnimation(.linear(duration: ability.cooldown)) {
            cooldownProgress = 0
        }
    }
}

struct Ability: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let cooldown: Double
    
    static let defaultAbilities = [
        Ability(name: "Restoration Melody", icon: "leaf.fill", cooldown: 3.0),
        Ability(name: "Exploration Song", icon: "location.fill", cooldown: 5.0),
        Ability(name: "Creation Harmony", icon: "sparkles", cooldown: 10.0),
        Ability(name: "Echo Call", icon: "waveform", cooldown: 30.0),
        Ability(name: "Silence Shield", icon: "shield.fill", cooldown: 15.0)
    ]
}

// MARK: - Panel Views
struct WorldInfoPanel: View {
    @EnvironmentObject var worldManager: WorldManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("World Status")
                .font(.headline)
            
            if let world = worldManager.currentWorld {
                InfoRow(label: "World", value: world.name)
                InfoRow(label: "Server", value: world.server.name)
                
                if let region = worldManager.currentRegion {
                    InfoRow(label: "Region", value: region.name)
                    InfoRow(label: "Coordinates", value: "\(region.coordinate.x), \(region.coordinate.z)")
                    
                    // Harmony meter
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Regional Harmony")
                            .font(.caption)
                        
                        ProgressView(value: Double(region.harmonyLevel), total: 2.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .accentColor(harmonyColor(for: region.harmonyLevel))
                    }
                }
            }
            
            Divider()
            
            // World metabolism
            Text("World Metabolism")
                .font(.headline)
            
            MetabolismView(metabolism: worldManager.worldMetabolism)
        }
    }
    
    private func harmonyColor(for level: Float) -> Color {
        if level > 1.5 {
            return .green
        } else if level > 1.0 {
            return .blue
        } else if level > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

struct MetabolismView: View {
    let metabolism: WorldMetabolism
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Harmony", systemImage: "music.note")
                Spacer()
                Text(String(format: "%.2f", metabolism.globalHarmony))
            }
            
            HStack {
                Label("Dissonance", systemImage: "waveform.path.ecg")
                Spacer()
                Text(String(format: "%.2f", metabolism.globalDissonance))
            }
            
            if metabolism.shouldTriggerEvent {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("World event imminent")
                        .font(.caption)
                }
                .padding(.top, 5)
            }
        }
    }
}

struct SocialPanel: View {
    @State private var onlinePlayers: [PlayerInfo] = []
    @State private var friends: [PlayerInfo] = []
    @State private var partyMembers: [PlayerInfo] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Party
            Section(header: Text("Party").font(.headline)) {
                if partyMembers.isEmpty {
                    Text("Not in a party")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(partyMembers) { player in
                        PlayerRow(player: player, showPartyOptions: true)
                    }
                }
            }
            
            Divider()
            
            // Friends online
            Section(header: Text("Friends Online").font(.headline)) {
                ForEach(friends.filter { $0.isOnline }) { friend in
                    PlayerRow(player: friend, showInvite: true)
                }
            }
            
            Divider()
            
            // Nearby players
            Section(header: Text("Nearby Players").font(.headline)) {
                ForEach(onlinePlayers) { player in
                    PlayerRow(player: player)
                }
            }
        }
    }
}

struct PlayerRow: View {
    let player: PlayerInfo
    var showPartyOptions: Bool = false
    var showInvite: Bool = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(player.isOnline ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading) {
                Text(player.displayName)
                    .font(.caption)
                Text("Lvl \(player.level)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if showPartyOptions {
                Button(action: {}) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Make Party Leader")
            }
            
            if showInvite {
                Button(action: {}) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(PlainButtonStyle())
                .help("Invite to Party")
            }
        }
        .padding(.vertical, 2)
    }
}

struct EchoesPanel: View {
    @EnvironmentObject var echoEngine: EchoEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("First Echoes")
                .font(.headline)
            
            ForEach(echoEngine.activeEchoes, id: \.id) { echo in
                EchoStatusView(echo: echo, state: echoEngine.echoStates[echo.id])
            }
            
            Divider()
            
            Text("Echo Abilities")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                EchoAbilityRow(
                    echo: "Lumi",
                    ability: "Illumination",
                    description: "Reveals hidden paths and secrets"
                )
                
                EchoAbilityRow(
                    echo: "KAI",
                    ability: "Analysis",
                    description: "Decodes ancient technologies"
                )
                
                EchoAbilityRow(
                    echo: "Terra",
                    ability: "Growth",
                    description: "Restores corrupted nature"
                )
                
                EchoAbilityRow(
                    echo: "Ignis",
                    ability: "Forge",
                    description: "Creates temporary equipment"
                )
            }
        }
    }
}

struct EchoStatusView: View {
    let echo: EchoEntity
    let state: EchoState?
    
    var body: some View {
        HStack {
            Circle()
                .fill(echoColor(for: echo.echoType))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(echo.echoName.prefix(1)))
                        .font(.headline)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading) {
                Text(echo.echoName)
                    .font(.caption)
                
                if let state = state {
                    HStack {
                        Text(state.activity.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Image(systemName: state.mood.icon)
                            .font(.caption2)
                            .foregroundColor(state.mood.color)
                    }
                }
            }
            
            Spacer()
            
            Button(action: { summonEcho(echo.echoType) }) {
                Image(systemName: "sparkles")
            }
            .buttonStyle(PlainButtonStyle())
            .help("Summon \(echo.echoName)")
        }
    }
    
    private func echoColor(for type: EchoType) -> Color {
        switch type {
        case .lumi: return .yellow
        case .kai: return .blue
        case .terra: return .green
        case .ignis: return .orange
        }
    }
    
    private func summonEcho(_ type: EchoType) {
        // Summon the echo
    }
}

struct EchoAbilityRow: View {
    let echo: String
    let ability: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(echo)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("•")
                    .foregroundColor(.secondary)
                Text(ability)
                    .font(.caption)
            }
            
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct QuestsPanel: View {
    @State private var activeQuests: [Quest] = []
    @State private var completedQuests: [Quest] = []
    @State private var selectedQuest: Quest?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Active Quests")
                .font(.headline)
            
            if activeQuests.isEmpty {
                Text("No active quests")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(activeQuests) { quest in
                    QuestRow(quest: quest, isSelected: selectedQuest?.id == quest.id)
                        .onTapGesture {
                            selectedQuest = quest
                        }
                }
            }
            
            if let selected = selectedQuest {
                Divider()
                
                QuestDetailView(quest: selected)
            }
        }
    }
}

struct QuestRow: View {
    let quest: Quest
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "scroll")
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading) {
                Text(quest.title)
                    .font(.caption)
                    .fontWeight(isSelected ? .medium : .regular)
                
                Text("\(quest.objectives.filter { $0.isCompleted }.count)/\(quest.objectives.count) objectives")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(5)
    }
}

struct QuestDetailView: View {
    let quest: Quest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(quest.title)
                .font(.headline)
            
            Text(quest.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Objectives:")
                .font(.caption)
                .fontWeight(.medium)
            
            ForEach(quest.objectives) { objective in
                HStack {
                    Image(systemName: objective.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(objective.isCompleted ? .green : .secondary)
                        .font(.caption)
                    
                    Text(objective.description)
                        .font(.caption)
                        .strikethrough(objective.isCompleted)
                }
            }
            
            if !quest.rewards.isEmpty {
                Text("Rewards:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.top, 5)
                
                ForEach(quest.rewards.indices, id: \.self) { index in
                    QuestRewardView(reward: quest.rewards[index])
                }
            }
        }
    }
}

struct QuestRewardView: View {
    let reward: QuestReward
    
    var body: some View {
        HStack {
            switch reward.type {
            case .resonance(let amount):
                Image(systemName: "sparkle")
                    .foregroundColor(.purple)
                Text("+\(Int(amount)) Resonance")
                
            case .item(let itemId):
                Image(systemName: "cube.fill")
                    .foregroundColor(.blue)
                Text("Item: \(itemId)")
                
            case .melody(let type):
                Image(systemName: "music.note")
                    .foregroundColor(.green)
                Text("New Melody: \(type)")
            }
        }
        .font(.caption2)
    }
}

struct ServicesPanel: View {
    @EnvironmentObject var finalverseServices: FinalverseServicesManager
    @State private var serviceStatuses: [ServiceStatus] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Finalverse Services")
                .font(.headline)
            
            ServiceStatusRow(
                name: "Song Engine",
                status: .connected,
                latency: 12
            )
            
            ServiceStatusRow(
                name: "Echo Engine",
                status: .connected,
                latency: 8
            )
            
            ServiceStatusRow(
                name: "AI Orchestra",
                status: .connected,
                latency: 45
            )
            
            ServiceStatusRow(
                name: "World Engine",
                status: .connected,
                latency: 15
            )
            
            ServiceStatusRow(
                name: "Symphony Engine",
                status: .connecting,
                latency: nil
            )
            
            Divider()
            
            Text("Service Metrics")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                MetricRow(label: "Active Players", value: "1,234")
                MetricRow(label: "World Events", value: "3")
                MetricRow(label: "Harmony Level", value: "1.24")
                MetricRow(label: "Server Load", value: "42%")
            }
        }
    }
}

struct ServiceStatusRow: View {
    let name: String
    let status: ServiceStatus.Status
    let latency: Int?
    
    var body: some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            
            Text(name)
                .font(.caption)
            
            Spacer()
            
            if let latency = latency {
                Text("\(latency)ms")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Supporting Types
struct PlayerInfo: Identifiable {
    let id = UUID()
    let displayName: String
    let level: Int
    let isOnline: Bool
}

struct ServiceStatus {
    enum Status {
        case connected
        case connecting
        case disconnected
        case error
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .connecting: return .yellow
            case .disconnected: return .gray
            case .error: return .red
            }
        }
    }
    
    let name: String
    let status: Status
    let latency: Int?
}

extension EchoState.EchoActivity {
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .moving: return "Moving"
        case .interacting: return "Interacting"
        case .teaching: return "Teaching"
        }
    }
}

extension EchoState.Mood {
    var icon: String {
        switch self {
        case .happy: return "face.smiling"
        case .neutral: return "face.smiling"
        case .concerned: return "exclamationmark.triangle"
        case .excited: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .happy: return .green
        case .neutral: return .gray
        case .concerned: return .orange
        case .excited: return .yellow
        }
    }
}
