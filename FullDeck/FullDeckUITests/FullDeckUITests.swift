import XCTest

// UI tests are XCUITest (ADR-003) — they drive the real app process, which Swift
// Testing can't do. The unit-level smoke test lives in FullDeckTests (Swift Testing).
//
// Phase-4 scaffold: no requirement ID yet (FR-backed flows begin in Phase 8). This
// replaces Xcode's generated boilerplate (an empty stub + a timing-based launch
// performance measure) — both non-traceable and, in the perf case, non-deterministic,
// which the project's testing standards forbid.
final class FullDeckUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The Phase-4 shell is a TabView with one tab per v1 screen. Proves the app
    /// launches and renders all three tabs — deterministic, no timing or sleeps.
    @MainActor
    func testAppLaunchesWithThreeTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Study"].exists)
        XCTAssertTrue(tabBar.buttons["Progress"].exists)
    }
}
