//
//  ActionBarView.swift
//  FinalStorm
//
//  Action bar for abilities and shortcuts
//

import SwiftUI

struct ActionBarView: View {
    @State private var abilities: [Ability] = Ability.defaultAbilities
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(abilities) { ability in
                AbilityButton(ability: ability)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
}

struct AbilityButton: View {
    let ability: Ability
    @State private var cooldownProgress: Double = 0
    
    var body: some View {
        Button(action: { useAbility() }) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                Image(systemName: ability.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                
                if cooldownProgress > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 50, height: 50 * cooldownProgress)
                        .animation(.linear(duration: ability.cooldown), value: cooldownProgress)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func useAbility() {
        // Use ability
        cooldownProgress = 1.0
        
        withAnimation(.linear(duration: ability.cooldown)) {
            cooldownProgress = 0
        }
    }
}

struct Ability: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let cooldown: Double
    
    static let defaultAbilities = [
        Ability(name: "Restoration Melody", icon: "leaf.fill", cooldown: 3.0),
        Ability(name: "Exploration Song", icon: "location.fill", cooldown: 5.0),
        Ability(name: "Creation Harmony", icon: "sparkles", cooldown: 10.0),
        Ability(name: "Echo Call", icon: "waveform", cooldown: 30.0),
        Ability(name: "Silence Shield", icon: "shield.fill", cooldown: 15.0)
    ]
}
