//
//  Services/Audio/EnvironmentalAudio.swift
//  FinalStorm
//
//  Environmental audio system - fixed version without conflicts
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
    var ambientLoops: [String: SpatialAudioSource] = [:]
    var weatherSounds: [String: SpatialAudioSource] = [:]
    var dynamicSources: [UUID: SpatialAudioSource] = [:]
    private var timeBasedSources: [String: SpatialAudioSource] = [:]
    
    // Enhanced state management
    private var currentBiome: BiomeType = .grassland
    private var currentWeather: WeatherType = .clear
    private var timeOfDay: TimeOfDay = .day
    private var environmentType: EnvironmentType = .outdoor
    
    // Audio processing
    private var fadeTask: Task<Void, Never>?
    private var randomEventTask: Task<Void, Never>?
    var isRandomEventsEnabled: Bool = false
    
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
        occlusionCalculator = AudioOcclusionCalculator()
        spatialAudioEngine.setOcclusionCalculator(occlusionCalculator!)
        
        updateEnvironmentalSettings()
        await loadBiomeAmbientSounds()
        await startAmbientUpdateLoop()
        
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
        // Fixed: Compare with enum instead of TaskPriority
        performanceMode = (preset.qualitySettings.sampleRate < 44100)
        
        setBiome(preset.biome, transition: true)
        setWeather(preset.weather, intensity: 0.7)
        setTimeOfDay(preset.timeOfDay)
        
        // Update existing ambient and weather sources with new volumes
        updateAmbientVolumes()
        updateWeatherVolumes()
        
        spatialAudioEngine.updateQualitySettings(preset.qualitySettings)
        spatialAudioEngine.enableSpatialAudio(preset.spatialProcessing)
        
        if preset.enableRandomEvents {
            startRandomAmbientEvents(frequency: preset.eventFrequency)
        } else {
            stopRandomAmbientEvents()
        }
    }
    
    // MARK: - Volume Management Methods (Add these methods)
    private func setAmbientVolume(_ volume: Float) {
        self.ambientVolume = volume
        updateAmbientVolumes()
    }

    private func setWeatherVolume(_ volume: Float) {
        self.weatherVolume = volume
        updateWeatherVolumes()
    }

    private func updateAmbientVolumes() {
        for (_, source) in ambientLoops {
            source.setBaseVolume(ambientVolume)
        }
    }

    private func updateWeatherVolumes() {
        for (_, source) in weatherSounds {
            source.setBaseVolume(weatherVolume)
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
        
        for _ in 0..<steps {
            let newVolume = ambientVolume + volumeStep
            setAmbientVolume(newVolume)
            try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
        }
        
        applyPreset(preset)
    }
    
    // MARK: - Environment Management
    func setBiome(_ biome: BiomeType, transition: Bool = true) {
        guard biome != currentBiome else { return }
        
        let oldBiome = currentBiome
        currentBiome = biome
        environmentType = EnvironmentType.from(biome: biome)
        
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
        
        let weatherEnvironment = AudioWorldBridge.audioEnvironment(for: weather, timeOfDay: timeOfDay)
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
        spatialAudioEngine.updateEnvironmentalEffects(for: environmentType)
        applyBiomeFilters()
    }
    
    private func applyBiomeFilters() {
        switch currentBiome {
        // Fixed: Use .ocean instead of .underwater for BiomeType
        case .ocean:
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
            break
        }
    }
    
    // MARK: - Audio Loading
    private func getBiomeAmbientSounds(_ biome: BiomeType) -> [String: String] {
        switch biome {
        case .grassland:
            return [
                "wind_light": "ambient_wind_light",
                "birds_meadow": "ambient_birds_meadow",
                "grass_rustle": "ambient_grass_rustle"
            ]
            
        case .forest:
            return [
                "wind_trees": "ambient_wind_trees",
                "birds_forest": "ambient_birds_forest",
                "leaves_rustle": "ambient_leaves_rustle"
            ]
            
        case .desert:
            return [
                "wind_desert": "ambient_wind_desert",
                "sand_shift": "ambient_sand_shift"
            ]
            
        case .ocean:
            return [
                "waves_gentle": "ambient_waves_gentle",
                "wind_ocean": "ambient_wind_ocean",
                "seagulls": "ambient_seagulls"
            ]
            
        case .mountain:
            return [
                "wind_mountain": "ambient_wind_mountain",
                "echo_distant": "ambient_echo_distant"
            ]
            
        case .corrupted:
            return [
                "whispers_dark": "ambient_whispers_dark",
                "energy_corrupt": "ambient_energy_corrupt"
            ]
            
        case .tundra:
            return [
                "wind_arctic": "ambient_wind_arctic",
                "ice_crack": "ambient_ice_crack"
            ]
            
        case .swamp:
            return [
                "water_murky": "ambient_water_murky",
                "frogs_chorus": "ambient_frogs_chorus"
            ]
            
        case .volcanic:
            return [
                "lava_flow": "ambient_lava_flow",
                "rumble_deep": "ambient_rumble_deep"
            ]
            
        // Added missing cases:
        case .ethereal:
            return [
                "chimes_ethereal": "ambient_chimes_ethereal",
                "whispers_gentle": "ambient_whispers_gentle",
                "energy_pure": "ambient_energy_pure"
            ]
            
        case .arctic:
            return [
                "wind_polar": "ambient_wind_polar",
                "ice_creaking": "ambient_ice_creaking",
                "aurora_hum": "ambient_aurora_hum"
            ]
            
        case .jungle:
            return [
                "birds_tropical": "ambient_birds_tropical",
                "insects_buzz": "ambient_insects_buzz",
                "leaves_drip": "ambient_leaves_drip",
                "monkeys_distant": "ambient_monkeys_distant"
            ]
            
        case .mesa:
            return [
                "wind_canyon": "ambient_wind_canyon",
                "rocks_settle": "ambient_rocks_settle",
                "echo_mesa": "ambient_echo_mesa"
            ]
            
        case .crystal:
            return [
                "crystal_hum": "ambient_crystal_hum",
                "energy_resonant": "ambient_energy_resonant",
                "chimes_crystal": "ambient_chimes_crystal"
            ]
        }
    }
    
    // MARK: - Weather Audio System
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
            
            let spatialization: AudioSpatialization = .ambient
            
            let audioSource = spatialAudioEngine.createAudioSource(
                id: UUID(),
                position: SIMD3<Float>(0, 20, 0),
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
                "rain_drops": "weather_rain_drops"
            ]
            
        case .storm:
            return [
                "rain_heavy": "weather_rain_heavy",
                "thunder_distant": "weather_thunder_distant"
            ]
            
        case .discordantStorm:
            return [
                "storm_magical": "weather_storm_magical",
                "energy_chaotic": "weather_energy_chaotic"
            ]
            
        case .fog:
            return [
                "mist_thick": "weather_mist_thick"
            ]
            
        case .snow:
            return [
                "snow_falling": "weather_snow_falling",
                "wind_cold": "weather_wind_cold"
            ]
            
        case .sandstorm:
            return [
                "sand_whipping": "weather_sand_whipping"
            ]
            
        case .auroras:
            return [
                "aurora_hum": "weather_aurora_hum"
            ]
            
        // Added missing cases:
        case .harmonyShower:
            return [
                "harmony_droplets": "weather_harmony_droplets",
                "chimes_gentle": "weather_chimes_gentle",
                "energy_healing": "weather_energy_healing"
            ]
            
        case .voidMist:
            return [
                "void_whispers": "weather_void_whispers",
                "energy_dark": "weather_energy_dark",
                "mist_eerie": "weather_mist_eerie"
            ]
            
        case .blizzard:
            return [
                "snow_heavy": "weather_snow_heavy",
                "wind_howling": "weather_wind_howling",
                "ice_pelting": "weather_ice_pelting"
            ]
            
        case .heatWave:
            return [
                "air_shimmering": "weather_air_shimmering",
                "wind_hot": "weather_wind_hot"
            ]
            
        case .meteor:
            return [
                "meteors_falling": "weather_meteors_falling",
                "impacts_distant": "weather_impacts_distant",
                "wind_celestial": "weather_wind_celestial"
            ]
            
        case .eclipse:
            return [
                "silence_eerie": "weather_silence_eerie",
                "energy_cosmic": "weather_energy_cosmic"
            ]
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
                
                // Fixed: Use helper method instead of non-existent property
                let spatialization = getSpatializationForEvent(event)
                audioSource.setSpatialization(spatialization)
                dynamicSources[audioSource.id] = audioSource
                audioSource.play()
                
                Task {
                    let duration = audioSource.estimatedDuration
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    dynamicSources.removeValue(forKey: audioSource.id)
                    spatialAudioEngine.removeAudioSource(audioSource.id)
                }
                
            } catch {
                print("Failed to play environmental event \(event): \(error)")
            }
        }
    }

    // Add this helper method to the class
    private func getSpatializationForEvent(_ event: EnvironmentalEvent) -> AudioSpatialization {
        switch event {
        case .thunderStrike, .corruptionPulse, .voidRipple:
            return .positional(radius: 50.0) // Large area effects
        case .windGust, .songweaving, .magicalResonance:
            return .positional(radius: 30.0) // Medium area effects
        case .animalCall, .harmonyBoost, .echoCall, .birdSong:
            return .positional(radius: 20.0) // Localized effects
        case .waterDrop, .leafFall, .crystalChime, .waterFlow, .firecrackle:
            return .positional(radius: 10.0) // Small localized effects
        case .stoneShift, .silenceWhisper, .iceShatter:
            return .positional(radius: 15.0) // Medium localized effects
        }
    }
    
    private func getEnvironmentalEventAudio(_ event: EnvironmentalEvent) -> [String] {
        switch event {
        case .thunderStrike:
            return ["event_thunder_strike"]
        case .windGust:
            return ["event_wind_gust"]
        case .animalCall:
            return ["event_animal_call_1"]
        case .waterDrop:
            return ["event_water_drop"]
        case .leafFall:
            return ["event_leaf_fall"]
        case .stoneShift:
            return ["event_stone_shift"]
        case .magicalResonance:
            return ["event_magical_resonance"]
        case .corruptionPulse:
            return ["event_corruption_pulse"]
        case .songweaving:
            return ["event_songweaving"]
        case .harmonyBoost:
            return ["event_harmony_boost"]
        case .silenceWhisper:
            return ["event_silence_whisper"]
        case .echoCall:
            return ["event_echo_call"]
        case .crystalChime:
            return ["event_crystal_chime"]
        case .voidRipple:
            return ["event_void_ripple"]
        case .birdSong:
            return ["event_bird_song"]
        case .waterFlow:
            return ["event_water_flow"]
        case .firecrackle:
            return ["event_fire_crackle"]
        case .iceShatter:
            return ["event_ice_shatter"]
        }
    }
    
    // MARK: - Time-Based Audio
    private func updateAmbientForTimeOfDay() {
        let timeMultiplier = timeOfDay.lightLevel
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
        case .morning:
            await addMorningSounds()
        case .afternoon:
            await addAfternoonSounds()
        case .midnight:
            await addMidnightSounds()
        }
    }
    
    private func addDawnSounds() async {
        await playTimedAmbientSound("dawn_chorus", audioFile: "ambient_dawn_chorus", duration: 30.0, volume: 0.6)
    }
    
    private func addDaySounds() async {
        await playTimedAmbientSound("day_activity", audioFile: "ambient_day_activity", duration: 60.0, volume: 0.5)
    }
    
    private func addDuskSounds() async {
        await playTimedAmbientSound("evening_birds", audioFile: "ambient_evening_birds", duration: 20.0, volume: 0.5)
    }
    
    private func addMorningSounds() async {
        await playTimedAmbientSound("morning_activity", audioFile: "ambient_morning_activity", duration: 45.0, volume: 0.6)
    }

    private func addAfternoonSounds() async {
        await playTimedAmbientSound("afternoon_calm", audioFile: "ambient_afternoon_calm", duration: 60.0, volume: 0.5)
    }

    private func addMidnightSounds() async {
        await playTimedAmbientSound("midnight_silence", audioFile: "ambient_midnight_silence", duration: 120.0, volume: 0.2)
    }
    
    private func addNightSounds() async {
        await playTimedAmbientSound("night_creatures", audioFile: "ambient_night_creatures", duration: 60.0, volume: 0.4)
    }
    
    private func addLateNightSounds() async {
        await playTimedAmbientSound("deep_silence", audioFile: "ambient_deep_silence", duration: 120.0, volume: 0.2)
    }
    
    // MARK: - Random Events
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
        // Fixed: Create preferred events based on time of day instead of using non-existent property
        let preferredEvents = getPreferredEventsForTimeOfDay(timeOfDay)
        let biomeEvents = getBiomeSpecificEvents()
        let allEvents = preferredEvents + biomeEvents
        
        guard let randomEvent = allEvents.randomElement() else { return }
        
        // Fixed: Use fixed falloff distance instead of non-existent property
        let eventDistance: Float = 30.0 // Default falloff distance
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

    // Add this helper method
    private func getPreferredEventsForTimeOfDay(_ time: TimeOfDay) -> [EnvironmentalEvent] {
        switch time {
        case .dawn:
            return [.birdSong, .animalCall, .windGust]
        case .morning, .day:
            return [.birdSong, .animalCall, .windGust, .leafFall]
        case .afternoon:
            return [.animalCall, .windGust, .waterFlow]
        case .dusk:
            return [.animalCall, .windGust, .crystalChime]
        case .night:
            return [.silenceWhisper, .echoCall, .crystalChime]
        case .lateNight:
            return [.silenceWhisper, .voidRipple, .magicalResonance]
        case .midnight:
            return [.silenceWhisper, .voidRipple, .corruptionPulse]
        }
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
        if abs(currentAmbientLevel - targetAmbientLevel) > 0.01 {
            if currentAmbientLevel < targetAmbientLevel {
                currentAmbientLevel = min(targetAmbientLevel, currentAmbientLevel + fadeSpeed)
            } else {
                currentAmbientLevel = max(targetAmbientLevel, currentAmbientLevel - fadeSpeed)
            }
            
            dynamicAmbientLevel = currentAmbientLevel
            
            for source in ambientLoops.values {
                source.updateVolume()
            }
        }
    }
    
    private func updateListenerTracking() {
        guard let listener = listenerEntity else { return }
        
        let newPosition = listener.position
        let distance = simd_distance(newPosition, lastListenerPosition)
        
        if distance > 1.0 {
            lastListenerPosition = newPosition
            spatialAudioEngine.updateListenerPosition()
            updateDynamicSourcePositions(listenerPosition: newPosition)
        }
    }
    
    private func updateDynamicSourcePositions(listenerPosition: SIMD3<Float>) {
        for source in dynamicSources.values {
            let distance = simd_distance(source.position, listenerPosition)
            let maxDistance: Float = 50.0
            
            if distance > maxDistance {
                source.setVolume(0.0)
            } else {
                source.updateVolume()
            }
        }
    }
    
    // MARK: - Audio Fading (Complete implementation)
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

    // MARK: - Individual Sound Fading Methods
    private func fadeOutAmbientSound(_ soundName: String) async {
        guard let audioSource = ambientLoops[soundName] else { return }
        
        let steps = 20
        let stepDuration: TimeInterval = 0.05
        let initialVolume = audioSource.baseVolume
        
        for step in 0..<steps {
            let progress = Float(step) / Float(steps)
            let newVolume = initialVolume * (1.0 - progress)
            audioSource.setBaseVolume(newVolume)
            
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
        
        audioSource.stop()
        ambientLoops.removeValue(forKey: soundName)
    }

    private func fadeInAmbientSound(_ soundName: String) async {
        guard let audioSource = ambientLoops[soundName] else { return }
        
        let steps = 20
        let stepDuration: TimeInterval = 0.05
        let targetVolume = ambientVolume
        
        audioSource.setBaseVolume(0.0)
        audioSource.play()
        
        for step in 0...steps {
            let progress = Float(step) / Float(steps)
            let newVolume = targetVolume * progress
            audioSource.setBaseVolume(newVolume)
            
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
    }

    private func fadeOutWeatherSound(_ soundName: String) async {
        guard let audioSource = weatherSounds[soundName] else { return }
        
        let steps = 15
        let stepDuration: TimeInterval = 0.1
        let initialVolume = audioSource.baseVolume
        
        for step in 0..<steps {
            let progress = Float(step) / Float(steps)
            let newVolume = initialVolume * (1.0 - progress)
            audioSource.setBaseVolume(newVolume)
            
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
        
        audioSource.stop()
        weatherSounds.removeValue(forKey: soundName)
    }

    private func fadeInWeatherSound(_ soundName: String) async {
        guard let audioSource = weatherSounds[soundName] else { return }
        
        let steps = 15
        let stepDuration: TimeInterval = 0.1
        let targetVolume = weatherVolume
        
        audioSource.setBaseVolume(0.0)
        audioSource.play()
        
        for step in 0...steps {
            let progress = Float(step) / Float(steps)
            let newVolume = targetVolume * progress
            audioSource.setBaseVolume(newVolume)
            
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
    }

    // MARK: - Crossfade Operations
    private func crossfadeBiomeAudio(from oldBiome: BiomeType, to newBiome: BiomeType) async {
        // Start fading out old biome sounds
        let fadeOutTask = Task {
            await fadeOutBiomeSounds(oldBiome)
        }
        
        // Wait a moment, then start loading and fading in new biome sounds
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let fadeInTask = Task {
            await loadBiomeAmbientSounds()
            await fadeInBiomeSounds(newBiome)
        }
        
        // Wait for both operations to complete
        await fadeOutTask.value
        await fadeInTask.value
    }

    private func crossfadeWeatherAudio(from oldWeather: WeatherType, to newWeather: WeatherType, intensity: Float) async {
        // Fade out old weather sounds
        await fadeOutWeatherSounds(oldWeather)
        
        // Load and fade in new weather sounds
        await loadWeatherSounds(newWeather, intensity: intensity)
        await fadeInWeatherSounds(newWeather)
    }

    // MARK: - Ambient Sound Loading and Management
    private func loadBiomeAmbientSounds() async {
        let biomeAudio = getBiomeAmbientSounds(currentBiome)
        
        await withTaskGroup(of: Void.self) { group in
            for (soundName, audioFile) in biomeAudio {
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
            
            // Choose spatialization based on performance mode and sound type
            let spatialization: AudioSpatialization = performanceMode ? .ambient : .positional(radius: 30.0)
            
            let audioSource = spatialAudioEngine.createAudioSource(
                id: UUID(),
                position: SIMD3<Float>(0, 10, 0), // Elevated ambient position for better spatial effect
                audioResource: audioResource,
                category: .environment,
                volume: 0.0, // Start at 0 for smooth fade-in
                loop: true
            )
            
            audioSource.setSpatialization(spatialization)
            ambientLoops[soundName] = audioSource
            
            // Note: Don't auto-play here - let the fade-in methods handle playback
            // This allows for proper volume transitions
            
        } catch {
            print("Failed to load ambient sound \(soundName): \(error)")
        }
    }

    // MARK: - Time-Based Sound Management
    private func playTimedAmbientSound(_ soundName: String, audioFile: String, duration: TimeInterval, volume: Float) async {
        do {
            let audioFile = try await resourceManager.loadAudioResource(named: audioFile)
            let audioResource = try await AudioFileResource.load(contentsOf: audioFile.url)
            
            let audioSource = spatialAudioEngine.createAudioSource(
                id: UUID(),
                position: SIMD3<Float>(0, 15, 0),
                audioResource: audioResource,
                category: .environment,
                volume: volume * ambientVolume,
                loop: false
            )
            
            audioSource.setSpatialization(.ambient)
            timeBasedSources[soundName] = audioSource
            audioSource.play()
            
            // Auto-remove after duration
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                timeBasedSources.removeValue(forKey: soundName)
                spatialAudioEngine.removeAudioSource(audioSource.id)
            }
            
        } catch {
            print("Failed to load timed ambient sound \(soundName): \(error)")
        }
    }

    private func clearTimeBasedSounds() async {
        for (soundName, audioSource) in timeBasedSources {
            audioSource.stop()
            spatialAudioEngine.removeAudioSource(audioSource.id)
        }
        timeBasedSources.removeAll()
    }

    // MARK: - Ambient Level Management
    private func updateAmbientLevels() async {
        // Smooth transition towards target ambient level
        if abs(currentAmbientLevel - targetAmbientLevel) > 0.01 {
            if currentAmbientLevel < targetAmbientLevel {
                currentAmbientLevel = min(targetAmbientLevel, currentAmbientLevel + fadeSpeed)
            } else {
                currentAmbientLevel = max(targetAmbientLevel, currentAmbientLevel - fadeSpeed)
            }
            
            // Apply the new level to all ambient sources
            for (_, audioSource) in ambientLoops {
                audioSource.setBaseVolume(currentAmbientLevel)
            }
            
            // Update published property for UI
            dynamicAmbientLevel = currentAmbientLevel
        }
    }

    // MARK: - Listener Tracking
    private func updateListenerTracking() async {
        guard let listener = listenerEntity else { return }
        
        let currentPosition = listener.position
        let distance = simd_distance(currentPosition, lastListenerPosition)
        
        if distance > 5.0 { // Significant movement threshold
            lastListenerPosition = currentPosition
            
            // Update occlusion calculations for dynamic sources
            for (_, audioSource) in dynamicSources {
                if let occlusionData = occlusionCalculator?.calculateOcclusion(
                    from: currentPosition,
                    to: audioSource.position
                ) {
                    audioSource.setOcclusion(occlusionData)
                }
            }
        }
    }

    // MARK: - Random Ambient Events
    func startRandomAmbientEvents(frequency: TimeInterval) {
        guard !isRandomEventsEnabled else { return }
        
        isRandomEventsEnabled = true
        randomEventTask = Task { [weak self] in
            while !Task.isCancelled && self?.isRandomEventsEnabled == true {
                let jitter = frequency * 0.3 // Add some randomness
                let nextEventDelay = frequency + Double.random(in: -jitter...jitter)
                
                try? await Task.sleep(nanoseconds: UInt64(nextEventDelay * 1_000_000_000))
                
                if !Task.isCancelled && self?.isRandomEventsEnabled == true {
                    await self?.triggerRandomAmbientEvent()
                }
            }
        }
    }

    // MARK: - Performance Mode
    func enablePerformanceMode(_ enabled: Bool) {
        performanceMode = enabled
        
        if enabled {
            // Reduce number of simultaneous sounds
            let maxAmbientSounds = 3
            let maxWeatherSounds = 2
            
            // Stop excess ambient sounds
            if ambientLoops.count > maxAmbientSounds {
                let excessSounds = Array(ambientLoops.keys.dropFirst(maxAmbientSounds))
                for soundName in excessSounds {
                    ambientLoops[soundName]?.stop()
                    ambientLoops.removeValue(forKey: soundName)
                }
            }
            
            // Stop excess weather sounds
            if weatherSounds.count > maxWeatherSounds {
                let excessSounds = Array(weatherSounds.keys.dropFirst(maxWeatherSounds))
                for soundName in excessSounds {
                    weatherSounds[soundName]?.stop()
                    weatherSounds.removeValue(forKey: soundName)
                }
            }
            
            // Disable random events in performance mode
            stopRandomAmbientEvents()
        }
    }

    // MARK: - Cleanup and Resource Management
    func cleanup() {
        // Stop all tasks
        fadeTask?.cancel()
        randomEventTask?.cancel()
        
        // Stop and remove all audio sources
        for (_, audioSource) in ambientLoops {
            audioSource.stop()
        }
        ambientLoops.removeAll()
        
        for (_, audioSource) in weatherSounds {
            audioSource.stop()
        }
        weatherSounds.removeAll()
        
        for (_, audioSource) in dynamicSources {
            audioSource.stop()
        }
        dynamicSources.removeAll()
        
        for (_, audioSource) in timeBasedSources {
            audioSource.stop()
        }
        timeBasedSources.removeAll()
        
        // Reset state
        isRandomEventsEnabled = false
        currentAmbientLevel = 0.0
        targetAmbientLevel = 0.0
    }

    // MARK: - Public Interface Extensions
    func setListener(_ entity: Entity) {
        listenerEntity = entity
        lastListenerPosition = entity.position
    }

    func playEchoInteraction(echo: EchoType, at position: SIMD3<Float>) {
        let event: EnvironmentalEvent = .echoCall
        playEnvironmentalEvent(event, at: position, intensity: 0.8)
    }

    func playHarmonyEvent(at position: SIMD3<Float>, strength: Float) {
        let event: EnvironmentalEvent = .harmonyBoost
        playEnvironmentalEvent(event, at: position, intensity: strength)
    }

    func playCorruptionEvent(at position: SIMD3<Float>, intensity: Float) {
        let event: EnvironmentalEvent = .corruptionPulse
        playEnvironmentalEvent(event, at: position, intensity: intensity)
    }

    func playSongweavingEvent(at position: SIMD3<Float>, melody: MelodyType) {
        let event: EnvironmentalEvent = .songweaving
        playEnvironmentalEvent(event, at: position, intensity: 0.9)
    }

    // MARK: - Debug and Diagnostics
    // MARK: - Debug and Diagnostics
    func getAudioDiagnostics() -> EnvironmentalAudioDiagnostics {
        return EnvironmentalAudioDiagnostics(
            currentBiome: currentBiome,
            currentWeather: currentWeather,
            timeOfDay: timeOfDay,
            ambientSoundCount: ambientLoops.count,
            weatherSoundCount: weatherSounds.count,
            dynamicSoundCount: dynamicSources.count,
            timeBasedSoundCount: timeBasedSources.count,
            isRandomEventsEnabled: isRandomEventsEnabled,
            performanceMode: performanceMode,
            currentAmbientLevel: currentAmbientLevel,
            targetAmbientLevel: targetAmbientLevel
        )
    }

    deinit {
        // Cancel tasks synchronously
        fadeTask?.cancel()
        randomEventTask?.cancel()
        
        // For @MainActor isolated cleanup, we need to schedule it
        Task { @MainActor in
            self.cleanup()
        }
    }

} // Add this closing brace for the EnvironmentalAudio class
