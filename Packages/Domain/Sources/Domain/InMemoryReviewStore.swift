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
        let prefix = "\(languageCode.rawValue):"
        return statesByWord.values.filter { $0.wordID.rawValue.hasPrefix(prefix) }
    }

    public func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary {
        let states = try await allStates(languageCode)
        let learned = states.filter { $0.learnedDate != nil }.count
        let inProgress = states.filter { $0.firstReviewedDate != nil && $0.learnedDate == nil }
            .count
        return ProgressSummary(
            wordsLearned: learned, wordsInProgress: inProgress,
            totalReviewed: learned + inProgress)
    }
}
