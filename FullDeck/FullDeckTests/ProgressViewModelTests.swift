import Domain
import Testing

@testable import FullDeck

@MainActor
private func makeProgressViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    seed: [ReviewState] = [],
    errorOverride: PackLoadError? = nil
) -> ProgressViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:],
        errorOverride: errorOverride)
    return ProgressViewModel(
        languageCode: code, packStore: packStore,
        reviewStore: InMemoryReviewStore(seed: seed))
}

@Test("FR-10 progress reports words learned out of the pack's word count")
@MainActor
func progressReportsLearnedOutOfTotal() async {
    let learned = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 21, repetitions: 4,
        nextReviewDate: day(21), firstReviewedDate: day(-30), learnedDate: day(-2))
    let viewModel = makeProgressViewModel(seed: [learned])

    await viewModel.load()

    #expect(viewModel.state == .ready(learned: 1, total: 2))
}

@Test("FR-10 an untouched language reads zero learned")
@MainActor
func untouchedLanguageReadsZero() async {
    let viewModel = makeProgressViewModel()

    await viewModel.load()

    #expect(viewModel.state == .ready(learned: 0, total: 2))
}

@Test("FR-11 progress reports the pack as complete when every word is learned")
@MainActor
func progressReportsCompleteWhenAllLearned() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeProgressViewModel(
        pack: pack, seed: pack.words.map { learnedState($0) })

    await viewModel.load()

    #expect(viewModel.state == .ready(learned: 2, total: 2))
    #expect(viewModel.state.isComplete)
}

@Test("FR-11 a partly learned pack is not complete")
@MainActor
func partlyLearnedPackIsNotComplete() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeProgressViewModel(pack: pack, seed: [learnedState(pack.words[0])])

    await viewModel.load()

    #expect(!viewModel.state.isComplete)
}

@Test("FR-11 an empty or unloaded pack is never complete")
@MainActor
func unloadedPackIsNotComplete() async {
    let viewModel = makeProgressViewModel()

    #expect(!viewModel.state.isComplete)  // still .loading
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedProgressState() async {
    let viewModel = makeProgressViewModel(pack: nil)

    await viewModel.load()

    guard case .failed = viewModel.state else {
        Issue.record("expected a failed state, got \(viewModel.state)")
        return
    }
}

@Test("NFR-10 a schema-version mismatch surfaces the update message")
@MainActor
func progressSchemaVersionMismatchSurfacesUpdateMessage() async {
    let viewModel = makeProgressViewModel(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await viewModel.load()

    #expect(viewModel.state == .failed("This language needs an app update."))
}
