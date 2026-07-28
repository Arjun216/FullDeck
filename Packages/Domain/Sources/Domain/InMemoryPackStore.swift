import Foundation

/// In-memory `PackStore` double for Presentation-layer tests (Phase 8) — no file
/// I/O, no framework dependency beyond Foundation. Seed it via the initializer.
public actor InMemoryPackStore: PackStore {
    private let descriptors: [PackDescriptor]
    private let packsByCode: [LanguageCode: LanguagePack]
    private let errorOverride: PackLoadError?

    public init(
        descriptors: [PackDescriptor] = [], packs: [LanguageCode: LanguagePack] = [:],
        errorOverride: PackLoadError? = nil
    ) {
        self.descriptors = descriptors
        self.packsByCode = packs
        self.errorOverride = errorOverride
    }

    public func availablePacks() async throws -> [PackDescriptor] {
        if let errorOverride { throw errorOverride }
        return descriptors
    }

    public func loadPack(_ languageCode: LanguageCode) async throws -> LanguagePack {
        if let errorOverride { throw errorOverride }
        guard let pack = packsByCode[languageCode] else {
            throw PackLoadError.fileNotFound(languageCode: languageCode)
        }
        return pack
    }
}
