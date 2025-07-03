//
//  AppStateManager.swift
//  FinalStorm
//
//  Manages global application state
//

import Foundation
import Combine

@MainActor
class AppStateManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var currentWorld: WorldInfo?
    @Published var currentRegion: RegionInfo?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var userProfile: UserProfile?
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    func login(username: String, password: String) async throws {
        connectionState = .connecting
        
        // Simulate login process
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        userProfile = UserProfile(
            id: UUID(),
            username: username,
            displayName: username
        )
        
        isLoggedIn = true
        connectionState = .connected
    }
    
    func logout() {
        isLoggedIn = false
        userProfile = nil
        currentWorld = nil
        currentRegion = nil
        connectionState = .disconnected
    }
}

// MARK: - Supporting Types
struct WorldInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let imageURL: URL?
    let playerCount: Int
}

struct RegionInfo: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: RegionCoordinate
    let ownerName: String?
}

struct RegionCoordinate {
    let x: Int
    let z: Int
}

struct UserProfile: Identifiable {
    let id: UUID
    let username: String
    let displayName: String
    
    static let `default` = UserProfile(
        id: UUID(),
        username: "guest",
        displayName: "Guest User"
    )
}
