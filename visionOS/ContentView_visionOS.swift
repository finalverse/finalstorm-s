//
//  ContentView_visionOS.swift
//  FinalStorm-S
//
//  visionOS-specific implementation with immersive spaces
//

import SwiftUI
import RealityKit

struct ContentView_visionOS: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @EnvironmentObject var finalverseServices: FinalverseServicesManager
    
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    @State private var showImmersiveSpace = false
    @State private var immersionStyle: ImmersionStyle = .mixed
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("World") {
                    WorldControlsView()
                }
                
                Section("Character") {
                    CharacterControlsView()
                }
                
                Section("Echoes") {
                    EchoControlsView()
                }
            }
            .navigationTitle("FinalStorm")
        } detail: {
            // Main view
            VStack {
                if showImmersiveSpace {
                    Text("Immersive space is active")
                        .font(.largeTitle)
                        .padding()
                    
                    Button("Exit Immersive Space") {
                        Task {
                            await dismissImmersiveSpace()
                            showImmersiveSpace = false
                        }
                    }
                } else {
                    // Window-based view
                    WindowWorldView()
                        .overlay(alignment: .bottom) {
                            VisionControlBar(
                                showImmersiveSpace: $showImmersiveSpace,
                                immersionStyle: $immersionStyle
                            )
                            .padding()
                        }
                }
            }
        }
        .onChange(of: showImmersiveSpace) { _, newValue in
            Task {
                if newValue {
                    await openImmersiveSpace(id: "FinalverseWorld")
                }
            }
        }
    }
}

// MARK: - Immersive World View
struct ImmersiveWorldView: View {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @EnvironmentObject var finalverseServices: FinalverseServicesManager
    
    @State private var playerPosition = SIMD3<Float>(0, 0, 0)
    
    var body: some View {
        RealityView { content in
            // Setup immersive world
            await setupImmersiveWorld(content)
        } update: { content in
            // Update world based on state changes
            updateWorld(content)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleSpatialTap(value.entity, location: value.location3D)
                }
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    handleDrag(value)
                }
        )
    }
    
    @MainActor
    private func setupImmersiveWorld(_ content: RealityViewContent) async {
        // Create ground plane
        let ground = ModelEntity(
            mesh: .generatePlane(width: 100, depth: 100),
            materials: [GridMaterial()]
        )
        ground.position = [0, -0.1, 0]
        content.add(ground)
        
        // Add skybox
        do {
            let skybox = try await EnvironmentResource.load(named: "skybox")
            content.environment = skybox
        } catch {
            // Use default environment
        }
        
        // Load first hour scene
        await loadFirstHourScene(content)
        
        // Setup spatial audio
        setupSpatialAudio()
    }
    
    private func loadFirstHourScene(_ content: RealityViewContent) async {
        // Create Memory Grotto
        let grotto = await createMemoryGrotto()
        grotto.position = [0, 0, -5]
        content.add(grotto)
        
        // Add player avatar
        if let avatar = avatarSystem.localAvatar {
            avatar.position = [0, 0, 0]
            content.add(avatar)
        }
        
        // Summon Lumi
        await finalverseServices.echoEngine.summonEcho(.lumi, at: [2, 0.5, -3])
        if let lumi = finalverseServices.echoEngine.activeEchoes.first(where: { $0.echoType == .lumi }) {
            content.add(lumi)
        }
    }
    
    private func createMemoryGrotto() async -> Entity {
        let grotto = Entity()
        
        // Crystal formations
        for i in 0..<8 {
            let angle = Float(i) * .pi / 4
            let crystal = await createCrystal()
            crystal.position = [
                sin(angle) * 3,
                0,
                cos(angle) * 3
            ]
            grotto.addChild(crystal)
        }
        
        // Central pool
        let pool = ModelEntity(
            mesh: .generateSphere(radius: 1.5),
            materials: [WaterMaterial()]
        )
        pool.position = [0, -0.5, 0]
        pool.scale = [1, 0.1, 1]
        grotto.addChild(pool)
        
        // Ambient particles
        let particles = ParticleEmitterComponent.Presets.magic
        particles.birthLocation = .volume
        particles.emitterShape = .sphere
        particles.birthRate = 20
        
        let particleEntity = Entity()
        particleEntity.components.set(particles)
        grotto.addChild(particleEntity)
        
        return grotto
    }
    
    private func createCrystal() async -> ModelEntity {
        let crystal = ModelEntity(
            mesh: .generateBox(size: [0.3, 1.5, 0.3]),
            materials: [CrystalMaterial()]
        )
        
        // Add glow
        crystal.components.set(PointLightComponent(
            color: .init(red: 0.5, green: 0.8, blue: 1.0),
            intensity: 500,
            attenuationRadius: 2
        ))
        
        // Floating animation
        let floatAnimation = FromToByAnimation(
            from: crystal.position,
            to: crystal.position + [0, 0.2, 0],
            duration: 3,
            bindTarget: .position
        )
        
        if let animation = try? AnimationResource.generate(with: floatAnimation) {
            crystal.playAnimation(animation.repeat())
        }
        
        return crystal
    }
    
    private func updateWorld(_ content: RealityViewContent) {
        // Update based on world state changes
        for entity in worldManager.visibleEntities {
            if content.entities.contains(where: { $0.id == entity.id }) == false {
                content.add(entity)
            }
        }
    }
    
    private func handleSpatialTap(_ entity: Entity, location: SIMD3<Float>) {
        // Check if tapped entity is interactable
        if let echo = entity as? EchoEntity {
            Task {
                await finalverseServices.echoEngine.interactWithEcho(echo, interaction: .talk)
            }
        } else if entity.components[InteractionComponent.self] != nil {
            // Perform interaction
            Task {
                await avatarSystem.performSongweaving(.exploration, target: entity)
            }
        } else {
            // Move to location
            avatarSystem.moveAvatar(to: location, rotation: .identity)
        }
    }
    
    private func handleDrag(_ value: DragGesture.Value) {
        // Handle object manipulation
        if let entity = value.entity {
            let translation = value.translation3D
            entity.position += SIMD3<Float>(
                Float(translation.width) * 0.01,
                Float(translation.height) * 0.01,
                Float(translation.depth) * 0.01
            )
        }
    }
    
    private func setupSpatialAudio() {
        // Configure spatial audio for immersive experience
        let audioEngine = SpatialAudioEngine()
        audioEngine.outputFormat = .binaural
        audioEngine.reverbPreset = .mediumRoom
    }
}

// MARK: - Window World View
struct WindowWorldView: View {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    var body: some View {
        RealityView { content in
            // Setup bounded volume view
            setupBoundedVolume(content)
        } update: { content in
            updateBoundedVolume(content)
        }
        .frame(depth: 500)
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleTap(value.entity)
                }
        )
    }
    
    private func setupBoundedVolume(_ content: RealityViewContent) {
        // Create miniature world representation
        let worldModel = Entity()
        
        // Add terrain
        let terrain = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 2),
            materials: [TerrainMaterial()]
        )
        worldModel.addChild(terrain)
        
        // Add miniature buildings
        let weaversLanding = createMiniatureBuilding(name: "Weaver's Landing")
        weaversLanding.position = [0.5, 0.1, 0.5]
        worldModel.addChild(weaversLanding)
        
        content.add(worldModel)
    }
    
    private func updateBoundedVolume(_ content: RealityViewContent) {
        // Update miniature world based on state
    }
    
    private func createMiniatureBuilding(name: String) -> Entity {
        let building = ModelEntity(
            mesh: .generateBox(size: [0.2, 0.3, 0.2]),
            materials: [SimpleMaterial(color: .gray, isMetallic: true)]
        )
        
        // Add label
        if let textMesh = MeshResource.generateText(
            name,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.05)
        ) {
            let label = ModelEntity(mesh: textMesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
            label.position = [0, 0.2, 0]
            building.addChild(label)
        }
        
        return building
    }
    
    private func handleTap(_ entity: Entity) {
        // Handle interactions in bounded volume
        print("Tapped: \(entity.name)")
    }
}

// MARK: - Control Views
struct WorldControlsView: View {
    @EnvironmentObject var worldManager: WorldManager
    
    var body: some View {
        VStack(alignment: .leading) {
            if let world = worldManager.currentWorld {
                Label(world.name, systemImage: "globe")
                
                if let region = worldManager.currentRegion {
                    Label(region.name, systemImage: "map")
                        .font(.caption)
                }
            }
            
            Button("Load World") {
                Task {
                    try await worldManager.loadWorld(
                        named: "Terra Nova",
                        server: ServerInfo.finalverseLocal
                    )
                }
            }
        }
    }
}

struct CharacterControlsView: View {
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    var body: some View {
        VStack(alignment: .leading) {
            // Resonance display
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("Creative: \(Int(avatarSystem.resonanceLevel.creativeResonance))")
                }
                
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("Exploration: \(Int(avatarSystem.resonanceLevel.explorationResonance))")
                }
                
                HStack {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                    Text("Restoration: \(Int(avatarSystem.resonanceLevel.restorationResonance))")
                }
            }
            .font(.caption)
        }
    }
}

struct EchoControlsView: View {
    @EnvironmentObject var echoEngine: EchoEngine
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(EchoType.allCases, id: \.self) { echoType in
                Button("Summon \(echoType.rawValue)") {
                    Task {
                        await echoEngine.summonEcho(echoType, at: [0, 0, -2])
                    }
                }
            }
        }
    }
}

struct VisionControlBar: View {
    @Binding var showImmersiveSpace: Bool
    @Binding var immersionStyle: ImmersionStyle
    
    var body: some View {
        HStack {
            Button(action: { showImmersiveSpace.toggle() }) {
                Label(
                    showImmersiveSpace ? "Exit Immersive" : "Enter Immersive",
                    systemImage: showImmersiveSpace ? "visionpro" : "visionpro.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            
            Picker("Immersion", selection: $immersionStyle) {
                Text("Mixed").tag(ImmersionStyle.mixed)
                Text("Progressive").tag(ImmersionStyle.progressive)
                Text("Full").tag(ImmersionStyle.full)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(15)
    }
}

// MARK: - Custom Materials
struct GridMaterial: Material {
    func generate() -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: .darkGray, texture: .init(try! .load(named: "grid_texture")))
        material.roughness = 0.8
        material.metallic = 0.1
        return material
    }
}

struct CrystalMaterial: Material {
    func generate() -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(white: 0.9, alpha: 0.7))
        material.roughness = 0.1
        material.metallic = 0.3
        return material
    }
}

struct WaterMaterial: Material {
    func generate() -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.6))
        material.roughness = 0.0
        material.metallic = 0.0
        return material
    }
}

struct TerrainMaterial: Material {
    func generate() -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: .brown, texture: .init(try! .load(named: "terrain_texture")))
        material.roughness = 0.9
        material.metallic = 0.0
        return material
    }
}

// MARK: - Extensions
extension EchoType: CaseIterable {
    static var allCases: [EchoType] {
        [.lumi, .kai, .terra, .ignis]
    }
}

extension SIMD3 where Scalar == Float {
    static var one: SIMD3<Float> {
        SIMD3<Float>(1, 1, 1)
    }
}

