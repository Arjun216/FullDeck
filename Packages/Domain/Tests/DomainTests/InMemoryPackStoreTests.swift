import Foundation
import Testing

@testable import Domain

private let fr = LanguageCode("fr")

private func makePack() -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "0.1.0", languageCode: fr, languageName: "Français",
        baseLanguage: "en", wordCount: 0,
        source: PackSource(name: "test", license: "CC0-1.0", attribution: "test"), words: [])
}

@Test("FR-1 InMemoryPackStore returns the descriptors it was seeded with")
func availablePacksReturnsSeededDescriptors() async throws {
    let descriptor = PackDescriptor(
        languageCode: fr, displayName: "Français", filename: "fr.pack.json",
        unlockedByDefault: true)
    let store = InMemoryPackStore(descriptors: [descriptor])

    let packs = try await store.availablePacks()

    #expect(packs == [descriptor])
}

@Test("FR-1 InMemoryPackStore loads a seeded pack by language code")
func loadPackReturnsSeededPack() async throws {
    let pack = makePack()
    let store = InMemoryPackStore(packs: [fr: pack])

    let loaded = try await store.loadPack(fr)

    #expect(loaded == pack)
}

@Test("NFR-10 InMemoryPackStore throws fileNotFound for an unseeded language")
func loadPackThrowsForMissingLanguage() async throws {
    let store = InMemoryPackStore()

    do {
        _ = try await store.loadPack(fr)
        Issue.record("expected PackLoadError.fileNotFound")
    } catch let error as PackLoadError {
        #expect(error == .fileNotFound(languageCode: fr))
    }
}
