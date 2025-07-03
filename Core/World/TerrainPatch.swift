//
//  TerrainPatch.swift
//  FinalStorm
//
//  Terrain patch for world grid
//

import RealityKit

struct TerrainPatch {
    let mesh: MeshResource
    let heightmap: [[Float]]
    let biome: Biome
}
