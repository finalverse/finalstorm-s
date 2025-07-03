//
//  SpinComponent.swift
//  FinalStorm
//
//  Created by Wenyan Qin on 2025-07-02.
//

import RealityKit

/// A component that spins the entity around a given axis.
struct SpinComponent: Component {
    let spinAxis: SIMD3<Float> = [0, 1, 0]
}
