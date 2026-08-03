import Foundation

/// One day on FR-17's outcome trend. Both counts are cumulative — FR-17 asks
/// for words that have *moved into* learning and into learned — so both curves
/// rise monotonically and the gap between them is the in-flight set.
///
/// Plotting the *currently* learning population instead would fall as words
/// graduate: a line that drops when the learner succeeds, on the one screen
/// whose point is the climb toward 1000.
public struct TrendPoint: Equatable, Sendable {
    public let day: Date
    /// Cumulative words that have entered learning by this day.
    public let started: Int
    /// Cumulative words that have met `L` by this day. Never exceeds `started`.
    public let learned: Int

    public init(day: Date, started: Int, learned: Int) {
        self.day = day
        self.started = started
        self.learned = learned
    }
}

/// Progress computed from a pack plus `ReviewStore.allStates(...)` — the type
/// `architecture.md` §3 has named since Phase 9. Pure, and needs no new port:
/// every input is already on `ReviewState`.
public struct StatsService: Sendable {
    public init() {}

    /// FR-17. One point per day from the earliest `firstReviewedDate` to
    /// `today`, both ends inclusive.
    ///
    /// `today` is a parameter rather than an injected clock, matching
    /// `Scheduler.schedule(_:grade:today:)` — the type stays a pure function of
    /// its arguments, so determinism is structural rather than a discipline.
    ///
    /// Per-day rather than only on days something changed: a cumulative count is
    /// truthful under any interpolation the chart picks, where sparse points
    /// would draw a diagonal across a week when nothing happened.
    public func trend(states: [ReviewState], today: Date) -> [TrendPoint] {
        let started = states.compactMap(\.firstReviewedDate).map(DayCalendar.startOfDay).sorted()
        let learned = states.compactMap(\.learnedDate).map(DayCalendar.startOfDay).sorted()
        guard let first = started.first else { return [] }
        let end = DayCalendar.startOfDay(today)
        guard first <= end else { return [] }

        var points: [TrendPoint] = []
        var startedIndex = 0
        var learnedIndex = 0
        var day = first
        while day <= end {
            while startedIndex < started.count, started[startedIndex] <= day { startedIndex += 1 }
            while learnedIndex < learned.count, learned[learnedIndex] <= day { learnedIndex += 1 }
            points.append(TrendPoint(day: day, started: startedIndex, learned: learnedIndex))
            day = DayCalendar.adding(days: 1, to: day)
        }
        return points
    }

    /// FR-18. Words the learner currently finds hardest, hardest first.
    ///
    /// Ranked by ease alone, because ease *is* the running difficulty estimate.
    /// `Scheduler` adds +0.05 on every pass, so a word that lapsed once and has
    /// since been recalled four times is back at `startingEase` and drops off
    /// this list — correct, not lossy: FR-18 asks what is hard *now*, and a
    /// permanent record of old mistakes is closer to a shame list than to help.
    ///
    /// A state whose word is no longer in the pack is skipped rather than
    /// crashing: packs are versioned and a word can leave one (NFR-10).
    public func hardestWords(
        in pack: LanguagePack, states: [ReviewState], limit: Int
    ) -> [WordEntry] {
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`, which traps on a
        // duplicate. The validator forbids duplicate ids; bad data must still not
        // crash the app.
        // Broken into typed steps on purpose: as one chained expression this
        // defeated the type checker outright ("unable to type-check this
        // expression in reasonable time").
        let byID = Dictionary(
            pack.words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var scored: [(ease: Double, word: WordEntry)] = []
        for state in states where state.easeFactor < ReviewState.startingEase {
            guard let word = byID[state.wordID] else { continue }
            scored.append((ease: state.easeFactor, word: word))
        }

        // Ties break on rank so the list cannot reorder between two loads —
        // a flickering list is also an unreproducible test.
        scored.sort { lhs, rhs in
            lhs.ease == rhs.ease ? lhs.word.rank < rhs.word.rank : lhs.ease < rhs.ease
        }
        return scored.prefix(limit).map(\.word)
    }
}

extension Array where Element == TrendPoint {
    /// FR-17's acceptance sentence, read off the series rather than recomputed
    /// from the states — one derivation, so the number and the curve cannot
    /// disagree.
    ///
    /// Both ends inclusive: a milestone dated exactly `today − days` counts as
    /// within the window, so the baseline is the day *before* it.
    public func learnedInLast(_ days: Int) -> Int {
        guard let latest = last else { return 0 }
        let baselineDay = DayCalendar.adding(days: -(days + 1), to: latest.day)
        let baseline = self.last(where: { $0.day <= baselineDay })?.learned ?? 0
        return latest.learned - baseline
    }
}
