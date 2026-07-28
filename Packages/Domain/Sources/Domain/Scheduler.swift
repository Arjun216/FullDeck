import Foundation

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Simplified SM-2 spaced-repetition engine (FR-8).
///
/// ponytail: scheduling is day-granular — a lapsed word comes back tomorrow, not
/// in ten minutes. Anki-style intra-session relearning steps would live in the
/// Phase 8 SessionBuilder (re-queue a failed card inside the same session)
/// without this type changing at all; add them if the spot-check says lapses
/// aren't sticking.
public struct Scheduler: Sendable {
    /// Ease starts at 2.5, so the ceiling sits above the start — otherwise
    /// `.easy` would be a silent no-op on a fresh word.
    static let easeRange = 1.3...3.0
    static let hardMultiplier = 1.2
    /// Floor of 1 day is what guarantees `nextReviewDate > today` (FR-8); the
    /// one-year ceiling keeps a word from effectively disappearing forever.
    static let intervalRange = 1...365
    /// A word counts as learned once it survives a two-week gap (FR-10, FR-11).
    /// Interval-based rather than repetition-based so a low-ease word has to earn
    /// it: at ease 2.2 the third pass lands at 13.2 days and does not cross.
    static let learnedIntervalDays = 14

    public init() {}

    public func schedule(_ state: ReviewState, grade: Grade, today: Date) -> ReviewState {
        var next = state
        // A flat delta table replaces SM-2's quadratic quality formula: same
        // shape (worse answer → lower ease), but readable.
        let easeDelta: Double =
            switch grade {
            case .again: -0.20
            case .hard: -0.15
            case .good: 0
            case .easy: 0.15
            }
        next.easeFactor = (state.easeFactor + easeDelta).clamped(to: Self.easeRange)
        // Reset-on-failure (FR-8): a lapse sends the word back to the bottom of
        // the ladder — tomorrow, and the fixed steps again from there.
        next.repetitions = grade == .again ? 0 : state.repetitions + 1
        // SM-2's ladder: the first two passes use fixed steps, after which the
        // ease factor takes over and intervals grow multiplicatively.
        let interval =
            switch (grade, state.repetitions) {
            case (.again, _): 1
            case (_, 0): 1
            case (_, 1): 6
            // `hard` deliberately departs from textbook SM-2, which multiplies
            // by the ease factor even here — so "I barely got it" still
            // *lengthened* the interval. A small fixed step is the fix.
            case (.hard, _): Int((Double(state.intervalDays) * Self.hardMultiplier).rounded())
            default: Int((Double(state.intervalDays) * next.easeFactor).rounded())
            }
        next.intervalDays = interval.clamped(to: Self.intervalRange)
        // Derived from the *clamped* interval — the two must never disagree.
        next.nextReviewDate = DayCalendar.adding(days: next.intervalDays, to: today)
        return stampingMilestones(on: next, previous: state, today: today)
    }

    /// FR-4 and FR-10/FR-17's milestone dates. Split out of `schedule` purely to
    /// keep its cyclomatic complexity under the SwiftLint gate — both lines are a
    /// pure function of the same `(state, grade, today)` `schedule` already took.
    private func stampingMilestones(
        on next: ReviewState, previous state: ReviewState, today: Date
    ) -> ReviewState {
        var next = next
        // FR-4's per-day new-word cap counts introductions by this date.
        if next.firstReviewedDate == nil { next.firstReviewedDate = today }
        // Sticky (FR-17): set once on the crossing review and never cleared — not
        // even by a lapse, which resets intervalDays to 1. The progress trend is
        // reconstructed from this date, so clearing it would erase history.
        if state.learnedDate == nil, next.intervalDays >= Self.learnedIntervalDays {
            next.learnedDate = today
        }
        return next
    }
}
