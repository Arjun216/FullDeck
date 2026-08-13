import XCTest

/// NFR-2 (cold launch ≤ 2.0 s) and NFR-3 (reveal/advance ≤ 100 ms).
///
/// **Not a CI gate, on purpose.** A shared GitHub macOS runner is too noisy for
/// a 100 ms assertion — gating there produces flakes, not signal — so
/// `.github/workflows/ci.yml` skips this class the same way it skips the
/// StoreKit adapter suite, and the numbers live in `docs/test-plan.md` §4
/// instead. Run it with `scripts/measure-performance.sh`.
///
/// **What a pass here does and does not mean.** These run on a simulator, on an
/// Apple-silicon Mac, which is *faster* than the baseline device (iPhone SE 3 /
/// iPhone 12 class, per requirements §Assumptions). So a failure here is
/// conclusive and a pass is only evidence — the acceptance measurement NFR-2 and
/// NFR-3 actually ask for needs the phone, and is on the manual QA checklist.
///
/// The NFR-3 numbers also include XCUITest's own tap-dispatch and
/// element-query overhead, which is not latency the learner experiences. Read
/// them as an upper bound.
final class PerformanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func frenchButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Français")).firstMatch
    }

    /// NFR-2. `XCTApplicationLaunchMetric` measures process start to the first
    /// frame, which is the "interactive first screen" the requirement names.
    @MainActor
    func testNFR2ColdLaunchTime() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // NFR-3 is deliberately not measured here. A card-advance test lived in this
    // file and reported 1.49 s — because `waitForExistence` polls on roughly
    // one-second intervals, so every XCUITest timing has a ~1 s floor regardless
    // of how fast the app is. It measured the harness. A 100 ms target is simply
    // below XCUITest's resolution.
    //
    // `FullDeckTests/GradeLatencyTests` measures the same transition in-process
    // against a real on-disk store instead, which is every millisecond between
    // the tap and the next card being ready to draw. The frames themselves need
    // Instruments on a device, and are on the manual QA checklist.
}
