import Domain
import Foundation
import Testing

@testable import FullDeck

// The fixture builder below reshapes the bundled pack as untyped JSON, which needs
// two casts. `force_cast` is a default rule and CI runs --strict, so the file
// disables it rather than wrapping test-fixture plumbing in ten lines of ceremony.
// swiftlint:disable force_cast

/// Writes a real packs directory to a temp location by truncating the bundled
/// French pack to its first `wordCount` entries. Truncation keeps every rule the
/// Swift validator checks: ranks stay 1...n and unique, ids stay unique, and
/// `word_count` is rewritten to match (VR-2). Hand-writing a fixture would risk
/// tripping a rule the plan can't foresee; real data can't.
@MainActor
private func makeTempPacksDirectory(wordCount: Int) throws -> URL {
    let source = AppDependencies.bundledPacksDirectory.appending(path: "fr.pack.json")
    var pack = try JSONSerialization.jsonObject(with: Data(contentsOf: source))
        as! [String: Any]
    let words = (pack["words"] as! [[String: Any]]).prefix(wordCount)
    pack["words"] = Array(words)
    pack["word_count"] = words.count

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "packs-\(wordCount)-\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: pack)
        .write(to: directory.appending(path: "fr.pack.json"))
    try JSONSerialization.data(withJSONObject: [
        "packs": [[
            "language_code": "fr", "display_name": "Français",
            "filename": "fr.pack.json", "unlocked_by_default": true,
        ]]
    ]).write(to: directory.appending(path: "manifest.json"))
    return directory
}

@MainActor
private func makeStudy(
    _ dependencies: AppDependencies, today: Date, newWordCap: Int = 10
) -> StudyViewModel {
    StudyViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore, scheduler: dependencies.scheduler,
        sessionBuilder: dependencies.sessionBuilder, speech: FakeSpeechService(),
        clock: FixedDayClock(today: today), newWordCap: newWordCap)
}

@Test("FR-1 the bundled French pack loads and reports 1000 words")
@MainActor
func bundledFrenchPackLoads() async throws {
    let dependencies = try AppDependencies.make(
        packsDirectory: AppDependencies.bundledPacksDirectory, inMemory: true)

    let pack = try await dependencies.packStore.loadPack(LanguageCode("fr"))

    #expect(pack.wordCount == 1000)
    #expect(pack.words.count == 1000)
    #expect(pack.words.first?.rank == 1)
}

@Test("FR-9 grades persist through the real store and survive a relaunch")
@MainActor
func gradesPersistAcrossRelaunch() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 5)
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)
    let study = makeStudy(dependencies, today: day0, newWordCap: 3)

    await study.start()
    for _ in 0..<3 {
        study.reveal()
        await study.grade(.good)
    }

    // "Relaunch": a brand-new ViewModel over the same store.
    let progress = ProgressViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore)
    await progress.load()

    let states = try await dependencies.reviewStore.allStates(LanguageCode("fr"))
    #expect(states.count == 3)
    #expect(states.allSatisfy { $0.firstReviewedDate == day0 })
    #expect(progress.state == .ready(learned: 0, total: 5))
}

@Test("FR-11 a pack studied to the learned threshold reaches the completion state")
@MainActor
func studyingToThresholdReachesCompletion() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 3)
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)

    // Three passes take every word to interval 15 (1 → 6 → 15), crossing L = 14
    // on the third. Reviews land on day 0, day 1, and day 7.
    for reviewDay in [0, 1, 7] {
        let study = makeStudy(dependencies, today: day(reviewDay), newWordCap: 3)
        await study.start()
        while case .card = study.state {
            study.reveal()
            await study.grade(.good)
        }
    }

    let progress = ProgressViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore)
    await progress.load()
    #expect(progress.state == .ready(learned: 3, total: 3))
    #expect(progress.state.isComplete)

    let afterwards = makeStudy(dependencies, today: day(8), newWordCap: 3)
    await afterwards.start()
    #expect(afterwards.state == .complete(nextDue: day(22)))
}

@Test("NFR-10 a corrupt pack surfaces a failed state instead of crashing")
@MainActor
func corruptPackSurfacesFailedStateEndToEnd() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 3)
    try Data("{ not json".utf8).write(to: directory.appending(path: "fr.pack.json"))
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)

    let study = makeStudy(dependencies, today: day0)
    await study.start()

    #expect(
        study.state
            == .failed("This language's data couldn't be read. Try reinstalling the app."))
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedStateEndToEnd() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 3)
    try FileManager.default.removeItem(at: directory.appending(path: "fr.pack.json"))
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)

    let progress = ProgressViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore)
    await progress.load()

    #expect(
        progress.state
            == .failed("This language's data couldn't be read. Try reinstalling the app."))
}

// swiftlint:enable force_cast
