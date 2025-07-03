//
//  FinalStorm/FinalStormApp.swift
//  FinalStorm
//
//  Main app entry point with proper platform handling
//

import SwiftUI

@main
struct FinalStormApp: App {
    #if !os(visionOS)
    @StateObject private var appState = AppStateManager()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var worldManager = WorldManager()
    @StateObject private var avatarSystem = AvatarSystem()
    @StateObject private var finalverseServices = FinalverseServicesManager()
    #endif
    
    var body: some Scene {
        #if os(visionOS)
        WindowGroup {
            ContentView_visionOS()
        }
        .windowStyle(.volumetric)

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveWorldView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #else
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
                .environmentObject(networkManager)
                .environmentObject(worldManager)
                .environmentObject(avatarSystem)
                .environmentObject(finalverseServices)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        #endif
    }
}
