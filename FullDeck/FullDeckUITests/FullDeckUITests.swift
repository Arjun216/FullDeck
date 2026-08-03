import XCTest

// UI tests are XCUITest (ADR-003) — they drive the real app process, which Swift
// Testing can't do. The unit-level smoke test lives in FullDeckTests (Swift Testing).
//
// Phase-4 scaffold: no requirement ID yet (FR-backed flows begin in Phase 8). This
// replaces Xcode's generated boilerplate (an empty stub + a timing-based launch
// performance measure) — both non-traceable and, in the perf case, non-deterministic,
// which the project's testing standards forbid.
// A uniform, generous waitForExistence timeout (15s) is used throughout this
// file rather than tuning per-wait values — cold launch and render time are
// more variable under host load than any individual step, and a single
// number is one less thing to second-guess when a wait needs adjusting.
final class FullDeckUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The French row's accessibility label is "Français" until it's the
    /// active language, then "Français, active language" (real UserDefaults
    /// persists across test methods within one run) — match by prefix so
    /// this isn't order-dependent on which test selected it first.
    private func frenchButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Français")).firstMatch
    }

    /// The Phase-4 shell is a TabView with one tab per v1 screen. Proves the app
    /// launches and renders all three tabs — deterministic, no timing or sleeps.
    @MainActor
    func testAppLaunchesWithThreeTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 15))
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

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()

        app.tabBars.firstMatch.buttons["Progress"].tap()

        let readout = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "words learned"))
            .firstMatch
        XCTAssertTrue(
            readout.waitForExistence(timeout: 15),
            "Progress tab showed no readout. Hierarchy:\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Choose a language"].exists)
    }

    /// The starting card's total is real, persisted session state shared
    /// across every test method in this run (same on-disk SwiftData store,
    /// no reset between methods) — order and other methods' grading shift
    /// it, so tests read the actual "Card N of T" text rather than assuming
    /// a fixed N/T.
    private func cardLabel(in app: XCUIApplication) -> String? {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card "))
            .firstMatch.label
    }

    /// No issue filter. The one known exclusion — `.borderedProminent`'s white
    /// label on the accent fill — was retired when the prominent buttons moved
    /// to `AccentFill` (#B45309, 5.02:1 against white). A filter that outlives
    /// the problem it was written for hides the next real regression.
    private func performAudit(on app: XCUIApplication) throws {
        try app.performAccessibilityAudit()
    }

    /// Regression: switching tabs mid-session must not throw away the learner's
    /// place in the deck. Rebuilding the ViewModel on every body evaluation
    /// restarted the queue from the first card.
    @MainActor
    func testFR3StudySessionSurvivesATabSwitch() throws {
        let app = XCUIApplication()
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()

        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Study"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card "))
                .firstMatch.waitForExistence(timeout: 15))
        let startingLabel = try XCTUnwrap(cardLabel(in: app))
        let components = startingLabel.split(separator: " ")
        let startingIndex = try XCTUnwrap(Int(components[1]))
        let total = components[3]
        let nextLabel = "Card \(startingIndex + 1) of \(total)"

        app.buttons["Reveal"].tap()
        app.buttons["Knew it!"].tap()
        XCTAssertTrue(app.staticTexts[nextLabel].waitForExistence(timeout: 15))

        tabBar.buttons["Progress"].tap()
        tabBar.buttons["Study"].tap()

        XCTAssertTrue(
            app.staticTexts[nextLabel].waitForExistence(timeout: 15),
            "Session restarted after a tab switch. Hierarchy:\n\(app.debugDescription)")
    }

    /// The Languages screen lists Hindi as a real, locked pack. It must be visible
    /// and must not be selectable — Phase 11 is what makes it buyable.
    @MainActor
    func testFR1LockedLanguageIsListedButNotSelectable() throws {
        let app = XCUIApplication()
        app.launch()

        let hindi = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "हिन्दी")
        ).firstMatch
        XCTAssertTrue(
            hindi.waitForExistence(timeout: 15),
            "No Hindi row. Hierarchy:\n\(app.debugDescription)")
        XCTAssertEqual(hindi.label, "हिन्दी, locked")

        // Tap it. The row is deliberately not `.disabled()` — that dimmed the label
        // below the contrast floor — so the real assertion is on the outcome, not on
        // the styling: selecting a locked pack must not make it the active language.
        hindi.tap()
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "हिन्दी"))
                .firstMatch.label,
            "हिन्दी, locked",
            "a locked pack became active. Hierarchy:\n\(app.debugDescription)")
    }

    /// NFR-4, NFR-5, NFR-6: Xcode's built-in accessibility audit on each core
    /// screen. Catches missing labels, insufficient contrast, and clipping at
    /// large Dynamic Type sizes automatically, on every push. What it *can't*
    /// judge — whether a label is meaningful, not just present — is the manual
    /// VoiceOver walkthrough documented in docs/phase-10-verification.md.
    @MainActor
    func testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 15))
        try performAudit(on: app)

        // Settings — a whole screen the audit had never seen, carrying a
        // Stepper, a Toggle and a Link, none of which any other screen uses.
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        try performAudit(on: app)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 15))

        // The purchase sheet — a whole screen the audit had never seen, and the
        // one place the app asks for money. It reaches `unavailable` rather than
        // `ready` here: `xcodebuild test` from the command line gives the app no
        // StoreKit test environment on iOS 26.5 (see StoreKitPurchaseServiceTests).
        // The chrome, the copy and the contrast are the same either way.
        let hindi = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "हिन्दी")
        ).firstMatch
        XCTAssertTrue(hindi.waitForExistence(timeout: 15))
        hindi.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        try performAudit(on: app)
        app.buttons["Done"].tap()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()

        tabBar.buttons["Study"].tap()
        // Not an exact "Card 1 of N" match: other tests' grade() calls shift
        // today's real session size and starting position. The audit only
        // needs a card on screen, not a specific count.
        let card = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card "))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        try performAudit(on: app)

        app.buttons["Reveal"].tap()
        try performAudit(on: app)

        tabBar.buttons["Progress"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "words learned"))
                .firstMatch.waitForExistence(timeout: 15))
        try performAudit(on: app)
    }

    /// NFR-4, NFR-5, NFR-6 on the two Study screens the audit had never seen
    /// (C-3): the caught-up screen and the completion screen.
    ///
    /// They need opposite things. `caughtUp` is reachable organically — grade a
    /// session to its end and nothing is due, because scheduling is day-granular
    /// (L-1), so even a forgotten word returns tomorrow rather than in ten
    /// minutes. That is what makes the loop below terminate.
    @MainActor
    func testNFR4NFR5NFR6AccessibilityAuditOnTheCaughtUpScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()
        app.tabBars.firstMatch.buttons["Study"].tap()

        let caughtUp = app.staticTexts["You're caught up"]
        let reveal = app.buttons["Reveal"]
        // Bounded: the session is the day's due reviews plus at most N=10 new
        // words, and other test methods in this run may have spent some of that
        // cap already. 60 is far above any real session and still terminates.
        for _ in 0..<60 where !caughtUp.exists {
            guard reveal.waitForExistence(timeout: 15) else { break }
            reveal.tap()
            app.buttons["Knew it!"].tap()
        }

        XCTAssertTrue(
            caughtUp.waitForExistence(timeout: 15),
            "never reached the caught-up screen. Hierarchy:\n\(app.debugDescription)")
        try performAudit(on: app)
    }

    /// The completion screen is the product's deliberate ending, and it was the
    /// least-tested screen in the app. It cannot be reached by tapping: FR-11
    /// needs every word in the pack to have met `L`, a 14-day interval, against
    /// a 1000-word pack and a real clock. So this one launches the app with the
    /// DEBUG-only fixture wiring in `AppDependencies`.
    @MainActor
    func testFR11AccessibilityAuditOnTheCompletionScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestAllWordsLearned"]
        app.launch()

        let french = frenchButton(in: app)
        XCTAssertTrue(french.waitForExistence(timeout: 15))
        french.tap()
        app.tabBars.firstMatch.buttons["Study"].tap()

        let ending = app.staticTexts["You've learned all the words in this language."]
        XCTAssertTrue(
            ending.waitForExistence(timeout: 15),
            "the fixture did not produce the completion screen. Hierarchy:\n\(app.debugDescription)"
        )
        XCTAssertTrue(app.buttons["Add another language — $0.99"].exists)
        try performAudit(on: app)
    }

    /// NFR-12: the UI chrome resolves through the localization catalog — this
    /// is the "prove it, don't just wire it" step. Only the tab labels are
    /// checked; if the catalog resolves for these chrome strings it resolves
    /// for all of them (same mechanism, same file).
    @MainActor
    func testNFR12UIChromeIsLocalizedIntoSpanish() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.buttons["Estudiar"].waitForExistence(timeout: 15),
            "Study tab did not render in Spanish. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(tabBar.buttons["Idiomas"].exists)
        XCTAssertTrue(tabBar.buttons["Progreso"].exists)
    }

    /// FR-16's acceptance is *reachability*, not content — a ViewModel test
    /// cannot prove a screen can be got to. This is the half that was missing
    /// as N-4, and the half a green traceability report claimed was covered.
    @MainActor
    func testFR16SettingsIsReachableFromLanguages() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 15))

        let settings = app.buttons["Settings"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 15),
            "no Settings row on the Languages screen. Hierarchy:\n\(app.debugDescription)")
        settings.tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10),
            "Settings did not push its screen. Hierarchy:\n\(app.debugDescription)")

        // The licence condition itself: the attribution has to be *visible*,
        // not merely present in a pack file.
        let attribution = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "wordfreq")
        ).firstMatch
        XCTAssertTrue(
            attribution.waitForExistence(timeout: 10),
            "no wordfreq attribution on Settings. Hierarchy:\n\(app.debugDescription)")
    }
}

extension FullDeckUITests {
    /// FR-14: tapping a locked row opens the purchase sheet. The sheet reaches
    /// `unavailable` here rather than `ready` — `xcodebuild test` from the
    /// command line does not give the app a StoreKit test environment on iOS
    /// 26.5 (see StoreKitPurchaseServiceTests) — but that it *opens* and says
    /// something honest is the behaviour under test.
    @MainActor
    func testFR14TappingALockedLanguageOpensThePurchaseSheet() throws {
        let app = XCUIApplication()
        app.launch()

        let hindi = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "हिन्दी")
        ).firstMatch
        XCTAssertTrue(hindi.waitForExistence(timeout: 15))
        hindi.tap()

        XCTAssertTrue(
            app.buttons["Done"].waitForExistence(timeout: 10),
            "no purchase sheet. Hierarchy:\n\(app.debugDescription)")
    }
}
