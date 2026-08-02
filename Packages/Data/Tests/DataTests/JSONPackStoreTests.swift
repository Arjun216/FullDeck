import Domain
import Foundation
import Testing

@testable import Data

/// Builds a throwaway packs directory containing exactly one pack file (copied
/// from `sourceFixture`) plus a manifest.json mapping `languageCode` to it —
/// what JSONPackStore needs to load a single fixture in isolation.
private func makePacksDirectory(
    languageCode: String, filename: String, sourceFixture: URL
) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
        at: sourceFixture, to: directory.appendingPathComponent(filename))
    let manifest = """
        {"packs": [{"language_code": "\(languageCode)", "display_name": "Test", \
        "filename": "\(filename)", "unlocked_by_default": true}]}
        """
    try manifest.write(
        to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    return directory
}

// --- positive control -------------------------------------------------------

@Test("FR-6 the fr-mini fixture loads as a valid Structural pack")
func validFixtureLoadsSuccessfully() async throws {
    let store = JSONPackStore(packsDirectory: Fixtures.root)

    let pack = try await store.loadPack(LanguageCode("fr"))

    #expect(pack.wordCount == 5)
    #expect(pack.words.count == 5)
    #expect(pack.words.map(\.lemma) == ["je", "être", "avoir", "chat", "noir"])
}

@Test("FR-1 availablePacks reads the manifest and returns its descriptors")
func availablePacksReadsManifest() async throws {
    let store = JSONPackStore(packsDirectory: Fixtures.root)

    let packs = try await store.availablePacks()

    #expect(
        packs == [
            PackDescriptor(
                languageCode: LanguageCode("fr"), displayName: "Français",
                filename: "fr-mini.pack.json", unlockedByDefault: true)
        ])
}

// --- rejection: one case per rule -------------------------------------------

@Test(
    "NFR-10 each fixtures/invalid entry fails for the exact rule it breaks",
    arguments: [
        ("dup-id.pack.json", "VR-3"),
        ("id-mismatch.pack.json", "VR-4"),
        ("dup-rank.pack.json", "VR-5"),
        ("function-word-flag.pack.json", "VR-7"),
        ("word-count-mismatch.pack.json", "VR-2"),
        ("wordfreq-attribution.pack.json", "VR-14"),
        ("unresolvable-audio.pack.json", "VR-12"),
    ])
func invalidFixtureReportsItsOwnRule(filename: String, expectedRule: String) async throws {
    let directory = try makePacksDirectory(
        languageCode: "fr", filename: filename,
        sourceFixture: Fixtures.url("invalid/\(filename)"))
    let store = JSONPackStore(packsDirectory: directory)

    do {
        _ = try await store.loadPack(LanguageCode("fr"))
        Issue.record("\(filename) should have been rejected")
    } catch PackLoadError.validationFailed(let rule, _) {
        #expect(rule == expectedRule, "\(filename): expected \(expectedRule), got \(rule)")
    }
}

@Test("NFR-10 a pack newer than the max supported schema version fails closed")
func futureSchemaVersionFailsClosed() async throws {
    let directory = try makePacksDirectory(
        languageCode: "fr", filename: "future-schema-version.pack.json",
        sourceFixture: Fixtures.url("invalid/future-schema-version.pack.json"))
    let store = JSONPackStore(packsDirectory: directory)

    do {
        _ = try await store.loadPack(LanguageCode("fr"))
        Issue.record("expected unsupportedSchemaVersion")
    } catch PackLoadError.unsupportedSchemaVersion(let found, let maxSupported) {
        #expect(found == 2)
        #expect(maxSupported == 1)
    }
}

@Test("VR-16 a pack whose language_code disagrees with the manifest entry is rejected")
func languageCodeMismatchWithManifestIsRejected() async throws {
    // The manifest claims "es" for a pack file whose own language_code is "fr".
    // The manifest half of VR-16 has no shared fixture (Python's validator has
    // no manifest concept), so this case is constructed directly.
    let directory = try makePacksDirectory(
        languageCode: "es", filename: "fr-mini.pack.json",
        sourceFixture: Fixtures.url("fr-mini.pack.json"))
    let store = JSONPackStore(packsDirectory: directory)

    do {
        _ = try await store.loadPack(LanguageCode("es"))
        Issue.record("expected VR-16 rejection")
    } catch PackLoadError.validationFailed(let rule, _) {
        #expect(rule == "VR-16")
    }
}

@Test("VR-5 a pack containing a rank below 1 is rejected")
func rankBelowOneIsRejected() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var json = try String(contentsOf: Fixtures.url("fr-mini.pack.json"), encoding: .utf8)
    json = json.replacingOccurrences(of: "\"rank\": 1,", with: "\"rank\": 0,")
    try json.write(
        to: directory.appendingPathComponent("zero-rank.pack.json"), atomically: true,
        encoding: .utf8)
    try """
    {"packs": [{"language_code": "fr", "display_name": "Test", \
    "filename": "zero-rank.pack.json", "unlocked_by_default": true}]}
    """.write(
        to: directory.appendingPathComponent("manifest.json"), atomically: true,
        encoding: .utf8)
    let store = JSONPackStore(packsDirectory: directory)

    do {
        _ = try await store.loadPack(LanguageCode("fr"))
        Issue.record("expected VR-5 rejection")
    } catch PackLoadError.validationFailed(let rule, _) {
        #expect(rule == "VR-5")
    }
}

@Test("VR-9 a pack containing an empty example sentence is rejected")
func emptyExampleIsRejected() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var json = try String(contentsOf: Fixtures.url("fr-mini.pack.json"), encoding: .utf8)
    json = json.replacingOccurrences(
        of: "\"example\": \"Je suis Paul.\"", with: "\"example\": \"\"")
    try json.write(
        to: directory.appendingPathComponent("empty-example.pack.json"), atomically: true,
        encoding: .utf8)
    try """
    {"packs": [{"language_code": "fr", "display_name": "Test", \
    "filename": "empty-example.pack.json", "unlocked_by_default": true}]}
    """.write(
        to: directory.appendingPathComponent("manifest.json"), atomically: true,
        encoding: .utf8)
    let store = JSONPackStore(packsDirectory: directory)

    do {
        _ = try await store.loadPack(LanguageCode("fr"))
        Issue.record("expected VR-9 rejection")
    } catch PackLoadError.validationFailed(let rule, _) {
        #expect(rule == "VR-9")
    }
}

// --- robustness on bad/missing data (NFR-10) --------------------------------

@Test("NFR-10 loading an unknown language surfaces fileNotFound, not a crash")
func loadPackThrowsFileNotFoundForUnknownLanguage() async throws {
    let store = JSONPackStore(packsDirectory: Fixtures.root)

    do {
        _ = try await store.loadPack(LanguageCode("xx"))
        Issue.record("expected fileNotFound")
    } catch PackLoadError.fileNotFound(let languageCode) {
        #expect(languageCode == LanguageCode("xx"))
    }
}

@Test("NFR-10 malformed JSON surfaces a typed error, not a crash")
func loadPackThrowsMalformedJSONForCorruptFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "{ not valid json".write(
        to: directory.appendingPathComponent("broken.pack.json"), atomically: true,
        encoding: .utf8)
    try """
    {"packs": [{"language_code": "fr", "display_name": "Test", \
    "filename": "broken.pack.json", "unlocked_by_default": true}]}
    """.write(
        to: directory.appendingPathComponent("manifest.json"), atomically: true,
        encoding: .utf8)
    let store = JSONPackStore(packsDirectory: directory)

    do {
        _ = try await store.loadPack(LanguageCode("fr"))
        Issue.record("expected malformedJSON")
    } catch PackLoadError.malformedJSON {
        // expected
    }
}
