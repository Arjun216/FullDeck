//
//  FullDeckApp.swift
//  FullDeck
//
//  Created by Arjun Pathak on 2026-07-24.
//

import SwiftUI

@main
struct FullDeckApp: App {
    /// The composition root: dependencies are constructed here, once, and
    /// injected downward. Nothing below reaches for a global.
    @State private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
    }
}
