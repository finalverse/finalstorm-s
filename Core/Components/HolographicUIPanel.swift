//
//  HolographicUIPanel.swift
//  FinalStorm
//
//  Holographic UI panel for AR/VR interfaces
//

import RealityKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

class HolographicUIPanel: Entity {
    func displayMetrics(from metabolism: WorldMetabolism) {
        // Clear existing children
        children.removeAll()
        
        // Create background panel
        let panel = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 1),
            materials: [createHologramMaterial()]
        )
        panel.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        addChild(panel)
        
        // Add title - FIXED: Remove optional binding
        let titleMesh = MeshResource.generateText(
            "World Metabolism",
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.08, weight: .bold)
        )
        let title = ModelEntity(mesh: titleMesh, materials: [UnlitMaterial(color: .cyan)])
        title.position = [0, 0.4, 0.01]
        addChild(title)
        
        // Add metrics
        let metrics = [
            ("Harmony", metabolism.globalHarmony),
            ("Dissonance", metabolism.globalDissonance)
        ]
        
        for (index, (label, value)) in metrics.enumerated() {
            let yPos = 0.2 - Float(index) * 0.2
            
            // Label - FIXED: Remove optional binding
            let labelMesh = MeshResource.generateText(
                label,
                extrusionDepth: 0.01,
                font: .systemFont(ofSize: 0.06)
            )
            let labelEntity = ModelEntity(mesh: labelMesh, materials: [UnlitMaterial(color: .white)])
            labelEntity.position = [-0.8, yPos, 0.01]
            addChild(labelEntity)
            
            // Value bar
            let barWidth = value * 1.2
            let bar = ModelEntity(
                mesh: .generateBox(size: [barWidth, 0.1, 0.02]),
                materials: [UnlitMaterial(color: value > 1.0 ? .green : .yellow)]
            )
            bar.position = [-0.8 + barWidth/2, yPos - 0.05, 0.01]
            addChild(bar)
        }
    }
    
    private func createHologramMaterial() -> Material {
        var material = UnlitMaterial()
        
        // FIXED: Use proper platform-specific color handling
        #if canImport(UIKit)
        material.color = .init(tint: UIColor.cyan.withAlphaComponent(0.2))
        #elseif canImport(AppKit)
        material.color = .init(tint: NSColor.cyan.withAlphaComponent(0.2))
        #endif
        
        material.blending = .transparent(opacity: .init(floatLiteral: 0.2))
        return material
    }
}
