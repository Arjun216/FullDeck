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

struct FakeStoreError: Error, Equatable, Sendable {}

@Test("NFR-10 an injected saveErrorOverride is thrown from save")
func saveErrorOverrideThrows() async throws {
    let store = InMemoryReviewStore(saveErrorOverride: FakeStoreError())

    await #expect(throws: FakeStoreError()) {
        try await store.save(ReviewState(wordID: chat))
    }
}
