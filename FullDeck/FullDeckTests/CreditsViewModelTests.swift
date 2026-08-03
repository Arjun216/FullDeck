import Domain
import Foundation
import Testing

@testable import FullDeck

private let hindiDescriptor = PackDescriptor(
    languageCode: LanguageCode("hi"), displayName: "Hindi", filename: "hi.pack.json",
    unlockedByDefault: false)

private let wordfreq = PackSource(
    name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors")

private func creditsPack(_ code: String, name: String, source: PackSource) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode(code),
        languageName: name, baseLanguage: "en", wordCount: 1, source: source,
        words: [entry("chat", rank: 1)])
}

@Test("FR-16 credits list each bundled pack's source, licence and attribution")
@MainActor
func creditsListEachPacksAttribution() async {
    let store = InMemoryPackStore(
        descriptors: [frDescriptor()],
        packs: [LanguageCode("fr"): creditsPack("fr", name: "Français", source: wordfreq)])
    let viewModel = CreditsViewModel(packStore: store)

    await viewModel.load()

    #expect(
        viewModel.state
            == .ready([
                Credit(
                    sourceName: "wordfreq", license: "CC-BY-SA 4.0",
                    attribution: "wordfreq contributors", languages: ["Français"])
            ]))
}

@Test("FR-16 two packs from one source render one grouped credit")
@MainActor
func creditsGroupPacksSharingASource() async {
    let store = InMemoryPackStore(
        descriptors: [frDescriptor(), hindiDescriptor],
        packs: [
            LanguageCode("fr"): creditsPack("fr", name: "Français", source: wordfreq),
            LanguageCode("hi"): creditsPack("hi", name: "हिन्दी", source: wordfreq),
        ])
    let viewModel = CreditsViewModel(packStore: store)

    await viewModel.load()

    #expect(
        viewModel.state
            == .ready([
                Credit(
                    sourceName: "wordfreq", license: "CC-BY-SA 4.0",
                    attribution: "wordfreq contributors", languages: ["Français", "हिन्दी"])
            ]))
}

@Test("NFR-10 a pack that cannot load surfaces a message, not a crash")
@MainActor
func creditsReportAFailedLoad() async {
    let store = InMemoryPackStore(
        descriptors: [frDescriptor()],
        errorOverride: .fileNotFound(languageCode: LanguageCode("fr")))
    let viewModel = CreditsViewModel(packStore: store)

    await viewModel.load()

    guard case .failed(let message) = viewModel.state else {
        Issue.record("expected .failed, got \(viewModel.state)")
        return
    }
    #expect(!message.isEmpty)
}
