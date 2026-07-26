# Phase 7 — Persistence Layer: Design

**Phase:** 7 (Data Pipeline follow-on: Persistence) · **Status:** Approved for planning · **Date:** 2026-07-26

This is the design for the concrete persistence implementation behind the `PackStore` and
`ReviewStore` ports sketched in `architecture.md` §3. It finalizes the port signatures (Domain
owns them; they existed only as sketches before this phase), the two concrete adapters (JSON for
read-only packs, SwiftData for mutable review state, per [ADR-001](../../adr/ADR-001-persistence.md)),
and the in-memory test doubles Phase 8's ViewModel tests will depend on.

Builds on: `architecture.md` §3 (port sketches) and §4 (concurrency model), ADR-001 (persistence
tech split), ADR-004 (pack format/bundling/discovery), `language-pack-schema.md` (the JSON
contract and its validation rules), and the Phase 6 pipeline's `fixtures/invalid/` rejection set,
which this phase's loader must also reject correctly.

---

## Scope

**In scope:**
- Domain-layer port protocols (`PackStore`, `ReviewStore`) and the value types they traffic in
  (`LanguagePack`, `WordEntry`, `PackDescriptor`, `ProgressSummary`), finalized from sketch to
  real code.
- `JSONPackStore`: reads a manifest + pack JSON files from an injected directory, validates
  against the Structural profile (`language-pack-schema.md` §7), returns typed errors.
- `SwiftDataReviewStore`: actor-isolated SwiftData adapter for review state + per-language
  progress.
- `InMemoryPackStore` / `InMemoryReviewStore`: fakes conforming to the same ports, for Phase 8's
  ViewModel tests.
- Two new fields on `ReviewState`: `firstReviewedDate`, `learnedDate` (both `Date?`, default
  `nil`) — storage plumbing only.
- A new fixture: `fixtures/manifest.json`, for `availablePacks()` tests.

**Out of scope (explicitly deferred):**
- The learned-threshold rule `L` itself (Phase 9, per `requirements.md`) — Phase 7 persists
  `learnedDate` faithfully but nothing sets it yet, so `wordsLearned` is mechanically `0` until
  Phase 9 lands.
- The real production `manifest.json` listing `pipeline/packs/fr.pack.json`, and bundling packs
  as actual App-target resources — that's Phase 8's composition-root wiring (`App.swift`
  constructs the concrete adapters and points them at the real bundle).
- `EntitlementStore` (Phase 8 stub, Phase 11 real) and `SessionBuilder`/`StatsService` (Phase 9) —
  unrelated to this phase's ports.

---

## 1. Domain additions

New file `Packages/Domain/Sources/Domain/Ports.swift` plus additions to `Models.swift`. Domain
owns these — Data implements them, Presentation consumes them (architecture.md §3).

### Value types

`LanguageCode` is a new wrapper, matching the existing `WordID` pattern (`Models.swift`'s comment
on `WordID` already names the reason: "so a word key can never be passed where a language code...
is expected"). `architecture.md`'s own port sketches already used the name `LanguageCode`, not
`String` — this finalizes that, rather than downgrading it.

```swift
public struct LanguageCode: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String)
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
}

public struct PackSource: Equatable, Sendable {
    public let name: String
    public let license: String
    public let attribution: String
}

public enum PartOfSpeech: String, Equatable, Sendable, CaseIterable {
    case noun = "NOUN", verb = "VERB", adj = "ADJ", adv = "ADV", num = "NUM", intj = "INTJ"
    case det = "DET", adp = "ADP", pron = "PRON", aux = "AUX"
    case cconj = "CCONJ", sconj = "SCONJ", part = "PART"
}

public enum Register: String, Equatable, Sendable {
    case casual, neutral, formal
}

public struct PackDescriptor: Equatable, Sendable {
    public let languageCode: LanguageCode
    public let displayName: String
    public let filename: String
    public let unlockedByDefault: Bool
}

public struct ProgressSummary: Equatable, Sendable {
    public let wordsLearned: Int
    public let wordsInProgress: Int   // firstReviewedDate set, learnedDate not
    public let totalReviewed: Int     // wordsLearned + wordsInProgress
}
```

`audio` and `generator` (schema §2/§4) are intentionally not modeled yet — no v1 pack populates
either field, and adding them later is additive (schema §9 says new optional fields never bump
`schema_version`). `PartOfSpeech` only needs the entry-valid set (schema §3); `PROPN` etc. never
appear as a `WordEntry.pos`.

### Ports

```swift
public protocol PackStore: Sendable {
    func availablePacks() async throws -> [PackDescriptor]
    func loadPack(_ languageCode: LanguageCode) async throws -> LanguagePack
}

public protocol ReviewStore: Sendable {
    func reviewState(for word: WordID) async throws -> ReviewState?
    func save(_ state: ReviewState) async throws
    func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState]
    func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary
}
```

### `ReviewState` additions

```swift
public var firstReviewedDate: Date?   // set on first save with repetitions > 0 — by whoever calls save(); Phase 7 doesn't decide when
public var learnedDate: Date?         // set once L is met — Phase 9's rule, not Phase 7's
```

Additive with default `nil` — existing Phase 5 `Scheduler` tests are untouched.

### `PackLoadError`

```swift
public enum PackLoadError: Error, Equatable, Sendable {
    case fileNotFound(languageCode: LanguageCode)
    case malformedJSON(String)
    case unsupportedSchemaVersion(found: Int, maxSupported: Int)
    case validationFailed(rule: String, reason: String)
}
```

`rule` carries the VR id (`"VR-3"`, etc.), matching the convention `fixtures/invalid/expected.json`
already established in Phase 6 — tests assert the exact rule fired, not just "some error."

---

## 2. `JSONPackStore` (Data layer)

A `Sendable` struct, not an actor — no mutable state to protect beyond an immutable injected
directory URL, so actor isolation would buy nothing (ponytail: skip it).

```swift
public struct JSONPackStore: PackStore, Sendable {
    public init(packsDirectory: URL, maxSupportedSchemaVersion: Int = 1)
}
```

- `availablePacks()` — reads `manifest.json` in `packsDirectory`, decodes to `[PackDescriptor]`.
- `loadPack(_:)` — resolves the filename via the manifest, reads + decodes the JSON, runs the
  **Structural-profile validator** (`language-pack-schema.md` §7, VR-1 through VR-16 — VR-17/18
  are shippable-only and stay out of scope here, same as the fixtures themselves waive them), then
  maps the validated DTO to `LanguagePack`. `schema_version > maxSupportedSchemaVersion` is checked
  first and maps to `.unsupportedSchemaVersion` — the dedicated fail-closed case from schema §9 —
  before any other validation runs.

The validator reuses the same rejection fixtures the Python pipeline validates against
(`fixtures/invalid/*`, cross-referenced by `fixtures/invalid/expected.json`) — both validators
now consume the same corpus, per `language-pack-schema.md` §12's stated intent. Test fixture
access: a small `#filePath`-relative helper in `DataTests` walks up from the test file to the
repo-root `/fixtures` directory. No SPM resource bundling or symlinks — this is test-only file
I/O on the host machine, not a shipped resource.

**New fixture:** `fixtures/manifest.json`, listing `fr-mini.pack.json` as its one entry, for
`availablePacks()` tests. Lives alongside the existing fixtures, same convention.

---

## 3. `SwiftDataReviewStore` (Data layer)

```swift
@Model
final class PersistentReviewState {
    var wordID: String
    var languageCode: String   // LanguageCode.rawValue, denormalized from wordID's prefix — the
                                // mapper wraps/unwraps at the port boundary; #Predicate needs the
                                // raw String field to filter directly
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var nextReviewDate: Date
    var firstReviewedDate: Date?
    var learnedDate: Date?
}

@ModelActor
public actor SwiftDataReviewStore: ReviewStore { ... }
```

`@ModelActor` (Swift 6's standard pattern for isolating a non-`Sendable` `ModelContext`) generates
an actor wrapping the context; every method serializes automatically, and only `Sendable` domain
value types (`ReviewState`, `ProgressSummary`) cross the port — `PersistentReviewState` never
leaves the Data layer (ADR-001).

- `reviewState(for:)` / `save(_:)` — fetch/upsert by `wordID`; a small mapper is the single place
  `@Model ↔ Domain.ReviewState` conversion happens.
- `allStates(_:)` — `#Predicate` filtered on `languageCode`.
- `progress(_:)` — computed purely from stored dates: `learnedDate != nil` → learned;
  `firstReviewedDate != nil && learnedDate == nil` → in progress. Does not know the pack's total
  word count (that's `PackStore`'s domain — Phase 9's `StatsService` combines both). Currently
  `wordsLearned` will be `0` for everything, since nothing sets `learnedDate` yet — expected, and
  a test constructing a state with `learnedDate` pre-set proves the read path independent of who
  writes it.

Package tests use an in-memory `ModelConfiguration` (ADR-001). Also covers: missing/corrupt data
returns a typed error rather than crashing (NFR-10), and one migration smoke test confirming
`ModelContainer(for:)` succeeds cleanly — thin by design, since there's only one schema version
right now.

---

## 4. In-memory fakes (Domain package)

```swift
public actor InMemoryPackStore: PackStore { ... }
public actor InMemoryReviewStore: ReviewStore { ... }
```

Plain dictionary-backed actors, zero dependencies beyond Foundation. Live in
`Packages/Domain/Sources/Domain/` (the main library target, not `Tests/`) — Phase 8's
`PresentationTests` needs to import them across the package boundary, and a test target can't
import another package's test target. Shipped in the release binary; harmless, ~50 lines, no
framework weight, keeps ViewModel tests linking only Domain (no SwiftData).

---

## 5. Testing & coverage

- **Domain:** new port types + fakes, covered by conformance/round-trip tests. Folds into the
  existing ≥90% floor.
- **Data:** `JSONPackStore` rejection-fixture tests are written first (build-plan is explicit: the
  loader's error mapping is logic) — one test per `fixtures/invalid/*` entry asserting the exact
  `PackLoadError` case/rule, `fr-mini.pack.json` as the positive control throughout. Watch each
  fail because the validator doesn't exist yet, implement one VR at a time to green.
  `SwiftDataReviewStore` round-trip/error/migration-smoke tests are glue — tested alongside the
  implementation, not necessarily first. Existing ≥80% floor and `scripts/coverage-gate.sh` are
  unchanged.

---

## 6. Concurrency model

Two different isolation stories, deliberately:

- **`JSONPackStore`** — no shared mutable state (just reads a file), so a plain `Sendable` struct
  is enough. `async throws` on the protocol is satisfied trivially; an actor here would add
  overhead for nothing.
- **`SwiftDataReviewStore`** — `ModelContext` genuinely is mutable state, and SwiftData itself
  marks it non-`Sendable`. `@ModelActor` generates an actor wrapping that context, so every access
  is automatically serialized — no data races — and only the `Sendable` value types the port
  promises (`ReviewState`, `ProgressSummary`) ever cross the boundary. Callers just `await`; the
  isolation is invisible from outside.

---

## Open questions / deferred

- **`L` (learned threshold)** — Phase 9. `learnedDate`/`firstReviewedDate` exist and round-trip
  correctly starting now, so Phase 9 only needs to add the rule that sets them, not a SwiftData
  migration.
- **Real app-bundle wiring** (production `manifest.json`, bundling `pipeline/packs/fr.pack.json`
  as an App-target resource, composition-root construction of the concrete adapters) — Phase 8.
- **`StatsService`** (trend data, hardest-words ranking, combining `PackStore` + `ReviewStore`
  progress) — Phase 9, per architecture.md §3.
