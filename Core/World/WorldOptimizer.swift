//
//  Core/World/WorldOptimizer.swift
//  FinalStorm
//
//  Performance optimization system for world management
//

import Foundation
import RealityKit
import simd

@MainActor
class WorldOptimizer: ObservableObject {
    
    // MARK: - Performance Metrics
    struct PerformanceMetrics {
        var frameRate: Float = 60.0
        var memoryUsage: Int = 0
        var entityCount: Int = 0
        var visibleEntities: Int = 0
        var loadedGrids: Int = 0
        var renderingTime: TimeInterval = 0.0
        var lastUpdate: Date = Date()
        
        var isPerformanceGood: Bool {
            return frameRate > 30.0 && memoryUsage < 1024 * 1024 * 512 // 512MB limit
        }
    }
    
    @Published var currentMetrics = PerformanceMetrics()
    @Published var optimizationLevel: OptimizationLevel = .balanced
    
    enum OptimizationLevel: String, CaseIterable {
        case performance = "Performance"
        case balanced = "Balanced"
        case quality = "Quality"
        case ultra = "Ultra"
        
        var lodDistanceMultiplier: Float {
            switch self {
            case .performance: return 0.5
            case .balanced: return 1.0
            case .quality: return 1.5
            case .ultra: return 2.0
            }
        }
        
        var maxVisibleEntities: Int {
            switch self {
            case .performance: return 500
            case .balanced: return 1000
            case .quality: return 2000
            case .ultra: return 4000
            }
        }
        
        var terrainResolution: Int {
            switch self {
            case .performance: return 64
            case .balanced: return 128
            case .quality: return 256
            case .ultra: return 512
            }
        }
    }
    
    // MARK: - Optimization Methods
    
    func optimizeWorld(
        worldManager: WorldManager,
        playerPosition: SIMD3<Float>
    ) async {
        
        updateMetrics(worldManager: worldManager)
        
        // Adjust optimization level based on performance
        if !currentMetrics.isPerformanceGood {
            await reduceQuality(worldManager: worldManager)
        } else if currentMetrics.frameRate > 50.0 && currentMetrics.memoryUsage < 256 * 1024 * 1024 {
            await increaseQuality(worldManager: worldManager)
        }
        
        // Perform specific optimizations
        await optimizeLOD(worldManager: worldManager, playerPosition: playerPosition)
        await optimizeEntityVisibility(worldManager: worldManager, playerPosition: playerPosition)
        await optimizeMemoryUsage(worldManager: worldManager)
    }
    
    private func updateMetrics(worldManager: WorldManager) {
        currentMetrics.entityCount = worldManager.visibleEntities.count
        currentMetrics.loadedGrids = worldManager.loadedGrids.count
        currentMetrics.lastUpdate = Date()
        
        // Calculate memory usage (simplified)
        currentMetrics.memoryUsage = currentMetrics.loadedGrids * 1024 * 1024 // ~1MB per grid estimate
        
        // Update visible entities count
        currentMetrics.visibleEntities = min(currentMetrics.entityCount, optimizationLevel.maxVisibleEntities)
    }
    
    private func reduceQuality(worldManager: WorldManager) async {
        switch optimizationLevel {
        case .ultra:
            optimizationLevel = .quality
        case .quality:
            optimizationLevel = .balanced
        case .balanced:
            optimizationLevel = .performance
        case .performance:
            break // Already at minimum
        }
        
        print("Reduced quality to: \(optimizationLevel.rawValue)")
    }
    
    private func increaseQuality(worldManager: WorldManager) async {
        switch optimizationLevel {
        case .performance:
            optimizationLevel = .balanced
        case .balanced:
            optimizationLevel = .quality
        case .quality:
            optimizationLevel = .ultra
        case .ultra:
            break // Already at maximum
        }
        
        print("Increased quality to: \(optimizationLevel.rawValue)")
    }
    
    private func optimizeLOD(
        worldManager: WorldManager,
        playerPosition: SIMD3<Float>
    ) async {
        
        let lodDistances = [
            100.0 * optimizationLevel.lodDistanceMultiplier,
            200.0 * optimizationLevel.lodDistanceMultiplier,
            500.0 * optimizationLevel.lodDistanceMultiplier,
            1000.0 * optimizationLevel.lodDistanceMultiplier
        ]
        
        for (coordinate, grid) in worldManager.loadedGrids {
            let gridCenter = coordinate.toWorldPosition()
            let distance = simd_length(playerPosition - gridCenter)
            
            // Determine appropriate LOD level
            var lodLevel = 3 // Furthest LOD
            for (index, maxDistance) in lodDistances.enumerated() {
                if distance <= maxDistance {
                    lodLevel = index
                    break
                }
            }
            
            // Update terrain LOD if needed
            if let currentTerrain = grid.terrain,
               currentTerrain.lodLevel != lodLevel {
                
                Task {
                    await worldManager.updateGridLOD(coordinate: coordinate, lodLevel: lodLevel)
                }
            }
        }
    }
    
    private func optimizeEntityVisibility(
        worldManager: WorldManager,
        playerPosition: SIMD3<Float>
    ) async {
        
        // Create priority list of entities based on distance and importance
        var entityPriorities: [(Entity, Float)] = []
        
        for entity in worldManager.visibleEntities {
            let distance = simd_length(entity.position - playerPosition)
            let importance = calculateEntityImportance(entity)
            let priority = importance / (distance + 1.0) // Closer and more important = higher priority
            
            entityPriorities.append((entity, priority))
        }
        
        // Sort by priority and limit visible entities
        entityPriorities.sort { $0.1 > $1.1 }
        let maxVisible = optimizationLevel.maxVisibleEntities
        
        for (index, (entity, _)) in entityPriorities.enumerated() {
            entity.isEnabled = index < maxVisible
        }
        
        currentMetrics.visibleEntities = min(entityPriorities.count, maxVisible)
    }
    
    private func calculateEntityImportance(_ entity: Entity) -> Float {
        var importance: Float = 1.0
        
        // Interactive entities are more important
        if entity.components.has(InteractionComponent.self) {
            importance += 2.0
        }
        
        // Harmony-related entities are important
        if entity.components.has(HarmonyComponent.self) {
            importance += 1.5
        }
        
        // Large entities are more visible
        let scale = entity.scale
        let avgScale = (scale.x + scale.y + scale.z) / 3.0
        importance += avgScale * 0.5
        
        return importance
    }
    
    private func optimizeMemoryUsage(worldManager: WorldManager) async {
        let memoryLimit = 256 * 1024 * 1024 // 256MB limit
        
        if currentMetrics.memoryUsage > memoryLimit {
            // Unload distant grids
            let playerGrid = GridCoordinate(
                x: Int(worldManager.playerPosition.x / 100.0),
                z: Int(worldManager.playerPosition.z / 100.0)
            )
            
            var gridsToUnload: [GridCoordinate] = []
            
            for coordinate in worldManager.loadedGrids.keys {
                let distance = coordinate.distance(to: playerGrid)
                
                // Unload grids beyond optimization distance
                let maxDistance = 5.0 * optimizationLevel.lodDistanceMultiplier
                if distance > maxDistance {
                    gridsToUnload.append(coordinate)
                }
            }
            
            // Unload grids
            for coordinate in gridsToUnload {
                await worldManager.unloadGrid(coordinate)
            }
            
            print("Unloaded \(gridsToUnload.count) grids for memory optimization")
        }
    }
    
    // MARK: - Quality Presets
    
    func applyQualityPreset(_ preset: OptimizationLevel) {
        optimizationLevel = preset
        print("Applied quality preset: \(preset.rawValue)")
    }
    
    func getRecommendedSettings() -> OptimizationLevel {
        // Recommend settings based on current performance
        if currentMetrics.frameRate < 20 {
            return .performance
        } else if currentMetrics.frameRate < 40 {
            return .balanced
        } else if currentMetrics.frameRate > 50 && currentMetrics.memoryUsage < 128 * 1024 * 1024 {
            return .ultra
        } else {
            return .quality
        }
    }
}

// MARK: - WorldManager Extensions for Optimization

extension WorldManager {
    
    func updateGridLOD(coordinate: GridCoordinate, lodLevel: Int) async {
        guard var grid = loadedGrids[coordinate] else { return }
        
        do {
            // Regenerate terrain with new LOD
            let newTerrain = try await terrainGenerator.generateTerrain(
                for: coordinate,
                worldMetabolism: worldMetabolism,
                playerPosition: playerPosition,
                lodLevel: lodLevel
            )
            
            grid.terrain = newTerrain
            loadedGrids[coordinate] = grid
            
            // Update scene
            await sceneManager.updateGrid(grid)
            
        } catch {
            print("Failed to update LOD for grid \(coordinate): \(error)")
        }
    }
    
    func unloadGrid(_ coordinate: GridCoordinate) async {
        // Remove from scene
        sceneManager.removeGrid(coordinate)
        
        // Remove from loaded grids
        loadedGrids.removeValue(forKey: coordinate)
        
        print("Unloaded grid: \(coordinate)")
    }
    
    func preloadGridsInDirection(_ direction: SIMD3<Float>) async {
        let currentGrid = GridCoordinate(
            x: Int(playerPosition.x / 100.0),
            z: Int(playerPosition.z / 100.0)
        )
        
        // Calculate grids in movement direction
        let normalizedDirection = normalize(direction)
        let preloadDistance = 2
        
        for distance in 1...preloadDistance {
            let targetX = currentGrid.x + Int(normalizedDirection.x * Float(distance))
            let targetZ = currentGrid.z + Int(normalizedDirection.z * Float(distance))
            let targetCoord = GridCoordinate(x: targetX, z: targetZ)
            
            if loadedGrids[targetCoord] == nil {
                Task {
                    do {
                        _ = try await loadGrid(at: targetCoord)
                    } catch {
                        print("Failed to preload grid \(targetCoord): \(error)")
                    }
                }
            }
        }
    }
}
