//
//  ContentView_iOS.swift
//  FinalStorm-S
//
//  iOS-specific implementation with AR support
//

import SwiftUI
import RealityKit
import ARKit
import Combine

struct ContentView_iOS: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @EnvironmentObject var finalverseServices: FinalverseServicesManager
    
    @State private var showInventory = false
    @State private var showChat = false
    @State private var showMap = false
    @State private var arMode = false
    @State private var selectedEntity: Entity?
    
    var body: some View {
        ZStack {
            // Main world view
            if arMode {
                ARWorldView()
                    .edgesIgnoringSafeArea(.all)
            } else {
                WorldView()
                    .edgesIgnoringSafeArea(.all)
            }
            
            // HUD overlay
            VStack {
                // Top bar
                HStack {
                    // Character info
                    CharacterInfoView()
                    
                    Spacer()
                    
                    // Mini map
                    if showMap {
                        MiniMapView()
                            .frame(width: 200, height: 200)
                            .cornerRadius(10)
                            .padding()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Chat window
                if showChat {
                    ChatView()
                        .frame(height: 200)
                        .transition(.move(edge: .bottom))
                }
                
                // Bottom controls
                HStack(spacing: 20) {
                    // Inventory button
                    Button(action: { showInventory.toggle() }) {
                        Image(systemName: "bag.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    // Songweaving wheel
                    SongweavingWheel()
                        .frame(width: 150, height: 150)
                    
                    // AR toggle
                    Button(action: { arMode.toggle() }) {
                        Image(systemName: arMode ? "arkit" : "cube.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.blue.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 30)
            }
            
            // Inventory overlay
            if showInventory {
                InventoryView()
                    .transition(.scale)
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            setupScene()
        }
    }
    
    private func setupScene() {
        // Initialize world for first hour experience
        Task {
            if !appState.isLoggedIn {
                // Show login or start first hour experience
                await startFirstHourExperience()
            }
        }
    }
    
    private func startFirstHourExperience() async {
        // Load Weaver's Landing
        do {
            try await worldManager.loadWorld(
                named: "Terra Nova",
                server: ServerInfo.finalverseLocal
            )
            
            // Create player avatar
            let profile = UserProfile.default
            let avatar = try await avatarSystem.createLocalAvatar(profile: profile)
            
            // Position at Memory Grotto
            avatar.position = SIMD3<Float>(128, 50, 128)
            
            // Summon Lumi for greeting
            await finalverseServices.echoEngine.summonEcho(.lumi, at: avatar.position + [2, 0, 0])
            
            appState.isLoggedIn = true
        } catch {
            print("Failed to start first hour: \(error)")
        }
    }
}

// MARK: - World View (Standard 3D)
struct WorldView: UIViewRepresentable {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure for non-AR rendering
        arView.environment.background = .color(.black)
        
        // Add gesture recognizers
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)
        
        // Setup camera
        let cameraEntity = PerspectiveCamera()
        cameraEntity.camera.fieldOfViewInDegrees = 60
        arView.scene.addAnchor(AnchorEntity(world: .zero))
        
        context.coordinator.arView = arView
        context.coordinator.setupControls()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update scene based on world state
        context.coordinator.updateScene()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(worldManager: worldManager, avatarSystem: avatarSystem)
    }
    
    class Coordinator: NSObject {
        let worldManager: WorldManager
        let avatarSystem: AvatarSystem
        weak var arView: ARView?
        
        private var cameraController: CameraController?
        private var inputHandler: TouchInputHandler?
        
        init(worldManager: WorldManager, avatarSystem: AvatarSystem) {
            self.worldManager = worldManager
            self.avatarSystem = avatarSystem
            super.init()
        }
        
        func setupControls() {
            guard let arView = arView else { return }
            
            // Setup camera controller
            cameraController = CameraController(arView: arView)
            
            // Setup input handling
            inputHandler = TouchInputHandler(arView: arView)
            inputHandler?.onMove = { [weak self] position in
                self?.avatarSystem.moveAvatar(to: position, rotation: .identity)
            }
        }
        
        func updateScene() {
            guard let arView = arView else { return }
            
            // Update visible entities
            for entity in worldManager.visibleEntities {
                if arView.scene.findEntity(named: entity.name) == nil {
                    let anchor = AnchorEntity(world: entity.position)
                    anchor.addChild(entity)
                    arView.scene.addAnchor(anchor)
                }
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            
            let location = gesture.location(in: arView)
            let results = arView.hitTest(location)
            
            if let firstResult = results.first {
                // Handle entity interaction
                handleEntityInteraction(firstResult.entity)
            } else {
                // Move to tapped location
                if let rayResult = arView.ray(through: location) {
                    let worldPosition = rayResult.origin + rayResult.direction * 10
                    avatarSystem.moveAvatar(to: worldPosition, rotation: .identity)
                }
            }
        }
        
        private func handleEntityInteraction(_ entity: Entity) {
            // Check if entity is interactable
            if entity.components[InteractionComponent.self] != nil {
                // Perform interaction
                if let echo = entity as? EchoEntity {
                    Task {
                        await avatarSystem.performSongweaving(.greeting, target: echo)
                    }
                }
            }
        }
    }
}

// MARK: - AR World View
struct ARWorldView: UIViewRepresentable {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        arView.session.run(config)
        
        // Enable occlusion
        arView.environment.sceneUnderstanding.options = [.occlusion, .physics]
        
        context.coordinator.arView = arView
        context.coordinator.setupAR()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateAR()
    }
    
    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(worldManager: worldManager, avatarSystem: avatarSystem)
    }
    
    class ARCoordinator: NSObject, ARSessionDelegate {
        let worldManager: WorldManager
        let avatarSystem: AvatarSystem
        weak var arView: ARView?
        
        private var arAnchorManager: ARAnchorManager?
        
        init(worldManager: WorldManager, avatarSystem: AvatarSystem) {
            self.worldManager = worldManager
            self.avatarSystem = avatarSystem
            super.init()
        }
        
        func setupAR() {
            guard let arView = arView else { return }
            
            arView.session.delegate = self
            arAnchorManager = ARAnchorManager(arView: arView)
            
            // Place initial content
            placeWorldContent()
        }
        
        func updateAR() {
            // Update AR anchors based on world state
            arAnchorManager?.updateAnchors(for: worldManager.visibleEntities)
        }
        
        private func placeWorldContent() {
            // Place world entities in AR space
            for entity in worldManager.visibleEntities {
                arAnchorManager?.placeEntity(entity, at: entity.position)
            }
        }
        
        // MARK: - ARSessionDelegate
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    // Place content on detected planes
                    handlePlaneDetection(planeAnchor)
                }
            }
        }
        
        private func handlePlaneDetection(_ planeAnchor: ARPlaneAnchor) {
            // Place appropriate content based on plane type
            if planeAnchor.classification == .floor {
                // Place ground-based entities
                placeGroundContent(on: planeAnchor)
            } else if planeAnchor.classification == .wall {
                // Place wall-mounted UI elements
                placeWallUI(on: planeAnchor)
            }
        }
        
//        private func placeGroundContent(on planeAnchor: ARPlaneAnchor) {
//            // Place avatar and world objects on floor
//            if let avatar = avatarSystem.localAvatar {
//                arAnchorManager?.anchorEntity(avatar, to: planeAnchor)
//

        private func placeWallUI(on planeAnchor: ARPlaneAnchor) {
                    // Create floating UI panels on walls
                    let uiPanel = HolographicUIPanel()
                    uiPanel.displayMetrics(from: worldManager.worldMetabolism)
                    arAnchorManager?.anchorEntity(uiPanel, to: planeAnchor)
                }
            }
        }

        // MARK: - UI Components
        struct CharacterInfoView: View {
            @EnvironmentObject var avatarSystem: AvatarSystem
            
            var body: some View {
                HStack(spacing: 15) {
                    // Avatar portrait
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 5) {
                        // Resonance levels
                        ResonanceMeter(
                            type: .creative,
                            value: avatarSystem.resonanceLevel.creativeResonance
                        )
                        ResonanceMeter(
                            type: .exploration,
                            value: avatarSystem.resonanceLevel.explorationResonance
                        )
                        ResonanceMeter(
                            type: .restoration,
                            value: avatarSystem.resonanceLevel.restorationResonance
                        )
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(15)
            }
        }

        struct ResonanceMeter: View {
            enum ResonanceType {
                case creative, exploration, restoration
                
                var color: Color {
                    switch self {
                    case .creative: return .purple
                    case .exploration: return .blue
                    case .restoration: return .green
                    }
                }
                
                var icon: String {
                    switch self {
                    case .creative: return "paintbrush.fill"
                    case .exploration: return "location.fill"
                    case .restoration: return "leaf.fill"
                    }
                }
            }
            
            let type: ResonanceType
            let value: Float
            
            var body: some View {
                HStack(spacing: 5) {
                    Image(systemName: type.icon)
                        .font(.caption)
                        .foregroundColor(type.color)
                        .frame(width: 20)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(type.color)
                                .frame(width: CGFloat(value / 100) * geometry.size.width, height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(Int(value))")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(height: 20)
            }
        }

        struct SongweavingWheel: View {
            @State private var selectedMelody: MelodyType?
            @State private var isExpanded = false
            @State private var rotationAngle: Double = 0
            
            let melodies: [MelodyType] = [.restoration, .exploration, .creation]
            
            var body: some View {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                    
                    if isExpanded {
                        // Melody options
                        ForEach(0..<melodies.count, id: \.self) { index in
                            MelodyButton(
                                melody: melodies[index],
                                isSelected: selectedMelody == melodies[index]
                            )
                            .offset(x: 50 * cos(Double(index) * 2 * .pi / 3 + rotationAngle),
                                   y: 50 * sin(Double(index) * 2 * .pi / 3 + rotationAngle))
                        }
                    }
                    
                    // Center button
                    Button(action: {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                            if isExpanded {
                                rotationAngle += .pi / 6
                            }
                        }
                    }) {
                        Image(systemName: "music.note.list")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(
                                RadialGradient(
                                    colors: [Color.purple, Color.blue],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 30
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: .purple.opacity(0.5), radius: 10)
                    }
                    .scaleEffect(isExpanded ? 0.8 : 1.0)
                }
            }
        }

        struct MelodyButton: View {
            let melody: MelodyType
            let isSelected: Bool
            
            var body: some View {
                Button(action: {
                    // Perform songweaving with selected melody
                }) {
                    Circle()
                        .fill(melody.color)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: melody.icon)
                                .foregroundColor(.white)
                                .font(.body)
                        )
                        .scaleEffect(isSelected ? 1.2 : 1.0)
                        .shadow(color: melody.color.opacity(0.5), radius: isSelected ? 10 : 5)
                }
            }
        }

        // MARK: - Helper Classes
        class CameraController {
            private let arView: ARView
            private var cameraEntity: Entity?
            private var panGesture: UIPanGestureRecognizer?
            private var pinchGesture: UIPinchGestureRecognizer?
            
            init(arView: ARView) {
                self.arView = arView
                setupCamera()
                setupGestures()
            }
            
            private func setupCamera() {
                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 60
                camera.position = [0, 10, 20]
                camera.look(at: [0, 0, 0], from: camera.position, relativeTo: nil)
                
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(camera)
                arView.scene.addAnchor(anchor)
                
                cameraEntity = camera
            }
            
            private func setupGestures() {
                // Pan for rotation
                panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                arView.addGestureRecognizer(panGesture!)
                
                // Pinch for zoom
                pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
                arView.addGestureRecognizer(pinchGesture!)
            }
            
            @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
                guard let camera = cameraEntity else { return }
                
                let translation = gesture.translation(in: arView)
                let rotationY = Float(translation.x) * 0.01
                let rotationX = Float(translation.y) * 0.01
                
                camera.transform.rotation *= simd_quatf(angle: rotationY, axis: [0, 1, 0])
                camera.transform.rotation *= simd_quatf(angle: rotationX, axis: [1, 0, 0])
                
                gesture.setTranslation(.zero, in: arView)
            }
            
            @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
                guard let camera = cameraEntity else { return }
                
                let scale = Float(gesture.scale)
                let forward = camera.transform.matrix.columns.2.xyz
                camera.position -= forward * (scale - 1) * 2
                
                gesture.scale = 1.0
            }
        }

        class TouchInputHandler {
            private let arView: ARView
            var onMove: ((SIMD3<Float>) -> Void)?
            var onInteract: ((Entity) -> Void)?
            
            init(arView: ARView) {
                self.arView = arView
            }
            
            func handleTouch(at location: CGPoint) {
                let results = arView.hitTest(location)
                
                if let hit = results.first {
                    // Entity interaction
                    onInteract?(hit.entity)
                } else if let raycast = arView.raycast(
                    from: location,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                ).first {
                    // Movement
                    let worldPosition = raycast.worldTransform.columns.3.xyz
                    onMove?(worldPosition)
                }
            }
        }

        class ARAnchorManager {
            private let arView: ARView
            private var anchors: [UUID: AnchorEntity] = [:]
            
            init(arView: ARView) {
                self.arView = arView
            }
            
            func placeEntity(_ entity: Entity, at position: SIMD3<Float>) {
                let anchor = AnchorEntity(world: position)
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
                anchors[entity.id] = anchor
            }
            
            func anchorEntity(_ entity: Entity, to arAnchor: ARAnchor) {
                let anchorEntity = AnchorEntity(anchor: arAnchor)
                anchorEntity.addChild(entity)
                arView.scene.addAnchor(anchorEntity)
                anchors[entity.id] = anchorEntity
            }
            
            func updateAnchors(for entities: Set<Entity>) {
                // Update anchor positions based on tracking
                for entity in entities {
                    if let anchor = anchors[entity.id] {
                        // Update if needed
                    }
                }
            }
        }

        // MARK: - Supporting Types
        extension MelodyType {
            var color: Color {
                switch self {
                case .restoration: return .green
                case .exploration: return .blue
                case .creation: return .purple
                }
            }
            
            var icon: String {
                switch self {
                case .restoration: return "leaf.fill"
                case .exploration: return "location.fill"
                case .creation: return "sparkles"
                }
            }
        }

        struct ServerInfo {
            let name: String
            let address: String
            let port: Int
            
            static let finalverseLocal = ServerInfo(
                name: "Finalverse Local",
                address: "localhost",
                port: 3000
            )
        }

        struct UserProfile {
            let id: UUID
            let username: String
            let displayName: String
            
            static let `default` = UserProfile(
                id: UUID(),
                username: "songweaver",
                displayName: "New Songweaver"
            )
        }
