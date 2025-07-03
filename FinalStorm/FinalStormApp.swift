//
//  FinalStormApp.swift
//  FinalStorm
//

import SwiftUI
import RealityKit

@main
struct FinalStormApp: App {
    // Shared state managers
    @StateObject private var appState = AppStateManager()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var worldManager = WorldManager()
    @StateObject private var avatarSystem = AvatarSystem()
    @StateObject private var finalverseServices = FinalverseServicesManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(networkManager)
                .environmentObject(worldManager)
                .environmentObject(avatarSystem)
                .environmentObject(finalverseServices)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
        
        #if os(visionOS)
        WindowGroup(id: "FinalverseWorld") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(networkManager)
                .environmentObject(worldManager)
                .environmentObject(avatarSystem)
                .environmentObject(finalverseServices)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1, height: 1, depth: 1, in: .meters)
        
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveWorldView()
                .environmentObject(appState)
                .environmentObject(worldManager)
                .environmentObject(avatarSystem)
                .environmentObject(finalverseServices)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}
