//
//  ImmersiveWorldView.swift
//  FinalStorm
//
//  Immersive world view for visionOS
//

import SwiftUI
import RealityKit

struct ImmersiveWorldView: View {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    var body: some View {
        RealityView { content in
            await setupWorld(content)
        }
    }
    
    @MainActor
    private func setupWorld(_ content: RealityViewContent) async {
        // Create ground
        let ground = ModelEntity(
            mesh: .generatePlane(width: 100, depth: 100),
            materials: [SimpleMaterial(color: .brown, isMetallic: false)]
        )
        ground.position = [0, -0.1, 0]
        content.add(ground)
        
        // Add some sample content
        let cube = ModelEntity(
            mesh: .generateBox(size: 1),
            materials: [SimpleMaterial(color: .blue, isMetallic: true)]
        )
        cube.position = [0, 0.5, -2]
        content.add(cube)
    }
}
