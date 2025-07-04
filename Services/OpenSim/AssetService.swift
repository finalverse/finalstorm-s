//
//  Services/OpenSim/AssetService.swift
//  FinalStorm
//
//  OpenSimulator asset service for managing textures, meshes, sounds, and other assets
//  Handles asset downloading, caching, and format conversion
//

import Foundation
import RealityKit
import Combine

@MainActor
class AssetService: ObservableObject {
    // MARK: - Properties
    @Published var downloadProgress: [UUID: Float] = [:]
    @Published var cacheSize: Int64 = 0
    
    private let assetCache: AssetCache
    private let httpSession: URLSession
    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    private let maxConcurrentDownloads = 10
    private var downloadQueue: OperationQueue
    
    // Asset servers and capabilities
    private var assetServerURL: URL?
    private var capabilities: [String: URL] = [:]
    
    // MARK: - Initialization
    init() {
        self.assetCache = AssetCache()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = URLCache(memoryCapacity: 100 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024)
        self.httpSession = URLSession(configuration: config)
        
        self.downloadQueue = OperationQueue()
        downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads
        downloadQueue.qualityOfService = .utility
        
        updateCacheSize()
    }
    
    // MARK: - Asset Loading
    func loadAsset<T: Asset>(_ assetId: UUID, type: T.Type) async throws -> T {
        // Check cache first
        if let cachedAsset = assetCache.getAsset(assetId, type: type) {
            return cachedAsset
        }
        
        // Download asset
        let assetData = try await downloadAsset(assetId)
        
        // Convert to appropriate type
        let asset = try await convertAsset(assetData, to: type, assetId: assetId)
        
        // Cache the asset
        assetCache.storeAsset(asset, for: assetId)
        
        updateCacheSize()
        
        return asset
    }
    
    func loadTexture(_ textureId: UUID) async throws -> TextureResource {
        return try await loadAsset(textureId, type: TextureAsset.self).textureResource
    }
    
    func loadMesh(_ meshId: UUID) async throws -> MeshResource {
        return try await loadAsset(meshId, type: MeshAsset.self).meshResource
    }
    
    func loadSound(_ soundId: UUID) async throws -> AudioFileResource {
        return try await loadAsset(soundId, type: SoundAsset.self).audioResource
    }
    
    func loadAnimation(_ animationId: UUID) async throws -> AnimationResource {
        return try await loadAsset(animationId, type: AnimationAsset.self).animationResource
    }
    
    // MARK: - Asset Downloading
    private func downloadAsset(_ assetId: UUID) async throws -> Data {
        // Check if already downloading
        if let existingTask = downloadTasks[assetId] {
            // Wait for existing download
            return try await withCheckedThrowingContinuation { continuation in
                // This is simplified - in practice you'd want to handle multiple waiters
                continuation.resume(throwing: AssetError.downloadInProgress)
            }
        }
        
        // Construct asset URL
        guard let assetURL = buildAssetURL(for: assetId) else {
            throw AssetError.invalidAssetURL
        }
        
        downloadProgress[assetId] = 0.0
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = httpSession.downloadTask(with: assetURL) { [weak self] url, response, error in
                Task { @MainActor in
                    self?.downloadTasks.removeValue(forKey: assetId)
                    self?.downloadProgress.removeValue(forKey: assetId)
                    
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.resume(throwing: AssetError.downloadFailed)
                        return
                    }
                    
                    guard let url = url else {
                        continuation.resume(throwing: AssetError.noData)
                        return
                    }
                    
                    do {
                        let data = try Data(contentsOf: url)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            downloadTasks[assetId] = task
            task.resume()
        }
    }
    
    private func buildAssetURL(for assetId: UUID) -> URL? {
        // Try CAPS first
        if let getTextureURL = capabilities["GetTexture"] {
            return getTextureURL.appendingPathComponent("?texture_id=\(assetId.uuidString)")
        }
        
        // Fall back to legacy asset server
        if let assetServerURL = assetServerURL {
            return assetServerURL.appendingPathComponent("assets/\(assetId.uuidString)/data")
        }
        
        return nil
    }
    
    // MARK: - Asset Conversion
    private func convertAsset<T: Asset>(_ data: Data, to type: T.Type, assetId: UUID) async throws -> T {
        switch type {
        case is TextureAsset.Type:
            return try await convertToTexture(data, assetId: assetId) as! T
        case is MeshAsset.Type:
            return try await convertToMesh(data, assetId: assetId) as! T
        case is SoundAsset.Type:
            return try await convertToSound(data, assetId: assetId) as! T
        case is AnimationAsset.Type:
            return try await convertToAnimation(data, assetId: assetId) as! T
        default:
            throw AssetError.unsupportedAssetType
        }
    }
    
    private func convertToTexture(_ data: Data, assetId: UUID) async throws -> TextureAsset {
        // Detect format
        let format = detectImageFormat(data)
        
        let textureResource: TextureResource
        
        switch format {
        case .jpeg2000:
            // Convert JPEG2000 to standard format
            let convertedData = try convertJPEG2000(data)
            textureResource = try await TextureResource.load(from: convertedData)
            
        case .tga:
            // Convert TGA
            let convertedData = try convertTGA(data)
            textureResource = try await TextureResource.load(from: convertedData)
            
        case .png, .jpeg:
            // Standard formats
            textureResource = try await TextureResource.load(from: data)
            
        default:
            throw AssetError.unsupportedImageFormat
        }
        
        return TextureAsset(id: assetId, textureResource: textureResource, originalData: data)
    }
    
    private func convertToMesh(_ data: Data, assetId: UUID) async throws -> MeshAsset {
        // Detect mesh format
        let format = detectMeshFormat(data)
        
        let meshResource: MeshResource
        
        switch format {
        case .dae:
            // Convert DAE/Collada
            meshResource = try await convertDAEMesh(data)
            
        case .obj:
            // Convert OBJ
            meshResource = try await convertOBJMesh(data)
            
        case .llmesh:
            // OpenSim/SL specific mesh format
            meshResource = try await convertLLMesh(data)
            
        default:
            throw AssetError.unsupportedMeshFormat
        }
        
        return MeshAsset(id: assetId, meshResource: meshResource, originalData: data)
    }
    
    private func convertToSound(_ data: Data, assetId: UUID) async throws -> SoundAsset {
        // Detect audio format
        let format = detectAudioFormat(data)
        
        var audioData = data
        
        // Convert to supported format if needed
        if format == .ogg {
            audioData = try convertOGGToAAC(data)
        }
        
        // Create temporary file for AudioFileResource
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(assetId.uuidString)
            .appendingPathExtension("m4a")
        
        try audioData.write(to: tempURL)
        
        let audioResource = try await AudioFileResource.load(contentsOf: tempURL)
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        
        return SoundAsset(id: assetId, audioResource: audioResource, originalData: data)
    }
    
    private func convertToAnimation(_ data: Data, assetId: UUID) async throws -> AnimationAsset {
        // Parse BVH or other animation format
        let animationData = try parseBVHAnimation(data)
        
        // Convert to RealityKit animation
        let animationResource = try await createAnimationResource(from: animationData)
        
        return AnimationAsset(id: assetId, animationResource: animationResource, originalData: data)
    }
    
    // MARK: - Format Detection
    private func detectImageFormat(_ data: Data) -> ImageFormat {
        guard data.count >= 4 else { return .unknown }
        
        let header = data.prefix(4)
        
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .png
        } else if header.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        } else if header.starts(with: [0x00, 0x00, 0x00, 0x0C]) {
            return .jpeg2000
        } else if data.count >= 18 && data[data.count - 18] == 0x54 && data[data.count - 17] == 0x52 {
            return .tga
        }
        
        return .unknown
    }
    
    private func detectMeshFormat(_ data: Data) -> MeshFormat {
        guard let header = String(data: data.prefix(100), encoding: .utf8) else {
            return .unknown
        }
        
        if header.contains("<?xml") && header.contains("COLLADA") {
            return .dae
        } else if header.contains("v ") || header.contains("f ") {
            return .obj
        } else if data.count >= 4 && data.prefix(4) == Data([0x4D, 0x65, 0x73, 0x68]) {
            return .llmesh
        }
        
        return .unknown
    }
    
    private func detectAudioFormat(_ data: Data) -> AudioFormat {
        guard data.count >= 4 else { return .unknown }
        
        let header = data.prefix(4)
        
        if header.starts(with: [0x4F, 0x67, 0x67, 0x53]) {
            return .ogg
        } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return .wav
        } else if data.count >= 8 && data.subdata(in: 4..<8) == Data([0x66, 0x74, 0x79, 0x70]) {
            return .mp4
        }
        
        return .unknown
    }
    
    // MARK: - Format Conversion
    private func convertJPEG2000(_ data: Data) throws -> Data {
        // This would use a JPEG2000 decoder library
        // For now, return original data (assuming it's supported)
        throw AssetError.conversionNotImplemented
    }
    
    private func convertTGA(_ data: Data) throws -> Data {
        // TGA to PNG conversion
        // This would implement TGA decoding
        throw AssetError.conversionNotImplemented
    }
    
    private func convertDAEMesh(_ data: Data) async throws -> MeshResource {
        // DAE/Collada to MeshResource conversion
        // This would parse the DAE XML and extract geometry
        throw AssetError.conversionNotImplemented
    }
    
    private func convertOBJMesh(_ data: Data) async throws -> MeshResource {
        // OBJ to MeshResource conversion
        // Parse OBJ format and create mesh
        let objContent = String(data: data, encoding: .utf8) ?? ""
        return try await parseOBJToMesh(objContent)
    }
    
    private func convertLLMesh(_ data: Data) async throws -> MeshResource {
        // OpenSim/SecondLife mesh format conversion
        // This would implement the LLSD mesh format parsing
        throw AssetError.conversionNotImplemented
    }
    
    private func convertOGGToAAC(_ data: Data) throws -> Data {
        // OGG Vorbis to AAC conversion
        // This would use an audio conversion library
        throw AssetError.conversionNotImplemented
    }
    
    private func parseOBJToMesh(_ objContent: String) async throws -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        
        let lines = objContent.components(separatedBy: .newlines)
        
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            guard !parts.isEmpty else { continue }
            
            switch parts[0] {
            case "v": // Vertex
                if parts.count >= 4 {
                    let x = Float(parts[1]) ?? 0
                    let y = Float(parts[2]) ?? 0
                    let z = Float(parts[3]) ?? 0
                    vertices.append([x, y, z])
                }
                
            case "vn": // Normal
                if parts.count >= 4 {
                    let x = Float(parts[1]) ?? 0
                    let y = Float(parts[2]) ?? 0
                    let z = Float(parts[3]) ?? 0
                    normals.append([x, y, z])
                }
                
            case "vt": // Texture coordinate
                if parts.count >= 3 {
                    let u = Float(parts[1]) ?? 0
                    let v = Float(parts[2]) ?? 0
                    uvs.append([u, v])
                }
                
            case "f": // Face
                for i in 1..<parts.count {
                    let faceData = parts[i].components(separatedBy: "/")
                    if let vertexIndex = Int(faceData[0]) {
                        indices.append(UInt32(vertexIndex - 1)) // OBJ indices are 1-based
                    }
                }
                
            default:
                continue
            }
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        if !normals.isEmpty {
            descriptor.normals = MeshBuffer(normals)
        }
        if !uvs.isEmpty {
            descriptor.textureCoordinates = MeshBuffer(uvs)
        }
        descriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [descriptor])
    }
    
    private func parseBVHAnimation(_ data: Data) throws -> AnimationData {
        // Parse BVH (Biovision Hierarchy) animation format
        // This is a complex format used for skeletal animation
        throw AssetError.conversionNotImplemented
    }
    
    private func createAnimationResource(from animationData: AnimationData) async throws -> AnimationResource {
        // Convert parsed animation data to RealityKit AnimationResource
        throw AssetError.conversionNotImplemented
    }
    
    // MARK: - Cache Management
    func clearCache() {
        assetCache.clearAll()
        updateCacheSize()
    }
    
    func clearCacheForAsset(_ assetId: UUID) {
        assetCache.removeAsset(assetId)
        updateCacheSize()
    }
    
    func getCacheInfo() -> CacheInfo {
        return assetCache.getCacheInfo()
    }
    
    private func updateCacheSize() {
        cacheSize = assetCache.getTotalSize()
    }
    
    // MARK: - Configuration
    func updateAssetServerURL(_ url: URL) {
        assetServerURL = url
    }
    
    func updateCapabilities(_ caps: [String: URL]) {
        capabilities = caps
    }
}

// MARK: - Asset Types
protocol Asset {
    var id: UUID { get }
    var originalData: Data { get }
    var createdAt: Date { get }
}

struct TextureAsset: Asset {
    let id: UUID
    let textureResource: TextureResource
    let originalData: Data
    let createdAt: Date = Date()
}

struct MeshAsset: Asset {
    let id: UUID
    let meshResource: MeshResource
    let originalData: Data
    let createdAt: Date = Date()
}

struct SoundAsset: Asset {
    let id: UUID
    let audioResource: AudioFileResource
    let originalData: Data
    let createdAt: Date = Date()
}

struct AnimationAsset: Asset {
    let id: UUID
    let animationResource: AnimationResource
    let originalData: Data
    let createdAt: Date = Date()
}

// MARK: - Format Enums
enum ImageFormat {
    case png
    case jpeg
    case jpeg2000
    case tga
    case unknown
}

enum MeshFormat {
    case dae
    case obj
    case llmesh
    case unknown
}

enum AudioFormat {
    case ogg
    case wav
    case mp4
    case unknown
}

// MARK: - Animation Data
struct AnimationData {
    let bones: [BoneData]
    let keyframes: [KeyframeData]
    let duration: TimeInterval
}

struct BoneData {
    let name: String
    let parentIndex: Int?
    let restTransform: Transform
}

struct KeyframeData {
    let time: TimeInterval
    let boneTransforms: [Transform]
}

// MARK: - Asset Cache
class AssetCache {
    private var cache: [UUID: Any] = [:]
    private let cacheQueue = DispatchQueue(label: "asset.cache", attributes: .concurrent)
    private let maxCacheSize: Int64 = 1024 * 1024 * 1024 // 1GB
    private var currentSize: Int64 = 0
    
    func getAsset<T: Asset>(_ id: UUID, type: T.Type) -> T? {
        return cacheQueue.sync {
            return cache[id] as? T
        }
    }
    
    func storeAsset<T: Asset>(_ asset: T, for id: UUID) {
        cacheQueue.async(flags: .barrier) {
            self.cache[id] = asset
            self.currentSize += Int64(asset.originalData.count)
            
            // Cleanup if cache is too large
            if self.currentSize > self.maxCacheSize {
                self.performCacheCleanup()
            }
        }
    }
    
    func removeAsset(_ id: UUID) {
        cacheQueue.async(flags: .barrier) {
            if let asset = self.cache[id] as? any Asset {
                self.currentSize -= Int64(asset.originalData.count)
            }
            self.cache.removeValue(forKey: id)
        }
    }
    
    func clearAll() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
            self.currentSize = 0
        }
    }
    
    func getTotalSize() -> Int64 {
        return cacheQueue.sync {
            return currentSize
        }
    }
    
    func getCacheInfo() -> CacheInfo {
        return cacheQueue.sync {
            return CacheInfo(
                itemCount: cache.count,
                totalSize: currentSize,
                maxSize: maxCacheSize
            )
        }
    }
    
    private func performCacheCleanup() {
        // Remove oldest assets until we're under the limit
        let targetSize = maxCacheSize * 8 / 10 // Target 80% of max size
        
        // Sort by creation date and remove oldest
        let sortedAssets = cache.compactMap { (key, value) -> (UUID, Date, Int64)? in
            guard let asset = value as? any Asset else { return nil }
            return (key, asset.createdAt, Int64(asset.originalData.count))
        }.sorted { $0.1 < $1.1 }
        
        for (id, _, size) in sortedAssets {
            if currentSize <= targetSize {
                break
            }
            
            cache.removeValue(forKey: id)
            currentSize -= size
        }
    }
}

struct CacheInfo {
    let itemCount: Int
    let totalSize: Int64
    let maxSize: Int64
    
    var usagePercentage: Float {
        return Float(totalSize) / Float(maxSize)
    }
    
    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedMaxSize: String {
        return ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
    }
}

// MARK: - Error Types
enum AssetError: Error, LocalizedError {
    case invalidAssetURL
    case downloadFailed
    case downloadInProgress
    case noData
    case unsupportedAssetType
    case unsupportedImageFormat
    case unsupportedMeshFormat
    case conversionNotImplemented
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAssetURL:
            return "Invalid asset URL"
        case .downloadFailed:
            return "Asset download failed"
        case .downloadInProgress:
            return "Asset download already in progress"
        case .noData:
            return "No data received"
        case .unsupportedAssetType:
            return "Unsupported asset type"
        case .unsupportedImageFormat:
            return "Unsupported image format"
        case .unsupportedMeshFormat:
            return "Unsupported mesh format"
        case .conversionNotImplemented:
            return "Format conversion not yet implemented"
        case .parsingFailed:
            return "Failed to parse asset data"
        }
    }
}
