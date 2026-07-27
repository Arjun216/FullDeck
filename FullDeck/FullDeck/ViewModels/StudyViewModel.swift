import Domain
import Foundation
import Observation

/// Drives one study session: presents a card at a time, enforces active recall
/// (nothing is graded before it is revealed), and feeds the grade back to the
/// scheduler (FR-3, FR-5, FR-6, FR-7, FR-8, FR-12).
///
/// `@Observable` (iOS 17+) makes SwiftUI re-render exactly the views that read a
/// property that changed. `@MainActor` keeps every state mutation on the main
/// thread; the `await`s below hop off for I/O and resume back on it.
@MainActor
@Observable
final class StudyViewModel {
    enum State: Equatable {
        case loading
        case card(Card)
        /// Nothing due and the daily cap is spent (FR-12). `nextDue` is the
        /// earliest future review, `nil` when there is none.
        case caughtUp(nextDue: Date?)
        case failed(String)
    }

    struct Card: Equatable {
        let entry: WordEntry
        var isRevealed: Bool
        /// 1-based position in this session, for a plain "3 of 12" readout.
        let index: Int
        let total: Int
    }

    private(set) var state: State = .loading
    private(set) var audioUnavailable = false

    private let languageCode: LanguageCode
    private let packStore: PackStore
    private let reviewStore: ReviewStore
    private let scheduler: Scheduler
    private let sessionBuilder: SessionBuilder
    private let speech: SpeechService
    private let clock: DayClock
    private let newWordCap: Int

    private var queue: [WordEntry] = []
    private var position = 0
    private var states: [ReviewState] = []

    init(
        languageCode: LanguageCode,
        packStore: PackStore,
        reviewStore: ReviewStore,
        scheduler: Scheduler,
        sessionBuilder: SessionBuilder,
        speech: SpeechService,
        clock: DayClock,
        newWordCap: Int = SessionBuilder.defaultNewWordCap
    ) {
        self.languageCode = languageCode
        self.packStore = packStore
        self.reviewStore = reviewStore
        self.scheduler = scheduler
        self.sessionBuilder = sessionBuilder
        self.speech = speech
        self.clock = clock
        self.newWordCap = newWordCap
    }

    func start() async {
        state = .loading
        do {
            let pack = try await packStore.loadPack(languageCode)
            states = try await reviewStore.allStates(languageCode)
            queue = sessionBuilder.build(
                pack: pack, states: states, today: clock.today, newWordCap: newWordCap)
            position = 0
            showCurrentCard()
        } catch {
            // NFR-10: bad or missing data is a state, never a crash. Phase 10
            // owns the user-facing copy.
            state = .failed("Couldn't load this language.")
        }
    }

    /// Active recall (FR-5): the learner commits to an attempt, *then* sees the
    /// answer. Nothing can be graded before this.
    func reveal() {
        guard case .card(var card) = state, !card.isRevealed else { return }
        card.isRevealed = true
        state = .card(card)
    }

    /// Reveal → self-grade → schedule → persist → next card (FR-5, FR-8).
    func grade(_ grade: Grade) async {
        guard case .card(let card) = state, card.isRevealed else { return }
        let today = clock.today
        do {
            let current =
                try await reviewStore.reviewState(for: card.entry.id)
                ?? ReviewState(wordID: card.entry.id)
            var next = scheduler.schedule(current, grade: grade, today: today)
            // Stamping the first review here is what makes FR-4's per-day cap
            // countable. `learnedDate` stays Phase 9's job.
            if next.firstReviewedDate == nil {
                next.firstReviewedDate = today
            }
            try await reviewStore.save(next)
            states.removeAll { $0.wordID == next.wordID }
            states.append(next)
        } catch {
            state = .failed("Couldn't save your progress.")
            return
        }
        position += 1
        showCurrentCard()
    }

    private func showCurrentCard() {
        guard position < queue.count else {
            state = .caughtUp(nextDue: nextDueDate())
            return
        }
        state = .card(
            Card(
                entry: queue[position], isRevealed: false, index: position + 1,
                total: queue.count))
    }

    /// The earliest review still in the future — what the caught-up screen tells
    /// the learner to come back for (FR-12).
    private func nextDueDate() -> Date? {
        states.map(\.nextReviewDate).filter { $0 > clock.today }.min()
    }
}
