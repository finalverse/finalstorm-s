//
//  Harmony.swift
//  FinalStorm
//
//  Harmony system types
//

import Foundation

struct Harmony: Identifiable {
    let id: UUID
    let melodies: [Melody]
    let participants: [UUID]
    let strength: Float
    let duration: TimeInterval
    
    init(id: UUID = UUID(), melodies: [Melody], participants: [UUID], strength: Float, duration: TimeInterval) {
        self.id = id
        self.melodies = melodies
        self.participants = participants
        self.strength = strength
        self.duration = duration
    }
    
    init(from melody: Melody) {
        self.id = UUID()
        self.melodies = [melody]
        self.participants = []
        self.strength = melody.strength
        self.duration = melody.duration
    }
}
