//
// File Path: macOS/ContentView_macOS.swift
// Description: macOS-specific content view implementation
// This view provides the main interface for macOS devices
//

import SwiftUI
import RealityKit

struct ContentView_macOS: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @State private var selectedSidebarItem: SidebarItem? = .world
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    enum SidebarItem: String, CaseIterable, Identifiable {
        case world = "World"
        case inventory = "Inventory"
        case chat = "Chat"
        case map = "Map"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .world: return "globe"
            case .inventory: return "backpack"
            case .chat: return "message"
            case .map: return "map"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List(SidebarItem.allCases, selection: $selectedSidebarItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .navigationTitle("FinalStorm")
        } content: {
            // Detail view based on selection
            if let selectedItem = selectedSidebarItem {
                switch selectedItem {
                case .world:
                    WorldListView_macOS()
                case .inventory:
                    InventoryListView_macOS()
                case .chat:
                    ChatChannelListView()
                case .map:
                    MapOverviewView()
                case .settings:
                    SettingsCategoriesView()
                }
            }
        } detail: {
            // Main content area
            if let selectedItem = selectedSidebarItem {
                switch selectedItem {
                case .world:
                    WorldView_macOS()
                case .inventory:
                    InventoryDetailView()
                case .chat:
                    ChatDetailView()
                case .map:
                    DetailedMapView()
                case .settings:
                    SettingsDetailView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 600)
    }
}

// MARK: - World View for macOS
struct WorldView_macOS: View {
    @EnvironmentObject var worldManager: WorldManager
    @State private var cameraController = CameraController()
    @State private var showOverlay = true
    @State private var selectedEntity: Entity?
    @State private var cameraEntity: PerspectiveCamera? = nil
    @GestureState private var dragOffset = CGSize.zero
    @State private var cameraYaw: Float = 0
    @State private var cameraPitch: Float = 0
    @State private var cameraDistance: Float = 5.0
    @State private var reticleEntity: Entity?

    private let minCameraDistance: Float = 2.0
    private let maxCameraDistance: Float = 12.0
    
    var body: some View {
        ZStack {
            // Main 3D View
            RealityView { content in
                // Setup scene
                let scene = Entity()
                
                // Add world content
                if let worldEntity = await worldManager.createWorldEntity() {
                    scene.addChild(worldEntity)
                }

                // Add avatar to scene
                if let avatarEntity = await avatarSystem.createLocalAvatar() {
                    scene.addChild(avatarEntity)
                }
                
                // Setup lighting
                setupLighting(in: scene)
                
                // Add camera
                let cameraEntity = PerspectiveCamera()
                scene.addChild(cameraEntity)
                // Assign to state property
                self.cameraEntity = cameraEntity

                // Add teleportation reticle
                let reticle = Entity()
                let reticleMaterial = SimpleMaterial(color: .blue, isMetallic: false)
                reticle.components.set(ModelComponent(mesh: .generateSphere(radius: 0.05), materials: [reticleMaterial]))
                scene.addChild(reticle)
                self.reticleEntity = reticle

                // Set initial avatar position and camera follow
                avatarSystem.setAvatarPosition(SIMD3<Float>(0, 0, 0))
                cameraEntity.position = SIMD3<Float>(0, 2, 5)
                cameraEntity.look(at: SIMD3<Float>(0, 1, 0), from: cameraEntity.position, relativeTo: nil)
                
                content.add(scene)
                
            } update: { content in
                // Update world state
                worldManager.updateContent(content)
                avatarSystem.updateAvatar(in: content)
                if let avatar = avatarSystem.currentAvatar, let camera = cameraEntity {
                    let avatarPosition = avatar.position
                    
                    // Orbit camera around avatar using yaw and pitch
                    let radius = cameraDistance
                    
                    // Create offset vectors based on spherical coordinates
                    let offsetX = radius * cos(cameraPitch) * sin(cameraYaw)
                    let offsetY = radius * sin(cameraPitch)
                    let offsetZ = radius * cos(cameraPitch) * cos(cameraYaw)
                    
                    // Calculate target position by adding offset to avatar position, with vertical offset
                    let targetPosition = SIMD3<Float>(offsetX, offsetY + 2.0, offsetZ) + avatarPosition

                    // Smooth camera movement using linear interpolation (lerp)
                    let lerpFactor: Float = 0.1
                    camera.position = mix(camera.position, targetPosition, t: lerpFactor)
                    
                    // Look at avatar position from camera's current position
                    camera.look(at: avatarPosition, from: camera.position, relativeTo: nil)
                }
                if let avatar = avatarSystem.currentAvatar,
                   let reticle = reticleEntity {
                    let forward = SIMD3<Float>(0, 0, -1)
                    let transform = avatar.transform.matrix
                    let worldForward = (transform * SIMD4<Float>(forward.x, forward.y, forward.z, 0)).xyz
                    let targetPosition = avatar.position + normalize(worldForward) * 2.0
                    reticle.position = targetPosition

                    // Animate pulsing scale
                    let scale = 1.0 + 0.1 * sin(Float(Date().timeIntervalSinceReferenceDate * 2))
                    reticle.scale = SIMD3<Float>(repeating: scale)

                    // Color shift when close
                    let dist = distance(avatar.position, targetPosition)
                    let newColor: NSColor = dist < 1.5 ? .green : .blue
                    if var model = reticle.model {
                        model.materials = [SimpleMaterial(color: newColor, isMetallic: false)]
                        reticle.model = model
                    }
                }
            }
            .onContinuousHover { phase in
                handleMouseHover(phase)
            }
            .focusable()
            .onKeyPress { press in
                handleKeyPress(press)
            }
            .onScroll { event in
                // Adjust zoom level with scroll delta
                let zoomSpeed: Float = 0.2
                cameraDistance -= Float(event.deltaY) * zoomSpeed
                cameraDistance = min(max(cameraDistance, minCameraDistance), maxCameraDistance)
            }
            .gesture(DragGesture(minimumDistance: 0).updating($dragOffset) { value, state, _ in
                state = value.translation
            }.onEnded { value in
                let sensitivity: Float = 0.005
                // Adjust yaw based on horizontal drag
                cameraYaw += Float(value.translation.width) * sensitivity
                // Adjust pitch based on vertical drag
                cameraPitch += Float(value.translation.height) * sensitivity
                // Clamp pitch to avoid flipping camera upside down
                cameraPitch = max(-.pi / 4, min(.pi / 4, cameraPitch))
            })
            .gesture(
                TapGesture()
                    .onEnded {
                        if let avatar = avatarSystem.currentAvatar,
                           let reticle = reticleEntity {
                            avatar.position = reticle.position
                        }
                    }
            )
            
            // Overlay UI
            if showOverlay {
                WorldOverlayView_macOS(selectedEntity: $selectedEntity)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showOverlay.toggle() }) {
                    Image(systemName: showOverlay ? "eye" : "eye.slash")
                }
                .help("Toggle overlay")
                
                Divider()
                
                CameraControlsToolbar(controller: cameraController)
            }
        }
    }
    
    private func setupLighting(in scene: Entity) {
        // Directional light (sun)
        let sunLight = DirectionalLight()
        sunLight.light.intensity = 2000
        sunLight.light.isRealWorldProxy = true
        sunLight.shadow?.maximumDistance = 100
        sunLight.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(10, 20, 10), relativeTo: nil)
        scene.addChild(sunLight)
        
        // Ambient light
        let ambientLight = Entity()
        var ambientComponent = ImageBasedLightComponent()
        ambientComponent.inheritsRotation = true
        ambientLight.components.set(ambientComponent)
        scene.addChild(ambientLight)
    }
    
    private func handleMouseHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            // Handle hover effects
            break
        case .ended:
            // Clear hover effects
            break
        }
    }
    
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .w:
            let isBoosting = press.modifiers.contains(.shift)
            let modifier: AvatarSystem.MovementModifier = isBoosting ? .boost : .normal
            avatarSystem.moveAvatar(direction: .forward, modifier: modifier)
            return .handled
        case .s:
            let isBoosting = press.modifiers.contains(.shift)
            let modifier: AvatarSystem.MovementModifier = isBoosting ? .boost : .normal
            avatarSystem.moveAvatar(direction: .backward, modifier: modifier)
            return .handled
        case .a:
            let isBoosting = press.modifiers.contains(.shift)
            let modifier: AvatarSystem.MovementModifier = isBoosting ? .boost : .normal
            avatarSystem.moveAvatar(direction: .left, modifier: modifier)
            return .handled
        case .d:
            let isBoosting = press.modifiers.contains(.shift)
            let modifier: AvatarSystem.MovementModifier = isBoosting ? .boost : .normal
            avatarSystem.moveAvatar(direction: .right, modifier: modifier)
            return .handled
        case .space:
            avatarSystem.jumpAvatar()
            return .handled
        case .f:
            avatarSystem.toggleFlying()
            return .handled
        case .q:
            avatarSystem.ascendWhileFlying()
            return .handled
        case .e:
            avatarSystem.descendWhileFlying()
            return .handled
        case .upArrow:
            cameraController.moveForward()
            return .handled
        case .downArrow:
            cameraController.moveBackward()
            return .handled
        case .leftArrow:
            cameraController.rotateLeft()
            return .handled
        case .rightArrow:
            cameraController.rotateRight()
            return .handled
        default:
            return .ignored
        }
    }
}

// MARK: - World Overlay for macOS
struct WorldOverlayView_macOS: View {
    @Binding var selectedEntity: Entity?
    @EnvironmentObject var worldManager: WorldManager
    
    var body: some View {
        VStack {
            HStack {
                // Performance metrics
                PerformanceMetricsView()
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                // Mini map
                MiniMapView()
                    .frame(width: 200, height: 200)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
            
            Spacer()
            
            // Bottom UI
            HStack {
                // Chat preview
                ChatPreviewView()
                    .frame(width: 300, height: 150)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                // Action bar
                ActionBarView()
                    .padding(.horizontal)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
            }
            .padding()
        }
    }
}

// MARK: - Settings Detail View
struct SettingsDetailView: View {
    @State private var selectedCategory = "General"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(selectedCategory)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom)
                
                // Dynamic content based on category
                Group {
                    switch selectedCategory {
                    case "General":
                        GeneralSettingsView()
                    case "Graphics":
                        GraphicsSettingsView()
                    case "Audio":
                        AudioSettingsView()
                    case "Network":
                        NetworkSettingsView()
                    default:
                        Text("Select a category")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView_macOS()
        .environmentObject(AppStateManager())
        .environmentObject(WorldManager())
        .environmentObject(AvatarSystem())
        .frame(width: 1200, height: 800)
}
