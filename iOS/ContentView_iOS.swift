//
// File Path: iOS/ContentView_iOS.swift
// Description: iOS-specific content view implementation
// This view provides the main interface for iOS devices
//

import SwiftUI
import RealityKit

struct ContentView_iOS: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @State private var selectedTab = 0
    @State private var showARView = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // World View Tab
            WorldView_iOS()
                .tabItem {
                    Label("World", systemImage: "globe")
                }
                .tag(0)
            
            // Inventory Tab
            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "backpack")
                }
                .tag(1)
            
            // Chat Tab
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView_iOS()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .overlay(alignment: .topTrailing) {
            if selectedTab == 0 {
                ARToggleButton(isAREnabled: $showARView)
                    .padding()
            }
        }
        .sheet(isPresented: $showARView) {
            ARWorldView_iOS()
        }
    }
}

// MARK: - World View for iOS
struct WorldView_iOS: View {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    @State private var cameraYaw: Float = 0
    @State private var cameraPitch: Float = 0
    @State private var cameraDistance: Float = 6
    @State private var cameraPosition = SIMD3<Float>(0, 5, 10)
    @State private var targetCameraPosition = SIMD3<Float>(0, 5, 10)
    @State private var showMiniMap = true
    @State private var reticleEntity: Entity?
    
    var body: some View {
        ZStack {
            // Main 3D View
            RealityView { content in
                // Setup scene
                let worldEntity = worldManager.createWorldEntity()
                content.add(worldEntity)
                
                if let avatar = try? await avatarSystem.createLocalAvatar() {
                    content.add(avatar)
                }
                
                let camera = PerspectiveCamera()
                camera.position = SIMD3<Float>(0, 5, 10)
                camera.look(at: SIMD3<Float>(0, 0, 0), from: camera.position, relativeTo: nil)
                content.add(camera)
                
                let reticle = Entity()
                let reticleMaterial = SimpleMaterial(color: .blue, isMetallic: false)
                reticle.components.set(ModelComponent(mesh: .generateSphere(radius: 0.05), materials: [reticleMaterial]))
                content.add(reticle)
                reticleEntity = reticle
                
            } update: { content in
                guard let camera = content.entities.compactMap({ $0 as? PerspectiveCamera }).first else { return }
                
                // Smoothly interpolate camera position
                targetCameraPosition = orbitCamera(yaw: cameraYaw, pitch: cameraPitch, distance: cameraDistance)
                cameraPosition = lerp(cameraPosition, targetCameraPosition, 0.1)
                camera.position = cameraPosition
                camera.look(at: SIMD3<Float>(0, 0, 0), from: camera.position, relativeTo: nil)
                
                // Update avatar
                avatarSystem.updateAvatar(in: content)
                
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
                    let newColor: UIColor = dist < 1.5 ? .green : .blue
                    if var model = reticle.model {
                        model.materials = [SimpleMaterial(color: newColor, isMetallic: false)]
                        reticle.model = model
                    }
                }
                
                // Update world entity
                if let worldEntity = content.entities.first(where: { $0 != camera && $0.name != "Avatar" }) {
                    worldManager.updateWorldEntity(worldEntity)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation
                        cameraYaw += Float(delta.width) * 0.005
                        cameraPitch -= Float(delta.height) * 0.005
                        cameraPitch = max(-.pi / 2 + 0.1, min(.pi / 2 - 0.1, cameraPitch))
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let scale = Float(value)
                        cameraDistance /= scale
                        cameraDistance = max(2, min(50, cameraDistance))
                    }
            )
            .gesture(
                TapGesture()
                    .onEnded {
                        if let avatar = avatarSystem.currentAvatar,
                           let reticle = reticleEntity {
                            avatar.position = reticle.position
                        }
                    }
            )
            
            // UI Overlay
            VStack {
                HStack {
                    // Player status
                    PlayerStatusView()
                        .padding()
                    
                    Spacer()
                    
                    // Mini map
                    if showMiniMap {
                        MiniMapView()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .padding()
                    }
                }
                
                Spacer()
                
                // Action bar
                ActionBarView()
                    .padding()
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
    }
    
    private func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }
    
    private func orbitCamera(yaw: Float, pitch: Float, distance: Float) -> SIMD3<Float> {
        let x = distance * cos(pitch) * sin(yaw)
        let y = distance * sin(pitch)
        let z = distance * cos(pitch) * cos(yaw)
        return SIMD3<Float>(x, y, z)
    }
}

// MARK: - AR Toggle Button
struct ARToggleButton: View {
    @Binding var isAREnabled: Bool
    
    var body: some View {
        Button(action: {
            isAREnabled.toggle()
        }) {
            Image(systemName: isAREnabled ? "arkit" : "arkit.badge.xmark")
                .font(.title2)
                .foregroundColor(.white)
                .padding()
                .background(Circle().fill(Color.blue))
                .shadow(radius: 4)
        }
    }
}

// MARK: - Settings View for iOS
struct SettingsView_iOS: View {
    @EnvironmentObject var appState: AppStateManager
    @State private var selectedSection = 0
    
    var body: some View {
        NavigationView {
            List {
                Section("Account") {
                    NavigationLink(destination: AccountSettingsView()) {
                        Label("Account Settings", systemImage: "person.circle")
                    }
                    NavigationLink(destination: PrivacySettingsView()) {
                        Label("Privacy", systemImage: "lock")
                    }
                }
                
                Section("Graphics") {
                    NavigationLink(destination: GraphicsSettingsView()) {
                        Label("Graphics Quality", systemImage: "wand.and.rays")
                    }
                    NavigationLink(destination: PerformanceSettingsView()) {
                        Label("Performance", systemImage: "speedometer")
                    }
                }
                
                Section("Audio") {
                    NavigationLink(destination: AudioSettingsView()) {
                        Label("Audio Settings", systemImage: "speaker.wave.3")
                    }
                }
                
                Section("Network") {
                    NavigationLink(destination: NetworkSettingsView()) {
                        Label("Network Settings", systemImage: "network")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    ContentView_iOS()
        .environmentObject(AppStateManager())
        .environmentObject(WorldManager())
        .environmentObject(AvatarSystem())
}
