import Domain
import Testing

@testable import FullDeck

@MainActor
private func makeProgressViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    seed: [ReviewState] = []
) -> ProgressViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:])
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
