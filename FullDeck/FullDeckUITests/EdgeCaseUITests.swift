import XCTest

/// The rows of Phase 13's edge-case matrix that only a running app can answer:
/// content that will not load, the app being sent to the background mid-session,
/// and the largest accessibility text size.
///
/// Separate file from `FullDeckUITests` because these are about the app
/// surviving conditions rather than about a requirement's happy path, and
/// because each one launches with different arguments — the shared 15-second
/// `waitForExistence` convention carries over, for the same reason.
final class EdgeCaseUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func frenchButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Français")).firstMatch
    }

    /// NFR-10: bad content produces a stated failure, not a crash and not an
    /// empty screen. The coverage review found `ErrorStateView` had never been
    /// rendered by any test, so this is the first time the app's own "something
    /// went wrong" has been looked at.
    @MainActor
    func testNFR10AnUnreadablePackShowsTheErrorStateRatherThanCrashing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestUnreadablePack"]
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()

        app.tabBars.firstMatch.buttons["Study"].tap()

        XCTAssertTrue(
            app.staticTexts["Something went wrong"].waitForExistence(timeout: 15),
            "no error state for an unloadable pack. Hierarchy:\n\(app.debugDescription)")
        // Still running, and still navigable: the failure is one screen's, not
        // the app's.
        app.tabBars.firstMatch.buttons["Languages"].tap()
        XCTAssertTrue(frenchButton(in: app).waitForExistence(timeout: 15))
    }

    /// NFR-4/NFR-5/NFR-6 on the error screen, which the audit could not reach
    /// before the fixture above existed — the same argument C-3 made for the
    /// completion screen.
    @MainActor
    func testNFR5AccessibilityAuditOnTheErrorState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestUnreadablePack"]
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()
        app.tabBars.firstMatch.buttons["Study"].tap()
        XCTAssertTrue(app.staticTexts["Something went wrong"].waitForExistence(timeout: 15))

        try app.performAccessibilityAudit()
    }

    /// FR-9/FR-3: backgrounding is not a session boundary. Every grade is written
    /// when it is made, so the learner comes back to where they were — and the
    /// app must not have been rebuilt from scratch in between.
    ///
    /// Distinct from `testFR3StudySessionSurvivesATabSwitch`: a tab switch keeps
    /// the process alive and the ViewModel in memory. Backgrounding runs the
    /// scene-phase path, which is where the reminder reconciliation also lives.
    @MainActor
    func testFR9AStudySessionSurvivesBeingBackgrounded() throws {
        let app = XCUIApplication()
        // C-8: without a fixture this asserts on the shared on-disk session,
        // which whichever tests ran earlier may already have spent — and "no
        // card on screen" then reads as a broken app rather than as an empty
        // deck. In-memory, twenty words, full session on every launch.
        app.launchArguments = ["-uiTestFreshSession"]
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()
        app.tabBars.firstMatch.buttons["Study"].tap()

        let card = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card "))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let before = card.label

        XCUIDevice.shared.press(.home)
        // `activate()` rather than a fresh `launch()`: launch would terminate and
        // relaunch the app, which tests cold start, not resumption. This asks for
        // the resumption path specifically.
        app.activate()

        // No assertion on `app.state`. One was here and it flaked: `activate()`
        // can return while the app is still `runningForegroundInactive`, so the
        // equality was racing the scene transition rather than testing anything.
        // The card query below is the real evidence — it cannot succeed unless
        // the app came back *and* rendered.
        let after = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card "))
            .firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 15))
        XCTAssertEqual(
            after.label, before,
            "coming back from the background moved the learner. Hierarchy:\n"
                + "\(app.debugDescription)")
    }

    /// NFR-5 at the size that actually breaks layouts.
    ///
    /// The existing audits run at the default text size and rely on the audit's
    /// "may be clipped at larger sizes" heuristic, which is a prediction. This
    /// sets the largest accessibility size for real and then asks the audit
    /// again, so the finding is an observation instead.
    @MainActor
    func testNFR5CoreScreensSurviveTheLargestAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            // C-8, same reason as the backgrounding test: this one needs a card
            // on screen to audit, and the shared session may have none left.
            "-uiTestFreshSession",
        ]
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        try app.performAccessibilityAudit()

        french.tap()
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Study"].tap()
        let card = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card "))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        try app.performAccessibilityAudit()

        // The revealed card is the densest screen in the app: word, gloss,
        // sentence, two speak buttons and the grade row, all at once.
        app.buttons["Reveal"].tap()
        XCTAssertTrue(app.buttons["Knew it!"].waitForExistence(timeout: 15))
        try app.performAccessibilityAudit()

        tabBar.buttons["Progress"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "words learned"))
                .firstMatch.waitForExistence(timeout: 15))
        try app.performAccessibilityAudit()
    }
}
