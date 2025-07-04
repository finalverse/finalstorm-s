//
//  Services/Audio/EnvironmentalAudio.swift
//  FinalStorm
//
//  Enhanced environmental audio system using consolidated audio types
//  Platform-agnostic with advanced features and performance optimizations
//

import Foundation
import AVFoundation
import RealityKit
import Combine

@MainActor
class EnvironmentalAudio: ObservableObject {
    // MARK: - Properties
    @Published var isEnabled: Bool = true
    @Published var currentPreset: EnvironmentalAudioPreset?
    @Published var dynamicAmbientLevel: Float = 0.0
    @Published var performanceMode: Bool = false
    
    private let spatialAudioEngine: SpatialAudioEngine
    private var ambientLoops: [String: SpatialAudioSource] = [:]
    private var weatherSounds: [String: SpatialAudioSource] = [:]
    private var dynamicSources: [UUID: SpatialAudioSource] = [:]
    private var timeBasedSources: [String: SpatialAudioSource] = [:]
    
    // Enhanced state management
    private var currentBiome: BiomeType = .grassland
    private var currentWeather: WeatherType = .clear
    private var timeOfDay: TimeOfDay = .day
    private var environmentType: EnvironmentType = .outdoor
    
    // Audio processing
    private var fadeTask: Task<Void, Never>?
    private var randomEventTask: Task<Void, Never>?
    private var isRandomEventsEnabled: Bool = false
    
    // Volume management
    private var ambientVolume: Float = 0.7
    private var weatherVolume: Float = 0.8
    private var currentAmbientLevel: Float = 0.0
    private var targetAmbientLevel: Float = 0.0
    private let fadeSpeed: Float = 0.02
    
    // Listener tracking
    private weak var listenerEntity: Entity?
    private var lastListenerPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // Occlusion and performance
    private var occlusionCalculator: AudioOcclusionCalculator?
    private let resourceManager = AudioResourceManager.shared
    
    // MARK: - Initialization
    init(spatialAudioEngine: SpatialAudioEngine) {
        self.spatialAudioEngine = spatialAudioEngine
        
        Task {
            await initialize()
        }
    }
    
    private func initialize() async {
        // Setup occlusion calculator
        occlusionCalculator = AudioOcclusionCalculator()
        spatialAudioEngine.setOcclusionCalculator(occlusionCalculator!)
        
        // Configure initial environment
        updateEnvironmentalSettings()
        
        // Load initial ambient sounds
        await loadBiomeAmbientSounds()
        
        // Start update loops
        await startAmbientUpdateLoop()
        
        // Apply default preset
        applyPreset(.peacefulForest)
    }
    
    private func startAmbientUpdateLoop() async {
        fadeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateAmbientLevels()
                await self?.updateListenerTracking()
                try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
            }
        }
    }
    
    // MARK: - Preset Management
    func applyPreset(_ preset: EnvironmentalAudioPreset) {
        currentPreset = preset
        performanceMode = preset.qualitySettings == .low
        
        setBiome(preset.biome, transition: true)
        setWeather(preset.weather, intensity: 0.7)
        setTimeOfDay(preset.timeOfDay)
        setAmbientVolume(preset.ambientVolume)
        setWeatherVolume(preset.weatherVolume)
        
        // Update audio quality
        spatialAudioEngine.updateQualitySettings(preset.qualitySettings)
        spatialAudioEngine.enableSpatialAudio(preset.spatialProcessing)
        
        // Configure random events
        if preset.enableRandomEvents {
            startRandomAmbientEvents(frequency: preset.eventFrequency)
        } else {
            stopRandomAmbientEvents()
        }
    }
    
    func transitionToPreset(_ preset: EnvironmentalAudioPreset, duration: TimeInterval = 3.0) {
        Task {
            await smoothTransitionToPreset(preset, over: duration)
        }
    }
    
    private func smoothTransitionToPreset(_ preset: EnvironmentalAudioPreset, over duration: TimeInterval) async {
        let steps = Int(duration / 0.1)
        let volumeStep = (preset.ambientVolume - ambientVolume) / Float(steps)
        
        // Gradually transition volumes
        for _ in 0..<steps {
            let newVolume = ambientVolume + volumeStep
            setAmbientVolume(newVolume)
            try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
        }
        
        // Apply final preset settings
        applyPreset(preset)
    }
    
    // MARK: - Environment Management
    func setBiome(_ biome: BiomeType, transition: Bool = true) {
        guard biome != currentBiome else { return }
        
        let oldBiome = currentBiome
        currentBiome = biome
        environmentType = biome.environmentType
        
        // Update spatial audio environment
        spatialAudioEngine.updateEnvironmentalEffects(for: environmentType)
        
        if transition {
            Task {
                await crossfadeBiomeAudio(from: oldBiome, to: biome)
            }
        } else {
            Task {
                await loadBiomeAmbientSounds()
            }
        }
        
        updateEnvironmentalSettings()
    }
    
    func setWeather(_ weather: WeatherType, intensity: Float = 1.0) {
        guard weather != currentWeather else { return }
        
        let oldWeather = currentWeather
        currentWeather = weather
        
        // Update environment type if weather changes it significantly
        let weatherEnvironment = weather.environmentalEffect
        if weatherEnvironment != environmentType {
            environmentType = weatherEnvironment
            spatialAudioEngine.updateEnvironmentalEffects(for: environmentType)
        }
        
        Task {
            await crossfadeWeatherAudio(from: oldWeather, to: weather, intensity: intensity)
        }
    }
    
    func setTimeOfDay(_ time: TimeOfDay) {
        guard time != timeOfDay else { return }
        
        timeOfDay = time
        updateAmbientForTimeOfDay()
    }
    
    private func updateEnvironmentalSettings() {
        let reverbPreset = environmentType.reverbPreset
        spatialAudioEngine.setEnvironmentalReverb(reverbPreset)
        
        // Apply biome-specific audio filters
        applyBiomeFilters()
    }
    
    private func applyBiomeFilters() {
        switch currentBiome {
        case .underwater, .ocean:
            spatialAudioEngine.applyAudioFilter(.lowPass(frequency: 2000, resonance: 1.5))
            
        case .mountain:
            spatialAudioEngine.applyAudioFilter(.echo(delay: 0.3, feedback: 0.4, wetDryMix: 0.2))
            
        case .corrupted:
            spatialAudioEngine.applyAudioFilter(.distortion(preGain: 10, wetDryMix: 0.3))
            spatialAudioEngine.applyAudioFilter(.highPass(frequency: 200, resonance: 1.2))
            
        case .volcanic:
            spatialAudioEngine.applyAudioFilter(.lowPass(frequency: 8000, resonance: 0.8))
            spatialAudioEngine.applyAudioFilter(.distortion(preGain: 5, wetDryMix: 0.15))
            
        case .swamp:
            spatialAudioEngine.applyAudioFilter(.bandPass(frequency: 1000, bandwidth: 2.0))
            
        default:
            // Reset filters for natural biomes
            break
        }
    }
    
    // MARK: - Audio Loading and Management
    private func crossfadeBiomeAudio(from oldBiome: BiomeType, to newBiome: BiomeType) async {
        // Fade out old biome sounds
        await fadeOutBiomeSounds(oldBiome)
        
        // Load and fade in new biome sounds
        await loadBiomeAmbientSounds()
        await fadeInBiomeSounds(newBiome)
    }
    
    private func loadBiomeAmbientSounds() async {
        let soundsToLoad = getBiomeAmbientSounds(currentBiome)
        
        await withTaskGroup(of: Void.self) { group in
            for (soundName, audioFile) in soundsToLoad {
                group.addTask { [weak self] in
                    await self?.loadAmbientSound(soundName, audioFile: audioFile)
                }
            }
        }
    }
    
    private func loadAmbientSound(_ soundName: String, audioFile: String) async {
        do {
            let audioFile = try await resourceManager.loadAudioResource(named: audioFile)
            let audioResource = try await AudioFileResource.load(contentsOf: audioFile.url)
            
            let spatialization: AudioSpatialization = performanceMode ? .ambient : .positional(radius: 30.0)
            
            let audioSource = spatialAudioEngine.createAudioSource(
                id: UUID(),
                position: SIMD3<Float>(0, 0, 0), // Ambient sounds are typically non-positional
                audioResource: audioResource,
                category: .environment,
                volume: 0.0, // Start silent for fade-in
                loop: true
            )
            
            audioSource.setSpatialization(spatialization)
            ambientLoops[soundName] = audioSource
            audioSource.play()
            
        } catch {
            print("Failed to load ambient sound \(soundName): \(error)")
        }
    }
    
    private func getBiomeAmbientSounds(_ biome: BiomeType) -> [String: String] {
        switch biome {
        case .grassland:
            return [
                "wind_light": "ambient_wind_light",
                "birds_meadow": "ambient_birds_meadow",
                "grass_rustle": "ambient_grass_rustle",
                "insects_gentle": "ambient_insects_gentle",
                "breeze_soft": "ambient_breeze_soft"
            ]
            
        case .forest:
            return [
                "wind_trees": "ambient_wind_trees",
                "birds_forest": "ambient_birds_forest",
                "leaves_rustle": "ambient_leaves_rustle",
                "creek_distant": "ambient_creek_distant",
                "owl_soft": "ambient_owl_soft",
                "woodpecker": "ambient_woodpecker"
            ]
            
        case .desert:
            return [
                "wind_desert": "ambient_wind_desert",
                "sand_shift": "ambient_sand_shift",
                "coyote_distant": "ambient_coyote_distant",
                "heat_shimmer": "ambient_heat_shimmer"
            ]
            
        case .ocean:
            return [
                "waves_gentle": "ambient_waves_gentle",
                "wind_ocean": "ambient_wind_ocean",
                "seagulls": "ambient_seagulls",
                "water_deep": "ambient_water_deep",
                "whale_distant": "ambient_whale_distant"
            ]
            
        case .mountain:
            return [
                "wind_mountain": "ambient_wind_mountain",
                "echo_distant": "ambient_echo_distant",
                "stones_settle": "ambient_stones_settle",
                "eagle_cry": "ambient_eagle_cry",
                "avalanche_distant": "ambient_avalanche_distant"
            ]
            
        case .corrupted:
            return [
                "whispers_dark": "ambient_whispers_dark",
                "energy_corrupt": "ambient_energy_corrupt",
                "silence_oppressive": "ambient_silence_oppressive",
                "distortion_reality": "ambient_distortion_reality",
                "void_hum": "ambient_void_hum"
            ]
            
        case .tundra:
            return [
                "wind_arctic": "ambient_wind_arctic",
                "ice_crack": "ambient_ice_crack",
                "aurora_hum": "ambient_aurora_hum",
                "snow_fall": "ambient_snow_fall"
            ]
            
        case .swamp:
            return [
                "water_murky": "ambient_water_murky",
                "frogs_chorus": "ambient_frogs_chorus",
                "insects_swamp": "ambient_insects_swamp",
                "bubbles_methane": "ambient_bubbles_methane",
                "mist_ethereal": "ambient_mist_ethereal"
            ]
            
        case .volcanic:
            return [
                "lava_flow": "ambient_lava_flow",
                "gas_hiss": "ambient_gas_hiss",
                "rumble_deep": "ambient_rumble_deep",
                "heat_waves": "ambient_heat_waves",
                "crystals_sing": "ambient_crystals_sing"
            ]
        }
    }
    
    // MARK: - Weather Audio System
    private func crossfadeWeatherAudio(from oldWeather: WeatherType, to newWeather: WeatherType, intensity: Float) async {
        await fadeOutWeatherSounds(oldWeather)
        await loadWeatherSounds(newWeather, intensity: intensity)
        await fadeInWeatherSounds(newWeather)
    }
    
    private func loadWeatherSounds(_ weather: WeatherType, intensity: Float = 1.0) async {
        guard weather != .clear else { return }
        
        let weatherAudio = getWeatherAudioFiles(weather)
        
        await withTaskGroup(of: Void.self) { group in
            for (soundName, audioFile) in weatherAudio {
                group.addTask { [weak self] in
                    await self?.loadWeatherSound(soundName, audioFile: audioFile, intensity: intensity)
                }
            }
        }
    }
    
    private func loadWeatherSound(_ soundName: String, audioFile: String, intensity: Float) async {
        do {
            let audioFile = try await resourceManager.loadAudioResource(named: audioFile)
            let audioResource = try await AudioFileResource.load(contentsOf: audioFile.url)
            
            let spatialization: AudioSpatialization = .ambient // Weather is typically ambient
            
            let audioSource = spatialAudioEngine.createAudioSource(
                id: UUID(),
                position: SIMD3<Float>(0, 20, 0), // Weather sounds from above
                audioResource: audioResource,
                category: .environment,
                volume: 0.0,
                loop: true
            )
            
            audioSource.setSpatialization(spatialization)
            audioSource.setBaseVolume(weatherVolume * intensity)
            weatherSounds[soundName] = audioSource
            audioSource.play()
            
        } catch {
            print("Failed to load weather sound \(soundName): \(error)")
        }
    }
    
    private func getWeatherAudioFiles(_ weather: WeatherType) -> [String: String] {
        switch weather {
        case .clear:
            return [:]
            
        case .rain:
            return [
                "rain_light": "weather_rain_light",
                "rain_drops": "weather_rain_drops",
                "puddle_splash": "weather_puddle_splash",
                "rain_on_leaves": "weather_rain_on_leaves"
            ]
            
        case .storm:
            return [
                "rain_heavy": "weather_rain_heavy",
                "thunder_distant": "weather_thunder_distant",
                "wind_storm": "weather_wind_storm",
                "lightning_crack": "weather_lightning_crack",
                "thunder_close": "weather_thunder_close"
            ]
            
        case .discordantStorm:
            return [
                "storm_magical": "weather_storm_magical",
                "energy_chaotic": "weather_energy_chaotic",
                "wind_otherworldly": "weather_wind_otherworldly",
                "reality_tear": "weather_reality_tear",
                "void_lightning": "weather_void_lightning"
            ]
            
        case .fog:
            return [
                "mist_thick": "weather_mist_thick",
                "droplets_condensing": "weather_droplets_condensing",
                "visibility_low": "weather_visibility_low"
            ]
            
        case .snow:
            return [
                "snow_falling": "weather_snow_falling",
                "wind_cold": "weather_wind_cold",
                "snow_crunch": "weather_snow_crunch",
                "blizzard_distant": "weather_blizzard_distant"
            ]
            
        case .sandstorm:
            return [
                "sand_whipping": "weather_sand_whipping",
                "wind_desert_storm": "weather_wind_desert_storm",
                "particles_stinging": "weather_particles_stinging"
            ]
            
        case .auroras:
            return [
                "aurora_hum": "weather_aurora_hum",
                "magnetic_field": "weather_magnetic_field",
                "celestial_song": "weather_celestial_song"
            ]
        }
    }
    
    // MARK: - Time-Based Audio
    private func updateAmbientForTimeOfDay() {
        let timeMultiplier = timeOfDay.ambientMultiplier
        targetAmbientLevel = ambientVolume * timeMultiplier
        
        Task {
            await updateTimeBasedSounds()
        }
    }
    
    private func updateTimeBasedSounds() async {
        await clearTimeBasedSounds()
        
        switch timeOfDay {
        case .dawn:
            await addDawnSounds()
        case .day:
            await addDaySounds()
        case .dusk:
            await addDuskSounds()
        case .night:
            await addNightSounds()
        case .lateNight:
            await addLateNightSounds()
        }
    }
    
    private func addDawnSounds() async {
        await playTimedAmbientSound("dawn_chorus", audioFile: "ambient_dawn_chorus", duration: 30.0, volume: 0.6)
        await playTimedAmbientSound("morning_breeze", audioFile: "ambient_morning_breeze", duration: 45.0, volume: 0.4)
        await playTimedAmbientSound("rooster_distant", audioFile: "ambient_rooster_distant", duration: 5.0, volume: 0.3)
    }
    
    private func addDaySounds() async {
        await playTimedAmbientSound("day_activity", audioFile: "ambient_day_activity", duration: 60.0, volume: 0.5)
        await playTimedAmbientSound("bees_buzzing", audioFile: "ambient_bees_buzzing", duration: 40.0, volume: 0.3)
    }
    
    private func addDuskSounds() async {
        await playTimedAmbientSound("evening_birds", audioFile: "ambient_evening_birds", duration: 20.0, volume: 0.5)
        await playTimedAmbientSound("cricket_start", audioFile: "ambient_cricket_start", duration: 15.0, volume: 0.3)
        await playTimedAmbientSound("fireflies", audioFile: "ambient_fireflies", duration: 30.0, volume: 0.2)
    }
    
    private func addNightSounds() async {
        await playTimedAmbientSound("night_creatures", audioFile: "ambient_night_creatures", duration: 60.0, volume: 0.4)
        await playTimedAmbientSound("owl_distant", audioFile: "ambient_owl_distant", duration: 45.0, volume: 0.3)
        await playTimedAmbientSound("night_wind", audioFile: "ambient_night_wind", duration: 90.0, volume: 0.5)
        await playTimedAmbientSound("wolf_howl", audioFile: "ambient_wolf_howl", duration: 8.0, volume: 0.4)
    }
    
    private func addLateNightSounds() async {
        await playTimedAmbientSound("deep_silence", audioFile: "ambient_deep_silence", duration: 120.0, volume: 0.2)
        await playTimedAmbientSound("mysterious_whispers", audioFile: "ambient_mysterious_whispers", duration: 30.0, volume: 0.1)
        await playTimedAmbientSound("night_spirits", audioFile: "ambient_night_spirits", duration: 60.0, volume: 0.15)
    }
    
    private func clearTimeBasedSounds() async {
        for source in timeBasedSources.values {
            source.stop()
            spatialAudioEngine.removeAudioSource(source.id)
        }
        timeBasedSources.removeAll()
    }
    
    private func playTimedAmbientSound(_ name: String, audioFile: String, duration: TimeInterval, volume: Float = 0.6) async {
        do {
            let audioFile = try await resourceManager.loadAudioResource(named: audioFile)
            let audioResource = try await AudioFileResource.load(contentsOf: audioFile.url)
            
            let audioSource = spatialAudioEngine.createAudioSource(
                id: UUID(),
                position: SIMD3<Float>(
                    Float.random(in: -20...20),
                    Float.random(in: 5...15),
                    Float.random(in: -20...20)
                ),
                audioResource: audioResource,
                category: .environment,
                volume: ambientVolume * volume,
                loop: false
            )
            
            audioSource.setSpatialization(.positional(radius: 25.0))
            timeBasedSources[name] = audioSource
            audioSource.play()
            
            // Remove after duration
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                timeBasedSources.removeValue(forKey: name)
                spatialAudioEngine.removeAudioSource(audioSource.id)
            }
            
        } catch {
            print("Failed to play timed ambient sound \(name): \(error)")
        }
    }
    
    // MARK: - Environmental Events
    func playEnvironmentalEvent(_ event: EnvironmentalEvent, at position: SIMD3<Float>, intensity: Float = 1.0) {
        Task {
            await playEnvironmentalEventAsync(event, at: position, intensity: intensity)
        }
    }
    
    private func playEnvironmentalEventAsync(_ event: EnvironmentalEvent, at position: SIMD3<Float>, intensity: Float) async {
        let audioFiles = getEnvironmentalEventAudio(event)
        
        for audioFile in audioFiles {
            do {
                let audioFile = try await resourceManager.loadAudioResource(named: audioFile)
                let audioResource = try await AudioFileResource.load(contentsOf: audioFile.url)
                
                let audioSource = spatialAudioEngine.createAudioSource(
                    id: UUID(),
                    position: position,
                    audioResource: audioResource,
                    category: .environment,
                    volume: event.defaultIntensity * intensity,
                    loop: false
                )
                
                audioSource.setSpatialization(event.spatialization)
                dynamicSources[audioSource.id] = audioSource
                audioSource.play()
                
                // Clean up after playback
                Task {
                    let duration = audioSource.duration
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    dynamicSources.removeValue(forKey: audioSource.id)
                    spatialAudioEngine.removeAudioSource(audioSource.id)
                }
                
            } catch {
                print("Failed to play environmental event \(event): \(error)")
            }
        }
    }
    
    private func getEnvironmentalEventAudio(_ event: EnvironmentalEvent) -> [String] {
        switch event {
        case .thunderStrike:
            return ["event_thunder_strike", "event_thunder_rumble", "event_lightning_crack"]
            
        case .windGust:
            return ["event_wind_gust", "event_leaves_swirl"]
            
        case .animalCall:
            let animalSounds = ["event_animal_call_1", "event_animal_call_2", "event_animal_call_3",
                               "event_bird_cry", "event_wolf_howl", "event_deer_call"]
            return [animalSounds.randomElement() ?? "event_animal_call_1"]
            
        case .waterDrop:
            return ["event_water_drop", "event_ripple"]
            
        case .leafFall:
            return ["event_leaf_fall", "event_branch_crack"]
            
        case .stoneShift:
            return ["event_stone_shift", "event_pebbles_fall"]
            
        case .magicalResonance:
            return ["event_magical_resonance", "event_harmony_chime", "event_crystal_sing"]
            
        case .corruptionPulse:
            return ["event_corruption_pulse", "event_silence_whisper", "event_void_crack"]
            
        case .songweaving:
            return ["event_songweaving", "event_melody_creation", "event_harmony_weave"]
            
        case .harmonyBoost:
            return ["event_harmony_boost", "event_positive_energy", "event_light_chime"]
            
        case .silenceWhisper:
            return ["event_silence_whisper", "event_dark_murmur"]
            
        case .echoCall:
            return ["event_echo_call", "event_voice_distant"]
            
        case .crystalChime:
            return ["event_crystal_chime", "event_crystal_resonate"]
            
        case .voidRipple:
            return ["event_void_ripple", "event_reality_tear", "event_dimension_shift"]
        }
    }
    
    // MARK: - Random Ambient Events
    func startRandomAmbientEvents(frequency: TimeInterval = 60.0) {
        guard !isRandomEventsEnabled else { return }
        
        isRandomEventsEnabled = true
        randomEventTask = Task { [weak self] in
            await self?.randomEventLoop(frequency: frequency)
        }
    }
    
    func stopRandomAmbientEvents() {
        isRandomEventsEnabled = false
        randomEventTask?.cancel()
        randomEventTask = nil
    }
    
    private func randomEventLoop(frequency: TimeInterval) async {
        while isRandomEventsEnabled && !Task.isCancelled {
            let nextEventDelay = TimeInterval.random(in: frequency*0.5...frequency*1.5)
            
            try? await Task.sleep(nanoseconds: UInt64(nextEventDelay * 1_000_000_000))
            
            if !Task.isCancelled && isRandomEventsEnabled {
                await triggerRandomAmbientEvent()
            }
        }
    }
    
    private func triggerRandomAmbientEvent() async {
        let preferredEvents = timeOfDay.preferredEvents
        let biomeEvents = getBiomeSpecificEvents()
        let allEvents = preferredEvents + biomeEvents
        
        guard let randomEvent = allEvents.randomElement() else { return }
        
        // Random position around listener with appropriate distance
        let eventDistance = randomEvent.falloffDistance * 0.7
        let randomPosition = SIMD3<Float>(
            Float.random(in: -eventDistance...eventDistance),
            Float.random(in: 0...10),
            Float.random(in: -eventDistance...eventDistance)
        )
        
        await playEnvironmentalEventAsync(
            randomEvent,
            at: randomPosition,
            intensity: Float.random(in: 0.3...0.8)
        )
    }
    
    private func getBiomeSpecificEvents() -> [EnvironmentalEvent] {
        switch currentBiome {
        case .forest:
            return [.leafFall, .animalCall, .windGust]
        case .ocean:
            return [.waterDrop, .windGust]
        case .mountain:
            return [.stoneShift, .windGust, .echoCall]
        case .desert:
            return [.windGust, .stoneShift]
        case .corrupted:
            return [.corruptionPulse, .silenceWhisper, .voidRipple]
        case .swamp:
            return [.waterDrop, .animalCall, .magicalResonance]
        case .volcanic:
            return [.stoneShift, .magicalResonance, .crystalChime]
        case .tundra:
            return [.windGust, .crystalChime]
        default:
            return [.animalCall, .windGust, .leafFall]
        }
    }
    
    // MARK: - Update Loops
    private func updateAmbientLevels() {
        // Smooth fade ambient levels
        if abs(currentAmbientLevel - targetAmbientLevel) > 0.01 {
            if currentAmbientLevel < targetAmbientLevel {
                currentAmbientLevel = min(targetAmbientLevel, currentAmbientLevel + fadeSpeed)
            } else {
                currentAmbientLevel = max(targetAmbientLevel, currentAmbientLevel - fadeSpeed)
            }
            
            dynamicAmbientLevel = currentAmbientLevel
            
            // Apply to all ambient sources
            for source in ambientLoops.values {
                source.updateVolume()
            }
        }
    }
    
    private func updateListenerTracking() {
        guard let listener = listenerEntity else { return }
        
        let newPosition = listener.position
        let distance = simd_distance(newPosition, lastListenerPosition)
        
        // Update position-dependent audio only if listener moved significantly
        if distance > 1.0 {
            lastListenerPosition = newPosition
            spatialAudioEngine.updateListenerPosition()
            
            // Update dynamic source positions if needed
            updateDynamicSourcePositions(listenerPosition: newPosition)
        }
    }
    
    private func updateDynamicSourcePositions(listenerPosition: SIMD3<Float>) {
        for source in dynamicSources.values {
            // Apply distance-based volume adjustments
            let distance = simd_distance(source.position, listenerPosition)
            let maxDistance = source.spatialization.usesSpatialProcessing ? 50.0 : 100.0
            
            if distance > maxDistance {
                // Source is too far, fade it out
                source.setVolume(0.0)
            } else {
                // Normal distance attenuation is handled by spatial audio engine
                source.updateVolume()
            }
        }
    }
    
    // MARK: - Audio Fading
    private func fadeOutBiomeSounds(_ biome: BiomeType) async {
        let soundNames = Array(getBiomeAmbientSounds(biome).keys)
        
        await withTaskGroup(of: Void.self) { group in
            for soundName in soundNames {
                group.addTask { [weak self] in
                    await self?.fadeOutAmbientSound(soundName)
                }
            }
        }
    }
    
    private func fadeInBiomeSounds(_ biome: BiomeType) async {
        let soundNames = Array(getBiomeAmbientSounds(biome).keys)
        
        await withTaskGroup(of: Void.self) { group in
            for soundName in soundNames {
                group.addTask { [weak self] in
                    await self?.fadeInAmbientSound(soundName)
                }
            }
        }
    }
    
    private func fadeOutWeatherSounds(_ weather: WeatherType) async {
        let soundNames = Array(getWeatherAudioFiles(weather).keys)
        
        await withTaskGroup(of: Void.self) { group in
            for soundName in soundNames {
                group.addTask { [weak self] in
                    await self?.fadeOutWeatherSound(soundName)
                }
            }
        }
    }
    
    private func fadeInWeatherSounds(_ weather: WeatherType) async {
        let soundNames = Array(getWeatherAudioFiles(weather).keys)
        
        await withTaskGroup(of: Void.self) { group in
            for soundName in soundNames {
                group.addTask { [weak self] in
                    await self?.fadeInWeatherSound(soundName)
                }
            }
        }
    }
    
    private func fadeOutAmbientSound(_ soundName: String) async {
        guard let source = ambientLoops[soundName] else { return }
        
        let fadeSteps = 20
        let fadeStepDuration: TimeInterval = 0.05
        let volumeStep = source.volume / Float(fadeSteps)
        
        for _ in 0..<fadeSteps {
            let newVolume = max(0, source.volume - volumeStep)
            source.setVolume(newVolume)
            try? await Task.sleep(nanoseconds: UInt64(fadeStepDuration * 1_000_000_000))
        }
        
        source.stop()
        ambientLoops.removeValue(forKey: soundName)
        spatialAudioEngine.removeAudioSource(source.id)
    }
    
    private func fadeInAmbientSound(_ soundName: String) async {
        guard let source = ambientLoops[soundName] else { return }
        
        let targetVolume = ambientVolume
        let fadeSteps = 20
        let fadeStepDuration: TimeInterval = 0.05
        let volumeStep = targetVolume / Float(fadeSteps)
        
        source.setVolume(0)
        
        for _ in 0..<fadeSteps {
            let newVolume = min(targetVolume, source.volume + volumeStep)
            source.setVolume(newVolume)
            try? await Task.sleep(nanoseconds: UInt64(fadeStepDuration * 1_000_000_000))
        }
    }
    
    private func fadeOutWeatherSound(_ soundName: String) async {
        guard let source = weatherSounds[soundName] else { return }
        
        let fadeSteps = 15
        let fadeStepDuration: TimeInterval = 0.05
        let volumeStep = source.volume / Float(fadeSteps)
        
        for _ in 0..<fadeSteps {
            let newVolume = max(0, source.volume - volumeStep)
            source.setVolume(newVolume)
            try? await Task.sleep(nanoseconds: UInt64(fadeStepDuration * 1_000_000_000))
        }
        
        source.stop()
        weatherSounds.removeValue(forKey: soundName)
        spatialAudioEngine.removeAudioSource(source.id)
    }
    
    private func fadeInWeatherSound(_ soundName: String) async {
        guard let source = weatherSounds[soundName] else { return }
        
        let targetVolume = weatherVolume
        let fadeSteps = 15
        let fadeStepDuration: TimeInterval = 0.05
        let volumeStep = targetVolume / Float(fadeSteps)
        
        source.setVolume(0)
        
        for _ in 0..<fadeSteps {
            let newVolume = min(targetVolume, source.volume + volumeStep)
            source.setVolume(newVolume)
            try? await Task.sleep(nanoseconds: UInt64(fadeStepDuration * 1_000_000_000))
        }
    }
    
    // MARK: - Volume Control
    func setAmbientVolume(_ volume: Float) {
        ambientVolume = volume
        targetAmbientLevel = volume * timeOfDay.ambientMultiplier
        
        for source in ambientLoops.values {
            source.setBaseVolume(volume)
        }
    }
    
    func setWeatherVolume(_ volume: Float) {
        weatherVolume = volume
        
        for source in weatherSounds.values {
            source.setBaseVolume(volume)
        }
    }
    
    // MARK: - Listener Management
    func setListener(_ entity: Entity) {
        listenerEntity = entity
        lastListenerPosition = entity.position
        spatialAudioEngine.setListener(entity)
    }
    
    // MARK: - Game Integration Methods
    func playHarmonyEvent(at position: SIMD3<Float>, strength: Float) {
        let event: EnvironmentalEvent = strength > 0.7 ? .harmonyBoost : .magicalResonance
        playEnvironmentalEvent(event, at: position, intensity: strength)
    }
    
    func playCorruptionEvent(at position: SIMD3<Float>, intensity: Float) {
        let event: EnvironmentalEvent = intensity > 0.8 ? .voidRipple : .corruptionPulse
        playEnvironmentalEvent(event, at: position, intensity: intensity)
    }
    
    func playSongweavingEvent(at position: SIMD3<Float>, melody: MelodyType) {
        let intensity: Float
        switch melody {
        case .restoration:
            intensity = 0.8
        case .creation:
            intensity = 1.0
        case .protection:
            intensity = 0.9
        case .exploration:
            intensity = 0.7
        case .transformation:
            intensity = 1.2
        }
        
        playEnvironmentalEvent(.songweaving, at: position, intensity: intensity)
    }
    
    func playEchoInteraction(echo: EchoType, at position: SIMD3<Float>) {
        playEnvironmentalEvent(.echoCall, at: position, intensity: 0.6)
        
        // Add echo-specific sound
        let echoEvent: EnvironmentalEvent
        switch echo {
        case .lumi:
            echoEvent = .crystalChime
        case .kai:
            echoEvent = .magicalResonance
        case .terra:
            echoEvent = .harmonyBoost
        case .ignis:
            echoEvent = .windGust
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await playEnvironmentalEventAsync(echoEvent, at: position, intensity: 0.4)
        }
    }
    
    // MARK: - Performance Optimization
    func enablePerformanceMode(_ enabled: Bool) {
        performanceMode = enabled
        
        if enabled {
            // Reduce quality for better performance
            spatialAudioEngine.updateQualitySettings(.low)
            spatialAudioEngine.enableSpatialAudio(false)
            
            // Limit active sources
            limitActiveSources(maxSources: 10)
        } else {
            // Restore high quality
            let qualitySettings = currentPreset?.qualitySettings ?? .high
            spatialAudioEngine.updateQualitySettings(qualitySettings)
            spatialAudioEngine.enableSpatialAudio(true)
        }
    }
    
    private func limitActiveSources(maxSources: Int) {
        // Remove least important sources if we exceed the limit
        let totalSources = ambientLoops.count + weatherSounds.count + dynamicSources.count
        
        if totalSources > maxSources {
            // Priority: keep ambient > weather > dynamic
            let excessSources = totalSources - maxSources
            
            // Remove oldest dynamic sources first
            let sortedDynamic = dynamicSources.values.sorted { source1, source2 in
                // Assume sources have creation timestamps for sorting
                return source1.id.uuidString < source2.id.uuidString
            }
            
            for i in 0..<min(excessSources, sortedDynamic.count) {
                let source = sortedDynamic[i]
                source.stop()
                dynamicSources.removeValue(forKey: source.id)
                spatialAudioEngine.removeAudioSource(source.id)
            }
        }
    }
    
    // MARK: - Cleanup
    func stopAllEnvironmentalAudio() {
        // Cancel ongoing tasks
        fadeTask?.cancel()
        fadeTask = nil
        
        randomEventTask?.cancel()
        randomEventTask = nil
        
        isRandomEventsEnabled = false
        
        // Stop all audio sources
        for source in ambientLoops.values {
            source.stop()
        }
        ambientLoops.removeAll()
        
        for source in weatherSounds.values {
            source.stop()
        }
        weatherSounds.removeAll()
        
        for source in dynamicSources.values {
            source.stop()
        }
        dynamicSources.removeAll()
        
        for source in timeBasedSources.values {
            source.stop()
        }
        timeBasedSources.removeAll()
        
        // Clear resource cache if needed
        if performanceMode {
            resourceManager.clearCache()
        }
    }
    
    deinit {
        Task { @MainActor in
            stopAllEnvironmentalAudio()
        }
    }
 }

 // MARK: - Environmental Audio Manager
 @MainActor
 class EnvironmentalAudioManager: ObservableObject {
    static let shared = EnvironmentalAudioManager()
    
    @Published var currentPreset: EnvironmentalAudioPreset?
    @Published var isInitialized: Bool = false
    @Published var performanceMetrics: AudioPerformanceMetrics = AudioPerformanceMetrics()
    
    private var environmentalAudio: EnvironmentalAudio?
    private var spatialAudioEngine: SpatialAudioEngine?
    
    private init() {}
    
    func initialize() async {
        guard !isInitialized else { return }
        
        spatialAudioEngine = SpatialAudioEngine()
        
        if let engine = spatialAudioEngine {
            environmentalAudio = EnvironmentalAudio(spatialAudioEngine: engine)
            isInitialized = true
            
            // Start performance monitoring
            startPerformanceMonitoring()
        }
    }
    
    private func startPerformanceMonitoring() {
        Task {
            while isInitialized {
                if let engine = spatialAudioEngine {
                    performanceMetrics = engine.getPerformanceMetrics()
                }
                
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
            }
        }
    }
    
    func applyPreset(_ preset: EnvironmentalAudioPreset) {
        guard let environmentalAudio = environmentalAudio else { return }
        
        currentPreset = preset
        environmentalAudio.applyPreset(preset)
    }
    
    func transitionToPreset(_ preset: EnvironmentalAudioPreset, duration: TimeInterval = 3.0) {
        environmentalAudio?.transitionToPreset(preset, duration: duration)
    }
    
    func setBiome(_ biome: BiomeType) {
        environmentalAudio?.setBiome(biome)
    }
    
    func setWeather(_ weather: WeatherType, intensity: Float = 1.0) {
        environmentalAudio?.setWeather(weather, intensity: intensity)
    }
    
    func setTimeOfDay(_ time: TimeOfDay) {
        environmentalAudio?.setTimeOfDay(time)
    }
    
    func playEnvironmentalEvent(_ event: EnvironmentalEvent, at position: SIMD3<Float>, intensity: Float = 1.0) {
        environmentalAudio?.playEnvironmentalEvent(event, at: position, intensity: intensity)
    }
    
    func setListener(_ entity: Entity) {
        environmentalAudio?.setListener(entity)
    }
    
    func enablePerformanceMode(_ enabled: Bool) {
        environmentalAudio?.enablePerformanceMode(enabled)
    }
    
    func shutdown() {
        environmentalAudio?.stopAllEnvironmentalAudio()
        spatialAudioEngine?.shutdown()
        isInitialized = false
    }
 }
