# Architecture — "Top 1000 Words" (working title)

**Written:** Phase 2 (2026-07-07) · **Status:** Accepted; kept current as the app is built ·
**Last checked against the code:** 2026-08-01 (after Phase 11)

This document is the system design. It was written before any production code and has held:
every layer below now exists, and the shape has not changed. It realizes the hard rules in
`CLAUDE.md` (strict inward-only layering; pure, dependency-free domain; everything testable
behind protocols) and the structure recommended in `docs/claude-code-xcode-setup.md`
(Domain and Data as local Swift packages, a thin app target). Decisions that needed a
"which technology" call are recorded as ADRs in `docs/adr/` and cross-referenced here.

> New-to-Swift notes are inline in quotes like this, the first time a concept appears.

---

## 1. Layered architecture

Three layers. **Dependencies point inward only** — an outer layer may know about an inner
layer, never the reverse. The Domain is the center and imports nothing.

| Layer | Responsibility | May depend on | Must NOT import |
|-------|----------------|---------------|-----------------|
| **Presentation** | SwiftUI views (thin) + `@Observable` ViewModels; user interaction; speech playback; wiring (composition root). | Domain | SwiftData, file system directly |
| **Domain** | The product's brain, in pure Swift: the spaced-repetition scheduler, session assembly, progress/"learned" rules, the domain models, and the **ports** (protocols) it needs. Deterministic and side-effect-free. | *nothing* (Foundation only) | SwiftUI, SwiftData, AVFoundation, the file system |
| **Data** | Concrete persistence: loads bundled JSON language packs; stores/reads review state + settings via SwiftData. Implements the Domain ports. | Domain | SwiftUI, Presentation |

> A **port** is just a protocol (interface) declared by the inner layer that describes what
> it needs ("give me the review state for this word"), without saying how it's done. The
> outer Data layer provides the **adapter** (the concrete implementation). This is dependency
> inversion: the Domain depends on an abstraction it owns, not on persistence.

Why this shape: the Domain — where correctness is non-negotiable (`CLAUDE.md`) — has zero
framework or I/O dependencies, so it's unit-testable in isolation and driven deterministically
(including an injectable "today"). Adding a language never touches this code; it's a data pack
(ADR-004).

---

## 2. Module & target breakdown

Two local Swift packages plus a thin app target. Package boundaries **enforce the dependency
rules at compile time** — a package physically cannot import something it doesn't declare, so
"Domain must not import persistence" is guaranteed by the compiler, not by discipline alone.

```
Language_App/
├─ Packages/
│  ├─ Domain/                 SPM package · pure Swift · zero deps
│  │  ├─ Sources/Domain/      Scheduler, SessionBuilder, models, ports (protocols)
│  │  └─ Tests/DomainTests/   Swift Testing · runs via `swift test`, no simulator
│  └─ Data/                   SPM package · imports Domain
│     ├─ Sources/Data/        JSON PackStore, SwiftData ReviewStore, mappers
│     └─ Tests/DataTests/     Swift Testing · round-trips, fixture pack, error paths
└─ FullDeck/ (Xcode app target, thin SwiftUI shell)
   ├─ Views/                  SwiftUI views (thin)
   ├─ ViewModels/             @Observable, @MainActor
   ├─ Services/               Adapters for the two Presentation-owned ports:
   │                          AVSpeechService (TTS), StoreKitPurchaseService
   │                          (purchases + entitlements), plus their no-op stubs
   ├─ DesignSystem/           Spacing scale, the swipe-commit rule (pure, tested)
   ├─ Errors/                 PackLoadError → user-facing message mapping
   ├─ FullDeckApp.swift       @main entry
   ├─ AppDependencies.swift   Composition root (DI wiring)
   └─ FullDeckTests / FullDeckUITests
                              ViewModel + integration (Swift Testing), UI (XCUITest)
```

> **SPM package** = a self-contained unit of Swift with its own `Package.swift` manifest and
> test target. `swift test --package-path Packages/Domain` runs its tests in seconds without
> booting a simulator — the fast TDD loop Phase 5 needs.
>
> **Target** = one buildable product (a package's library, the app, or a test bundle).

**Test seams** (where each part is tested in isolation):
- **Domain** — pure; tested directly, no doubles needed except the injected clock.
- **Data** — tested against the real SwiftData store (in-memory configuration) and the Phase 3 fixture pack.
- **Presentation** — ViewModels depend only on Domain ports, so tests inject in-memory fakes (fake stores, fake clock, fake speech) — no real persistence or TTS. (Phase 7 also ships an in-memory store double for this.)

> **Deliberate simplification (ponytail):** Presentation lives in the app target, not its own
> package. ViewModels are still unit-testable (they depend only on protocols). If ViewModel
> test speed or stricter boundary enforcement ever matters, promote `Presentation` to a third
> SPM package — contained change, do it when it pays for itself, not before.

---

## 3. Key protocol boundaries (the ports)

These are the seams that let every layer be injected and mocked. Signatures are sketches to
show the shape — final APIs land in Phases 5/7/8. `async throws` because I/O can be slow and
can fail (errors are typed and surfaced, never crashes — NFR-10).

**Owned by Domain** (Data implements them; Presentation consumes them):

```swift
// Read-only bundled content. Adapter: JSON+Codable (ADR-004).
protocol PackStore {
    func availablePacks() async throws -> [PackDescriptor]      // drives language selection (FR-1)
    func loadPack(_ language: LanguageCode) async throws -> LanguagePack
}

// Mutable per-user state. Adapter: SwiftData (ADR-001).
protocol ReviewStore {
    func reviewState(for word: WordID) async throws -> ReviewState?
    func save(_ state: ReviewState) async throws
    func allStates(_ language: LanguageCode) async throws -> [ReviewState]
    func progress(_ language: LanguageCode) async throws -> ProgressSummary   // FR-10
}

// Injectable "today" so the scheduler is deterministic in tests (Phase 5).
protocol Clock { var today: Date { get } }

// Is a language purchased/unlocked? Stubbed in Phase 8, StoreKit-backed in Phase 11 (FR-14).
// Synchronous and non-throwing on purpose: it is read while drawing a list row.
protocol EntitlementStore { func isUnlocked(_ language: LanguageCode) -> Bool }
```

**Owned by Presentation** (Domain never knows about audio or money):

```swift
// Wraps on-device TTS (spec D3). Concrete: AVSpeechService (AVSpeechSynthesizer).
// Callers can't tell TTS from a future bundled recording (FR-7). Fake-able in tests.
protocol SpeechService {
    func speak(_ text: String, language: LanguageCode) throws
    func stop()
}

// Buying a language (FR-14, FR-15). Concrete: StoreKitPurchaseService — the only
// file in the app that imports StoreKit. It also implements EntitlementStore, so
// one object answers both "is it unlocked?" and "unlock it"; `entitlementChanges`
// is how an out-of-band unlock (a restore, an approved Ask-to-Buy) reaches the UI
// without a relaunch. Fake-able in tests; the composition root's default is a
// no-op so nothing but `live()` ever reaches the store.
protocol PurchaseService: Sendable {
    var entitlementChanges: AsyncStream<Void> { get }
    func price(for language: LanguageCode) async throws -> String?
    func purchase(_ language: LanguageCode) async throws -> PurchaseOutcome
    func restore() async throws
}
```

> **Why the purchase port is owned by Presentation, not Domain:** the Domain's
> question is "may this learner study Hindi?", which `EntitlementStore` already
> answers. Buying is a UI flow with a UI state machine (`PurchaseViewModel`), and
> the Domain stayed byte-for-byte unchanged through Phase 11 — the check that the
> boundary is in the right place.

**Pure Domain services** (not ports — plain testable types the ViewModel calls):
- `Scheduler` — SM-2-style; `schedule(_ state:, grade:, today:) -> ReviewState`. Pure (Phase 5).
- `SessionBuilder` — assembles a session queue from a pack + review states + `today` + the daily new-word cap `N`: all due reviews plus up to `N` new words (FR-3, FR-4).
- `StatsService` — computes progress from a pack + `ReviewStore.allStates(...)`: words-learned count (FR-10), the learning-over-time trend from per-word milestone dates (FR-17), and hardest-words ranking by ease factor (FR-18). Pure; needs no new port.

### How a study session wires together
1. **Composition root** (`AppDependencies.live()`) constructs the concrete adapters — `JSONPackStore`, `SwiftDataReviewStore`, `AVSpeechService`, and one `StoreKitPurchaseService` passed as *both* the `EntitlementStore` and the `PurchaseService` — and injects them into the ViewModel via its initializer.

   > **Composition root** = the single place where concrete dependencies are created and wired. Everywhere else receives them through `init` (constructor injection). No singletons, no globals (`CLAUDE.md`), no DI framework needed.

2. `StudyViewModel` (Presentation) loads the pack via `PackStore` and states via `ReviewStore`, asks `SessionBuilder` for the queue, and presents one `SessionCard` at a time.
3. On reveal the learner grades (`G`); the ViewModel calls `Scheduler.schedule(...)` (pure Domain) then `ReviewStore.save(...)`; progress refreshes (FR-8, FR-9, FR-10).
4. Audio is triggered by the ViewModel through `SpeechService` — Domain is uninvolved.

---

## 4. Concurrency model (Swift 6 strict concurrency)

The 2026 baseline is Swift 6 with strict concurrency checking on.

> **Where it is actually on (still true as of Phase 11):** the Domain and Data packages declare
> `swiftLanguageModes: [.v6]`, so everything below is compiler-enforced there. The app target
> still builds in Swift 5 mode with `SWIFT_APPROACHABLE_CONCURRENCY` and
> `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — migration aids, not complete data-race
> checking. Its `@MainActor @Observable` ViewModels follow the model by construction, but
> nothing enforces it yet. Flipping the app target to Swift 6 is **deferred to its own phase**
> (`CLAUDE.md`), deliberately kept out of Phase 10 so each stays reviewable on its own.
>
> That default isolation has a sharp edge worth knowing: an *undecorated* type in the app
> target is implicitly `@MainActor`, enums included. `PurchaseService`, its value types, and
> `StoreKitPurchaseService` are all marked `nonisolated` for exactly this reason — a
> lock-backed entitlement cache and a `Transaction.updates` loop must not be pinned to the
> main actor.

- **Domain** types are `Sendable` value types (structs/enums); `Scheduler`/`SessionBuilder` are synchronous pure functions — trivially concurrency-safe.
- **ViewModels** are `@MainActor @Observable` — UI state is always touched on the main thread.

  > **`@Observable`** (iOS 17+) makes a class's properties automatically tracked by SwiftUI, so views re-render precisely when the data they read changes. It's the modern replacement for `ObservableObject`/`@Published` and is what makes SwiftUI's default flow "effectively MVVM" (ADR-002).

- **Data** isolates its store. SwiftData's `ModelContext` is **not** `Sendable`, so the `SwiftDataReviewStore` keeps the context internal (a `ModelActor` / dedicated context) and only ever returns `Sendable` domain values across the port. SwiftData `@Model` types never leak past the Data layer (ADR-001).

  > **`actor`** = a type that serializes access to its own mutable state, preventing data races. Isolating the non-Sendable SwiftData context inside one is how we hand safe value types outward.

---

## 5. ADR index

| ADR | Decision |
|-----|----------|
| [ADR-001](adr/ADR-001-persistence.md) | Persistence: JSON+Codable for read-only packs; **SwiftData** for the mutable progress store; both behind repository ports. |
| [ADR-002](adr/ADR-002-ui-architecture.md) | UI pattern: **MVVM with `@Observable`**, thin views, constructor-injected ViewModels; no Coordinator/TCA. |
| [ADR-003](adr/ADR-003-testing-frameworks.md) | Tests: **Swift Testing** for unit/integration; **XCUITest** for UI; snapshot via `swift-snapshot-testing` if adopted in Phase 13. |
| [ADR-004](adr/ADR-004-language-pack-format.md) | Packs: **versioned JSON** conforming to the Phase 3 schema, bundled as resources, discovered via a manifest, updated by app release. Validated by adding a second language in Phase 12 — verdict in [`phase-12-verdict.md`](phase-12-verdict.md). |

---

## 6. How this satisfies the CLAUDE.md hard rules

- *Strict inward-only layering* → package boundaries enforce it at compile time (§2).
- *Pure, dependency-free Domain, testable in isolation* → Domain package imports only Foundation; scheduler is pure with an injected clock (§3).
- *Add a language = add a data pack, not code* → data-driven pack discovery (ADR-004); no per-language code path.
- *Speech behind a protocol, swappable for recordings* → `SpeechService` port (§3, FR-7).
- *No singletons / injected dependencies* → composition root + constructor injection (§3).
- *Never crash on bad data* → ports are `async throws`; typed errors surface as UI states (NFR-10).
