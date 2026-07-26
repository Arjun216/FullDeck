import Foundation

struct PackDTO: Decodable {
    let schemaVersion: Int
    let packVersion: String
    let languageCode: String
    let languageName: String
    let baseLanguage: String?
    let wordCount: Int
    let source: SourceDTO
    let words: [WordEntryDTO]
}

struct SourceDTO: Decodable {
    let name: String
    let license: String
    let attribution: String
}

struct WordEntryDTO: Decodable {
    let id: String
    let lemma: String
    let display: String
    let pos: String
    let rank: Int
    let register: String
    let isFunctionWord: Bool
    let gloss: String?
    let example: String
    let audio: AudioDTO?
    let aliases: [String]?
}

struct AudioDTO: Decodable {
    let word: String?
    let sentence: String?
}
