import Domain
import Foundation
import SwiftData
import Testing

@testable import Data

private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: PersistentReviewState.self, configurations: configuration)
}

private let chat = WordID("fr:chat:NOUN")
private let noir = WordID("fr:noir:ADJ")
private let fr = LanguageCode("fr")

@Test("FR-9 reviewState returns nil for a word that was never saved")
func reviewStateReturnsNilForUnsavedWord() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())

    let state = try await store.reviewState(for: chat)

    #expect(state == nil)
}

@Test("FR-9 a saved review state round-trips through save and reviewState")
func saveThenReviewStateRoundTrips() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    let state = ReviewState(wordID: chat, easeFactor: 2.3, intervalDays: 6, repetitions: 2)

    try await store.save(state)
    let loaded = try await store.reviewState(for: chat)

    #expect(loaded == state)
}

@Test("FR-9 saving twice for the same word updates rather than duplicates")
func saveTwiceUpdatesExistingState() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    try await store.save(ReviewState(wordID: chat, easeFactor: 2.5, intervalDays: 1))
    try await store.save(ReviewState(wordID: chat, easeFactor: 2.3, intervalDays: 6))

    let states = try await store.allStates(fr)

    #expect(states.count == 1)
    #expect(states.first?.easeFactor == 2.3)
}

@Test("FR-10 allStates only returns states for the requested language")
func allStatesFiltersByLanguage() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    try await store.save(ReviewState(wordID: chat))
    try await store.save(ReviewState(wordID: WordID("hi:sa:VERB")))

    let states = try await store.allStates(fr)

    #expect(states.map(\.wordID) == [chat])
}

@Test("FR-10 progress counts learned and in-progress words from milestone dates")
func progressComputesFromMilestoneDates() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    try await store.save(
        ReviewState(wordID: chat, firstReviewedDate: .distantPast, learnedDate: .distantPast))
    try await store.save(
        ReviewState(wordID: noir, firstReviewedDate: .distantPast, learnedDate: nil))

    let summary = try await store.progress(fr)

    #expect(summary == ProgressSummary(wordsLearned: 1, wordsInProgress: 1, totalReviewed: 2))
}

@Test("NFR-10 progress for a language with no saved state is all zeros")
func progressForEmptyLanguageIsZero() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())

    let summary = try await store.progress(fr)

    #expect(summary == ProgressSummary(wordsLearned: 0, wordsInProgress: 0, totalReviewed: 0))
}

@Test("migration smoke test: the model container initializes cleanly for the current schema")
func modelContainerInitializesCleanly() throws {
    _ = try makeContainer()
}
