//
// File Path: Networking/FinalverseNetworkCore.swift
// Description: Advanced networking system for FinalStorm
// Handles real-time communication with Finalverse servers
//

import Foundation
import Network
import Combine
import CryptoKit

// MARK: - Finalverse Network Core
/// High-performance networking system optimized for virtual worlds
@MainActor
class FinalverseNetworkCore: ObservableObject {
   
   // MARK: - Network Components
   @Published var connectionStatus: ConnectionStatus = .disconnected
   @Published var networkLatency: TimeInterval = 0
   @Published var bandwidth: NetworkBandwidth = .unknown
   
   private var primaryConnection: FinalverseConnection?
   private var messagingSystem: RealtimeMessagingSystem
   private var stateSync: StateSynchronizationManager
   private var predictionEngine: ClientPredictionEngine
   private var compressionEngine: NetworkCompressionEngine
   private var encryptionManager: EncryptionManager
   
   // MARK: - Connection Management
   private var reconnectionTimer: Timer?
   private var heartbeatTimer: Timer?
   private let maxReconnectAttempts = 5
   private var reconnectAttempts = 0
   
   // MARK: - Message Queues
   private var outgoingQueue: PriorityMessageQueue
   private var incomingQueue: MessageProcessingQueue
   
   // MARK: - Performance Metrics
   private var metricsCollector: NetworkMetricsCollector
   
   init() {
       self.messagingSystem = RealtimeMessagingSystem()
       self.stateSync = StateSynchronizationManager()
       self.predictionEngine = ClientPredictionEngine()
       self.compressionEngine = NetworkCompressionEngine()
       self.encryptionManager = EncryptionManager()
       self.outgoingQueue = PriorityMessageQueue()
       self.incomingQueue = MessageProcessingQueue()
       self.metricsCollector = NetworkMetricsCollector()
       
       setupNetworkMonitoring()
   }
   
   // MARK: - Connection Methods
   func connect(to server: ServerEndpoint, credentials: AuthCredentials) async throws {
       connectionStatus = .connecting
       
       do {
           // Create secure connection
           let connection = try await establishConnection(to: server)
           
           // Authenticate
           let authToken = try await authenticate(connection: connection, credentials: credentials)
           
           // Initialize connection
           primaryConnection = FinalverseConnection(
               connection: connection,
               authToken: authToken,
               endpoint: server
           )
           
           // Start connection services
           startHeartbeat()
           startMessageProcessing()
           
           connectionStatus = .connected
           reconnectAttempts = 0
           
       } catch {
           connectionStatus = .disconnected
           throw NetworkError.connectionFailed(reason: error.localizedDescription)
       }
   }
   
   private func establishConnection(to server: ServerEndpoint) async throws -> NWConnection {
       let parameters = NWParameters.quic(alpn: ["finalverse"])
       
       // Configure TLS
       let tlsOptions = NWProtocolTLS.Options()
       sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv13)
       parameters.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
       
       // Create connection
       let connection = NWConnection(
           host: NWEndpoint.Host(server.host),
           port: NWEndpoint.Port(rawValue: server.port)!,
           using: parameters
       )
       
       return try await withCheckedThrowingContinuation { continuation in
           connection.stateUpdateHandler = { state in
               switch state {
               case .ready:
                   continuation.resume(returning: connection)
               case .failed(let error):
                   continuation.resume(throwing: error)
               default:
                   break
               }
           }
           
           connection.start(queue: .main)
       }
   }
   
   // MARK: - Message Handling
   func sendMessage<T: NetworkMessage>(_ message: T, priority: MessagePriority = .normal) {
       Task {
           do {
               // Serialize message
               let data = try messagingSystem.serialize(message)
               
               // Compress if beneficial
               let compressed = compressionEngine.compressIfBeneficial(data)
               
               // Encrypt
               let encrypted = try encryptionManager.encrypt(compressed)
               
               // Queue for sending
               outgoingQueue.enqueue(
                   NetworkPacket(
                       id: UUID(),
                       type: message.messageType,
                       data: encrypted,
                       priority: priority,
                       timestamp: Date()
                   ),
                   priority: priority
               )
               
           } catch {
               print("Failed to send message: \(error)")
           }
       }
   }
   
   private func startMessageProcessing() {
       Task {
           while connectionStatus == .connected {
               // Process outgoing messages
               if let packet = await outgoingQueue.dequeue() {
                   await sendPacket(packet)
               }
               
               // Small delay to prevent busy waiting
               try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
           }
       }
       
       // Start incoming message processing
       Task {
           await receiveMessages()
       }
   }
   
   private func sendPacket(_ packet: NetworkPacket) async {
       guard let connection = primaryConnection?.connection else { return }
       
       let frame = NetworkFrame(
           header: FrameHeader(
               version: 1,
               flags: [],
               sequenceNumber: getNextSequenceNumber(),
               timestamp: packet.timestamp
           ),
           payload: packet.data
       )
       
       let frameData = frame.serialize()
       
       connection.send(content: frameData, completion: .contentProcessed { error in
           if let error = error {
               print("Send error: \(error)")
               self.handleSendError(packet: packet, error: error)
           } else {
               self.metricsCollector.recordSentPacket(size: frameData.count)
           }
       })
   }
   
   private func receiveMessages() async {
       guard let connection = primaryConnection?.connection else { return }
       
       while connectionStatus == .connected {
           connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
               if let data = data, !data.isEmpty {
                   Task {
                       await self.processIncomingData(data)
                   }
               }
               
               if isComplete || error != nil {
                   self.handleConnectionClosed()
                   return
               }
               
               // Continue receiving
               Task {
                   await self.receiveMessages()
               }
           }
           
           // Wait for next receive
           await Task.yield()
       }
   }
   
   private func processIncomingData(_ data: Data) async {
       do {
           // Parse frame
           let frame = try NetworkFrame.deserialize(from: data)
           
           // Decrypt
           let decrypted = try encryptionManager.decrypt(frame.payload)
           
           // Decompress if needed
           let decompressed = compressionEngine.decompress(decrypted)
           
           // Process based on message type
           let messageType = try detectMessageType(from: decompressed)
           
           switch messageType {
           case .worldUpdate:
               let update = try messagingSystem.deserialize(WorldUpdate.self, from: decompressed)
               await stateSync.processWorldUpdate(update)
               
           case .entityUpdate:
               let update = try messagingSystem.deserialize(EntityUpdate.self, from: decompressed)
               await stateSync.processEntityUpdate(update)
               
           case .playerAction:
               let action = try messagingSystem.deserialize(PlayerAction.self, from: decompressed)
               await processPlayerAction(action)
               
           case .chat:
               let message = try messagingSystem.deserialize(ChatMessage.self, from: decompressed)
               await processChatMessage(message)
               
           default:
               print("Unknown message type: \(messageType)")
           }
           
           metricsCollector.recordReceivedPacket(size: data.count)
           
       } catch {
           print("Failed to process incoming data: \(error)")
       }
   }
   
   // MARK: - State Synchronization
   private func processPlayerAction(_ action: PlayerAction) async {
       // Apply prediction
       predictionEngine.applyPrediction(action)
       
       // Forward to state sync
       await stateSync.processPlayerAction(action)
   }
   
   private func processChatMessage(_ message: ChatMessage) async {
       // Emit chat event
       NotificationCenter.default.post(
           name: .chatMessageReceived,
           object: nil,
           userInfo: ["message": message]
       )
   }
   
   // MARK: - Heartbeat Management
   private func startHeartbeat() {
       heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
           self.sendHeartbeat()
       }
   }
   
   private func sendHeartbeat() {
       let heartbeat = Heartbeat(
           timestamp: Date(),
           clientTime: CACurrentMediaTime(),
           sequenceNumber: getNextSequenceNumber()
       )
       
       sendMessage(heartbeat, priority: .high)
   }
   
   // MARK: - Connection Management
   private func handleConnectionClosed() {
       connectionStatus = .disconnected
       heartbeatTimer?.invalidate()
       
       // Attempt reconnection
       if reconnectAttempts < maxReconnectAttempts {
           reconnectAttempts += 1
           scheduleReconnection()
       }
   }
   
   private func scheduleReconnection() {
       let delay = TimeInterval(min(pow(2, Double(reconnectAttempts)), 30))
       
       reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
           Task {
               if let endpoint = self.primaryConnection?.endpoint {
                   try? await self.reconnect(to: endpoint)
               }
           }
       }
   }
   
   private func reconnect(to endpoint: ServerEndpoint) async throws {
       // Use stored credentials for reconnection
       // Implementation depends on credential storage strategy
   }
   
   // MARK: - Network Monitoring
   private func setupNetworkMonitoring() {
       let monitor = NWPathMonitor()
       let queue = DispatchQueue(label: "NetworkMonitor")
       
       monitor.pathUpdateHandler = { [weak self] path in
           Task { @MainActor in
               self?.updateNetworkStatus(path)
           }
       }
       
       monitor.start(queue: queue)
   }
   
   private func updateNetworkStatus(_ path: NWPath) {
       if path.status == .satisfied {
           if path.usesInterfaceType(.wifi) {
               bandwidth = .high
           } else if path.usesInterfaceType(.cellular) {
               bandwidth = .medium
           } else {
               bandwidth = .low
           }
       } else {
           bandwidth = .none
       }
   }
   
   // MARK: - Helper Methods
   private var sequenceNumber: UInt64 = 0
   
   private func getNextSequenceNumber() -> UInt64 {
       sequenceNumber += 1
       return sequenceNumber
   }
   
   private func authenticate(connection: NWConnection, credentials: AuthCredentials) async throws -> AuthToken {
       // Implement authentication protocol
       // This is a placeholder
       return AuthToken(
           token: UUID().uuidString,
           expiresAt: Date().addingTimeInterval(3600)
       )
   }
   
   private func detectMessageType(from data: Data) throws -> MessageType {
       // Read message type from data header
       guard data.count >= 4 else {
           throw NetworkError.invalidMessage
       }
       
       let typeValue = data.withUnsafeBytes { $0.load(as: UInt32.self) }
       
       guard let type = MessageType(rawValue: typeValue) else {
           throw NetworkError.unknownMessageType
       }
       
       return type
   }
   
   private func handleSendError(packet: NetworkPacket, error: Error) {
       // Re-queue high priority messages
       if packet.priority == .critical || packet.priority == .high {
           outgoingQueue.enqueue(packet, priority: packet.priority)
       }
   }
}

// MARK: - Client Prediction Engine
/// Handles client-side prediction for smooth gameplay
class ClientPredictionEngine {
   private var predictedStates: [UUID: PredictedState] = [:]
   private var confirmedStates: [UUID: ConfirmedState] = [:]
   private var predictionBuffer: CircularBuffer<PredictionFrame>
   
   init() {
       self.predictionBuffer = CircularBuffer<PredictionFrame>(capacity: 120) // 2 seconds at 60fps
   }
   
   func applyPrediction(_ action: PlayerAction) {
       let prediction = PredictedState(
           entityId: action.playerId,
           position: action.newPosition,
           velocity: action.velocity,
           timestamp: action.timestamp,
           sequenceNumber: action.sequenceNumber
       )
       
       predictedStates[action.playerId] = prediction
       
       // Store in buffer for later reconciliation
       predictionBuffer.append(PredictionFrame(
           sequenceNumber: action.sequenceNumber,
           state: prediction,
           input: action
       ))
   }
   
   func reconcile(with serverState: ServerState) {
       guard let confirmedSequence = serverState.lastProcessedSequence else { return }
       
       // Find the prediction frame
       guard let frameIndex = predictionBuffer.firstIndex(where: {
           $0.sequenceNumber == confirmedSequence
       }) else { return }
       
       // Remove old predictions
       predictionBuffer.removeFirst(frameIndex + 1)
       
       // Update confirmed state
       confirmedStates[serverState.entityId] = ConfirmedState(
           position: serverState.position,
           velocity: serverState.velocity,
           timestamp: serverState.timestamp
       )
       
       // Re-apply remaining predictions
       for frame in predictionBuffer {
           reapplyPrediction(frame)
       }
   }
   
   private func reapplyPrediction(_ frame: PredictionFrame) {
       // Re-simulate from confirmed state
       guard let confirmed = confirmedStates[frame.state.entityId] else { return }
       
       var position = confirmed.position
       var velocity = confirmed.velocity
       
       // Apply physics simulation
       let deltaTime = frame.state.timestamp.timeIntervalSince(confirmed.timestamp)
       position += velocity * Float(deltaTime)
       
       // Update predicted state
       predictedStates[frame.state.entityId] = PredictedState(
           entityId: frame.state.entityId,
           position: position,
           velocity: velocity,
           timestamp: frame.state.timestamp,
           sequenceNumber: frame.sequenceNumber
       )
   }
}

// MARK: - Network Compression Engine
class NetworkCompressionEngine {
   private let compressionThreshold = 1024 // Only compress data larger than 1KB
   
   func compressIfBeneficial(_ data: Data) -> Data {
       guard data.count > compressionThreshold else { return data }
       
       if let compressed = data.compressed(using: .zlib),
          compressed.count < data.count * 0.9 { // Only use if 10% smaller
           return compressed
       }
       
       return data
   }
   
   func decompress(_ data: Data) -> Data {
       // Check if data is compressed (simple magic byte check)
       if data.first == 0x78 { // zlib magic byte
           return data.decompressed(using: .zlib) ?? data
       }
       return data
   }
}

// MARK: - Supporting Types
enum ConnectionStatus {
   case disconnected
   case connecting
   case connected
   case reconnecting
   case error(String)
}

enum NetworkBandwidth {
   case unknown
   case none
   case low
   case medium
   case high
}

struct ServerEndpoint {
   let host: String
   let port: UInt16
   let region: String
   let priority: Int
}

struct AuthCredentials {
   let username: String
   let password: String
   let twoFactorCode: String?
}

struct AuthToken {
   let token: String
   let expiresAt: Date
}

struct FinalverseConnection {
   let connection: NWConnection
   let authToken: AuthToken
   let endpoint: ServerEndpoint
}

protocol NetworkMessage: Codable {
   var messageType: MessageType { get }
   var timestamp: Date { get }
   var sequenceNumber: UInt64 { get }
}

enum MessageType: UInt32 {
   case heartbeat = 1
   case worldUpdate = 2
   case entityUpdate = 3
   case playerAction = 4
   case chat = 5
   case serverCommand = 6
   case clientCommand = 7
}

enum MessagePriority: Int, Comparable {
   case low = 0
   case normal = 1
   case high = 2
   case critical = 3
   
   static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
       lhs.rawValue < rhs.rawValue
   }
}

struct NetworkPacket {
   let id: UUID
   let type: MessageType
   let data: Data
   let priority: MessagePriority
   let timestamp: Date
}

struct NetworkFrame {
   let header: FrameHeader
   let payload: Data
   
   func serialize() -> Data {
       var data = Data()
       data.append(header.serialize())
       data.append(payload)
       return data
   }
   
   static func deserialize(from data: Data) throws -> NetworkFrame {
       guard data.count >= FrameHeader.size else {
           throw NetworkError.invalidFrame
       }
       
       let headerData = data.prefix(FrameHeader.size)
       let header = try FrameHeader.deserialize(from: headerData)
       let payload = data.suffix(from: FrameHeader.size)
       
       return NetworkFrame(header: header, payload: payload)
   }
}

struct FrameHeader {
   static let size = 16
   
   let version: UInt8
   let flags: Set<FrameFlag>
   let sequenceNumber: UInt64
   let timestamp: Date
   
   func serialize() -> Data {
       var data = Data()
       data.append(version)
       data.append(UInt8(flags.rawValue))
       data.append(contentsOf: withUnsafeBytes(of: sequenceNumber) { Array($0) })
       data.append(contentsOf: withUnsafeBytes(of: timestamp.timeIntervalSince1970) { Array($0) })
       return data
   }
   
   static func deserialize(from data: Data) throws -> FrameHeader {
       guard data.count >= size else {
           throw NetworkError.invalidFrameHeader
       }
       
       let version = data[0]
       let flags = FrameFlag(rawValue: data[1])
       let sequenceNumber = data.withUnsafeBytes { buffer in
           buffer.load(fromByteOffset: 2, as: UInt64.self)
       }
       let timestamp = data.withUnsafeBytes { buffer in
           let interval = buffer.load(fromByteOffset: 10, as: TimeInterval.self)
           return Date(timeIntervalSince1970: interval)
       }
       
       return FrameHeader(
           version: version,
           flags: flags,
           sequenceNumber: sequenceNumber,
           timestamp: timestamp
       )
   }
}

struct FrameFlag: OptionSet {
   let rawValue: UInt8
   
   static let compressed = FrameFlag(rawValue: 1 << 0)
   static let encrypted = FrameFlag(rawValue: 1 << 1)
   static let priority = FrameFlag(rawValue: 1 << 2)
}

enum NetworkError: Error {
   case connectionFailed(reason: String)
   case authenticationFailed
   case invalidMessage
   case unknownMessageType
   case invalidFrame
   case invalidFrameHeader
   case encryptionError
   case decompressionError
}

// MARK: - Network Messages
struct Heartbeat: NetworkMessage {
   let messageType = MessageType.heartbeat
   let timestamp: Date
   let clientTime: TimeInterval
   let sequenceNumber: UInt64
}

struct WorldUpdate: NetworkMessage {
   let messageType = MessageType.worldUpdate
   let timestamp: Date
   let sequenceNumber: UInt64
   let chunks: [ChunkUpdate]
   let entities: [EntityState]
}

struct EntityUpdate: NetworkMessage {
   let messageType = MessageType.entityUpdate
   let timestamp: Date
   let sequenceNumber: UInt64
   let entityId: UUID
   let position: SIMD3<Float>
   let rotation: simd_quatf
   let velocity: SIMD3<Float>
   let state: EntityState
}

struct PlayerAction: NetworkMessage {
   let messageType = MessageType.playerAction
   let timestamp: Date
   let sequenceNumber: UInt64
   let playerId: UUID
   let actionType: ActionType
   let newPosition: SIMD3<Float>
   let velocity: SIMD3<Float>
   let inputState: InputState
}

enum ActionType: String, Codable {
   case move
   case jump
   case interact
   case attack
   case use
}

struct ChatMessage: NetworkMessage {
   let messageType = MessageType.chat
   let timestamp: Date
   let sequenceNumber: UInt64
   let senderId: UUID
   let senderName: String
   let content: String
   let channel: ChatChannel
}

// MARK: - Utility Classes
class CircularBuffer<T> {
   private var buffer: [T?]
   private var head = 0
   private var count = 0
   private let capacity: Int
   
   init(capacity: Int) {
       self.capacity = capacity
       self.buffer = Array(repeating: nil, count: capacity)
   }
   
   func append(_ element: T) {
       buffer[(head + count) % capacity] = element
       
       if count < capacity {
           count += 1
       } else {
           head = (head + 1) % capacity
       }
   }
   
   func removeFirst(_ k: Int) {
       let removeCount = min(k, count)
       head = (head + removeCount) % capacity
       count -= removeCount
   }
   
   var first: T? {
       guard count > 0 else { return nil }
       return buffer[head]
   }
   
   func firstIndex(where predicate: (T) -> Bool) -> Int? {
       for i in 0..<count {
           let index = (head + i) % capacity
           if let element = buffer[index], predicate(element) {
               return i
           }
       }
       return nil
   }
   
   func makeIterator() -> AnyIterator<T> {
       var currentIndex = 0
       
       return AnyIterator {
           guard currentIndex < self.count else { return nil }
           
           let index = (self.head + currentIndex) % self.capacity
           currentIndex += 1
           
           return self.buffer[index]
       }
   }
}

extension CircularBuffer: Sequence {
   func forEach(_ body: (T) throws -> Void) rethrows {
       for element in self {
           try body(element)
       }
   }
}

// MARK: - Priority Message Queue
class PriorityMessageQueue {
   private var queues: [MessagePriority: [NetworkPacket]] = [:]
   private let lock = NSLock()
   
   init() {
       // Initialize queues for each priority
       for priority in [MessagePriority.low, .normal, .high, .critical] {
           queues[priority] = []
       }
   }
   
   func enqueue(_ packet: NetworkPacket, priority: MessagePriority) {
       lock.lock()
       defer { lock.unlock() }
       
       queues[priority]?.append(packet)
   }
   
   func dequeue() async -> NetworkPacket? {
       lock.lock()
       defer { lock.unlock() }
       
       // Check queues in priority order
       for priority in [MessagePriority.critical, .high, .normal, .low] {
           if let queue = queues[priority], !queue.isEmpty {
               return queues[priority]?.removeFirst()
           }
       }
       
       return nil
   }
   
   var isEmpty: Bool {
       lock.lock()
       defer { lock.unlock() }
       
       return queues.values.allSatisfy { $0.isEmpty }
   }
}

// MARK: - Message Processing Queue
class MessageProcessingQueue {
   private var queue: [NetworkPacket] = []
   private let semaphore = DispatchSemaphore(value: 0)
   private let lock = NSLock()
   
   func enqueue(_ packet: NetworkPacket) {
       lock.lock()
       queue.append(packet)
       lock.unlock()
       
       semaphore.signal()
   }
   
   func dequeue() -> NetworkPacket? {
       semaphore.wait()
       
       lock.lock()
       defer { lock.unlock() }
       
       return queue.isEmpty ? nil : queue.removeFirst()
   }
}

// MARK: - Network Metrics Collector
class NetworkMetricsCollector {
   private var sentBytes: Int = 0
   private var receivedBytes: Int = 0
   private var sentPackets: Int = 0
   private var receivedPackets: Int = 0
   private var latencySamples: [TimeInterval] = []
   private let maxSamples = 100
   
   func recordSentPacket(size: Int) {
       sentBytes += size
       sentPackets += 1
   }
   
   func recordReceivedPacket(size: Int) {
       receivedBytes += size
       receivedPackets += 1
   }
   
   func recordLatency(_ latency: TimeInterval) {
       latencySamples.append(latency)
       if latencySamples.count > maxSamples {
           latencySamples.removeFirst()
       }
   }
   
   var averageLatency: TimeInterval {
       guard !latencySamples.isEmpty else { return 0 }
       return latencySamples.reduce(0, +) / Double(latencySamples.count)
   }
   
   var bandwidth: NetworkBandwidth {
       let bytesPerSecond = Double(receivedBytes) / max(1, Date().timeIntervalSinceReferenceDate)
       
       if bytesPerSecond > 1_000_000 {
           return .high
       } else if bytesPerSecond > 100_000 {
           return .medium
       } else if bytesPerSecond > 0 {
           return .low
       } else {
           return .none
       }
   }
}

// MARK: - Realtime Messaging System
class RealtimeMessagingSystem {
   private let encoder = JSONEncoder()
   private let decoder = JSONDecoder()
   
   init() {
       encoder.dateEncodingStrategy = .millisecondsSince1970
       decoder.dateDecodingStrategy = .millisecondsSince1970
   }
   
   func serialize<T: Encodable>(_ message: T) throws -> Data {
       return try encoder.encode(message)
   }
   
   func deserialize<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
       return try decoder.decode(type, from: data)
   }
}

// MARK: - State Synchronization Manager
class StateSynchronizationManager {
   private var worldState: WorldState
   private var entityStates: [UUID: EntityState] = [:]
   private var pendingUpdates: [StateUpdate] = []
   private let updateInterval: TimeInterval = 1.0 / 60.0 // 60 FPS
   
   init() {
       self.worldState = WorldState()
       startUpdateLoop()
   }
   
   private func startUpdateLoop() {
       Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
           Task {
               await self.processPendingUpdates()
           }
       }
   }
   
   func processWorldUpdate(_ update: WorldUpdate) async {
       // Update chunks
       for chunkUpdate in update.chunks {
           await updateChunk(chunkUpdate)
       }
       
       // Update entities
       for entityState in update.entities {
           entityStates[entityState.id] = entityState
       }
   }
   
   func processEntityUpdate(_ update: EntityUpdate) async {
       entityStates[update.entityId] = update.state
       
       // Notify observers
       await MainActor.run {
           NotificationCenter.default.post(
               name: .entityUpdated,
               object: nil,
               userInfo: ["entityId": update.entityId, "state": update.state]
           )
       }
   }
   
   func processPlayerAction(_ action: PlayerAction) async {
       // Update local state immediately for responsiveness
       if let entityState = entityStates[action.playerId] {
           var updatedState = entityState
           updatedState.position = action.newPosition
           updatedState.velocity = action.velocity
           entityStates[action.playerId] = updatedState
       }
   }
   
   private func processPendingUpdates() async {
       let updates = pendingUpdates
       pendingUpdates.removeAll()
       
       for update in updates {
           switch update {
           case .world(let worldUpdate):
               await processWorldUpdate(worldUpdate)
           case .entity(let entityUpdate):
               await processEntityUpdate(entityUpdate)
           }
       }
   }
   
   private func updateChunk(_ update: ChunkUpdate) async {
       // Update chunk in world state
       worldState.updateChunk(update)
       
       // Notify world manager
       await MainActor.run {
           NotificationCenter.default.post(
               name: .chunkUpdated,
               object: nil,
               userInfo: ["chunk": update]
           )
       }
   }
}

// MARK: - Encryption Manager
class EncryptionManager {
   private var symmetricKey: SymmetricKey?
   private var publicKey: P256.KeyAgreement.PublicKey?
   private var privateKey: P256.KeyAgreement.PrivateKey?
   
   init() {
       setupKeys()
   }
   
   private func setupKeys() {
       // Generate key pair for key exchange
       privateKey = P256.KeyAgreement.PrivateKey()
       publicKey = privateKey?.publicKey
   }
   
   func performKeyExchange(with serverPublicKey: P256.KeyAgreement.PublicKey) throws {
       guard let privateKey = privateKey else {
           throw NetworkError.encryptionError
       }
       
       let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
       
       // Derive symmetric key
       let symmetricKeyData = sharedSecret.withUnsafeBytes { bytes in
           SHA256.hash(data: Data(bytes))
       }
       
       self.symmetricKey = SymmetricKey(data: symmetricKeyData)
   }
   
   func encrypt(_ data: Data) throws -> Data {
       guard let key = symmetricKey else {
           return data // No encryption if key not established
       }
       
       let sealedBox = try AES.GCM.seal(data, using: key)
       return sealedBox.combined ?? data
   }
   
   func decrypt(_ data: Data) throws -> Data {
       guard let key = symmetricKey else {
           return data // No decryption if key not established
       }
       
       let sealedBox = try AES.GCM.SealedBox(combined: data)
       return try AES.GCM.open(sealedBox, using: key)
   }
}

// MARK: - Supporting State Types
struct WorldState {
   var chunks: [ChunkCoordinate: ChunkData] = [:]
   var time: TimeInterval = 0
   var weather: WeatherState = .clear
   
   mutating func updateChunk(_ update: ChunkUpdate) {
       chunks[update.coordinate] = update.data
   }
}

struct EntityState: Codable {
   let id: UUID
   var position: SIMD3<Float>
   var rotation: simd_quatf
   var velocity: SIMD3<Float>
   var health: Float
   var energy: Float
   var state: String
}

struct ChunkUpdate: Codable {
   let coordinate: ChunkCoordinate
   let data: ChunkData
   let timestamp: Date
}

struct ChunkData: Codable {
   let voxels: Data // Compressed voxel data
   let entities: [UUID]
   let metadata: ChunkMetadata
}

struct ChunkMetadata: Codable {
   let biome: BiomeType
   let averageHeight: Float
   let hasStructures: Bool
}

enum StateUpdate {
   case world(WorldUpdate)
   case entity(EntityUpdate)
}

struct InputState: Codable {
   let movement: SIMD2<Float>
   let rotation: SIMD2<Float>
   let buttons: Set<InputButton>
}

enum InputButton: String, Codable {
   case jump
   case interact
   case attack
   case crouch
   case sprint
}

struct PredictedState {
   let entityId: UUID
   var position: SIMD3<Float>
   var velocity: SIMD3<Float>
   let timestamp: Date
   let sequenceNumber: UInt64
}

struct ConfirmedState {
   var position: SIMD3<Float>
   var velocity: SIMD3<Float>
   let timestamp: Date
}

struct PredictionFrame {
   let sequenceNumber: UInt64
   let state: PredictedState
   let input: PlayerAction
}

struct ServerState {
   let entityId: UUID
   let position: SIMD3<Float>
   let velocity: SIMD3<Float>
   let timestamp: Date
   let lastProcessedSequence: UInt64?
}

enum WeatherState: String, Codable {
   case clear
   case cloudy
   case rainy
   case stormy
   case snowy
   case foggy
}

// MARK: - Notification Names
extension Notification.Name {
   static let entityUpdated = Notification.Name("FinalStorm.entityUpdated")
   static let chunkUpdated = Notification.Name("FinalStorm.chunkUpdated")
   static let chatMessageReceived = Notification.Name("FinalStorm.chatMessageReceived")
}

// MARK: - Data Compression Extensions
extension Data {
   func compressed(using algorithm: NSData.CompressionAlgorithm) -> Data? {
       return (self as NSData).compressed(using: algorithm) as Data?
   }
   
   func decompressed(using algorithm: NSData.CompressionAlgorithm) -> Data? {
       return (self as NSData).decompressed(using: algorithm) as Data?
   }
}
