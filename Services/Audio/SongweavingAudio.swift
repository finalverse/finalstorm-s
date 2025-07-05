//
//  Services/Audio/SongweavingAudio.swift
//  FinalStorm
//
//  Enhanced songweaving audio system using consolidated audio types
//  Handles melody generation, harmony synthesis, and magical audio effects
//

import Foundation
import AVFoundation
import RealityKit
import Combine

@MainActor
class SongweavingAudio: ObservableObject {
    // MARK: - Properties
    @Published var isEnabled: Bool = true
    @Published var melodyVolume: Float = 1.0
    @Published var harmonyVolume: Float = 0.8
    @Published var resonanceVolume: Float = 0.6
    @Published var activeMelodyCount: Int = 0
    @Published var activeHarmonyCount: Int = 0
    
    private let spatialAudioEngine: SpatialAudioEngine
    private let audioSynthesizer: AudioSynthesizer
    private let harmonyProcessor: HarmonyProcessor
    private var activeMelodies: [UUID: PlayingMelody] = [:]
    private var activeHarmonies: [UUID: PlayingHarmony] = [:]
    
    // Audio synthesis parameters
    private let qualitySettings: AudioQualitySettings
    private var melodyPresets: [MelodyType: AudioTimbre] = [:]
    
    // Performance optimization
    private let maxConcurrentMelodies: Int = 8
    private let maxConcurrentHarmonies: Int = 3
    
    // MARK: - Initialization
    init(spatialAudioEngine: SpatialAudioEngine, qualitySettings: AudioQualitySettings = .high) {
        self.spatialAudioEngine = spatialAudioEngine
        self.audioSynthesizer = AudioSynthesizer(qualitySettings: qualitySettings)
        self.harmonyProcessor = HarmonyProcessor(qualitySettings: qualitySettings)
        self.qualitySettings = qualitySettings
        
        setupMelodyPresets()
    }
    
    private func setupMelodyPresets() {
        melodyPresets[.restoration] = AudioTimbre(
            waveform: .sine,
            harmonics: [1.0, 0.3, 0.1, 0.05],
            envelope: ADSREnvelope(attack: 0.1, decay: 0.2, sustain: 0.7, release: 0.5),
            effects: [.reverb(preset: .cathedral, wetDryMix: 0.3)]
        )
        
        melodyPresets[.exploration] = AudioTimbre(
            waveform: .triangle,
            harmonics: [1.0, 0.5, 0.2, 0.1, 0.05],
            envelope: ADSREnvelope(attack: 0.05, decay: 0.1, sustain: 0.8, release: 0.3),
            effects: [.echo(delay: 0.2, feedback: 0.3, wetDryMix: 0.2)]
        )
        
        melodyPresets[.creation] = AudioTimbre(
            waveform: .square,
            harmonics: [1.0, 0.8, 0.4, 0.2, 0.1],
            envelope: ADSREnvelope(attack: 0.2, decay: 0.3, sustain: 0.6, release: 0.8),
            effects: [.chorus(rate: 2.0, depth: 0.3, feedback: 0.2, wetDryMix: 0.4)]
        )
        
        melodyPresets[.protection] = AudioTimbre(
            waveform: .sawtooth,
            harmonics: [1.0, 0.6, 0.3, 0.15, 0.08],
            envelope: ADSREnvelope(attack: 0.3, decay: 0.2, sustain: 0.9, release: 1.0),
            effects: [.lowPass(frequency: 2000, resonance: 1.2)]
        )
        
        melodyPresets[.transformation] = AudioTimbre(
            waveform: .custom,
            harmonics: [1.0, 0.4, 0.8, 0.2, 0.6, 0.1, 0.3],
            envelope: ADSREnvelope(attack: 0.1, decay: 0.4, sustain: 0.5, release: 0.6),
            effects: [.distortion(preGain: 5, wetDryMix: 0.3), .highPass(frequency: 200, resonance: 1.0)]
        )
    }
    
    // MARK: - Melody Playback
    func playMelody(_ melody: Melody, at position: SIMD3<Float>, caster: Entity) async {
        // Check limits
        guard activeMelodies.count < maxConcurrentMelodies else {
            await stopOldestMelody()
        }
        
        let melodyId = UUID()
        
        // Generate audio for melody
        let audioData = await generateMelodyAudio(melody)
        
        guard let audioData = audioData else {
            print("Failed to generate melody audio")
            return
        }
        
        // Create spatial audio source
        let audioSource = spatialAudioEngine.createAudioSource(
            id: melodyId,
            position: position,
            audioResource: audioData,
            category: .songweaving,
            volume: melodyVolume * melody.strength,
            loop: false
        )
        
        // Configure spatialization based on melody type
        let spatialization = getSpatializationForMelody(melody.type)
        audioSource.setSpatialization(spatialization)
        
        // Create playing melody tracker
        let playingMelody = PlayingMelody(
            id: melodyId,
            melody: melody,
            caster: caster,
            audioSource: audioSource,
            startTime: Date()
        )
        
        activeMelodies[melodyId] = playingMelody
        activeMelodyCount = activeMelodies.count
        
        // Play the melody
        audioSource.play()
        
        // Add visual effects synchronized with audio
        await addMelodyVisualEffects(melody, at: position, duration: melody.duration)
        
        // Remove from active melodies after completion
        Task {
            try? await Task.sleep(nanoseconds: UInt64(melody.duration * 1_000_000_000))
            activeMelodies.removeValue(forKey: melodyId)
            activeMelodyCount = activeMelodies.count
            spatialAudioEngine.removeAudioSource(melodyId)
        }
    }
    
    func playHarmony(_ harmony: Harmony, participants: [Entity]) async {
        // Check limits
        guard activeHarmonies.count < maxConcurrentHarmonies else {
            await stopOldestHarmony()
        }
        
        let harmonyId = UUID()
        
        // Calculate center position of participants
        let centerPosition = calculateCenterPosition(participants)
        
        // Generate harmony audio from constituent melodies
        let harmonyAudio = await generateHarmonyAudio(harmony, participants: participants)
        
        guard let harmonyAudio = harmonyAudio else {
            print("Failed to generate harmony audio")
            return
        }
        
        // Create spatial audio source for harmony
        let audioSource = spatialAudioEngine.createAudioSource(
            id: harmonyId,
            position: centerPosition,
            audioResource: harmonyAudio,
            category: .songweaving,
            volume: harmonyVolume * harmony.strength,
            loop: false
        )
        
        // Configure harmony spatialization (larger radius than individual melodies)
        audioSource.setSpatialization(.positional(radius: 50.0))
        
        // Create playing harmony tracker
        let playingHarmony = PlayingHarmony(
            id: harmonyId,
            harmony: harmony,
            participants: participants,
            audioSource: audioSource,
            startTime: Date()
        )
        
        activeHarmonies[harmonyId] = playingHarmony
        activeHarmonyCount = activeHarmonies.count
        
        // Play the harmony
        audioSource.play()
        
        // Add enhanced visual effects for harmony
        await addHarmonyVisualEffects(harmony, at: centerPosition, participants: participants)
        
        // Apply harmony effects to environment
        await applyHarmonyEnvironmentalEffects(harmony, at: centerPosition)
        
        // Remove from active harmonies after completion
        Task {
            try? await Task.sleep(nanoseconds: UInt64(harmony.duration * 1_000_000_000))
            activeHarmonies.removeValue(forKey: harmonyId)
            activeHarmonyCount = activeHarmonies.count
            spatialAudioEngine.removeAudioSource(harmonyId)
        }
    }
    
    // MARK: - Audio Generation
    private func generateMelodyAudio(_ melody: Melody) async -> AudioFileResource? {
        let notes = getMelodyNotes(for: melody.type)
        let timbre = melodyPresets[melody.type] ?? melodyPresets[.restoration]!
        
        do {
            let audioData = await audioSynthesizer.synthesizeMelody(
                notes: notes,
                timbre: timbre,
                volume: melody.strength,
                tempo: getMelodyTempo(melody.type)
            )
            
            // Create temporary file and convert to AudioFileResource
            let tempURL = await createTempAudioFile(data: audioData, format: .wav)
            return try await AudioFileResource.load(contentsOf: tempURL)
        } catch {
            print("Failed to generate melody audio: \(error)")
            return nil
        }
    }
    
    private func generateHarmonyAudio(_ harmony: Harmony, participants: [Entity]) async -> AudioFileResource? {
        // Generate individual melody lines for each participant
        var melodyLines: [MelodyLine] = []
        
        // Base melody
        let baseMelody = getMelodyNotes(for: .restoration)
        melodyLines.append(MelodyLine(notes: baseMelody, voice: 0, volume: 1.0))
        
        // Add harmonic voices based on participant count
        for (index, _) in participants.enumerated() {
            let harmonicInterval = getHarmonicInterval(index + 1)
            let harmonicNotes = transposeNotes(baseMelody, by: harmonicInterval)
            let voice = index + 1
            let volume = calculateHarmonyVoiceVolume(voice: voice, totalVoices: participants.count)
            
            melodyLines.append(MelodyLine(notes: harmonicNotes, voice: voice, volume: volume))
        }
        
        do {
            let audioData = await harmonyProcessor.synthesizeHarmony(
                melodyLines: melodyLines,
                strength: harmony.strength,
                blendFactor: Float(participants.count) * 0.15
            )
            
            let tempURL = await createTempAudioFile(data: audioData, format: .wav)
            return try await AudioFileResource.load(contentsOf: tempURL)
        } catch {
            print("Failed to generate harmony audio: \(error)")
            return nil
        }
    }
    
    private func getMelodyNotes(for type: MelodyType) -> [MelodyNote] {
        switch type {
        case .restoration:
            return [
                MelodyNote(frequency: 440, duration: 0.5, volume: 1.0), // A4
                MelodyNote(frequency: 523, duration: 0.5, volume: 0.9), // C5
                MelodyNote(frequency: 659, duration: 0.5, volume: 0.8), // E5
                MelodyNote(frequency: 523, duration: 0.5, volume: 0.9), // C5
                MelodyNote(frequency: 440, duration: 1.0, volume: 1.0)  // A4
            ]
            
        case .exploration:
            return [
                MelodyNote(frequency: 392, duration: 0.3, volume: 0.8), // G4
                MelodyNote(frequency: 440, duration: 0.3, volume: 0.9), // A4
                MelodyNote(frequency: 494, duration: 0.3, volume: 1.0), // B4
                MelodyNote(frequency: 523, duration: 0.3, volume: 1.0), // C5
                MelodyNote(frequency: 587, duration: 0.6, volume: 0.9), // D5
                MelodyNote(frequency: 659, duration: 0.4, volume: 0.8)  // E5
            ]
            
        case .creation:
            return [
                MelodyNote(frequency: 523, duration: 0.4, volume: 1.0), // C5
                MelodyNote(frequency: 659, duration: 0.4, volume: 1.0), // E5
                MelodyNote(frequency: 784, duration: 0.4, volume: 1.0), // G5
                MelodyNote(frequency: 1047, duration: 0.3, volume: 0.9), // C6
                MelodyNote(frequency: 784, duration: 0.4, volume: 0.8), // G5
                MelodyNote(frequency: 659, duration: 0.4, volume: 0.9), // E5
                MelodyNote(frequency: 523, duration: 0.8, volume: 1.0)  // C5
            ]
            
        case .protection:
            return [
                MelodyNote(frequency: 349, duration: 0.6, volume: 1.0), // F4
                MelodyNote(frequency: 440, duration: 0.6, volume: 1.0), // A4
                MelodyNote(frequency: 523, duration: 0.6, volume: 1.0), // C5
                MelodyNote(frequency: 698, duration: 0.4, volume: 0.9), // F5
                MelodyNote(frequency: 523, duration: 0.6, volume: 0.8), // C5
                MelodyNote(frequency: 440, duration: 0.6, volume: 0.8), // A4
                MelodyNote(frequency: 349, duration: 0.8, volume: 1.0)  // F4
            ]
            
        case .transformation:
            return [
                MelodyNote(frequency: 466, duration: 0.3, volume: 0.7), // A#4
                MelodyNote(frequency: 554, duration: 0.3, volume: 0.9), // C#5
                MelodyNote(frequency: 622, duration: 0.3, volume: 1.0), // D#5
                MelodyNote(frequency: 698, duration: 0.3, volume: 1.0), // F5
                MelodyNote(frequency: 831, duration: 0.3, volume: 1.0), // G#5
                MelodyNote(frequency: 932, duration: 0.3, volume: 0.9), // A#5
                MelodyNote(frequency: 698, duration: 0.6, volume: 0.8)  // F5
            ]
        }
    }
    
    private func getMelodyTempo(_ type: MelodyType) -> Float {
        switch type {
        case .restoration:
            return 72.0  // Slow, peaceful
        case .exploration:
            return 120.0 // Moderate, curious
        case .creation:
            return 100.0 // Moderate, building
        case .protection:
            return 80.0  // Steady, strong
        case .transformation:
            return 140.0 // Fast, dynamic
        }
    }
    
    private func getSpatializationForMelody(_ type: MelodyType) -> AudioSpatialization {
        switch type {
        case .restoration:
            return .positional(radius: 20.0) // Gentle, local effect
        case .exploration:
            return .positional(radius: 35.0) // Wide-reaching discovery
        case .creation:
            return .positional(radius: 25.0) // Creative energy spreads
        case .protection:
            return .positional(radius: 15.0) // Focused, protective barrier
        case .transformation:
            return .positional(radius: 40.0) // Far-reaching transformation
        }
    }
    
    private func getHarmonicInterval(_ voiceIndex: Int) -> Float {
        // Return harmonic intervals (in semitones) for different voice parts
        let intervals: [Float] = [0, 4, 7, 10, 12, 16, 19] // Unison, Major 3rd, Perfect 5th, Minor 7th, Octave, etc.
        return intervals[voiceIndex % intervals.count]
    }
    
    private func transposeNotes(_ notes: [MelodyNote], by semitones: Float) -> [MelodyNote] {
        let multiplier = pow(2.0, semitones / 12.0)
        return notes.map { note in
            MelodyNote(
                frequency: note.frequency * multiplier,
                duration: note.duration,
                volume: note.volume * 0.7, // Reduce volume for harmony parts
                timbre: note.timbre
            )
        }
    }
    
    private func calculateHarmonyVoiceVolume(voice: Int, totalVoices: Int) -> Float {
        // Lead voice (0) gets full volume, harmony voices get reduced volume
        if voice == 0 {
            return 1.0
        } else {
            let reduction = 0.3 + (0.4 / Float(totalVoices)) // Volume reduction based on voice count
            return 1.0 - (Float(voice) * reduction / Float(totalVoices))
        }
    }
    
    // MARK: - Visual Effects Integration
    private func addMelodyVisualEffects(_ melody: Melody, at position: SIMD3<Float>, duration: TimeInterval) async {
        let noteCount = 8
        let noteSpacing: Float = 0.3
        let colorVariation = melody.harmonyColor
        
        for i in 0..<noteCount {
            let delay = Double(i) * (duration / Double(noteCount))
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                await createVisualNote(
                    at: position + SIMD3<Float>(
                        Float.random(in: -noteSpacing...noteSpacing),
                        Float(i) * 0.1,
                        Float.random(in: -noteSpacing...noteSpacing)
                    ),
                    color: colorVariation,
                    size: 0.05 + Float(i) * 0.008,
                    melody: melody.type
                )
            }
        }
    }
    
    private func addHarmonyVisualEffects(_ harmony: Harmony, at position: SIMD3<Float>, participants: [Entity]) async {
        // Create connecting energy beams between participants
        for participant in participants {
            await createHarmonyBeam(from: participant.position, to: position, strength: harmony.strength)
        }
        
        // Create central harmony nexus
        await createHarmonyNexus(at: position, strength: harmony.strength, duration: harmony.duration, participantCount: participants.count)
        
        // Create individual participant auras
        for participant in participants {
            await createParticipantAura(at: participant.position, strength: harmony.strength * 0.6)
        }
    }
    
    private func createVisualNote(at position: SIMD3<Float>, color: CodableColor, size: Float, melody: MelodyType) async {
        let noteEntity = Entity()
        
        // Create note mesh based on melody type
        let noteMesh = createMelodySpecificMesh(melody: melody, size: size)
        let noteMaterial = createGlowingMaterial(color: color, intensity: 1.0)
        
        noteEntity.components.set(ModelComponent(mesh: noteMesh, materials: [noteMaterial]))
        noteEntity.position = position
        
        // Add melody-specific animation
        let animation = createMelodyAnimation(melody: melody)
        if let animationResource = try? AnimationResource.generate(with: animation) {
            noteEntity.playAnimation(animationResource)
        }
        
        // Add floating animation
        let floatHeight: Float = 2.0 + Float.random(in: -0.5...0.5)
        let targetPosition = position + SIMD3<Float>(0, floatHeight, 0)
        
        noteEntity.move(
            to: Transform(translation: targetPosition),
            relativeTo: nil,
            duration: 3.0
        )
        
        // Add to scene
        NotificationCenter.default.post(name: .addVisualEffect, object: noteEntity)
        
        // Remove after animation
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            NotificationCenter.default.post(name: .removeVisualEffect, object: noteEntity)
        }
    }
    
    private func createMelodySpecificMesh(melody: MelodyType, size: Float) -> MeshResource {
        switch melody {
        case .restoration:
            return .generateSphere(radius: size)
        case .exploration:
            return .generateBox(size: size, height: size * 1.5, depth: size)
        case .creation:
            return .generateCone(height: size * 2, radius: size)
        case .protection:
            return .generateCylinder(height: size, radius: size * 1.2)
        case .transformation:
            // Create a more complex shape for transformation
            return .generateTorus(meanRadius: size, tubeRadius: size * 0.3)
        }
    }
    
    private func createMelodyAnimation(melody: MelodyType) -> FromToByAnimation<Transform> {
        switch melody {
        case .restoration:
            // Gentle pulsing
            return FromToByAnimation(
                from: Transform(scale: [0.8, 0.8, 0.8]),
                to: Transform(scale: [1.2, 1.2, 1.2]),
                duration: 2.0,
                bindTarget: .transform
            )
            
        case .exploration:
            // Spinning motion
            return FromToByAnimation(
                by: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
                duration: 3.0,
                bindTarget: .transform
            )
            
        case .creation:
            // Growing animation
            return FromToByAnimation(
                from: Transform(scale: [0.1, 0.1, 0.1]),
                to: Transform(scale: [1.5, 1.5, 1.5]),
                duration: 2.5,
                bindTarget: .transform
            )
            
        case .protection:
            // Steady, strong presence
            return FromToByAnimation(
                from: Transform(scale: [1.0, 1.0, 1.0]),
                to: Transform(scale: [1.1, 1.1, 1.1]),
                duration: 4.0,
                bindTarget: .transform
            )
            
        case .transformation:
            // Complex morphing animation
            return FromToByAnimation(
                by: Transform(
                    scale: [1.3, 0.7, 1.3],
                    rotation: simd_quatf(angle: .pi, axis: [1, 1, 0])
                ),
                duration: 1.5,
                bindTarget: .transform
            )
        }
    }
    
    private func createHarmonyBeam(from start: SIMD3<Float>, to end: SIMD3<Float>, strength: Float) async {
        let beamEntity = Entity()
        
        let distance = simd_distance(start, end)
        let beamMesh = MeshResource.generateCylinder(height: distance, radius: 0.03 * strength)
        let beamMaterial = createEnergyMaterial(strength: strength)
        
        beamEntity.components.set(ModelComponent(mesh: beamMesh, materials: [beamMaterial]))
        
        // Position and orient beam
        let midpoint = (start + end) / 2
        beamEntity.position = midpoint
        
        let direction = normalize(end - start)
        let rotation = simd_quatf(from: [0, 1, 0], to: direction)
        beamEntity.orientation = rotation
        
        // Add energy flow animation
        let pulseAnimation = FromToByAnimation(
            from: Transform(scale: [0.5, 1, 0.5]),
            to: Transform(scale: [1.5, 1, 1.5]),
            duration: 0.8,
            bindTarget: .transform
        )
        
        if let animationResource = try? AnimationResource.generate(with: pulseAnimation) {
            beamEntity.playAnimation(animationResource.repeat(autoreverses: true))
        }
        
        NotificationCenter.default.post(name: .addVisualEffect, object: beamEntity)
        
        // Remove after harmony duration
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            NotificationCenter.default.post(name: .removeVisualEffect, object: beamEntity)
        }
    }
    
    private func createHarmonyNexus(at position: SIMD3<Float>, strength: Float, duration: TimeInterval, participantCount: Int) async {
        let nexusEntity = Entity()
        
        // Create multi-layered nexus
        let coreRadius = 0.3 * strength
        let coreMesh = MeshResource.generateSphere(radius: coreRadius)
        let coreMaterial = createHarmonyNexusMaterial(strength: strength, layer: .core)
        
        let coreModel = ModelEntity(mesh: coreMesh, materials: [coreMaterial])
        nexusEntity.addChild(coreModel)
        
        // Add outer rings based on participant count
        for i in 1...min(participantCount, 5) {
            let ringRadius = coreRadius + Float(i) * 0.2
            let ringMesh = MeshResource.generateTorus(meanRadius: ringRadius, tubeRadius: 0.02)
            let ringMaterial = createHarmonyNexusMaterial(strength: strength * 0.7, layer: .ring(i))
            
            let ringModel = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
            ringModel.orientation = simd_quatf(angle: Float(i) * .pi / 3, axis: [1, 0, 1])
            nexusEntity.addChild(ringModel)
            
            // Add rotation to rings
            let ringRotation = FromToByAnimation(
                by: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
                duration: 4.0 + Double(i),
                bindTarget: .transform
            )
            
            if let rotationResource = try? AnimationResource.generate(with: ringRotation) {
                ringModel.playAnimation(rotationResource.repeat())
            }
        }
        
        nexusEntity.position = position
        
        // Add core particle effects
        var particles = ParticleEmitterComponent()
        particles.birthRate = 150 * strength
        particles.emitterShape = .sphere
        particles.mainEmitter.lifeSpan = 3.0
        particles.mainEmitter.speed = 2.0
        particles.mainEmitter.size = 0.02
        particles.mainEmitter.color = .evolving(
            start: .single(.white),
            end: .single(.cyan)
        )
        particles.mainEmitter.opacityOverLife = .linearFade
        
        nexusEntity.components.set(particles)
        
        // Add overall nexus rotation
        let nexusRotation = FromToByAnimation(
            by: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
            duration: 6.0,
            bindTarget: .transform
        )
        
        if let rotationResource = try? AnimationResource.generate(with: nexusRotation) {
            nexusEntity.playAnimation(rotationResource.repeat())
        }
        
        NotificationCenter.default.post(name: .addVisualEffect, object: nexusEntity)
        
        // Remove after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            NotificationCenter.default.post(name: .removeVisualEffect, object: nexusEntity)
        }
    }
    
    private func createParticipantAura(at position: SIMD3<Float>, strength: Float) async {
        let auraEntity = Entity()
        
        let auraRadius = 1.0 * strength
        let auraMesh = MeshResource.generateSphere(radius: auraRadius)
        let auraMaterial = createAuraMaterial(strength: strength)
        
        auraEntity.components.set(ModelComponent(mesh: auraMesh, materials: [auraMaterial]))
        auraEntity.position = position
        
        // Add gentle pulsing
        let pulseAnimation = FromToByAnimation(
            from: Transform(scale: [0.8, 0.8, 0.8]),
            to: Transform(scale: [1.2, 1.2, 1.2]),
            duration: 2.0,
            bindTarget: .transform
        )
        
        if let animationResource = try? AnimationResource.generate(with: pulseAnimation) {
            auraEntity.playAnimation(animationResource.repeat(autoreverses: true))
        }
        
        NotificationCenter.default.post(name: .addVisualEffect, object: auraEntity)
        
        // Remove after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            NotificationCenter.default.post(name: .removeVisualEffect, object: auraEntity)
        }
    }
    
    // MARK: - Environmental Effects
    private func applyHarmonyEnvironmentalEffects(_ harmony: Harmony, at position: SIMD3<Float>) async {
        // Apply audio filter effects to the environment based on harmony strength
        let filterStrength = harmony.strength
        
        // Enhance reverb for stronger harmonies
        spatialAudioEngine.applyAudioFilter(.reverb(preset: .cathedral, wetDryMix: 0.2 + filterStrength * 0.3))
        
        // Add subtle chorus effect
        spatialAudioEngine.applyAudioFilter(.chorus(rate: 1.5, depth: 0.2, feedback: 0.1, wetDryMix: filterStrength * 0.2))
        
        // Temporarily boost high frequencies for magical sparkle
        spatialAudioEngine.applyAudioFilter(.highPass(frequency: 2000, resonance: 0.8))
        
        // Reset effects after harmony duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(harmony.duration * 1_000_000_000))
            await resetEnvironmentalEffects()
        }
    }
    
    private func resetEnvironmentalEffects() async {
        // Reset environmental effects to default
        spatialAudioEngine.applyAudioFilter(.reverb(preset: .mediumHall, wetDryMix: 0.3))
    }
    
    // MARK: - Material Creation
    private func createGlowingMaterial(color: CodableColor, intensity: Float = 1.0) -> Material {
        var material = UnlitMaterial()
        
        #if canImport(UIKit)
        material.color = .init(tint: UIColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        ))
        #elseif canImport(AppKit)
        material.color = .init(tint: NSColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        ))
        #endif
        
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        return material
    }
    
    private func createEnergyMaterial(strength: Float) -> Material {
        var material = UnlitMaterial()
        
        #if canImport(UIKit)
        let baseColor = UIColor.cyan.withAlphaComponent(0.7 + strength * 0.2)
        #elseif canImport(AppKit)
        let baseColor = NSColor.cyan.withAlphaComponent(0.7 + strength * 0.2)
        #endif
        
        material.color = .init(tint: baseColor)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        return material
    }
    
    private func createHarmonyNexusMaterial(strength: Float, layer: NexusLayer) -> Material {
        var material = PhysicallyBasedMaterial()
        
        let alpha: Float
        let emissiveIntensity: Float
        
        switch layer {
        case .core:
            alpha = 0.4
            emissiveIntensity = strength * 3.0
        case .ring(let index):
            alpha = 0.2 + (0.1 / Float(index))
            emissiveIntensity = strength * (2.0 / Float(index))
        }
        
        #if canImport(UIKit)
        material.baseColor = .init(tint: UIColor.white.withAlphaComponent(alpha))
        material.emissiveColor = .init(color: UIColor.cyan)
        #elseif canImport(AppKit)
        material.baseColor = .init(tint: NSColor.white.withAlphaComponent(alpha))
        material.emissiveColor = .init(color: NSColor.cyan)
        #endif
        
        material.emissiveIntensity = emissiveIntensity
        material.blending = .transparent(opacity: .init(floatLiteral: alpha))
        material.metallic = 0.0
        material.roughness = 0.1
        
        return material
    }
    
    private func createAuraMaterial(strength: Float) -> Material {
        var material = UnlitMaterial()
        
        #if canImport(UIKit)
        let color = UIColor.systemBlue.withAlphaComponent(0.3 + strength * 0.2)
        #elseif canImport(AppKit)
        let color = NSColor.systemBlue.withAlphaComponent(0.3 + strength * 0.2)
        #endif
        
        material.color = .init(tint: color)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        return material
    }
    
    // MARK: - Utility Methods
    private func calculateCenterPosition(_ entities: [Entity]) -> SIMD3<Float> {
        guard !entities.isEmpty else { return SIMD3<Float>(0, 0, 0) }
        
        let sum = entities.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1.position }
        return sum / Float(entities.count)
    }
    
    private func createTempAudioFile(data: Data, format: AudioFormat) async -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileExtension = getFileExtension(for: format)
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        
        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to write audio file: \(error)")
        }
        
        return fileURL
    }
    
    private func getFileExtension(for format: AudioFormat) -> String {
        switch format {
        case .wav:
            return "wav"
        case .mp4:
            return "m4a"
        case .ogg:
            return "ogg"
        case .unknown:
            return "wav"
        }
    }
    
    // MARK: - Performance Management
    private func stopOldestMelody() async {
        guard let oldestMelody = activeMelodies.values.min(by: { $0.startTime < $1.startTime }) else { return }
        
        oldestMelody.audioSource.stop()
        activeMelodies.removeValue(forKey: oldestMelody.id)
        activeMelodyCount = activeMelodies.count
        spatialAudioEngine.removeAudioSource(oldestMelody.id)
    }
    
    private func stopOldestHarmony() async {
        guard let oldestHarmony = activeHarmonies.values.min(by: { $0.startTime < $1.startTime }) else { return }
        
        oldestHarmony.audioSource.stop()
        activeHarmonies.removeValue(forKey: oldestHarmony.id)
        activeHarmonyCount = activeHarmonies.count
        spatialAudioEngine.removeAudioSource(oldestHarmony.id)
    }
    
    // MARK: - Active Audio Management
    func stopAllMelodies() {
        for melody in activeMelodies.values {
            melody.audioSource.stop()
            spatialAudioEngine.removeAudioSource(melody.id)
        }
        activeMelodies.removeAll()
        activeMelodyCount = 0
    }
    
    func stopAllHarmonies() {
        for harmony in activeHarmonies.values {
            harmony.audioSource.stop()
            spatialAudioEngine.removeAudioSource(harmony.id)
        }
        activeHarmonies.removeAll()
        activeHarmonyCount = 0
    }
    
    func stopMelody(_ melodyId: UUID) {
        if let melody = activeMelodies[melodyId] {
            melody.audioSource.stop()
            activeMelodies.removeValue(forKey: melodyId)
            activeMelodyCount = activeMelodies.count
            spatialAudioEngine.removeAudioSource(melodyId)
        }
    }
    
    func stopHarmony(_ harmonyId: UUID) {
        if let harmony = activeHarmonies[harmonyId] {
            harmony.audioSource.stop()
            activeHarmonies.removeValue(forKey: harmonyId)
            activeHarmonyCount = activeHarmonies.count
            spatialAudioEngine.removeAudioSource(harmonyId)
        }
    }
    
    // MARK: - Volume Control
    func setMelodyVolume(_ volume: Float) {
        melodyVolume = volume
        spatialAudioEngine.setCategoryVolume(.songweaving, volume: volume)
    }
    
    func setHarmonyVolume(_ volume: Float) {
        harmonyVolume = volume
        // Harmonies use the same category but with different base volume
        updateHarmonyVolumes()
    }
    
    private func updateHarmonyVolumes() {
        for harmony in activeHarmonies.values {
            harmony.audioSource.setBaseVolume(harmonyVolume * harmony.harmony.strength)
        }
    }
    
    // MARK: - Audio Quality Management
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        audioSynthesizer.updateQualitySettings(settings)
        harmonyProcessor.updateQualitySettings(settings)
    }
    
    // MARK: - Performance Metrics
    func getPerformanceInfo() -> SongweavingPerformanceInfo {
        return SongweavingPerformanceInfo(
            activeMelodies: activeMelodyCount,
            activeHarmonies: activeHarmonyCount,
            maxMelodies: maxConcurrentMelodies,
            maxHarmonies: maxConcurrentHarmonies,
            synthesisLoad: audioSynthesizer.getCurrentLoad(),
            memoryUsage: calculateMemoryUsage()
        )
    }
    
    private func calculateMemoryUsage() -> Float {
        // Simplified memory usage calculation
        let melodyMemory = Float(activeMelodies.count) * 0.2 // MB per melody
        let harmonyMemory = Float(activeHarmonies.count) * 0.5 // MB per harmony
        return melodyMemory + harmonyMemory
    }
 }

 // MARK: - Enhanced Audio Synthesis Classes
 class AudioSynthesizer {
    private let qualitySettings: AudioQualitySettings
    private var currentLoad: Float = 0.0
    
    init(qualitySettings: AudioQualitySettings) {
        self.qualitySettings = qualitySettings
    }
    
    func synthesizeMelody(notes: [MelodyNote], timbre: AudioTimbre, volume: Float, tempo: Float) async -> Data {
        currentLoad = 0.8 // Simulate synthesis load
        
        let sampleRate = Float(qualitySettings.sampleRate)
        var audioSamples: [Float] = []
        
        let beatDuration = 60.0 / tempo // Duration of one beat in seconds
        
        for note in notes {
            let noteDuration = note.duration * beatDuration
            let noteSamples = generateNoteSamples(
                frequency: note.frequency,
                duration: noteDuration,
                volume: note.volume * volume,
                timbre: timbre,
                sampleRate: sampleRate
            )
            audioSamples.append(contentsOf: noteSamples)
        }
        
        currentLoad = 0.0
        return convertSamplesToData(audioSamples, sampleRate: sampleRate)
    }
    
    private func generateNoteSamples(
        frequency: Float,
        duration: TimeInterval,
        volume: Float,
        timbre: AudioTimbre,
        sampleRate: Float
    ) -> [Float] {
        let sampleCount = Int(Float(duration) * sampleRate)
        var samples: [Float] = []
        
        for i in 0..<sampleCount {
            let time = Float(i) / sampleRate
            let phase = 2.0 * Float.pi * frequency * time
            
            // Generate base waveform with harmonics
            var sample: Float = 0
            let harmonics = timbre.harmonics.isEmpty ? timbre.waveform.harmonicContent : timbre.harmonics
            
            for (harmonicIndex, harmonicStrength) in harmonics.enumerated() {
                let harmonicFreq = frequency * Float(harmonicIndex + 1)
                let harmonicPhase = 2.0 * Float.pi * harmonicFreq * time
                
                let harmonicSample: Float
                switch timbre.waveform {
                case .sine:
                    harmonicSample = sin(harmonicPhase)
                case .triangle:
                    harmonicSample = 2.0 * asin(sin(harmonicPhase)) / Float.pi
                case .square:
                    harmonicSample = sin(harmonicPhase) > 0 ? 1.0 : -1.0
                case .sawtooth:
                    harmonicSample = 2.0 * (harmonicPhase / (2.0 * Float.pi) - floor(harmonicPhase / (2.0 * Float.pi) + 0.5))
                case .noise:
                    harmonicSample = Float.random(in: -1...1)
                case .custom:
                    harmonicSample = generateCustomWaveform(phase: harmonicPhase, frequency: harmonicFreq)
                }
                
                sample += harmonicSample * harmonicStrength
            }
            
            // Apply envelope (ADSR)
            let envelope = calculateEnvelope(
                time: time,
                duration: Float(duration),
                envelope: timbre.envelope
            )
            
            sample *= envelope * volume
            
            // Apply effects (simplified)
            sample = applyEffects(sample: sample, effects: timbre.effects, time: time)
            
            samples.append(sample)
        }
        
        return samples
    }
    
    private func generateCustomWaveform(phase: Float, frequency: Float) -> Float {
        // Custom waveform for transformation melodies - more complex harmonics
        let fundamental = sin(phase)
        let octave = sin(phase * 2) * 0.3
        let fifth = sin(phase * 1.5) * 0.2
        let noise = Float.random(in: -0.1...0.1)
        
        return fundamental + octave + fifth + noise
    }
    
    private func calculateEnvelope(time: Float, duration: Float, envelope: ADSREnvelope) -> Float {
        let attack = Float(envelope.attack)
        let decay = Float(envelope.decay)
        let sustain = envelope.sustain
        let release = Float(envelope.release)
        
        if time < attack {
            // Attack phase
            return time / attack
        } else if time < attack + decay {
            // Decay phase
            let decayProgress = (time - attack) / decay
            return 1.0 - (1.0 - sustain) * decayProgress
        } else if time < duration - release {
            // Sustain phase
            return sustain
        } else {
            // Release phase
            let releaseProgress = (time - (duration - release)) / release
            return sustain * (1.0 - releaseProgress)
        }
    }
    
    private func applyEffects(sample: Float, effects: [AudioFilter], time: Float) -> Float {
        var processedSample = sample
        
        for effect in effects {
            switch effect {
            case .reverb(_, let wetDryMix):
                // Simplified reverb - just add delayed version
                let delayedSample = sample * 0.3 // Simplified delay
                processedSample = sample * (1.0 - wetDryMix) + delayedSample * wetDryMix
                
            case .echo(let delay, let feedback, let wetDryMix):
                // Simplified echo effect
                let echoSample = sample * feedback
                processedSample = sample * (1.0 - wetDryMix) + echoSample * wetDryMix
                
            case .distortion(let preGain, let wetDryMix):
                // Simple distortion
                let distortedSample = tanh(sample * preGain)
                processedSample = sample * (1.0 - wetDryMix) + distortedSample * wetDryMix
                
            default:
                // Other effects would be implemented here
                break
            }
        }
        
        return processedSample
    }
    
    private func convertSamplesToData(_ samples: [Float], sampleRate: Float) -> Data {
        var data = Data()
        
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))
            withUnsafeBytes(of: intSample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    func getCurrentLoad() -> Float {
        return currentLoad
    }
    
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        // Update internal settings for future synthesis
    }
 }

 class HarmonyProcessor {
    private let qualitySettings: AudioQualitySettings
    
    init(qualitySettings: AudioQualitySettings) {
        self.qualitySettings = qualitySettings
    }
    
    func synthesizeHarmony(melodyLines: [MelodyLine], strength: Float, blendFactor: Float) async -> Data {
        // Combine multiple melody lines into harmony
        let sampleRate = Float(qualitySettings.sampleRate)
        
        // Find the maximum duration among all melody lines
        let maxDuration = melodyLines.map { line in
            line.notes.reduce(0.0) { $0 + $1.duration }
        }.max() ?? 0.0
        
        let totalSamples = Int(maxDuration * sampleRate)
        var combinedSamples = Array(repeating: Float(0), count: totalSamples)
        
        // Generate and combine each melody line
        for melodyLine in melodyLines {
            let lineSamples = await generateMelodyLineSamples(
                melodyLine: melodyLine,
                sampleRate: sampleRate,
                totalSamples: totalSamples,
                strength: strength
            )
            
            // Add to combined samples with proper volume mixing
            for i in 0..<min(combinedSamples.count, lineSamples.count) {
                combinedSamples[i] += lineSamples[i] * melodyLine.volume * blendFactor
            }
        }
        
        // Normalize to prevent clipping
        let maxSample = combinedSamples.max() ?? 1.0
        if maxSample > 1.0 {
            for i in 0..<combinedSamples.count {
                combinedSamples[i] /= maxSample
            }
        }
        
        return convertSamplesToData(combinedSamples, sampleRate: sampleRate)
    }
    
    private func generateMelodyLineSamples(
        melodyLine: MelodyLine,
        sampleRate: Float,
        totalSamples: Int,
        strength: Float
    ) async -> [Float] {
        let synthesizer = AudioSynthesizer(qualitySettings: qualitySettings)
        let timbre = createHarmonyTimbre(for: melodyLine.voice)
        
        let audioData = await synthesizer.synthesizeMelody(
            notes: melodyLine.notes,
            timbre: timbre,
            volume: strength,
            tempo: 100.0 // Standard tempo for harmonies
        )
        
        return convertDataToSamples(audioData, targetSampleCount: totalSamples)
    }
    
    private func createHarmonyTimbre(for voice: Int) -> AudioTimbre {
        // Create different timbres for different harmony voices
        let waveform: AudioTimbre.Waveform
        let harmonics: [Float]
        
        switch voice {
        case 0: // Lead voice
            waveform = .sine
            harmonics = [1.0, 0.3, 0.1]
        case 1: // First harmony
            waveform = .triangle
            harmonics = [1.0, 0.5, 0.2]
        case 2: // Second harmony
            waveform = .square
            harmonics = [1.0, 0.0, 0.3, 0.0, 0.1]
        default: // Additional harmonies
            waveform = .sawtooth
            harmonics = [1.0, 0.4, 0.2, 0.1]
        }
        
        return AudioTimbre(
            waveform: waveform,
            harmonics: harmonics,
            envelope: .default,
            effects: [.reverb(preset: .mediumHall, wetDryMix: 0.2)]
        )
    }
    
    private func convertDataToSamples(_ data: Data, targetSampleCount: Int) -> [Float] {
        let int16Array = data.withUnsafeBytes { buffer in
            return Array(buffer.bindMemory(to: Int16.self))
        }
        
        var floatSamples = int16Array.map { Float($0) / Float(Int16.max) }
        
        // Resize to target sample count
        if floatSamples.count < targetSampleCount {
            floatSamples.append(contentsOf: Array(repeating: 0.0, count: targetSampleCount - floatSamples.count))
        } else if floatSamples.count > targetSampleCount {
            floatSamples = Array(floatSamples.prefix(targetSampleCount))
        }
        
        return floatSamples
    }
    
    private func convertSamplesToData(_ samples: [Float], sampleRate: Float) -> Data {
        var data = Data()
        
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))
            withUnsafeBytes(of: intSample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    func updateQualitySettings(_ settings: AudioQualitySettings) {
        // Update internal settings for future processing
    }
 }

 // MARK: - Notification Extensions
 extension Notification.Name {
    static let addVisualEffect = Notification.Name("addVisualEffect")
    static let removeVisualEffect = Notification.Name("removeVisualEffect")
 }
