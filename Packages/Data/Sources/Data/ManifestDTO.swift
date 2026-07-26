import Foundation

struct ManifestDTO: Decodable {
    let packs: [ManifestEntryDTO]
}

struct ManifestEntryDTO: Decodable {
    let languageCode: String
    let displayName: String
    let filename: String
    let unlockedByDefault: Bool
}
