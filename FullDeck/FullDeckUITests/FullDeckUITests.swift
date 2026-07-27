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

    /// Regression: selecting a language must light up *every* dependent tab, not
    /// just the first one visited. The Progress tab kept rendering the
    /// "Choose a language" placeholder after French was already active.
    @MainActor
    func testFR10ProgressTabShowsTheReadoutAfterSelectingALanguage() throws {
        let app = XCUIApplication()
        app.launch()

        let french = app.buttons["French"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()

        app.tabBars.firstMatch.buttons["Progress"].tap()

        let readout = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "words learned"))
            .firstMatch
        XCTAssertTrue(
            readout.waitForExistence(timeout: 5),
            "Progress tab showed no readout. Hierarchy:\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Choose a language"].exists)
    }

    /// Regression: switching tabs mid-session must not throw away the learner's
    /// place in the deck. Rebuilding the ViewModel on every body evaluation
    /// restarted the queue from the first card.
    @MainActor
    func testFR3StudySessionSurvivesATabSwitch() throws {
        let app = XCUIApplication()
        app.launch()

        let french = app.buttons["French"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()

        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Study"].tap()
        XCTAssertTrue(app.staticTexts["Card 1 of 5"].waitForExistence(timeout: 5))

        app.buttons["Reveal"].tap()
        app.buttons["Grade this word Good"].tap()
        XCTAssertTrue(app.staticTexts["Card 2 of 5"].waitForExistence(timeout: 5))

        tabBar.buttons["Progress"].tap()
        tabBar.buttons["Study"].tap()

        XCTAssertTrue(
            app.staticTexts["Card 2 of 5"].waitForExistence(timeout: 5),
            "Session restarted after a tab switch. Hierarchy:\n\(app.debugDescription)")
    }
}
