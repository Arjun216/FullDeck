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
