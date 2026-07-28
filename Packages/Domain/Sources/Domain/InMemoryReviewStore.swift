import Foundation

/// In-memory `ReviewStore` double for Presentation-layer tests (Phase 8).
public actor InMemoryReviewStore: ReviewStore {
    private var statesByWord: [WordID: ReviewState]
    private let saveErrorOverride: (any Error & Sendable)?

    public init(seed: [ReviewState] = [], saveErrorOverride: (any Error & Sendable)? = nil) {
        var initial: [WordID: ReviewState] = [:]
        for state in seed {
            initial[state.wordID] = state
        }
        self.statesByWord = initial
        self.saveErrorOverride = saveErrorOverride
    }

    public func reviewState(for word: WordID) async throws -> ReviewState? {
        statesByWord[word]
    }

    public func save(_ state: ReviewState) async throws {
        if let saveErrorOverride { throw saveErrorOverride }
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
