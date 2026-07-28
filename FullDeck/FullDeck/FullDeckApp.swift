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
    /// injected downward. Nothing below reaches for a global. Construction can
    /// fail (the SwiftData store may not open), and NFR-10 says that is a state,
    /// never a crash.
    @State private var dependencies: Result<AppDependencies, Error> = Result {
        try AppDependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            switch dependencies {
            case .success(let dependencies):
                ContentView(dependencies: dependencies)
            case .failure:
                ErrorStateView(message: "Couldn't open your saved progress.")
            }
        }
    }
}
