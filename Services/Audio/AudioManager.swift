//
//  Services/Audio/AudioManager.swift
//  FinalStorm
//
//  Main audio coordinator - fixed to remove async call conflicts
//

import Foundation
import RealityKit
import Combine

@MainActor
class AudioManager: ObservableObject {
    // MARK: - Singleton
    static let shared = AudioManager()
    
    // MARK: - Properties
    @Published var isInitialized: Bool = false
    @Published var currentQualitySettings: AudioQualitySettings = .high
    @Published var performanceMode: Bool = false
    @Published var masterVolume: Float = 1.0
    
    // Audio subsystems
    private var spatialAudioEngine: SpatialAudioEngine?
    private var environmentalAudio: EnvironmentalAudio?
    private var songweavingAudio: SongweavingAudio?
    
    // Managers
    private let environmentalAudioManager = EnvironmentalAudioManager.shared
    
    // Performance monitoring
    @Published var performanceMetrics: AudioPerformanceMetrics = AudioPerformanceMetrics()
    private var performanceMonitoringTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Initialization
    func initialize(qualitySettings: AudioQualitySettings = .high) async {
        guard !isInitialized else { return }
        
        currentQualitySettings = qualitySettings
        
        // Initialize core spatial audio engine
        spatialAudioEngine = SpatialAudioEngine()
        
        guard let engine = spatialAudioEngine else {
            print("Failed to initialize spatial audio engine")
            return
        }
        
        // Initialize subsystems
        environmentalAudio = EnvironmentalAudio(spatialAudioEngine: engine)
        songweavingAudio = SongweavingAudio(spatialAudioEngine: engine, qualitySettings: qualitySettings)
        
        // Initialize environmental audio manager
        await environmentalAudioManager.initialize()
        
        isInitialized = true
        
        // Start performance monitoring
        startPerformanceMonitoring()
        
        print("AudioManager initialized successfully")
    }
    
    private func startPerformanceMonitoring() {
        performanceMonitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updatePerformanceMetrics()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    
    private func updatePerformanceMetrics() async {
        guard let engine = spatialAudioEngine else { return }
        
        performanceMetrics = engine.getPerformanceMetrics()
        
        if performanceMetrics.cpuUsage > 0.8 && !performanceMode {
            enablePerformanceMode(true)
        }
    }
    
    // MARK: - Master Controls
    func setMasterVolume(_ volume: Float) {
        masterVolume = volume
        spatialAudioEngine?.setMasterVolume(volume)
    }
    
    func enablePerformanceMode(_ enabled: Bool) {
        performanceMode = enabled
        
        if enabled {
            currentQualitySettings = .low
        } else {
            currentQualitySettings = .high
        }
        
        updateQualitySettings(currentQualitySettings)
        environmentalAudio?.enablePerformanceMode(enabled)
    }
    
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        currentQualitySettings = settings
        spatialAudioEngine?.updateQualitySettings(settings)
        songweavingAudio?.updateQualitySettings(settings)
    }
    
    // MARK: - Listener Management
    func setListener(_ entity: Entity) {
        spatialAudioEngine?.setListener(entity)
        environmentalAudio?.setListener(entity)
    }
    
    // MARK: - Environmental Audio Interface
    func setBiome(_ biome: BiomeType) {
        environmentalAudioManager.setBiome(biome)
    }
    
    func setWeather(_ weather: WeatherType, intensity: Float = 1.0) {
        environmentalAudioManager.setWeather(weather, intensity: intensity)
    }
    
    func setTimeOfDay(_ time: TimeOfDay) {
        environmentalAudioManager.setTimeOfDay(time)
    }
    
    func applyEnvironmentalPreset(_ preset: EnvironmentalAudioPreset) {
        environmentalAudioManager.applyPreset(preset)
    }
    
    func transitionToEnvironmentalPreset(_ preset: EnvironmentalAudioPreset, duration: TimeInterval = 3.0) {
        environmentalAudioManager.transitionToPreset(preset, duration: duration)
    }
    
    func playEnvironmentalEvent(_ event: EnvironmentalEvent, at position: SIMD3<Float>, intensity: Float = 1.0) {
        environmentalAudioManager.playEnvironmentalEvent(event, at: position, intensity: intensity)
    }
    
    // MARK: - Songweaving Audio Interface
    func playMelody(_ melody: Melody, at position: SIMD3<Float>, caster: Entity) async {
        await songweavingAudio?.playMelody(melody, at: position, caster: caster)
    }
    
    func playHarmony(_ harmony: Harmony, participants: [Entity]) async {
        await songweavingAudio?.playHarmony(harmony, participants: participants)
    }
    
    func stopAllMelodies() {
        songweavingAudio?.stopAllMelodies()
    }
    
    func stopAllHarmonies() {
        songweavingAudio?.stopAllHarmonies()
    }
    
    func getSongweavingPerformanceInfo() -> SongweavingPerformanceInfo? {
        return songweavingAudio?.getPerformanceInfo()
    }
    
    // MARK: - Direct Audio Playback
    func playSound(
        _ soundName: String,
        at position: SIMD3<Float>,
        category: AudioCategory = .effects,
        volume: Float = 1.0,
        spatialization: AudioSpatialization = .positional(radius: 10.0)
    ) async {
        guard let engine = spatialAudioEngine else { return }
        
        do {
            let audioFile = try await AudioResourceManager.shared.loadAudioResource(named: soundName)
            let audioResource = try await AudioFileResource.load(contentsOf: audioFile.url)
            
            engine.playSound(
                at: position,
                audioResource: audioResource,
                category: category,
                volume: volume,
                spatialization: spatialization
            )
        } catch {
            print("Failed to play sound \(soundName): \(error)")
        }
    }
    
    // MARK: - Game Integration Methods
    func playEchoInteraction(echo: EchoType, at position: SIMD3<Float>) {
        environmentalAudio?.playEchoInteraction(echo: echo, at: position)
    }
    
    func playHarmonyEvent(at position: SIMD3<Float>, strength: Float) {
        environmentalAudio?.playHarmonyEvent(at: position, strength: strength)
    }
    
    func playCorruptionEvent(at position: SIMD3<Float>, intensity: Float) {
        environmentalAudio?.playCorruptionEvent(at: position, intensity: intensity)
    }
    
    func playSongweavingEvent(at position: SIMD3<Float>, melody: MelodyType) {
        environmentalAudio?.playSongweavingEvent(at: position, melody: melody)
    }
    
    // MARK: - Audio Categories Volume Control
    func setCategoryVolume(_ category: AudioCategory, volume: Float) {
        spatialAudioEngine?.setCategoryVolume(category, volume: volume)
    }
    
    func getCategoryVolume(_ category: AudioCategory) -> Float {
        return spatialAudioEngine?.getCategoryVolume(category) ?? category.defaultVolume
    }
    
    // MARK: - Advanced Audio Processing
    func applyGlobalAudioFilter(_ filter: AudioFilter) {
        spatialAudioEngine?.applyAudioFilter(filter)
    }
    
    func setEnvironmentalEffects(for environment: EnvironmentType) {
        spatialAudioEngine?.updateEnvironmentalEffects(for: environment)
    }
    
    // MARK: - Performance and Diagnostics
    func getDetailedPerformanceInfo() -> DetailedAudioPerformanceInfo {
        let baseMetrics = performanceMetrics
        let songweavingInfo = getSongweavingPerformanceInfo()
        let environmentalInfo = getEnvironmentalPerformanceInfo()
        
        return DetailedAudioPerformanceInfo(
            baseMetrics: baseMetrics,
            songweavingInfo: songweavingInfo,
            environmentalInfo: environmentalInfo,
            qualitySettings: currentQualitySettings,
            performanceMode: performanceMode
        )
    }
    
    private func getEnvironmentalPerformanceInfo() -> EnvironmentalPerformanceInfo {
        return EnvironmentalPerformanceInfo(
            activeAmbientSources: environmentalAudio?.ambientLoops.count ?? 0,
            activeWeatherSources: environmentalAudio?.weatherSounds.count ?? 0,
            activeDynamicSources: environmentalAudio?.dynamicSources.count ?? 0,
            randomEventsEnabled: environmentalAudio?.isRandomEventsEnabled ?? false
        )
    }
    
    func clearAudioCache() {
        AudioResourceManager.shared.clearCache()
    }
    
    // MARK: - Scene Integration
    func onSceneChanged(to newScene: SceneType) {
        let preset = getPresetForScene(newScene)
        applyEnvironmentalPreset(preset)
    }
    
    private func getPresetForScene(_ scene: SceneType) -> EnvironmentalAudioPreset {
        switch scene {
        case .mainMenu:
            return .tranquilOcean
        case .gameplay:
            return .peacefulForest
        case .combat:
            return .corruptedWasteland
        case .exploration:
            return .mysteriousSwamp
        case .performance:
            return .performanceOptimized
        }
    }
    
    // MARK: - State Management
    func saveAudioSettings() -> AudioSettings {
        return AudioSettings(
            masterVolume: masterVolume,
            categoryVolumes: getAllCategoryVolumes(),
            qualitySettings: currentQualitySettings,
            performanceMode: performanceMode,
            currentPreset: environmentalAudioManager.currentPreset
        )
    }
    
    func loadAudioSettings(_ settings: AudioSettings) {
        setMasterVolume(settings.masterVolume)
        
        for (category, volume) in settings.categoryVolumes {
            setCategoryVolume(category, volume: volume)
        }
        
        updateQualitySettings(settings.qualitySettings)
        enablePerformanceMode(settings.performanceMode)
        
        if let preset = settings.currentPreset {
            applyEnvironmentalPreset(preset)
        }
    }
    
    private func getAllCategoryVolumes() -> [AudioCategory: Float] {
        var volumes: [AudioCategory: Float] = [:]
        for category in AudioCategory.allCases {
            volumes[category] = getCategoryVolume(category)
        }
        return volumes
    }
    
    // MARK: - Platform-Specific Features
    #if os(iOS) || os(visionOS)
    func configureForMobileDevice() {
        enablePerformanceMode(true)
        updateQualitySettings(.medium)
        
        songweavingAudio?.maxConcurrentMelodies = 4
        songweavingAudio?.maxConcurrentHarmonies = 2
    }
    
    func handleAudioSessionInterruption(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
           let type = AVAudioSessionInterruptionType(rawValue: typeValue) {
            
            switch type {
            case .began:
                pauseAllAudio()
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSessionInterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        resumeAllAudio()
                    }
                }
            @unknown default:
                break
            }
        }
    }
    #endif
    
    #if os(macOS)
    func configureForDesktop() {
        updateQualitySettings(.high)
        enablePerformanceMode(false)
    }
    #endif
    
    // MARK: - Audio Lifecycle Management
    func pauseAllAudio() {
        songweavingAudio?.stopAllMelodies()
        songweavingAudio?.stopAllHarmonies()
        setCategoryVolume(.environment, volume: 0.2)
    }
    
    func resumeAllAudio() {
        for category in AudioCategory.allCases {
            setCategoryVolume(category, volume: category.defaultVolume)
        }
    }
    
    func muteAllAudio() {
        setMasterVolume(0.0)
    }
    
    func unmuteAllAudio() {
        setMasterVolume(1.0)
    }
    
    // MARK: - Cleanup
    func shutdown() {
        performanceMonitoringTask?.cancel()
        performanceMonitoringTask = nil
        
        songweavingAudio?.stopAllMelodies()
        songweavingAudio?.stopAllHarmonies()
        environmentalAudio?.stopAllEnvironmentalAudio()
        
        // Fixed: Use Task to call async shutdown from sync context
        Task { @MainActor in
            spatialAudioEngine?.shutdown()
        }
        
        isInitialized = false
        
        print("AudioManager shut down")
    }
    
    deinit {
        Task { @MainActor in
            shutdown()
        }
    }
 }

 // MARK: - Supporting Types
 struct AudioSettings: Codable {
    let masterVolume: Float
    let categoryVolumes: [AudioCategory: Float]
    let qualitySettings: AudioQualitySettings
    let performanceMode: Bool
    let currentPreset: EnvironmentalAudioPreset?
 }

 struct DetailedAudioPerformanceInfo {
    let baseMetrics: AudioPerformanceMetrics
    let songweavingInfo: SongweavingPerformanceInfo?
    let environmentalInfo: EnvironmentalPerformanceInfo
    let qualitySettings: AudioQualitySettings
    let performanceMode: Bool
    
    var overallHealthScore: Float {
        let cpuScore = 1.0 - baseMetrics.cpuUsage
        let memoryScore = max(0, 1.0 - (baseMetrics.memoryUsage / 100.0))
        let sourceScore = max(0, 1.0 - Float(baseMetrics.activeSources) / 50.0)
        
        return (cpuScore + memoryScore + sourceScore) / 3.0
    }
    
    var recommendedQualitySettings: AudioQualitySettings {
        if overallHealthScore < 0.5 {
            return .low
        } else if overallHealthScore < 0.8 {
            return .medium
        } else {
            return .high
        }
    }
 }

 struct EnvironmentalPerformanceInfo {
    let activeAmbientSources: Int
    let activeWeatherSources: Int
    let activeDynamicSources: Int
    let randomEventsEnabled: Bool
    
    var totalSources: Int {
        return activeAmbientSources + activeWeatherSources + activeDynamicSources
    }
 }

 enum SceneType {
    case mainMenu
    case gameplay
    case combat
    case exploration
    case performance
 }
