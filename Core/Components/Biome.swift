//
//  Biome.swift
//  FinalStorm
//
//  Biome definitions for world generation
//

import Foundation

enum Biome {
    case grassland
    case forest
    case desert
    case ocean
    case mountain
    case corrupted
    
    func modifyTerrain(_ heightmap: [[Float]]) -> [[Float]] {
        var modified = heightmap
        
        switch self {
        case .ocean:
            // Lower terrain and add wave patterns
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] = min(modified[z][x], 0.5)
                }
            }
        case .mountain:
            // Amplify height differences
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    modified[z][x] *= 2.0
                }
            }
        case .corrupted:
            // Add jagged, discordant patterns
            for z in 0..<modified.count {
                for x in 0..<modified[z].count {
                    let noise = sin(Float(x) * 0.5) * cos(Float(z) * 0.5) * 0.3
                    modified[z][x] += noise
                }
            }
        default:
            break
        }
        
        return modified
    }
}
