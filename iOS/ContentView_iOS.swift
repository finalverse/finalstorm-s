//
//  iOS/ContentView_iOS.swift
//  FinalStorm
//
//  iOS-specific content view implementation
//

import SwiftUI

struct ContentView_iOS: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, iOS world!")
        }
        .padding()
    }
}

#Preview {
    ContentView_iOS()
}
