//
//  CodableColor.swift
//  FinalStorm
//
//  Platform-agnostic color representation
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Platform-agnostic color that can be encoded/decoded
struct CodableColor: Codable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float
    
    init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    /// Convert to SwiftUI Color
    var swiftUIColor: Color {
        return Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }
    
    #if canImport(UIKit)
    /// Convert to UIColor on iOS/tvOS
    func toUIColor() -> UIColor {
        return UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
    #endif
    
    #if canImport(AppKit)
    /// Convert to NSColor on macOS
    func toNSColor() -> NSColor {
        return NSColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
    #endif
    
    /// Get platform-specific color
    var platformColor: Any {
        #if canImport(UIKit)
        return toUIColor()
        #elseif canImport(AppKit)
        return toNSColor()
        #else
        return swiftUIColor
        #endif
    }
    
    /// Convert to SIMD4 for RealityKit
    var simd4: SIMD4<Float> {
        return SIMD4<Float>(red, green, blue, alpha)
    }
}
