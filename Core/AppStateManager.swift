//
// File Path: Core/AppStateManager.swift
// Description: Global application state management
// Manages app-wide state, preferences, and coordination between systems
//

import Foundation
import SwiftUI
import Combine

@MainActor
class AppStateManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoggedIn = false
    @Published var currentUser: User?
    @Published var currentWorld: String?
    @Published var appMode: AppMode = .normal
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showAboutWindow = false
    
    // Preferences
    @Published var autoConnect = false
    @Published var rememberLogin = false
    @Published var graphicsQuality: GraphicsQuality = .high
    @Published var soundEnabled = true
    @Published var showFPS = false
    @Published var showNetworkStats = false
    
    // UI State
    @Published var selectedTab = 0
    @Published var sidebarSelection: String?
    @Published var isFullscreen = false
    @Published var currentTheme: AppTheme = .dark
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    private let keychain = KeychainManager.shared
    
    // MARK: - App Mode
    enum AppMode {
        case normal
        case buildMode
        case spectator
        case vr
        case ar
    }
    
    enum GraphicsQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case ultra = "Ultra"
    }
    
    enum AppTheme: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"
        case auto = "Auto"
    }
    
    // MARK: - Initialization
    init() {
        loadUserPreferences()
        setupBindings()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Save preferences when they change
        $autoConnect
            .sink { [weak self] value in
                self?.userDefaults.set(value, forKey: "autoConnect")
            }
            .store(in: &cancellables)
        
        $rememberLogin
            .sink { [weak self] value in
                self?.userDefaults.set(value, forKey: "rememberLogin")
            }
            .store(in: &cancellables)
        
        $graphicsQuality
            .sink { [weak self] quality in
                self?.userDefaults.set(quality.rawValue, forKey: "graphicsQuality")
                self?.applyGraphicsSettings(quality)
            }
            .store(in: &cancellables)
        
        $soundEnabled
            .sink { [weak self] enabled in
                self?.userDefaults.set(enabled, forKey: "soundEnabled")
            }
            .store(in: &cancellables)
        
        $currentTheme
            .sink { [weak self] theme in
                self?.userDefaults.set(theme.rawValue, forKey: "appTheme")
                self?.applyTheme(theme)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - User Preferences
    func loadUserPreferences() {
        autoConnect = userDefaults.bool(forKey: "autoConnect")
        rememberLogin = userDefaults.bool(forKey: "rememberLogin")
        soundEnabled = userDefaults.bool(forKey: "soundEnabled")
        showFPS = userDefaults.bool(forKey: "showFPS")
        showNetworkStats = userDefaults.bool(forKey: "showNetworkStats")
        
        if let qualityString = userDefaults.string(forKey: "graphicsQuality"),
           let quality = GraphicsQuality(rawValue: qualityString) {
            graphicsQuality = quality
        }
        
        if let themeString = userDefaults.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: themeString) {
            currentTheme = theme
        }
        
        // Load saved login if remember is enabled
        if rememberLogin {
            loadSavedLogin()
        }
    }
    
    func saveUserPreferences() {
        userDefaults.set(autoConnect, forKey: "autoConnect")
        userDefaults.set(rememberLogin, forKey: "rememberLogin")
        userDefaults.set(graphicsQuality.rawValue, forKey: "graphicsQuality")
        userDefaults.set(soundEnabled, forKey: "soundEnabled")
        userDefaults.set(showFPS, forKey: "showFPS")
        userDefaults.set(showNetworkStats, forKey: "showNetworkStats")
        userDefaults.set(currentTheme.rawValue, forKey: "appTheme")
    }
    
    // MARK: - Login Management
    func login(username: String, password: String) async throws {
        // Perform login through network manager
        let networkManager = NetworkManager()
        try await networkManager.authenticate(username: username, password: password)
        
        // Create user object
        currentUser = User(username: username, id: UUID())
        isLoggedIn = true
        
        // Save credentials if remember is enabled
        if rememberLogin {
            saveCredentials(username: username, password: password)
        }
    }
    
    func logout() {
        isLoggedIn = false
        currentUser = nil
        currentWorld = nil
        
        // Clear saved credentials
        if !rememberLogin {
            clearSavedCredentials()
        }
        
        // Notify other systems
        NotificationCenter.default.post(name: .userLoggedOut, object: nil)
    }
    
    private func saveCredentials(username: String, password: String) {
        userDefaults.set(username, forKey: "savedUsername")
        keychain.save(password, for: "userPassword")
    }
    
    private func loadSavedLogin() {
        guard let username = userDefaults.string(forKey: "savedUsername"),
              let password = keychain.load(for: "userPassword") else {
            return
        }
        
        // Auto-login if enabled
        if autoConnect {
            Task {
                try? await login(username: username, password: password)
            }
        }
    }
    
    private func clearSavedCredentials() {
        userDefaults.removeObject(forKey: "savedUsername")
        keychain.delete(for: "userPassword")
    }
    
    // MARK: - Error Handling
    func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    func dismissError() {
        showError = false
        errorMessage = ""
    }
    
    func showInitializationError(_ error: Error) {
        showError("Failed to initialize: \(error.localizedDescription)")
    }
    
    // MARK: - App Mode
    func setAppMode(_ mode: AppMode) {
        appMode = mode
        
        // Configure systems for the mode
        switch mode {
        case .normal:
            configureNormalMode()
        case .buildMode:
            configureBuildMode()
        case .spectator:
            configureSpectatorMode()
        case .vr:
            configureVRMode()
        case .ar:
            configureARMode()
        }
    }
    
    private func configureNormalMode() {
        // Standard gameplay configuration
    }
    
    private func configureBuildMode() {
        // Enable building tools and UI
        NotificationCenter.default.post(name: .enterBuildMode, object: nil)
    }
    
    private func configureSpectatorMode() {
        // Disable collision, enable free camera
        NotificationCenter.default.post(name: .enterSpectatorMode, object: nil)
    }
    
    private func configureVRMode() {
        // Setup VR rendering and controls
        #if os(visionOS)
        NotificationCenter.default.post(name: .enterVRMode, object: nil)
        #endif
    }
    
    private func configureARMode() {
        // Setup AR features
        #if os(iOS)
        NotificationCenter.default.post(name: .enterARMode, object: nil)
        #endif
    }
    
    // MARK: - Graphics Settings
    private func applyGraphicsSettings(_ quality: GraphicsQuality) {
        var settings = RenderSettings()
        
        switch quality {
        case .low:
            settings.renderScale = 0.75
            settings.shadowsEnabled = false
            settings.postProcessSettings.bloomEnabled = false
            settings.msaaSampleCount = 1
            
        case .medium:
            settings.renderScale = 1.0
            settings.shadowsEnabled = true
            settings.shadowMapSize = 1024
            settings.postProcessSettings.bloomEnabled = true
            settings.msaaSampleCount = 2
            
        case .high:
            settings.renderScale = 1.0
            settings.shadowsEnabled = true
            settings.shadowMapSize = 2048
            settings.postProcessSettings.bloomEnabled = true
            settings.postProcessSettings.fxaaEnabled = true
            settings.msaaSampleCount = 4
            
        case .ultra:
            settings.renderScale = 1.0
            settings.shadowsEnabled = true
            settings.shadowMapSize = 4096
            settings.shadowCascades = 4
            settings.postProcessSettings.bloomEnabled = true
            settings.postProcessSettings.fxaaEnabled = true
            settings.postProcessSettings.depthOfFieldEnabled = true
            settings.msaaSampleCount = 8
        }
        
        // Apply settings to render pipeline
        NotificationCenter.default.post(
            name: .graphicsSettingsChanged,
            object: nil,
            userInfo: ["settings": settings]
        )
    }
    
    // MARK: - Theme Management
    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .light:
            setLightTheme()
        case .dark:
            setDarkTheme()
        case .auto:
            setAutoTheme()
        }
    }
    
    private func setLightTheme() {
        #if os(macOS)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        #endif
    }
    
    private func setDarkTheme() {
        #if os(macOS)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        #endif
    }
    
    private func setAutoTheme() {
        #if os(macOS)
        NSApplication.shared.appearance = nil
        #endif
    }
    
    // MARK: - Window Management
    func toggleFullscreen() {
        isFullscreen.toggle()
        
        #if os(macOS)
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
        #endif
    }
    
    func resetWindowLayout() {
        // Reset to default window positions and sizes
        NotificationCenter.default.post(name: .resetWindowLayout, object: nil)
    }
    
    // MARK: - State Persistence
    func saveAppState() {
        let state = AppState(
            currentWorld: currentWorld,
            selectedTab: selectedTab,
            sidebarSelection: sidebarSelection,
            windowFrame: getWindowFrame()
        )
        
        if let data = try? JSONEncoder().encode(state) {
            userDefaults.set(data, forKey: "appState")
        }
    }
    
    func restoreAppState() {
        guard let data = userDefaults.data(forKey: "appState"),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return
        }
        
        currentWorld = state.currentWorld
        selectedTab = state.selectedTab
        sidebarSelection = state.sidebarSelection
        
        if let frame = state.windowFrame {
            setWindowFrame(frame)
        }
    }
    
    private func getWindowFrame() -> CGRect? {
        #if os(macOS)
        return NSApplication.shared.windows.first?.frame
        #else
        return nil
        #endif
    }
    
    private func setWindowFrame(_ frame: CGRect) {
        #if os(macOS)
        NSApplication.shared.windows.first?.setFrame(frame, display: true)
        #endif
    }
 }

 // MARK: - Supporting Types
 struct User: Identifiable, Codable {
    let id: UUID
    let username: String
    var displayName: String?
    var avatarURL: URL?
    var level: Int = 1
    var experience: Int = 0
 }

 struct AppState: Codable {
    let currentWorld: String?
    let selectedTab: Int
    let sidebarSelection: String?
    let windowFrame: CGRect?
 }

 // MARK: - Keychain Manager
 class KeychainManager {
    static let shared = KeychainManager()
    
    func save(_ password: String, for key: String) {
        let data = password.data(using: .utf8)!
        
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ] as CFDictionary
        
        SecItemDelete(query)
        SecItemAdd(query, nil)
    }
    
    func load(for key: String) -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        
        if let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    func delete(for key: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ] as CFDictionary
        
        SecItemDelete(query)
    }
 }

 // MARK: - Notifications
 extension Notification.Name {
    static let userLoggedOut = Notification.Name("userLoggedOut")
    static let enterBuildMode = Notification.Name("enterBuildMode")
    static let enterSpectatorMode = Notification.Name("enterSpectatorMode")
    static let enterVRMode = Notification.Name("enterVRMode")
    static let enterARMode = Notification.Name("enterARMode")
    static let graphicsSettingsChanged = Notification.Name("graphicsSettingsChanged")
    static let resetWindowLayout = Notification.Name("resetWindowLayout")
 }
