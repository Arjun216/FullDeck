import Foundation
import Testing

@testable import Domain

@Test("FR-17 a fresh ReviewState has no milestone dates")
func freshReviewStateHasNoMilestones() {
    let state = ReviewState(wordID: WordID("fr:chat:NOUN"))

    #expect(state.firstReviewedDate == nil)
    #expect(state.learnedDate == nil)
}

@Test("FR-17 milestone dates round-trip through ReviewState's initializer")
func milestoneDatesRoundTrip() {
    let reviewed = Date(timeIntervalSince1970: 1_000)
    let learned = Date(timeIntervalSince1970: 2_000)
    let state = ReviewState(
        wordID: WordID("fr:chat:NOUN"), firstReviewedDate: reviewed, learnedDate: learned)

    #expect(state.firstReviewedDate == reviewed)
    #expect(state.learnedDate == learned)
}

@Test("PartOfSpeech.isFunctionWord matches the CLOSED_CLASS set from the schema")
func partOfSpeechFunctionWordClassification() {
    #expect(PartOfSpeech.pron.isFunctionWord)
    #expect(PartOfSpeech.aux.isFunctionWord)
    #expect(PartOfSpeech.det.isFunctionWord)
    #expect(!PartOfSpeech.noun.isFunctionWord)
    #expect(!PartOfSpeech.verb.isFunctionWord)
}

@Test("two WordEntry values with identical fields are equal")
func wordEntryEquatable() {
    let a = WordEntry(
        id: WordID("fr:chat:NOUN"), lemma: "chat", display: "le chat", pos: .noun, rank: 4,
        register: .neutral, isFunctionWord: false, gloss: "cat", example: "J'ai un chat.",
        aliases: [])
    let b = a

    #expect(a == b)
}

@Test("LanguageCode wraps a raw string and compares by value")
func languageCodeEquatable() {
    #expect(LanguageCode("fr") == LanguageCode("fr"))
    #expect(LanguageCode("fr") != LanguageCode("hi"))
}
