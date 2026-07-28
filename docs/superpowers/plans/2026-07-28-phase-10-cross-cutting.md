# Phase 10 — Cross-Cutting Concerns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden FullDeck's cross-cutting concerns per `docs/build-plan.md` PHASE 10 — accessibility (automated + manual), typed-error-to-message mapping, an offline-first audit, a Spanish UI localization catalog, and a documented observability decision.

**Architecture:** No new layers. Work happens entirely within the existing `FullDeck` app target (Views, ViewModels) and the Domain package's test doubles (`InMemoryPackStore`, `InMemoryReviewStore` gain error-injection for the new tests). One new file, `Errors/PackLoadError+UserMessage.swift`, maps the existing `Domain.PackLoadError` cases to distinct, localized, user-facing strings — the mapping lives in the app target (presentation concern), not Domain, per `CLAUDE.md`'s layering rule. Localization is delivered as a String Catalog (`Localizable.xcstrings`) authored directly as JSON (not via `xcodebuild -exportLocalizations`/`-importLocalizations`, which would add a fragile, hard-to-verify shell round-trip for no benefit over hand-authoring the same file).

**Tech Stack:** Swift 5 (app target, unchanged this phase — see Global Constraints), SwiftUI, Swift Testing (`FullDeckTests`), XCTest/XCUITest (`FullDeckUITests`), Xcode 26 String Catalogs (`.xcstrings`).

## Global Constraints

- Coverage floors: Domain ≥ 90%, Data ≥ 80% (`scripts/coverage-gate.sh`) — this phase touches Domain's test doubles, re-check after Task 1.
- `swiftlint lint --strict` and `-warnings-as-errors` must stay clean after every task.
- `scripts/determinism-check.sh` must stay clean — no `Date()`, sleeps, or unseeded randomness in any new test.
- Test names are prefixed with the requirement ID they verify (`FR-`, `NFR-`). This phase is almost entirely NFR-4, NFR-5, NFR-6 (accessibility), NFR-10 (robustness), NFR-1 (offline), NFR-7/NFR-8 (privacy/observability), NFR-12 (localization).
- **Swift 6 migration of the app target is explicitly OUT of scope for this phase** (deferred per `CLAUDE.md`'s updated note) — do not touch `SWIFT_VERSION`/strict-concurrency settings on the `FullDeck` target.
- UI localization target language is **Spanish (`es`)**, chosen by Arjun during brainstorming — do not substitute another language.
- No new third-party dependencies. No analytics/tracking SDK of any kind (NFR-8) — the observability decision this phase makes is "none," not "which one."
- Build/test commands throughout, run from repo root:
  ```sh
  swift test --package-path Packages/Domain
  xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
    -destination 'platform=iOS Simulator,name=iPhone 17'
  swiftlint lint --strict
  ```

---

### Task 1: Error-injection support in Domain's in-memory test doubles

**Files:**
- Modify: `Packages/Domain/Sources/Domain/InMemoryPackStore.swift`
- Modify: `Packages/Domain/Sources/Domain/InMemoryReviewStore.swift`
- Modify: `Packages/Domain/Tests/DomainTests/InMemoryPackStoreTests.swift`
- Modify: `Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift`

**Interfaces:**
- Produces: `InMemoryPackStore.init(descriptors:packs:errorOverride:)` — new `errorOverride: PackLoadError? = nil` parameter; when set, `availablePacks()` and `loadPack(_:)` both throw it instead of their normal behavior.
- Produces: `InMemoryReviewStore.init(seed:saveErrorOverride:)` — new `saveErrorOverride: (any Error & Sendable)? = nil` parameter; when set, `save(_:)` throws it instead of writing.
- Produces: `FakeStoreError` — a trivial `Error, Sendable` struct for tests that need *some* non-`PackLoadError` failure to inject into `save(_:)`.
- Consumes: nothing new — both types already exist and are used by every existing ViewModel test via `import Domain`.

Both existing types take only defaulted parameters today, so every current call site (`InMemoryPackStore(descriptors: ...)`, `InMemoryReviewStore(seed: ...)`) keeps compiling unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `Packages/Domain/Tests/DomainTests/InMemoryPackStoreTests.swift`:

```swift
@Test("NFR-10 an injected errorOverride is thrown from availablePacks")
func errorOverrideThrowsFromAvailablePacks() async throws {
    let store = InMemoryPackStore(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await #expect(throws: PackLoadError.unsupportedSchemaVersion(found: 99, maxSupported: 1)) {
        try await store.availablePacks()
    }
}

@Test("NFR-10 an injected errorOverride is thrown from loadPack")
func errorOverrideThrowsFromLoadPack() async throws {
    let store = InMemoryPackStore(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await #expect(throws: PackLoadError.unsupportedSchemaVersion(found: 99, maxSupported: 1)) {
        try await store.loadPack(LanguageCode("fr"))
    }
}
```

Add to `Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift`:

```swift
struct FakeStoreError: Error, Equatable, Sendable {}

@Test("NFR-10 an injected saveErrorOverride is thrown from save")
func saveErrorOverrideThrows() async throws {
    let store = InMemoryReviewStore(saveErrorOverride: FakeStoreError())

    await #expect(throws: FakeStoreError()) {
        try await store.save(ReviewState(wordID: WordID("fr:chat:NOUN")))
    }
}
```

(If `FakeStoreError` already has an obvious home in that file's existing fixtures, place it at file scope there instead of inline — it must be visible to this test, no `private`.)

- [ ] **Step 2: Run tests to verify they fail**

```sh
swift test --package-path Packages/Domain --filter errorOverrideThrows
swift test --package-path Packages/Domain --filter saveErrorOverrideThrows
```

Expected: FAIL — `init(descriptors:packs:errorOverride:)` and `init(seed:saveErrorOverride:)` don't exist yet (compile error). Confirm the failure is that, not a typo.

- [ ] **Step 3: Implement**

`Packages/Domain/Sources/Domain/InMemoryPackStore.swift`:

```swift
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
```

`Packages/Domain/Sources/Domain/InMemoryReviewStore.swift`:

```swift
public actor InMemoryReviewStore: ReviewStore {
    private var statesByWord: [WordID: ReviewState]
    private let saveErrorOverride: (any Error & Sendable)?

    public init(seed: [ReviewState] = [], saveErrorOverride: (any Error & Sendable)? = nil) {
        var initial: [WordID: ReviewState] = [:]
        for state in seed {
            initial[state.wordID] = state
        }
        self.statesByWord = initial
        self.saveErrorOverride = saveErrorOverride
    }

    public func reviewState(for word: WordID) async throws -> ReviewState? {
        statesByWord[word]
    }

    public func save(_ state: ReviewState) async throws {
        if let saveErrorOverride { throw saveErrorOverride }
        statesByWord[state.wordID] = state
    }

    public func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState] {
        statesByWord.values.filter { $0.wordID.languageCode == languageCode }
            .sorted { $0.wordID.rawValue < $1.wordID.rawValue }
    }

    public func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary {
        let states = try await allStates(languageCode)
        return ProgressSummary(states: states)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```sh
swift test --package-path Packages/Domain
```

Expected: all pass, including the two new ones.

- [ ] **Step 5: Re-check Domain coverage floor**

```sh
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
```

Expected: still ≥ 90%. The new `if let errorOverride` branches are now exercised by the tests above.

- [ ] **Step 6: Commit**

```bash
git add Packages/Domain/Sources/Domain/InMemoryPackStore.swift \
  Packages/Domain/Sources/Domain/InMemoryReviewStore.swift \
  Packages/Domain/Tests/DomainTests/InMemoryPackStoreTests.swift \
  Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift
git commit -m "test(domain): add error-injection to the in-memory PackStore/ReviewStore doubles"
```

---

### Task 2: Reveal button accessibility hint

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift:79`

**Interfaces:** none — self-contained view change.

The accessibility survey found every other interactive control on this screen has a label or hint; the "Reveal" button (the active-recall gate — FR-5) has neither, relying only on its visible title.

- [ ] **Step 1: Make the change**

```swift
Button("Reveal") { viewModel.reveal() }
    .buttonStyle(.borderedProminent)
    .accessibilityHint("Shows the answer")
```

- [ ] **Step 2: Build and manually confirm with VoiceOver**

Build to a simulator, enable VoiceOver (Settings → Accessibility → VoiceOver, or `xcrun simctl` doesn't toggle this — use the Simulator's Accessibility Inspector or a real device), navigate to the Reveal button on the Study tab, confirm it announces "Reveal, button, Shows the answer."

- [ ] **Step 3: Run the full app test suite**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: unchanged pass count — this is additive, no existing test asserts the Reveal button's accessibility properties.

- [ ] **Step 4: Commit**

```bash
git add FullDeck/FullDeck/Views/StudyView.swift
git commit -m "feat(app): add an accessibility hint to the Reveal button"
```

---

### Task 3: `PackLoadError` → distinct user-facing messages

**Files:**
- Create: `FullDeck/FullDeck/Errors/PackLoadError+UserMessage.swift`
- Create test: `FullDeck/FullDeckTests/PackLoadErrorUserMessageTests.swift`

**Interfaces:**
- Produces: `PackLoadError.userMessage: String` — a computed property, already localized via `String(localized:)` at the point each case's copy is written (so the String Catalog in Task 9 can extract it).
- Consumes: `Domain.PackLoadError` (`fileNotFound`, `malformedJSON`, `unsupportedSchemaVersion`, `validationFailed` — all four cases, `Packages/Domain/Sources/Domain/Ports.swift:45-53`).

Today all three ViewModels catch generically and show one blanket message regardless of *which* `PackLoadError` case fired. This task adds the mapping as a pure, independently testable extension; Task 4 wires it into the ViewModels. Two buckets: a schema-version mismatch means the *app* is stale (an update fixes it); everything else means the *pack data* is unreadable (reinstalling fixes it) — there's no actionable difference between "not found," "malformed," and "failed a validation rule" from the learner's point of view.

- [ ] **Step 1: Write the failing tests**

```swift
import Domain
import Testing

@testable import FullDeck

@Test("NFR-10 a schema-version mismatch tells the learner an app update is needed")
func schemaVersionMismatchSuggestsUpdate() {
    let error = PackLoadError.unsupportedSchemaVersion(found: 99, maxSupported: 1)

    #expect(error.userMessage == "This language needs an app update.")
}

@Test("NFR-10 a missing pack file tells the learner to reinstall")
func fileNotFoundSuggestsReinstall() {
    let error = PackLoadError.fileNotFound(languageCode: LanguageCode("fr"))

    #expect(error.userMessage == "This language's data couldn't be read. Try reinstalling the app.")
}

@Test("NFR-10 malformed JSON tells the learner to reinstall")
func malformedJSONSuggestsReinstall() {
    let error = PackLoadError.malformedJSON("unexpected end of file")

    #expect(error.userMessage == "This language's data couldn't be read. Try reinstalling the app.")
}

@Test("NFR-10 a failed validation rule tells the learner to reinstall")
func validationFailedSuggestsReinstall() {
    let error = PackLoadError.validationFailed(rule: "VR-3", reason: "duplicate word id")

    #expect(error.userMessage == "This language's data couldn't be read. Try reinstalling the app.")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FullDeckTests/PackLoadErrorUserMessageTests
```

Expected: FAIL — `userMessage` doesn't exist yet (compile error).

- [ ] **Step 3: Implement**

```swift
import Domain

/// Phase 10, NFR-10 + build-plan #2: per-case error copy, not one blanket
/// message. A schema mismatch means the *app* is stale; everything else means
/// the bundled pack data itself can't be read — the learner can't tell "not
/// found" from "malformed" apart, so those three share one message.
extension PackLoadError {
    var userMessage: String {
        switch self {
        case .unsupportedSchemaVersion:
            String(localized: "This language needs an app update.")
        case .fileNotFound, .malformedJSON, .validationFailed:
            String(
                localized: "This language's data couldn't be read. Try reinstalling the app.")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FullDeckTests/PackLoadErrorUserMessageTests
```

Expected: all 4 pass.

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/Errors/PackLoadError+UserMessage.swift \
  FullDeck/FullDeckTests/PackLoadErrorUserMessageTests.swift
git commit -m "feat(app): map each PackLoadError case to a distinct user-facing message"
```

---

### Task 4: Wire per-case messages into the three ViewModels + close the two NFR-10 gaps

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift:37-58`
- Modify: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift:80-99`, `:110-129`
- Modify: `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift:31-40`
- Modify: `FullDeck/FullDeckTests/Fakes.swift:75-86` (`makeStudyViewModel`)
- Modify: `FullDeck/FullDeckTests/ProgressViewModelTests.swift:7-17` (`makeProgressViewModel`)
- Modify: `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift:22-30` (`makeSelectionViewModel`)
- Modify: `FullDeck/FullDeckTests/StudyViewModelTests.swift`
- Modify: `FullDeck/FullDeckTests/ProgressViewModelTests.swift`

**Interfaces:**
- Consumes: `PackLoadError.userMessage` (Task 3), `InMemoryPackStore(errorOverride:)` and `InMemoryReviewStore(saveErrorOverride:)` (Task 1).
- Produces: `makeStudyViewModel(..., errorOverride: PackLoadError? = nil)`, `makeProgressViewModel(..., errorOverride: PackLoadError? = nil)`, `makeSelectionViewModel(..., errorOverride: PackLoadError? = nil)` — each threads the new parameter into its internal `InMemoryPackStore` construction. None of these three factories currently expose a way to inject a `PackLoadError` (confirmed by reading all three: they build `InMemoryPackStore(descriptors:packs:)` internally from `pack:`/`descriptors:`, with no override), so this task adds it rather than assuming it already exists.

Each `do { ... } catch { ... }` becomes a specific `catch let error as PackLoadError` (uses `.userMessage`) followed by a generic `catch` (unchanged fallback message, for `ReviewStore`-thrown errors, which stay opaque — there's no finite, actionable set of cases to branch on the way `PackLoadError` has).

- [ ] **Step 1: Add `errorOverride:` to the three ViewModel test-helper factories**

`FullDeck/FullDeckTests/Fakes.swift:75-86` — add the parameter and pass it through:

```swift
func makeStudyViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    today: Date = day0,
    newWordCap: Int = SessionBuilder.defaultNewWordCap,
    speech: FakeSpeechService = FakeSpeechService(),
    reviewStore: InMemoryReviewStore = InMemoryReviewStore(),
    errorOverride: PackLoadError? = nil
) -> StudyViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:],
        errorOverride: errorOverride)
    return StudyViewModel(
```

(Everything after that `return StudyViewModel(` line is unchanged — only the signature and the `InMemoryPackStore(...)` call gain the new argument.)

`FullDeck/FullDeckTests/ProgressViewModelTests.swift:7-17`:

```swift
private func makeProgressViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    seed: [ReviewState] = [],
    errorOverride: PackLoadError? = nil
) -> ProgressViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:],
        errorOverride: errorOverride)
    return ProgressViewModel(
        languageCode: code, packStore: packStore,
        reviewStore: InMemoryReviewStore(seed: seed))
}
```

`FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift:22-30`:

```swift
private func makeSelectionViewModel(
    descriptors: [PackDescriptor] = [frDescriptor(), hindiDescriptor],
    unlocked: Set<String> = [],
    defaults: UserDefaults = emptyDefaults(),
    errorOverride: PackLoadError? = nil
) -> LanguageSelectionViewModel {
    LanguageSelectionViewModel(
        packStore: InMemoryPackStore(descriptors: descriptors, errorOverride: errorOverride),
        entitlements: StubEntitlementStore(unlocked: unlocked), defaults: defaults)
}
```

- [ ] **Step 2: Write the failing tests**

Add to `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift` (this file currently has *no* NFR-10 test — closing that gap):

```swift
@Test("NFR-10 a schema-version mismatch surfaces the update message")
@MainActor
func schemaVersionMismatchSurfacesUpdateMessage() async {
    let viewModel = makeSelectionViewModel(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await viewModel.load()

    #expect(viewModel.state == .failed("This language needs an app update."))
}
```

Add to `FullDeck/FullDeckTests/StudyViewModelTests.swift`:

```swift
@Test("NFR-10 a schema-version mismatch surfaces the update message")
@MainActor
func schemaVersionMismatchSurfacesUpdateMessage() async {
    let viewModel = makeStudyViewModel(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await viewModel.start()

    #expect(viewModel.state == .failed("This language needs an app update."))
}

@Test("NFR-10 a save failure surfaces a failed state instead of crashing")
@MainActor
func saveFailureSurfacesFailedState() async {
    let store = InMemoryReviewStore(saveErrorOverride: FakeStoreError())
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.good)

    #expect(viewModel.state == .failed("Couldn't save your progress."))
}
```

(`FakeStoreError` from Task 1 is a Domain-package type, visible here the same way `InMemoryReviewStore` already is via `import Domain`.)

Add to `FullDeck/FullDeckTests/ProgressViewModelTests.swift`:

```swift
@Test("NFR-10 a schema-version mismatch surfaces the update message")
@MainActor
func schemaVersionMismatchSurfacesUpdateMessage() async {
    let viewModel = makeProgressViewModel(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await viewModel.load()

    #expect(viewModel.state == .failed("This language needs an app update."))
}
```

- [ ] **Step 3: Run tests to verify they fail**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FullDeckTests/LanguageSelectionViewModelTests \
  -only-testing:FullDeckTests/StudyViewModelTests \
  -only-testing:FullDeckTests/ProgressViewModelTests
```

Expected: the three new tests FAIL with the *old* blanket message (e.g. got `"Couldn't load the available languages."`, expected `"This language needs an app update."`) — not a compile error. That confirms the test is exercising real, not-yet-updated behavior.

- [ ] **Step 4: Implement — `LanguageSelectionViewModel.load()`**

```swift
func load() async {
    state = .loading
    do {
        let descriptors = try await packStore.availablePacks()
        state = .ready(
            descriptors.map { descriptor in
                Option(
                    descriptor: descriptor,
                    isUnlocked: descriptor.unlockedByDefault
                        || entitlements.isUnlocked(descriptor.languageCode))
            })
        if activeLanguage == nil,
            let saved = defaults.string(forKey: Self.activeLanguageKey),
            descriptors.contains(where: { $0.languageCode.rawValue == saved }) {
            activeLanguage = LanguageCode(saved)
        }
    } catch let error as PackLoadError {
        state = .failed(error.userMessage)
    } catch {
        state = .failed(String(localized: "Couldn't load the available languages."))
    }
}
```

- [ ] **Step 5: Implement — `StudyViewModel.start()`**

```swift
func start() async {
    if case .card = state { return }
    state = .loading
    do {
        let pack = try await packStore.loadPack(languageCode)
        wordCount = pack.wordCount
        states = try await reviewStore.allStates(languageCode)
        queue = sessionBuilder.build(
            pack: pack, states: states, today: clock.today, newWordCap: newWordCap)
        position = 0
        showCurrentCard()
    } catch let error as PackLoadError {
        state = .failed(error.userMessage)
    } catch {
        state = .failed(String(localized: "Couldn't load this language."))
    }
}
```

- [ ] **Step 6: Implement — `StudyViewModel.grade()`'s save-failure message**

Only the fallback string needs `String(localized:)` — `PackLoadError` can't occur here, `reviewStore.save` is the only throwing call:

```swift
} catch {
    state = .failed(String(localized: "Couldn't save your progress."))
    return
}
```

- [ ] **Step 7: Implement — `ProgressViewModel.load()`**

```swift
func load() async {
    state = .loading
    do {
        let pack = try await packStore.loadPack(languageCode)
        let progress = try await reviewStore.progress(languageCode)
        state = .ready(learned: progress.wordsLearned, total: pack.wordCount)
    } catch let error as PackLoadError {
        state = .failed(error.userMessage)
    } catch {
        state = .failed(String(localized: "Couldn't load your progress."))
    }
}
```

- [ ] **Step 8: Fix the two `IntegrationTests.swift` exact-message assertions if needed**

`FullDeck/FullDeckTests/IntegrationTests.swift:128,143` compare full-state equality against `.failed("Couldn't load this language.")` / `.failed("Couldn't load your progress.")`. Those fixtures use `fileNotFound`/`malformedJSON`-class failures (a genuinely corrupt/missing pack, not a schema mismatch), so the fallback bucket message is unchanged — these should still pass as-is. Run them to confirm:

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FullDeckTests/IntegrationTests
```

If either fails, read the actual vs. expected message in the failure output before changing anything — it means that fixture's error doesn't land in the bucket this plan assumed, and the fixture (not the mapping) is the thing to double check.

- [ ] **Step 9: Run the full app test suite**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: all pass, including every new test from this task and Task 3.

- [ ] **Step 10: Lint**

```sh
swiftlint lint --strict
```

- [ ] **Step 11: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift \
  FullDeck/FullDeckTests/Fakes.swift \
  FullDeck/FullDeck/ViewModels/StudyViewModel.swift \
  FullDeck/FullDeck/ViewModels/ProgressViewModel.swift \
  FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift \
  FullDeck/FullDeckTests/StudyViewModelTests.swift \
  FullDeck/FullDeckTests/ProgressViewModelTests.swift \
  FullDeck/FullDeckTests/IntegrationTests.swift
git commit -m "feat(app): surface distinct per-case messages for typed pack-load errors"
```

---

### Task 5: Automated accessibility audit (XCUITest)

**Files:**
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift`

**Interfaces:** none — pure addition to the existing `XCTestCase`.

Adds the "automated net" the build plan calls for: `XCUIApplication.performAccessibilityAudit()` on each of the three core screens. This is Xcode's built-in audit (missing labels, low contrast, clipping at large Dynamic Type) — separate from, and no substitute for, the manual VoiceOver walkthrough in Task 6.

- [ ] **Step 1: Write the test**

```swift
/// NFR-4, NFR-5, NFR-6: Xcode's built-in accessibility audit on each core
/// screen. Catches missing labels, insufficient contrast, and clipping at
/// large Dynamic Type sizes automatically, on every push. What it *can't*
/// judge — whether a label is meaningful, not just present — is the manual
/// VoiceOver walkthrough documented in docs/phase-10-verification.md.
@MainActor
func testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens() throws {
    let app = XCUIApplication()
    app.launch()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 5))
    try app.performAccessibilityAudit()

    let french = app.buttons["French"]
    XCTAssertTrue(french.waitForExistence(timeout: 5))
    french.tap()

    tabBar.buttons["Study"].tap()
    XCTAssertTrue(app.staticTexts["Card 1 of 5"].waitForExistence(timeout: 5))
    try app.performAccessibilityAudit()

    app.buttons["Reveal"].tap()
    try app.performAccessibilityAudit()

    tabBar.buttons["Progress"].tap()
    XCTAssertTrue(
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "words learned"))
            .firstMatch.waitForExistence(timeout: 5))
    try app.performAccessibilityAudit()
}
```

- [ ] **Step 2: Run it and read the result**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FullDeckUITests/FullDeckUITests/testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens
```

Two outcomes, both real signal:
- **Passes:** the survey's read of the existing accessibility labels (Phase 8/9 already did most of this work) holds up under Apple's own audit. Move on.
- **Fails:** `performAccessibilityAudit()` reports specific issues (e.g. a contrast ratio, a missing label Apple's heuristic flags that the human read in the survey missed). Read the failure message — it names the exact view and audit type (`XCUIAccessibilityAuditType`). Fix the flagged view directly (add the missing label, adjust the color, etc.) using the same patterns already in the codebase (`.accessibilityLabel`, `.accessibilityElement(children:)`). If a flagged issue is a deliberate, known-OK design choice (e.g. a decorative icon inside a row whose label already covers it — see `LanguageSelectionView.swift:38`), exclude that specific issue via the audit's `issueHandler:` closure rather than suppressing the whole audit type, and comment why.

- [ ] **Step 3: Re-run until green**

Repeat Step 2 after each fix until the test passes clean.

- [ ] **Step 4: Run the full suite**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeckUITests/FullDeckUITests.swift
git commit -m "test(app): add an automated accessibility audit across the core screens"
```

(If Step 2 required fixes to view files, include those files in this commit too, and mention what was fixed in the commit body.)

---

### Task 6: Cross-cutting verification doc — manual accessibility, offline audit, observability decision

**Files:**
- Create: `docs/phase-10-verification.md`

**Interfaces:** none — documentation only.

This is the write-up for the three parts of Phase 10 that are either manual-verification-only (accessibility walkthrough, offline audit) or a decision-and-rationale rather than code (observability). The offline-first code audit itself *is* done as part of writing this doc — grep the whole repo — so "no networking exists" is a verified finding, not an assumption.

- [ ] **Step 1: Run the offline-surface grep and record the result**

```sh
grep -rn "URLSession\|URLRequest\|\.dataTask\|http://\|https://\|NWConnection" \
  FullDeck/FullDeck Packages/Domain/Sources Packages/Data/Sources
```

Expected: no output (zero matches). Record the exact command and its empty result in the doc as the evidence, not just the conclusion.

- [ ] **Step 2: Write `docs/phase-10-verification.md`**

```markdown
# Phase 10 — Manual Verification & Decisions

## NFR-1 — Offline-first

Code audit: `grep -rn "URLSession\|URLRequest\|\.dataTask\|http://\|https://\|NWConnection" FullDeck/FullDeck Packages/Domain/Sources Packages/Data/Sources` returns zero matches. There is no networking code anywhere in the app target or the Domain/Data packages — NFR-1 holds by construction, not by a runtime check that could regress silently. The only feature that will ever touch the network is Phase 11's StoreKit purchase/restore flow, which doesn't exist yet.

`AVSpeechSynthesizer` (on-device TTS, spec decision D3) has no documented network fallback for on-device system voices — confirmed against Apple's documentation, not just assumed.

**Manual confirmation (Arjun, on a device):**
- [ ] Enable Airplane Mode.
- [ ] Launch FullDeck, select a language, complete one full study session (reveal + grade every card until caught-up or complete).
- [ ] Confirm no error state appeared and the session's grades are still there after backgrounding and reopening.

## NFR-4/NFR-5/NFR-6 — Manual accessibility walkthrough

The automated audit (Task 5) catches missing labels, contrast, and Dynamic-Type clipping mechanically. It cannot judge whether a label is *meaningful* — that needs a human.

**VoiceOver walkthrough (Arjun, on a device or Simulator with VoiceOver on — Settings → Accessibility → VoiceOver):**
- [ ] Languages tab: swipe through the list; each row announces its language name and lock/active state.
- [ ] Study tab: swipe through a card — word, part of speech, "Hear the word" — reveal it, swipe through the gloss, example sentence, "Hear the sentence," grade buttons, each announcing what it does.
- [ ] Progress tab: the learned/total readout announces as one combined phrase.
- [ ] Complete an entire study session using only VoiceOver gestures, no sighted assistance.

**Dynamic Type walkthrough (Settings → Accessibility → Display & Text Size → Larger Text → largest slider position, i.e. AX5):**
- [ ] Languages, Study, and Progress tabs each render with no truncated, clipped, or overlapping text.

## NFR-7/NFR-8 — Observability decision

**Decision: no analytics, no crash reporting, no usage telemetry of any kind. Local-only, by design, not a placeholder for "add it later."**

Rationale: `CLAUDE.md`'s design philosophy rejects "engagement/retention theater," and NFR-8 already forbids third-party trackers, IDFA, and ad networks outright. The app's only persisted data is what the product itself needs to function (`ReviewState` — ease factor, interval, dates — via `SwiftDataReviewStore`), already covered by NFR-7's local-only-storage guarantee. Adding *any* collection layer — even first-party, even aggregate-only — would be new surface area serving no v1 feature, in direct tension with "does this help someone learn the 1000 words, or is it engagement theater."

If a future need arises (e.g. diagnosing a crash reported by a user), the bar is: local-only, on-device, no per-user identifier, no event stream — an aggregate on-device log the user can inspect and clear themselves, never anything transmitted. That bar is not met today, so nothing is implemented.

## NFR-12 — UI localization

Delivered in Tasks 7–10 of `docs/superpowers/plans/2026-07-28-phase-10-cross-cutting.md`: a `Localizable.xcstrings` String Catalog with English (source) and Spanish translations for every UI-chrome string, proven by an XCUITest that launches the app with the Spanish locale and asserts translated text renders.
```

- [ ] **Step 3: Commit**

```bash
git add docs/phase-10-verification.md
git commit -m "docs: record the offline audit, accessibility walkthrough steps, and the observability decision"
```

(The two checklists inside the doc are Arjun's to physically walk through and check off on a device — that's a manual step this plan cannot execute. Flag it to Arjun at hand-off rather than marking it done.)

---

### Task 7: Localization plumbing — fix the two dynamic-string call sites

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift:104-111` (`label(for:)`), `:92-102` (`gradeButtons`)
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift:49-58` (`accessibilityLabel(for:)`)

**Interfaces:** none — internal, private helper functions only; return types stay `String` so no call site outside these two files changes.

Every *literal* string passed directly to a SwiftUI view initializer (`Text("Study")`, `Button("Reveal")`, `.navigationTitle("Progress")`, `.accessibilityLabel("Card \(card.index) of \(card.total)")`, etc.) is picked up by Xcode's String Catalog automatically — no code change needed there, only a catalog entry (Task 9). The two exceptions are these private helpers: each builds a `String` value *inside a function* and returns it, so by the time it reaches the view call site it's a plain `String`, not a literal — Xcode's extractor only recognizes literals at the call site, so these two would silently never localize without this fix. `String(localized:)` called *with a literal argument* is one of Xcode's other recognized extraction patterns, so wrapping each returned literal in it fixes both while keeping the function signatures unchanged.

- [ ] **Step 1: Fix `StudyView.label(for:)`**

```swift
private func label(for grade: Grade) -> String {
    switch grade {
    case .again: String(localized: "Again")
    case .hard: String(localized: "Hard")
    case .good: String(localized: "Good")
    case .easy: String(localized: "Easy")
    }
}
```

- [ ] **Step 2: Fix the composite accessibility label that uses it**

`gradeButtons` at line 99 already interpolates `label(for: grade)` into a literal at its own call site — `.accessibilityLabel("Grade this word \(label(for: grade))")` — so once `label(for:)` itself resolves through `String(localized:)`, this line needs no change; it was already extractable as its own format-string key ("Grade this word %@"). Leave it as-is.

- [ ] **Step 3: Fix `LanguageSelectionView.accessibilityLabel(for:)`**

```swift
private func accessibilityLabel(
    for option: LanguageSelectionViewModel.Option
) -> String {
    guard option.isUnlocked else {
        return String(localized: "\(option.descriptor.displayName), locked")
    }
    return isActive(option)
        ? String(localized: "\(option.descriptor.displayName), active language")
        : option.descriptor.displayName
}
```

- [ ] **Step 4: Build and run the full test suite**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: unchanged pass count. `String(localized:)` with no matching catalog entry yet just returns the literal English text verbatim (Foundation's fallback behavior when a key isn't found in any table), so every existing test that compares against the English strings — including the UI tests that look up `app.buttons["Grade this word Good"]` — still matches exactly, both before and after Task 9 adds the catalog.

- [ ] **Step 5: Lint**

```sh
swiftlint lint --strict
```

- [ ] **Step 6: Commit**

```bash
git add FullDeck/FullDeck/Views/StudyView.swift FullDeck/FullDeck/Views/LanguageSelectionView.swift
git commit -m "refactor(app): route the two dynamic accessibility-label helpers through String(localized:)"
```

---

### Task 8: Add Spanish as a project region

**Files:**
- Modify: `FullDeck/FullDeck.xcodeproj/project.pbxproj:209-212`

**Interfaces:** none.

This is a plain value edit inside an existing array (`knownRegions`) — no new file reference, no new build-phase membership, no structural change. Per the project's standing pbxproj-edit policy, a value-only change like this is fine to make directly rather than requiring the Xcode GUI; the diff below is the entire change.

- [ ] **Step 1: Make the edit**

```diff
 			knownRegions = (
 				en,
+				es,
 				Base,
 			);
```

- [ ] **Step 2: Open the project in Xcode (or `xcodebuild -list`) to confirm it still parses**

```sh
xcodebuild -list -project FullDeck/FullDeck.xcodeproj
```

Expected: lists the same schemes/targets as before, no parse error.

- [ ] **Step 3: Commit**

```bash
git add FullDeck/FullDeck.xcodeproj/project.pbxproj
git commit -m "chore(app): declare Spanish as a supported project region"
```

---

### Task 9: Create the String Catalog with English + Spanish

**Files:**
- Create: `FullDeck/FullDeck/Localizable.xcstrings`

**Interfaces:** none.

`FullDeck/FullDeck` is a `PBXFileSystemSynchronizedRootGroup` (confirmed at `project.pbxproj:38-42`) — any file placed directly under that folder on disk is picked up as a build resource automatically; no separate file-reference or build-phase edit is needed the way a classic Xcode group would require. `.xcstrings` is JSON; author it directly rather than via `xcodebuild -exportLocalizations`/`-importLocalizations`, which would add an unverifiable shell round-trip for the same end result.

- [ ] **Step 1: Write the catalog**

Create `FullDeck/FullDeck/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "Languages" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Idiomas" } }
      }
    },
    "Study" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Estudiar" } }
      }
    },
    "Progress" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Progreso" } }
      }
    },
    "Choose a language" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Elige un idioma" } }
      }
    },
    "Pick a language on the Languages tab to start." : {
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Elige un idioma en la pestaña Idiomas para empezar."
          }
        }
      }
    },
    "Something went wrong" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Algo salió mal" } }
      }
    },
    "%@, locked" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "%@, bloqueado" } }
      }
    },
    "%@, active language" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "%@, idioma activo" } }
      }
    },
    "Every word. That's the whole deck." : {
      "localizations" : {
        "es" : {
          "stringUnit" : { "state" : "translated", "value" : "Todas las palabras. El mazo completo." }
        }
      }
    },
    "%lld of %lld words learned" : {
      "localizations" : {
        "es" : {
          "stringUnit" : { "state" : "translated", "value" : "%lld de %lld palabras aprendidas" }
        }
      }
    },
    "of %lld words learned" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "de %lld palabras aprendidas" } }
      }
    },
    "Card %lld of %lld" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Tarjeta %lld de %lld" } }
      }
    },
    "Hear the word" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Escuchar la palabra" } }
      }
    },
    "Hear the word %@" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Escuchar la palabra %@" } }
      }
    },
    "Hear the sentence" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Escuchar la oración" } }
      }
    },
    "Hear the example sentence" : {
      "localizations" : {
        "es" : {
          "stringUnit" : { "state" : "translated", "value" : "Escuchar la oración de ejemplo" }
        }
      }
    },
    "Reveal" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Mostrar" } }
      }
    },
    "Shows the answer" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Muestra la respuesta" } }
      }
    },
    "Audio unavailable on this device." : {
      "localizations" : {
        "es" : {
          "stringUnit" : { "state" : "translated", "value" : "Audio no disponible en este dispositivo." }
        }
      }
    },
    "Grade this word %@" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Califica esta palabra: %@" } }
      }
    },
    "Again" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Otra vez" } }
      }
    },
    "Hard" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Difícil" } }
      }
    },
    "Good" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Bien" } }
      }
    },
    "Easy" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Fácil" } }
      }
    },
    "You're caught up" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Estás al día" } }
      }
    },
    "Next review %@." : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Próximo repaso %@." } }
      }
    },
    "Nothing is due right now." : {
      "localizations" : {
        "es" : {
          "stringUnit" : { "state" : "translated", "value" : "No hay nada pendiente ahora mismo." }
        }
      }
    },
    "You've learned all the words in this language." : {
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Has aprendido todas las palabras de este idioma."
          }
        }
      }
    },
    "Add another language — $0.99" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Añadir otro idioma — 0,99 $" } }
      }
    },
    "Opens the languages list" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Abre la lista de idiomas" } }
      }
    },
    "Couldn't load the available languages." : {
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No se pudieron cargar los idiomas disponibles."
          }
        }
      }
    },
    "Couldn't load this language." : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "No se pudo cargar este idioma." } }
      }
    },
    "Couldn't save your progress." : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "No se pudo guardar tu progreso." } }
      }
    },
    "Couldn't load your progress." : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "No se pudo cargar tu progreso." } }
      }
    },
    "Couldn't open your saved progress." : {
      "localizations" : {
        "es" : {
          "stringUnit" : { "state" : "translated", "value" : "No se pudo abrir tu progreso guardado." }
        }
      }
    },
    "This language needs an app update." : {
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Este idioma necesita una actualización de la app."
          }
        }
      }
    },
    "This language's data couldn't be read. Try reinstalling the app." : {
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No se pudieron leer los datos de este idioma. Intenta reinstalar la app."
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 2: Validate the JSON**

```sh
plutil -lint FullDeck/FullDeck/Localizable.xcstrings
```

Expected: `FullDeck/FullDeck/Localizable.xcstrings: OK`. If it reports a syntax error, fix the reported line before continuing — don't proceed with invalid JSON.

- [ ] **Step 3: Build the app target**

```sh
xcodebuild build -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: builds clean. A build failure here (not just the lint) means Xcode's own String Catalog compiler rejected something the JSON linter didn't catch (e.g. a key that doesn't match any extractable literal in source, which Xcode reports as a build warning, not an error, so this should still succeed — but read any new warnings that appear).

- [ ] **Step 4: Commit**

```bash
git add FullDeck/FullDeck/Localizable.xcstrings
git commit -m "feat(app): add the Localizable.xcstrings catalog with English and Spanish"
```

---

### Task 10: Prove the localization setup works end-to-end (NFR-12)

**Files:**
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift`

**Interfaces:** none.

**Consumes:** the catalog from Task 9. `XCUIApplication` supports launch arguments; `-AppleLanguages "(es)"` + `-AppleLocale "es_ES"` force the app to run under Spanish for exactly this one test process, without touching the Simulator's own system language.

- [ ] **Step 1: Write the test**

```swift
/// NFR-12: the UI chrome resolves through the localization catalog — this is
/// the "prove it, don't just wire it" step. Only the Study tab label is
/// checked; if the catalog resolves for one chrome string it resolves for
/// all of them (same mechanism, same file).
@MainActor
func testNFR12UIChromeIsLocalizedIntoSpanish() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
    app.launch()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(
        tabBar.buttons["Estudiar"].waitForExistence(timeout: 5),
        "Study tab did not render in Spanish. Hierarchy:\n\(app.debugDescription)")
    XCTAssertTrue(tabBar.buttons["Idiomas"].exists)
    XCTAssertTrue(tabBar.buttons["Progreso"].exists)
}
```

- [ ] **Step 2: Run it**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FullDeckUITests/FullDeckUITests/testNFR12UIChromeIsLocalizedIntoSpanish
```

Expected: PASS. If it fails, read `app.debugDescription` in the failure output — it dumps the actual accessibility tree, which will show what the tab labels actually rendered as (e.g. still English, meaning the catalog key didn't match the literal exactly — check for a typo or mismatched punctuation between the source string in Task 9's JSON and the literal in `ContentView.swift`).

- [ ] **Step 3: Run the full suite one more time**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: everything passes, including every test added across this whole plan.

- [ ] **Step 4: Commit**

```bash
git add FullDeck/FullDeckUITests/FullDeckUITests.swift
git commit -m "test(app): prove the Spanish localization catalog resolves at runtime"
```

---

### Task 11: Phase wrap-up

**Files:**
- Modify: `docs/next-task.md`

**Interfaces:** none.

- [ ] **Step 1: Run every gate one more time on the finished branch**

```sh
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
scripts/determinism-check.sh
scripts/trace-requirements.sh
swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: every gate green. Capture full output to a file and check the real exit code and summary banner (`** TEST SUCCEEDED **`) rather than trusting a piped/truncated tail — a truncated log was mistaken for success once already this project; don't repeat it.

- [ ] **Step 2: Self-review for tech debt**

Read back over every file this plan touched. Confirm there is no leftover: unused import, a `String(localized:)` call whose catalog key doesn't exist (Task 9's build warnings from Step 3 would have caught this, but double-check), or a TODO. Report any residual risk to Arjun directly rather than silently accepting it — in particular: the two manual checklists in `docs/phase-10-verification.md` are unchecked until Arjun walks through them on a device.

- [ ] **Step 3: Update `docs/next-task.md`**

Rewrite the "Right now" block to point at Phase 11 (StoreKit 2 design, Opus 5, xhigh effort — per the existing "Then" table), summarizing what Phase 10 shipped: automated + manual accessibility coverage, per-case pack-load error messages, a confirmed offline-first audit, a documented no-analytics decision, and a Spanish UI localization catalog proven by a runtime test. Strike through the Phase 10 rows in the "Full remaining map" table as done, dated today.

- [ ] **Step 4: Commit**

```bash
git add docs/next-task.md
git commit -m "docs: point the task doc at Phase 11"
```

- [ ] **Step 5: Hand off**

Report to Arjun: Phase 10 is complete on `phase-10-cross-cutting`, all gates green, and the two manual checklists in `docs/phase-10-verification.md` are waiting on him. Then follow `superpowers:finishing-a-development-branch` for the merge decision — do not merge unilaterally.
