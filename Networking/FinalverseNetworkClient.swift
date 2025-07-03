//
//  FinalverseNetworkClient.swift
//  FinalStorm
//
//  Network client for Finalverse services
//

import Foundation

class FinalverseNetworkClient {
    enum Service: String {
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
    }
    
    private let service: Service
    private let baseURL: String
    private let session = URLSession.shared
    
    init(service: Service, baseURL: String = "http://localhost") {
        self.service = service
        self.baseURL = baseURL
    }
    
    func connect() async throws {
        // Test connection to service
        let url = URL(string: "\(baseURL):\(service.port)/health")!
        let (_, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.connectionFailed
        }
    }
    
    func request<T: Decodable>(_ endpoint: ServiceEndpoint) async throws -> T {
        let url = URL(string: "\(baseURL):\(service.port)\(endpoint.path)")!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.requestFailed
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct ServiceEndpoint {
    let path: String
    let method: String
    let body: Data?
    
    init(path: String, method: String = "GET", body: Data? = nil) {
        self.path = path
        self.method = method
        self.body = body
    }
}

enum NetworkError: Error {
    case connectionFailed
    case requestFailed
}
