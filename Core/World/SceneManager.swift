//
//  SceneManager.swift
//  FinalStorm
//
//  Manages the RealityKit scene
//

import RealityKit
#if canImport(ARKit)
import ARKit
#endif

class SceneManager {
    private var rootAnchor: AnchorEntity?
    private var loadedGrids: [GridCoordinate: AnchorEntity] = [:]
    
    func setupScene(in arView: ARView) {
        rootAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(rootAnchor!)
    }
    
    func addGrid(_ grid: Grid) async {
        guard let rootAnchor = rootAnchor else { return }
        
        let gridAnchor = AnchorEntity(world: grid.coordinate.toWorldPosition())
        
        // Add terrain if available
        if let terrain = grid.terrain {
            let terrainEntity = Entity()
            terrainEntity.components.set(ModelComponent(
                mesh: terrain.mesh,
                materials: [createTerrainMaterial(for: terrain.biome)]
            ))
            gridAnchor.addChild(terrainEntity)
        }
        
        // Add entities
        for entity in grid.entities {
            gridAnchor.addChild(entity)
        }
        
        rootAnchor.addChild(gridAnchor)
        loadedGrids[grid.coordinate] = gridAnchor
    }
    
    func removeGrid(_ coordinate: GridCoordinate) {
        if let gridAnchor = loadedGrids[coordinate] {
            gridAnchor.removeFromParent()
            loadedGrids.removeValue(forKey: coordinate)
        }
    }
    
    func addEntity(_ entity: Entity) {
        rootAnchor?.addChild(entity)
    }
    
    private func createTerrainMaterial(for biome: Biome) -> Material {
        var material = PhysicallyBasedMaterial()
        
        // Use direct color values for cross-platform compatibility
        switch biome {
        case .grassland:
            material.baseColor = .init(tint: .init(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0))
            material.roughness = 0.9
        case .forest:
            material.baseColor = .init(tint: .init(red: 0.2, green: 0.4, blue: 0.2, alpha: 1.0))
            material.roughness = 0.95
        case .desert:
            material.baseColor = .init(tint: .init(red: 1.0, green: 0.9, blue: 0.4, alpha: 1.0))
            material.roughness = 1.0
        case .ocean:
            material.baseColor = .init(tint: .init(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0))
            material.roughness = 0.1
            material.metallic = 0.5
        case .mountain:
            material.baseColor = .init(tint: .init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
            material.roughness = 1.0
        case .corrupted:
            material.baseColor = .init(tint: .init(red: 0.6, green: 0.0, blue: 0.8, alpha: 1.0))
            material.roughness = 0.7
            material.emissiveColor = .init(color: .init(red: 0.6, green: 0.0, blue: 0.8, alpha: 1.0))
            material.emissiveIntensity = 0.1
        }
        
        return material
    }
}
