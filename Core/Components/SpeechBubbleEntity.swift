//
//  SpeechBubbleEntity.swift
//  FinalStorm
//
//  Speech bubble for character dialogue
//

import RealityKit

class SpeechBubbleEntity: Entity {
    init(text: String) {
        super.init()
        
        // Create bubble background
        let background = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 0.5),
            materials: [createBubbleMaterial()]
        )
        background.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        addChild(background)
        
        // Add text
        if let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.1),
            containerFrame: CGRect(x: -0.9, y: -0.2, width: 1.8, height: 0.4),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        ) {
            let textEntity = ModelEntity(
                mesh: textMesh,
                materials: [UnlitMaterial(color: .black)]
            )
            textEntity.position = [0, 0, 0.01]
            addChild(textEntity)
        }
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
    private func createBubbleMaterial() -> Material {
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.9))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        return material
    }
}
