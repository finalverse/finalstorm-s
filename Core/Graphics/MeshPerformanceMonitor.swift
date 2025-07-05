//
//  Core/Graphics/MeshPerformanceMonitor.swift
//  FinalStorm
//
//  Performance monitoring and analytics for mesh system
//

import Foundation

class MeshPerformanceMonitor {
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var loadTimes: [TimeInterval] = []
    private var memoryPeaks: [Int] = []
    private let maxSamples = 1000
    
    // MARK: - Metrics Recording
    
    func recordCacheHit() {
        cacheHits += 1
    }
    
    func recordCacheMiss() {
        cacheMisses += 1
    }
    
    func recordLoadTime(_ time: TimeInterval) {
        loadTimes.append(time)
        if loadTimes.count > maxSamples {
            loadTimes.removeFirst()
        }
    }
    
    func recordMemoryPeak(_ peak: Int) {
        memoryPeaks.append(peak)
        if memoryPeaks.count > maxSamples {
            memoryPeaks.removeFirst()
        }
    }
    
    // MARK: - Computed Metrics
    
    var cacheHitRate: Float {
        let total = cacheHits + cacheMisses
        return total > 0 ? Float(cacheHits) / Float(total) : 0.0
    }
    
    var averageLoadTime: TimeInterval {
        return loadTimes.isEmpty ? 0.0 : loadTimes.reduce(0, +) / Double(loadTimes.count)
    }
    
    var maxLoadTime: TimeInterval {
        return loadTimes.max() ?? 0.0
    }
    
    var averageMemoryPeak: Int {
        return memoryPeaks.isEmpty ? 0 : memoryPeaks.reduce(0, +) / memoryPeaks.count
    }
    
    var maxMemoryPeak: Int {
        return memoryPeaks.max() ?? 0
    }
    
    // MARK: - Performance Report
    
    func generateReport() -> PerformanceReport {
        return PerformanceReport(
            cacheHitRate: cacheHitRate,
            totalCacheAccesses: cacheHits + cacheMisses,
            averageLoadTime: averageLoadTime,
            maxLoadTime: maxLoadTime,
            averageMemoryPeak: averageMemoryPeak,
            maxMemoryPeak: maxMemoryPeak,
            totalSamples: loadTimes.count
        )
    }
    
    func reset() {
        cacheHits = 0
        cacheMisses = 0
        loadTimes.removeAll()
        memoryPeaks.removeAll()
    }
}

struct PerformanceReport {
    let cacheHitRate: Float
    let totalCacheAccesses: Int
    let averageLoadTime: TimeInterval
    let maxLoadTime: TimeInterval
    let averageMemoryPeak: Int
    let maxMemoryPeak: Int
    let totalSamples: Int
    
    var formattedReport: String {
        return """
        Mesh System Performance Report
        =============================
        Cache Hit Rate: \(String(format: "%.1f%%", cacheHitRate * 100))
        Total Cache Accesses: \(totalCacheAccesses)
        Average Load Time: \(String(format: "%.3f", averageLoadTime))s
        Max Load Time: \(String(format: "%.3f", maxLoadTime))s
        Average Memory Peak: \(ByteCountFormatter.string(fromByteCount: Int64(averageMemoryPeak), countStyle: .memory))
        Max Memory Peak: \(ByteCountFormatter.string(fromByteCount: Int64(maxMemoryPeak), countStyle: .memory))
        Total Samples: \(totalSamples)
        """
    }
}
