import Testing

@testable import FullDeck

// Swift Testing (ADR-003), matching the Domain/Data packages. Xcode generated an
// XCTest template here regardless of the dropdown; it's been replaced. UI tests
// stay XCUITest in the FullDeckUITests target — that's the correct split.
//
// Phase-4 scaffold smoke test: no requirement ID yet (FR-backed tests begin in
// Phase 5/8). Just proves the app module compiles and its root view constructs.
@Test("Phase-4 scaffold: app module builds and ContentView constructs")
@MainActor
func contentViewConstructs() {
    _ = ContentView()
}
