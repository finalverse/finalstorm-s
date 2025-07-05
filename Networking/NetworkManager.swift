//
//  Networking/NetworkManager.swift
//  FinalStorm
//
//  Enhanced network manager with unified ServerInfo and improved error handling
//

import Foundation
import Combine

@MainActor
class NetworkManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var latency: TimeInterval = 0
    @Published var lastError: NetworkError?
    @Published var isConnecting = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    // Message handling
    private var messageHandlers: [NetworkMessage.MessageType: (NetworkMessage) -> Void] = [:]
    private var pendingMessages: [NetworkMessage] = []
    
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case error(String)
        
        var description: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .reconnecting: return "Reconnecting..."
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    enum NetworkError: Error, LocalizedError {
        case invalidURL
        case notConnected
        case connectionFailed
        case authenticationFailed
        case serverUnavailable
        case timeout
        case encodingFailed
        case decodingFailed
        case messageQueueFull
        case unknownError(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .notConnected: return "Not connected to server"
            case .connectionFailed: return "Failed to connect to server"
            case .authenticationFailed: return "Authentication failed"
            case .serverUnavailable: return "Server is unavailable"
            case .timeout: return "Connection timeout"
            case .encodingFailed: return "Failed to encode message"
            case .decodingFailed: return "Failed to decode message"
            case .messageQueueFull: return "Message queue is full"
            case .unknownError(let message): return message
            }
        }
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
        
        setupMessageHandlers()
    }
    
    // MARK: - Connection Management
    
    func connect(to server: ServerInfo) async throws {
        guard !isConnecting else { return }
        
        isConnecting = true
        connectionStatus = .connecting
        lastError = nil
        
        defer {
            isConnecting = false
        }
        
        do {
            // Build WebSocket URL
            let scheme = server.isSecure ? "wss" : "ws"
            let urlString = "\(scheme)://\(server.url.host ?? server.address):\(server.port)/ws"
            
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }
            
            // Create WebSocket connection
            webSocketTask = urlSession.webSocketTask(with: url)
            webSocketTask?.resume()
            
            // Start listening for messages
            startListening()
            
            // Start ping for latency monitoring
            startPingTimer()
            
            connectionStatus = .connected
            isConnected = true
            reconnectAttempts = 0
            
            // Send any pending messages
            await sendPendingMessages()
            
            print("Connected to server: \(server.name)")
            
        } catch {
            connectionStatus = .error(error.localizedDescription)
            lastError = error as? NetworkError ?? .unknownError(error.localizedDescription)
            isConnected = false
            throw error
        }
    }
    
    func disconnect() {
        stopTimers()
        
        webSocketTask?.cancel(with: .goingAway, reason: Data("Client disconnect".utf8))
        webSocketTask = nil
        
        isConnected = false
        connectionStatus = .disconnected
        reconnectAttempts = 0
        
        print("Disconnected from server")
    }
    
    private func attemptReconnect(to server: ServerInfo) {
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionStatus = .error("Max reconnection attempts reached")
            return
        }
        
        reconnectAttempts += 1
        connectionStatus = .reconnecting
        
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await self?.connect(to: server)
                } catch {
                    self?.attemptReconnect(to: server)
                }
            }
        }
        
        print("Attempting reconnect \(reconnectAttempts)/\(maxReconnectAttempts) in \(delay)s")
    }
    
    // MARK: - Message Handling
    
    private func startListening() {
        guard let webSocketTask = webSocketTask else { return }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                Task { @MainActor in
                    await self?.handleMessage(message)
                }
                // Continue listening
                self?.startListening()
                
            case .failure(let error):
                Task { @MainActor in
                    self?.handleConnectionError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            await handleTextMessage(text)
            
        case .data(let data):
            await handleBinaryMessage(data)
            
        @unknown default:
            print("Received unknown message type")
        }
    }
    
    private func handleTextMessage(_ text: String) async {
        do {
            let data = text.data(using: .utf8) ?? Data()
            let message = try JSONDecoder().decode(NetworkMessage.self, from: data)
            
            // Call registered handler
            if let handler = messageHandlers[message.type] {
                handler(message)
            } else {
                print("No handler for message type: \(message.type)")
            }
            
        } catch {
            print("Failed to decode text message: \(error)")
            lastError = .decodingFailed
        }
    }
    
    private func handleBinaryMessage(_ data: Data) async {
        do {
            let message = try JSONDecoder().decode(NetworkMessage.self, from: data)
            
            // Call registered handler
            if let handler = messageHandlers[message.type] {
                handler(message)
            } else {
                print("No handler for message type: \(message.type)")
            }
            
        } catch {
            print("Failed to decode binary message: \(error)")
            lastError = .decodingFailed
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        connectionStatus = .error(error.localizedDescription)
        lastError = .connectionFailed
        isConnected = false
        
        print("Connection error: \(error)")
    }
    
    // MARK: - Message Sending
    
    func send(_ message: NetworkMessage) async throws {
        guard isConnected, let webSocketTask = webSocketTask else {
            // Queue message for later if not connected
            if pendingMessages.count < 100 { // Limit queue size
                pendingMessages.append(message)
            } else {
                throw NetworkError.messageQueueFull
            }
            throw NetworkError.notConnected
        }
        
        do {
            let data = try JSONEncoder().encode(message)
            let wsMessage = URLSessionWebSocketTask.Message.data(data)
            try await webSocketTask.send(wsMessage)
            
        } catch {
            lastError = .encodingFailed
            throw NetworkError.encodingFailed
        }
    }
    
    func sendText(_ text: String) async throws {
        guard isConnected, let webSocketTask = webSocketTask else {
            throw NetworkError.notConnected
        }
        
        let message = URLSessionWebSocketTask.Message.string(text)
        try await webSocketTask.send(message)
    }
    
    private func sendPendingMessages() async {
        for message in pendingMessages {
            do {
                try await send(message)
            } catch {
                print("Failed to send pending message: \(error)")
                break // Stop on first failure
            }
        }
        pendingMessages.removeAll()
    }
    
    // MARK: - Message Handler Registration
    
    func registerHandler(for messageType: NetworkMessage.MessageType, handler: @escaping (NetworkMessage) -> Void) {
        messageHandlers[messageType] = handler
    }
    
    func unregisterHandler(for messageType: NetworkMessage.MessageType) {
        messageHandlers.removeValue(forKey: messageType)
    }
    
    private func setupMessageHandlers() {
        // Default handlers
        registerHandler(for: .worldUpdate) { message in
            print("Received world update")
        }
        
        registerHandler(for: .chat) { message in
            print("Received chat message")
        }
    }
    
    // MARK: - Ping System
    
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.ping()
            }
        }
    }
    
    private func ping() async {
        guard let webSocketTask = webSocketTask else { return }
        
        let start = Date()
        webSocketTask.sendPing { [weak self] error in
            Task { @MainActor in
                if error == nil {
                    self?.latency = Date().timeIntervalSince(start)
                } else {
                    self?.lastError = .connectionFailed
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func stopTimers() {
        pingTimer?.invalidate()
        pingTimer = nil
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    deinit {
        stopTimers()
        disconnect()
    }
}

// MARK: - Network Message Types

struct NetworkMessage: Codable {
    let type: MessageType
    let payload: Data
    let timestamp: Date
    let messageId: UUID
    
    enum MessageType: String, Codable, CaseIterable {
        case login = "login"
        case logout = "logout"
        case movement = "movement"
        case chat = "chat"
        case action = "action"
        case worldUpdate = "world_update"
        case playerUpdate = "player_update"
        case entityUpdate = "entity_update"
        case terrainRequest = "terrain_request"
        case harmonyUpdate = "harmony_update"
        case songweaving = "songweaving"
        case ping = "ping"
        case pong = "pong"
    }
    
    init(type: MessageType, payload: Data) {
        self.type = type
        self.payload = payload
        self.timestamp = Date()
        self.messageId = UUID()
    }
    
    init<T: Codable>(type: MessageType, data: T) throws {
        self.type = type
        self.payload = try JSONEncoder().encode(data)
        self.timestamp = Date()
        self.messageId = UUID()
    }
    
    func decode<T: Codable>(_ type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: payload)
    }
}

// MARK: - Specific Message Payloads

struct LoginPayload: Codable {
    let username: String
    let avatarId: UUID
    let clientVersion: String
}

struct MovementPayload: Codable {
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let velocity: SIMD3<Float>
    let timestamp: Date
}

struct ChatPayload: Codable {
    let message: String
    let channel: String
    let senderId: UUID
}

struct WorldUpdatePayload: Codable {
    let regionId: UUID
    let gridUpdates: [GridUpdate]
    let entityUpdates: [EntityUpdate]
}

struct GridUpdate: Codable {
    let coordinate: GridCoordinate
    let harmonyLevel: Float
    let entitiesChanged: [UUID]
}

struct EntityUpdate: Codable {
    let entityId: UUID
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let properties: [String: String]
}

// MARK: - SIMD Codable Support

extension SIMD3: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Scalar.self)
        let y = try container.decode(Scalar.self)
        let z = try container.decode(Scalar.self)
        self.init(x, y, z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

extension simd_quatf: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        let w = try container.decode(Float.self)
        self.init(ix: x, iy: y, iz: z, r: w)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(imag.x)
        try container.encode(imag.y)
        try container.encode(imag.z)
        try container.encode(real)
    }
}
