//
//  Services/Audio/SpatialAudioEngine.swift
//  FinalStorm
//
//  Enhanced spatial audio engine with latest AVFoundation features
//  Platform-agnostic with proper iOS/macOS/visionOS support
//

import Foundation
import AVFoundation
import RealityKit
import Combine

@MainActor
class SpatialAudioEngine: ObservableObject {
    // MARK: - Properties
    @Published var isEnabled: Bool = true
    @Published var masterVolume: Float = 1.0
    @Published var categoryVolumes: [AudioCategory: Float] = [:]
    @Published var qualitySettings: AudioQualitySettings = .high
    
    private let audioEngine: AVAudioEngine
    private let spatialMixer: AVAudioEnvironmentNode
    private let mixerNode: AVAudioMixerNode
    private var effectNodes: [AudioNodeType: AVAudioNode] = [:]
    private var audioSources: [UUID: SpatialAudioSource] = [:]
    private var listenerEntity: Entity?
    
    // Audio processing chain
    private var reverbNode: AVAudioUnitReverb
    private var eqNode: AVAudioUnitEQ
    private var compressorNode: AVAudioUnitDistortion // Using distortion as compressor placeholder
    private var limiterNode: AVAudioUnitDistortion
    
    // Performance monitoring
    private var performanceMetrics = AudioPerformanceMetrics()
    
    // MARK: - Initialization
    init() {
        self.audioEngine = AVAudioEngine()
        self.spatialMixer = AVAudioEnvironmentNode()
        self.mixerNode = AVAudioMixerNode()
        self.reverbNode = AVAudioUnitReverb()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 10)
        self.compressorNode = AVAudioUnitDistortion()
        self.limiterNode = AVAudioUnitDistortion()
        
        // Initialize category volumes
        for category in AudioCategory.allCases {
            categoryVolumes[category] = category.defaultVolume
        }
        
        setupAudioEngine()
        setupSpatialAudio()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if os(iOS) || os(visionOS)
        do {
            try AVAudioSession.configureFinalverseSession()
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
        
        #if os(macOS)
        // macOS doesn't use AVAudioSession, configure directly
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine on macOS: \(error)")
        }
        #endif
    }
    
    private func setupAudioEngine() {
        // Attach all nodes
        audioEngine.attach(spatialMixer)
        audioEngine.attach(mixerNode)
        audioEngine.attach(reverbNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(compressorNode)
        audioEngine.attach(limiterNode)
        
        // Create processing chain: spatial -> eq -> compressor -> reverb -> limiter -> output
        audioEngine.connect(spatialMixer, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: compressorNode, format: nil)
        audioEngine.connect(compressorNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: limiterNode, format: nil)
        audioEngine.connect(limiterNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Configure main mixer
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Setup EQ bands for environmental effects
        setupEqualizer()
        
        // Start engine
        startAudioEngine()
    }
    
    private func setupEqualizer() {
        let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        
        for (index, frequency) in frequencies.enumerated() {
            if index < eqNode.bands.count {
                let band = eqNode.bands[index]
                band.frequency = frequency
                band.gain = 0.0
                band.bandwidth = 0.5
                band.bypass = false
                
                if index == 0 {
                    band.filterType = .highPass
                } else if index == frequencies.count - 1 {
                    band.filterType = .lowPass
                } else {
                    band.filterType = .parametric
                }
            }
        }
    }
    
    private func startAudioEngine() {
        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func setupSpatialAudio() {
        // Configure spatial mixer with latest features
        spatialMixer.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        spatialMixer.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
        
        // Use highest quality spatial rendering
        spatialMixer.renderingAlgorithm = .auto // Let system choose best
        spatialMixer.sourceMode = .spatializeIfMono
        spatialMixer.pointSourceInHeadMode = .bypass
        
        // Configure reverb for environmental effects
        reverbNode.loadFactoryPreset(.cathedral)
        reverbNode.wetDryMix = 30
        
        // Setup compressor for dynamic range control
        compressorNode.loadFactoryPreset(.speechEqualizer)
        compressorNode.wetDryMix = 100
        
        // Setup limiter for protecting speakers
        limiterNode.loadFactoryPreset(.drumsBitBrush)
        limiterNode.wetDryMix = 50
    }
    
    // MARK: - Audio Source Management
    func createAudioSource(
        id: UUID,
        position: SIMD3<Float>,
        audioResource: AudioFileResource,
        category: AudioCategory = .effects,
        volume: Float = 1.0,
        loop: Bool = false
    ) -> SpatialAudioSource {
        let source = SpatialAudioSource(
            id: id,
            position: position,
            audioResource: audioResource,
            category: category,
            volume: volume,
            loop: loop,
            audioEngine: audioEngine,
            spatialMixer: spatialMixer,
            qualitySettings: qualitySettings
        )
        
        audioSources[id] = source
        performanceMetrics.activeSources += 1
        
        return source
    }
    
    func removeAudioSource(_ id: UUID) {
        if let source = audioSources[id] {
            source.stop()
            audioSources.removeValue(forKey: id)
            performanceMetrics.activeSources -= 1
        }
    }
    
    func updateSourcePosition(_ id: UUID, position: SIMD3<Float>) {
        audioSources[id]?.updatePosition(position)
    }
    
    func playSound(
        at position: SIMD3<Float>,
        audioResource: AudioFileResource,
        category: AudioCategory = .effects,
        volume: Float = 1.0,
        spatialization: AudioSpatialization = .positional(radius: 10.0)
    ) {
        let id = UUID()
        let source = createAudioSource(
            id: id,
            position: position,
            audioResource: audioResource,
            category: category,
            volume: volume,
            loop: false
        )
        
        source.setSpatialization(spatialization)
        source.play()
        
        // Auto-remove after playback
        Task {
            let duration = source.duration
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            removeAudioSource(id)
        }
    }
    
    // MARK: - Listener Management
    func setListener(_ entity: Entity) {
        listenerEntity = entity
        updateListenerPosition()
    }
    
    func updateListenerPosition() {
        guard let listener = listenerEntity else { return }
        
        let position = listener.position
        let forward = listener.convert(direction: [0, 0, -1], to: nil)
        let up = listener.convert(direction: [0, 1, 0], to: nil)
        
        spatialMixer.listenerPosition = AVAudio3DPoint(
            x: position.x,
            y: position.y,
            z: position.z
        )
        
        spatialMixer.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z)
        )
        
        // Update all sources for potential occlusion changes
        updateAudioOcclusion()
    }
    
    // MARK: - Environmental Audio
    func setEnvironmentalReverb(_ preset: AVAudioUnitReverbPreset) {
        reverbNode.loadFactoryPreset(preset)
    }
    
    func updateEnvironmentalEffects(for environment: EnvironmentType) {
        reverbNode.loadFactoryPreset(environment.reverbPreset)
        reverbNode.wetDryMix = environment.wetDryMix
        
        // Adjust EQ based on environment
        switch environment {
        case .underwater:
            // Cut high frequencies, boost low-mids
            setEQBand(frequency: 8000, gain: -12.0)
            setEQBand(frequency: 4000, gain: -8.0)
            setEQBand(frequency: 500, gain: 3.0)
            
        case .cave:
            // Emphasize reverb, slight high cut
            setEQBand(frequency: 16000, gain: -3.0)
            setEQBand(frequency: 8000, gain: -2.0)
            
        case .magical:
            // Enhance presence, add sparkle
            setEQBand(frequency: 2000, gain: 2.0)
            setEQBand(frequency: 8000, gain: 4.0)
            
        case .corrupted:
            // Distorted, unsettling
            setEQBand(frequency: 1000, gain: -3.0)
            setEQBand(frequency: 4000, gain: 6.0)
            compressorNode.wetDryMix = 80
            
        default:
            // Reset to flat response
            resetEqualizer()
            compressorNode.wetDryMix = 50
        }
    }
    
    private func setEQBand(frequency: Float, gain: Float) {
        for band in eqNode.bands {
            if abs(band.frequency - frequency) < 100 {
                band.gain = gain
                break
            }
        }
    }
    
    private func resetEqualizer() {
        for band in eqNode.bands {
            band.gain = 0.0
        }
    }
    
    // MARK: - Audio Occlusion with Enhanced Ray Tracing
    private var occlusionCalculator: AudioOcclusionCalculator?
    
    func setOcclusionCalculator(_ calculator: AudioOcclusionCalculator) {
        occlusionCalculator = calculator
    }
    
    func updateAudioOcclusion() {
        guard let listener = listenerEntity,
              let calculator = occlusionCalculator else { return }
        
        let listenerPosition = listener.position
        
        for source in audioSources.values {
            let occlusionData = calculator.calculateOcclusion(
                from: source.position,
                to: listenerPosition
            )
            source.setOcclusion(occlusionData)
        }
    }
    
    // MARK: - Advanced Audio Processing
    func applyAudioFilter(_ filter: AudioFilter, to category: AudioCategory? = nil) {
        switch filter {
        case .lowPass(let frequency, let resonance):
            applyLowPassFilter(frequency: frequency, resonance: resonance, category: category)
            
        case .highPass(let frequency, let resonance):
            applyHighPassFilter(frequency: frequency, resonance: resonance, category: category)
            
        case .bandPass(let frequency, let bandwidth):
            applyBandPassFilter(frequency: frequency, bandwidth: bandwidth, category: category)
            
        case .echo(let delay, let feedback, let wetDryMix):
            applyEchoEffect(delay: delay, feedback: feedback, wetDryMix: wetDryMix)
            
        case .reverb(let preset, let wetDryMix):
            reverbNode.loadFactoryPreset(preset)
            reverbNode.wetDryMix = wetDryMix
            
        case .distortion(let preGain, let wetDryMix):
            compressorNode.preGain = preGain
            compressorNode.wetDryMix = wetDryMix
            
        case .chorus(let rate, let depth, let feedback, let wetDryMix):
            applyChorusEffect(rate: rate, depth: depth, feedback: feedback, wetDryMix: wetDryMix)
            
        case .compressor(let threshold, let ratio, let attack, let release):
            applyCompression(threshold: threshold, ratio: ratio, attack: attack, release: release)
        }
    }
    
    private func applyLowPassFilter(frequency: Float, resonance: Float, category: AudioCategory?) {
        // Find appropriate EQ band
        for band in eqNode.bands {
            if band.frequency >= frequency {
                band.filterType = .lowPass
                band.frequency = frequency
                band.bandwidth = resonance
                band.bypass = false
                break
            }
        }
    }
    
    private func applyHighPassFilter(frequency: Float, resonance: Float, category: AudioCategory?) {
        // Find appropriate EQ band
        for band in eqNode.bands {
            if band.frequency <= frequency {
                band.filterType = .highPass
                band.frequency = frequency
                band.bandwidth = resonance
                band.bypass = false
                break
            }
        }
    }
    
    private func applyBandPassFilter(frequency: Float, bandwidth: Float, category: AudioCategory?) {
        // Find closest EQ band
        var closestBand: AVAudioUnitEQFilterParameters?
        var closestDistance: Float = Float.greatestFiniteMagnitude
        
        for band in eqNode.bands {
            let distance = abs(band.frequency - frequency)
            if distance < closestDistance {
                closestDistance = distance
                closestBand = band
            }
        }
        
        closestBand?.filterType = .bandPass
        closestBand?.frequency = frequency
        closestBand?.bandwidth = bandwidth
        closestBand?.bypass = false
    }
    
    private func applyEchoEffect(delay: TimeInterval, feedback: Float, wetDryMix: Float) {
        // Create delay effect using AVAudioUnitDelay
        let delayNode = AVAudioUnitDelay()
        delayNode.delayTime = delay
        delayNode.feedback = feedback
        delayNode.wetDryMix = wetDryMix
        
        // Insert into chain if not already present
        if effectNodes[.delay] == nil {
            audioEngine.attach(delayNode)
            audioEngine.connect(delayNode, to: reverbNode, format: nil)
            audioEngine.connect(compressorNode, to: delayNode, format: nil)
            effectNodes[.delay] = delayNode
        }
    }
    
    private func applyChorusEffect(rate: Float, depth: Float, feedback: Float, wetDryMix: Float) {
        // Simplified chorus using multiple delayed signals
        // In a full implementation, this would use proper chorus algorithms
        print("Applying chorus effect: rate=\(rate), depth=\(depth), feedback=\(feedback), wetDryMix=\(wetDryMix)")
    }
    
    private func applyCompression(threshold: Float, ratio: Float, attack: TimeInterval, release: TimeInterval) {
        // Use distortion node as a simplified compressor
        compressorNode.preGain = threshold
        compressorNode.wetDryMix = min(100, ratio * 10)
    }
    
    // MARK: - Volume Control
    func setMasterVolume(_ volume: Float) {
        masterVolume = volume
        audioEngine.mainMixerNode.outputVolume = volume
    }
    
    func setCategoryVolume(_ category: AudioCategory, volume: Float) {
        categoryVolumes[category] = volume
        updateSourceVolumes(for: category)
    }
    
    private func updateSourceVolumes(for category: AudioCategory) {
        for source in audioSources.values {
            if source.category == category {
                source.updateVolume()
            }
        }
    }
    
    func getCategoryVolume(_ category: AudioCategory) -> Float {
        return categoryVolumes[category] ?? category.defaultVolume
    }
    
    // MARK: - Performance Monitoring
    func getPerformanceMetrics() -> AudioPerformanceMetrics {
        performanceMetrics.cpuUsage = audioEngine.mainMixerNode.auAudioUnit.cpuLoad
        performanceMetrics.memoryUsage = getAudioMemoryUsage()
        return performanceMetrics
    }
    
    private func getAudioMemoryUsage() -> Float {
        // Simplified memory usage calculation
        return Float(audioSources.count) * 0.1 // MB per source
    }
    
    // MARK: - Quality Settings
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        qualitySettings = settings
        
        // Apply new settings to audio engine
        if let format = AVAudioFormat.finalverseFormat(settings: settings) {
            // Update engine format if possible
            // Note: In practice, changing format requires restarting the engine
        }
        
        // Update all sources with new quality settings
        for source in audioSources.values {
            source.updateQualitySettings(settings)
        }
    }
    
    // MARK: - Advanced Features
    func enableSpatialAudio(_ enabled: Bool) {
        spatialMixer.sourceMode = enabled ? .spatializeIfMono : .bypass
    }
    
    func setListenerOrientation(forward: SIMD3<Float>, up: SIMD3<Float>) {
        spatialMixer.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z)
        )
    }
    
    func createAudioGroup(sources: [UUID]) -> AudioGroup {
        let groupId = UUID()
        let group = AudioGroup(id: groupId, sourceIds: sources)
        return group
    }
    
    // MARK: - Cleanup
    func shutdown() {
        for source in audioSources.values {
            source.stop()
        }
        audioSources.removeAll()
        
        audioEngine.stop()
        performanceMetrics.reset()
    }
    
    deinit {
        shutdown()
    }
 }

 // MARK: - Enhanced SpatialAudioSource
 class SpatialAudioSource {
    let id: UUID
    var position: SIMD3<Float>
    let audioResource: AudioFileResource
    let category: AudioCategory
    var volume: Float
    let loop: Bool
    
    private let audioEngine: AVAudioEngine
    private let spatialMixer: AVAudioEnvironmentNode
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private var qualitySettings: AudioQualitySettings
    private var spatialization: AudioSpatialization = .positional(radius: 10.0)
    private var occlusionData: AudioOcclusionData?
    
    var duration: TimeInterval {
        return audioFile?.duration ?? 0
    }
    
    var isPlaying: Bool {
        return playerNode?.isPlaying ?? false
    }
    
    init(
        id: UUID,
        position: SIMD3<Float>,
        audioResource: AudioFileResource,
        category: AudioCategory,
        volume: Float,
        loop: Bool,
        audioEngine: AVAudioEngine,
        spatialMixer: AVAudioEnvironmentNode,
        qualitySettings: AudioQualitySettings
    ) {
        self.id = id
        self.position = position
        self.audioResource = audioResource
        self.category = category
        self.volume = volume
        self.loop = loop
        self.audioEngine = audioEngine
        self.spatialMixer = spatialMixer
        self.qualitySettings = qualitySettings
        
        setupAudioPlayer()
    }
    
    private func setupAudioPlayer() {
        Task {
            do {
                // Create player node
                playerNode = AVAudioPlayerNode()
                guard let player = playerNode else { return }
                
                // Load audio file from resource
                audioFile = try await loadAudioFile()
                
                // Attach and connect player
                audioEngine.attach(player)
                
                // Use appropriate connection based on spatialization
                if spatialization.usesSpatialProcessing {
                    audioEngine.connect(player, to: spatialMixer, format: audioFile?.processingFormat)
                } else {
                    // Connect directly to mixer for non-spatial audio
                    audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFile?.processingFormat)
                }
                
                // Set 3D position
                updatePosition(position)
                
            } catch {
                print("Failed to setup audio player: \(error)")
            }
        }
    }
    
    private func loadAudioFile() async throws -> AVAudioFile {
        // Convert AudioFileResource to AVAudioFile
        // This is a simplified approach - real implementation would handle various formats
        let tempURL = createTempFileURL()
        return try AVAudioFile(forReading: tempURL)
    }
    
    func play() {
        guard let player = playerNode,
              let file = audioFile else { return }
        
        if loop {
            scheduleLoopedPlayback(player: player, file: file)
        } else {
            player.scheduleFile(file, at: nil)
        }
        
        player.play()
    }
    
    private func scheduleLoopedPlayback(player: AVAudioPlayerNode, file: AVAudioFile) {
        player.scheduleFile(file, at: nil) { [weak self] in
            // Reschedule for looping
            if self?.loop == true && player.isPlaying {
                self?.scheduleLoopedPlayback(player: player, file: file)
            }
        }
    }
    
    func stop() {
        playerNode?.stop()
    }
    
    func pause() {
        playerNode?.pause()
    }
    
    func updatePosition(_ newPosition: SIMD3<Float>) {
        position = newPosition
        
        if spatialization.usesSpatialProcessing {
            playerNode?.position = AVAudio3DPoint(x: newPosition.x, y: newPosition.y, z: newPosition.z)
        }
        
        // Update spatialization-specific settings
        switch spatialization {
        case .directional(let direction, let cone):
            // Set directional parameters
            if let player = playerNode {
                player.position = AVAudio3DPoint(x: newPosition.x, y: newPosition.y, z: newPosition.z)
                // Note: AVAudioPlayerNode doesn't directly support cone settings
                // This would need custom implementation
            }
            
        case .positional(let radius):
            playerNode?.position = AVAudio3DPoint(x: newPosition.x, y: newPosition.y, z: newPosition.z)
            // Apply distance-based attenuation
            
        default:
            break
        }
    }
    
    func setSpatialization(_ spatialization: AudioSpatialization) {
        self.spatialization = spatialization
        
        // Reconnect player with appropriate spatialization
        if let player = playerNode {
            audioEngine.disconnectNodeOutput(player)
            
            if spatialization.usesSpatialProcessing {
                audioEngine.connect(player, to: spatialMixer, format: audioFile?.processingFormat)
            } else {
                audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFile?.processingFormat)
            }
        }
    }
    
    func updateVolume() {
        var finalVolume = volume
        
        // Apply occlusion if available
        if let occlusion = occlusionData {
            finalVolume *= occlusion.attenuatedVolume
        }
        
        playerNode?.volume = finalVolume
    }
    
    func setOcclusion(_ occlusionData: AudioOcclusionData) {
        self.occlusionData = occlusionData
        updateVolume()
        
        // Apply frequency filtering based on material
        applyOcclusionFiltering(occlusionData)
    }
    
    private func applyOcclusionFiltering(_ data: AudioOcclusionData) {
        // Apply low-pass filtering based on occlusion
        let cutoffFrequency = 20000 * (1.0 - data.occlusionFactor)
        
        // This would require inserting an EQ node for this specific source
        // Simplified for this example
    }
    
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        qualitySettings = settings
        // Apply new quality settings - may require recreating audio file
    }
    
    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("\(id.uuidString).wav")
    }
    
    // MARK: - Advanced Properties
    var baseVolume: Float {
        return volume
    }
    
    func setBaseVolume(_ volume: Float) {
        self.volume = volume
        updateVolume()
    }
    
    func setVolume(_ volume: Float) {
        self.volume = volume
        updateVolume()
    }
 }

 // MARK: - Audio Occlusion Calculator
 class AudioOcclusionCalculator {
    private var worldGeometry: [CollisionMesh] = []
    private let rayTracingQueue = DispatchQueue(label: "audio.occlusion", qos: .utility)
    
    func updateWorldGeometry(_ geometry: [CollisionMesh]) {
        rayTracingQueue.async {
            self.worldGeometry = geometry
        }
    }
    
    func calculateOcclusion(from sourcePosition: SIMD3<Float>, to listenerPosition: SIMD3<Float>) -> AudioOcclusionData {
        let distance = simd_distance(sourcePosition, listenerPosition)
        
        // Perform ray tracing for occlusion
        let occlusionFactor = performRayTracing(from: sourcePosition, to: listenerPosition)
        let materialType = getMaterialAtIntersection(from: sourcePosition, to: listenerPosition)
        
        return AudioOcclusionData(
            sourcePosition: sourcePosition,
            listenerPosition: listenerPosition,
            occlusionFactor: occlusionFactor,
            materialType: materialType,
            distance: distance
        )
    }
    
    private func performRayTracing(from source: SIMD3<Float>, to listener: SIMD3<Float>) -> Float {
        // Simplified ray tracing - in practice this would be more sophisticated
        let direction = normalize(listener - source)
        let ray = Ray(origin: source, direction: direction)
        
        var totalOcclusion: Float = 0.0
        
        for mesh in worldGeometry {
            if let intersection = rayIntersectsMesh(ray, mesh) {
                totalOcclusion += intersection.material.occlusionFactor
            }
        }
        
        return min(1.0, totalOcclusion)
    }
    
    private func getMaterialAtIntersection(from source: SIMD3<Float>, to listener: SIMD3<Float>) -> MaterialType {
        // Return the dominant material type along the ray path
        // Simplified to return air if no intersections
        return .air
    }
    
    private func rayIntersectsMesh(_ ray: Ray, _ mesh: CollisionMesh) -> (hit: Bool, material: MaterialType)? {
        // Simplified intersection test
        if mesh.boundingBox.contains(ray.origin) {
            return (hit: true, material: mesh.materialType)
        }
        return nil
    }
 }

 struct Ray {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
 }

 // MARK: - Audio Performance Metrics
 struct AudioPerformanceMetrics {
    var activeSources: Int = 0
    var cpuUsage: Float = 0.0
    var memoryUsage: Float = 0.0
    var dropouts: Int = 0
    var latency: TimeInterval = 0.0
    
    mutating func reset() {
        activeSources = 0
        cpuUsage = 0.0
        memoryUsage = 0.0
        dropouts = 0
        latency = 0.0
    }
 }

 // MARK: - Audio Group Management
 struct AudioGroup {
    let id: UUID
    let sourceIds: [UUID]
    var volume: Float = 1.0
    var enabled: Bool = true
    
    mutating func addSource(_ sourceId: UUID) {
        if !sourceIds.contains(sourceId) {
            // Note: This would need to be a var property to modify
        }
    }
    
    mutating func removeSource(_ sourceId: UUID) {
        // Note: This would need to be a var property to modify
    }
 }

 // MARK: - Extensions for SpatialAudioEngine
 extension SpatialAudioEngine {
    func updateListenerPosition(_ position: SIMD3<Float>) {
        spatialMixer.listenerPosition = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
    }
    
    func setEnvironmentalReverb(_ preset: AVAudioUnitReverbPreset) {
        reverbNode.loadFactoryPreset(preset)
    }
 }
    
        
