//
// File Path: Networking/NetworkManager.swift
// Description: Core networking system for FinalStorm
// Handles all network communication with OpenSim/MutSea servers
//

import Foundation
import Combine
import Network

@MainActor
class NetworkManager: ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentLatency: TimeInterval = 0
    @Published var networkQuality: NetworkQuality = .good
    @Published var connectedRegion: String = ""
    @Published var connectedGrid: String = ""
    
    // MARK: - Private Properties
    private var tcpConnection: NWConnection?
    private var udpConnection: NWConnection?
    private let networkQueue = DispatchQueue(label: "com.finalstorm.network")
    
    private var messageHandler: MessageHandler
    private var packetHandler: PacketHandler
    private var loginService: LoginService
    private var assetService: AssetService
    
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Connection State
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case authenticating
        case authenticated
        case error(Error)
    }
    
    enum NetworkQuality {
        case excellent  // < 50ms
        case good      // 50-100ms
        case fair      // 100-200ms
        case poor      // > 200ms
    }
    
    // MARK: - Initialization
    init() {
        self.messageHandler = MessageHandler()
        self.packetHandler = PacketHandler()
        self.loginService = LoginService()
        self.assetService = AssetService()
        
        setupMessageHandlers()
    }
    
    // MARK: - Setup
    func initialize() async {
        // Initialize services
        await loginService.initialize()
        await assetService.initialize()
        
        // Setup network monitoring
        setupNetworkMonitoring()
    }
    
    private func setupMessageHandlers() {
        // Handle incoming messages
        messageHandler.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleIncomingMessage(message)
            }
        }
        
        // Handle packet data
        packetHandler.onPacket = { [weak self] packet in
            Task { @MainActor in
                self?.handleIncomingPacket(packet)
            }
        }
    }
    
    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkPathUpdate(path)
            }
        }
        
        let queue = DispatchQueue(label: "com.finalstorm.networkmonitor")
        monitor.start(queue: queue)
    }
    
    // MARK: - Connection Management
    func connectToServer(host: String, port: Int) async throws {
        connectionState = .connecting
        
        // Create TCP connection for reliable data
        let tcpParams = NWParameters.tcp
        tcpParams.prohibitedInterfaceTypes = [.cellular] // WiFi only for now
        
        let tcpEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        tcpConnection = NWConnection(to: tcpEndpoint, using: tcpParams)
        
        // Create UDP connection for real-time data
        let udpParams = NWParameters.udp
        let udpPort = port + 1 // Convention: UDP port is TCP port + 1
        
        let udpEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(udpPort))
        )
        
        udpConnection = NWConnection(to: udpEndpoint, using: udpParams)
        
        // Setup connection handlers
        setupConnectionHandlers()
        
        // Start connections
        tcpConnection?.start(queue: networkQueue)
        udpConnection?.start(queue: networkQueue)
        
        // Wait for connection
        try await waitForConnection()
    }
    
    func connectToDefaultServer() async {
        do {
            // Get default server from preferences
            let host = UserDefaults.standard.string(forKey: "defaultServerHost") ?? "localhost"
            let port = UserDefaults.standard.integer(forKey: "defaultServerPort")
            
            if port == 0 {
                // Default OpenSim port
                try await connectToServer(host: host, port: 9000)
            } else {
                try await connectToServer(host: host, port: port)
            }
        } catch {
            connectionState = .error(error)
        }
    }
    
    private func setupConnectionHandlers() {
        // TCP Connection handlers
        tcpConnection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionStateChange(state, isUDP: false)
            }
        }
        
        tcpConnection?.betterPathUpdateHandler = { [weak self] betterPath in
            if betterPath {
                print("Better network path available")
            }
        }
        
        // UDP Connection handlers
        udpConnection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionStateChange(state, isUDP: true)
            }
        }
        
        // Start receiving data
        receiveData()
    }
    
    private func handleConnectionStateChange(_ state: NWConnection.State, isUDP: Bool) {
        switch state {
        case .ready:
            if !isUDP { // Only update state for TCP
                connectionState = .connected
                startPingTimer()
            }
            
        case .failed(let error):
            if !isUDP {
                connectionState = .error(error)
                attemptReconnect()
            }
            
        case .cancelled:
            if !isUDP {
                connectionState = .disconnected
            }
            
        default:
            break
        }
    }
    
    private func waitForConnection() async throws {
        let timeout: TimeInterval = 10.0
        let startTime = Date()
        
        while connectionState == .connecting {
            if Date().timeIntervalSince(startTime) > timeout {
                throw NetworkError.connectionTimeout
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        if case .error(let error) = connectionState {
            throw error
        }
    }
    
    // MARK: - Authentication
    func authenticate(username: String, password: String) async throws {
        guard connectionState == .connected else {
            throw NetworkError.notConnected
        }
        
        connectionState = .authenticating
        
        do {
            // Perform login through LoginService
            let loginResponse = try await loginService.login(
                username: username,
                password: password,
                connection: tcpConnection
            )
            
            // Store session info
            connectedRegion = loginResponse.regionName
            connectedGrid = loginResponse.gridName
            
            // Update state
            connectionState = .authenticated
            
            // Request initial data
            await requestInitialData()
            
        } catch {
            connectionState = .error(error)
            throw error
        }
    }
    
    // MARK: - Data Transmission
    func send(message: NetworkMessage) async throws {
        guard let connection = tcpConnection else {
            throw NetworkError.notConnected
        }
        
        let data = try messageHandler.encode(message)
        
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
    
    func sendUnreliable(packet: NetworkPacket) async throws {
        guard let connection = udpConnection else {
            throw NetworkError.notConnected
        }
        
        let data = try packetHandler.encode(packet)
        
        connection.send(content: data, completion: .contentProcessed { _ in
            // UDP is fire-and-forget
        })
    }
    
    private func receiveData() {
        // Receive TCP data
        tcpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data = data, !data.isEmpty {
                self?.messageHandler.processData(data)
            }
            
            if error == nil {
                self?.receiveData() // Continue receiving
            }
        }
        
        // Receive UDP data
        udpConnection?.receiveMessage { [weak self] data, _, _, error in
            if let data = data, !data.isEmpty {
                self?.packetHandler.processData(data)
            }
            
            if error == nil {
                self?.receiveUDPData() // Continue receiving
            }
        }
    }
    
    private func receiveUDPData() {
        udpConnection?.receiveMessage { [weak self] data, _, _, error in
            if let data = data, !data.isEmpty {
                self?.packetHandler.processData(data)
            }
            
            if error == nil {
                self?.receiveUDPData() // Continue receiving
            }
        }
    }
    
    // MARK: - Message Handling
    private func handleIncomingMessage(_ message: NetworkMessage) {
        switch message.type {
        case .worldData:
            handleWorldData(message)
            
        case .entityUpdate:
            handleEntityUpdate(message)
            
        case .chatMessage:
            handleChatMessage(message)
            
        case .assetData:
            handleAssetData(message)
            
        case .inventoryUpdate:
            handleInventoryUpdate(message)
            
        case .systemMessage:
            handleSystemMessage(message)
            
        default:
            print("Unhandled message type: \(message.type)")
        }
    }
    
    private func handleIncomingPacket(_ packet: NetworkPacket) {
        switch packet.type {
        case .movement:
            handleMovementPacket(packet)
            
        case .animation:
            handleAnimationPacket(packet)
            
        case .audio:
            handleAudioPacket(packet)
            
        default:
            break
        }
    }
    
    // MARK: - World Data
    func fetchWorldData(worldName: String) async throws -> WorldData {
        let request = NetworkMessage(
            type: .worldDataRequest,
            payload: ["worldName": worldName]
        )
        
        try await send(message: request)
        
        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            messageHandler.onWorldData = { worldData in
                continuation.resume(returning: worldData)
            }
        }
    }
    
    private func handleWorldData(_ message: NetworkMessage) {
        // Parse world data
        if let worldData = try? JSONDecoder().decode(WorldData.self, from: message.data) {
            messageHandler.onWorldData?(worldData)
        }
    }
    
    // MARK: - Entity Updates
    private func handleEntityUpdate(_ message: NetworkMessage) {
        // Notify entity system
        NotificationCenter.default.post(
            name: .entityUpdate,
            object: nil,
            userInfo: ["message": message]
        )
    }
    
    private func handleMovementPacket(_ packet: NetworkPacket) {
        // Fast path for movement updates
        NotificationCenter.default.post(
            name: .entityMovement,
            object: nil,
            userInfo: ["packet": packet]
        )
    }
    
    // MARK: - Chat
    private func handleChatMessage(_ message: NetworkMessage) {
        NotificationCenter.default.post(
            name: .chatMessageReceived,
            object: nil,
            userInfo: ["message": message]
        )
    }
    
    // MARK: - Assets
    private func handleAssetData(_ message: NetworkMessage) {
        Task {
            await assetService.handleAssetData(message)
        }
    }
    
    // MARK: - Inventory
    private func handleInventoryUpdate(_ message: NetworkMessage) {
        NotificationCenter.default.post(
            name: .inventoryUpdate,
            object: nil,
            userInfo: ["message": message]
        )
    }
    
    // MARK: - System Messages
    private func handleSystemMessage(_ message: NetworkMessage) {
        // Handle server notifications, alerts, etc.
        print("System message: \(message)")
    }
    
    // MARK: - Network Quality
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task {
                await self?.measureLatency()
            }
        }
    }
    
    private func measureLatency() async {
        let startTime = Date()
        
        let pingMessage = NetworkMessage(type: .ping, payload: [:])
        
        do {
            try await send(message: pingMessage)
            
            // Wait for pong
            await withCheckedContinuation { continuation in
                messageHandler.onPong = {
                    continuation.resume()
                }
            }
            
            currentLatency = Date().timeIntervalSince(startTime)
            updateNetworkQuality()
            
        } catch {
            print("Ping failed: \(error)")
        }
    }
    
    private func updateNetworkQuality() {
        if currentLatency < 0.05 {
            networkQuality = .excellent
        } else if currentLatency < 0.1 {
            networkQuality = .good
        } else if currentLatency < 0.2 {
            networkQuality = .fair
        } else {
            networkQuality = .poor
        }
    }
    
    // MARK: - Reconnection
    private func attemptReconnect() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.connectToDefaultServer()
            }
        }
    }
    
    // MARK: - Cleanup
    func disconnect() {
        pingTimer?.invalidate()
        reconnectTimer?.invalidate()
        
        tcpConnection?.cancel()
        udpConnection?.cancel()
        
        connectionState = .disconnected
    }
    
    private func handleNetworkPathUpdate(_ path: NWPath) {
        // Handle network changes (WiFi/Cellular/None)
        print("Network path update: \(path.status)")
    }
    
    private func requestInitialData() async {
        // Request initial world state, inventory, etc.
        let requests = [
            NetworkMessage(type: .inventoryRequest, payload: [:]),
            NetworkMessage(type: .friendsListRequest, payload: [:]),
            NetworkMessage(type: .groupsRequest, payload: [:])
        ]
        
        for request in requests {
            try? await send(message: request)
        }
    }
}

// MARK: - Network Message Types
enum NetworkMessageType: String, Codable {
    case ping
    case pong
    case worldDataRequest
    case worldData
    case entityUpdate
    case chatMessage
    case assetData
    case inventoryUpdate
    case inventoryRequest
    case friendsListRequest
    case groupsRequest
    case systemMessage
}

struct NetworkMessage: Codable {
    let id: UUID
    let type: NetworkMessageType
    let timestamp: Date
    let payload: [String: Any]
    let data: Data
    
    init(type: NetworkMessageType, payload: [String: Any]) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.payload = payload
        self.data = Data()
    }
}

enum NetworkPacketType: UInt8 {
    case movement = 1
    case animation = 2
    case audio = 3
    case input = 4
}

struct NetworkPacket {
    let type: NetworkPacketType
    let sequenceNumber: UInt32
    let timestamp: UInt64
    let data: Data
}

// MARK: - Network Errors
enum NetworkError: LocalizedError {
    case notConnected
    case connectionTimeout
    case authenticationFailed
    case invalidResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .connectionTimeout:
            return "Connection timeout"
        case .authenticationFailed:
            return "Authentication failed"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let entityUpdate = Notification.Name("entityUpdate")
    static let entityMovement = Notification.Name("entityMovement")
    static let chatMessageReceived = Notification.Name("chatMessageReceived")
    static let inventoryUpdate = Notification.Name("inventoryUpdate")
}
