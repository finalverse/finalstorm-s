//
//  SilenceService.swift
//  FinalStorm
//
//  Manages corruption and silence mechanics
//

import Foundation
import simd  // Add this import for simd_distance

@MainActor
class SilenceService: ObservableObject {
    @Published var silenceLevel: Float = 0.0
    @Published var corruptedAreas: [CorruptedArea] = []
    
    private let networkClient: FinalverseNetworkClient
    
    init() {
        self.networkClient = FinalverseNetworkClient(service: .silenceService)
    }
    
    func initialize() async {
        do {
            try await networkClient.connect()
        } catch {
            print("Failed to initialize Silence Service: \(error)")
        }
    }
    
    func checkCorruption(at location: SIMD3<Float>) -> Float {
        // Check corruption level at location
        for area in corruptedAreas {
            let distance = simd_distance(location, area.center)
            if distance < area.radius {
                return area.corruptionLevel * (1.0 - distance / area.radius)
            }
        }
        return 0.0
    }
    
    func applySilence(at location: SIMD3<Float>, strength: Float) {
        // Create or expand corrupted area
        let area = CorruptedArea(
            center: location,
            radius: strength * 10,
            corruptionLevel: strength
        )
        corruptedAreas.append(area)
        
        // Update global silence level
        silenceLevel = min(1.0, silenceLevel + strength * 0.1)
    }
}

struct CorruptedArea {
    let id = UUID()
    let center: SIMD3<Float>
    let radius: Float
    let corruptionLevel: Float
}
