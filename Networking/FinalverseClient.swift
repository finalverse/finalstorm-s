//
//  Networking/FinalverseClient.swift
//  FinalStorm
//
//  Enhanced network client for Finalverse services with better integration
//

import Foundation
import Combine

@MainActor
class FinalverseClient: ObservableObject {
    @Published var connectedServices: Set<Service> = []
    @Published var connectionStatus: [Service: ConnectionStatus] = [:]
    @Published var lastError: FinalverseNetworkError?
    
    private var serviceClients: [Service: ServiceClient] = [:]
    private let session: URLSession
    private let baseURL: String
    
    enum Service: String, CaseIterable {
        case songEngine = "song-engine"
        case echoEngine = "echo-engine"
        case aiOrchestra = "ai-orchestra"
        case harmonyService = "harmony-service"
        case storyEngine = "story-engine"
        case worldEngine = "world-engine"
        case symphonyEngine = "symphony-engine"
        case silenceService = "silence-service"
        
        var port: Int {
            switch self {
            case .songEngine: return 3001
            case .echoEngine: return 3003
            case .aiOrchestra: return 3004
            case .harmonyService: return 3006
            case .storyEngine: return 3002
            case .worldEngine: return 3002
            case .symphonyEngine: return 3005
            case .silenceService: return 3009
            }
        }
        
        var displayName: String {
            return rawValue.capitalized.replacingOccurrences(of: "-", with: " ")
        }
    }
    
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    enum FinalverseNetworkError: Error, LocalizedError {
        case serviceUnavailable(Service)
        case connectionFailed(Service)
        case requestFailed(Service, String)
        case decodingFailed(Service)
        case timeout(Service)
        
        var errorDescription: String? {
            switch self {
            case .serviceUnavailable(let service):
                return "\(service.displayName) is unavailable"
            case .connectionFailed(let service):
                return "Failed to connect to \(service.displayName)"
            case .requestFailed(let service, let reason):
                return "\(service.displayName) request failed: \(reason)"
            case .decodingFailed(let service):
                return "Failed to decode response from \(service.displayName)"
            case .timeout(let service):
                return "\(service.displayName) request timed out"
            }
        }
    }
    
    init(baseURL: String = "http://localhost") {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Service Management
    
    func connectToService(_ service: Service) async throws {
        connectionStatus[service] = .connecting
        
        let client = ServiceClient(service: service, baseURL: baseURL, session: session)
        
        do {
            try await client.connect()
            serviceClients[service] = client
            connectedServices.insert(service)
            connectionStatus[service] = .connected
            
            print("Connected to \(service.displayName)")
            
        } catch {
            connectionStatus[service] = .error(error.localizedDescription)
            let finalverseError = FinalverseNetworkError.connectionFailed(service)
            lastError = finalverseError
            throw finalverseError
        }
    }
    
    func disconnectFromService(_ service: Service) {
        serviceClients.removeValue(forKey: service)
        connectedServices.remove(service)
        connectionStatus[service] = .disconnected
        
        print("Disconnected from \(service.displayName)")
    }
    
    func connectToAllServices() async throws {
        await withTaskGroup(of: Void.self) { group in
            for service in Service.allCases {
                group.addTask {
                    do {
                        try await self.connectToService(service)
                    } catch {
                        print("Failed to connect to \(service.displayName): \(error)")
                    }
                }
            }
        }
    }
    
    func disconnectFromAllServices() {
        for service in Service.allCases {
            disconnectFromService(service)
        }
    }
    
    // MARK: - Service Requests
    
    func request<T: Codable>(_ endpoint: ServiceEndpoint, from service: Service) async throws -> T {
        guard let client = serviceClients[service] else {
            throw FinalverseNetworkError.serviceUnavailable(service)
        }
        
        do {
            return try await client.request(endpoint)
        } catch {
            let finalverseError = FinalverseNetworkError.requestFailed(service, error.localizedDescription)
            lastError = finalverseError
            throw finalverseError
        }
    }
    
    // MARK: - Convenience Methods for Specific Services
    
    func getSongs() async throws -> SongsResponse {
        return try await request(.getSongs, from: .songEngine)
    }
    
    func getWorldData(for coordinate: GridCoordinate) async throws -> WorldDataResponse {
        let endpoint = ServiceEndpoint.getWorldData(coordinate: coordinate)
        return try await request(endpoint, from: .worldEngine)
    }
    
    func performSongweaving(_ song: Song, at position: SIMD3<Float>) async throws -> SongweavingResponse {
        let endpoint = ServiceEndpoint.performSongweaving(song: song, position: position)
        return try await request(endpoint, from: .harmonyService)
    }
    
    func getHarmonyLevel(at position: SIMD3<Float>) async throws -> HarmonyResponse {
        let endpoint = ServiceEndpoint.getHarmony(position: position)
        return try await request(endpoint, from: .harmonyService)
    }
    
    // MARK: - Health Checks
    
    func checkServiceHealth(_ service: Service) async -> Bool {
        guard let client = serviceClients[service] else { return false }
        
        do {
            let _: HealthResponse = try await client.request(.health)
            return true
        } catch {
            return false
        }
    }
    
    func checkAllServicesHealth() async -> [Service: Bool] {
        var results: [Service: Bool] = [:]
        
        await withTaskGroup(of: (Service, Bool).self) { group in
            for service in Service.allCases {
                group.addTask {
                    let isHealthy = await self.checkServiceHealth(service)
                    return (service, isHealthy)
                }
            }
            
            for await (service, isHealthy) in group {
                results[service] = isHealthy
            }
        }
        
        return results
    }
}

// MARK: - Service Client

private class ServiceClient {
    let service: FinalverseClient.Service
    let baseURL: String
    let session: URLSession
    
    var serviceEndpoint: URL {
        return URL(string: "\(baseURL):\(service.port)")!
    }
    
    init(service: FinalverseClient.Service, baseURL: String, session: URLSession) {
        self.service = service
        self.baseURL = baseURL
        self.session = session
    }
    
    func connect() async throws {
        let url = serviceEndpoint.appendingPathComponent("health")
        let (_, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FinalverseClient.FinalverseNetworkError.connectionFailed(service)
        }
    }
    
    func request<T: Codable>(_ endpoint: ServiceEndpoint) async throws -> T {
        let url = serviceEndpoint.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FinalverseClient.FinalverseNetworkError.requestFailed(service, "Invalid response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let statusMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw FinalverseClient.FinalverseNetworkError.requestFailed(service, statusMessage)
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FinalverseClient.FinalverseNetworkError.decodingFailed(service)
        }
    }
}

// MARK: - Service Endpoints

struct ServiceEndpoint {
    let path: String
    let method: String
    let body: Data?
    
    init(path: String, method: String = "GET", body: Data? = nil) {
        self.path = path
        self.method = method
        self.body = body
    }
    
    // MARK: - Predefined Endpoints
    
    static let health = ServiceEndpoint(path: "/health")
    static let getSongs = ServiceEndpoint(path: "/songs")
    
    static func getWorldData(coordinate: GridCoordinate) -> ServiceEndpoint {
        return ServiceEndpoint(path: "/world/\(coordinate.x)/\(coordinate.z)")
    }
    
    static func performSongweaving(song: Song, position: SIMD3<Float>) -> ServiceEndpoint {
        let payload = SongweavingRequest(song: song, position: position)
        let body = try? JSONEncoder().encode(payload)
        return ServiceEndpoint(path: "/songweaving", method: "POST", body: body)
    }
    
    static func getHarmony(position: SIMD3<Float>) -> ServiceEndpoint {
        return ServiceEndpoint(path: "/harmony?x=\(position.x)&y=\(position.y)&z=\(position.z)")
    }
}

// MARK: - Response Types

struct SongsResponse: Codable {
    let songs: [Song]
    let totalCount: Int
}

struct Song: Codable {
    let id: UUID
    let name: String
    let category: String
    let harmonyType: HarmonyType
    let duration: TimeInterval
    let difficulty: Int
    
    enum HarmonyType: String, Codable {
        case restoration = "restoration"
        case creation = "creation"
        case transformation = "transformation"
        case protection = "protection"
        case purification = "purification"
    }
}

struct WorldDataResponse: Codable {
    let coordinate: GridCoordinate
    let biome: BiomeType
    let harmonyLevel: Float
    let features: [WorldFeature]
    let entities: [EntityData]
}

struct EntityData: Codable {
    let id: UUID
    let type: String
    let position: SIMD3<Float>
    let properties: [String: String]
}

struct SongweavingRequest: Codable {
    let song: Song
    let position: SIMD3<Float>
}

struct SongweavingResponse: Codable {
    let success: Bool
    let effectRadius: Float
    let harmonyDelta: Float
    let message: String
}

struct HarmonyResponse: Codable {
    let position: SIMD3<Float>
    let harmonyLevel: Float
    let dissonanceLevel: Float
    let stabilityIndex: Float
}

struct HealthResponse: Codable {
    let status: String
    let uptime: TimeInterval
    let version: String
}
