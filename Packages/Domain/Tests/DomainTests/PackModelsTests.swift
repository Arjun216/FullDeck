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

@Test("PackSource round-trips through its initializer")
func packSourceRoundTrip() {
    let source = PackSource(
        name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq by Rory Beard"
    )

    #expect(source.name == "wordfreq")
    #expect(source.license == "CC-BY-SA 4.0")
    #expect(source.attribution == "wordfreq by Rory Beard")
}

@Test("LanguagePack round-trips through its initializer")
func languagePackRoundTrip() {
    let source = PackSource(
        name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq by Rory Beard"
    )
    let words = [
        WordEntry(
            id: WordID("fr:le:DET"), lemma: "le", display: "le", pos: .det, rank: 1,
            register: .neutral, isFunctionWord: true, gloss: nil, example: "Le chat.", aliases: []),
    ]
    let pack = LanguagePack(
        schemaVersion: 1, packVersion: "0.1.0", languageCode: LanguageCode("fr"),
        languageName: "French", baseLanguage: nil, wordCount: 1, source: source, words: words
    )

    #expect(pack.schemaVersion == 1)
    #expect(pack.packVersion == "0.1.0")
    #expect(pack.languageCode == LanguageCode("fr"))
    #expect(pack.languageName == "French")
    #expect(pack.baseLanguage == nil)
    #expect(pack.wordCount == 1)
    #expect(pack.words.count == 1)
}

@Test("PackDescriptor round-trips through its initializer")
func packDescriptorRoundTrip() {
    let descriptor = PackDescriptor(
        languageCode: LanguageCode("fr"), displayName: "French",
        filename: "fr.pack.json", unlockedByDefault: true
    )

    #expect(descriptor.languageCode == LanguageCode("fr"))
    #expect(descriptor.displayName == "French")
    #expect(descriptor.filename == "fr.pack.json")
    #expect(descriptor.unlockedByDefault)
}

@Test("ProgressSummary round-trips through its initializer")
func progressSummaryRoundTrip() {
    let summary = ProgressSummary(wordsLearned: 100, wordsInProgress: 50, totalReviewed: 150)

    #expect(summary.wordsLearned == 100)
    #expect(summary.wordsInProgress == 50)
    #expect(summary.totalReviewed == 150)
}
