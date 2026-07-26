import Domain
import Foundation

/// Structural-profile validator (`docs/language-pack-schema.md` §7): VR-2
/// through VR-9 and VR-11 through VR-16. VR-10 (the example-sentence
/// frequency constraint) needs tokenization/lemmatization/POS-tagging
/// equivalent to the pipeline's spaCy analyzer and is deliberately out of
/// scope here — see the Phase 7 design doc's amendment. The pipeline already
/// enforces VR-10 before a pack ships.
enum PackValidator {
    static func validate(
        _ pack: PackDTO,
        expectedLanguageCode: LanguageCode,
        audioAssetsDirectory: URL?
    ) -> PackLoadError? {
        if let violation = checkPackLevel(pack, expectedLanguageCode: expectedLanguageCode) {
            return violation
        }
        for entry in pack.words {
            if let violation = checkEntry(entry, audioAssetsDirectory: audioAssetsDirectory) {
                return violation
            }
        }
        return nil
    }

    private static func checkEntry(
        _ entry: WordEntryDTO, audioAssetsDirectory: URL?
    ) -> PackLoadError? {
        let code = languageCode(from: entry.id)
        let expectedID = "\(code):\(entry.lemma):\(entry.pos)"
        if entry.id != expectedID {
            return .validationFailed(
                rule: "VR-4", reason: "id is not its derivation \(expectedID)")
        }
        guard let pos = PartOfSpeech(rawValue: entry.pos) else {
            return .validationFailed(rule: "VR-6", reason: "unknown pos \(entry.pos)")
        }
        if entry.isFunctionWord != pos.isFunctionWord {
            return .validationFailed(
                rule: "VR-7",
                reason: "is_function_word must be \(pos.isFunctionWord) for \(entry.pos)")
        }
        guard Register(rawValue: entry.register) != nil else {
            return .validationFailed(rule: "VR-8", reason: "unknown register \(entry.register)")
        }
        for (fieldName, text) in [
            ("lemma", entry.lemma), ("display", entry.display), ("example", entry.example),
        ] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = text.precomposedStringWithCanonicalMapping
            if text != trimmed || text != normalized {
                return .validationFailed(
                    rule: "VR-9", reason: "\(fieldName) is not trimmed and NFC-normalized")
            }
        }
        if let audio = entry.audio {
            for ref in [audio.word, audio.sentence].compactMap({ $0 }) {
                let resolved = audioAssetsDirectory?.appendingPathComponent(ref)
                guard let resolved, FileManager.default.fileExists(atPath: resolved.path) else {
                    return .validationFailed(
                        rule: "VR-12", reason: "audio reference \(ref) does not resolve")
                }
            }
        }
        return nil
    }

    private static func languageCode(from id: String) -> String {
        String(id.split(separator: ":", maxSplits: 1).first ?? "")
    }

    private static func checkPackLevel(
        _ pack: PackDTO, expectedLanguageCode: LanguageCode
    ) -> PackLoadError? {
        if pack.wordCount != pack.words.count {
            return .validationFailed(
                rule: "VR-2",
                reason: "word_count \(pack.wordCount) != \(pack.words.count) entries")
        }
        if let dup = firstDuplicate(pack.words.map(\.id)) {
            return .validationFailed(rule: "VR-3", reason: "duplicate id \(dup)")
        }
        if let dup = firstDuplicate(pack.words.map(\.rank)) {
            return .validationFailed(rule: "VR-5", reason: "duplicate rank \(dup)")
        }
        let hasGloss = pack.words.contains(where: { $0.gloss != nil })
        if hasGloss && (pack.baseLanguage ?? "").isEmpty {
            return .validationFailed(
                rule: "VR-11", reason: "entries carry a gloss but base_language is unset")
        }
        if let violation = checkAttribution(pack.source) {
            return violation
        }
        if pack.languageCode != expectedLanguageCode.rawValue {
            let expected = expectedLanguageCode.rawValue
            return .validationFailed(
                rule: "VR-16",
                reason: "language_code \(pack.languageCode) != manifest \(expected)")
        }
        let prefix = "\(pack.languageCode):"
        if let mismatch = pack.words.first(where: { !$0.id.hasPrefix(prefix) }) {
            return .validationFailed(
                rule: "VR-16", reason: "id \(mismatch.id) does not start with \(prefix)")
        }
        let liveIDs = Set(pack.words.map(\.id))
        var seenAliases = Set<String>()
        for alias in pack.words.compactMap(\.aliases).flatMap({ $0 }) {
            if liveIDs.contains(alias) || !seenAliases.insert(alias).inserted {
                return .validationFailed(
                    rule: "VR-13",
                    reason: "alias \(alias) collides with a live id or another alias")
            }
        }
        return nil
    }

    private static func checkAttribution(_ source: SourceDTO) -> PackLoadError? {
        if source.license.trimmingCharacters(in: .whitespaces).isEmpty {
            return .validationFailed(rule: "VR-14", reason: "source.license is missing or empty")
        }
        if source.attribution.trimmingCharacters(in: .whitespaces).isEmpty {
            return .validationFailed(
                rule: "VR-14", reason: "source.attribution is missing or empty")
        }
        let isWordfreq = source.name.lowercased().contains("wordfreq")
        if isWordfreq && !source.attribution.contains("CC-BY-SA 4.0") {
            return .validationFailed(
                rule: "VR-14",
                reason: "wordfreq-derived pack must credit CC-BY-SA 4.0 in source.attribution")
        }
        return nil
    }

    private static func firstDuplicate<T: Hashable>(_ values: [T]) -> T? {
        var seen = Set<T>()
        for value in values where !seen.insert(value).inserted {
            return value
        }
        return nil
    }
}
