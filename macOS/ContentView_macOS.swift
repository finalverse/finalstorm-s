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
                
                // Setup lighting
                setupLighting(in: scene)
                
                // Add camera
                let cameraEntity = PerspectiveCamera()
                cameraEntity.position = SIMD3<Float>(0, 10, 20)
                cameraEntity.look(at: SIMD3<Float>(0, 0, 0), from: cameraEntity.position, relativeTo: nil)
                scene.addChild(cameraEntity)
                
                content.add(scene)
                
            } update: { content in
                // Update world state
                worldManager.updateContent(content)
            }
            .onContinuousHover { phase in
                handleMouseHover(phase)
            }
            .focusable()
            .onKeyPress { press in
                handleKeyPress(press)
            }
            
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
