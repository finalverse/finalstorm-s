//
//  Core/Rendering/BufferPool.swift
//  FinalStorm
//
//  High-performance buffer management system with pooling and automatic resizing
//

import Foundation
import Metal

class BufferPool {
    private var device: MTLDevice!
    private var bufferPools: [BufferType: [MTLBuffer]] = [:]
    private var inUseBuffers: Set<ObjectIdentifier> = []
    private var bufferSizes: [ObjectIdentifier: Int] = [:]
    private let poolQueue = DispatchQueue(label: "com.finalstorm.bufferpool", qos: .userInitiated)
    
    // Configuration
    private let maxPoolSize = 100
    private let initialBufferCount = 10
    private var totalMemoryUsage: Int = 0
    private let memoryLimit = 256 * 1024 * 1024 // 256MB
    
    enum BufferType: CaseIterable {
        case vertex
        case index
        case uniform
        case storage
        case staging
        case instance
        case compute
        
        var defaultSize: Int {
            switch self {
            case .vertex: return 1024 * 1024 // 1MB
            case .index: return 512 * 1024   // 512KB
            case .uniform: return 64 * 1024  // 64KB
            case .storage: return 2 * 1024 * 1024 // 2MB
            case .staging: return 1024 * 1024 // 1MB
            case .instance: return 256 * 1024 // 256KB
            case .compute: return 1024 * 1024 // 1MB
            }
        }
        
        var storageMode: MTLStorageMode {
            switch self {
            case .vertex, .index: return .managed
            case .uniform: return .shared
            case .storage, .compute: return .shared
            case .staging: return .shared
            case .instance: return .shared
            }
        }
    }
    
    func initialize(device: MTLDevice) throws {
        self.device = device
        
        // Pre-allocate initial buffers for each type
        for bufferType in BufferType.allCases {
            try preallocateBuffers(type: bufferType, count: initialBufferCount)
        }
        
        print("BufferPool initialized with \(getTotalBufferCount()) buffers")
    }
    
    // MARK: - Buffer Allocation
    
    func allocateBuffer(type: BufferType, size: Int, label: String? = nil) -> MTLBuffer? {
        return poolQueue.sync {
            // Try to find a suitable buffer from the pool
            if let buffer = findAvailableBuffer(type: type, minimumSize: size) {
                markBufferInUse(buffer)
                buffer.label = label
                return buffer
            }
            
            // Create new buffer if none available
            let actualSize = max(size, type.defaultSize)
            guard let newBuffer = createBuffer(type: type, size: actualSize, label: label) else {
                return nil
            }
            
            markBufferInUse(newBuffer)
            return newBuffer
        }
    }
    
    func releaseBuffer(_ buffer: MTLBuffer) {
        poolQueue.async { [weak self] in
            guard let self = self else { return }
            
            let bufferId = ObjectIdentifier(buffer)
            self.inUseBuffers.remove(bufferId)
            
            // Return buffer to appropriate pool
            if let bufferType = self.getBufferType(buffer) {
                if self.bufferPools[bufferType] == nil {
                    self.bufferPools[bufferType] = []
                }
                
                // Only return to pool if we're not over the limit
                if self.bufferPools[bufferType]!.count < self.maxPoolSize {
                    self.bufferPools[bufferType]!.append(buffer)
                } else {
                    // Remove from tracking
                    if let size = self.bufferSizes[bufferId] {
                        self.totalMemoryUsage -= size
                        self.bufferSizes.removeValue(forKey: bufferId)
                    }
                }
            }
        }
    }
    
    private func findAvailableBuffer(type: BufferType, minimumSize: Int) -> MTLBuffer? {
        guard let pool = bufferPools[type], !pool.isEmpty else {
            return nil
        }
        
        // Find the smallest buffer that meets the size requirement
        var bestBuffer: MTLBuffer?
        var bestIndex: Int?
        var bestSize = Int.max
        
        for (index, buffer) in pool.enumerated() {
            let bufferSize = buffer.length
            if bufferSize >= minimumSize && bufferSize < bestSize {
                bestBuffer = buffer
                bestIndex = index
                bestSize = bufferSize
            }
        }
        
        if let buffer = bestBuffer, let index = bestIndex {
            bufferPools[type]!.remove(at: index)
            return buffer
        }
        
        return nil
    }
    
    private func createBuffer(type: BufferType, size: Int, label: String?) -> MTLBuffer? {
        // Check memory limit
        if totalMemoryUsage + size > memoryLimit {
            performMemoryCleanup()
            
            if totalMemoryUsage + size > memoryLimit {
                print("Warning: Buffer allocation would exceed memory limit")
                return nil
            }
        }
        
        guard let buffer = device.makeBuffer(length: size, options: .init(rawValue: type.storageMode.rawValue)) else {
            return nil
        }
        
        buffer.label = label
        
        let bufferId = ObjectIdentifier(buffer)
        bufferSizes[bufferId] = size
        totalMemoryUsage += size
        
        return buffer
    }
    
    private func preallocateBuffers(type: BufferType, count: Int) throws {
        bufferPools[type] = []
        
        for i in 0..<count {
            guard let buffer = createBuffer(
                type: type,
                size: type.defaultSize,
                label: "\(type)_Pool_\(i)"
            ) else {
                throw BufferPoolError.allocationFailed
            }
            
            bufferPools[type]!.append(buffer)
        }
    }
    
    // MARK: - Buffer Management
    
    private func markBufferInUse(_ buffer: MTLBuffer) {
        let bufferId = ObjectIdentifier(buffer)
        inUseBuffers.insert(bufferId)
    }
    
    private func getBufferType(_ buffer: MTLBuffer) -> BufferType? {
        // Determine buffer type based on label or usage patterns
        guard let label = buffer.label else { return nil }
        
        for type in BufferType.allCases {
            if label.contains(String(describing: type)) {
                return type
            }
        }
        
        return nil
    }
    
    // MARK: - Memory Management
    
    private func performMemoryCleanup() {
        print("Performing buffer pool memory cleanup...")
        
        let initialMemory = totalMemoryUsage
        
        // Remove excess buffers from pools
        for type in BufferType.allCases {
            if var pool = bufferPools[type] {
                let targetSize = max(initialBufferCount, pool.count / 2)
                while pool.count > targetSize {
                    let buffer = pool.removeLast()
                    let bufferId = ObjectIdentifier(buffer)
                    
                    if let size = bufferSizes[bufferId] {
                        totalMemoryUsage -= size
                        bufferSizes.removeValue(forKey: bufferId)
                    }
                }
                bufferPools[type] = pool
            }
        }
        
        let freedMemory = initialMemory - totalMemoryUsage
        print("Freed \(ByteCountFormatter.string(fromByteCount: Int64(freedMemory), countStyle: .memory)) from buffer pool")
    }
    
    func getTotalMemoryUsage() -> Int {
        return poolQueue.sync { totalMemoryUsage }
    }
    
    func getTotalBufferCount() -> Int {
        return poolQueue.sync {
            return bufferPools.values.reduce(0) { $0 + $1.count } + inUseBuffers.count
        }
    }
    
    func getPoolStatistics() -> BufferPoolStatistics {
        return poolQueue.sync {
            var typeStatistics: [BufferType: TypeStatistics] = [:]
            
            for type in BufferType.allCases {
                let poolCount = bufferPools[type]?.count ?? 0
                let inUseCount = inUseBuffers.count // This is simplified - would need better tracking
                
                typeStatistics[type] = TypeStatistics(
                    pooledCount: poolCount,
                    inUseCount: inUseCount,
                    totalMemory: calculateMemoryForType(type)
                )
            }
            
            return BufferPoolStatistics(
                totalMemoryUsage: totalMemoryUsage,
                totalBufferCount: getTotalBufferCount(),
                inUseBufferCount: inUseBuffers.count,
                typeStatistics: typeStatistics
            )
        }
    }
    
    private func calculateMemoryForType(_ type: BufferType) -> Int {
        // Calculate total memory usage for a specific buffer type
        var totalMemory = 0
        
        if let pool = bufferPools[type] {
            for buffer in pool {
                totalMemory += buffer.length
            }
        }
        
        return totalMemory
    }
    
    // MARK: - Specialized Allocators
    
    func allocateVertexBuffer<T>(for vertices: [T], label: String? = nil) -> MTLBuffer? {
        let size = vertices.count * MemoryLayout<T>.stride
        guard let buffer = allocateBuffer(type: .vertex, size: size, label: label) else {
            return nil
        }
        
        let pointer = buffer.contents().bindMemory(to: T.self, capacity: vertices.count)
        vertices.withUnsafeBufferPointer { bufferPointer in
            pointer.initialize(from: bufferPointer.baseAddress!, count: vertices.count)
        }
        
        return buffer
    }
    
    func allocateIndexBuffer(for indices: [UInt32], label: String? = nil) -> MTLBuffer? {
        let size = indices.count * MemoryLayout<UInt32>.stride
        guard let buffer = allocateBuffer(type: .index, size: size, label: label) else {
            return nil
        }
        
        let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: indices.count)
        indices.withUnsafeBufferPointer { bufferPointer in
            pointer.initialize(from: bufferPointer.baseAddress!, count: indices.count)
        }
        
        return buffer
    }
    
    func allocateUniformBuffer<T>(for data: T, label: String? = nil) -> MTLBuffer? {
        let size = MemoryLayout<T>.stride
        guard let buffer = allocateBuffer(type: .uniform, size: size, label: label) else {
            return nil
        }
        
        buffer.contents().bindMemory(to: T.self, capacity: 1).pointee = data
        
        return buffer
    }
    
    func allocateInstanceBuffer<T>(for instances: [T], label: String? = nil) -> MTLBuffer? {
        let size = instances.count * MemoryLayout<T>.stride
        guard let buffer = allocateBuffer(type: .instance, size: size, label: label) else {
            return nil
        }
        
        let pointer = buffer.contents().bindMemory(to: T.self, capacity: instances.count)
        instances.withUnsafeBufferPointer { bufferPointer in
            pointer.initialize(from: bufferPointer.baseAddress!, count: instances.count)
        }
        
        return buffer
    }
}

// MARK: - Statistics and Monitoring

struct BufferPoolStatistics {
    let totalMemoryUsage: Int
    let totalBufferCount: Int
    let inUseBufferCount: Int
    let typeStatistics: [BufferPool.BufferType: TypeStatistics]
    
    struct TypeStatistics {
        let pooledCount: Int
        let inUseCount: Int
        let totalMemory: Int
    }
    
    var formattedReport: String {
        var report = "Buffer Pool Statistics\n"
        report += "=====================\n"
        report += "Total Memory: \(ByteCountFormatter.string(fromByteCount: Int64(totalMemoryUsage), countStyle: .memory))\n"
        report += "Total Buffers: \(totalBufferCount)\n"
        report += "In Use: \(inUseBufferCount)\n"
        report += "Available: \(totalBufferCount - inUseBufferCount)\n\n"
        
        for (type, stats) in typeStatistics {
            report += "\(type):\n"
            report += "  Pooled: \(stats.pooledCount)\n"
            report += "  In Use: \(stats.inUseCount)\n"
            report += "  Memory: \(ByteCountFormatter.string(fromByteCount: Int64(stats.totalMemory), countStyle: .memory))\n"
        }
        
        return report
    }
}

enum BufferPoolError: Error {
    case allocationFailed
    case memoryLimitExceeded
    case invalidBufferType
}
