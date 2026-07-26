import Foundation
import Testing

@testable import Domain

private let fr = LanguageCode("fr")
private let chat = WordID("fr:chat:NOUN")
private let noir = WordID("fr:noir:ADJ")

@Test("FR-9 InMemoryReviewStore returns nil for a word with no saved state")
func reviewStateReturnsNilWhenUnsaved() async throws {
    let store = InMemoryReviewStore()

    let state = try await store.reviewState(for: chat)

    #expect(state == nil)
}

@Test("FR-9 InMemoryReviewStore round-trips a saved state")
func saveThenReviewStateRoundTrips() async throws {
    let store = InMemoryReviewStore()
    let state = ReviewState(wordID: chat, easeFactor: 2.3, intervalDays: 6)

    try await store.save(state)
    let loaded = try await store.reviewState(for: chat)

    #expect(loaded == state)
}

@Test("FR-10 InMemoryReviewStore allStates filters by language code")
func allStatesFiltersByLanguage() async throws {
    let store = InMemoryReviewStore()
    try await store.save(ReviewState(wordID: chat))
    try await store.save(ReviewState(wordID: WordID("hi:sa:VERB")))

    let states = try await store.allStates(fr)

    #expect(states.map(\.wordID) == [chat])
}

@Test("FR-10 InMemoryReviewStore progress counts learned, in-progress and total")
func progressComputesFromMilestoneDates() async throws {
    let store = InMemoryReviewStore()
    let learned = ReviewState(
        wordID: chat, firstReviewedDate: .distantPast, learnedDate: .distantPast)
    let inProgress = ReviewState(wordID: noir, firstReviewedDate: .distantPast, learnedDate: nil)
    try await store.save(learned)
    try await store.save(inProgress)

    let summary = try await store.progress(fr)

    #expect(summary == ProgressSummary(wordsLearned: 1, wordsInProgress: 1, totalReviewed: 2))
}
