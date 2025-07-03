//
//  NetworkManager.swift
//  FinalStorm
//
//  Manages network connections to servers
//

import Foundation
import Combine

@MainActor
class NetworkManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var latency: TimeInterval = 0
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    func connect(to server: ServerInfo) async throws {
        connectionStatus = .connecting
        
        guard let url = URL(string: "ws://\(server.address):\(server.port)/ws") else {
            throw NetworkError.invalidURL
        }
        
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        connectionStatus = .connected
        isConnected = true
        
        // Start ping for latency
        startPing()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionStatus = .disconnected
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self?.handleMessage(message)
                }
                self?.receiveMessage()
                
            case .failure(let error):
                Task { @MainActor in
                    self?.connectionStatus = .error(error.localizedDescription)
                    self?.isConnected = false
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Parse and handle text message
            handleTextMessage(text)
            
        case .data(let data):
            // Parse and handle binary message
            handleBinaryMessage(data)
            
        @unknown default:
            break
        }
    }
    
    private func handleTextMessage(_ text: String) {
        // Implement message handling
    }
    
    private func handleBinaryMessage(_ data: Data) {
        // Implement binary message handling
    }
    
    private func startPing() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                await self.ping()
            }
        }
    }
    
    private func ping() async {
        let start = Date()
        webSocketTask?.sendPing { [weak self] error in
            if error == nil {
                Task { @MainActor in
                    self?.latency = Date().timeIntervalSince(start)
                }
            }
        }
    }
    
    func send(_ message: NetworkMessage) async throws {
        guard let webSocketTask = webSocketTask else {
            throw NetworkError.notConnected
        }
        
        let data = try JSONEncoder().encode(message)
        let message = URLSessionWebSocketTask.Message.data(data)
        
        try await webSocketTask.send(message)
    }
}

// MARK: - Supporting Types
struct ServerInfo {
    let name: String
    let address: String
    let port: Int
    
    static let finalverseLocal = ServerInfo(
        name: "Finalverse Local",
        address: "localhost",
        port: 3000
    )
    
    static let openSimLocal = ServerInfo(
        name: "OpenSim Local",
        address: "localhost",
        port: 9000
    )
}

struct NetworkMessage: Codable {
    let type: MessageType
    let payload: Data
    
    enum MessageType: String, Codable {
        case login
        case logout
        case movement
        case chat
        case action
        case worldUpdate
    }
}

enum NetworkError: Error {
    case invalidURL
    case notConnected
    case encodingFailed
    case decodingFailed
}
