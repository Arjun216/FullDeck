import Foundation
import Testing

@testable import Domain

private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

private func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

private func entry(_ lemma: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID("fr:\(lemma):NOUN"), lemma: lemma, display: lemma, pos: .noun,
        rank: rank, register: .neutral, isFunctionWord: false, gloss: "gloss of \(lemma)",
        example: "Une phrase avec \(lemma).", aliases: [])
}

private func frPack(_ entries: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "French", baseLanguage: "en", wordCount: entries.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: entries)
}

@Test("FR-3 a fresh learner's session is new words in rank order")
func freshSessionIsNewWordsInRankOrder() {
    let pack = frPack([entry("chien", rank: 2), entry("chat", rank: 1)])

    let queue = SessionBuilder().build(pack: pack, states: [], today: day0)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-4 new words stop at the daily cap")
func newWordsStopAtTheCap() {
    let pack = frPack([
        entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3),
    ])

    let queue = SessionBuilder().build(pack: pack, states: [], today: day0, newWordCap: 2)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-3 due reviews come before new words")
func dueReviewsComeFirst() {
    let pack = frPack([
        entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3),
    ])
    let due = ReviewState(
        wordID: WordID("fr:maison:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day0, firstReviewedDate: day(-1))

    let queue = SessionBuilder().build(
        pack: pack, states: [due], today: day0, newWordCap: 1)

    #expect(queue.map(\.lemma) == ["maison", "chat"])
}

@Test("FR-4 due reviews are never capped")
func dueReviewsAreNeverCapped() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let states = [
        ReviewState(
            wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
        ReviewState(
            wordID: WordID("fr:chien:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
    ]

    let queue = SessionBuilder().build(
        pack: pack, states: states, today: day0, newWordCap: 0)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-4 words already introduced today count against the cap")
func wordsIntroducedTodayCountAgainstTheCap() {
    let pack = frPack([
        entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3),
    ])
    // Introduced earlier today and scheduled for tomorrow: not due, but it spent
    // one of today's new-word slots.
    let introducedToday = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day(1), firstReviewedDate: day0.addingTimeInterval(9 * 3600))

    let queue = SessionBuilder().build(
        pack: pack, states: [introducedToday], today: day0.addingTimeInterval(20 * 3600),
        newWordCap: 2)

    #expect(queue.map(\.lemma) == ["chien"])
}

@Test("FR-3 due reviews are ordered most-overdue first")
func dueReviewsAreOrderedMostOverdueFirst() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let states = [
        ReviewState(
            wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
        ReviewState(
            wordID: WordID("fr:chien:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day(-3), firstReviewedDate: day(-4)),
    ]

    let queue = SessionBuilder().build(
        pack: pack, states: states, today: day0, newWordCap: 0)

    #expect(queue.map(\.lemma) == ["chien", "chat"])
}

@Test("FR-3 due reviews sharing a date fall back to rank order")
func dueReviewsTieBreakOnRank() {
    let pack = frPack([entry("chien", rank: 2), entry("chat", rank: 1)])
    let states = [
        ReviewState(
            wordID: WordID("fr:chien:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
        ReviewState(
            wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
    ]

    let queue = SessionBuilder().build(
        pack: pack, states: states, today: day0, newWordCap: 0)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-3 a word scheduled for tomorrow is not in today's session")
func wordDueTomorrowIsNotInTodaysSession() {
    let pack = frPack([entry("chat", rank: 1)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(1), firstReviewedDate: day(-6))

    let queue = SessionBuilder().build(
        pack: pack, states: [notYetDue], today: day0, newWordCap: 10)

    #expect(queue.isEmpty)
}

@Test("FR-12 nothing due and no new words left yields an empty queue")
func nothingDueAndNoNewWordsYieldsEmptyQueue() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(3), firstReviewedDate: day(-6))

    let queue = SessionBuilder().build(
        pack: pack, states: [notYetDue], today: day0, newWordCap: 0)

    #expect(queue.isEmpty)
}

@Test("FR-3 the session ignores review state belonging to another language")
func otherLanguageStateIsIgnored() {
    let pack = frPack([entry("chat", rank: 1)])
    let hindiState = ReviewState(
        wordID: WordID("hi:बिल्ली:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day(-1), firstReviewedDate: day(-2))

    let queue = SessionBuilder().build(
        pack: pack, states: [hindiState], today: day0, newWordCap: 10)

    #expect(queue.map(\.lemma) == ["chat"])
}
