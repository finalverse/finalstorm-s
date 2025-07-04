//
//  Services/Inventory/AssetManager.swift
//  FinalStorm
//
//  Asset management specifically for inventory items
//  Handles texture loading, mesh caching, and asset optimization
//

import Foundation
import RealityKit
import Combine

@MainActor
class AssetManager: ObservableObject {
    // MARK: - Properties
    @Published var loadingAssets: Set<UUID> = []
    @Published var failedAssets: Set<UUID> = []
    
    private let assetCache: AssetCache
    private let assetService: AssetService
    private var loadingTasks: [UUID: Task<Any, Error>] = [:]
    
    // MARK: - Initialization
    init() {
        self.assetCache = AssetCache()
        self.assetService = AssetService()
    }
    
    // MARK: - Texture Management
    func loadTexture(_ assetId: UUID) async throws -> TextureResource {
        // Check if already loading
        if let existingTask = loadingTasks[assetId] as? Task<TextureResource, Error> {
            return try await existingTask.value
        }
        
        loadingAssets.insert(assetId)
        failedAssets.remove(assetId)
        
        let task = Task<TextureResource, Error> {
            do {
                let texture = try await assetService.loadTexture(assetId)
                await MainActor.run {
                    loadingAssets.remove(assetId)
                    loadingTasks.removeValue(forKey: assetId)
                }
                return texture
            } catch {
                await MainActor.run {
                    loadingAssets.remove(assetId)
                    failedAssets.insert(assetId)
                    loadingTasks.removeValue(forKey: assetId)
                }
                throw error
            }
        }
        
        loadingTasks[assetId] = task
        return try await task.value
    }
    
    func loadMesh(_ assetId: UUID) async throws -> MeshResource {
        // Check if already loading
        if let existingTask = loadingTasks[assetId] as? Task<MeshResource, Error> {
            return try await existingTask.value
        }
        
        loadingAssets.insert(assetId)
        failedAssets.remove(assetId)
        
        let task = Task<MeshResource, Error> {
            do {
                let mesh = try await assetService.loadMesh(assetId)
                await MainActor.run {
                    loadingAssets.remove(assetId)
                    loadingTasks.removeValue(forKey: assetId)
                }
                return mesh
            } catch {
                await MainActor.run {
                    loadingAssets.remove(assetId)
                    failedAssets.insert(assetId)
                    loadingTasks.removeValue(forKey: assetId)
                }
                throw error
            }
        }
        
        loadingTasks[assetId] = task
        return try await task.value
    }
    
    // MARK: - Preloading
    func preloadItemAssets(_ items: [InventoryItem]) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    // Preload icon
                    if let iconAssetId = item.iconAssetId {
                        group.addTask {
                            do {
                                _ = try await self.loadTexture(iconAssetId)
                            } catch {
                                print("Failed to preload icon for \(item.name): \(error)")
                            }
                        }
                    }
                    
                    // Preload mesh for equipped items
                    if item.isEquipped, let meshAssetId = item.meshAssetId {
                        group.addTask {
                            do {
                                _ = try await self.loadMesh(meshAssetId)
                            } catch {
                                print("Failed to preload mesh for \(item.name): \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cache Management
    func clearAssetCache() {
        assetCache.clearAll()
        loadingAssets.removeAll()
        failedAssets.removeAll()
        
        // Cancel ongoing tasks
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
    }
    
    func getCacheSize() -> Int64 {
        return assetCache.getTotalSize()
    }
}
