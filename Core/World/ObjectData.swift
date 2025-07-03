//
//  ObjectData.swift
//  FinalStorm
//
//  Object data for world entities
//

import Foundation

struct ObjectData {
    let id: UUID
    let name: String
    let meshURL: URL?
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>
    let hasPhysics: Bool
    let isDynamic: Bool
    let mass: Float
    let isInteractive: Bool
}
