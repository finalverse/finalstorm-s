//
//  HarmonyService.swift
//  FinalStorm
//
//  Manages harmony calculations and world balance
//

import Foundation
import Combine

@MainActor
class HarmonyService: ObservableObject {
    @Published var globalHarmony: Float = 1.0
    @Published var regionalHarmonies: [UUID: Float] = [:]
    
    private let networkClient: FinalverseClient
    
    init() {
        self.networkClient = FinalverseClient(service: .harmonyService)
    }
    
    func initialize() async {
        // Connect to harmony service
        do {
            try await networkClient.connect()
        } catch {
            print("Failed to initialize Harmony Service: \(error)")
        }
    }
    
    func calculateHarmony(for region: RegionInfo) -> Float {
        return regionalHarmonies[region.id] ?? 1.0
    }
    
    func applyHarmonyBoost(_ amount: Float, at location: SIMD3<Float>) {
        // Apply localized harmony boost
        globalHarmony = min(2.0, globalHarmony + amount * 0.1)
    }
}
