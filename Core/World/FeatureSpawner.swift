//
//  Core/World/FeatureSpawner.swift
//  FinalStorm
//
//  Advanced world feature spawning system with contextual placement
//

import Foundation
import simd

class FeatureSpawner {
    private let maxFeaturesPerGrid = 15
    private let minFeatureDistance: Float = 5.0
    
    func spawnFeatures(
        coordinate: GridCoordinate,
        biome: BiomeType,
        heightmap: [[Float]],
        harmonyLevel: Float
    ) async -> [WorldFeature] {
        
        var features: [WorldFeature] = []
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        // Get appropriate features for this biome
        let availableFeatures = biome.commonFeatures
        
        // Spawn features based on biome and harmony
        for featureType in availableFeatures {
            if shouldSpawnFeature(featureType, harmonyLevel: harmonyLevel, biome: biome) {
                if let feature = await generateFeature(
                    type: featureType,
                    heightmap: heightmap,
                    biome: biome,
                    harmonyLevel: harmonyLevel,
                    existingFeatures: features
                ) {
                    features.append(feature)
                    
                    // Limit total features per grid
                    if features.count >= maxFeaturesPerGrid {
                        break
                    }
                }
            }
        }
        
        // Add special harmony/dissonance features
        features.append(contentsOf: generateSpecialFeatures(
            coordinate: coordinate,
            biome: biome,
            heightmap: heightmap,
            harmonyLevel: harmonyLevel,
            existingFeatures: features
        ))
        
        return features
    }
    
    private func shouldSpawnFeature(
        _ featureType: WorldFeature.FeatureType,
        harmonyLevel: Float,
        biome: BiomeType
    ) -> Bool {
        
        // Base spawn chance
        var spawnChance: Float = 0.3
        
        // Adjust based on feature type and harmony
        switch featureType {
        case .corruption:
            spawnChance = harmonyLevel < 0.5 ? 0.8 : 0.1
        case .garden, .spring:
            spawnChance = harmonyLevel > 1.0 ? 0.7 : 0.2
        case .crystal:
            spawnChance = (harmonyLevel > 1.2 || harmonyLevel < 0.3) ? 0.6 : 0.1
        case .shrine:
            spawnChance = harmonyLevel > 0.8 ? 0.4 : 0.1
        case .ruin:
            spawnChance = 0.2 // Ruins are rare
        case .portal:
            spawnChance = abs(harmonyLevel - 1.0) > 0.5 ? 0.3 : 0.05
        case .settlement:
            spawnChance = harmonyLevel > 0.6 ? 0.15 : 0.05
        case .tower:
            spawnChance = biome == .mountain ? 0.4 : 0.2
        case .cave:
            spawnChance = [.mountain, .mesa].contains(biome) ? 0.5 : 0.1
        default:
            spawnChance = 0.3
        }
        
        // Biome-specific adjustments
        if biome == .corrupted && [.garden, .spring, .shrine].contains(featureType) {
            spawnChance *= 0.1
        } else if biome == .ethereal && [.shrine, .garden, .crystal].contains(featureType) {
            spawnChance *= 2.0
        }
        
        return Float.random(in: 0...1) < spawnChance
    }
    
    private func generateFeature(
        type: WorldFeature.FeatureType,
        heightmap: [[Float]],
        biome: BiomeType,
        harmonyLevel: Float,
        existingFeatures: [WorldFeature]
    ) async -> WorldFeature? {
        
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        // Find suitable placement location
        for attempt in 0..<10 { // Maximum attempts to find good placement
            let x = Int.random(in: 5..<(resolution-5))
            let z = Int.random(in: 5..<(resolution-5))
            
            let worldX = (Float(x) / Float(resolution)) * gridSize
            let worldZ = (Float(z) / Float(resolution)) * gridSize
            let height = heightmap[z][x]
            
            let position = SIMD3<Float>(worldX, height, worldZ)
            
            // Check if location is suitable for this feature type
            if isValidFeatureLocation(
                type: type,
                position: position,
                heightmap: heightmap,
                x: x, z: z,
                existingFeatures: existingFeatures
            ) {
                return createFeatureWithMetadata(
                    type: type,
                    position: position,
                    biome: biome,
                    harmonyLevel: harmonyLevel
                )
            }
        }
        
        return nil
    }
    
    private func isValidFeatureLocation(
        type: WorldFeature.FeatureType,
        position: SIMD3<Float>,
        heightmap: [[Float]],
        x: Int, z: Int,
        existingFeatures: [WorldFeature]
    ) -> Bool {
        
        let resolution = heightmap.count
        let height = position.y
        let slope = calculateSlope(x: x, z: z, heightmap: heightmap)
        
        // Check minimum distance to other features
        for feature in existingFeatures {
            if simd_length(position - feature.position) < minFeatureDistance {
                return false
            }
        }
        
        // Feature-specific placement rules
        switch type {
        case .settlement, .garden, .shrine:
            return height > 0 && slope < 0.3 // Flat, dry areas
            
        case .tower:
            return height > 5 && slope < 0.5 // High ground
            
        case .cave:
            return height > 2 && slope > 0.4 // Hillsides
            
        case .spring:
            return height > -1 && height < 3 && slope < 0.2 // Near water level
            
        case .bridge:
            return detectWaterNearby(x: x, z: z, heightmap: heightmap) // Near water
            
        case .corruption:
            return true // Can spawn anywhere
            
        case .crystal:
            return height > 0 // Above water
            
        case .portal:
            return height > 0 && slope < 0.2 // Stable ground
            
        case .ruin:
            return height > -2 // Can be partially submerged
            
        default:
            return height > -1 && slope < 0.6
        }
    }
    
    private func calculateSlope(x: Int, z: Int, heightmap: [[Float]]) -> Float {
        let resolution = heightmap.count
        guard x > 0 && x < resolution-1 && z > 0 && z < resolution-1 else { return 0 }
        
        let left = heightmap[z][x-1]
        let right = heightmap[z][x+1]
        let up = heightmap[z-1][x]
        let down = heightmap[z+1][x]
        
        let dx = abs(right - left) / 2.0
        let dz = abs(down - up) / 2.0
        
        return sqrt(dx * dx + dz * dz)
    }
    
    private func detectWaterNearby(x: Int, z: Int, heightmap: [[Float]]) -> Bool {
        let resolution = heightmap.count
        let searchRadius = 3
        
        for dz in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                let checkX = x + dx
                let checkZ = z + dz
                
                if checkX >= 0 && checkX < resolution &&
                   checkZ >= 0 && checkZ < resolution &&
                   heightmap[checkZ][checkX] < -1.0 {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func createFeatureWithMetadata(
        type: WorldFeature.FeatureType,
        position: SIMD3<Float>,
        biome: BiomeType,
        harmonyLevel: Float
    ) -> WorldFeature {
        
        var metadata: [String: String] = [
            "biome": biome.rawValue,
            "harmonyLevel": String(format: "%.2f", harmonyLevel),
            "generatedAt": Date().ISO8601Format()
        ]
        
        // Add type-specific metadata
        switch type {
        case .tree:
            metadata["species"] = selectTreeSpecies(biome: biome).rawValue
            metadata["age"] = String(format: "%.2f", Float.random(in: 0.1...1.0))
            
        case .crystal:
            metadata["crystalType"] = selectCrystalType(harmonyLevel: harmonyLevel)
            metadata["resonance"] = String(format: "%.2f", harmonyLevel)
            
        case .corruption:
            metadata["corruptionLevel"] = String(format: "%.2f", 1.0 - harmonyLevel)
            metadata["spreadRate"] = String(format: "%.3f", Float.random(in: 0.001...0.01))
            
        case .spring:
            metadata["waterType"] = selectWaterType(biome: biome, harmonyLevel: harmonyLevel)
            metadata["purity"] = String(format: "%.2f", harmonyLevel)
            
        case .shrine:
            metadata["shrineType"] = selectShrineType(biome: biome, harmonyLevel: harmonyLevel)
            metadata["power"] = String(format: "%.2f", harmonyLevel)
            
        case .settlement:
            metadata["populationType"] = selectPopulationType(biome: biome)
            metadata["size"] = selectSettlementSize(harmonyLevel: harmonyLevel)
            
        case .ruin:
            metadata["age"] = selectRuinAge()
            metadata["civilization"] = selectRuinCivilization(biome: biome)
            
        default:
            break
        }
        
        return WorldFeature(type: type, position: position, metadata: metadata)
    }
    
    private func selectTreeSpecies(biome: BiomeType) -> VegetationMap.TreeSpecies {
        switch biome {
        case .forest: return [.oak, .birch, .pine].randomElement() ?? .oak
        case .mountain: return .pine
        case .swamp: return .willow
        case .ethereal: return .harmonyTree
        case .corrupted: return .corruptedTree
        case .crystal: return .crystalTree
        default: return .oak
        }
    }
    
    private func selectCrystalType(harmonyLevel: Float) -> String {
        if harmonyLevel > 1.5 {
            return "Harmony Crystal"
        } else if harmonyLevel < 0.3 {
            return "Void Crystal"
        } else {
            return ["Quartz", "Amethyst", "Emerald", "Sapphire"].randomElement() ?? "Quartz"
        }
    }
    
    private func selectWaterType(biome: BiomeType, harmonyLevel: Float) -> String {
        switch biome {
        case .ethereal: return "Harmonic Water"
        case .corrupted: return "Tainted Water"
        case .volcanic: return "Mineral Water"
        default: return harmonyLevel > 1.0 ? "Pure Water" : "Fresh Water"
        }
    }
    
    private func selectShrineType(biome: BiomeType, harmonyLevel: Float) -> String {
        if harmonyLevel > 1.3 {
            return "Harmony Shrine"
        } else if harmonyLevel < 0.5 {
            return "Abandoned Shrine"
        } else {
            return ["Echo Shrine", "Memory Shrine", "Song Shrine", "Wind Shrine"].randomElement() ?? "Echo Shrine"
        }
    }
    
    private func selectPopulationType(biome: BiomeType) -> String {
        switch biome {
        case .grassland: return "Farmers"
        case .forest: return "Foresters"
        case .mountain: return "Miners"
        case .desert: return "Nomads"
        case .ethereal: return "Songweavers"
        case .ocean: return "Fishers"
        default: return "Travelers"
        }
    }
    
    private func selectSettlementSize(harmonyLevel: Float) -> String {
        if harmonyLevel > 1.2 {
            return "Large"
        } else if harmonyLevel > 0.8 {
            return "Medium"
        } else {
            return "Small"
        }
    }
    
    private func selectRuinAge() -> String {
        return ["Ancient", "Old", "Weathered", "Crumbling", "Recent"].randomElement() ?? "Old"
    }
    
    private func selectRuinCivilization(biome: BiomeType) -> String {
        switch biome {
        case .desert: return "Desert Empire"
        case .mountain: return "Mountain Kingdom"
        case .forest: return "Forest Realm"
        case .ethereal: return "Songweaver Civilization"
        case .corrupted: return "Fallen Empire"
        default: return "Unknown Civilization"
        }
    }
    
    private func generateSpecialFeatures(
        coordinate: GridCoordinate,
        biome: BiomeType,
        heightmap: [[Float]],
        harmonyLevel: Float,
        existingFeatures: [WorldFeature]
    ) -> [WorldFeature] {
        
        var specialFeatures: [WorldFeature] = []
        
        // Generate harmony-specific features
        if harmonyLevel > 1.8 && Float.random(in: 0...1) < 0.3 {
            // Celestial convergence point
            if let position = findOpenArea(heightmap: heightmap, existingFeatures: existingFeatures) {
                let feature = WorldFeature(
                    type: .garden,
                    position: position,
                    metadata: [
                        "specialType": "Celestial Convergence",
                        "harmonyBonus": "0.5",
                        "rarity": "Legendary"
                    ]
                )
                specialFeatures.append(feature)
            }
        }
        
        if harmonyLevel < 0.2 && Float.random(in: 0...1) < 0.4 {
            // Corruption nexus
            if let position = findOpenArea(heightmap: heightmap, existingFeatures: existingFeatures) {
                let feature = WorldFeature(
                    type: .corruption,
                    position: position,
                    metadata: [
                        "specialType": "Corruption Nexus",
                        "corruptionRadius": "20.0",
                        "rarity": "Rare"
                    ]
                )
                specialFeatures.append(feature)
            }
        }
        
        // Generate coordinate-based unique features
        let coordinateHash = coordinate.x ^ coordinate.z
        if coordinateHash % 100 == 0 { // 1% chance for unique features
            if let position = findOpenArea(heightmap: heightmap, existingFeatures: existingFeatures) {
                let uniqueFeature = generateUniqueFeature(
                    coordinate: coordinate,
                    position: position,
                    biome: biome
                )
                specialFeatures.append(uniqueFeature)
            }
        }
        
        return specialFeatures
    }
    
    private func findOpenArea(
        heightmap: [[Float]],
        existingFeatures: [WorldFeature]
    ) -> SIMD3<Float>? {
        
        let resolution = heightmap.count
        let gridSize: Float = 100.0
        
        for _ in 0..<20 { // Try 20 times to find open area
            let x = Int.random(in: 10..<(resolution-10))
            let z = Int.random(in: 10..<(resolution-10))
            
            let worldX = (Float(x) / Float(resolution)) * gridSize
            let worldZ = (Float(z) / Float(resolution)) * gridSize
            let height = heightmap[z][x]
            
            let position = SIMD3<Float>(worldX, height, worldZ)
            
            // Check if area is clear
            var isClear = true
            for feature in existingFeatures {
                if simd_length(position - feature.position) < 15.0 {
                    isClear = false
                    break
                }
            }
            
            if isClear && height > 0 {
                return position
            }
        }
        
        return nil
    }
    
    private func generateUniqueFeature(
        coordinate: GridCoordinate,
        position: SIMD3<Float>,
        biome: BiomeType
    ) -> WorldFeature {
        
        let uniqueNames = [
            "Ancient Monolith",
            "Singing Stone",
            "Harmony Nexus",
            "Echo Chamber",
            "Starfall Site",
            "Time Rift",
            "Memory Crystal",
            "Void Anchor"
        ]
        
        let uniqueName = uniqueNames.randomElement() ?? "Mysterious Structure"
        let featureType: WorldFeature.FeatureType = [.monument, .crystal, .shrine, .portal].randomElement() ?? .monument
        
        let metadata: [String: String] = [
            "uniqueName": uniqueName,
            "coordinateSignature": "\(coordinate.x),\(coordinate.z)",
            "discoveryRarity": "Unique",
            "biomeOrigin": biome.rawValue,
            "specialPowers": generateSpecialPowers(name: uniqueName),
            "lore": generateLore(name: uniqueName, biome: biome)
        ]
        
        return WorldFeature(type: featureType, position: position, metadata: metadata)
    }
    
    private func generateSpecialPowers(name: String) -> String {
        switch name {
        case "Ancient Monolith":
            return "Memory Resonance, Time Echo"
        case "Singing Stone":
            return "Harmonic Amplification, Song Storage"
        case "Harmony Nexus":
            return "Harmony Restoration, Energy Convergence"
        case "Echo Chamber":
            return "Sound Multiplication, Voice Preservation"
        case "Starfall Site":
            return "Celestial Connection, Meteor Attraction"
        case "Time Rift":
            return "Temporal Distortion, Past Glimpses"
        case "Memory Crystal":
            return "Memory Storage, Experience Sharing"
        case "Void Anchor":
            return "Reality Stabilization, Void Containment"
        default:
            return "Unknown Powers"
        }
    }
    
    private func generateLore(name: String, biome: BiomeType) -> String {
        let biomeDescriptor = getBiomeDescriptor(biome)
        
        switch name {
        case "Ancient Monolith":
            return "A towering stone structure predating known civilizations, found in the \(biomeDescriptor). Local legends speak of voices from the past."
        case "Singing Stone":
            return "A crystalline formation in the \(biomeDescriptor) that resonates with ethereal melodies when the wind passes through."
        case "Harmony Nexus":
            return "A convergence point of natural energies in the \(biomeDescriptor), where harmony flows like a visible river."
        case "Echo Chamber":
            return "A natural acoustic phenomenon in the \(biomeDescriptor) that preserves and replays sounds from ages past."
        case "Starfall Site":
            return "The impact crater of an ancient celestial visitor in the \(biomeDescriptor), still humming with otherworldly energy."
        case "Time Rift":
            return "A tear in reality within the \(biomeDescriptor), where past and present bleed together in impossible ways."
        case "Memory Crystal":
            return "A massive crystal formation in the \(biomeDescriptor) that pulses with stored memories of those who came before."
        case "Void Anchor":
            return "A mysterious structure in the \(biomeDescriptor) that seems to hold reality together against encroaching darkness."
        default:
            return "An enigmatic presence in the \(biomeDescriptor), its purpose lost to time."
        }
    }
    
    private func getBiomeDescriptor(_ biome: BiomeType) -> String {
        switch biome {
        case .grassland: return "rolling meadows"
        case .forest: return "ancient woodlands"
        case .desert: return "shifting sands"
        case .ocean: return "endless waters"
        case .mountain: return "towering peaks"
        case .corrupted: return "tainted wasteland"
        case .tundra: return "frozen plains"
        case .swamp: return "murky wetlands"
        case .volcanic: return "fire-scorched lands"
        case .ethereal: return "shimmering realm"
        case .arctic: return "ice-locked wilderness"
        case .jungle: return "verdant canopy"
        case .mesa: return "weathered plateaus"
        case .crystal: return "crystalline fields"
        }
    }
 }
