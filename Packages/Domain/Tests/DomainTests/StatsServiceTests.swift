import Foundation
import Testing

@testable import Domain

/// A fixed instant on a UTC day boundary. Domain tests never read the wall
/// clock — `scripts/determinism-check.sh` enforces it.
private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)

private func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

private func word(_ lemma: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID("fr:\(lemma):NOUN"), lemma: lemma, display: lemma, pos: .noun,
        rank: rank, register: .neutral, isFunctionWord: false, gloss: "gloss of \(lemma)",
        example: "Une phrase avec \(lemma).", aliases: [])
}

private func pack(_ entries: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "Français", baseLanguage: "en", wordCount: entries.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: entries)
}

private func state(_ entry: WordEntry, ease: Double) -> ReviewState {
    ReviewState(wordID: entry.id, easeFactor: ease)
}

@Test("FR-18 a lower ease factor ranks higher")
func lowerEaseRanksHigher() {
    let easy = word("chat", rank: 1)
    let hard = word("chien", rank: 2)
    let deck = pack([easy, hard])

    let ranked = StatsService().hardestWords(
        in: deck, states: [state(easy, ease: 2.3), state(hard, ease: 1.8)], limit: 5)

    #expect(ranked.map(\.lemma) == ["chien", "chat"])
}

@Test("FR-18 a word never failed is not surfaced as hard")
func neverFailedWordIsNotSurfaced() {
    let untouched = word("chat", rank: 1)
    let passing = word("chien", rank: 2)
    let deck = pack([untouched, passing])

    let ranked = StatsService().hardestWords(
        in: deck,
        states: [
            state(untouched, ease: ReviewState.startingEase),
            // Two passes above the start: +0.05 each.
            state(passing, ease: ReviewState.startingEase + 0.10),
        ],
        limit: 5)

    #expect(ranked.isEmpty)
}

@Test("FR-18 a word recovered through real Scheduler passes drops off the list")
func recoveredWordDropsOffTheList() {
    let recovered = word("chat", rank: 1)
    let deck = pack([recovered])
    let scheduler = Scheduler()
    // Graded through `Scheduler` rather than written as an ease literal: the
    // arithmetic *is* what is under test. One lapse (−0.20) plus four passes
    // (+0.05) is the exact case the doc comment on `hardestWords` promises
    // drops off, and the only case where binary rounding can break that promise.
    var state = ReviewState(wordID: recovered.id)
    state = scheduler.schedule(state, grade: .forgot, today: day(0))
    for offset in 1...4 {
        state = scheduler.schedule(state, grade: .recalled, today: day(offset))
    }

    #expect(StatsService().hardestWords(in: deck, states: [state], limit: 5).isEmpty)
}

@Test("FR-18 equal ease factors order by rank, deterministically")
func equalEaseOrdersByRank() {
    let later = word("chien", rank: 9)
    let earlier = word("chat", rank: 2)
    let deck = pack([later, earlier])

    let ranked = StatsService().hardestWords(
        in: deck, states: [state(later, ease: 2.0), state(earlier, ease: 2.0)], limit: 5)

    #expect(ranked.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-18 a state whose word is no longer in the pack is skipped")
func stateWithoutAPackWordIsSkipped() {
    let present = word("chat", rank: 1)
    let removed = word("disparu", rank: 2)
    let deck = pack([present])

    let ranked = StatsService().hardestWords(
        in: deck, states: [state(removed, ease: 1.4), state(present, ease: 2.1)], limit: 5)

    #expect(ranked.map(\.lemma) == ["chat"])
}

@Test("FR-18 the limit is honoured")
func hardestWordsHonoursTheLimit() {
    let entries = (1...10).map { word("mot\($0)", rank: $0) }
    let deck = pack(entries)
    let states = entries.enumerated().map { index, entry in
        state(entry, ease: 1.4 + Double(index) * 0.05)
    }

    #expect(StatsService().hardestWords(in: deck, states: states, limit: 5).count == 5)
}

@Test("FR-10 the learned count counts milestones, not words merely started")
func learnedCountCountsMilestones() {
    let states = [
        ReviewState(
            wordID: word("chat", rank: 1).id, firstReviewedDate: day(0), learnedDate: day(4)),
        ReviewState(wordID: word("chien", rank: 2).id, firstReviewedDate: day(1), learnedDate: nil),
        ReviewState(wordID: word("cheval", rank: 3).id),
    ]

    #expect(states.learnedCount == 1)
}

@Test("FR-17 cumulative counts at a past date match the milestones")
func trendCountsMatchMilestones() {
    let first = word("chat", rank: 1)
    let second = word("chien", rank: 2)
    let states = [
        ReviewState(wordID: first.id, firstReviewedDate: day(0), learnedDate: day(2)),
        ReviewState(wordID: second.id, firstReviewedDate: day(1), learnedDate: nil),
    ]

    let series = StatsService().trend(states: states, today: day(3))

    #expect(series.count == 4)
    #expect(series.map(\.started) == [1, 2, 2, 2])
    #expect(series.map(\.learned) == [0, 0, 1, 1])
}

@Test("FR-17 words learned in the last 7 days equals the milestones within 7 days")
func learnedInLastSevenDays() {
    let old = word("chat", rank: 1)
    let recent = word("chien", rank: 2)
    let edge = word("cheval", rank: 3)
    let states = [
        ReviewState(wordID: old.id, firstReviewedDate: day(0), learnedDate: day(1)),
        ReviewState(wordID: recent.id, firstReviewedDate: day(0), learnedDate: day(28)),
        // Exactly on the boundary: today − 7 counts as within the last 7 days.
        ReviewState(wordID: edge.id, firstReviewedDate: day(0), learnedDate: day(23)),
    ]

    let series = StatsService().trend(states: states, today: day(30))

    #expect(series.learnedInLast(7) == 2)
    #expect(series.learnedInLast(30) == 3)
}

@Test("FR-17 learned never exceeds started at any point in a series")
func learnedNeverExceedsStarted() {
    let entries = (1...20).map { word("mot\($0)", rank: $0) }
    let states = entries.enumerated().map { index, entry in
        ReviewState(
            wordID: entry.id,
            firstReviewedDate: day(index),
            learnedDate: index.isMultiple(of: 3) ? day(index + 5) : nil)
    }

    let series = StatsService().trend(states: states, today: day(40))

    #expect(series.allSatisfy { $0.learned <= $0.started })
}

@Test("FR-17 no milestones yields an empty series")
func noMilestonesYieldsEmptySeries() {
    let untouched = word("chat", rank: 1)

    let series = StatsService().trend(
        states: [ReviewState(wordID: untouched.id)], today: day(10))

    #expect(series.isEmpty)
}

@Test("FR-17 the series is a pure function of its states and today")
func trendIsPure() {
    let entry = word("chat", rank: 1)
    let states = [
        ReviewState(wordID: entry.id, firstReviewedDate: day(0), learnedDate: day(4))
    ]
    let service = StatsService()

    #expect(
        service.trend(states: states, today: day(9))
            == service.trend(states: states, today: day(9)))
}
