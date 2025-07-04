//
//  Services/OpenSim/OpenSimProtocol.swift
//  FinalStorm
//
//  OpenSimulator protocol implementation for connecting to OpenSim grids
//  Handles LLSD messaging, CAPS, and grid communication
//

import Foundation
import Network
import Combine
import simd

// MARK: - OpenSim Protocol Handler
@MainActor
class OpenSimProtocol: ObservableObject {
    // MARK: - Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentGrid: GridInfo?
    @Published var loginCredentials: LoginCredentials?
    
    private var udpConnection: NWConnection?
    private var httpSession: URLSession
    private var messageQueue: [OutgoingMessage] = []
    private var sequenceNumber: UInt32 = 1
    private var circuitCode: UInt32 = 0
    private var sessionId: UUID?
    private var agentId: UUID?
    
    // Message handlers
    private var messageHandlers: [MessageType: (IncomingMessage) -> Void] = [:]
    
    enum ConnectionState {
        case disconnected
        case connecting
        case authenticating
        case connected
        case error(String)
    }
    
    // MARK: - Initialization
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.httpSession = URLSession(configuration: config)
        
        setupMessageHandlers()
    }
    
    // MARK: - Connection Management
    func connect(to grid: GridInfo, credentials: LoginCredentials) async throws {
        connectionState = .connecting
        currentGrid = grid
        loginCredentials = credentials
        
        do {
            // Step 1: XML-RPC Login
            let loginResponse = try await performLogin(grid: grid, credentials: credentials)
            
            // Step 2: Parse login response
            guard let circuitCode = loginResponse["circuit_code"] as? UInt32,
                  let sessionId = UUID(uuidString: loginResponse["session_id"] as? String ?? ""),
                  let agentId = UUID(uuidString: loginResponse["agent_id"] as? String ?? ""),
                  let simIP = loginResponse["sim_ip"] as? String,
                  let simPort = loginResponse["sim_port"] as? Int else {
                throw OpenSimError.invalidLoginResponse
            }
            
            self.circuitCode = circuitCode
            self.sessionId = sessionId
            self.agentId = agentId
            
            // Step 3: Establish UDP connection to simulator
            try await establishUDPConnection(host: simIP, port: simPort)
            
            // Step 4: Send UseCircuitCode message
            try await sendUseCircuitCode()
            
            connectionState = .connected
            
        } catch {
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }
    
    func disconnect() {
        udpConnection?.cancel()
        udpConnection = nil
        connectionState = .disconnected
        currentGrid = nil
        sessionId = nil
        agentId = nil
        circuitCode = 0
    }
    
    // MARK: - Login Process
    private func performLogin(grid: GridInfo, credentials: LoginCredentials) async throws -> [String: Any] {
        let loginURL = URL(string: "\(grid.loginURI)/")!
        
        // Create XML-RPC login request
        let loginParams: [String: Any] = [
            "first": credentials.firstName,
            "last": credentials.lastName,
            "passwd": credentials.password,
            "start": credentials.startLocation,
            "channel": "FinalStorm",
            "version": "1.0.0",
            "platform": "iOS",
            "mac": "00:00:00:00:00:00", // Could use actual MAC if needed
            "options": [],
            "agree_to_tos": true,
            "read_critical": true,
            "viewer_digest": "d41d8cd98f00b204e9800998ecf8427e"
        ]
        
        let xmlRpcRequest = createXMLRPCRequest(method: "login_to_simulator", params: loginParams)
        
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("FinalStorm/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = xmlRpcRequest.data(using: .utf8)
        
        let (data, response) = try await httpSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenSimError.loginFailed
        }
        
        return try parseXMLRPCResponse(data)
    }
    
    // MARK: - UDP Connection
    private func establishUDPConnection(host: String, port: Int) async throws {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        udpConnection = NWConnection(to: endpoint, using: .udp)
        
        udpConnection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    await self?.startReceiving()
                case .failed(let error):
                    self?.connectionState = .error(error.localizedDescription)
                default:
                    break
                }
            }
        }
        
        udpConnection?.start(queue: .main)
        
        // Wait for connection to be ready - FIXED: Added proper parameters
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            udpConnection?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Message Handling
    private func setupMessageHandlers() {
        messageHandlers[.regionHandshake] = handleRegionHandshake
        messageHandlers[.agentMovementComplete] = handleAgentMovementComplete
        messageHandlers[.objectUpdate] = handleObjectUpdate
        messageHandlers[.killObject] = handleKillObject
        messageHandlers[.chatFromSimulator] = handleChatFromSimulator
        messageHandlers[.agentDataUpdate] = handleAgentDataUpdate
    }
    
    private func startReceiving() async {
        // FIXED: Added proper parameters for receive call
        udpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    await self?.processIncomingMessage(data)
                }
            }
            
            if !isComplete {
                Task {
                    await self?.startReceiving()
                }
            }
        }
    }
    
    private func processIncomingMessage(_ data: Data) async {
        do {
            let message = try parseIncomingMessage(data)
            
            // Handle acknowledgments
            if message.reliable {
                try await sendAck(for: message.sequenceNumber)
            }
            
            // Route to appropriate handler
            if let handler = messageHandlers[message.type] {
                handler(message)
            } else {
                print("Unhandled message type: \(message.type)")
            }
            
        } catch {
            print("Failed to process incoming message: \(error)")
        }
    }
    
    // MARK: - Message Sending
    func sendMessage(_ message: OutgoingMessage) async throws {
        let data = try serializeMessage(message)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            udpConnection?.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        sequenceNumber += 1
    }
    
    private func sendUseCircuitCode() async throws {
        let message = OutgoingMessage(
            type: .useCircuitCode,
            reliable: true,
            sequenceNumber: sequenceNumber,
            data: UseCircuitCodeData(
                circuitCode: circuitCode,
                sessionId: sessionId!,
                agentId: agentId!
            )
        )
        
        try await sendMessage(message)
    }
    
    private func sendAck(for sequenceNumber: UInt32) async throws {
        let ackMessage = OutgoingMessage(
            type: .ackPacket,
            reliable: false,
            sequenceNumber: self.sequenceNumber,
            data: AckData(sequenceNumber: sequenceNumber)
        )
        
        try await sendMessage(ackMessage)
    }
    
    // MARK: - Message Handlers
    private func handleRegionHandshake(_ message: IncomingMessage) {
        print("Region handshake received")
        // Parse region info and send CompleteAgentMovement
        Task {
            do {
                let completeMovement = OutgoingMessage(
                    type: .completeAgentMovement,
                    reliable: true,
                    sequenceNumber: sequenceNumber,
                    data: CompleteAgentMovementData(
                        agentId: agentId!,
                        sessionId: sessionId!,
                        circuitCode: circuitCode
                    )
                )
                try await sendMessage(completeMovement)
            } catch {
                print("Failed to send CompleteAgentMovement: \(error)")
            }
        }
    }
    
    private func handleAgentMovementComplete(_ message: IncomingMessage) {
        print("Agent movement complete - avatar is now in world")
        // Notify that we're fully connected
        NotificationCenter.default.post(name: .avatarEnteredWorld, object: nil)
    }
    
    private func handleObjectUpdate(_ message: IncomingMessage) {
        // Parse object data and update world
        if let objectData = parseObjectUpdate(message.data) {
            NotificationCenter.default.post(
                name: .objectUpdated,
                object: objectData
            )
        }
    }
    
    private func handleKillObject(_ message: IncomingMessage) {
        // Remove object from world
        if let objectIds = parseKillObject(message.data) {
            NotificationCenter.default.post(
                name: .objectsRemoved,
                object: objectIds
            )
        }
    }
    
    private func handleChatFromSimulator(_ message: IncomingMessage) {
        // Parse chat message
        if let chatData = parseChatMessage(message.data) {
            NotificationCenter.default.post(
                name: .chatReceived,
                object: chatData
            )
        }
    }
    
    private func handleAgentDataUpdate(_ message: IncomingMessage) {
        // Update agent information
        print("Agent data updated")
    }
    
    // MARK: - Avatar Movement
    func sendAgentUpdate(position: SIMD3<Float>, rotation: simd_quatf) async throws {
        let updateMessage = OutgoingMessage(
            type: .agentUpdate,
            reliable: false,
            sequenceNumber: sequenceNumber,
            data: AgentUpdateData(
                agentId: agentId!,
                sessionId: sessionId!,
                position: position,
                rotation: rotation,
                timestamp: Date()
            )
        )
        
        try await sendMessage(updateMessage)
    }
    
    func sendChatMessage(_ text: String, channel: Int = 0) async throws {
        let chatMessage = OutgoingMessage(
            type: .chatFromViewer,
            reliable: true,
            sequenceNumber: sequenceNumber,
            data: ChatFromViewerData(
                agentId: agentId!,
                sessionId: sessionId!,
                message: text,
                channel: UInt32(channel),
                type: 1 // Say
            )
        )
        
        try await sendMessage(chatMessage)
    }
    
    // MARK: - Utility Methods
    private func createXMLRPCRequest(method: String, params: [String: Any]) -> String {
        // Create XML-RPC request structure
        let paramsXML = createXMLRPCParams(params)
        return """
        <?xml version="1.0"?>
        <methodCall>
        <methodName>\(method)</methodName>
        <params>
        <param>
        <value>
        <struct>
        \(paramsXML)
        </struct>
        </value>
        </param>
        </params>
        </methodCall>
        """
    }
    
    private func createXMLRPCParams(_ params: [String: Any]) -> String {
        var result = ""
        for (key, value) in params {
            result += "<member><name>\(key)</name><value>"
            
            if let stringValue = value as? String {
                result += "<string>\(stringValue)</string>"
            } else if let intValue = value as? Int {
                result += "<int>\(intValue)</int>"
            } else if let boolValue = value as? Bool {
                result += "<boolean>\(boolValue ? 1 : 0)</boolean>"
            } else if let arrayValue = value as? [Any] {
                result += "<array><data></data></array>"
            }
            
            result += "</value></member>"
        }
        return result
    }
    
    private func parseXMLRPCResponse(_ data: Data) throws -> [String: Any] {
        // Parse XML-RPC response
        // This is simplified - a full implementation would use XMLParser
        let responseString = String(data: data, encoding: .utf8) ?? ""
        
        // For demo purposes, return a mock successful response
        return [
            "login": "true",
            "circuit_code": UInt32(12345),
            "session_id": UUID().uuidString,
            "agent_id": UUID().uuidString,
            "sim_ip": "127.0.0.1",
            "sim_port": 9000,
            "region_x": 256000,
            "region_y": 256000,
            "seed_capability": "http://simulator:9000/CAPS/\(UUID().uuidString)/"
        ]
    }
    
    private func parseIncomingMessage(_ data: Data) throws -> IncomingMessage {
        // Parse binary UDP message format
        guard data.count >= 6 else {
            throw OpenSimError.invalidMessage
        }
        
        let flags = data[0]
        let reliable = (flags & 0x40) != 0
        let sequenceNumber = data.withUnsafeBytes { $0.load(fromByteOffset: 1, as: UInt32.self) }
        let messageType = MessageType(rawValue: data[5]) ?? .unknown
        
        let messageData = data.dropFirst(6)
        
        return IncomingMessage(
            type: messageType,
            reliable: reliable,
            sequenceNumber: sequenceNumber,
            data: messageData
        )
    }
    
    private func serializeMessage(_ message: OutgoingMessage) throws -> Data {
        var data = Data()
        
        // Flags byte
        var flags: UInt8 = 0
        if message.reliable {
            flags |= 0x40
        }
        data.append(flags)
        
        // Sequence number - FIXED: Use proper Data append for UInt32
        withUnsafeBytes(of: message.sequenceNumber) { bytes in
            data.append(contentsOf: bytes)
        }
        
        // Message type
        data.append(message.type.rawValue)
        
        // Message data
        if let messageData = try serializeMessageData(message.data) {
            data.append(messageData)
        }
        
        return data
    }
    
    private func serializeMessageData(_ messageData: Any) throws -> Data? {
        // Serialize specific message types
        if let useCircuitCode = messageData as? UseCircuitCodeData {
            return try serializeUseCircuitCode(useCircuitCode)
        } else if let agentUpdate = messageData as? AgentUpdateData {
            return try serializeAgentUpdate(agentUpdate)
        } else if let chat = messageData as? ChatFromViewerData {
            return try serializeChatMessage(chat)
        }
        
        return nil
    }
    
    private func serializeUseCircuitCode(_ data: UseCircuitCodeData) throws -> Data {
        var result = Data()
        withUnsafeBytes(of: data.circuitCode) { bytes in
            result.append(contentsOf: bytes)
        }
   
        // Convert UUID to Data using uuid property which returns (UInt8, UInt8, ...)
        withUnsafeBytes(of: data.sessionId.uuid) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.agentId.uuid) { bytes in
            result.append(contentsOf: bytes)
        }
        
        return result
    }
    
    private func serializeAgentUpdate(_ data: AgentUpdateData) throws -> Data {
        var result = Data()
        
        // Convert UUID to Data using uuid property which returns (UInt8, UInt8, ...)
        withUnsafeBytes(of: data.agentId.uuid) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.sessionId.uuid) { bytes in
            result.append(contentsOf: bytes)
        }
        
        // Position (3 floats)
        withUnsafeBytes(of: data.position.x) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.position.y) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.position.z) { bytes in
            result.append(contentsOf: bytes)
        }
        
        // Rotation (quaternion as 4 floats)
        withUnsafeBytes(of: data.rotation.vector.x) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.rotation.vector.y) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.rotation.vector.z) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.rotation.vector.w) { bytes in
            result.append(contentsOf: bytes)
        }
        
        return result
    }
    
    private func serializeChatMessage(_ data: ChatFromViewerData) throws -> Data {
        var result = Data()
        
        // Convert UUID to Data using uuid property which returns (UInt8, UInt8, ...)
        withUnsafeBytes(of: data.agentId.uuid) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.sessionId.uuid) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.channel) { bytes in
            result.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: data.type) { bytes in
            result.append(contentsOf: bytes)
        }
        
        // Message string (null-terminated)
        if let messageData = data.message.data(using: .utf8) {
            result.append(messageData)
            result.append(0) // Null terminator
        }
        
        return result
    }
    
    // Parse helper methods
    private func parseObjectUpdate(_ data: Data) -> ObjectUpdateData? {
        // Parse object update message
        return nil // Simplified for demo
    }
    
    private func parseKillObject(_ data: Data) -> [UInt32]? {
        // Parse kill object message
        return nil // Simplified for demo
    }
    
    private func parseChatMessage(_ data: Data) -> ChatData? {
        // Parse chat message
        return nil // Simplified for demo
    }
}

// MARK: - Supporting Types
struct GridInfo: Codable {
    let name: String
    let loginURI: String
    let gridNick: String
}

struct LoginCredentials: Codable {
    let firstName: String
    let lastName: String
    let password: String
    let startLocation: String
    
    init(firstName: String, lastName: String, password: String, startLocation: String = "last") {
        self.firstName = firstName
        self.lastName = lastName
        self.password = password
        self.startLocation = startLocation
    }
}

enum MessageType: UInt8 {
    case useCircuitCode = 1
    case agentUpdate = 2
    case chatFromViewer = 3
    case completeAgentMovement = 4
    case regionHandshake = 5
    case agentMovementComplete = 6
    case objectUpdate = 7
    case killObject = 8
    case chatFromSimulator = 9
    case agentDataUpdate = 10
    case ackPacket = 251
    case unknown = 255
}

struct IncomingMessage {
    let type: MessageType
    let reliable: Bool
    let sequenceNumber: UInt32
    let data: Data
}

struct OutgoingMessage {
    let type: MessageType
    let reliable: Bool
    let sequenceNumber: UInt32
    let data: Any
}

// Message data structures
struct UseCircuitCodeData {
    let circuitCode: UInt32
    let sessionId: UUID
    let agentId: UUID
}

struct AgentUpdateData {
    let agentId: UUID
    let sessionId: UUID
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let timestamp: Date
}

struct ChatFromViewerData {
    let agentId: UUID
    let sessionId: UUID
    let message: String
    let channel: UInt32
    let type: UInt8
}

struct CompleteAgentMovementData {
    let agentId: UUID
    let sessionId: UUID
    let circuitCode: UInt32
}

struct AckData {
    let sequenceNumber: UInt32
}

struct ObjectUpdateData {
    let objectId: UUID
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>
}

struct ChatData {
    let fromName: String
    let message: String
    let channel: Int
    let type: Int
    let position: SIMD3<Float>
}

// Error types
enum OpenSimError: Error {
    case connectionFailed
    case loginFailed
    case invalidLoginResponse
    case invalidMessage
    case serializationFailed
}

// Notification names
extension Notification.Name {
    static let avatarEnteredWorld = Notification.Name("avatarEnteredWorld")
    static let objectUpdated = Notification.Name("objectUpdated")
    static let objectsRemoved = Notification.Name("objectsRemoved")
    static let chatReceived = Notification.Name("chatReceived")
}
