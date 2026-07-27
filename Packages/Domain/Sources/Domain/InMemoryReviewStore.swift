import Foundation

/// In-memory `ReviewStore` double for Presentation-layer tests (Phase 8).
public actor InMemoryReviewStore: ReviewStore {
    private var statesByWord: [WordID: ReviewState]

    public init(seed: [ReviewState] = []) {
        var initial: [WordID: ReviewState] = [:]
        for state in seed {
            initial[state.wordID] = state
        }
        self.statesByWord = initial
    }

    public func reviewState(for word: WordID) async throws -> ReviewState? {
        statesByWord[word]
    }

    public func save(_ state: ReviewState) async throws {
        statesByWord[state.wordID] = state
    }

    public func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState] {
        statesByWord.values.filter { $0.wordID.languageCode == languageCode }
            .sorted { $0.wordID.rawValue < $1.wordID.rawValue }
    }

    public func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary {
        let states = try await allStates(languageCode)
        return ProgressSummary(states: states)
    }
}
