import Foundation

/// In-memory `PackStore` double for Presentation-layer tests (Phase 8) — no file
/// I/O, no framework dependency beyond Foundation. Seed it via the initializer.
public actor InMemoryPackStore: PackStore {
    private let descriptors: [PackDescriptor]
    private let packsByCode: [LanguageCode: LanguagePack]

    public init(
        descriptors: [PackDescriptor] = [], packs: [LanguageCode: LanguagePack] = [:]
    ) {
        self.descriptors = descriptors
        self.packsByCode = packs
    }

    public func availablePacks() async throws -> [PackDescriptor] {
        descriptors
    }

    public func loadPack(_ languageCode: LanguageCode) async throws -> LanguagePack {
        guard let pack = packsByCode[languageCode] else {
            throw PackLoadError.fileNotFound(languageCode: languageCode)
        }
        return pack
    }
}
