//
//  ContentView.swift
//  FinalStorm
//
//  Main content view that delegates to platform-specific implementations
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        ContentView_iOS()
        #elseif os(macOS)
        ContentView_macOS()
        #elseif os(visionOS)
        ContentView_visionOS()
        #endif
    }
}

#Preview {
    ContentView()
}
