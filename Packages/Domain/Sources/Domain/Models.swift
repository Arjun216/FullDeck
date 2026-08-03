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

extension WordID {
    /// The language-code prefix of this word's id (e.g. `"fr:chat:NOUN"` → `LanguageCode("fr")`).
    public var languageCode: LanguageCode {
        LanguageCode(String(rawValue.prefix(while: { $0 != ":" })))
    }
}

/// Opaque BCP-47 language code (`"fr"`, `"hi"`). A wrapper rather than a bare
/// `String` for the same reason as `WordID`: a language code can never be passed
/// where a word key is expected.
public struct LanguageCode: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The learner's self-assessment after revealing a card (FR-5).
///
/// Binary by decision (spec 2026-07-28): a four-way judgement cost decision time
/// at exactly the moment the learner should be thinking about the word. `forgot`
/// is declared first so `allCases` renders fail-left / pass-right.
public enum Grade: Sendable, CaseIterable {
    case forgot
    case recalled
}

/// Everything the scheduler needs to know about one word, and everything it
/// writes back. A value type: `schedule` returns a new state, never mutates.
public struct ReviewState: Equatable, Sendable {
    /// The ease every word starts at. `Scheduler` moves it by −0.20 on a lapse
    /// and +0.05 on a pass, so a word *below* this value has been failed more
    /// than it has since recovered — which is what FR-18 ranks by.
    public static let startingEase = 2.5

    public let wordID: WordID
    /// SM-2 difficulty multiplier: higher = intervals grow faster.
    public var easeFactor: Double
    public var intervalDays: Int
    /// Consecutive passing reviews; a failing grade resets it.
    public var repetitions: Int
    public var nextReviewDate: Date
    /// Set on the word's first review. `nil` for an untouched word. Storage
    /// plumbing for FR-17's outcome trend; Phase 9 decides exactly when this
    /// gets set, not this type.
    public var firstReviewedDate: Date?
    /// Set once the word meets the learned threshold `L` (Phase 9). `nil` until
    /// then, so `wordsLearned` is mechanically 0 everywhere until that phase.
    public var learnedDate: Date?

    /// A never-reviewed word: `.distantPast` means "due now" without needing an
    /// optional date and the branch that comes with it.
    public init(
        wordID: WordID,
        easeFactor: Double = ReviewState.startingEase,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        nextReviewDate: Date = .distantPast,
        firstReviewedDate: Date? = nil,
        learnedDate: Date? = nil
    ) {
        self.wordID = wordID
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
        self.firstReviewedDate = firstReviewedDate
        self.learnedDate = learnedDate
    }
}
