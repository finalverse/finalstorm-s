//
//  Core/Graphics/MeshCache.swift
//  FinalStorm
//
//  Advanced multi-tier caching system for meshes and materials
//

import Foundation
import RealityKit
import simd

// MARK: - Advanced Mesh Cache

class MeshCache {
    private var primaryCache: [String: CacheEntry<MeshResource>] = [:]
    private var lodCache: [String: [Int: MeshResource]] = [:]
    private var memoryPressureThreshold: Int = 256 * 1024 * 1024 // 256MB
    private var maxEntries: Int = 1000
    
    private let cacheQueue = DispatchQueue(label: "com.finalstorm.meshcache", qos: .background)
    private var accessTimes: [String: Date] = [:]
    private var currentMemoryUsage: Int = 0
    
    struct CacheEntry<T> {
        let value: T
        let memorySize: Int
        let createdAt: Date
        var lastAccessed: Date
        let priority: CachePriority
        
        init(value: T, memorySize: Int, priority: CachePriority = .normal) {
            self.value = value
            self.memorySize = memorySize
            self.createdAt = Date()
            self.lastAccessed = Date()
            self.priority = priority
        }
        
        mutating func markAccessed() {
            lastAccessed = Date()
        }
    }
    
    enum CachePriority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
        
        static func < (lhs: CachePriority, rhs: CachePriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Cache Operations
    
    func getMesh(for key: String) -> MeshResource? {
        return cacheQueue.sync {
            guard var entry = primaryCache[key] else { return nil }
            
            entry.markAccessed()
            primaryCache[key] = entry
            accessTimes[key] = Date()
            
            return entry.value
        }
    }
    
    func storeMesh(_ mesh: MeshResource, for key: String, priority: CachePriority = .normal) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let memorySize = self.estimateMemorySize(mesh)
            let entry = CacheEntry(value: mesh, memorySize: memorySize, priority: priority)
            
            self.primaryCache[key] = entry
            self.accessTimes[key] = Date()
            self.currentMemoryUsage += memorySize
            
            // Trigger cleanup if needed
            if self.shouldTriggerCleanup() {
                self.performCleanup()
            }
        }
    }
    
    func storeLODMesh(_ mesh: MeshResource, for key: String, lodLevel: Int) {
        cacheQueue.async { [weak self] in
            if self?.lodCache[key] == nil {
                self?.lodCache[key] = [:]
            }
            self?.lodCache[key]?[lodLevel] = mesh
        }
    }
    
    func getLODMesh(for key: String, lodLevel: Int) -> MeshResource? {
        return cacheQueue.sync {
            return lodCache[key]?[lodLevel]
        }
    }
    
    // MARK: - Memory Management
    
    func optimizeMemory(targetSize: Int) async {
        await withCheckedContinuation { continuation in
            cacheQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                while self.currentMemoryUsage > targetSize && !self.primaryCache.isEmpty {
                    self.evictLeastRecentlyUsed()
                }
                
                continuation.resume()
            }
        }
    }
    
    func optimizeForQuality(_ quality: GraphicsConfiguration.QualityLevel) async {
        await withCheckedContinuation { continuation in
            cacheQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Adjust cache size based on quality
                let targetSize = quality == .ultra ? 512 * 1024 * 1024 : 256 * 1024 * 1024
                self.memoryPressureThreshold = targetSize
                
                // Clean up if over new threshold
                while self.currentMemoryUsage > targetSize && !self.primaryCache.isEmpty {
                    self.evictLeastRecentlyUsed()
                }
                
                continuation.resume()
            }
        }
    }
    
    private func shouldTriggerCleanup() -> Bool {
        return currentMemoryUsage > memoryPressureThreshold || primaryCache.count > maxEntries
    }
    
    private func performCleanup() {
        // Remove expired entries first
        removeExpiredEntries()
        
        // If still over threshold, remove LRU entries
        while currentMemoryUsage > memoryPressureThreshold * 3/4 && !primaryCache.isEmpty {
            evictLeastRecentlyUsed()
        }
    }
    
    private func removeExpiredEntries() {
        let now = Date()
        let maxAge: TimeInterval = 3600 // 1 hour
        
        let expiredKeys = primaryCache.compactMap { key, entry in
            now.timeIntervalSince(entry.lastAccessed) > maxAge && entry.priority != .critical ? key : nil
        }
        
        for key in expiredKeys {
            if let entry = primaryCache.removeValue(forKey: key) {
                currentMemoryUsage -= entry.memorySize
            }
            accessTimes.removeValue(forKey: key)
            lodCache.removeValue(forKey: key)
        }
    }
    
    private func evictLeastRecentlyUsed() {
        // Find LRU entry that's not critical priority
        let sortedEntries = primaryCache
            .filter { $0.value.priority != .critical }
            .sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        
        guard let (keyToRemove, entryToRemove) = sortedEntries.first else { return }
        
        primaryCache.removeValue(forKey: keyToRemove)
        accessTimes.removeValue(forKey: keyToRemove)
        lodCache.removeValue(forKey: keyToRemove)
        currentMemoryUsage -= entryToRemove.memorySize
    }
    
    private func estimateMemorySize(_ mesh: MeshResource) -> Int {
        // Rough estimation based on mesh complexity
        // In a real implementation, you'd inspect the mesh descriptor
        return 50 * 1024 // 50KB average estimate
    }
    
    // MARK: - Cache Statistics
    
    var memoryUsage: Int {
        return cacheQueue.sync { currentMemoryUsage }
    }
    
    var count: Int {
        return cacheQueue.sync { primaryCache.count }
    }
    
    func clearAll() {
        cacheQueue.sync {
            primaryCache.removeAll()
            lodCache.removeAll()
            accessTimes.removeAll()
            currentMemoryUsage = 0
        }
    }
    
    func getCacheStatistics() -> CacheStatistics {
        return cacheQueue.sync {
            CacheStatistics(
                totalEntries: primaryCache.count,
                memoryUsage: currentMemoryUsage,
                lodEntries: lodCache.values.reduce(0) { $0 + $1.count },
                oldestEntry: primaryCache.values.min { $0.createdAt < $1.createdAt }?.createdAt,
                newestEntry: primaryCache.values.max { $0.createdAt < $1.createdAt }?.createdAt
            )
        }
    }
}

struct CacheStatistics {
    let totalEntries: Int
    let memoryUsage: Int
    let lodEntries: Int
    let oldestEntry: Date?
    let newestEntry: Date?
    
    var averageEntrySize: Int {
        guard totalEntries > 0 else { return 0 }
        return memoryUsage / totalEntries
    }
}

// MARK: - Material Cache

class MaterialCache {
    private var cache: [String: CacheEntry<Material>] = [:]
    private var currentMemoryUsage: Int = 0
    private let cacheQueue = DispatchQueue(label: "com.finalstorm.materialcache", qos: .background)
    
    struct CacheEntry<T> {
        let value: T
        let memorySize: Int
        let createdAt: Date
        var lastAccessed: Date
        
        init(value: T, memorySize: Int) {
            self.value = value
            self.memorySize = memorySize
            self.createdAt = Date()
            self.lastAccessed = Date()
        }
        
        mutating func markAccessed() {
            lastAccessed = Date()
        }
    }
    
    func getMaterial(for key: String) -> Material? {
        return cacheQueue.sync {
            guard var entry = cache[key] else { return nil }
            entry.markAccessed()
            cache[key] = entry
            return entry.value
        }
    }
    
    func storeMaterial(_ material: Material, for key: String) {
        cacheQueue.async { [weak self] in
            let memorySize = 1024 // Rough estimate for material
            let entry = CacheEntry(value: material, memorySize: memorySize)
            self?.cache[key] = entry
            self?.currentMemoryUsage += memorySize
        }
    }
    
    func optimizeMemory(targetSize: Int) async {
        await withCheckedContinuation { continuation in
            cacheQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                while self.currentMemoryUsage > targetSize && !self.cache.isEmpty {
                    let sortedEntries = self.cache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
                    if let (keyToRemove, entryToRemove) = sortedEntries.first {
                        self.cache.removeValue(forKey: keyToRemove)
                        self.currentMemoryUsage -= entryToRemove.memorySize
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    func optimizeForQuality(_ quality: GraphicsConfiguration.QualityLevel) async {
        // Materials are less affected by quality settings
        await optimizeMemory(64 * 1024 * 1024) // 64MB limit
    }
    
    var memoryUsage: Int {
        return cacheQueue.sync { currentMemoryUsage }
    }
    
    func clearAll() {
        cacheQueue.sync {
            cache.removeAll()
            currentMemoryUsage = 0
        }
    }
}
