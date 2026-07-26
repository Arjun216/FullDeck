# Phase 7 — Persistence Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `PackStore` and `ReviewStore` behind the ports architecture.md sketched, with a JSON+`Codable` adapter for read-only language packs, a SwiftData adapter for mutable review state, and in-memory fakes for Phase 8's ViewModel tests — per [ADR-001](../../adr/ADR-001-persistence.md) and the approved [design](../specs/2026-07-26-phase-7-persistence-design.md).

**Architecture:** New Domain-owned value types and protocols (`LanguageCode`, `LanguagePack`, `WordEntry`, `PackDescriptor`, `ProgressSummary`, `PackStore`, `ReviewStore`, `PackLoadError`), plus two milestone-date fields added to the existing `ReviewState`. Two concrete Data-layer adapters (`JSONPackStore` — a `Sendable` struct; `SwiftDataReviewStore` — an actor via `@ModelActor`) implement those ports. Two in-memory fakes live in Domain, not Data, so Presentation tests never need to link SwiftData.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, SwiftData (iOS 17+/macOS 14+, no third-party dependency), Foundation `Codable`/`JSONDecoder`.

## Global Constraints

- Platform floor: iOS 17.0 / macOS 14.0 (already set in both `Package.swift` manifests — unchanged).
- Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`) — every new type must be `Sendable` or actor-isolated; no data races.
- `-warnings-as-errors` — code must compile clean, no warnings.
- Coverage floors: Domain ≥ 90%, Data ≥ 80% line coverage (`scripts/coverage-gate.sh`).
- Test determinism: no `Date()`, no sleeps, no unseeded randomness in test sources (`scripts/determinism-check.sh`) — use fixed `Date(timeIntervalSince1970:)` literals or `.distantPast`, matching `SchedulerTests.swift`'s existing convention.
- Test display names start with the requirement ID they verify (`@Test("FR-8 ...")`) wherever a genuine FR-/NFR- requirement applies to that behavior. Reserve a plain descriptive name for purely mechanical checks with no requirement behind them (`Equatable` derivation, enum-classification math, path arithmetic) — never as a blanket exemption for a whole test file.
- Conventional commits, small and focused, one per task (or per sub-cycle where a task's steps note it).

---

### Task 1: Domain — `LanguageCode`, pack value types, ports, and `ReviewState` milestone fields

**Files:**
- Modify: `Packages/Domain/Sources/Domain/Models.swift`
- Create: `Packages/Domain/Sources/Domain/PackModels.swift`
- Create: `Packages/Domain/Sources/Domain/Ports.swift`
- Test: `Packages/Domain/Tests/DomainTests/PackModelsTests.swift`

**Interfaces:**
- Produces: `LanguageCode`, `PartOfSpeech`, `Register`, `PackSource`, `WordEntry`, `LanguagePack`, `PackDescriptor`, `ProgressSummary`, `PackStore`, `ReviewStore`, `PackLoadError` — all used by every later task. `ReviewState` gains `firstReviewedDate: Date?` and `learnedDate: Date?` (both default `nil`).

- [ ] **Step 1: Write the failing tests**

Create `Packages/Domain/Tests/DomainTests/PackModelsTests.swift`:

```swift
import Foundation
import Testing

@testable import Domain

@Test("FR-17 a fresh ReviewState has no milestone dates")
func freshReviewStateHasNoMilestones() {
    let state = ReviewState(wordID: WordID("fr:chat:NOUN"))

    #expect(state.firstReviewedDate == nil)
    #expect(state.learnedDate == nil)
}

@Test("FR-17 milestone dates round-trip through ReviewState's initializer")
func milestoneDatesRoundTrip() {
    let reviewed = Date(timeIntervalSince1970: 1_000)
    let learned = Date(timeIntervalSince1970: 2_000)
    let state = ReviewState(
        wordID: WordID("fr:chat:NOUN"), firstReviewedDate: reviewed, learnedDate: learned)

    #expect(state.firstReviewedDate == reviewed)
    #expect(state.learnedDate == learned)
}

@Test("PartOfSpeech.isFunctionWord matches the CLOSED_CLASS set from the schema")
func partOfSpeechFunctionWordClassification() {
    #expect(PartOfSpeech.pron.isFunctionWord)
    #expect(PartOfSpeech.aux.isFunctionWord)
    #expect(PartOfSpeech.det.isFunctionWord)
    #expect(!PartOfSpeech.noun.isFunctionWord)
    #expect(!PartOfSpeech.verb.isFunctionWord)
}

@Test("two WordEntry values with identical fields are equal")
func wordEntryEquatable() {
    let a = WordEntry(
        id: WordID("fr:chat:NOUN"), lemma: "chat", display: "le chat", pos: .noun, rank: 4,
        register: .neutral, isFunctionWord: false, gloss: "cat", example: "J'ai un chat.",
        aliases: [])
    let b = a

    #expect(a == b)
}

@Test("LanguageCode wraps a raw string and compares by value")
func languageCodeEquatable() {
    #expect(LanguageCode("fr") == LanguageCode("fr"))
    #expect(LanguageCode("fr") != LanguageCode("hi"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/Domain --filter PackModelsTests`
Expected: FAIL to compile — `LanguageCode`, `PartOfSpeech`, `WordEntry` etc. don't exist yet, and `ReviewState`'s initializer doesn't accept `firstReviewedDate`/`learnedDate`. This is a compile-error red, which is expected here since the whole point of this task is introducing these types — proceed to Step 3.

- [ ] **Step 3: Add `LanguageCode` and the milestone fields to `Models.swift`**

In `Packages/Domain/Sources/Domain/Models.swift`, add after the `WordID` struct:

```swift
/// Opaque BCP-47 language code (`"fr"`, `"hi"`). A wrapper rather than a bare
/// `String` for the same reason as `WordID`: a language code can never be passed
/// where a word key is expected.
public struct LanguageCode: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
```

Then replace the `ReviewState` struct's stored properties and initializer with:

```swift
public struct ReviewState: Equatable, Sendable {
    public let wordID: WordID
    /// SM-2 difficulty multiplier: higher = intervals grow faster.
    public var easeFactor: Double
    public var intervalDays: Int
    /// Consecutive passing reviews; a failing grade resets it.
    public var repetitions: Int
    public var nextReviewDate: Date
    /// Set on the word's first review. `nil` for an untouched word. Storage
    /// plumbing for FR-17's outcome trend; Phase 9 decides exactly when this
    /// gets set, not this type.
    public var firstReviewedDate: Date?
    /// Set once the word meets the learned threshold `L` (Phase 9). `nil` until
    /// then, so `wordsLearned` is mechanically 0 everywhere until that phase.
    public var learnedDate: Date?

    /// A never-reviewed word: `.distantPast` means "due now" without needing an
    /// optional date and the branch that comes with it.
    public init(
        wordID: WordID,
        easeFactor: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        nextReviewDate: Date = .distantPast,
        firstReviewedDate: Date? = nil,
        learnedDate: Date? = nil
    ) {
        self.wordID = wordID
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
        self.firstReviewedDate = firstReviewedDate
        self.learnedDate = learnedDate
    }
}
```

- [ ] **Step 4: Create `PackModels.swift`**

```swift
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
```

- [ ] **Step 5: Create `Ports.swift`**

```swift
import Foundation

public struct ProgressSummary: Equatable, Sendable {
    public let wordsLearned: Int
    public let wordsInProgress: Int
    public let totalReviewed: Int

    public init(wordsLearned: Int, wordsInProgress: Int, totalReviewed: Int) {
        self.wordsLearned = wordsLearned
        self.wordsInProgress = wordsInProgress
        self.totalReviewed = totalReviewed
    }
}

/// Read-only bundled content. Adapter: `JSONPackStore` (Phase 7, JSON+Codable, ADR-004).
public protocol PackStore: Sendable {
    func availablePacks() async throws -> [PackDescriptor]
    func loadPack(_ languageCode: LanguageCode) async throws -> LanguagePack
}

/// Mutable per-user state. Adapter: `SwiftDataReviewStore` (Phase 7, ADR-001).
public protocol ReviewStore: Sendable {
    func reviewState(for word: WordID) async throws -> ReviewState?
    func save(_ state: ReviewState) async throws
    func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState]
    func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary
}

/// Typed errors `PackStore` implementations throw — never a crash on bad or
/// missing data (NFR-10).
public enum PackLoadError: Error, Equatable, Sendable {
    case fileNotFound(languageCode: LanguageCode)
    case malformedJSON(String)
    /// Fail-closed per schema §9: a pack newer than the loader supports.
    case unsupportedSchemaVersion(found: Int, maxSupported: Int)
    /// `rule` carries the VR id (`"VR-3"`), matching the convention
    /// `fixtures/invalid/expected.json` already uses.
    case validationFailed(rule: String, reason: String)
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path Packages/Domain --filter PackModelsTests`
Expected: PASS (5 tests).

- [ ] **Step 7: Run the full Domain suite to confirm nothing broke**

Run: `swift test --package-path Packages/Domain`
Expected: PASS — `SchedulerTests.swift` is unaffected since `ReviewState`'s new fields default to `nil` and existing call sites don't reference them.

- [ ] **Step 8: Commit**

```bash
git add Packages/Domain/Sources/Domain/Models.swift Packages/Domain/Sources/Domain/PackModels.swift Packages/Domain/Sources/Domain/Ports.swift Packages/Domain/Tests/DomainTests/PackModelsTests.swift
git commit -m "feat(domain): add pack value types, ports, and ReviewState milestone dates"
```

---

### Task 2: Domain — `InMemoryPackStore`

**Files:**
- Create: `Packages/Domain/Sources/Domain/InMemoryPackStore.swift`
- Test: `Packages/Domain/Tests/DomainTests/InMemoryPackStoreTests.swift`

**Interfaces:**
- Consumes: `PackStore`, `LanguageCode`, `LanguagePack`, `PackDescriptor`, `PackLoadError` (Task 1).
- Produces: `InMemoryPackStore` — a `PackStore` conformance Phase 8's `PresentationTests` construct directly with seed data.

- [ ] **Step 1: Write the failing tests**

Create `Packages/Domain/Tests/DomainTests/InMemoryPackStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/Domain --filter InMemoryPackStoreTests`
Expected: FAIL to compile — `InMemoryPackStore` doesn't exist yet.

- [ ] **Step 3: Create `InMemoryPackStore.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/Domain --filter InMemoryPackStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/Domain/Sources/Domain/InMemoryPackStore.swift Packages/Domain/Tests/DomainTests/InMemoryPackStoreTests.swift
git commit -m "feat(domain): add InMemoryPackStore test double"
```

---

### Task 3: Domain — `InMemoryReviewStore`

**Files:**
- Create: `Packages/Domain/Sources/Domain/InMemoryReviewStore.swift`
- Test: `Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift`

**Interfaces:**
- Consumes: `ReviewStore`, `ReviewState`, `WordID`, `LanguageCode`, `ProgressSummary` (Task 1).
- Produces: `InMemoryReviewStore` — a `ReviewStore` conformance Phase 8's `PresentationTests` construct directly.

- [ ] **Step 1: Write the failing tests**

Create `Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift`:

```swift
import Foundation
import Testing

@testable import Domain

private let fr = LanguageCode("fr")
private let chat = WordID("fr:chat:NOUN")
private let noir = WordID("fr:noir:ADJ")

@Test("FR-9 InMemoryReviewStore returns nil for a word with no saved state")
func reviewStateReturnsNilWhenUnsaved() async throws {
    let store = InMemoryReviewStore()

    let state = try await store.reviewState(for: chat)

    #expect(state == nil)
}

@Test("FR-9 InMemoryReviewStore round-trips a saved state")
func saveThenReviewStateRoundTrips() async throws {
    let store = InMemoryReviewStore()
    let state = ReviewState(wordID: chat, easeFactor: 2.3, intervalDays: 6)

    try await store.save(state)
    let loaded = try await store.reviewState(for: chat)

    #expect(loaded == state)
}

@Test("FR-10 InMemoryReviewStore allStates filters by language code")
func allStatesFiltersByLanguage() async throws {
    let store = InMemoryReviewStore()
    try await store.save(ReviewState(wordID: chat))
    try await store.save(ReviewState(wordID: WordID("hi:sa:VERB")))

    let states = try await store.allStates(fr)

    #expect(states.map(\.wordID) == [chat])
}

@Test("FR-10 InMemoryReviewStore progress counts learned, in-progress and total")
func progressComputesFromMilestoneDates() async throws {
    let store = InMemoryReviewStore()
    let learned = ReviewState(
        wordID: chat, firstReviewedDate: .distantPast, learnedDate: .distantPast)
    let inProgress = ReviewState(wordID: noir, firstReviewedDate: .distantPast, learnedDate: nil)
    try await store.save(learned)
    try await store.save(inProgress)

    let summary = try await store.progress(fr)

    #expect(summary == ProgressSummary(wordsLearned: 1, wordsInProgress: 1, totalReviewed: 2))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/Domain --filter InMemoryReviewStoreTests`
Expected: FAIL to compile — `InMemoryReviewStore` doesn't exist yet.

- [ ] **Step 3: Create `InMemoryReviewStore.swift`**

```swift
import Foundation

/// In-memory `ReviewStore` double for Presentation-layer tests (Phase 8).
public actor InMemoryReviewStore: ReviewStore {
    private var statesByWord: [WordID: ReviewState]

    public init(seed: [ReviewState] = []) {
        var initial: [WordID: ReviewState] = [:]
        for state in seed {
            initial[state.wordID] = state
        }
        self.statesByWord = initial
    }

    public func reviewState(for word: WordID) async throws -> ReviewState? {
        statesByWord[word]
    }

    public func save(_ state: ReviewState) async throws {
        statesByWord[state.wordID] = state
    }

    public func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState] {
        let prefix = "\(languageCode.rawValue):"
        return statesByWord.values.filter { $0.wordID.rawValue.hasPrefix(prefix) }
    }

    public func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary {
        let states = try await allStates(languageCode)
        let learned = states.filter { $0.learnedDate != nil }.count
        let inProgress = states.filter { $0.firstReviewedDate != nil && $0.learnedDate == nil }
            .count
        return ProgressSummary(
            wordsLearned: learned, wordsInProgress: inProgress,
            totalReviewed: learned + inProgress)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/Domain --filter InMemoryReviewStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full Domain suite and check coverage**

Run: `swift test --package-path Packages/Domain --enable-code-coverage && scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests`
Expected: PASS, ≥ 90% line coverage.

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain/Sources/Domain/InMemoryReviewStore.swift Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift
git commit -m "feat(domain): add InMemoryReviewStore test double"
```

---

### Task 4: Data — cleanup, fixture helper, and JSON DTOs

**Files:**
- Delete: `Packages/Data/Sources/Data/DataScaffold.swift`
- Delete: `Packages/Data/Tests/DataTests/DataScaffoldTests.swift`
- Create: `Packages/Data/Tests/DataTests/Fixtures.swift`
- Create: `fixtures/manifest.json`
- Create: `Packages/Data/Sources/Data/PackDTO.swift`
- Create: `Packages/Data/Sources/Data/ManifestDTO.swift`

**Interfaces:**
- Produces: `Fixtures.root: URL`, `Fixtures.url(_ name: String) -> URL` (test-only helper); `PackDTO`, `SourceDTO`, `WordEntryDTO`, `AudioDTO`, `ManifestDTO`, `ManifestEntryDTO` (internal Codable wire types) — consumed by Task 5.

- [ ] **Step 1: Delete the Phase-4 scaffold**

The scaffold's own comment says to delete it once the real adapters arrive (`// ponytail: Phase-4 placeholder ... Delete this file then.`) — that's now.

```bash
git rm Packages/Data/Sources/Data/DataScaffold.swift Packages/Data/Tests/DataTests/DataScaffoldTests.swift
```

- [ ] **Step 2: Write the failing test for the fixture-path helper**

Create `Packages/Data/Tests/DataTests/Fixtures.swift`:

```swift
import Foundation

/// Locates the shared `/fixtures` directory at the repo root from any test file,
/// via the compile-time source path — test-only file reads, so no SPM resource
/// bundling or symlinks are needed.
enum Fixtures {
    static let root: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Fixtures.swift -> DataTests/
            .deletingLastPathComponent()  // DataTests/ -> Tests/
            .deletingLastPathComponent()  // Tests/ -> Data/
            .deletingLastPathComponent()  // Data/ -> Packages/
            .deletingLastPathComponent()  // Packages/ -> repo root
            .appendingPathComponent("fixtures")
    }()

    static func url(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }
}
```

Create `Packages/Data/Tests/DataTests/FixturesTests.swift`:

```swift
import Foundation
import Testing

@Test("Fixtures.root resolves to the repo-root fixtures directory")
func fixturesRootResolvesCorrectly() {
    let fileManager = FileManager.default

    #expect(fileManager.fileExists(atPath: Fixtures.url("fr-mini.pack.json").path))
    var isDirectory: ObjCBool = false
    #expect(
        fileManager.fileExists(
            atPath: Fixtures.root.appendingPathComponent("invalid").path,
            isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}
```

- [ ] **Step 3: Run the test**

Run: `swift test --package-path Packages/Data --filter FixturesTests`
Expected: PASS immediately — this is pure path arithmetic against files that already exist on disk, so there's no red state to chase here; running it once confirms the 5-level climb is correct before later tasks depend on it.

- [ ] **Step 4: Create `fixtures/manifest.json`**

```json
{
  "packs": [
    {
      "language_code": "fr",
      "display_name": "Français",
      "filename": "fr-mini.pack.json",
      "unlocked_by_default": true
    }
  ]
}
```

- [ ] **Step 5: Create `PackDTO.swift`**

Wire-format types mirroring `docs/language-pack-schema.md` §2/§4 exactly, decoded with `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` (set by the caller in Task 5) so `word_count` → `wordCount` etc. need no manual `CodingKeys`.

```swift
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
```

- [ ] **Step 6: Create `ManifestDTO.swift`**

```swift
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
```

- [ ] **Step 7: Run the full Data suite**

Run: `swift test --package-path Packages/Data`
Expected: PASS — the DTOs aren't consumed by anything yet, so this just confirms the package still compiles and `FixturesTests` passes after removing the scaffold.

- [ ] **Step 8: Commit**

```bash
git add -A Packages/Data fixtures/manifest.json
git commit -m "feat(data): remove Phase-4 scaffold, add fixture helper and pack JSON DTOs"
```

---

### Task 5: Data — `PackValidator` and `JSONPackStore`

This is the core of the phase: build-plan requires the loader's error mapping to be test-first, driving `fixtures/invalid/` the same way the Phase 6 Python validator does. VR-10 (the sentence frequency constraint) is excluded — see the design doc's amendment — so the two VR-10 fixtures are not part of this task's rejection set.

**Files:**
- Create: `Packages/Data/Sources/Data/PackValidator.swift`
- Create: `Packages/Data/Sources/Data/JSONPackStore.swift`
- Test: `Packages/Data/Tests/DataTests/JSONPackStoreTests.swift`

**Interfaces:**
- Consumes: `PackDTO`, `SourceDTO`, `WordEntryDTO`, `ManifestDTO` (Task 4); `LanguageCode`, `LanguagePack`, `WordEntry`, `PackSource`, `PartOfSpeech`, `Register`, `PackDescriptor`, `PackStore`, `PackLoadError` (Task 1); `Fixtures` (Task 4).
- Produces: `JSONPackStore` — the `PackStore` conformance Phase 8's composition root constructs with the real bundled-resource directory.

- [ ] **Step 1: Create `PackValidator.swift` as a stub that always passes**

This is the TDD "make it compile, red for the right reason" step — the tests in Step 3 must fail because no error is thrown, not because the code doesn't build.

```swift
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
        nil
    }
}
```

- [ ] **Step 2: Create `JSONPackStore.swift`**

```swift
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
            dto, expectedLanguageCode: languageCode, audioAssetsDirectory: audioAssetsDirectory)
        {
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
```

- [ ] **Step 3: Write the full rejection-fixture test suite (still red for the validator rules)**

Create `Packages/Data/Tests/DataTests/JSONPackStoreTests.swift`:

```swift
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
```

- [ ] **Step 4: Run the suite to confirm it fails for the right reason**

Run: `swift test --package-path Packages/Data --filter JSONPackStoreTests`
Expected: FAIL — the positive control, `availablePacks`, `fileNotFound`, and `malformedJSON` tests already PASS (they don't depend on `PackValidator`'s rules). The 7 parameterized rejection cases, the schema-version test, and the VR-16 test all FAIL because `PackValidator.validate` currently returns `nil` unconditionally, so no error is thrown — this is red for the right reason: the validator's rule logic doesn't exist yet.

- [ ] **Step 5: Implement the pack-level validator rules (VR-2, VR-3, VR-5, VR-11, VR-14, VR-16, VR-13)**

Replace the stub body in `PackValidator.swift`:

```swift
enum PackValidator {
    static func validate(
        _ pack: PackDTO,
        expectedLanguageCode: LanguageCode,
        audioAssetsDirectory: URL?
    ) -> PackLoadError? {
        if let violation = checkPackLevel(pack, expectedLanguageCode: expectedLanguageCode) {
            return violation
        }
        return nil
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
        if pack.words.contains(where: { $0.gloss != nil })
            && (pack.baseLanguage ?? "").isEmpty
        {
            return .validationFailed(
                rule: "VR-11", reason: "entries carry a gloss but base_language is unset")
        }
        if let violation = checkAttribution(pack.source) {
            return violation
        }
        if pack.languageCode != expectedLanguageCode.rawValue {
            return .validationFailed(
                rule: "VR-16",
                reason:
                    "language_code \(pack.languageCode) != manifest \(expectedLanguageCode.rawValue)"
            )
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
        if source.name.lowercased().contains("wordfreq"),
            !source.attribution.contains("CC-BY-SA 4.0")
        {
            return .validationFailed(
                rule: "VR-14",
                reason: "wordfreq-derived pack must credit CC-BY-SA 4.0 in source.attribution")
        }
        return nil
    }

    private static func firstDuplicate<T: Hashable>(_ values: [T]) -> T? {
        var seen = Set<T>()
        for value in values {
            if !seen.insert(value).inserted {
                return value
            }
        }
        return nil
    }
}
```

- [ ] **Step 6: Run the suite again**

Run: `swift test --package-path Packages/Data --filter JSONPackStoreTests`
Expected: `dup-id` (VR-3), `dup-rank` (VR-5), `word-count-mismatch` (VR-2), `wordfreq-attribution` (VR-14), and the VR-16 mismatch test now PASS. `id-mismatch` (VR-4), `function-word-flag` (VR-7), and `unresolvable-audio` (VR-12) still FAIL — those are per-entry rules, not implemented yet. This is the expected partial-green state.

- [ ] **Step 7: Implement the per-entry validator rules (VR-4, VR-6, VR-7, VR-8, VR-9, VR-12)**

Add to `PackValidator.swift`, and call it from `validate`:

```swift
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
```

- [ ] **Step 8: Run the full suite to confirm green**

Run: `swift test --package-path Packages/Data --filter JSONPackStoreTests`
Expected: PASS — all 13 tests (2 positive-control/manifest + 7 parameterized rejection + schema-version + VR-16 + fileNotFound + malformedJSON).

- [ ] **Step 9: Run the whole Data suite and check coverage**

Run: `swift test --package-path Packages/Data --enable-code-coverage && scripts/coverage-gate.sh Packages/Data 80 DataPackageTests`
Expected: PASS, ≥ 80% line coverage.

- [ ] **Step 10: Commit**

```bash
git add Packages/Data/Sources/Data/PackValidator.swift Packages/Data/Sources/Data/JSONPackStore.swift Packages/Data/Tests/DataTests/JSONPackStoreTests.swift
git commit -m "feat(data): add JSONPackStore with Structural-profile validation"
```

---

### Task 6: Data — `PersistentReviewState` and `SwiftDataReviewStore`

**Files:**
- Create: `Packages/Data/Sources/Data/PersistentReviewState.swift`
- Create: `Packages/Data/Sources/Data/SwiftDataReviewStore.swift`
- Test: `Packages/Data/Tests/DataTests/SwiftDataReviewStoreTests.swift`

**Interfaces:**
- Consumes: `ReviewStore`, `ReviewState`, `WordID`, `LanguageCode`, `ProgressSummary` (Task 1).
- Produces: `SwiftDataReviewStore` — the `ReviewStore` conformance Phase 8's composition root constructs with the real on-disk `ModelContainer`.

- [ ] **Step 1: Write the failing tests**

Create `Packages/Data/Tests/DataTests/SwiftDataReviewStoreTests.swift`:

```swift
import Domain
import Foundation
import SwiftData
import Testing

@testable import Data

private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: PersistentReviewState.self, configurations: configuration)
}

private let chat = WordID("fr:chat:NOUN")
private let noir = WordID("fr:noir:ADJ")
private let fr = LanguageCode("fr")

@Test("FR-9 reviewState returns nil for a word that was never saved")
func reviewStateReturnsNilForUnsavedWord() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())

    let state = try await store.reviewState(for: chat)

    #expect(state == nil)
}

@Test("FR-9 a saved review state round-trips through save and reviewState")
func saveThenReviewStateRoundTrips() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    let state = ReviewState(wordID: chat, easeFactor: 2.3, intervalDays: 6, repetitions: 2)

    try await store.save(state)
    let loaded = try await store.reviewState(for: chat)

    #expect(loaded == state)
}

@Test("FR-9 saving twice for the same word updates rather than duplicates")
func saveTwiceUpdatesExistingState() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    try await store.save(ReviewState(wordID: chat, easeFactor: 2.5, intervalDays: 1))
    try await store.save(ReviewState(wordID: chat, easeFactor: 2.3, intervalDays: 6))

    let states = try await store.allStates(fr)

    #expect(states.count == 1)
    #expect(states.first?.easeFactor == 2.3)
}

@Test("FR-10 allStates only returns states for the requested language")
func allStatesFiltersByLanguage() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    try await store.save(ReviewState(wordID: chat))
    try await store.save(ReviewState(wordID: WordID("hi:sa:VERB")))

    let states = try await store.allStates(fr)

    #expect(states.map(\.wordID) == [chat])
}

@Test("FR-10 progress counts learned and in-progress words from milestone dates")
func progressComputesFromMilestoneDates() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())
    try await store.save(
        ReviewState(wordID: chat, firstReviewedDate: .distantPast, learnedDate: .distantPast))
    try await store.save(
        ReviewState(wordID: noir, firstReviewedDate: .distantPast, learnedDate: nil))

    let summary = try await store.progress(fr)

    #expect(summary == ProgressSummary(wordsLearned: 1, wordsInProgress: 1, totalReviewed: 2))
}

@Test("NFR-10 progress for a language with no saved state is all zeros")
func progressForEmptyLanguageIsZero() async throws {
    let store = SwiftDataReviewStore(modelContainer: try makeContainer())

    let summary = try await store.progress(fr)

    #expect(summary == ProgressSummary(wordsLearned: 0, wordsInProgress: 0, totalReviewed: 0))
}

@Test("migration smoke test: the model container initializes cleanly for the current schema")
func modelContainerInitializesCleanly() throws {
    _ = try makeContainer()
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/Data --filter SwiftDataReviewStoreTests`
Expected: FAIL to compile — `PersistentReviewState` and `SwiftDataReviewStore` don't exist yet.

- [ ] **Step 3: Create `PersistentReviewState.swift`**

```swift
import Foundation
import SwiftData

/// SwiftData storage for review state (ADR-001). Never crosses the `ReviewStore`
/// port — `SwiftDataReviewStore` maps to/from the pure `Domain.ReviewState`.
@Model
final class PersistentReviewState {
    @Attribute(.unique) var wordID: String
    /// Denormalized from `wordID`'s prefix so `#Predicate` can filter by
    /// language directly, without string-prefix matching in the query.
    var languageCode: String
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var nextReviewDate: Date
    var firstReviewedDate: Date?
    var learnedDate: Date?

    init(
        wordID: String, languageCode: String, easeFactor: Double, intervalDays: Int,
        repetitions: Int, nextReviewDate: Date, firstReviewedDate: Date?, learnedDate: Date?
    ) {
        self.wordID = wordID
        self.languageCode = languageCode
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
        self.firstReviewedDate = firstReviewedDate
        self.learnedDate = learnedDate
    }
}
```

- [ ] **Step 4: Create `SwiftDataReviewStore.swift`**

```swift
import Domain
import Foundation
import SwiftData

@ModelActor
public actor SwiftDataReviewStore: ReviewStore {
    public func reviewState(for word: WordID) async throws -> ReviewState? {
        let wordID = word.rawValue
        let descriptor = FetchDescriptor<PersistentReviewState>(
            predicate: #Predicate { $0.wordID == wordID })
        return try modelContext.fetch(descriptor).first.map(Self.toDomain)
    }

    public func save(_ state: ReviewState) async throws {
        let wordID = state.wordID.rawValue
        let descriptor = FetchDescriptor<PersistentReviewState>(
            predicate: #Predicate { $0.wordID == wordID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.easeFactor = state.easeFactor
            existing.intervalDays = state.intervalDays
            existing.repetitions = state.repetitions
            existing.nextReviewDate = state.nextReviewDate
            existing.firstReviewedDate = state.firstReviewedDate
            existing.learnedDate = state.learnedDate
        } else {
            modelContext.insert(Self.toPersistent(state))
        }
        try modelContext.save()
    }

    public func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState] {
        let code = languageCode.rawValue
        let descriptor = FetchDescriptor<PersistentReviewState>(
            predicate: #Predicate { $0.languageCode == code })
        return try modelContext.fetch(descriptor).map(Self.toDomain)
    }

    public func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary {
        let states = try await allStates(languageCode)
        let learned = states.filter { $0.learnedDate != nil }.count
        let inProgress = states.filter { $0.firstReviewedDate != nil && $0.learnedDate == nil }
            .count
        return ProgressSummary(
            wordsLearned: learned, wordsInProgress: inProgress,
            totalReviewed: learned + inProgress)
    }

    private static func toDomain(_ persisted: PersistentReviewState) -> ReviewState {
        ReviewState(
            wordID: WordID(persisted.wordID),
            easeFactor: persisted.easeFactor,
            intervalDays: persisted.intervalDays,
            repetitions: persisted.repetitions,
            nextReviewDate: persisted.nextReviewDate,
            firstReviewedDate: persisted.firstReviewedDate,
            learnedDate: persisted.learnedDate)
    }

    private static func toPersistent(_ state: ReviewState) -> PersistentReviewState {
        PersistentReviewState(
            wordID: state.wordID.rawValue,
            languageCode: languageCode(fromWordID: state.wordID.rawValue),
            easeFactor: state.easeFactor,
            intervalDays: state.intervalDays,
            repetitions: state.repetitions,
            nextReviewDate: state.nextReviewDate,
            firstReviewedDate: state.firstReviewedDate,
            learnedDate: state.learnedDate)
    }

    private static func languageCode(fromWordID wordID: String) -> String {
        String(wordID.split(separator: ":", maxSplits: 1).first ?? "")
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/Data --filter SwiftDataReviewStoreTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Run the full Data suite and check coverage**

Run: `swift test --package-path Packages/Data --enable-code-coverage && scripts/coverage-gate.sh Packages/Data 80 DataPackageTests`
Expected: PASS, ≥ 80% line coverage.

- [ ] **Step 7: Commit**

```bash
git add Packages/Data/Sources/Data/PersistentReviewState.swift Packages/Data/Sources/Data/SwiftDataReviewStore.swift Packages/Data/Tests/DataTests/SwiftDataReviewStoreTests.swift
git commit -m "feat(data): add SwiftDataReviewStore, actor-isolated per ADR-001"
```

---

### Task 7: Final verification

**Files:** none — this task only runs gates, no code changes.

- [ ] **Step 1: Run the full Domain suite with coverage**

Run: `swift test --package-path Packages/Domain --enable-code-coverage && scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests`
Expected: PASS, ≥ 90% line coverage.

- [ ] **Step 2: Run the full Data suite with coverage**

Run: `swift test --package-path Packages/Data --enable-code-coverage && scripts/coverage-gate.sh Packages/Data 80 DataPackageTests`
Expected: PASS, ≥ 80% line coverage.

- [ ] **Step 3: Run the determinism check**

Run: `scripts/determinism-check.sh`
Expected: PASS — no `Date()`, sleeps, or unseeded randomness in any new test file (all new tests use `.distantPast` or `Date(timeIntervalSince1970:)` literals).

- [ ] **Step 4: Lint**

Run: `swiftlint lint --strict`
Expected: PASS, no violations in the new files.

- [ ] **Step 5: Confirm the build compiles warnings-as-errors clean**

Run: `swift build --package-path Packages/Domain -Xswiftc -warnings-as-errors && swift build --package-path Packages/Data -Xswiftc -warnings-as-errors`
Expected: PASS.

No commit for this task — it's verification only, and Task 6's commit already left the tree clean.
