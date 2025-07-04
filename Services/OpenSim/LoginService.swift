//
//  Services/OpenSim/LoginService.swift
//  FinalStorm
//
//  OpenSimulator login service for authentication and session management
//  Handles XML-RPC login, CAPS capabilities, and session persistence
//

import Foundation
import Combine

@MainActor
class LoginService: ObservableObject {
    // MARK: - Properties
    @Published var isLoggedIn = false
    @Published var currentSession: SessionInfo?
    @Published var availableGrids: [GridInfo] = []
    @Published var loginState: LoginState = .idle
    
    private let openSimProtocol: OpenSimProtocol  // FIXED: Use consistent naming
    private let credentialsStore: CredentialsStore
    private var cancellables = Set<AnyCancellable>()
    
    enum LoginState {
        case idle
        case authenticating
        case connecting
        case establishingSession
        case loggedIn
        case error(String)
    }
    
    // MARK: - Initialization
    init() {
        self.openSimProtocol = OpenSimProtocol()  // FIXED: Use correct type name
        self.credentialsStore = CredentialsStore()
        
        setupBindings()
        loadAvailableGrids()
    }
    
    private func setupBindings() {
        openSimProtocol.$connectionState  // FIXED: Use correct property name
            .sink { [weak self] state in
                self?.updateLoginState(from: state)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func login(grid: GridInfo, credentials: LoginCredentials, rememberCredentials: Bool = false) async throws {
        loginState = .authenticating
        
        do {
            // Store credentials if requested
            if rememberCredentials {
                try credentialsStore.store(credentials, for: grid)
            }
            
            // Perform login
            try await openSimProtocol.connect(to: grid, credentials: credentials)  // FIXED: Use correct method name
            
            // Create session
            currentSession = SessionInfo(
                grid: grid,
                credentials: credentials,
                loginTime: Date(),
                lastActivity: Date()
            )
            
            isLoggedIn = true
            loginState = .loggedIn
            
        } catch {
            loginState = .error(error.localizedDescription)
            throw error
        }
    }
    
    func logout() async {
        // Send logout message if connected
        if isLoggedIn {
            do {
                try await sendLogoutMessage()
            } catch {
                print("Error during logout: \(error)")
            }
        }
        
        // Disconnect protocol
        openSimProtocol.disconnect()  // FIXED: Use correct property name
        
        // Clear session
        currentSession = nil
        isLoggedIn = false
        loginState = .idle
    }
    
    func getStoredCredentials(for grid: GridInfo) -> LoginCredentials? {
        return credentialsStore.retrieve(for: grid)
    }
    
    func removeStoredCredentials(for grid: GridInfo) {
        credentialsStore.remove(for: grid)
    }
    
    func testGridConnection(_ grid: GridInfo) async -> Bool {
        do {
            // Test connection to grid's login endpoint
            let url = URL(string: "\(grid.loginURI)/")!
            let (_, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Grid Management
    private func loadAvailableGrids() {
        availableGrids = [
            GridInfo(name: "OSGrid", loginURI: "http://login.osgrid.org", gridNick: "OSGrid"),
            GridInfo(name: "Metropolis", loginURI: "http://hypergrid.org:8002", gridNick: "Metropolis"),
            GridInfo(name: "Local OpenSim", loginURI: "http://localhost:9000", gridNick: "Local"),
            GridInfo(name: "Kitely", loginURI: "https://grid.kitely.com:8002", gridNick: "Kitely"),
            GridInfo(name: "InWorldz", loginURI: "https://inworldz.com:8003", gridNick: "InWorldz")
        ]
    }
    
    func addCustomGrid(_ grid: GridInfo) {
        if !availableGrids.contains(where: { $0.loginURI == grid.loginURI }) {
            availableGrids.append(grid)
            saveGridsToUserDefaults()
        }
    }
    
    func removeGrid(_ grid: GridInfo) {
        availableGrids.removeAll { $0.loginURI == grid.loginURI }
        saveGridsToUserDefaults()
    }
    
    // MARK: - Session Management
    func refreshSession() async throws {
        guard let session = currentSession else {
            throw LoginError.noActiveSession
        }
        
        // Update last activity
        currentSession?.lastActivity = Date()
        
        // Check if session is still valid
        let timeSinceLogin = Date().timeIntervalSince(session.loginTime)
        if timeSinceLogin > 86400 { // 24 hours
            // Session expired, need to re-login
            try await login(grid: session.grid, credentials: session.credentials)
        }
    }
    
    private func updateLoginState(from protocolState: OpenSimProtocol.ConnectionState) {
        switch protocolState {
        case .disconnected:
            if loginState != .idle {
                loginState = .idle
            }
        case .connecting:
            loginState = .connecting
        case .authenticating:
            loginState = .authenticating
        case .connected:
            loginState = .establishingSession
        case .error(let message):
            loginState = .error(message)
        }
    }
    
    private func sendLogoutMessage() async throws {
        // Send logout notification to grid
        // This is typically done via a CAPS call or UDP message
        print("Sending logout message to grid")
    }
    
    // MARK: - Persistence
    private func saveGridsToUserDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(availableGrids) {
            UserDefaults.standard.set(data, forKey: "SavedGrids")
        }
    }
    
    private func loadGridsFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "SavedGrids") else { return }
        
        let decoder = JSONDecoder()
        if let savedGrids = try? decoder.decode([GridInfo].self, from: data) {
            // Merge with default grids
            for grid in savedGrids {
                if !availableGrids.contains(where: { $0.loginURI == grid.loginURI }) {
                    availableGrids.append(grid)
                }
            }
        }
    }
}

// MARK: - Session Info
struct SessionInfo {
    let grid: GridInfo
    let credentials: LoginCredentials
    let loginTime: Date
    var lastActivity: Date
    var capabilities: [String: URL] = [:]
    var regionInfo: RegionInfo?
    
    var isExpired: Bool {
        Date().timeIntervalSince(lastActivity) > 3600 // 1 hour of inactivity
    }
    
    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(loginTime)
    }
}

// MARK: - Credentials Store
class CredentialsStore {
    private let keychain = KeychainManager()
    
    func store(_ credentials: LoginCredentials, for grid: GridInfo) throws {
        let key = "opensim_credentials_\(grid.gridNick)"
        let data = try JSONEncoder().encode(credentials)
        try keychain.store(data, forKey: key)
    }
    
    func retrieve(for grid: GridInfo) -> LoginCredentials? {
        let key = "opensim_credentials_\(grid.gridNick)"
        guard let data = keychain.retrieve(forKey: key),
              let credentials = try? JSONDecoder().decode(LoginCredentials.self, from: data) else {
            return nil
        }
        return credentials
    }
    
    func remove(for grid: GridInfo) {
        let key = "opensim_credentials_\(grid.gridNick)"
        keychain.remove(forKey: key)
    }
}

// MARK: - Keychain Manager
class KeychainManager {
    func store(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed
        }
    }
    
    func retrieve(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }
        
        return result as? Data
    }
    
    func remove(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Error Types
enum LoginError: Error, LocalizedError {
    case invalidCredentials
    case gridUnavailable
    case networkError
    case noActiveSession
    case sessionExpired
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .gridUnavailable:
            return "Grid is currently unavailable"
        case .networkError:
            return "Network connection error"
        case .noActiveSession:
            return "No active session"
        case .sessionExpired:
            return "Session has expired"
        }
    }
}

enum KeychainError: Error {
    case storeFailed
    case retrieveFailed
}

// MARK: - Extensions
extension GridInfo: Equatable {
    static func == (lhs: GridInfo, rhs: GridInfo) -> Bool {
        return lhs.loginURI == rhs.loginURI
    }
}
