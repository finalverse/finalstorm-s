import SwiftUI
import RealityKit

struct ImmersiveWorldView: View {
    var body: some View {
        RealityView { content in
            // Create a simple cube for now
            let mesh = MeshResource.generateBox(size: 0.3, cornerRadius: 0.02)
            let material = SimpleMaterial(color: .blue, roughness: 0.15, isMetallic: true)
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.position = [0, 0, -1]
            content.add(model)
        }
    }
}
