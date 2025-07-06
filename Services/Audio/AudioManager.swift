//
// File Path: Services/Audio/AudioManager.swift
// Description: Core audio management system for FinalStorm
// Handles 3D spatial audio, music, sound effects, and voice
//

import Foundation
import AVFoundation
import Accelerate
import Combine

@MainActor
class AudioManager: ObservableObject {
    // MARK: - Properties
    @Published var masterVolume: Float = 1.0
    @Published var musicVolume: Float = 0.8
    @Published var effectsVolume: Float = 1.0
    @Published var voiceVolume: Float = 1.0
    @Published var ambientVolume: Float = 0.7
    
    private let audioEngine = AVAudioEngine()
    private let spatialAudioEngine: SpatialAudioEngine
    private let environmentalAudio: EnvironmentalAudio
    private let immersiveAudioSystem: ImmersiveAudioSystem
    
    // Audio Nodes
    private let masterMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private let effectsMixer = AVAudioMixerNode()
    private let voiceMixer = AVAudioMixerNode()
    private let ambientMixer = AVAudioMixerNode()
    
    // Audio Players
    private var musicPlayers: [String: AVAudioPlayerNode] = [:]
    private var effectPlayers: [AVAudioPlayerNode] = []
    private let maxEffectPlayers = 32
    
    // Audio Buffers
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    private let bufferCache = AudioBufferCache()
    
    // Voice Chat
    private var voiceEngine: AVAudioEngine?
    private var voiceInput: AVAudioInputNode?
    
    // MARK: - Initialization
    init() {
        self.spatialAudioEngine = SpatialAudioEngine(engine: audioEngine)
        self.environmentalAudio = EnvironmentalAudio()
        self.immersiveAudioSystem = ImmersiveAudioSystem()
        
        setupAudioEngine()
        setupAudioSession()
        createEffectPlayers()
    }
    
    // MARK: - Setup
    private func setupAudioEngine() {
        // Attach mixer nodes
        audioEngine.attach(masterMixer)
        audioEngine.attach(musicMixer)
        audioEngine.attach(effectsMixer)
        audioEngine.attach(voiceMixer)
        audioEngine.attach(ambientMixer)
        
        // Connect mixers to master
        audioEngine.connect(musicMixer, to: masterMixer, format: nil)
        audioEngine.connect(effectsMixer, to: masterMixer, format: nil)
        audioEngine.connect(voiceMixer, to: masterMixer, format: nil)
        audioEngine.connect(ambientMixer, to: masterMixer, format: nil)
        
        // Connect master to output
        audioEngine.connect(masterMixer, to: audioEngine.mainMixerNode, format: nil)
        
        // Set initial volumes
        updateVolumes()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            #if os(iOS)
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
            #else
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            #endif
            
            try session.setActive(true)
            
            // Configure for spatial audio
            if session.isMultichannelOutputSupported {
                try session.setPreferredOutputNumberOfChannels(6) // 5.1 surround
            }
            
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func createEffectPlayers() {
        for _ in 0..<maxEffectPlayers {
            let player = AVAudioPlayerNode()
            audioEngine.attach(player)
            audioEngine.connect(player, to: effectsMixer, format: nil)
            effectPlayers.append(player)
        }
    }
    
    // MARK: - Initialization
    func initialize() async {
        // Load audio resources
        await loadAudioResources()
        
        // Initialize subsystems
        await spatialAudioEngine.initialize()
        await environmentalAudio.initialize()
        await immersiveAudioSystem.initialize()
        
        // Start audio engine
        startEngine()
    }
    
    private func startEngine() {
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    // MARK: - Volume Control
    private func updateVolumes() {
        masterMixer.volume = masterVolume
        musicMixer.volume = musicVolume
        effectsMixer.volume = effectsVolume
        voiceMixer.volume = voiceVolume
        ambientMixer.volume = ambientVolume
    }
    
    func setMasterVolume(_ volume: Float) {
        masterVolume = volume.clamped(to: 0...1)
        updateVolumes()
    }
    
    func setMusicVolume(_ volume: Float) {
        musicVolume = volume.clamped(to: 0...1)
        updateVolumes()
    }
    
    func setEffectsVolume(_ volume: Float) {
        effectsVolume = volume.clamped(to: 0...1)
        updateVolumes()
    }
    
    // MARK: - Music Playback
    func playMusic(_ musicName: String, fadeIn: TimeInterval = 0) {
        guard let buffer = audioBuffers[musicName] else {
            // Try to load the music
            Task {
                if let loadedBuffer = await loadAudioFile(named: musicName) {
                    audioBuffers[musicName] = loadedBuffer
                    playMusic(musicName, fadeIn: fadeIn)
                }
            }
            return
        }
        
        // Create or reuse player
        let player = musicPlayers[musicName] ?? {
            let newPlayer = AVAudioPlayerNode()
            audioEngine.attach(newPlayer)
            audioEngine.connect(newPlayer, to: musicMixer, format: buffer.format)
            musicPlayers[musicName] = newPlayer
            return newPlayer
        }()
        
        // Schedule buffer
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        
        // Fade in if requested
        if fadeIn > 0 {
            player.volume = 0
            fadeVolume(of: player, to: 1.0, duration: fadeIn)
        }
    }
    
    func stopMusic(_ musicName: String, fadeOut: TimeInterval = 0) {
        guard let player = musicPlayers[musicName] else { return }
        
        if fadeOut > 0 {
            fadeVolume(of: player, to: 0, duration: fadeOut) {
                player.stop()
            }
        } else {
            player.stop()
        }
    }
    
    func crossfadeMusic(from currentMusic: String, to newMusic: String, duration: TimeInterval = 2.0) {
        stopMusic(currentMusic, fadeOut: duration)
        playMusic(newMusic, fadeIn: duration)
    }
    
    // MARK: - Sound Effects
    func playEffect(_ effectName: String, at position: SIMD3<Float>? = nil, volume: Float = 1.0) {
        guard let buffer = audioBuffers[effectName] else {
            // Try to load the effect
            Task {
                if let loadedBuffer = await loadAudioFile(named: effectName) {
                    audioBuffers[effectName] = loadedBuffer
                    playEffect(effectName, at: position, volume: volume)
                }
            }
            return
        }
        
        // Find available player
        guard let player = effectPlayers.first(where: { !$0.isPlaying }) else {
            print("No available effect players")
            return
        }
        
        // Apply 3D positioning if provided
        if let position = position {
            spatialAudioEngine.positionSound(player: player, at: position)
        }
        
        // Set volume and play
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
    
    func playRandomEffect(from group: String, at position: SIMD3<Float>? = nil) {
        let effects = getEffectsInGroup(group)
        if let randomEffect = effects.randomElement() {
            playEffect(randomEffect, at: position)
        }
    }
    
    // MARK: - Ambient Audio
    func setAmbientEnvironment(_ environment: AudioEnvironment) {
        environmentalAudio.setEnvironment(environment)
        
        // Update reverb and environmental effects
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(environment.reverbPreset)
        reverb.wetDryMix = environment.reverbMix
        
        audioEngine.attach(reverb)
        audioEngine.connect(ambientMixer, to: reverb, format: nil)
        audioEngine.connect(reverb, to: masterMixer, format: nil)
    }
    
    func playAmbientLoop(_ loopName: String, volume: Float = 1.0) {
        playMusic(loopName, fadeIn: 2.0) // Reuse music system for ambient loops
    }
    
    // MARK: - Voice Chat
    func startVoiceChat() {
        voiceEngine = AVAudioEngine()
        voiceInput = voiceEngine?.inputNode
        
        guard let voiceEngine = voiceEngine,
              let voiceInput = voiceInput else { return }
        
        // Setup voice processing
        let format = voiceInput.inputFormat(forBus: 0)
        
        voiceInput.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processVoiceInput(buffer)
        }
        
        do {
            try voiceEngine.start()
        } catch {
            print("Failed to start voice engine: \(error)")
        }
    }
    
    func stopVoiceChat() {
        voiceInput?.removeTap(onBus: 0)
        voiceEngine?.stop()
        voiceEngine = nil
        voiceInput = nil
    }
    
    private func processVoiceInput(_ buffer: AVAudioPCMBuffer) {
        // Apply noise suppression and voice enhancement
        let processedBuffer = applyVoiceProcessing(to: buffer)
        
        // Send to network
        NotificationCenter.default.post(
            name: .voiceDataReady,
            object: nil,
            userInfo: ["buffer": processedBuffer]
        )
    }
    
    func playVoiceData(_ data: Data, from playerId: UUID) {
        // Convert data to audio buffer
        guard let buffer = dataToAudioBuffer(data) else { return }
        
        // Get or create player for this user
        let player = getVoicePlayer(for: playerId)
        
        // Schedule and play
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
    
    // MARK: - 3D Audio
    func updateListenerPosition(_ position: SIMD3<Float>, orientation: simd_quatf) {
        spatialAudioEngine.updateListenerPosition(position, orientation: orientation)
    }
    
    func createPositionalAudioSource(at position: SIMD3<Float>) -> PositionalAudioSource {
        return spatialAudioEngine.createSource(at: position)
    }
    
    // MARK: - Audio Loading
    private func loadAudioResources() async {
        // Load common sound effects
        let commonEffects = [
            "ui_click", "ui_hover", "ui_open", "ui_close",
            "footstep_grass", "footstep_stone", "footstep_water",
            "pickup_item", "drop_item", "equip_item",
            "level_up", "achievement", "notification"
        ]
        
        await withTaskGroup(of: Void.self) { group in
            for effect in commonEffects {
                group.addTask { [weak self] in
                    if let buffer = await self?.loadAudioFile(named: effect) {
                        await MainActor.run {
                            self?.audioBuffers[effect] = buffer
                        }
                    }
                }
            }
        }
    }
    
    private func loadAudioFile(named name: String) async -> AVAudioPCMBuffer? {
        // Check cache first
        if let cachedBuffer = await bufferCache.getBuffer(for: name) {
            return cachedBuffer
        }
        
        // Load from bundle
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") ??
                       Bundle.main.url(forResource: name, withExtension: "wav") ??
                       Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("Audio file not found: \(name)")
            return nil
        }
        
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = UInt32(file.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            
            try file.read(into: buffer)
            
            // Cache the buffer
            await bufferCache.cache(buffer, for: name)
            
            return buffer
            
        } catch {
            print("Failed to load audio file \(name): \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    private func fadeVolume(of player: AVAudioPlayerNode, to targetVolume: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let steps = Int(duration * 60) // 60 steps per second
        let stepDuration = duration / Double(steps)
        let volumeStep = (targetVolume - player.volume) / Float(steps)
        
        var currentStep = 0
        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
            currentStep += 1
            player.volume += volumeStep
            
            if currentStep >= steps {
                timer.invalidate()
                player.volume = targetVolume
                completion?()
            }
        }
    }
    
    private func getEffectsInGroup(_ group: String) -> [String] {
        // Return effects based on group
        switch group {
        case "footsteps":
            return ["footstep_grass", "footstep_stone", "footstep_water", "footstep_sand"]
        case "ui":
            return ["ui_click", "ui_hover", "ui_open", "ui_close"]
        case "combat":
            return ["sword_swing", "arrow_shoot", "spell_cast", "shield_block"]
        default:
            return []
        }
    }
    
    private func applyVoiceProcessing(to buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Apply noise reduction and enhancement
        // This is a simplified version - real implementation would use DSP
        return buffer
    }
    
    private func dataToAudioBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        // Convert network data to audio buffer
        // Implementation depends on audio codec used
        return nil
    }
    
    private func getVoicePlayer(for playerId: UUID) -> AVAudioPlayerNode {
        // Get or create a player for voice chat
        let player = AVAudioPlayerNode()
        audioEngine.attach(player)
        audioEngine.connect(player, to: voiceMixer, format: nil)
        return player
    }
 }

 // MARK: - Audio Environment
 struct AudioEnvironment {
    let name: String
    let reverbPreset: AVAudioUnitReverbPreset
    let reverbMix: Float
    let ambientSounds: [String]
    let echoDelay: TimeInterval
    let filterCutoff: Float
    
    static let indoor = AudioEnvironment(
        name: "Indoor",
        reverbPreset: .mediumRoom,
        reverbMix: 30,
        ambientSounds: ["ambient_indoor"],
        echoDelay: 0.1,
        filterCutoff: 8000
    )
    
    static let outdoor = AudioEnvironment(
        name: "Outdoor",
        reverbPreset: .plate,
        reverbMix: 10,
        ambientSounds: ["ambient_outdoor", "wind", "birds"],
        echoDelay: 0.3,
        filterCutoff: 12000
    )
    
    static let cave = AudioEnvironment(
        name: "Cave",
        reverbPreset: .largeChamber,
        reverbMix: 60,
        ambientSounds: ["ambient_cave", "dripping_water"],
        echoDelay: 0.8,
        filterCutoff: 4000
    )
    
    static let underwater = AudioEnvironment(
        name: "Underwater",
        reverbPreset: .cathedral,
        reverbMix: 80,
        ambientSounds: ["ambient_underwater"],
        echoDelay: 0.05,
        filterCutoff: 2000
    )
 }

 // MARK: - Positional Audio Source
 class PositionalAudioSource {
    let id = UUID()
    var position: SIMD3<Float>
    var orientation: simd_quatf
    var radius: Float
    var volume: Float
    
    weak var player: AVAudioPlayerNode?
    
    init(position: SIMD3<Float>, radius: Float = 10.0) {
        self.position = position
        self.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        self.radius = radius
        self.volume = 1.0
    }
    
    func play(_ audioBuffer: AVAudioPCMBuffer) {
        player?.scheduleBuffer(audioBuffer, at: nil, options: [], completionHandler: nil)
        player?.play()
    }
    
    func stop() {
        player?.stop()
    }
 }

 // MARK: - Audio Buffer Cache
 actor AudioBufferCache {
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private let maxCacheSize = 100
    
    func getBuffer(for name: String) -> AVAudioPCMBuffer? {
        return cache[name]
    }
    
    func cache(_ buffer: AVAudioPCMBuffer, for name: String) {
        cache[name] = buffer
        
        // Evict old buffers if needed
        if cache.count > maxCacheSize {
            evictOldestBuffer()
        }
    }
    
    private func evictOldestBuffer() {
        // Simple eviction - remove first item
        if let firstKey = cache.keys.first {
            cache.removeValue(forKey: firstKey)
        }
    }
 }

 // MARK: - Notifications
 extension Notification.Name {
    static let voiceDataReady = Notification.Name("voiceDataReady")
 }

 // MARK: - Float Extension
 extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return max(range.lowerBound, min(self, range.upperBound))
    }
 }
