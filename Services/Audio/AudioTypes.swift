//
//  Services/Audio/AudioTypes.swift
//  FinalStorm
//
//  Consolidated audio types for the Finalverse audio system
//  Platform-agnostic audio definitions with latest AVFoundation support
//

import Foundation
import AVFoundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Core Audio Types
enum AudioCategory: String, CaseIterable, Codable {
    case music = "Music"
    case effects = "Effects"
    case environment = "Environment"
    case voice = "Voice"
    case ui = "UI"
    case songweaving = "Songweaving"
    
    var priority: Int {
        switch self {
        case .voice:
            return 100
        case .songweaving:
            return 90
        case .ui:
            return 80
        case .effects:
            return 70
        case .environment:
            return 50
        case .music:
            return 40
        }
    }
    
    var defaultVolume: Float {
        switch self {
        case .music:
            return 0.6
        case .effects:
            return 0.8
        case .environment:
            return 0.7
        case .voice:
            return 1.0
        case .ui:
            return 0.9
        case .songweaving:
            return 0.8
        }
    }
    
    var nodeTag: Int {
        switch self {
        case .music:
            return 1000
        case .effects:
            return 1001
        case .environment:
            return 1002
        case .voice:
            return 1003
        case .ui:
            return 1004
        case .songweaving:
            return 1005
        }
    }
}

// MARK: - Environment Types
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
        case .outdoor:
            return .mediumHall
        case .indoor:
            return .mediumRoom
        case .cave:
            return .cathedral
        case .underwater:
            return .plate
        case .magical:
            return .largeHall2
        case .corrupted:
            return .largeRoom
        case .void:
            return .plate
        }
    }
    
    var wetDryMix: Float {
        switch self {
        case .outdoor:
            return 10
        case .indoor:
            return 25
        case .cave:
            return 60
        case .underwater:
            return 80
        case .magical:
            return 40
        case .corrupted:
            return 50
        case .void:
            return 90
        }
    }
}

// MARK: - Biome Types
enum BiomeType: String, CaseIterable, Codable {
    case grassland = "Grassland"
    case forest = "Forest"
    case desert = "Desert"
    case ocean = "Ocean"
    case mountain = "Mountain"
    case corrupted = "Corrupted"
    case tundra = "Tundra"
    case swamp = "Swamp"
    case volcanic = "Volcanic"
    
    var defaultAmbientLevel: Float {
        switch self {
        case .grassland, .forest:
            return 0.8
        case .desert, .tundra:
            return 0.5
        case .ocean:
            return 0.9
        case .mountain:
            return 0.6
        case .corrupted:
            return 0.3
        case .swamp:
            return 0.7
        case .volcanic:
            return 0.4
        }
    }
    
    var environmentType: EnvironmentType {
        switch self {
        case .grassland, .desert, .tundra:
            return .outdoor
        case .forest, .swamp:
            return .outdoor
        case .ocean:
            return .underwater
        case .mountain:
            return .cave
        case .corrupted:
            return .corrupted
        case .volcanic:
            return .magical
        }
    }
}

// MARK: - Weather Types
enum WeatherType: String, CaseIterable, Codable {
    case clear = "Clear"
    case rain = "Rain"
    case storm = "Storm"
    case discordantStorm = "Discordant Storm"
    case fog = "Fog"
    case snow = "Snow"
    case sandstorm = "Sandstorm"
    case auroras = "Auroras"
    
    var intensityRange: ClosedRange<Float> {
        switch self {
        case .clear:
            return 0.0...0.0
        case .rain, .fog, .snow:
            return 0.3...0.8
        case .storm, .sandstorm:
            return 0.6...1.0
        case .discordantStorm:
            return 0.8...1.2
        case .auroras:
            return 0.2...0.5
        }
    }
    
    var environmentalEffect: EnvironmentType {
        switch self {
        case .clear, .auroras:
            return .outdoor
        case .rain, .fog:
            return .outdoor
        case .storm:
            return .cave
        case .discordantStorm:
            return .corrupted
        case .snow:
            return .cave
        case .sandstorm:
            return .corrupted
        }
    }
}

// MARK: - Time of Day
enum TimeOfDay: String, CaseIterable, Codable {
    case dawn = "Dawn"
    case day = "Day"
    case dusk = "Dusk"
    case night = "Night"
    case lateNight = "Late Night"
    
    var ambientMultiplier: Float {
        switch self {
        case .dawn:
            return 0.8
        case .day:
            return 1.0
        case .dusk:
            return 0.7
        case .night:
            return 0.4
        case .lateNight:
            return 0.2
        }
    }
    
    var preferredEvents: [EnvironmentalEvent] {
        switch self {
        case .dawn:
            return [.animalCall, .windGust, .magicalResonance]
        case .day:
            return [.animalCall, .leafFall, .harmonyBoost]
        case .dusk:
            return [.windGust, .animalCall, .magicalResonance]
        case .night, .lateNight:
            return [.windGust, .stoneShift, .corruptionPulse]
        }
    }
}

// MARK: - Environmental Events
enum EnvironmentalEvent: String, CaseIterable, Codable {
    case thunderStrike = "Thunder Strike"
    case windGust = "Wind Gust"
    case animalCall = "Animal Call"
    case waterDrop = "Water Drop"
    case leafFall = "Leaf Fall"
    case stoneShift = "Stone Shift"
    case magicalResonance = "Magical Resonance"
    case corruptionPulse = "Corruption Pulse"
    case songweaving = "Songweaving"
    case harmonyBoost = "Harmony Boost"
    case silenceWhisper = "Silence Whisper"
    case echoCall = "Echo Call"
    case crystalChime = "Crystal Chime"
    case voidRipple = "Void Ripple"
    
    var defaultIntensity: Float {
        switch self {
        case .thunderStrike, .corruptionPulse, .voidRipple:
            return 1.0
        case .windGust, .songweaving, .magicalResonance:
            return 0.7
        case .animalCall, .harmonyBoost, .echoCall:
            return 0.6
        case .waterDrop, .leafFall, .crystalChime:
            return 0.3
        case .stoneShift, .silenceWhisper:
            return 0.5
        }
    }
    
    var falloffDistance: Float {
        switch self {
        case .thunderStrike, .voidRipple:
            return 100.0
        case .windGust, .corruptionPulse:
            return 50.0
        case .animalCall, .echoCall, .magicalResonance:
            return 30.0
        case .songweaving, .harmonyBoost:
            return 25.0
        case .waterDrop, .leafFall, .crystalChime:
            return 10.0
        case .stoneShift, .silenceWhisper:
            return 15.0
        }
    }
    
    var spatialization: AudioSpatialization {
        switch self {
        case .thunderStrike, .voidRipple:
            return .ambient
        case .windGust, .corruptionPulse:
            return .positional(radius: falloffDistance)
        case .animalCall, .echoCall:
            return .positional(radius: falloffDistance)
        case .songweaving, .harmonyBoost, .magicalResonance:
            return .positional(radius: falloffDistance)
        case .waterDrop, .leafFall, .crystalChime, .stoneShift, .silenceWhisper:
            return .positional(radius: falloffDistance)
        }
    }
}

// MARK: - Audio Processing Types
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
        case .lowPass, .highPass, .bandPass:
            return .equalizer
        case .echo:
            return .delay
        case .reverb:
            return .reverb
        case .distortion:
            return .distortion
        case .chorus:
            return .modulation
        case .compressor:
            return .dynamics
        }
    }
}

enum AudioNodeType {
    case equalizer
    case delay
    case reverb
    case distortion
    case modulation
    case dynamics
}

// MARK: - Spatial Audio Types
enum AudioSpatialization {
    case ambient                                    // Non-positional, fills space
    case positional(radius: Float)                  // 3D positioned with falloff
    case directional(direction: SIMD3<Float>, cone: Float) // Directional with cone
    case surround                                   // Multi-channel surround
    
    var usesSpatialProcessing: Bool {
        switch self {
        case .ambient, .surround:
            return false
        case .positional, .directional:
            return true
        }
    }
}

// MARK: - Audio Quality Settings
struct AudioQualitySettings {
    let sampleRate: Double
    let bitDepth: Int
    let channels: Int
    let bufferSize: AVAudioFrameCount
    
    static let high = AudioQualitySettings(
        sampleRate: 48000,
        bitDepth: 24,
        channels: 2,
        bufferSize: 256
    )
    
    static let medium = AudioQualitySettings(
        sampleRate: 44100,
        bitDepth: 16,
        channels: 2,
        bufferSize: 512
    )
    
    static let low = AudioQualitySettings(
        sampleRate: 22050,
        bitDepth: 16,
        channels: 1,
        bufferSize: 1024
    )
}

// MARK: - Songweaving Audio Types
struct MelodyNote {
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

struct AudioTimbre {
    let waveform: Waveform
    let harmonics: [Float]
    let envelope: ADSREnvelope
    let effects: [AudioFilter]
    
    enum Waveform: String, CaseIterable, Codable {
        case sine = "sine"
        case triangle = "triangle"
        case square = "square"
        case sawtooth = "sawtooth"
        case noise = "noise"
        case custom = "custom"
        
        var harmonicContent: [Float] {
            switch self {
            case .sine:
                return [1.0]
            case .triangle:
                return [1.0, 0.0, 0.11, 0.0, 0.04]
            case .square:
                return [1.0, 0.0, 0.33, 0.0, 0.2, 0.0, 0.14]
            case .sawtooth:
                return [1.0, 0.5, 0.33, 0.25, 0.2]
            case .noise:
                return Array(repeating: 1.0, count: 20) // Flat spectrum
            case .custom:
                return [1.0]
            }
        }
    }
}

struct ADSREnvelope {
    let attack: TimeInterval
    let decay: TimeInterval
    let sustain: Float
    let release: TimeInterval
    
    static let `default` = ADSREnvelope(
        attack: 0.1,
        decay: 0.2,
        sustain: 0.7,
        release: 0.5
    )
    
    static let percussive = ADSREnvelope(
        attack: 0.01,
        decay: 0.1,
        sustain: 0.0,
        release: 0.3
    )
    
    static let pad = ADSREnvelope(
        attack: 0.5,
        decay: 0.3,
        sustain: 0.8,
        release: 1.0
    )
}

// MARK: - Audio Source Tracking
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

// MARK: - Audio Occlusion
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
    case stone = "stone"
    case wood = "wood"
    case water = "water"
    case air = "air"
    case metal = "metal"
    case fabric = "fabric"
    case magical = "magical"
    
    var occlusionFactor: Float {
        switch self {
        case .stone, .metal:
            return 0.9  // Heavy occlusion
        case .wood:
            return 0.6  // Moderate occlusion
        case .fabric:
            return 0.4  // Light occlusion
        case .water:
            return 0.3  // Minimal occlusion
        case .magical:
            return 0.1  // Magical materials don't occlude much
        case .air:
            return 0.0  // No occlusion
        }
    }
    
    var densityFactor: Float {
        switch self {
        case .air:
            return 0.001
        case .water:
            return 1.0
        case .fabric:
            return 0.3
        case .wood:
            return 0.6
        case .stone:
            return 2.7
        case .metal:
            return 7.8
        case .magical:
            return 0.5 // Variable density
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
    
    var center: SIMD3<Float> {
        return (min + max) / 2
    }
    
    var size: SIMD3<Float> {
        return max - min
    }
    
    func contains(_ point: SIMD3<Float>) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
}

// MARK: - Audio Presets
struct EnvironmentalAudioPreset {
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
        name: "Peaceful Forest",
        biome: .forest,
        weather: .clear,
        timeOfDay: .day,
        ambientVolume: 0.8,
        weatherVolume: 0.0,
        enableRandomEvents: true,
        eventFrequency: 45.0,
        qualitySettings: .high,
        spatialProcessing: true
    )
    
    static let mysteriousSwamp = EnvironmentalAudioPreset(
        name: "Mysterious Swamp",
        biome: .swamp,
        weather: .fog,
        timeOfDay: .dusk,
        ambientVolume: 0.6,
        weatherVolume: 0.7,
        enableRandomEvents: true,
        eventFrequency: 30.0,
        qualitySettings: .high,
        spatialProcessing: true
    )
    
    static let corruptedWasteland = EnvironmentalAudioPreset(
        name: "Corrupted Wasteland",
        biome: .corrupted,
        weather: .discordantStorm,
        timeOfDay: .night,
        ambientVolume: 0.3,
        weatherVolume: 0.9,
        enableRandomEvents: true,
        eventFrequency: 20.0,
        qualitySettings: .medium,
        spatialProcessing: true
    )
    
    static let tranquilOcean = EnvironmentalAudioPreset(
        name: "Tranquil Ocean",
        biome: .ocean,
        weather: .clear,
        timeOfDay: .dawn,
        ambientVolume: 0.9,
        weatherVolume: 0.0,
        enableRandomEvents: false,
        eventFrequency: 60.0,
        qualitySettings: .high,
        spatialProcessing: false
    )
    
    static let performanceOptimized = EnvironmentalAudioPreset(
        name: "Performance Optimized",
        biome: .grassland,
        weather: .clear,
        timeOfDay: .day,
        ambientVolume: 0.7,
        weatherVolume: 0.5,
        enableRandomEvents: false,
        eventFrequency: 120.0,
        qualitySettings: .low,
        spatialProcessing: false
    )
}

// MARK: - Platform-Specific Extensions
#if os(iOS) || os(visionOS)
extension AVAudioSession {
    static func configureFinalverseSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .gameChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true)
    }
}
#endif

// MARK: - Audio Format Utilities
extension AVAudioFormat {
    static func finalverseFormat(settings: AudioQualitySettings) -> AVAudioFormat? {
        return AVAudioFormat(
            standardFormatWithSampleRate: settings.sampleRate,
            channels: AVAudioChannelCount(settings.channels)
        )
    }
    
    static func spatialFormat() -> AVAudioFormat? {
        return AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: 2
        )
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
        case .fileNotFound(let name):
            return "Audio file '\(name)' not found"
        case .loadingFailed(let error):
            return "Failed to load audio: \(error.localizedDescription)"
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .invalidData:
            return "Invalid audio data"
        }
    }
}

// Add to AudioTypes.swift
enum ParticleType: String, CaseIterable, Codable {
    case sparkles = "sparkles"
    case data = "data"
    case leaves = "leaves"
    case fire = "fire"
    
    var birthRate: Float {
        switch self {
        case .sparkles: return 20
        case .data: return 30
        case .leaves: return 10
        case .fire: return 40
        }
    }
    
    var particleSize: Float {
        switch self {
        case .sparkles: return 0.01
        case .data: return 0.005
        case .leaves: return 0.02
        case .fire: return 0.015
        }
    }
}

struct EchoAppearance {
    let meshName: String
    let baseScale: SIMD3<Float>
    let glowIntensity: Float
    let particleType: ParticleType
    
    static let lumiAppearance = EchoAppearance(
        meshName: "lumi_model",
        baseScale: SIMD3<Float>(0.3, 0.3, 0.3),
        glowIntensity: 2.0,
        particleType: .sparkles
    )
    
    static let kaiAppearance = EchoAppearance(
        meshName: "kai_model",
        baseScale: SIMD3<Float>(0.5, 0.5, 0.5),
        glowIntensity: 1.5,
        particleType: .data
    )
    
    static let terraAppearance = EchoAppearance(
        meshName: "terra_model",
        baseScale: SIMD3<Float>(0.8, 0.8, 0.8),
        glowIntensity: 1.0,
        particleType: .leaves
    )
    
    static let ignisAppearance = EchoAppearance(
        meshName: "ignis_model",
        baseScale: SIMD3<Float>(0.6, 0.6, 0.6),
        glowIntensity: 3.0,
        particleType: .fire
    )
}

// MARK: - Echo Animation States (CONSOLIDATED VERSION)
/// Animation states for Echo entities used throughout the application
/// This is the single source of truth for all echo animations
enum EchoAnimation: String, CaseIterable, Codable {
    // Basic states (used in all modules)
    case idle = "idle"
    case floating = "floating"
    case gesturing = "gesturing"
    
    // Teaching and interaction states
    case demonstrating = "demonstrating"  // Used in EchoEngine.swift for melody teaching
    case teaching = "teaching"            // Used in EchoEntity.swift for extended teaching sequences
    
    // Emotional and action states
    case excited = "excited"              // Used in EchoEntity.swift for high-energy responses
    
    // Movement states
    case wandering = "wandering"          // For playful movement
    case scanning = "scanning"            // For KAI's analysis mode
    case healing = "healing"              // For Terra's restoration activities
    case defending = "defending"          // For Ignis's protective stance
    case inspiring = "inspiring"          // For Lumi's encouragement behaviors
    
    /// Returns the default duration for this animation in seconds
    var defaultDuration: TimeInterval {
        switch self {
        case .idle:
            return .infinity  // Continuous loop
        case .floating:
            return 3.0       // Standard floating cycle
        case .gesturing:
            return 1.0       // Quick gesture
        case .demonstrating:
            return 5.0       // Melody demonstration
        case .teaching:
            return 8.0       // Extended teaching sequence
        case .excited:
            return 2.0       // Energetic burst
        case .wandering:
            return 4.0       // Movement to new position
        case .scanning:
            return 6.0       // KAI's environmental scan
        case .healing:
            return 5.0       // Terra's healing ritual
        case .defending:
            return 7.0       // Ignis's defensive formation
        case .inspiring:
            return 4.0       // Lumi's encouragement display
        }
    }
    
    /// Returns whether this animation should loop automatically
    var shouldLoop: Bool {
        switch self {
        case .idle, .floating:
            return true
        default:
            return false
        }
    }
    
    /// Returns the animation intensity (used for particle effects and scaling)
    var intensity: Float {
        switch self {
        case .idle:
            return 0.3
        case .floating:
            return 0.5
        case .gesturing:
            return 0.8
        case .demonstrating:
            return 1.0
        case .teaching:
            return 1.2
        case .excited:
            return 1.5
        case .wandering:
            return 0.7
        case .scanning:
            return 0.9
        case .healing:
            return 1.1
        case .defending:
            return 1.3
        case .inspiring:
            return 1.4
        }
    }
    
    /// Echo type compatibility - some animations are specific to certain echo types
    func isCompatible(with echoType: EchoType) -> Bool {
        switch self {
        case .scanning:
            return echoType == .kai
        case .healing:
            return echoType == .terra
        case .defending:
            return echoType == .ignis
        case .inspiring:
            return echoType == .lumi
        default:
            return true  // Basic animations work for all echo types
        }
    }
}
