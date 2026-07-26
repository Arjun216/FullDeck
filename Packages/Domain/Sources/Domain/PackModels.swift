import Foundation

/// Universal Dependencies POS tags valid as pack entries (schema §3).
public enum PartOfSpeech: String, Equatable, Sendable, CaseIterable {
    case noun = "NOUN"
    case verb = "VERB"
    case adj = "ADJ"
    case adv = "ADV"
    case num = "NUM"
    case intj = "INTJ"
    case det = "DET"
    case adp = "ADP"
    case pron = "PRON"
    case aux = "AUX"
    case cconj = "CCONJ"
    case sconj = "SCONJ"
    case part = "PART"

    /// §3 CLOSED_CLASS — the function-word set. Drives VR-7 and the §6 exemption.
    public static let closedClass: Set<PartOfSpeech> = [
        .det, .adp, .pron, .aux, .cconj, .sconj, .part,
    ]

    public var isFunctionWord: Bool { Self.closedClass.contains(self) }
}

public enum Register: String, Equatable, Sendable {
    case casual, neutral, formal
}

public struct PackSource: Equatable, Sendable {
    public let name: String
    public let license: String
    public let attribution: String

    public init(name: String, license: String, attribution: String) {
        self.name = name
        self.license = license
        self.attribution = attribution
    }
}

public struct WordEntry: Equatable, Sendable {
    public let id: WordID
    public let lemma: String
    public let display: String
    public let pos: PartOfSpeech
    public let rank: Int
    public let register: Register
    public let isFunctionWord: Bool
    public let gloss: String?
    public let example: String
    public let aliases: [String]

    public init(
        id: WordID, lemma: String, display: String, pos: PartOfSpeech, rank: Int,
        register: Register, isFunctionWord: Bool, gloss: String?, example: String,
        aliases: [String]
    ) {
        self.id = id
        self.lemma = lemma
        self.display = display
        self.pos = pos
        self.rank = rank
        self.register = register
        self.isFunctionWord = isFunctionWord
        self.gloss = gloss
        self.example = example
        self.aliases = aliases
    }
}

public struct LanguagePack: Equatable, Sendable {
    public let schemaVersion: Int
    public let packVersion: String
    public let languageCode: LanguageCode
    public let languageName: String
    public let baseLanguage: String?
    public let wordCount: Int
    public let source: PackSource
    public let words: [WordEntry]

    public init(
        schemaVersion: Int, packVersion: String, languageCode: LanguageCode,
        languageName: String, baseLanguage: String?, wordCount: Int, source: PackSource,
        words: [WordEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.packVersion = packVersion
        self.languageCode = languageCode
        self.languageName = languageName
        self.baseLanguage = baseLanguage
        self.wordCount = wordCount
        self.source = source
        self.words = words
    }
}

public struct PackDescriptor: Equatable, Sendable {
    public let languageCode: LanguageCode
    public let displayName: String
    public let filename: String
    public let unlockedByDefault: Bool

    public init(
        languageCode: LanguageCode, displayName: String, filename: String,
        unlockedByDefault: Bool
    ) {
        self.languageCode = languageCode
        self.displayName = displayName
        self.filename = filename
        self.unlockedByDefault = unlockedByDefault
    }
}
