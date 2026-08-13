import Foundation
import Testing

@testable import Domain

/// Phase 13's edge-case matrix, row "device date changed".
///
/// Spaced repetition is a function of dates, so the clock is an input the user
/// controls — by travelling, by a DST shift, or by setting the date by hand to
/// see what happens. None of these may corrupt state or crash. The behaviour we
/// commit to is deliberately modest and stated here rather than left implied:
///
/// - Moving the clock **forward** makes work due early. That is indistinguishable
///   from time passing, and nothing should try to detect it.
/// - Moving the clock **back** hides work until the date catches up. Also correct:
///   the alternative is showing a review the learner already did.
/// - Grading under *any* clock leaves a state the next session can read, with
///   `nextReviewDate` no earlier than the day it was graded on.
///
/// What is explicitly *not* promised: no anti-cheat. §4 rules out treating the
/// learner as an adversary, and a local-only app with no server has no way to
/// know the real date anyway.
private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

private func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

private let chat = WordID("fr:chat:NOUN")

private func pack(_ words: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "Français", baseLanguage: "en", wordCount: words.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: words)
}

private func word(_ id: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID(id), lemma: id, display: id, pos: .noun, rank: rank, register: .neutral,
        isFunctionWord: false, gloss: nil, example: "Example.", aliases: [])
}

@Test("FR-8 a clock jumped backwards never yields a review date before that day")
func backwardsClockStillSchedulesForward() {
    // Reviewed on day 100, so the state points at day 106. The learner then sets
    // the device back to day 0 and grades it again.
    let state = ReviewState(
        wordID: chat, intervalDays: 6, repetitions: 2, nextReviewDate: day(106),
        firstReviewedDate: day(94))

    let next = Scheduler().schedule(state, grade: .recalled, today: day0)

    // The invariant that matters: the scheduler answers relative to the day it
    // was handed, so the state stays usable rather than pointing into a past it
    // can never leave.
    #expect(next.nextReviewDate >= day0)
}

@Test("FR-8 a failing grade under a rewound clock still shortens the interval")
func backwardsClockDoesNotLetAFailureLengthenAnInterval() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.6, intervalDays: 21, repetitions: 5,
        nextReviewDate: day(121), firstReviewedDate: day(100))

    let next = Scheduler().schedule(state, grade: .forgot, today: day0)

    #expect(next.intervalDays < state.intervalDays)
    #expect(next.repetitions == 0)
    #expect(next.nextReviewDate >= day0)
}

@Test("FR-3 a clock moved back hides reviews scheduled under the later date")
func backwardsClockHidesFutureReviews() {
    let entry = word("fr:chat:NOUN", rank: 1)
    let state = ReviewState(
        wordID: entry.id, intervalDays: 6, repetitions: 2, nextReviewDate: day(106),
        firstReviewedDate: day(100))

    let queue = SessionBuilder().build(
        pack: pack([entry]), states: [state], today: day0, newWordCap: 0)

    // Not an error state and not a crash: simply nothing due, which is what the
    // "caught up" screen exists to say.
    #expect(queue.isEmpty)
}

@Test("FR-3 a clock moved far forward makes every outstanding review due at once")
func forwardClockMakesEverythingDue() {
    let entries = (1...3).map { word("fr:w\($0):NOUN", rank: $0) }
    let states = entries.map {
        ReviewState(
            wordID: $0.id, intervalDays: 6, repetitions: 2, nextReviewDate: day(10),
            firstReviewedDate: day(4))
    }

    let queue = SessionBuilder().build(
        pack: pack(entries), states: states, today: day(3650), newWordCap: 0)

    // Reviews are never capped (FR-3) — the cap is for new words only — so a
    // decade away returns all three rather than a slice.
    #expect(queue.count == 3)
}

@Test("FR-4 the new-word cap survives a clock moved back onto an earlier day")
func backwardsClockDoesNotDoubleSpendTheDailyCap() {
    let entries = (1...5).map { word("fr:w\($0):NOUN", rank: $0) }
    // Two words were introduced on day 100. The device is then set back to day 0,
    // so `isSameDay` no longer matches and the cap looks untouched.
    let introduced = entries.prefix(2).map {
        ReviewState(
            wordID: $0.id, intervalDays: 1, repetitions: 1, nextReviewDate: day(101),
            firstReviewedDate: day(100))
    }

    let queue = SessionBuilder().build(
        pack: pack(entries), states: Array(introduced), today: day0, newWordCap: 3)

    // The honest answer is that the cap is per *calendar day*, so a different day
    // gets its own allowance. Asserted rather than lamented: this is the
    // behaviour, and a learner who moves their clock to study more is not a
    // threat model (§4).
    #expect(queue.count == 3)
    #expect(queue.allSatisfy { entry in !introduced.contains { $0.wordID == entry.id } })
}

@Test("FR-8 a day-long clock drift within the same day does not change what is due")
func subDayDriftDoesNotChangeTheQueue() {
    let entry = word("fr:chat:NOUN", rank: 1)
    let state = ReviewState(
        wordID: entry.id, intervalDays: 1, repetitions: 1, nextReviewDate: day(1),
        firstReviewedDate: day0)

    // 23:59 and 00:01 of the same UTC day: scheduling is day-granular (L-1), so
    // both must answer identically. This is the DST/timezone case in miniature.
    let earlyQueue = SessionBuilder().build(
        pack: pack([entry]), states: [state], today: day(1).addingTimeInterval(60),
        newWordCap: 0)
    let lateQueue = SessionBuilder().build(
        pack: pack([entry]), states: [state], today: day(1).addingTimeInterval(86_340),
        newWordCap: 0)

    #expect(earlyQueue.map(\.id) == lateQueue.map(\.id))
    #expect(earlyQueue.count == 1)
}
