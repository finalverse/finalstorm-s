//
//  Core/Components/SpeechBubbleEntity.swift
//  FinalStorm
//
//  Speech bubble for character dialogue with proper imports and error-free code
//

import RealityKit
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        
        // Add text with proper platform handling
        addTextToSpeechBubble(text: text)
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
    private func addTextToSpeechBubble(text: String) {
        // Platform-specific text generation for iOS 18+, macOS 15+, visionOS 2+
        #if os(iOS) || os(macOS) || os(visionOS)
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
            // Use the advanced text generation API - NO optional binding needed
            let textMesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.01,
                font: .systemFont(ofSize: 0.1),
                containerFrame: CGRect(x: -0.9, y: -0.2, width: 1.8, height: 0.4),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )
            
            let textEntity = ModelEntity(
                mesh: textMesh,
                materials: [createTextMaterial()]
            )
            textEntity.position = [0, 0, 0.01]
            addChild(textEntity)
        } else {
            // Fallback for older versions - use simple text
            addFallbackText(text: text)
        }
        #else
        // Fallback for other platforms
        addFallbackText(text: text)
        #endif
    }
    
    private func addFallbackText(text: String) {
        // Simple fallback - create a basic text representation - NO optional binding needed
        let simpleMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.1)
        )
        
        let textEntity = ModelEntity(
            mesh: simpleMesh,
            materials: [createTextMaterial()]
        )
        textEntity.position = [0, 0, 0.01]
        addChild(textEntity)
    }
    
    private func createBubbleMaterial() -> Material {
        var material = UnlitMaterial()
        
        // Platform-specific color handling with proper imports
        #if os(iOS) || os(visionOS)
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.9))
        #elseif os(macOS)
        material.color = .init(tint: NSColor.white.withAlphaComponent(0.9))
        #endif
        
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        return material
    }
    
    private func createTextMaterial() -> Material {
        var material = UnlitMaterial()
        
        // Platform-specific black color with proper imports
        #if os(iOS) || os(visionOS)
        material.color = .init(tint: UIColor.black)
        #elseif os(macOS)
        material.color = .init(tint: NSColor.black)
        #endif
        
        return material
    }
}
