//
// File Path: Services/FVServicesManager.swift
// Description: Manages connections to all Finalverse microservices
// Provides unified interface for interacting with the service ecosystem
//

import Foundation
import Combine

@MainActor
class FVServicesManager: ObservableObject {
   
   // MARK: - Service Status
   @Published var servicesStatus: [ServiceType: ServiceStatus] = [:]
   @Published var overallHealth: SystemHealth = .unknown
   
   // MARK: - Service Endpoints
   private let serviceEndpoints: [ServiceType: String] = [
       .gateway: "http://localhost:8080",
       .worldEngine: "http://localhost:3002",
       .aiOrchestra: "http://localhost:3004",
       .songEngine: "http://localhost:3001",
       .echoEngine: "http://localhost:3003",
       .harmonyService: "http://localhost:3006",
       .assetService: "http://localhost:3007",
       .communityService: "http://localhost:3008",
       .silenceService: "http://localhost:3009",
       .proceduralGen: "http://localhost:3010",
       .behaviorAI: "http://localhost:3011"
   ]
   
   // MARK: - Service Clients
   private var worldEngineClient: WorldEngineClient?
   private var aiOrchestraClient: AIOrchstraClient?
   private var assetServiceClient: AssetServiceClient?
   private var communityClient: CommunityServiceClient?
   
   // MARK: - WebSocket Connections
   private var worldEngineSocket: URLSessionWebSocketTask?
   private var eventStreamSocket: URLSessionWebSocketTask?
   
   // MARK: - Initialization
   override init() {
       super.init()
       initializeServiceClients()
       startHealthMonitoring()
   }
   
   // MARK: - Service Client Initialization
   private func initializeServiceClients() {
       worldEngineClient = WorldEngineClient(baseURL: serviceEndpoints[.worldEngine]!)
       aiOrchestraClient = AIOrchstraClient(baseURL: serviceEndpoints[.aiOrchestra]!)
       assetServiceClient = AssetServiceClient(baseURL: serviceEndpoints[.assetService]!)
       communityClient = CommunityServiceClient(baseURL: serviceEndpoints[.communityService]!)
   }
   
   // MARK: - Health Monitoring
   private func startHealthMonitoring() {
       Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
           Task {
               await self.checkAllServicesHealth()
           }
       }
   }
   
   private func checkAllServicesHealth() async {
       await withTaskGroup(of: (ServiceType, ServiceStatus).self) { group in
           for (service, endpoint) in serviceEndpoints {
               group.addTask {
                   let status = await self.checkServiceHealth(service, endpoint: endpoint)
                   return (service, status)
               }
           }
           
           for await (service, status) in group {
               servicesStatus[service] = status
           }
       }
       
       updateOverallHealth()
   }
   
   private func checkServiceHealth(_ service: ServiceType, endpoint: String) async -> ServiceStatus {
       do {
           let url = URL(string: "\(endpoint)/health")!
           let (data, response) = try await URLSession.shared.data(from: url)
           
           guard let httpResponse = response as? HTTPURLResponse,
                 httpResponse.statusCode == 200 else {
               return .unhealthy("HTTP error")
           }
           
           if let healthData = try? JSONDecoder().decode(HealthResponse.self, from: data) {
               return .healthy(healthData.version, healthData.uptime)
           }
           
           return .healthy("Unknown", 0)
           
       } catch {
           return .offline(error.localizedDescription)
       }
   }
   
   private func updateOverallHealth() {
       let healthyCount = servicesStatus.values.filter { status in
           if case .healthy = status { return true }
           return false
       }.count
       
       let totalCount = servicesStatus.count
       
       if healthyCount == totalCount {
           overallHealth = .healthy
       } else if healthyCount >= totalCount / 2 {
           overallHealth = .degraded
       } else if healthyCount > 0 {
           overallHealth = .critical
       } else {
           overallHealth = .offline
       }
   }
   
   // MARK: - World Engine Integration
   func connectToWorldEngine() async throws {
       guard let wsURL = URL(string: "ws://localhost:3000/ws") else {
           throw ServiceError.invalidEndpoint
       }
       
       worldEngineSocket = URLSession.shared.webSocketTask(with: wsURL)
       worldEngineSocket?.resume()
       
       // Start receiving messages
       Task {
           await receiveWorldEngineMessages()
       }
       
       // Send initial connection message
       let connectMessage = WorldEngineMessage.connect(
           playerId: getCurrentPlayerId(),
           token: getAuthToken()
       )
       
       try await sendWorldEngineMessage(connectMessage)
   }
   
   private func receiveWorldEngineMessages() async {
       guard let socket = worldEngineSocket else { return }
       
       do {
           while true {
               let message = try await socket.receive()
               
               switch message {
               case .string(let text):
                   await processWorldEngineMessage(text)
               case .data(let data):
                   await processWorldEngineBinaryMessage(data)
               @unknown default:
                   break
               }
           }
       } catch {
           print("WebSocket receive error: \(error)")
           // Attempt reconnection
           Task {
               try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
               try? await connectToWorldEngine()
           }
       }
   }
   
   private func processWorldEngineMessage(_ text: String) async {
       guard let data = text.data(using: .utf8),
             let message = try? JSONDecoder().decode(WorldEngineResponse.self, from: data) else {
           return
       }
       
       switch message.type {
       case "world_update":
           await handleWorldUpdate(message.data)
       case "entity_spawn":
           await handleEntitySpawn(message.data)
       case "quest_update":
           await handleQuestUpdate(message.data)
       default:
           print("Unknown message type: \(message.type)")
       }
   }
   
   private func sendWorldEngineMessage(_ message: WorldEngineMessage) async throws {
       guard let socket = worldEngineSocket else {
           throw ServiceError.notConnected
       }
       
       let encoder = JSONEncoder()
       let data = try encoder.encode(message)
       let string = String(data: data, encoding: .utf8)!
       
       try await socket.send(.string(string))
   }
   
   // MARK: - AI Orchestra Integration
   func requestAIGeneration(_ request: AIGenerationRequest) async throws -> AIGenerationResponse {
       guard let client = aiOrchestraClient else {
           throw ServiceError.clientNotInitialized
       }
       
       return try await client.generateContent(request)
   }
   
   func streamAIResponse(_ prompt: String) -> AsyncThrowingStream<AIStreamChunk, Error> {
       return AsyncThrowingStream { continuation in
           Task {
               do {
                   let streamURL = URL(string: "\(serviceEndpoints[.aiOrchestra]!)/stream")!
                   var request = URLRequest(url: streamURL)
                   request.httpMethod = "POST"
                   request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                   
                   let body = ["prompt": prompt]
                   request.httpBody = try JSONEncoder().encode(body)
                   
                   let (bytes, _) = try await URLSession.shared.bytes(for: request)
                   
                   for try await line in bytes.lines {
                       if line.hasPrefix("data: ") {
                           let jsonString = String(line.dropFirst(6))
                           if let data = jsonString.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(AIStreamChunk.self, from: data) {
                               continuation.yield(chunk)
                           }
                       }
                   }
                   
                   continuation.finish()
                   
               } catch {
                   continuation.finish(throwing: error)
               }
           }
       }
   }
   
   // MARK: - Asset Service Integration
   func loadAsset(_ assetId: String) async throws -> AssetData {
       guard let client = assetServiceClient else {
           throw ServiceError.clientNotInitialized
       }
       
       return try await client.fetchAsset(assetId)
   }
   
   func uploadAsset(_ asset: AssetUpload) async throws -> AssetUploadResponse {
       guard let client = assetServiceClient else {
           throw ServiceError.clientNotInitialized
       }
       
       return try await client.uploadAsset(asset)
   }
   
   // MARK: - Community Service Integration
   func joinCommunity(_ communityId: String) async throws {
       guard let client = communityClient else {
           throw ServiceError.clientNotInitialized
       }
       
       try await client.joinCommunity(communityId, userId: getCurrentPlayerId())
   }
   
   func getCommunityEvents() async throws -> [CommunityEvent] {
       guard let client = communityClient else {
           throw ServiceError.clientNotInitialized
       }
       
       return try await client.getUpcomingEvents()
   }
   
   // MARK: - Procedural Generation
   func generateTerrain(_ params: TerrainGenerationParams) async throws -> GeneratedTerrain {
       let url = URL(string: "\(serviceEndpoints[.proceduralGen]!)/generate/terrain")!
       
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
       request.httpBody = try JSONEncoder().encode(params)
       
       let (data, _) = try await URLSession.shared.data(for: request)
       return try JSONDecoder().decode(GeneratedTerrain.self, from: data)
   }
   
   // MARK: - Helper Methods
   private func getCurrentPlayerId() -> String {
       // Return current player ID from app state
       return AppStateManager.shared.userProfile?.id.uuidString ?? "unknown"
   }
   
   private func getAuthToken() -> String {
       // Return auth token from secure storage
       return UserDefaults.standard.string(forKey: "authToken") ?? ""
   }
   
   private func handleWorldUpdate(_ data: Any) async {
       // Process world update data
       print("World update received: \(data)")
   }
   
   private func handleEntitySpawn(_ data: Any) async {
       // Process entity spawn data
       print("Entity spawn received: \(data)")
   }
   
   private func handleQuestUpdate(_ data: Any) async {
       // Process quest update data
       print("Quest update received: \(data)")
   }
   
   private func processWorldEngineBinaryMessage(_ data: Data) async {
       // Process binary messages (e.g., compressed world data)
       print("Binary message received: \(data.count) bytes")
   }
}

// MARK: - Service Types
enum ServiceType: String, CaseIterable {
   case gateway = "API Gateway"
   case worldEngine = "World Engine"
   case aiOrchestra = "AI Orchestra"
   case songEngine = "Song Engine"
   case echoEngine = "Echo Engine"
   case harmonyService = "Harmony Service"
   case assetService = "Asset Service"
   case communityService = "Community Service"
   case silenceService = "Silence Service"
   case proceduralGen = "Procedural Generation"
   case behaviorAI = "Behavior AI"
}

enum ServiceStatus {
   case healthy(String, TimeInterval) // version, uptime
   case degraded(String)
   case unhealthy(String)
   case offline(String)
}

enum SystemHealth {
   case healthy
   case degraded
   case critical
   case offline
   case unknown
}

enum ServiceError: Error {
   case invalidEndpoint
   case notConnected
   case clientNotInitialized
   case authenticationFailed
   case requestFailed(String)
}

// MARK: - Service Response Types
struct HealthResponse: Codable {
   let status: String
   let version: String
   let uptime: TimeInterval
   let services: [String: String]?
}

struct WorldEngineMessage: Codable {
   let type: String
   let data: [String: Any]
   
   static func connect(playerId: String, token: String) -> WorldEngineMessage {
       return WorldEngineMessage(
           type: "connect",
           data: ["playerId": playerId, "token": token]
       )
   }
   
   enum CodingKeys: String, CodingKey {
       case type
       case data
   }
   
   func encode(to encoder: Encoder) throws {
       var container = encoder.container(keyedBy: CodingKeys.self)
       try container.encode(type, forKey: .type)
       
       let jsonData = try JSONSerialization.data(withJSONObject: data)
       let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
       try container.encode(jsonObject as! [String: String], forKey: .data)
   }
}

struct WorldEngineResponse: Codable {
   let type: String
   let data: Any
   
   enum CodingKeys: String, CodingKey {
       case type
       case data
   }
   
   init(from decoder: Decoder) throws {
       let container = try decoder.container(keyedBy: CodingKeys.self)
       type = try container.decode(String.self, forKey: .type)
       data = try container.decode([String: Any].self, forKey: .data)
   }
}

// MARK: - Service Client Implementations
class WorldEngineClient {
   private let baseURL: String
   
   init(baseURL: String) {
       self.baseURL = baseURL
   }
   
   func getWorldState() async throws -> WorldState {
       // Implementation
       return WorldState()
   }
}

class AIOrchstraClient {
   private let baseURL: String
   
   init(baseURL: String) {
       self.baseURL = baseURL
   }
   
   func generateContent(_ request: AIGenerationRequest) async throws -> AIGenerationResponse {
       let url = URL(string: "\(baseURL)/generate")!
       
       var urlRequest = URLRequest(url: url)
       urlRequest.httpMethod = "POST"
       urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
       urlRequest.httpBody = try JSONEncoder().encode(request)
       
       let (data, _) = try await URLSession.shared.data(for: urlRequest)
       return try JSONDecoder().decode(AIGenerationResponse.self, from: data)
   }
}

class AssetServiceClient {
   private let baseURL: String
   
   init(baseURL: String) {
       self.baseURL = baseURL
   }
   
   func fetchAsset(_ assetId: String) async throws -> AssetData {
       let url = URL(string: "\(baseURL)/assets/\(assetId)")!
       let (data, _) = try await URLSession.shared.data(from: url)
       return try JSONDecoder().decode(AssetData.self, from: data)
   }
   
   func uploadAsset(_ asset: AssetUpload) async throws -> AssetUploadResponse {
       // Implementation
       return AssetUploadResponse(assetId: "new-asset", url: "")
   }
}

class CommunityServiceClient {
   private let baseURL: String
   
   init(baseURL: String) {
       self.baseURL = baseURL
   }
   
   func joinCommunity(_ communityId: String, userId: String) async throws {
       // Implementation
   }
   
   func getUpcomingEvents() async throws -> [CommunityEvent] {
       // Implementation
       return []
   }
}

// MARK: - Request/Response Types
struct AIGenerationRequest: Codable {
   let prompt: String
   let type: AIContentType
   let parameters: [String: Any]?
   
   enum CodingKeys: String, CodingKey {
       case prompt, type, parameters
   }
   
   func encode(to encoder: Encoder) throws {
       var container = encoder.container(keyedBy: CodingKeys.self)
       try container.encode(prompt, forKey: .prompt)
       try container.encode(type, forKey: .type)
       
       if let params = parameters {
           let jsonData = try JSONSerialization.data(withJSONObject: params)
           try container.encode(jsonData, forKey: .parameters)
       }
   }
}

enum AIContentType: String, Codable {
   case text
   case dialogue
   case quest
   case music
   case ambience
}

struct AIGenerationResponse: Codable {
   let content: String
   let metadata: [String: String]?
}

struct AIStreamChunk: Codable {
   let text: String
   let isComplete: Bool
   let metadata: [String: String]?
}

struct AssetData: Codable {
   let id: String
   let type: String
   let url: String
   let metadata: [String: String]
}

struct AssetUpload {
   let name: String
   let type: String
   let data: Data
}

struct AssetUploadResponse: Codable {
   let assetId: String
   let url: String
}

struct CommunityEvent: Codable {
   let id: String
   let name: String
   let description: String
   let startTime: Date
   let participants: Int
}

struct TerrainGenerationParams: Codable {
   let seed: Int64
   let size: SIMD2<Int>
   let biome: BiomeType
   let features: Set<TerrainFeature>
}

enum TerrainFeature: String, Codable {
   case rivers
   case lakes
   case caves
   case mountains
   case valleys
   case forests
}

struct GeneratedTerrain: Codable {
   let heightMap: [[Float]]
   let biomeMap: [[String]]
   let features: [TerrainFeatureData]
}

struct TerrainFeatureData: Codable {
   let type: TerrainFeature
   let position: SIMD3<Float>
   let size: Float
}

// MARK: - Notification Extensions
extension Notification.Name {
   static let serviceStatusChanged = Notification.Name("FinalStorm.serviceStatusChanged")
   static let worldEngineConnected = Notification.Name("FinalStorm.worldEngineConnected")
   static let worldEngineDisconnected = Notification.Name("FinalStorm.worldEngineDisconnected")
}
