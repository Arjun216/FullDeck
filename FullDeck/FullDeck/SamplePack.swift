import Domain

// ponytail: an in-code pack so the app runs before Phase 9 bundles the real
// `fr.pack.json` as an app resource. Delete this file — and the in-memory stores
// in `AppDependencies` — the moment JSONPackStore is wired in Phase 9.
enum SamplePack {
    static let french = LanguagePack(
        schemaVersion: 1, packVersion: "0.0.1-sample",
        languageCode: LanguageCode("fr"), languageName: "French", baseLanguage: "en",
        wordCount: 5,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0",
            attribution: "wordfreq contributors"),
        words: [
            word("je", .pron, rank: 1, gloss: "I", example: "Je suis Paul."),
            word("de", .adp, rank: 2, gloss: "of", example: "Je suis de Paris."),
            word("pas", .adv, rank: 3, gloss: "not", example: "Je ne suis pas de Paris."),
            word("chat", .noun, rank: 4, gloss: "cat", example: "Je ne suis pas un chat."),
            word("aussi", .adv, rank: 5, gloss: "also, too", example: "Moi aussi."),
        ])

    private static func word(
        _ lemma: String, _ pos: PartOfSpeech, rank: Int, gloss: String, example: String
    ) -> WordEntry {
        WordEntry(
            id: WordID("fr:\(lemma):\(pos.rawValue)"), lemma: lemma, display: lemma,
            pos: pos, rank: rank, register: .neutral, isFunctionWord: pos.isFunctionWord,
            gloss: gloss, example: example, aliases: [])
    }

    static let descriptor = PackDescriptor(
        languageCode: LanguageCode("fr"), displayName: "French",
        filename: "fr.pack.json", unlockedByDefault: true)

    static let hindiDescriptor = PackDescriptor(
        languageCode: LanguageCode("hi"), displayName: "Hindi",
        filename: "hi.pack.json", unlockedByDefault: false)
}
