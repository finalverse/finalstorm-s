# Core/Graphics

The **Core/Graphics** module is FinalStorm's high-level graphics management system, providing sophisticated mesh loading, material management, and procedural generation capabilities. This module serves as the bridge between game content and the low-level rendering pipeline.

## Architecture Overview

The graphics system follows a modular, cache-first architecture designed for performance and scalability. It handles asset loading, mesh generation, and material management while providing intelligent caching and optimization.

```
Core/Graphics/
├── GraphicsTypes.swift           # Foundation types and configurations
├── MeshSystem.swift             # Main mesh management system (enhanced)
├── MeshCache.swift              # Advanced multi-tier caching system
├── LODManager.swift             # Level-of-Detail management
├── ProceduralMeshGenerator.swift # Advanced procedural generation
├── AssetLoader.swift            # Multi-format asset loading
├── MeshPerformanceMonitor.swift # Performance monitoring and analytics
├── MaterialSystem.swift         # Material management (planned)
└── TextureManager.swift         # Texture loading and management (planned)
```

## Key Features

### 🎯 Intelligent Asset Management
- **Multi-Format Support**: USDZ, USD, OBJ, GLTF, FBX with automatic detection
- **Smart Caching**: Multi-tier caching with LRU eviction and priority levels
- **Automatic Fallbacks**: Procedural generation when assets fail to load
- **Hot-Reloading**: Live asset updates during development

### 🔄 Advanced Level-of-Detail (LOD)
- **Automatic LOD Generation**: Dynamic mesh simplification based on distance
- **Quality Scaling**: Adaptive LOD based on performance requirements
- **Cache Integration**: LOD meshes are cached for optimal performance
- **Real-time Switching**: Seamless LOD transitions during gameplay

### 🛠 Procedural Generation
- **Rich Shape Library**: Cubes, spheres, terrain, avatars, trees, buildings
- **Finalverse Specialization**: Harmony blossoms, crystals, corruption effects
- **Quality Adaptation**: Generation complexity scales with performance settings
- **Parameter-Driven**: Highly customizable procedural generation

### ⚡ Performance Optimization
- **Memory Management**: Intelligent cache sizing and cleanup
- **Async Loading**: Non-blocking asset loading with proper task management
- **Performance Monitoring**: Comprehensive metrics and profiling
- **Resource Pooling**: Efficient memory usage patterns

## Core Components

### MeshSystem

The central hub for all mesh operations:

```swift
@MainActor
class MeshSystem: ObservableObject {
    func loadMesh(named name: String, from bundle: Bundle, lodLevel: Int?) async throws -> MeshResource
    func loadMesh(from url: URL, lodLevel: Int?) async throws -> MeshResource
    func generateMesh(type: ProceduralMeshType, parameters: [String: Any]) async -> MeshResource
}
```

**Key Features:**
- Unified interface for all mesh operations
- Automatic caching and optimization
- Performance monitoring integration
- Quality-adaptive loading

### MeshCache

Advanced multi-tier caching system:

```swift
class MeshCache {
    func getMesh(for key: String) -> MeshResource?
    func storeMesh(_ mesh: MeshResource, for key: String, priority: CachePriority)
    func optimizeMemory(targetSize: Int) async
}
```

**Cache Levels:**
- **Primary Cache**: Recently accessed meshes
- **LOD Cache**: Level-of-detail variations
- **Priority System**: Critical, high, normal, low priority levels
- **Memory Management**: Automatic cleanup and optimization

### LODManager

Intelligent Level-of-Detail management:

```swift
class LODManager {
    func generateLOD(from baseMesh: MeshResource, level: Int) async throws -> MeshResource
    func selectLODLevel(distance: Float, meshBounds: BoundingBox) -> Int
    func generateLODChain(from baseMesh: MeshResource) async throws -> [MeshResource]
}
```

**LOD Features:**
- **Automatic Generation**: Mesh simplification algorithms
- **Distance-Based Selection**: Optimal LOD for viewing distance
- **Quality Scaling**: Adapts to performance requirements
- **Seamless Transitions**: Smooth LOD switching

### ProceduralMeshGenerator

Advanced procedural content generation:

```swift
class ProceduralMeshGenerator {
    func generateMesh(type: ProceduralMeshType, parameters: [String: Any]) async -> MeshResource
}
```

**Supported Types:**
- **Basic Shapes**: Cubes, spheres, cylinders, planes
- **Characters**: Avatar base meshes with customization
- **Environment**: Trees, rocks, buildings, terrain
- **Finalverse**: Harmony blossoms, crystals, corruption nodes

### AssetLoader

Multi-format asset loading system:

```swift
class AssetLoader {
    func loadMesh(from url: URL, format: MeshFormat, lodLevel: Int?) async throws -> MeshResource
    func detectFormat(from url: URL) -> MeshFormat
}
```

**Supported Formats:**
- **USDZ/USD**: Native RealityKit support with full features
- **OBJ**: Custom parser with material support
- **GLTF**: Modern 3D format (planned)
- **FBX**: Industry standard (planned)

## Mesh Types and Generation

### Basic Geometric Shapes

```swift
// Generate a customized sphere
let sphere = await meshSystem.generateMesh(
    type: .sphere,
    parameters: [
        "radius": 2.0,
        "segments": 32
    ]
)

// Generate a procedural terrain
let terrain = await meshSystem.generateMesh(
    type: .terrain,
    parameters: [
        "size": 128,
        "height": 20.0,
        "seed": 12345
    ]
)
```

### Finalverse-Specific Content

```swift
// Generate a harmony blossom
let blossom = await meshSystem.generateMesh(
    type: .harmonyBlossom,
    parameters: [
        "petalCount": 8,
        "size": 0.5,
        "harmonyLevel": 0.8
    ]
)

// Generate a corruption crystal
let crystal = await meshSystem.generateMesh(
    type: .crystal,
    parameters: [
        "height": 2.0,
        "sides": 6,
        "corruptionLevel": 0.3
    ]
)
```

### Avatar Generation

```swift
// Create an avatar mesh
let avatarMesh = try await meshSystem.createAvatarMesh(
    for: AvatarAppearance(
        bodyShape: .songweaver,
        height: 1.8,
        clothingStyle: .robes
    )
)
```

## Performance and Optimization

### Cache Management

The system provides sophisticated cache management:

```swift
// Get cache statistics
let stats = meshCache.getCacheStatistics()
print("Cache hit rate: \(stats.hitRate * 100)%")
print("Memory usage: \(stats.memoryUsage) bytes")

// Optimize cache for target memory usage
await meshSystem.optimizeMemoryUsage() // 256MB default target

// Clear cache if needed
meshSystem.clearCache()
```

### Performance Monitoring

Comprehensive performance tracking:

```swift
struct PerformanceReport {
    let cacheHitRate: Float
    let averageLoadTime: TimeInterval
    let maxLoadTime: TimeInterval
    let memoryUsage: Int
    let totalSamples: Int
}

let report = meshPerformanceMonitor.generateReport()
print(report.formattedReport)
```

### Quality Scaling

Automatic quality adaptation:

```swift
// Set quality level
meshSystem.setQualityLevel(.high)

// Get recommended quality based on performance
let recommendedQuality = meshSystem.getRecommendedQuality()
meshSystem.setQualityLevel(recommendedQuality)
```

## Asset Loading Workflow

### Loading from Bundle

```swift
// Load mesh with automatic format detection
let mesh = try await meshSystem.loadMesh(named: "character", from: .main)

// Load with specific LOD level
let lodMesh = try await meshSystem.loadMesh(
    named: "environment", 
    from: .main, 
    lodLevel: 2
)

// Load complete LOD chain
let lodChain = try await meshSystem.loadMeshWithLOD(named: "building", from: .main)
```

### Loading from URL

```swift
// Load from remote URL
let url = URL(string: "https://assets.finalverse.com/models/harmony_tree.usdz")!
let remoteMesh = try await meshSystem.loadMesh(from: url)

// Load with format specification
let objMesh = try await assetLoader.loadMesh(
    from: localURL, 
    format: .obj, 
    lodLevel: nil
)
```

### Preloading Assets

```swift
// Preload commonly used assets
let assetNames = ["character", "tree", "rock", "building"]
await meshSystem.preloadAssets(assetNames, from: .main)
```

## Terrain Generation

### Heightmap-Based Terrain

```swift
// Generate terrain from heightmap
let heightmap: [[Float]] = generateHeightmapData()
let terrainMesh = try await meshSystem.createTerrainMesh(
    from: heightmap,
    features: TerrainFeatures(
        enableNormals: true,
        enableTextures: true,
        enableLOD: true
    )
)
```

### Procedural Terrain

```swift
// Generate procedural terrain
let proceduralTerrain = await meshSystem.generateMesh(
    type: .terrain,
    parameters: [
        "size": 256,
        "height": 50.0,
        "octaves": 6,
        "frequency": 0.01,
        "seed": worldSeed
    ]
)
```

## Error Handling and Fallbacks

### Graceful Degradation

```swift
// The system automatically provides fallbacks
do {
    let mesh = try await meshSystem.loadMesh(named: "complex_model")
} catch {
    // System automatically generates procedural fallback
    print("Using procedural fallback for failed asset load")
}
```

### Asset Validation

```swift
// Validate assets during development
let validationResults = await assetLoader.validateAssets(in: .main)
for (asset, result) in validationResults {
    if !result.isValid {
        print("Asset '\(asset)' has issues: \(result.errors)")
    }
}
```

## Configuration

### Graphics Configuration

```swift
struct GraphicsConfiguration {
    var renderingPipeline: RenderingPipeline = .adaptive
    var qualityLevel: QualityLevel = .high
    var meshLODSettings: MeshLODSettings = MeshLODSettings()
    var enableCaching: Bool = true
    var maxCacheSize: Int = 256 * 1024 * 1024 // 256MB
}
```

### LOD Settings

```swift
struct MeshLODSettings {
    var enableLOD: Bool = true
    var lodDistances: [Float] = [50, 100, 200, 500]
    var lodBias: Float = 1.0
    var maxLODLevel: Int = 4
}
```

## Integration Examples

### World System Integration

```swift
// Generate terrain patch for world grid
let terrainPatch = try await terrainGenerator.generateTerrain(
    for: coordinate,
    worldMetabolism: worldMetabolism,
    playerPosition: playerPosition
)

// Create mesh from terrain data
let terrainMesh = try await meshSystem.createTerrainMesh(
    from: terrainPatch.heightmap,
    features: TerrainFeatures()
)
```

### Avatar System Integration

```swift
// Create customized avatar
let avatarAppearance = AvatarAppearance(
    bodyShape: .humanoid,
    height: 1.75,
    skinColor: SIMD4<Float>(0.9, 0.8, 0.7, 1.0),
    clothingStyle: .casual
)

let avatarMesh = try await meshSystem.createAvatarMesh(for: avatarAppearance)
```

## Thread Safety

All mesh operations are designed to be thread-safe:
- `@MainActor` for UI-related operations
- Internal queues for cache management
- Proper synchronization for concurrent access
- Async/await for non-blocking operations

## Memory Management

### Cache Optimization

```swift
// Automatic memory pressure handling
if systemMemoryPressure > threshold {
    await meshSystem.optimizeMemoryUsage()
}

// Manual cache management
meshSystem.clearCache() // Clear all cached meshes
meshCache.optimizeMemory(targetSize: 128 * 1024 * 1024) // 128MB target
```

### Resource Monitoring

```swift
// Monitor resource usage
let stats = meshSystem.getResourceUsage()
print("Active meshes: \(stats.activeMeshes)")
print("Cache memory: \(stats.cacheMemoryUsage)")
print("Hit rate: \(stats.cacheHitRate)")
```

## Development Tools

### Debug Visualization

```swift
// Enable debug mode for mesh loading
meshSystem.setDebugMode(true)

// Visualize mesh bounds
meshSystem.setShowBoundingBoxes(true)

// Monitor performance in real-time
let monitor = meshSystem.performanceMonitor
print("Average load time: \(monitor.averageLoadTime)ms")
```

### Asset Pipeline Integration

```swift
// Validate asset pipeline
let pipelineStatus = await meshSystem.validateAssetPipeline()
if !pipelineStatus.isValid {
    print("Asset pipeline issues: \(pipelineStatus.issues)")
}
```

## Best Practices

### Performance Optimization

1. **Preload Common Assets**: Load frequently used meshes at startup
2. **Use LOD Appropriately**: Enable LOD for distant or small objects
3. **Monitor Cache Performance**: Keep cache hit rate above 80%
4. **Profile Regularly**: Use performance monitoring to identify bottlenecks

### Memory Management

1. **Set Appropriate Cache Limits**: Balance memory usage vs. performance
2. **Clean Up Unused Assets**: Periodically optimize cache
3. **Use Procedural Generation**: For simple shapes, generation can be faster than loading

### Asset Organization

1. **Consistent Naming**: Use clear, descriptive asset names
2. **Proper Format Selection**: USDZ for complex models, OBJ for simple geometry
3. **LOD Planning**: Design assets with LOD in mind
4. **Validation**: Regularly validate asset integrity

---

*The Core/Graphics module provides the foundation for FinalStorm's stunning visual experiences, combining performance, quality, and ease of use in a world-class graphics management system.*
