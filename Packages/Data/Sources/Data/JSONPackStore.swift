import Domain
import Foundation

public struct JSONPackStore: PackStore, Sendable {
    private let packsDirectory: URL
    private let maxSupportedSchemaVersion: Int
    private let audioAssetsDirectory: URL?
    private let decoder: JSONDecoder

    public init(
        packsDirectory: URL,
        maxSupportedSchemaVersion: Int = 1,
        audioAssetsDirectory: URL? = nil
    ) {
        self.packsDirectory = packsDirectory
        self.maxSupportedSchemaVersion = maxSupportedSchemaVersion
        self.audioAssetsDirectory = audioAssetsDirectory
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    public func availablePacks() async throws -> [PackDescriptor] {
        let manifestURL = packsDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw PackLoadError.malformedJSON("manifest.json not found at \(manifestURL.path)")
        }
        let manifest: ManifestDTO
        do {
            manifest = try decoder.decode(ManifestDTO.self, from: data)
        } catch {
            throw PackLoadError.malformedJSON("manifest.json: \(error)")
        }
        return manifest.packs.map { entry in
            PackDescriptor(
                languageCode: LanguageCode(entry.languageCode),
                displayName: entry.displayName,
                filename: entry.filename,
                unlockedByDefault: entry.unlockedByDefault)
        }
    }

    public func loadPack(_ languageCode: LanguageCode) async throws -> LanguagePack {
        let descriptors = try await availablePacks()
        guard let descriptor = descriptors.first(where: { $0.languageCode == languageCode })
        else {
            throw PackLoadError.fileNotFound(languageCode: languageCode)
        }

        let packURL = packsDirectory.appendingPathComponent(descriptor.filename)
        guard let data = try? Data(contentsOf: packURL) else {
            throw PackLoadError.fileNotFound(languageCode: languageCode)
        }

        let dto: PackDTO
        do {
            dto = try decoder.decode(PackDTO.self, from: data)
        } catch {
            throw PackLoadError.malformedJSON("\(descriptor.filename): \(error)")
        }

        // §9 fail-closed: checked before any other validation, alone, like the
        // Python validator's own VR-15 handling.
        if dto.schemaVersion > maxSupportedSchemaVersion {
            throw PackLoadError.unsupportedSchemaVersion(
                found: dto.schemaVersion, maxSupported: maxSupportedSchemaVersion)
        }

        if let violation = PackValidator.validate(
            dto, expectedLanguageCode: languageCode, audioAssetsDirectory: audioAssetsDirectory
        ) {
            throw violation
        }

        // Safe to force-unwrap: PackValidator already confirmed every entry's
        // `pos`/`register` raw value parses (VR-6/VR-8) before this line runs.
        return LanguagePack(
            schemaVersion: dto.schemaVersion,
            packVersion: dto.packVersion,
            languageCode: LanguageCode(dto.languageCode),
            languageName: dto.languageName,
            baseLanguage: dto.baseLanguage,
            wordCount: dto.wordCount,
            source: PackSource(
                name: dto.source.name, license: dto.source.license,
                attribution: dto.source.attribution),
            words: dto.words.map { entry in
                WordEntry(
                    id: WordID(entry.id),
                    lemma: entry.lemma,
                    display: entry.display,
                    pos: PartOfSpeech(rawValue: entry.pos)!,
                    rank: entry.rank,
                    register: Register(rawValue: entry.register)!,
                    isFunctionWord: entry.isFunctionWord,
                    gloss: entry.gloss,
                    example: entry.example,
                    aliases: entry.aliases ?? [])
            })
    }
}
