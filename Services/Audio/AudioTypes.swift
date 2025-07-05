//
//  Services/Audio/AudioTypes.swift
//  FinalStorm
//
//  Audio-specific types for the Finalverse audio system
//  Platform-agnostic audio definitions with latest AVFoundation support
//  NOTE: This file imports types from other component files to avoid duplication
//

import Foundation
import AVFoundation
import RealityKit
import simd

// MARK: - Audio Category System

enum AudioCategory: String, CaseIterable, Codable {
    case music = "Music"
    case effects = "Effects"
    case environment = "Environment"
    case voice = "Voice"
    case ui = "UI"
    case songweaving = "Songweaving"
    
    var priority: Int {
        switch self {
        case .voice: return 100
        case .songweaving: return 90
        case .ui: return 80
        case .effects: return 70
        case .environment: return 50
        case .music: return 40
        }
    }
    
    var defaultVolume: Float {
        switch self {
        case .music: return 0.6
        case .effects: return 0.8
        case .environment: return 0.7
        case .voice: return 1.0
        case .ui: return 0.9
        case .songweaving: return 0.8
        }
    }
    
    var nodeTag: Int {
        switch self {
        case .music: return 1000
        case .effects: return 1001
        case .environment: return 1002
        case .voice: return 1003
        case .ui: return 1004
        case .songweaving: return 1005
        }
    }
}

extension AudioCategory: Comparable {
    public static func < (lhs: AudioCategory, rhs: AudioCategory) -> Bool {
        return lhs.priority < rhs.priority
    }
}

// MARK: - Audio Environment Processing

enum EnvironmentType: String, CaseIterable, Codable {
    case outdoor = "Outdoor"
    case indoor = "Indoor"
    case cave = "Cave"
    case underwater = "Underwater"
    case magical = "Magical"
    case corrupted = "Corrupted"
    case void = "Void"
    
    var reverbPreset: AVAudioUnitReverbPreset {
        switch self {
        case .outdoor: return .mediumHall
        case .indoor: return .mediumRoom
        case .cave: return .cathedral
        case .underwater: return .plate
        case .magical: return .largeHall2
        case .corrupted: return .largeRoom
        case .void: return .plate
        }
    }
    
    var wetDryMix: Float {
        switch self {
        case .outdoor: return 10
        case .indoor: return 25
        case .cave: return 60
        case .underwater: return 80
        case .magical: return 40
        case .corrupted: return 50
        case .void: return 90
        }
    }
    
    /// Map biome types to audio environment types
    static func from(biome: BiomeType) -> EnvironmentType {
        switch biome {
        case .grassland, .desert, .tundra, .mesa: return .outdoor
        case .forest, .swamp, .jungle: return .outdoor
        case .ocean: return .underwater
        case .mountain: return .cave
        case .corrupted: return .corrupted
        case .volcanic: return .magical
        case .ethereal, .crystal: return .magical
        case .arctic: return .outdoor
        }
    }
}

// MARK: - Audio Processing Effects

enum AudioFilter {
    case lowPass(frequency: Float, resonance: Float = 1.0)
    case highPass(frequency: Float, resonance: Float = 1.0)
    case bandPass(frequency: Float, bandwidth: Float)
    case echo(delay: TimeInterval, feedback: Float, wetDryMix: Float = 0.5)
    case reverb(preset: AVAudioUnitReverbPreset, wetDryMix: Float = 0.3)
    case distortion(preGain: Float, wetDryMix: Float = 0.5)
    case chorus(rate: Float, depth: Float, feedback: Float, wetDryMix: Float = 0.5)
    case compressor(threshold: Float, ratio: Float, attack: TimeInterval, release: TimeInterval)
    
    var nodeType: AudioNodeType {
        switch self {
        case .lowPass, .highPass, .bandPass: return .equalizer
        case .echo: return .delay
        case .reverb: return .reverb
        case .distortion: return .distortion
        case .chorus: return .modulation
        case .compressor: return .dynamics
        }
    }
}

enum AudioNodeType {
    case equalizer, delay, reverb, distortion, modulation, dynamics
}

// MARK: - Spatial Audio System

enum AudioSpatialization: Codable {
    case ambient                                    // Non-positional, fills space
    case positional(radius: Float)                 // 3D positioned with falloff
    case directional(direction: SIMD3<Float>, cone: Float) // Directional with cone
    case surround                                   // Multi-channel surround
    
    var usesSpatialProcessing: Bool {
        switch self {
        case .ambient, .surround: return false
        case .positional, .directional: return true
        }
    }
    
    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case type, radius, direction, cone
    }
    
    enum SpatializationType: String, Codable {
        case ambient, positional, directional, surround
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .ambient:
            try container.encode(SpatializationType.ambient, forKey: .type)
        case .positional(let radius):
            try container.encode(SpatializationType.positional, forKey: .type)
            try container.encode(radius, forKey: .radius)
        case .directional(let direction, let cone):
            try container.encode(SpatializationType.directional, forKey: .type)
            try container.encode([direction.x, direction.y, direction.z], forKey: .direction)
            try container.encode(cone, forKey: .cone)
        case .surround:
            try container.encode(SpatializationType.surround, forKey: .type)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SpatializationType.self, forKey: .type)
        
        switch type {
        case .ambient:
            self = .ambient
        case .positional:
            let radius = try container.decode(Float.self, forKey: .radius)
            self = .positional(radius: radius)
        case .directional:
            let directionArray = try container.decode([Float].self, forKey: .direction)
            let direction = SIMD3<Float>(directionArray[0], directionArray[1], directionArray[2])
            let cone = try container.decode(Float.self, forKey: .cone)
            self = .directional(direction: direction, cone: cone)
        case .surround:
            self = .surround
        }
    }
}

// MARK: - Audio Quality Management

struct AudioQualitySettings: Equatable, Comparable, Codable {
    let sampleRate: Double
    let bitDepth: Int
    let channels: Int
    let bufferSize: AVAudioFrameCount
    
    static let high = AudioQualitySettings(
        sampleRate: 48000, bitDepth: 24, channels: 2, bufferSize: 256
    )
    
    static let medium = AudioQualitySettings(
        sampleRate: 44100, bitDepth: 16, channels: 2, bufferSize: 512
    )
    
    static let low = AudioQualitySettings(
        sampleRate: 22050, bitDepth: 16, channels: 1, bufferSize: 1024
    )
    
    public static func == (lhs: AudioQualitySettings, rhs: AudioQualitySettings) -> Bool {
        return lhs.sampleRate == rhs.sampleRate &&
               lhs.bitDepth == rhs.bitDepth &&
               lhs.channels == rhs.channels &&
               lhs.bufferSize == rhs.bufferSize
    }
    
    public static func < (lhs: AudioQualitySettings, rhs: AudioQualitySettings) -> Bool {
        return lhs.qualityScore < rhs.qualityScore
    }
    
    var qualityScore: Int {
        return Int(sampleRate) + (bitDepth * 1000) + (channels * 10000)
    }
}

// MARK: - Songweaving Audio Components

struct MelodyNote: Codable {
    let frequency: Float
    let duration: TimeInterval
    let volume: Float
    let timbre: AudioTimbre?
    
    init(frequency: Float, duration: TimeInterval, volume: Float = 1.0, timbre: AudioTimbre? = nil) {
        self.frequency = frequency
        self.duration = duration
        self.volume = volume
        self.timbre = timbre
    }
}

struct AudioTimbre: Codable {
    let waveform: Waveform
    let harmonics: [Float]
    let envelope: ADSREnvelope
    let effects: [String] // Store effect descriptions instead of AudioFilter objects
    
    enum Waveform: String, CaseIterable, Codable {
        case sine, triangle, square, sawtooth, noise, custom
        
        var harmonicContent: [Float] {
            switch self {
            case .sine: return [1.0]
            case .triangle: return [1.0, 0.0, 0.11, 0.0, 0.04]
            case .square: return [1.0, 0.0, 0.33, 0.0, 0.2, 0.0, 0.14]
            case .sawtooth: return [1.0, 0.5, 0.33, 0.25, 0.2]
            case .noise: return Array(repeating: 1.0, count: 20)
            case .custom: return [1.0]
            }
        }
    }
}

struct ADSREnvelope: Codable {
    let attack: TimeInterval
    let decay: TimeInterval
    let sustain: Float
    let release: TimeInterval
    
    static let `default` = ADSREnvelope(attack: 0.1, decay: 0.2, sustain: 0.7, release: 0.5)
    static let percussive = ADSREnvelope(attack: 0.01, decay: 0.1, sustain: 0.0, release: 0.3)
    static let pad = ADSREnvelope(attack: 0.5, decay: 0.3, sustain: 0.8, release: 1.0)
}

// MARK: - Audio Source Management

struct PlayingMelody {
    let id: UUID
    let melody: Melody
    let caster: Entity
    let audioSource: SpatialAudioSource
    let startTime: Date
    
    var elapsedTime: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
    
    var isComplete: Bool {
        return elapsedTime >= melody.duration
    }
    
    var remainingTime: TimeInterval {
        return max(0, melody.duration - elapsedTime)
    }
}

struct PlayingHarmony {
    let id: UUID
    let harmony: Harmony
    let participants: [Entity]
    let audioSource: SpatialAudioSource
    let startTime: Date
    
    var elapsedTime: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
    
    var isComplete: Bool {
        return elapsedTime >= harmony.duration
    }
    
    var strength: Float {
        return harmony.strength * Float(participants.count) * 0.2
    }
}

// MARK: - Audio Occlusion System

struct AudioOcclusionData {
    let sourcePosition: SIMD3<Float>
    let listenerPosition: SIMD3<Float>
    let occlusionFactor: Float
    let materialType: MaterialType
    let distance: Float
    
    var attenuatedVolume: Float {
        let distanceAttenuation = 1.0 / (1.0 + distance * distance * 0.01)
        return distanceAttenuation * (1.0 - occlusionFactor * materialType.occlusionFactor)
    }
}

enum MaterialType: String, CaseIterable, Codable {
    case stone, wood, water, air, metal, fabric, magical
    
    var occlusionFactor: Float {
        switch self {
        case .stone, .metal: return 0.9
        case .wood: return 0.6
        case .fabric: return 0.4
        case .water: return 0.3
        case .magical: return 0.1
        case .air: return 0.0
        }
    }
    
    var densityFactor: Float {
        switch self {
        case .air: return 0.001
        case .water: return 1.0
        case .fabric: return 0.3
        case .wood: return 0.6
        case .stone: return 2.7
        case .metal: return 7.8
        case .magical: return 0.5
        }
    }
}

struct CollisionMesh {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
    let materialType: MaterialType
    let boundingBox: BoundingBox
}

struct BoundingBox {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
    
    var center: SIMD3<Float> { (min + max) / 2 }
    var size: SIMD3<Float> { max - min }
    
    func contains(_ point: SIMD3<Float>) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
}

// MARK: - Environmental Audio Presets

struct EnvironmentalAudioPreset: Codable {
    let name: String
    let biome: BiomeType
    let weather: WeatherType
    let timeOfDay: TimeOfDay
    let ambientVolume: Float
    let weatherVolume: Float
    let enableRandomEvents: Bool
    let eventFrequency: TimeInterval
    let qualitySettings: AudioQualitySettings
    let spatialProcessing: Bool
    
    static let peacefulForest = EnvironmentalAudioPreset(
        name: "Peaceful Forest", biome: .forest, weather: .clear, timeOfDay: .day,
        ambientVolume: 0.8, weatherVolume: 0.0, enableRandomEvents: true,
        eventFrequency: 45.0, qualitySettings: .high, spatialProcessing: true
    )
    
    static let mysteriousSwamp = EnvironmentalAudioPreset(
        name: "Mysterious Swamp", biome: .swamp, weather: .fog, timeOfDay: .dusk,
        ambientVolume: 0.6, weatherVolume: 0.7, enableRandomEvents: true,
        eventFrequency: 30.0, qualitySettings: .high, spatialProcessing: true
    )
    
    static let corruptedWasteland = EnvironmentalAudioPreset(
        name: "Corrupted Wasteland", biome: .corrupted, weather: .discordantStorm, timeOfDay: .night,
        ambientVolume: 0.3, weatherVolume: 0.9, enableRandomEvents: true,
        eventFrequency: 20.0, qualitySettings: .medium, spatialProcessing: true
    )
    
    static let tranquilOcean = EnvironmentalAudioPreset(
        name: "Tranquil Ocean", biome: .ocean, weather: .clear, timeOfDay: .dawn,
        ambientVolume: 0.9, weatherVolume: 0.0, enableRandomEvents: false,
        eventFrequency: 60.0, qualitySettings: .high, spatialProcessing: false
    )
    
    static let performanceOptimized = EnvironmentalAudioPreset(
        name: "Performance Optimized", biome: .grassland, weather: .clear, timeOfDay: .day,
        ambientVolume: 0.7, weatherVolume: 0.5, enableRandomEvents: false,
        eventFrequency: 120.0, qualitySettings: .low, spatialProcessing: false
    )
}

// MARK: - Performance Monitoring
 enum NexusLayer {
    case core
    case ring(Int)
 }

// MARK: - Environmental Audio Diagnostics

struct EnvironmentalAudioDiagnostics {
    let currentBiome: BiomeType
    let currentWeather: WeatherType
    let timeOfDay: TimeOfDay
    let ambientSoundCount: Int
    let weatherSoundCount: Int
    let dynamicSoundCount: Int
    let timeBasedSoundCount: Int
    let isRandomEventsEnabled: Bool
    let performanceMode: Bool
    let currentAmbientLevel: Float
    let targetAmbientLevel: Float
    
    var totalActiveSounds: Int {
        return ambientSoundCount + weatherSoundCount + dynamicSoundCount + timeBasedSoundCount
    }
    
    var memoryFootprint: String {
        let total = totalActiveSounds
        return "\(total) active sources"
    }
}

 struct SongweavingPerformanceInfo {
    let activeMelodies: Int
    let activeHarmonies: Int
    let maxMelodies: Int
    let maxHarmonies: Int
    let synthesisLoad: Float
    let memoryUsage: Float
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

struct AudioGroup {
    let id: UUID
    let sourceIds: [UUID]
    var volume: Float = 1.0
    var enabled: Bool = true
}

// MARK: - Audio Protocol Requirements

protocol SpatialAudioSourceProtocol {
    var id: UUID { get }
    var position: SIMD3<Float> { get set }
    var category: AudioCategory { get }
    var volume: Float { get set }
    var baseVolume: Float { get }
    var estimatedDuration: TimeInterval { get }
    var isPlaying: Bool { get }
    
    func play()
    func stop()
    func pause()
    func updatePosition(_ newPosition: SIMD3<Float>)
    func setSpatialization(_ spatialization: AudioSpatialization)
    func updateVolume()
    func setOcclusion(_ occlusionData: AudioOcclusionData)
    func updateQualitySettings(_ settings: AudioQualitySettings)
    func setBaseVolume(_ volume: Float)
    func setVolume(_ volume: Float)
}

// MARK: - Platform-Specific Audio Extensions

#if os(iOS) || os(visionOS)
extension AVAudioSession {
    static func configureFinalverseSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .gameChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true)
    }
}
#endif

extension AVAudioFormat {
    static func finalverseFormat(settings: AudioQualitySettings) -> AVAudioFormat? {
        return AVAudioFormat(
            standardFormatWithSampleRate: settings.sampleRate,
            channels: AVAudioChannelCount(settings.channels)
        )
    }
    
    static func spatialFormat() -> AVAudioFormat? {
        return AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)
    }
}

// MARK: - Audio Resource Management

class AudioResourceManager {
    static let shared = AudioResourceManager()
    private var cachedResources: [String: AVAudioFile] = [:]
    private let cacheQueue = DispatchQueue(label: "audio.resource.cache", qos: .utility)
    
    private init() {}
    
    func loadAudioResource(named name: String, bundle: Bundle = .main) async throws -> AVAudioFile {
        return try await withCheckedThrowingContinuation { continuation in
            cacheQueue.async {
                if let cached = self.cachedResources[name] {
                    continuation.resume(returning: cached)
                    return
                }
                
                guard let url = bundle.url(forResource: name, withExtension: nil) else {
                    continuation.resume(throwing: AudioResourceError.fileNotFound(name))
                    return
                }
                
                do {
                    let audioFile = try AVAudioFile(forReading: url)
                    self.cachedResources[name] = audioFile
                    continuation.resume(returning: audioFile)
                } catch {
                    continuation.resume(throwing: AudioResourceError.loadingFailed(error))
                }
            }
        }
    }
    
    func clearCache() {
        cacheQueue.async {
            self.cachedResources.removeAll()
        }
    }
}

enum AudioResourceError: Error, LocalizedError {
    case fileNotFound(String)
    case loadingFailed(Error)
    case unsupportedFormat(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name): return "Audio file '\(name)' not found"
        case .loadingFailed(let error): return "Failed to load audio: \(error.localizedDescription)"
        case .unsupportedFormat(let format): return "Unsupported audio format: \(format)"
        case .invalidData: return "Invalid audio data"
        }
    }
}

// MARK: - Audio Utility Extensions

extension Melody {
    /// Audio priority for mixing when multiple melodies play
    var audioPriority: Int {
        switch type {
        case .protection: return 100
        case .restoration: return 90
        case .transformation: return 80
        case .creation: return 70
        case .exploration: return 60
        }
    }
    
    /// Estimated audio resource cost for performance management
    var audioResourceCost: Float {
        let baseCost: Float = 1.0
        let strengthMultiplier = strength
        let durationMultiplier = min(Float(duration) / 5.0, 2.0)
        return baseCost * strengthMultiplier * durationMultiplier
    }
    
    /// Convert melody to audio notes for synthesis
    func toAudioNotes() -> [MelodyNote] {
        // If melody already has notes, return them
        // Otherwise, generate basic notes based on melody type
        guard notes.isEmpty else { return notes }
        
        // Generate default notes based on melody type
        return Melody.generateDefaultNotes(for: type)
    }
    
    private static func generateDefaultNotes(for type: MelodyType) -> [MelodyNote] {
        switch type {
        case .restoration:
            return [
                MelodyNote(frequency: 261.63, duration: 1.0, volume: 0.8),
                MelodyNote(frequency: 329.63, duration: 0.5, volume: 0.9),
                MelodyNote(frequency: 392.00, duration: 0.5, volume: 1.0),
                MelodyNote(frequency: 523.25, duration: 1.5, volume: 0.7)
            ]
        case .exploration:
            return [
                MelodyNote(frequency: 293.66, duration: 0.5, volume: 0.7),
                MelodyNote(frequency: 369.99, duration: 0.5, volume: 0.8),
                MelodyNote(frequency: 440.00, duration: 0.5, volume: 0.9),
                MelodyNote(frequency: 587.33, duration: 0.5, volume: 1.0)
            ]
        case .creation:
            return [
                MelodyNote(frequency: 349.23, duration: 0.75, volume: 0.9),
                MelodyNote(frequency: 415.30, duration: 0.75, volume: 1.0),
                MelodyNote(frequency: 523.25, duration: 0.75, volume: 0.8)
            ]
        case .protection:
            return [
                MelodyNote(frequency: 220.00, duration: 1.0, volume: 1.0),
                MelodyNote(frequency: 293.66, duration: 0.5, volume: 0.9),
                MelodyNote(frequency: 440.00, duration: 1.0, volume: 0.9)
            ]
        case .transformation:
            return [
                MelodyNote(frequency: 466.16, duration: 0.4, volume: 0.6),
                MelodyNote(frequency: 554.37, duration: 0.4, volume: 0.8),
                MelodyNote(frequency: 622.25, duration: 0.4, volume: 1.0)
            ]
        }
    }
}

// MARK: - Supporting Types

struct MelodyLine {
    let notes: [MelodyNote]
    let voice: Int
    let volume: Float
}

enum AudioFormat {
    case wav, mp4, ogg, unknown
}

// MARK: - Audio Integration Bridge

/// Bridge between audio system and world/gameplay systems
struct AudioWorldBridge {
    /// Convert world weather to audio environment effects
    static func audioEnvironment(for weather: WeatherType, timeOfDay: TimeOfDay) -> EnvironmentType {
        switch weather {
        case .clear, .auroras: return .outdoor
        case .rain, .fog: return .outdoor
        case .storm: return .cave
        case .discordantStorm: return .corrupted
        case .snow: return .cave
        case .sandstorm: return .corrupted
        case .harmonyShower: return .magical
        case .voidMist: return .void
        }
    }
    
    /// Calculate ambient audio level based on time and weather
    static func ambientLevel(timeOfDay: TimeOfDay, weather: WeatherType, biome: BiomeType) -> Float {
        let timeMultiplier = timeOfDay.lightLevel
        let weatherMultiplier = weather.intensityRange.lowerBound + 0.5
        let biomeBase = biome.defaultHarmonyLevel
        
        return min(1.0, timeMultiplier * weatherMultiplier * biomeBase)
    }
}
