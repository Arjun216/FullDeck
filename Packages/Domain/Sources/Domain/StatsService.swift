import Foundation

/// Progress computed from a pack plus `ReviewStore.allStates(...)` — the type
/// `architecture.md` §3 has named since Phase 9. Pure, and needs no new port:
/// every input is already on `ReviewState`.
public struct StatsService: Sendable {
    public init() {}

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
