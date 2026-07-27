# Phase 8 — Presentation Layer: Design

**Phase:** 8 (Presentation: SwiftUI + ViewModels) · **Status:** Approved for planning · **Date:** 2026-07-26

This is the design for the presentation layer: three thin SwiftUI screens driven by three
`@Observable` ViewModels, plus the last Domain pieces those ViewModels need (`SessionBuilder`,
a day clock, the entitlement port) and the `SpeechService` port that Presentation owns.

Builds on: `build-plan.md` PHASE 8, `architecture.md` §3 (port sketches) and §4 (concurrency),
[ADR-002](../../adr/ADR-002-ui-architecture.md) (MVVM + `@Observable`, no coordinator, no DI
framework), [ADR-003](../../adr/ADR-003-testing-frameworks.md) (Swift Testing), the Phase 5
`Scheduler`, and the Phase 7 ports + in-memory doubles the ViewModel tests run against.

---

## Scope

**In scope:**

- Domain: `SessionBuilder` (session assembly, FR-3/FR-4), `DayClock` port + `SystemDayClock` /
  `FixedDayClock`, `EntitlementStore` port, and an internal `DayCalendar` helper extracted from
  `Scheduler`.
- Presentation: the `SpeechService` port, its `AVSpeechSynthesizer` adapter, and a fake.
- Three `@MainActor @Observable` ViewModels — study, progress, language selection — built
  test-first against Phase 7's in-memory doubles.
- Three thin SwiftUI views replacing the Phase 4 placeholders, plus a composition root in
  `FullDeckApp` and a Phase-8-only in-code sample pack to run against.
- ViewModel unit tests in the `FullDeckTests` target (Swift Testing, fakes only).

**Out of scope (explicitly deferred):**

- **Real persistence wiring.** The composition root injects Phase 7's `InMemoryPackStore` /
  `InMemoryReviewStore`; pointing it at `JSONPackStore` + `SwiftDataReviewStore` and bundling
  `fr.pack.json` + a production manifest as app resources is Phase 9 ("wire the real layers
  together end-to-end"). *This supersedes the line in the Phase 7 design that anticipated Phase 8
  doing the real wiring* — the build plan puts Phase 8 on fakes and Phase 9 on real layers.
- The learned-threshold rule `L` and the completion screen (Phase 9). `learnedDate` stays `nil`,
  so progress reads `0 / N` and no completion state exists yet — `StudyViewModel.State` has no
  `.completed` case in this phase.
- A settings screen for the new-word cap `N` (FR-4's "user-adjustable" half). `N` is injected as a
  constant, default 10.
- Persisting which language is active across launches (Phase 9), StoreKit (Phase 11), the
  accessibility audit and error-copy pass (Phase 10), visual design (Phase 13).

---

## 1. Domain additions

### 1.1 `DayCalendar` (internal helper)

`Scheduler` already owns a private fixed Gregorian/UTC `Calendar` so day arithmetic never depends
on device locale or time zone. `SessionBuilder` needs the same calendar for "is this due today?"
and "was this introduced today?". Two copies would be two things that can drift, so the calendar
moves to one internal type both use:

```swift
enum DayCalendar {
    static let gregorianUTC: Calendar   // Gregorian, tz = .gmt
    static func startOfDay(_ date: Date) -> Date
    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool
    static func adding(days: Int, to date: Date) -> Date
}
```

Internal, not `public`: it is an implementation detail of the Domain package. `Scheduler`'s public
behavior does not change — this is a pure extraction, and the existing scheduler tests are the
regression net for it.

### 1.2 `SessionBuilder` (pure, test-first)

```swift
public struct SessionBuilder: Sendable {
    public static let defaultNewWordCap = 10
    public init() {}

    public func build(
        pack: LanguagePack,
        states: [ReviewState],
        today: Date,
        newWordCap: Int = SessionBuilder.defaultNewWordCap
    ) -> [WordEntry]
}
```

Rules:

1. **Due reviews (FR-3, never capped — FR-4).** A pack entry is due when it has a `ReviewState`
   whose `nextReviewDate` falls on or before `today`'s UTC day. Ordered by `nextReviewDate`
   ascending, ties broken by `rank` ascending, so the most-overdue and most-frequent words come
   first. A never-reviewed word's default `nextReviewDate` of `.distantPast` does **not** make it
   "due" — a word with no state is a *new* word and goes through the cap.
2. **New words (FR-4).** Pack entries with no `ReviewState`, ordered by `rank` ascending, limited
   to `max(0, newWordCap - introducedToday)`, where `introducedToday` counts states **belonging to
   this pack** whose `firstReviewedDate` is on `today`'s UTC day. Scoping the count to pack
   membership is what makes the cap per-language (FR-4) a property of the function rather than of
   its caller. A cap of 0 or less yields no new words.
3. **Order.** All due reviews first, then new words. Reviews are the debt; new words are the
   optional extra on top.
4. **Language scoping.** Entries come from the pack, so states belonging to another language
   simply never match a `WordID` in it. No filtering branch needed.
5. **Purity.** No `Date()`, no I/O, `today` injected — the same `(pack, states, today, cap)`
   always yields the same queue.

`SessionBuilder` does **not** re-queue a failed card within the session. `Scheduler`'s own note
already frames intra-session relearning steps as "add them if the spot-check says lapses aren't
sticking" — a lapsed word returns tomorrow. Not building it now keeps the queue a plain array.

### 1.3 `DayClock` port

```swift
public protocol DayClock: Sendable { var today: Date { get } }
public struct SystemDayClock: DayClock { public var today: Date { Date() } }
public struct FixedDayClock: DayClock { public let today: Date }   // tests
```

`architecture.md` §3 sketched this as `Clock`. It is named `DayClock` instead because Swift's
concurrency library already exports a `Clock` protocol; a Domain type of the same name would force
`Domain.Clock` disambiguation in every app-target file that imports both. `DayClock` also says
what it is: day-granular "today", not a monotonic instant source.

`FixedDayClock` ships in Domain sources alongside the existing `InMemoryPackStore` /
`InMemoryReviewStore` doubles, so the app target's tests can use it without duplicating it.

### 1.4 `EntitlementStore` port

```swift
public protocol EntitlementStore: Sendable {
    func isUnlocked(_ languageCode: LanguageCode) -> Bool
}
```

Synchronous — a purchase check is a local lookup, and Phase 11's StoreKit implementation can cache
its entitlement set behind this same signature. The Phase 8 stub lives in the app target and always
returns `false`. The lock rule is in `LanguageSelectionViewModel`, not in the store:

```
isUnlocked = descriptor.unlockedByDefault || entitlements.isUnlocked(descriptor.languageCode)
```

so the free launch language (FR-2) is a property of the pack manifest, and purchases only ever add
to it.

---

## 2. The speech port (Presentation-owned)

Domain never learns that audio exists (`architecture.md` §3). The port lives in the app target:

```swift
@MainActor
protocol SpeechService {
    func speak(_ text: String, language: LanguageCode) throws
    func stop()
}

enum SpeechError: Error, Equatable { case voiceUnavailable(LanguageCode) }
```

- **`@MainActor` on the protocol.** `AVSpeechSynthesizer` is a non-`Sendable` UIKit-era class;
  pinning the whole port to the main actor is how it stays legal under Swift 6 strict concurrency
  without wrapping it in an actor. The ViewModels are already `@MainActor`, so calls are free.
- **No `isAvailable(for:)` probe.** FR-7 needs the app to degrade gracefully when a language's
  voice is missing; the throw carries that. `AVSpeechService.speak` looks up
  `AVSpeechSynthesisVoice(language:)`, throws `.voiceUnavailable` when it is `nil`, and otherwise
  speaks an `AVSpeechUtterance`. `StudyViewModel` catches it, sets `audioUnavailable = true`, and
  the session stays fully usable. One code path instead of a probe plus a throw.
- `FakeSpeechService` (test target) records `(text, language)` calls and can be told to throw.

Speech is **manual**: the learner taps to hear the word or the sentence. Nothing auto-plays — FR-7
says the learner *can* play audio, and auto-speaking a card in a quiet room is a surprise, not a
feature.

---

## 3. ViewModels

All three are `@MainActor @Observable final class`, take every dependency through `init`
(constructor injection, no singletons), and expose read-only state to their view.

> **`@Observable`** (iOS 17+) makes stored properties automatically tracked: a SwiftUI view that
> reads `viewModel.state` re-renders when exactly that property changes. **`@MainActor`** pins the
> class to the main thread, so UI state is never mutated off it; `await` inside a `@MainActor`
> method hops off for the I/O and comes back on the main actor.

### 3.1 `StudyViewModel`

```swift
@MainActor @Observable
final class StudyViewModel {
    enum State: Equatable {
        case loading
        case card(Card)
        case caughtUp(nextDue: Date?)
        case failed(String)
    }

    struct Card: Equatable {
        let entry: WordEntry
        var isRevealed: Bool
        let index: Int          // 1-based position in the session
        let total: Int
    }

    private(set) var state: State = .loading
    private(set) var audioUnavailable = false

    init(languageCode: LanguageCode, packStore: PackStore, reviewStore: ReviewStore,
         scheduler: Scheduler, sessionBuilder: SessionBuilder, speech: SpeechService,
         clock: DayClock, newWordCap: Int = SessionBuilder.defaultNewWordCap)

    func start() async
    func reveal()
    func grade(_ grade: Grade) async
    func speakWord()
    func speakSentence()
}
```

Behavior:

- **`start()`** loads the pack and that language's states, builds the queue via `SessionBuilder`,
  and shows the first card — or `.caughtUp` when the queue is empty (FR-12). `nextDue` is the
  earliest future `nextReviewDate` across the language's states, `nil` when there is none.
- **`reveal()`** flips `isRevealed`. The card's front shows the target word and its part of speech;
  reveal adds the gloss and the example sentence (FR-5, direction: target word → meaning). The
  gloss is optional in the pack schema; when it is `nil` the reveal shows the example sentence
  alone rather than an empty label.
- **`grade(_:)`** is a **no-op unless the card is revealed** — that is the enforcement half of
  active recall (FR-5). Otherwise: `Scheduler.schedule(state, grade:, today: clock.today)`, stamp
  `firstReviewedDate = clock.today` if it was `nil` (this is what makes the FR-4 daily cap
  countable — Phase 9 still owns `learnedDate`), `ReviewStore.save`, then advance to the next card
  or `.caughtUp`.
- **`speakWord()` / `speakSentence()`** call the port with the pack's language code; a
  `voiceUnavailable` throw sets `audioUnavailable` and changes nothing else (FR-7).
- **Errors.** Any `PackLoadError` or store failure becomes `.failed(message)` — never a crash
  (NFR-10). Phase 10 owns the final user-facing copy.

### 3.2 `ProgressViewModel`

```swift
@MainActor @Observable
final class ProgressViewModel {
    enum State: Equatable { case loading, ready(learned: Int, total: Int), failed(String) }
    private(set) var state: State = .loading
    init(languageCode: LanguageCode, packStore: PackStore, reviewStore: ReviewStore)
    func load() async
}
```

`learned` comes from `ReviewStore.progress(_:).wordsLearned`, `total` from `LanguagePack.wordCount`.
Words learned out of 1000 and nothing else (FR-10) — no streaks, no time-spent, no review counts.
Reads `0 / N` until Phase 9 defines `L`.

### 3.3 `LanguageSelectionViewModel`

```swift
@MainActor @Observable
final class LanguageSelectionViewModel {
    struct Option: Equatable, Identifiable {
        let descriptor: PackDescriptor
        let isUnlocked: Bool
        var id: String { descriptor.languageCode.rawValue }
    }
    enum State: Equatable { case loading, ready([Option]), failed(String) }

    private(set) var state: State = .loading
    private(set) var activeLanguage: LanguageCode?

    init(packStore: PackStore, entitlements: EntitlementStore)
    func load() async
    func select(_ option: Option)
}
```

`select` sets `activeLanguage` only when the option is unlocked; selecting a locked pack does not
start a session (FR-1, FR-14). A locked row shows a lock affordance; the purchase sheet is
Phase 11.

---

## 4. Views and the composition root

Three thin views replace the Phase 4 placeholders. Plain system styling — the design pass is
Phase 13. Logic stays in the ViewModels; the views only read state and send intents.

- **`StudyView`** — switches on `state`: a progress indicator while loading; the card (word, POS,
  a speaker button; after reveal, gloss + example sentence, a second speaker button, and the four
  grade buttons); the caught-up view (FR-12) with the next-review date when known; an error view.
  `audioUnavailable` shows an inline "audio unavailable" note.
- **`LearningProgressView`** — "`learned` of `total` words learned", nothing else.
- **`LanguageSelectionView`** — a `List` of options with lock state and a checkmark on the active
  one.

Accessibility basics land here, not later: each interactive control gets a VoiceOver label, and
text uses Dynamic-Type-scaling styles (no fixed point sizes). The audit and the manual walkthrough
are Phase 10.

**Composition root.** `FullDeckApp` constructs the graph once and injects it (ADR-002: no DI
framework, no singletons): `InMemoryPackStore` seeded from a Phase-8-only in-code `SamplePack`
(~8 French entries), `InMemoryReviewStore`, `AVSpeechService`, the always-false entitlement stub,
and `SystemDayClock`. Both the sample pack and the in-memory stores are marked `ponytail:` and are
deleted in Phase 9 when the real adapters and the bundled pack land.

`ContentView` keeps its three tabs and owns `@State private var activeLanguage: LanguageCode?`.
Study and Progress show a "choose a language first" placeholder while it is `nil`, and build their
ViewModels keyed to the selected language (`.id(activeLanguage)`) once it is set. Persisting the
choice is Phase 9.

---

## 5. Testing and traceability

Test-first for all ViewModel and `SessionBuilder` behavior, one behavior at a time
(red → green → refactor). Views are thin glue and are not unit-tested in this phase.

| Suite | Location | Runs with |
|-------|----------|-----------|
| `SessionBuilder` | `Packages/Domain/Tests/DomainTests` | `swift test` (seconds) |
| ViewModels | `FullDeck/FullDeckTests` | `xcodebuild test` (simulator) |

Presentation lives in the app target (`architecture.md` §2), so its tests need a simulator. That is
the accepted cost of that deliberate simplification; the fast `swift test` loop still covers all
new Domain logic.

Coverage: the Domain floor (≥ 90%) applies to `SessionBuilder` and the new ports. No floor on the
app target — by policy, coverage % there is noise.

Fakes only in ViewModel tests: `InMemoryPackStore`, `InMemoryReviewStore`, `FixedDayClock`,
`FakeSpeechService`, a stub `EntitlementStore`. No real persistence, no real TTS, no `Date()`,
no sleeps — `scripts/determinism-check.sh` already greps `FullDeckTests`.

Every test's display name starts with its requirement ID. Planned coverage:

- **FR-1** selection lists packs with correct lock state; selecting a locked pack does not become active.
- **FR-3** the queue contains due reviews and new words for the active language.
- **FR-4** new words are capped at `N` minus those already introduced today; due reviews are never capped.
- **FR-5** the answer is hidden until `reveal()`; `grade(_:)` before reveal does nothing.
- **FR-6** every card carries exactly one non-empty example sentence.
- **FR-7** speaking sends word/sentence to the port with the pack's language; a `voiceUnavailable`
  throw sets `audioUnavailable` and leaves the session usable.
- **FR-8** grading calls the scheduler and persists the returned state.
- **FR-10** progress reports `wordsLearned` out of the pack's `wordCount`.
- **FR-12** an empty queue yields the caught-up state with the next due date.
- **NFR-10** a pack load failure yields `.failed`, not a crash.

Gates unchanged: `swiftlint --strict`, `-warnings-as-errors` (which is also what will flag any
deprecated `AVSpeechSynthesizer` API), determinism check, coverage gate.

---

## 6. Concurrency model

- ViewModels are `@MainActor @Observable` — every state mutation is on the main thread; `async`
  methods `await` the stores and resume on the main actor.
- `Scheduler` and `SessionBuilder` are synchronous pure value types — callable from anywhere.
- `SpeechService` is `@MainActor` (§2) because `AVSpeechSynthesizer` is not `Sendable`.
- `EntitlementStore` and `DayClock` are `Sendable` and synchronous.
- Views launch async work with `.task { await viewModel.start() }`, which SwiftUI cancels when the
  view disappears.

---

## 7. Open questions / deferred

1. **Intra-session relearning.** A lapsed card returns tomorrow, not later in the same session.
   Revisit after the Phase 13 spot-check if lapses do not stick.
2. **Session length.** No cap on total cards: all due reviews plus up to `N` new words. If a
   backlog ever produces uncomfortably long sessions, a cap belongs in `SessionBuilder`, not in the
   ViewModel.
3. **`N` as a setting.** FR-4 requires it to be user-adjustable; the screen and its persistence are
   deferred, so FR-4 is only half-closed by this phase.
4. **Card-front content.** Target word plus POS only. If the POS tag turns out to be noise for
   learners, drop it in the Phase 13 design pass.
