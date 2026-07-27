import Domain
import Testing

@testable import FullDeck

@Test("FR-3 starting a session presents the first card")
@MainActor
func startPresentsTheFirstCard() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeStudyViewModel(pack: pack)

    await viewModel.start()

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[0], isRevealed: false, index: 1, total: 2)))
}

@Test("FR-5 a freshly presented card hides its answer")
@MainActor
func freshCardHidesTheAnswer() async {
    let viewModel = makeStudyViewModel()

    await viewModel.start()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(!card.isRevealed)
}

@Test("FR-6 every card carries exactly one non-empty example sentence")
@MainActor
func cardCarriesOneExampleSentence() async {
    let viewModel = makeStudyViewModel()

    await viewModel.start()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(!card.entry.example.isEmpty)
}

@Test("FR-12 an empty session shows the caught-up state with the next due date")
@MainActor
func emptySessionShowsCaughtUp() async {
    let pack = frPack([entry("chat", rank: 1)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(3), firstReviewedDate: day(-6))
    let viewModel = makeStudyViewModel(
        pack: pack, newWordCap: 0, reviewStore: InMemoryReviewStore(seed: [notYetDue]))

    await viewModel.start()

    #expect(viewModel.state == .caughtUp(nextDue: day(3)))
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedState() async {
    let viewModel = makeStudyViewModel(pack: nil)

    await viewModel.start()

    guard case .failed = viewModel.state else {
        Issue.record("expected a failed state, got \(viewModel.state)")
        return
    }
}
