//
//  Core/World/WorldSystem.swift
//  FinalStorm
//
//  Complete integrated world system bringing everything together
//

import Foundation
import RealityKit
import Combine

@MainActor
class WorldSystem: ObservableObject {
    
    // MARK: - Core Managers
    private let worldManager = WorldManager()
    private let worldOptimizer = WorldOptimizer()
    private let terrainGenerator = TerrainGenerator()
    
    // MARK: - Published State
    @Published var isInitialized = false
    @Published var currentWorld: String = ""
    @Published var playerPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    @Published var performanceMetrics: WorldOptimizer.PerformanceMetrics = WorldOptimizer.PerformanceMetrics()
    
    // MARK: - Update System
    private var updateTimer: Timer?
    
    // MARK: - Initialization
    
    func initialize(serverInfo: ServerInfo) async throws {
        print("Initializing World System...")
        
        // Load default world
        try await worldManager.loadWorld(named: "FinalverseWorld", server: serverInfo)
        
        // Start optimization loop
        startOptimizationLoop()
        
        // Mark as initialized
        isInitialized = true
        currentWorld = "FinalverseWorld"
        
        print("World System initialized successfully")
    }
    
    private func startOptimizationLoop() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateWorldSystems()
            }
        }
    }
    
    private func updateWorldSystems() async {
        // Update player position in world manager
        worldManager.updatePlayerPosition(playerPosition)
        
        // Run optimization
        await worldOptimizer.optimizeWorld(
            worldManager: worldManager,
            playerPosition: playerPosition
        )
        
        // Update published metrics
        performanceMetrics = worldOptimizer.currentMetrics
        
        // Preload grids if player is moving
        if let lastPosition = getLastPlayerPosition(),
           simd_length(playerPosition - lastPosition) > 10.0 {
            
            let movementDirection = playerPosition - lastPosition
            await worldManager.preloadGridsInDirection(movementDirection)
        }
        
        updateLastPlayerPosition(playerPosition)
    }
    
    // MARK: - Player Movement Tracking
    
    private var lastPlayerPosition: SIMD3<Float>?
    
    private func getLastPlayerPosition() -> SIMD3<Float>? {
        return lastPlayerPosition
    }
    
    private func updateLastPlayerPosition(_ position: SIMD3<Float>) {
        lastPlayerPosition = position
    }
    
    // MARK: - Public Interface
    
    func updatePlayerPosition(_ newPosition: SIMD3<Float>) {
        playerPosition = newPosition
    }
    
    func getTerrainHeight(at position: SIMD3<Float>) -> Float? {
        return worldManager.getTerrainHeight(at: position)
    }
    
    func getBiome(at position: SIMD3<Float>) -> BiomeType? {
        return worldManager.getBiomeAt(worldPosition: position)
    }
    
    func getWorldStats() -> WorldStats {
        let terrainStats = worldManager.getTerrainStats()
        
        return WorldStats(
            loadedGrids: terrainStats.loadedChunks,
            visibleEntities: performanceMetrics.visibleEntities,
            memoryUsage: performanceMetrics.memoryUsage,
            frameRate: performanceMetrics.frameRate,
            optimizationLevel: worldOptimizer.optimizationLevel
        )
    }
    
    func setQualityLevel(_ level: WorldOptimizer.OptimizationLevel) {
        worldOptimizer.applyQualityPreset(level)
    }
    
    func getRecommendedQuality() -> WorldOptimizer.OptimizationLevel {
        return worldOptimizer.getRecommendedSettings()
    }
    
    // MARK: - Cleanup
    
    deinit {
        updateTimer?.invalidate()
    }
}

struct WorldStats {
    let loadedGrids: Int
    let visibleEntities: Int
    let memoryUsage: Int
    let frameRate: Float
    let optimizationLevel: WorldOptimizer.OptimizationLevel
    
    var formattedMemoryUsage: String {
        let mb = Float(memoryUsage) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}
