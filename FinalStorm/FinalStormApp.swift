//
// File Path: FinalStorm/FinalStormApp.swift
// Description: Main app entry point with proper platform handling
// This file manages the app lifecycle and platform-specific initialization
//

import SwiftUI

@main
struct FinalStormApp: App {
    // MARK: - State Objects
    #if !os(visionOS)
    @StateObject private var appState = AppStateManager()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var worldManager = WorldManager()
    @StateObject private var avatarSystem = AvatarSystem()
    @StateObject private var finalverseServices = FinalverseServicesManager()
    @StateObject private var core = FinalStormCore.shared
    #endif
    
    init() {
        // Configure app-wide settings
        configureAppearance()
        setupLogging()
    }
    
    var body: some Scene {
        #if os(visionOS)
        // VisionOS specific scene
        WindowGroup {
            ContentView_visionOS()
                .task {
                    await initializeVisionOS()
                }
        }
        .windowStyle(.volumetric)

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveWorldView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        
        #else
        // iOS and macOS scene
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
                .environmentObject(networkManager)
                .environmentObject(worldManager)
                .environmentObject(avatarSystem)
                .environmentObject(finalverseServices)
                .environmentObject(core)
                .task {
                    await initializeApp()
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FinalStorm") {
                    appState.showAboutWindow = true
                }
            }
        }
        #endif
        #endif
    }
    
    // MARK: - Initialization
    private func initializeApp() async {
        do {
            // Initialize core systems
            try await FinalStormCore.shared.initialize()
            
            // Load user preferences
            await appState.loadUserPreferences()
            
            // Connect to server if auto-connect is enabled
            if appState.autoConnect {
                await networkManager.connectToDefaultServer()
            }
            
        } catch {
            print("Failed to initialize app: \(error)")
            appState.showInitializationError(error)
        }
    }
    
    #if os(visionOS)
    private func initializeVisionOS() async {
        // VisionOS specific initialization
        do {
            try await FinalStormCore.shared.initialize()
        } catch {
            print("Failed to initialize VisionOS: \(error)")
        }
    }
    #endif
    
    // MARK: - Configuration
    private func configureAppearance() {
        #if os(macOS)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        #endif
    }
    
    private func setupLogging() {
        // Configure logging system
        LogManager.shared.configure(level: .debug)
    }
}

//
// File Path: FinalStorm/MainContentView.swift
// Description: Main content view that routes to platform-specific views
// This view handles the main UI routing based on the current platform
//

import SwiftUI

struct MainContentView: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var core: FinalStormCore
    
    var body: some View {
        Group {
            if core.isInitialized {
                #if os(iOS)
                ContentView_iOS()
                #elseif os(macOS)
                ContentView_macOS()
                #endif
            } else {
                LoadingView()
            }
        }
        .alert("Error", isPresented: $appState.showError) {
            Button("OK") {
                appState.dismissError()
            }
        } message: {
            Text(appState.errorMessage)
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    @State private var progress: Double = 0
    @State private var loadingMessage = "Initializing FinalStorm..."
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            
            Text("FinalStorm")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ProgressView(value: progress) {
                Text(loadingMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(width: 300)
            
            Spacer()
        }
        .padding()
        .onAppear {
            simulateLoading()
        }
    }
    
    private func simulateLoading() {
        withAnimation(.easeInOut(duration: 2)) {
            progress = 1.0
        }
    }
}

#Preview {
    MainContentView()
        .environmentObject(AppStateManager())
        .environmentObject(FinalStormCore.shared)
}
