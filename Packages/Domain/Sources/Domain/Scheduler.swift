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
    /// `.recalled` would be a silent no-op on a fresh word.
    static let easeRange = 1.3...3.0
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
        //
        // `recalled` must carry a *positive* delta, not zero. At zero, ease
        // could only ever decay toward its floor — Anki's "ease hell" — and a
        // word that lapsed once could never recover from it.
        let easeDelta: Double =
            switch grade {
            case .forgot: -0.20
            case .recalled: 0.05
            }
        // Rounded to the two decimals the delta table is written in. Neither 0.05
        // nor 0.20 is representable in binary, so an unrounded lapse plus four
        // passes lands on 2.499999999999999 rather than back on `startingEase` —
        // and every consumer comparing ease against a literal (FR-18 ranks the
        // hardest words by exactly that) reads a recovered word as still failing.
        // Rounded here, where the value is produced, rather than tolerated at
        // each comparison.
        let ease = (state.easeFactor + easeDelta).clamped(to: Self.easeRange)
        next.easeFactor = (ease * 100).rounded() / 100
        // Reset-on-failure (FR-8): a lapse sends the word back to the bottom of
        // the ladder — tomorrow, and the fixed steps again from there.
        next.repetitions = grade == .forgot ? 0 : state.repetitions + 1
        // SM-2's ladder: the first two passes use fixed steps, after which the
        // ease factor takes over and intervals grow multiplicatively.
        let interval =
            switch (grade, state.repetitions) {
            case (.forgot, _): 1
            case (_, 0): 1
            case (_, 1): 6
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
