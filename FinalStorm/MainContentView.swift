//
//  FinalStorm/MainContentView.swift
//  FinalStorm
//
//  Main content view that routes to platform-specific views
//

import SwiftUI

struct MainContentView: View {
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
    MainContentView()
}
