import Domain
import Observation

/// Words learned out of the language's total, and nothing else (FR-10). No
/// streaks, no time-spent, no review counts — those are engagement theater, and
/// the product deliberately does not have them.
///
/// Reads `0` until Phase 9 defines the learned threshold `L` and starts stamping
/// `learnedDate`.
@MainActor
@Observable
final class ProgressViewModel {
    enum State: Equatable {
        case loading
        case ready(learned: Int, total: Int)
        case failed(String)
    }

    private(set) var state: State = .loading

    private let languageCode: LanguageCode
    private let packStore: PackStore
    private let reviewStore: ReviewStore

    init(languageCode: LanguageCode, packStore: PackStore, reviewStore: ReviewStore) {
        self.languageCode = languageCode
        self.packStore = packStore
        self.reviewStore = reviewStore
    }

    func load() async {
        state = .loading
        do {
            let pack = try await packStore.loadPack(languageCode)
            let progress = try await reviewStore.progress(languageCode)
            state = .ready(learned: progress.wordsLearned, total: pack.wordCount)
        } catch {
            state = .failed("Couldn't load your progress.")
        }
    }
}

extension ProgressViewModel.State {
    /// FR-11. `total > 0` guards the degenerate case: an empty pack is not an
    /// achievement, and `.loading` is not a verdict.
    var isComplete: Bool {
        if case .ready(let learned, let total) = self { return total > 0 && learned == total }
        return false
    }
}
