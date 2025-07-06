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
    @State private var cameraPosition = SIMD3<Float>(0, 5, 10)
    @State private var showMiniMap = true
    
    var body: some View {
        ZStack {
            // Main 3D View
            RealityView { content in
                // Setup scene
                if let scene = try? await Entity.load(named: "WorldScene") {
                    content.add(scene)
                }
                
                // Add lighting
                let light = DirectionalLight()
                light.light.intensity = 1000
                light.light.isRealWorldProxy = true
                light.shadow?.maximumDistance = 50
                light.look(at: SIMD3<Float>(0, 0, 0), from: SIMD3<Float>(5, 10, 5), relativeTo: nil)
                content.add(light)
                
            } update: { content in
                // Update world content
                if let worldEntity = content.entities.first {
                    worldManager.updateWorldEntity(worldEntity)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleCameraDrag(value)
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        handleCameraZoom(value)
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
    
    private func handleCameraDrag(_ value: DragGesture.Value) {
        let delta = value.translation
        cameraPosition.x -= Float(delta.width) * 0.01
        cameraPosition.z += Float(delta.height) * 0.01
    }
    
    private func handleCameraZoom(_ value: CGFloat) {
        let scale = Float(value)
        cameraPosition.y = max(2, min(50, cameraPosition.y / scale))
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
