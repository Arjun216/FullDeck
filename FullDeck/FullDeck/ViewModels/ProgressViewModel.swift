import Domain
import Foundation
import Observation

/// Words learned out of the language's total (FR-10), the outcome trend
/// (FR-17), and the hardest words (FR-18). No streaks, no time-spent, no review
/// counts — §4 rules those out, and this screen stays outcome-only.
@MainActor
@Observable
final class ProgressViewModel {
    /// Everything the screen draws, derived from one pack load and one states
    /// load. A struct rather than loose associated values: the screen now has
    /// three sections, and a four-tuple in an enum case reads like nothing.
    struct Snapshot: Equatable {
        let learned: Int
        let total: Int
        let trend: [TrendPoint]
        let hardest: [WordEntry]
    }

    enum State: Equatable {
        case loading
        case ready(Snapshot)
        case failed(String)
    }

    /// Five reads as "here is what to watch"; ten starts to read as a report
    /// card, and in an app that bans streak-guilt the length of a list of your
    /// own mistakes is a tone decision.
    static let hardestWordLimit = 5

    private(set) var state: State = .loading

    private let languageCode: LanguageCode
    private let packStore: PackStore
    private let reviewStore: ReviewStore
    private let stats: StatsService
    private let clock: DayClock

    init(
        languageCode: LanguageCode, packStore: PackStore, reviewStore: ReviewStore,
        stats: StatsService = StatsService(), clock: DayClock
    ) {
        self.languageCode = languageCode
        self.packStore = packStore
        self.reviewStore = reviewStore
        self.stats = stats
        self.clock = clock
    }

    func load() async {
        state = .loading
        do {
            let pack = try await packStore.loadPack(languageCode)
            // One read of the states feeds all three sections. `ReviewStore` used
            // to expose a `progress(_:)` that recomputed the count store-side;
            // two paths to one number can disagree, so it was deleted.
            let states = try await reviewStore.allStates(languageCode)
            state = .ready(
                Snapshot(
                    learned: ProgressSummary(states: states).wordsLearned,
                    total: pack.wordCount,
                    trend: stats.trend(states: states, today: clock.today),
                    hardest: stats.hardestWords(
                        in: pack, states: states, limit: Self.hardestWordLimit)))
        } catch let error as PackLoadError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(String(localized: "Couldn't load your progress."))
        }
    }
}

extension ProgressViewModel.State {
    /// FR-11. `total > 0` guards the degenerate case: an empty pack is not an
    /// achievement, and `.loading` is not a verdict.
    var isComplete: Bool {
        if case .ready(let snapshot) = self {
            return snapshot.total > 0 && snapshot.learned == snapshot.total
        }
        return false
    }
}
