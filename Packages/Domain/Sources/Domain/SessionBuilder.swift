import Foundation

/// Assembles one study session: every due review, plus new words up to whatever
/// is left of the daily cap (FR-3, FR-4). Pure — the same inputs always produce
/// the same queue, and `today` is injected rather than read.
public struct SessionBuilder: Sendable {
    /// FR-4's `N`. A settings screen to change it is deferred; callers pass their
    /// own value.
    public static let defaultNewWordCap = 10

    public init() {}

    public func build(
        pack: LanguagePack,
        states: [ReviewState],
        today: Date,
        newWordCap: Int = SessionBuilder.defaultNewWordCap
    ) -> [WordEntry] {
        // Duplicate states per WordID are not expected; the second simply wins.
        let statesByWord = Dictionary(
            states.map { ($0.wordID, $0) }, uniquingKeysWith: { _, second in second })
        let today = DayCalendar.startOfDay(today)

        // Due (FR-3): has a state, and its next review lands on or before today.
        // Never capped — reviews are the debt, new words are the extra on top.
        let due =
            pack.words
            .compactMap { word -> (entry: WordEntry, due: Date)? in
                guard let state = statesByWord[word.id],
                    DayCalendar.startOfDay(state.nextReviewDate) <= today
                else { return nil }
                return (word, state.nextReviewDate)
            }
            .sorted {
                $0.due == $1.due ? $0.entry.rank < $1.entry.rank : $0.due < $1.due
            }
            .map(\.entry)

        // FR-4 counts *introductions per calendar day*, not per session, so a
        // second session on the same day cannot re-spend the cap. Scoped to this
        // pack's words (not the raw `states` array) so a state from another
        // language can never eat into this pack's cap.
        let introducedToday = pack.words
            .compactMap { statesByWord[$0.id] }
            .filter { state in
                guard let first = state.firstReviewedDate else { return false }
                return DayCalendar.isSameDay(first, today)
            }.count

        // New (FR-4): never seen, taken in frequency order, capped.
        let newWords =
            pack.words
            .filter { statesByWord[$0.id] == nil }
            .sorted { $0.rank < $1.rank }
            .prefix(max(0, newWordCap - introducedToday))

        return due + newWords
    }
}
