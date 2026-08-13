import Domain
import Foundation
import XCTest

@testable import FullDeck

/// NFR-3's measurable half, taken in-process.
///
/// **Why this is not an XCUITest.** One was written. It tapped a grade button and
/// waited for the next card, and reported **1.49 s** — because `waitForExistence`
/// polls on roughly one-second intervals, so any XCUITest-based timing has a
/// ~1 s floor no matter how fast the app is. The number measured the harness.
/// A 100 ms target is below XCUITest's resolution, full stop.
///
/// **What this measures instead.** `grade()` end to end against a real on-disk
/// SwiftData store: schedule the review, persist it, pick the next card, publish
/// the new state. That is every millisecond the app spends between the tap and
/// the next card being *ready to draw* — all of NFR-3 except the draw itself.
///
/// **What it does not measure.** The SwiftUI render, the display link, and
/// anything device-specific. "No perceptible frame drops (target 60 fps)" is the
/// other half of NFR-3 and needs Instruments on the phone; it is on the manual
/// QA checklist, and `docs/test-plan.md` §4 records it as outstanding.
///
/// XCTest rather than Swift Testing, which the rest of this target uses:
/// `measure` has no Swift Testing equivalent yet.
final class GradeLatencyTests: XCTestCase {

    /// A fixed instant, per the determinism rule — never the wall clock.
    private let today = Date(timeIntervalSince1970: 86_400 * 20_000)

    /// 200 words so a 10-iteration measurement never runs the deck out, with a
    /// cap high enough that every iteration grades a real card.
    @MainActor
    private func makeStudyViewModel() throws -> StudyViewModel {
        let source = AppDependencies.bundledPacksDirectory.appending(path: "fr.pack.json")
        // swiftlint:disable force_cast
        var pack =
            try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
        let words = (pack["words"] as! [[String: Any]]).prefix(200)
        // swiftlint:enable force_cast
        pack["words"] = Array(words)
        pack["word_count"] = words.count

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "perf-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: pack)
            .write(to: directory.appending(path: "fr.pack.json"))
        try JSONSerialization.data(withJSONObject: [
            "packs": [
                [
                    "language_code": "fr", "display_name": "Français",
                    "filename": "fr.pack.json", "unlocked_by_default": true,
                ]
            ]
        ]).write(to: directory.appending(path: "manifest.json"))

        // `inMemory: false` on purpose: NFR-3 is about the app as shipped, and
        // the shipped store writes to disk. An in-memory container would measure
        // a persistence layer nobody runs.
        let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: false)
        return StudyViewModel(
            languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
            reviewStore: dependencies.reviewStore, scheduler: dependencies.scheduler,
            sessionBuilder: dependencies.sessionBuilder, speech: FakeSpeechService(),
            clock: FixedDayClock(today: today), newWordCap: 200)
    }

    /// NFR-3: reveal + grade + persist + next card, ≤ 100 ms.
    ///
    /// Not an assertion — a measurement. The target is recorded in
    /// `docs/test-plan.md` §4 rather than gated here, for the reason the whole
    /// performance suite is ungated: a shared runner's numbers are noise.
    @MainActor
    func testNFR3GradeAndAdvanceLatency() throws {
        let viewModel = try makeStudyViewModel()
        let started = expectation(description: "session started")
        Task {
            await viewModel.start()
            started.fulfill()
        }
        wait(for: [started], timeout: 30)

        measure {
            let advanced = expectation(description: "advanced")
            Task { @MainActor in
                viewModel.reveal()
                await viewModel.grade(.recalled)
                advanced.fulfill()
            }
            wait(for: [advanced], timeout: 30)
        }
    }
}
