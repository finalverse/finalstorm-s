//
//  Services/Audio/SpatialAudioEngine.swift
//  FinalStorm
//
//  Core spatial audio engine - fixed version with proper method signatures
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
    private weak var listenerEntity: Entity?
    
    // Audio processing chain
    private var reverbNode: AVAudioUnitReverb
    private var eqNode: AVAudioUnitEQ
    private var distortionNode: AVAudioUnitDistortion
    private var limiterNode: AVAudioUnitDistortion
    
    // Performance monitoring
    private var performanceMetrics = AudioPerformanceMetrics()
    private var occlusionCalculator: AudioOcclusionCalculator?
    
    // MARK: - Initialization
    init() {
        self.audioEngine = AVAudioEngine()
        self.spatialMixer = AVAudioEnvironmentNode()
        self.mixerNode = AVAudioMixerNode()
        self.reverbNode = AVAudioUnitReverb()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 10)
        self.distortionNode = AVAudioUnitDistortion()
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
        audioEngine.attach(distortionNode)
        audioEngine.attach(limiterNode)
        
        // Create processing chain
        audioEngine.connect(spatialMixer, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: distortionNode, format: nil)
        audioEngine.connect(distortionNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: limiterNode, format: nil)
        audioEngine.connect(limiterNode, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: nil)
        
        setupEqualizer()
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
        spatialMixer.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        spatialMixer.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
        
        spatialMixer.renderingAlgorithm = .auto
        spatialMixer.sourceMode = .spatializeIfMono
        spatialMixer.pointSourceInHeadMode = .bypass
        
        reverbNode.loadFactoryPreset(.cathedral)
        reverbNode.wetDryMix = 30
        
        // Fixed: Use valid preset
        distortionNode.loadFactoryPreset(.drumsBitBrush)
        distortionNode.wetDryMix = 100
        
        limiterNode.loadFactoryPreset(.dramaBroken)
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
        
        Task {
            let duration = source.estimatedDuration
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
        
        updateAudioOcclusion()
    }
    
    // MARK: - Environmental Audio - Single definition
    func updateEnvironmentalEffects(for environment: EnvironmentType) {
        reverbNode.loadFactoryPreset(environment.reverbPreset)
        reverbNode.wetDryMix = environment.wetDryMix
        
        switch environment {
        case .underwater:
            setEQBand(frequency: 8000, gain: -12.0)
            setEQBand(frequency: 4000, gain: -8.0)
            setEQBand(frequency: 500, gain: 3.0)
            
        case .cave:
            setEQBand(frequency: 16000, gain: -3.0)
            setEQBand(frequency: 8000, gain: -2.0)
            
        case .magical:
            setEQBand(frequency: 2000, gain: 2.0)
            setEQBand(frequency: 8000, gain: 4.0)
            
        case .corrupted:
            setEQBand(frequency: 1000, gain: -3.0)
            setEQBand(frequency: 4000, gain: 6.0)
            distortionNode.wetDryMix = 80
            
        default:
            resetEqualizer()
            distortionNode.wetDryMix = 50
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
    
    // MARK: - Audio Processing
    func applyAudioFilter(_ filter: AudioFilter, to category: AudioCategory? = nil) {
        switch filter {
        case .lowPass(let frequency, let resonance):
            applyLowPassFilter(frequency: frequency, resonance: resonance)
            
        case .highPass(let frequency, let resonance):
            applyHighPassFilter(frequency: frequency, resonance: resonance)
            
        case .reverb(let preset, let wetDryMix):
            reverbNode.loadFactoryPreset(preset)
            reverbNode.wetDryMix = wetDryMix
            
        case .distortion(let preGain, let wetDryMix):
            distortionNode.preGain = preGain
            distortionNode.wetDryMix = wetDryMix
            
        default:
            break
        }
    }
    
    private func applyLowPassFilter(frequency: Float, resonance: Float) {
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
    
    private func applyHighPassFilter(frequency: Float, resonance: Float) {
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
    
    // MARK: - Audio Occlusion
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
    
    // MARK: - Performance Monitoring
    func getPerformanceMetrics() -> AudioPerformanceMetrics {
        // Fixed: Use estimated CPU usage instead of unavailable property
        performanceMetrics.cpuUsage = Float(audioSources.count) / 50.0 // Estimated based on source count
        performanceMetrics.memoryUsage = getAudioMemoryUsage()
        return performanceMetrics
    }
    
    private func getAudioMemoryUsage() -> Float {
        return Float(audioSources.count) * 0.1
    }
    
    // MARK: - Quality Settings
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        qualitySettings = settings
        
        for source in audioSources.values {
            source.updateQualitySettings(settings)
        }
    }
    
    func enableSpatialAudio(_ enabled: Bool) {
        spatialMixer.sourceMode = enabled ? .spatializeIfMono : .bypass
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
    
    // Fixed: Use estimated duration instead of unavailable property
    var estimatedDuration: TimeInterval {
        return 3.0 // Default estimated duration
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
                playerNode = AVAudioPlayerNode()
                guard let player = playerNode else { return }
                
                audioFile = try await loadAudioFile()
                
                audioEngine.attach(player)
                
                if spatialization.usesSpatialProcessing {
                    audioEngine.connect(player, to: spatialMixer, format: audioFile?.processingFormat)
                } else {
                    audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFile?.processingFormat)
                }
                
                updatePosition(position)
                
            } catch {
                print("Failed to setup audio player: \(error)")
            }
        }
    }
    
    private func loadAudioFile() async throws -> AVAudioFile {
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
    }
    
    func setSpatialization(_ spatialization: AudioSpatialization) {
        self.spatialization = spatialization
        
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
        
        if let occlusion = occlusionData {
            finalVolume *= occlusion.attenuatedVolume
        }
        
        playerNode?.volume = finalVolume
    }
    
    func setOcclusion(_ occlusionData: AudioOcclusionData) {
        self.occlusionData = occlusionData
        updateVolume()
    }
    
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        qualitySettings = settings
    }
    
    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("\(id.uuidString).wav")
    }
    
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
        return .air
    }
    
    private func rayIntersectsMesh(_ ray: Ray, _ mesh: CollisionMesh) -> (hit: Bool, material: MaterialType)? {
        if mesh.boundingBox.contains(ray.origin) {
            return (hit: true, material: mesh.materialType)
        }
        return nil
    }
}
