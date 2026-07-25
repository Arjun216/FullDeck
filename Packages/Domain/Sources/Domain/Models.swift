import Foundation

/// Opaque per-word key, minted by the language pack (`"fr:chat:NOUN"`).
/// A wrapper rather than a bare `String` so a word key can never be passed
/// where a language code or a lemma is expected.
public struct WordID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The learner's self-assessment after revealing a card (FR-5).
public enum Grade: Sendable, CaseIterable {
    case again
    case hard
    case good
    case easy
}

/// Everything the scheduler needs to know about one word, and everything it
/// writes back. A value type: `schedule` returns a new state, never mutates.
public struct ReviewState: Equatable, Sendable {
    public let wordID: WordID
    /// SM-2 difficulty multiplier: higher = intervals grow faster.
    public var easeFactor: Double
    public var intervalDays: Int
    /// Consecutive passing reviews; a failing grade resets it.
    public var repetitions: Int
    public var nextReviewDate: Date

    /// A never-reviewed word: `.distantPast` means "due now" without needing an
    /// optional date and the branch that comes with it.
    public init(
        wordID: WordID,
        easeFactor: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        nextReviewDate: Date = .distantPast
    ) {
        self.wordID = wordID
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
    }
}
