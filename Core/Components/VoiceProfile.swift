//
//  VoiceProfile.swift
//  FinalStorm
//
//  Voice profile for character speech
//

import Foundation

struct VoiceProfile {
    let pitch: Float
    let speed: Float
    let timbre: Timbre
    
    enum Timbre {
        case bright
        case warm
        case digital
        case bold
    }
}
