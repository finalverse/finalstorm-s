//
//  macOS/ContentView_macOS.swift
//  FinalStorm
//
//  macOS-specific content view implementation
//

import SwiftUI

struct ContentView_macOS: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, macOS world!")
        }
        .padding()
    }
}

#Preview {
    ContentView_macOS()
}
