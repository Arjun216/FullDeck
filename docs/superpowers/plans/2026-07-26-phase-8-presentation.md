# Phase 8 — Presentation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the three v1 screens — study session, progress, language selection — as thin SwiftUI views over tested `@Observable` ViewModels, plus the last Domain pieces they need (`SessionBuilder`, `DayClock`, `EntitlementStore`).

**Architecture:** MVVM per [ADR-002](../../adr/ADR-002-ui-architecture.md). ViewModels are `@MainActor @Observable` classes in the app target that depend only on Domain ports and pure Domain services, injected through `init`. Session assembly is pure Domain logic (`SessionBuilder`); speech is a Presentation-owned port so Domain never learns audio exists. The composition root wires Phase 7's in-memory doubles — real persistence is Phase 9.

**Tech Stack:** Swift 6 / Xcode 26, SwiftUI (iOS 17+ `@Observable`), Swift Testing, AVFoundation (`AVSpeechSynthesizer`), SwiftLint.

Design spec: [`docs/superpowers/specs/2026-07-26-phase-8-presentation-design.md`](../specs/2026-07-26-phase-8-presentation-design.md).

## Global Constraints

- **Test-first for all logic.** One behavior at a time: write the failing test → run it → confirm it fails *because the behavior is missing* → minimal implementation → green → refactor. A compile error is not a red; fix it and re-run until the failure is the assertion.
- **Requirement traceability.** Every test's display name starts with its requirement ID: `@Test("FR-3 ...")`.
- **Test determinism.** No `Date()`, `Date.now`, `Task.sleep`, `Thread.sleep`, or unseeded randomness in any file under a `*Tests/` directory — `scripts/determinism-check.sh` greps for exactly these and fails CI. Tests use the fixed `day0` instant and `FixedDayClock`.
- **Coverage floors (hard CI fail):** Domain ≥ 90%, Data ≥ 80%. No floor on the app target.
- **Warnings are errors.** `-warnings-as-errors` is on; this is also what will flag any deprecated AVFoundation API.
- **Lint:** `swiftlint lint --strict` must pass. Line length: 100 warn / 140 error, comments exempt.
- **Layering (hard rule).** Domain imports Foundation only — never SwiftUI, AVFoundation, or SwiftData. Presentation may import Domain. No singletons; every dependency arrives through `init`.
- **Conventional commits**, small and focused, one per task.
- **Deliberate simplifications** get a `// ponytail:` comment naming the ceiling and the upgrade path.
- **Deferred to later phases — do not build:** real persistence wiring and bundled pack resources (Phase 9), the learned rule `L` / `learnedDate` / the completion screen (Phase 9), a settings screen for the new-word cap (later), StoreKit (Phase 11), the accessibility audit and final error copy (Phase 10), visual design (Phase 13).

**Commands** (run from repo root):

```sh
swift test --package-path Packages/Domain
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
swiftlint lint --strict
```

**Shared test fixtures.** Domain tests already use this pattern (`SchedulerTests.swift`); reuse the exact same `day0`:

```swift
private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z
```

---

## File Structure

**Create:**

| File | Responsibility |
|------|----------------|
| `Packages/Domain/Sources/Domain/DayCalendar.swift` | The one fixed Gregorian/UTC calendar Domain does day math on |
| `Packages/Domain/Sources/Domain/SessionBuilder.swift` | Session assembly: due reviews + capped new words (FR-3, FR-4) |
| `Packages/Domain/Tests/DomainTests/DayCalendarTests.swift` | Day-comparison tests |
| `Packages/Domain/Tests/DomainTests/SessionBuilderTests.swift` | Session-assembly tests |
| `FullDeck/FullDeck/Services/SpeechService.swift` | Speech port + `SpeechError` (Presentation-owned) |
| `FullDeck/FullDeck/Services/AVSpeechService.swift` | `AVSpeechSynthesizer` adapter |
| `FullDeck/FullDeck/Services/StubEntitlementStore.swift` | Phase 8 entitlement stub + `SystemDayClock` |
| `FullDeck/FullDeck/ViewModels/StudyViewModel.swift` | Card sequencing, reveal/grade, speech (FR-3/5/6/7/8/12) |
| `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift` | Words learned out of the pack total (FR-10) |
| `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift` | Pack list, lock state, active language (FR-1, FR-2, FR-14) |
| `FullDeck/FullDeck/AppDependencies.swift` | The dependency container the composition root builds |
| `FullDeck/FullDeck/SamplePack.swift` | Phase-8-only in-code pack so the app runs before Phase 9 |
| `FullDeck/FullDeckTests/Fakes.swift` | `FakeSpeechService`, `FixedDayClock`, stub entitlements, pack builders |
| `FullDeck/FullDeckTests/StudyViewModelTests.swift` | Study ViewModel tests |
| `FullDeck/FullDeckTests/ProgressViewModelTests.swift` | Progress ViewModel tests |
| `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift` | Selection ViewModel tests |

**Modify:** `Packages/Domain/Sources/Domain/Scheduler.swift` (use `DayCalendar`), `Packages/Domain/Sources/Domain/Ports.swift` (add `DayClock`, `EntitlementStore`), the three views in `FullDeck/FullDeck/Views/`, `FullDeck/FullDeck/ContentView.swift`, `FullDeck/FullDeck/FullDeckApp.swift`, `FullDeck/FullDeckTests/FullDeckTests.swift`.

> **No Xcode project edits needed.** The project uses file-system-synchronized groups, so new `.swift` files under `FullDeck/FullDeck/` and `FullDeck/FullDeckTests/` join their targets automatically. Do not hand-edit `project.pbxproj`.

---

### Task 1: Domain — `DayCalendar`, `DayClock`, `EntitlementStore`

**Files:**
- Create: `Packages/Domain/Sources/Domain/DayCalendar.swift`
- Create: `Packages/Domain/Tests/DomainTests/DayCalendarTests.swift`
- Modify: `Packages/Domain/Sources/Domain/Scheduler.swift` (lines 24–31 and 65–66)
- Modify: `Packages/Domain/Sources/Domain/Ports.swift` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum DayCalendar` (internal) with `static func startOfDay(_ date: Date) -> Date`, `static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool`, `static func adding(days: Int, to date: Date) -> Date`; `public protocol DayClock: Sendable { var today: Date { get } }`; `public protocol EntitlementStore: Sendable { func isUnlocked(_ languageCode: LanguageCode) -> Bool }`.

- [ ] **Step 1: Write the failing tests**

Create `Packages/Domain/Tests/DomainTests/DayCalendarTests.swift`:

```swift
import Foundation
import Testing

@testable import Domain

private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

@Test("FR-4 two instants inside the same UTC day count as the same day")
func sameDayWithinTheDay() {
    let laterSameDay = day0.addingTimeInterval(23 * 3600)

    #expect(DayCalendar.isSameDay(day0, laterSameDay))
}

@Test("FR-4 an instant one day later is a different day")
func differentDayAcrossMidnight() {
    let nextDay = day0.addingTimeInterval(86_400)

    #expect(!DayCalendar.isSameDay(day0, nextDay))
}

@Test("FR-3 startOfDay truncates an instant to its UTC midnight")
func startOfDayTruncates() {
    let midAfternoon = day0.addingTimeInterval(13 * 3600 + 47 * 60)

    #expect(DayCalendar.startOfDay(midAfternoon) == day0)
}

@Test("FR-8 adding days moves forward by whole UTC days")
func addingDaysMovesForward() {
    #expect(DayCalendar.adding(days: 6, to: day0) == day0.addingTimeInterval(6 * 86_400))
}
```

- [ ] **Step 2: Run the tests and confirm they fail for the right reason**

Run: `swift test --package-path Packages/Domain --filter DayCalendar`
Expected: compile failure `cannot find 'DayCalendar' in scope`. That is the "behavior missing" red for a type that does not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `Packages/Domain/Sources/Domain/DayCalendar.swift`:

```swift
import Foundation

/// The one calendar Domain does day arithmetic on: a fixed Gregorian/UTC
/// calendar, never `Calendar.current`. Results must not depend on the device's
/// locale or time zone, and `date(byAdding: .day, ...)` stays correct across DST.
///
/// Internal on purpose — an implementation detail shared by `Scheduler` and
/// `SessionBuilder` so the two can never drift onto different calendars.
enum DayCalendar {
    static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func startOfDay(_ date: Date) -> Date {
        gregorianUTC.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        gregorianUTC.isDate(lhs, inSameDayAs: rhs)
    }

    /// Falls back to `date` if the calendar cannot produce the result — day
    /// arithmetic on a Gregorian calendar never actually fails, and the
    /// alternative is a force-unwrap Domain does not allow.
    static func adding(days: Int, to date: Date) -> Date {
        gregorianUTC.date(byAdding: .day, value: days, to: date) ?? date
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/Domain --filter DayCalendar`
Expected: 4 tests, PASS.

- [ ] **Step 5: Move `Scheduler` onto `DayCalendar`**

In `Packages/Domain/Sources/Domain/Scheduler.swift`, delete the private calendar (the `/// Day arithmetic runs on a fixed Gregorian/UTC calendar...` comment block and the `private static let calendar` property, lines 24–31) and replace the `nextReviewDate` assignment:

```swift
        // Derived from the *clamped* interval — the two must never disagree.
        next.nextReviewDate = DayCalendar.adding(days: next.intervalDays, to: today)
```

- [ ] **Step 6: Run the whole Domain suite — the existing scheduler tests are the regression net for this refactor**

Run: `swift test --package-path Packages/Domain`
Expected: every test passes, including the pre-existing `FR-8` scheduler tests. If any scheduler test fails, the extraction changed behavior — revert and redo it.

- [ ] **Step 7: Add the two ports**

Append to `Packages/Domain/Sources/Domain/Ports.swift`:

```swift
/// Injectable "today" so ViewModels never read the wall clock (NFR: deterministic
/// tests). Day-granular by design — the scheduler only ever needs the date.
///
/// Named `DayClock`, not `Clock` as `architecture.md` §3 sketched it: Swift's
/// concurrency library already exports a `Clock` protocol, and the collision
/// would force `Domain.Clock` at every app-target use site.
public protocol DayClock: Sendable {
    var today: Date { get }
}

/// Is a language purchased/unlocked (FR-14)? Synchronous — it is a local lookup,
/// and Phase 11's StoreKit adapter caches its entitlement set behind this same
/// signature. The Phase 8 stub lives in the app target and always returns false;
/// the free launch language is `PackDescriptor.unlockedByDefault`, not an
/// entitlement.
public protocol EntitlementStore: Sendable {
    func isUnlocked(_ languageCode: LanguageCode) -> Bool
}
```

- [ ] **Step 8: Verify the package still builds clean and lint passes**

Run: `swift test --package-path Packages/Domain && swiftlint lint --strict`
Expected: all tests pass, no lint output.

- [ ] **Step 9: Commit**

```bash
git add Packages/Domain
git commit -m "refactor(domain): extract DayCalendar, add DayClock and EntitlementStore ports"
```

---

### Task 2: Domain — `SessionBuilder`

**Files:**
- Create: `Packages/Domain/Sources/Domain/SessionBuilder.swift`
- Create: `Packages/Domain/Tests/DomainTests/SessionBuilderTests.swift`

**Interfaces:**
- Consumes: `DayCalendar` (Task 1), `LanguagePack`, `WordEntry`, `ReviewState`, `WordID`.
- Produces: `public struct SessionBuilder: Sendable` with `public static let defaultNewWordCap = 10`, `public init()`, and
  `public func build(pack: LanguagePack, states: [ReviewState], today: Date, newWordCap: Int = SessionBuilder.defaultNewWordCap) -> [WordEntry]`.

- [ ] **Step 1: Write the first failing test plus the fixture helpers**

Create `Packages/Domain/Tests/DomainTests/SessionBuilderTests.swift`:

```swift
import Foundation
import Testing

@testable import Domain

private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

private func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

private func entry(_ lemma: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID("fr:\(lemma):NOUN"), lemma: lemma, display: lemma, pos: .noun,
        rank: rank, register: .neutral, isFunctionWord: false, gloss: "gloss of \(lemma)",
        example: "Une phrase avec \(lemma).", aliases: [])
}

private func frPack(_ entries: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "French", baseLanguage: "en", wordCount: entries.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: entries)
}

@Test("FR-3 a fresh learner's session is new words in rank order")
func freshSessionIsNewWordsInRankOrder() {
    let pack = frPack([entry("chien", rank: 2), entry("chat", rank: 1)])

    let queue = SessionBuilder().build(pack: pack, states: [], today: day0)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: `cannot find 'SessionBuilder' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Packages/Domain/Sources/Domain/SessionBuilder.swift`:

```swift
import Foundation

/// Assembles one study session: every due review, plus new words up to whatever
/// is left of the daily cap (FR-3, FR-4). Pure — the same inputs always produce
/// the same queue, and `today` is injected rather than read.
public struct SessionBuilder: Sendable {
    /// FR-4's `N`. A settings screen to change it is deferred; callers pass their
    /// own value.
    public static let defaultNewWordCap = 10

    public init() {}

    public func build(
        pack: LanguagePack,
        states: [ReviewState],
        today: Date,
        newWordCap: Int = SessionBuilder.defaultNewWordCap
    ) -> [WordEntry] {
        pack.words.sorted { $0.rank < $1.rank }
    }
}
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: PASS.

- [ ] **Step 5: Write the failing cap test**

Append to `SessionBuilderTests.swift`:

```swift
@Test("FR-4 new words stop at the daily cap")
func newWordsStopAtTheCap() {
    let pack = frPack([
        entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3),
    ])

    let queue = SessionBuilder().build(pack: pack, states: [], today: day0, newWordCap: 2)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: FAIL — the queue is `["chat", "chien", "maison"]`; the cap is ignored.

- [ ] **Step 7: Apply the cap**

Replace the body of `build` with:

```swift
        let newWords = pack.words
            .sorted { $0.rank < $1.rank }
            .prefix(max(0, newWordCap))
        return Array(newWords)
```

- [ ] **Step 8: Run and confirm both tests pass**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: 2 tests PASS.

- [ ] **Step 9: Write the failing "due reviews come first, uncapped" tests**

Append:

```swift
@Test("FR-3 due reviews come before new words")
func dueReviewsComeFirst() {
    let pack = frPack([
        entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3),
    ])
    let due = ReviewState(
        wordID: WordID("fr:maison:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day0, firstReviewedDate: day(-1))

    let queue = SessionBuilder().build(
        pack: pack, states: [due], today: day0, newWordCap: 1)

    #expect(queue.map(\.lemma) == ["maison", "chat"])
}

@Test("FR-4 due reviews are never capped")
func dueReviewsAreNeverCapped() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let states = [
        ReviewState(
            wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
        ReviewState(
            wordID: WordID("fr:chien:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
    ]

    let queue = SessionBuilder().build(
        pack: pack, states: states, today: day0, newWordCap: 0)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}
```

- [ ] **Step 10: Run and confirm they fail**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: both FAIL — reviewed words are still being treated as new, and a cap of 0 empties the queue.

- [ ] **Step 11: Split the queue into due reviews and new words**

Replace the body of `build` with:

```swift
        let statesByWord = Dictionary(
            states.map { ($0.wordID, $0) }, uniquingKeysWith: { _, latest in latest })
        let today = DayCalendar.startOfDay(today)

        // Due (FR-3): has a state, and its next review lands on or before today.
        // Never capped — reviews are the debt, new words are the extra on top.
        let due =
            pack.words
            .compactMap { word -> (entry: WordEntry, due: Date)? in
                guard let state = statesByWord[word.id],
                    DayCalendar.startOfDay(state.nextReviewDate) <= today
                else { return nil }
                return (word, state.nextReviewDate)
            }
            .sorted {
                $0.due == $1.due ? $0.entry.rank < $1.entry.rank : $0.due < $1.due
            }
            .map(\.entry)

        // New (FR-4): never seen, taken in frequency order, capped.
        let newWords =
            pack.words
            .filter { statesByWord[$0.id] == nil }
            .sorted { $0.rank < $1.rank }
            .prefix(max(0, newWordCap))

        return due + newWords
```

- [ ] **Step 12: Run and confirm all four tests pass**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: 4 tests PASS.

- [ ] **Step 13: Write the failing "already introduced today" test**

Append:

```swift
@Test("FR-4 words already introduced today count against the cap")
func wordsIntroducedTodayCountAgainstTheCap() {
    let pack = frPack([
        entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3),
    ])
    // Introduced earlier today and scheduled for tomorrow: not due, but it spent
    // one of today's new-word slots.
    let introducedToday = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day(1), firstReviewedDate: day0.addingTimeInterval(9 * 3600))

    let queue = SessionBuilder().build(
        pack: pack, states: [introducedToday], today: day0.addingTimeInterval(20 * 3600),
        newWordCap: 2)

    #expect(queue.map(\.lemma) == ["chien"])
}
```

- [ ] **Step 14: Run and confirm it fails**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: FAIL — the queue is `["chien", "maison"]`; today's already-spent slot is not being subtracted.

- [ ] **Step 15: Subtract today's introductions from the cap**

In `build`, insert before the `newWords` computation and use it in the `prefix`:

```swift
        // FR-4 counts *introductions per calendar day*, not per session, so a
        // second session on the same day cannot re-spend the cap. Scoped to this
        // pack's words, so a word introduced today in another language cannot
        // spend this language's cap.
        let introducedToday = pack.words
            .compactMap { statesByWord[$0.id] }
            .filter { state in
                guard let first = state.firstReviewedDate else { return false }
                return DayCalendar.isSameDay(first, today)
            }
            .count
```

```swift
            .prefix(max(0, newWordCap - introducedToday))
```

- [ ] **Step 16: Run and confirm all five pass**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: 5 tests PASS.

- [ ] **Step 17: Write the remaining edge-case tests**

Append:

```swift
@Test("FR-3 due reviews are ordered most-overdue first")
func dueReviewsAreOrderedMostOverdueFirst() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let states = [
        ReviewState(
            wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
        ReviewState(
            wordID: WordID("fr:chien:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day(-3), firstReviewedDate: day(-4)),
    ]

    let queue = SessionBuilder().build(
        pack: pack, states: states, today: day0, newWordCap: 0)

    #expect(queue.map(\.lemma) == ["chien", "chat"])
}

@Test("FR-3 due reviews sharing a date fall back to rank order")
func dueReviewsTieBreakOnRank() {
    let pack = frPack([entry("chien", rank: 2), entry("chat", rank: 1)])
    let states = [
        ReviewState(
            wordID: WordID("fr:chien:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
        ReviewState(
            wordID: WordID("fr:chat:NOUN"), intervalDays: 1, repetitions: 1,
            nextReviewDate: day0, firstReviewedDate: day(-1)),
    ]

    let queue = SessionBuilder().build(
        pack: pack, states: states, today: day0, newWordCap: 0)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-3 a word scheduled for tomorrow is not in today's session")
func wordDueTomorrowIsNotInTodaysSession() {
    let pack = frPack([entry("chat", rank: 1)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(1), firstReviewedDate: day(-6))

    let queue = SessionBuilder().build(
        pack: pack, states: [notYetDue], today: day0, newWordCap: 10)

    #expect(queue.isEmpty)
}

@Test("FR-12 nothing due and no new words left yields an empty queue")
func nothingDueAndNoNewWordsYieldsEmptyQueue() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(3), firstReviewedDate: day(-6))

    let queue = SessionBuilder().build(
        pack: pack, states: [notYetDue], today: day0, newWordCap: 0)

    #expect(queue.isEmpty)
}

@Test("FR-4 a word introduced today in another language does not spend this pack's cap")
func otherLanguageIntroductionDoesNotSpendTheCap() {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let hindiIntroducedToday = ReviewState(
        wordID: WordID("hi:बिल्ली:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day(1), firstReviewedDate: day0)

    let queue = SessionBuilder().build(
        pack: pack, states: [hindiIntroducedToday], today: day0, newWordCap: 2)

    #expect(queue.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-3 the session ignores review state belonging to another language")
func otherLanguageStateIsIgnored() {
    let pack = frPack([entry("chat", rank: 1)])
    let hindiState = ReviewState(
        wordID: WordID("hi:बिल्ली:NOUN"), intervalDays: 1, repetitions: 1,
        nextReviewDate: day(-1), firstReviewedDate: day(-2))

    let queue = SessionBuilder().build(
        pack: pack, states: [hindiState], today: day0, newWordCap: 10)

    #expect(queue.map(\.lemma) == ["chat"])
}
```

- [ ] **Step 18: Run and confirm which of these fail**

Run: `swift test --package-path Packages/Domain --filter SessionBuilder`
Expected: `otherLanguageStateIsIgnored` may already pass (states from another language never match a pack `WordID`) — that is fine, it is a guard against a future filtering bug. Any *other* failure is a real gap: fix `build` minimally until all 10 pass. Do not add filtering logic that no failing test demanded.

- [ ] **Step 19: Verify coverage and lint**

Run:
```sh
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swiftlint lint --strict
```
Expected: coverage ≥ 90%, no lint output.

- [ ] **Step 20: Commit**

```bash
git add Packages/Domain
git commit -m "feat(domain): add SessionBuilder for session assembly (FR-3, FR-4)"
```

---

### Task 3: Presentation — speech port, test fakes, and `StudyViewModel` session loading

**Files:**
- Create: `FullDeck/FullDeck/Services/SpeechService.swift`
- Create: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift`
- Create: `FullDeck/FullDeckTests/Fakes.swift`
- Create: `FullDeck/FullDeckTests/StudyViewModelTests.swift`

**Interfaces:**
- Consumes: `PackStore`, `ReviewStore`, `Scheduler`, `SessionBuilder`, `DayClock`, `LanguagePack`, `WordEntry`, `InMemoryPackStore`, `InMemoryReviewStore` (all from `Domain`).
- Produces:
  - `@MainActor protocol SpeechService { func speak(_ text: String, language: LanguageCode) throws; func stop() }` and `enum SpeechError: Error, Equatable { case voiceUnavailable(LanguageCode) }`.
  - `@MainActor @Observable final class StudyViewModel` with `enum State: Equatable { case loading, card(Card), caughtUp(nextDue: Date?), failed(String) }`, `struct Card: Equatable { let entry: WordEntry; var isRevealed: Bool; let index: Int; let total: Int }`, `private(set) var state: State`, `private(set) var audioUnavailable: Bool`, `func start() async`, and (Tasks 4–5) `func reveal()`, `func grade(_ grade: Grade) async`, `func speakWord()`, `func speakSentence()`.
  - Test helpers in `Fakes.swift`: `day0`, `day(_:)`, `entry(_:rank:)`, `frPack(_:)`, `FixedDayClock`, `FakeSpeechService`, `StubEntitlementStore`, `makeStudyViewModel(...)`.

- [ ] **Step 1: Write the speech port (needed to construct the ViewModel at all)**

Create `FullDeck/FullDeck/Services/SpeechService.swift`:

```swift
import Domain

/// Spoken audio for a card (FR-7, spec D3). Presentation owns this port — Domain
/// never learns that audio exists. Callers cannot tell on-device TTS from a
/// future bundled recording; only the adapter changes.
///
/// `@MainActor` because the concrete adapter wraps `AVSpeechSynthesizer`, a
/// non-`Sendable` class. ViewModels are already main-actor, so calls are free.
@MainActor
protocol SpeechService {
    /// Throws `SpeechError.voiceUnavailable` when the device has no voice for
    /// this language — the caller degrades, it never crashes.
    func speak(_ text: String, language: LanguageCode) throws
    func stop()
}

enum SpeechError: Error, Equatable {
    case voiceUnavailable(LanguageCode)
}
```

- [ ] **Step 2: Write the shared test fakes**

Create `FullDeck/FullDeckTests/Fakes.swift`:

```swift
import Domain
import Foundation

@testable import FullDeck

// A fixed instant on a UTC day boundary. Tests never read the wall clock
// (scripts/determinism-check.sh enforces this).
let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

func entry(_ lemma: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID("fr:\(lemma):NOUN"), lemma: lemma, display: lemma, pos: .noun,
        rank: rank, register: .neutral, isFunctionWord: false, gloss: "gloss of \(lemma)",
        example: "Une phrase avec \(lemma).", aliases: [])
}

func frPack(_ entries: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "French", baseLanguage: "en", wordCount: entries.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: entries)
}

func frDescriptor(unlockedByDefault: Bool = true) -> PackDescriptor {
    PackDescriptor(
        languageCode: LanguageCode("fr"), displayName: "French", filename: "fr.pack.json",
        unlockedByDefault: unlockedByDefault)
}

struct FixedDayClock: DayClock {
    let today: Date
}

struct StubEntitlementStore: EntitlementStore {
    var unlocked: Set<String> = []

    func isUnlocked(_ languageCode: LanguageCode) -> Bool {
        unlocked.contains(languageCode.rawValue)
    }
}

@MainActor
final class FakeSpeechService: SpeechService {
    private(set) var spoken: [(text: String, language: LanguageCode)] = []
    private(set) var stopCount = 0
    var errorToThrow: SpeechError?

    func speak(_ text: String, language: LanguageCode) throws {
        if let errorToThrow { throw errorToThrow }
        spoken.append((text, language))
    }

    func stop() {
        stopCount += 1
    }
}

/// Builds a `StudyViewModel` over in-memory doubles. Every test that needs a
/// different pack, state set, or "today" passes it here rather than reaching
/// into the ViewModel.
@MainActor
func makeStudyViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    today: Date = day0,
    newWordCap: Int = SessionBuilder.defaultNewWordCap,
    speech: FakeSpeechService = FakeSpeechService(),
    reviewStore: InMemoryReviewStore = InMemoryReviewStore()
) -> StudyViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:])
    return StudyViewModel(
        languageCode: code, packStore: packStore, reviewStore: reviewStore,
        scheduler: Scheduler(), sessionBuilder: SessionBuilder(), speech: speech,
        clock: FixedDayClock(today: today), newWordCap: newWordCap)
}
```

> To give a test pre-existing review state, pass a seeded store:
> `makeStudyViewModel(reviewStore: InMemoryReviewStore(seed: [...]))`.

- [ ] **Step 3: Write the first failing ViewModel test**

Create `FullDeck/FullDeckTests/StudyViewModelTests.swift`:

```swift
import Domain
import Testing

@testable import FullDeck

@Test("FR-3 starting a session presents the first card")
@MainActor
func startPresentsTheFirstCard() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeStudyViewModel(pack: pack)

    await viewModel.start()

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[0], isRevealed: false, index: 1, total: 2)))
}
```

- [ ] **Step 4: Run it and confirm it fails for the right reason**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests`
Expected: compile failure `cannot find 'StudyViewModel' in scope`.

- [ ] **Step 5: Write the minimal implementation**

Create `FullDeck/FullDeck/ViewModels/StudyViewModel.swift`:

```swift
import Domain
import Foundation
import Observation

/// Drives one study session: presents a card at a time, enforces active recall
/// (nothing is graded before it is revealed), and feeds the grade back to the
/// scheduler (FR-3, FR-5, FR-6, FR-7, FR-8, FR-12).
///
/// `@Observable` (iOS 17+) makes SwiftUI re-render exactly the views that read a
/// property that changed. `@MainActor` keeps every state mutation on the main
/// thread; the `await`s below hop off for I/O and resume back on it.
@MainActor
@Observable
final class StudyViewModel {
    enum State: Equatable {
        case loading
        case card(Card)
        /// Nothing due and the daily cap is spent (FR-12). `nextDue` is the
        /// earliest future review, `nil` when there is none.
        case caughtUp(nextDue: Date?)
        case failed(String)
    }

    struct Card: Equatable {
        let entry: WordEntry
        var isRevealed: Bool
        /// 1-based position in this session, for a plain "3 of 12" readout.
        let index: Int
        let total: Int
    }

    private(set) var state: State = .loading
    private(set) var audioUnavailable = false

    private let languageCode: LanguageCode
    private let packStore: PackStore
    private let reviewStore: ReviewStore
    private let scheduler: Scheduler
    private let sessionBuilder: SessionBuilder
    private let speech: SpeechService
    private let clock: DayClock
    private let newWordCap: Int

    private var queue: [WordEntry] = []
    private var position = 0

    init(
        languageCode: LanguageCode,
        packStore: PackStore,
        reviewStore: ReviewStore,
        scheduler: Scheduler,
        sessionBuilder: SessionBuilder,
        speech: SpeechService,
        clock: DayClock,
        newWordCap: Int = SessionBuilder.defaultNewWordCap
    ) {
        self.languageCode = languageCode
        self.packStore = packStore
        self.reviewStore = reviewStore
        self.scheduler = scheduler
        self.sessionBuilder = sessionBuilder
        self.speech = speech
        self.clock = clock
        self.newWordCap = newWordCap
    }

    func start() async {
        state = .loading
        do {
            let pack = try await packStore.loadPack(languageCode)
            let states = try await reviewStore.allStates(languageCode)
            queue = sessionBuilder.build(
                pack: pack, states: states, today: clock.today, newWordCap: newWordCap)
            position = 0
            showCurrentCard()
        } catch {
            // NFR-10: bad or missing data is a state, never a crash. Phase 10
            // owns the user-facing copy.
            state = .failed("Couldn't load this language.")
        }
    }

    private func showCurrentCard() {
        guard position < queue.count else {
            state = .caughtUp(nextDue: nil)
            return
        }
        state = .card(
            Card(
                entry: queue[position], isRevealed: false, index: position + 1,
                total: queue.count))
    }
}
```

- [ ] **Step 6: Run it and confirm it passes**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests`
Expected: PASS.

- [ ] **Step 7: Write the failing caught-up and error tests**

Append to `StudyViewModelTests.swift`:

```swift
@Test("FR-5 a freshly presented card hides its answer")
@MainActor
func freshCardHidesTheAnswer() async {
    let viewModel = makeStudyViewModel()

    await viewModel.start()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(!card.isRevealed)
}

@Test("FR-6 every card carries exactly one non-empty example sentence")
@MainActor
func cardCarriesOneExampleSentence() async {
    let viewModel = makeStudyViewModel()

    await viewModel.start()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(!card.entry.example.isEmpty)
}

@Test("FR-12 an empty session shows the caught-up state with the next due date")
@MainActor
func emptySessionShowsCaughtUp() async {
    let pack = frPack([entry("chat", rank: 1)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(3), firstReviewedDate: day(-6))
    let viewModel = makeStudyViewModel(
        pack: pack, newWordCap: 0, reviewStore: InMemoryReviewStore(seed: [notYetDue]))

    await viewModel.start()

    #expect(viewModel.state == .caughtUp(nextDue: day(3)))
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedState() async {
    let viewModel = makeStudyViewModel(pack: nil)

    await viewModel.start()

    guard case .failed = viewModel.state else {
        Issue.record("expected a failed state, got \(viewModel.state)")
        return
    }
}
```

- [ ] **Step 8: Run and confirm the caught-up test fails**

Run the same `xcodebuild test` command.
Expected: `emptySessionShowsCaughtUp` FAILs — `caughtUp(nextDue: nil)` instead of `caughtUp(nextDue: day(3))`. The other three should pass already.

- [ ] **Step 9: Compute the next due date**

In `StudyViewModel`, add a stored property and set it in `start()`:

```swift
    private var states: [ReviewState] = []
```

In `start()`, after loading, replace `let states = ...` with `states = try await reviewStore.allStates(languageCode)`, and replace `showCurrentCard()`'s empty branch:

```swift
    private func showCurrentCard() {
        guard position < queue.count else {
            state = .caughtUp(nextDue: nextDueDate())
            return
        }
        ...
    }

    /// The earliest review still in the future — what the caught-up screen tells
    /// the learner to come back for (FR-12).
    private func nextDueDate() -> Date? {
        states.map(\.nextReviewDate).filter { $0 > clock.today }.min()
    }
```

- [ ] **Step 10: Run and confirm all five pass**

Run the same `xcodebuild test` command.
Expected: 5 tests PASS (plus the pre-existing Phase-4 scaffold test).

- [ ] **Step 11: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): add SpeechService port and StudyViewModel session loading"
```

---

### Task 4: `StudyViewModel` — reveal, grade, persist

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift`
- Modify: `FullDeck/FullDeckTests/StudyViewModelTests.swift`

**Interfaces:**
- Consumes: everything from Task 3, plus `Grade` and `Scheduler.schedule(_:grade:today:)` from `Domain`.
- Produces: `func reveal()` and `func grade(_ grade: Grade) async` on `StudyViewModel`.

- [ ] **Step 1: Write the failing reveal tests**

Append to `StudyViewModelTests.swift`:

```swift
@Test("FR-5 reveal exposes the answer side of the card")
@MainActor
func revealExposesTheAnswer() async {
    let viewModel = makeStudyViewModel()
    await viewModel.start()

    viewModel.reveal()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(card.isRevealed)
}

@Test("FR-5 grading before reveal does nothing")
@MainActor
func gradingBeforeRevealDoesNothing() async {
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()

    await viewModel.grade(.good)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved == nil)
    guard case .card(let card) = viewModel.state else {
        Issue.record("expected to still be on the first card, got \(viewModel.state)")
        return
    }
    #expect(card.index == 1)
}
```

- [ ] **Step 2: Run and confirm they fail**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests`
Expected: compile failure — `value of type 'StudyViewModel' has no member 'reveal'`.

- [ ] **Step 3: Implement reveal and a grade that refuses unrevealed cards**

Add to `StudyViewModel`:

```swift
    /// Active recall (FR-5): the learner commits to an attempt, *then* sees the
    /// answer. Nothing can be graded before this.
    func reveal() {
        guard case .card(var card) = state, !card.isRevealed else { return }
        card.isRevealed = true
        state = .card(card)
    }

    func grade(_ grade: Grade) async {
        guard case .card(let card) = state, card.isRevealed else { return }
    }
```

- [ ] **Step 4: Run and confirm both pass**

Run the same command.
Expected: PASS.

- [ ] **Step 5: Write the failing scheduling/persistence tests**

Append:

```swift
@Test("FR-8 grading persists the scheduler's updated state")
@MainActor
func gradingPersistsScheduledState() async {
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.good)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved?.repetitions == 1)
    #expect(saved?.intervalDays == 1)
    #expect(saved?.nextReviewDate == day(1))
}

@Test("FR-4 the first grade stamps firstReviewedDate so the daily cap can count it")
@MainActor
func firstGradeStampsFirstReviewedDate() async {
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.good)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved?.firstReviewedDate == day0)
}

@Test("FR-3 grading advances to the next card")
@MainActor
func gradingAdvancesToTheNextCard() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeStudyViewModel(pack: pack)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.good)

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[1], isRevealed: false, index: 2, total: 2)))
}

@Test("FR-12 grading the last card ends the session in the caught-up state")
@MainActor
func gradingLastCardEndsTheSession() async {
    let viewModel = makeStudyViewModel(pack: frPack([entry("chat", rank: 1)]))
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.good)

    #expect(viewModel.state == .caughtUp(nextDue: day(1)))
}
```

- [ ] **Step 6: Run and confirm they fail**

Run the same command.
Expected: all four FAIL — nothing is scheduled, saved, or advanced yet.

- [ ] **Step 7: Implement grading**

Replace `grade(_:)` with:

```swift
    /// Reveal → self-grade → schedule → persist → next card (FR-5, FR-8).
    func grade(_ grade: Grade) async {
        guard case .card(let card) = state, card.isRevealed else { return }
        let today = clock.today
        do {
            let current =
                try await reviewStore.reviewState(for: card.entry.id)
                ?? ReviewState(wordID: card.entry.id)
            var next = scheduler.schedule(current, grade: grade, today: today)
            // Stamping the first review here is what makes FR-4's per-day cap
            // countable. `learnedDate` stays Phase 9's job.
            if next.firstReviewedDate == nil {
                next.firstReviewedDate = today
            }
            try await reviewStore.save(next)
            states.removeAll { $0.wordID == next.wordID }
            states.append(next)
        } catch {
            state = .failed("Couldn't save your progress.")
            return
        }
        position += 1
        showCurrentCard()
    }
```

- [ ] **Step 8: Run and confirm every study test passes**

Run the same command.
Expected: all 9 `StudyViewModel` tests PASS.

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): grade a revealed card through the scheduler and persist it (FR-5, FR-8)"
```

---

### Task 5: `StudyViewModel` — speech (FR-7)

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift`
- Modify: `FullDeck/FullDeckTests/StudyViewModelTests.swift`

**Interfaces:**
- Consumes: `SpeechService`, `SpeechError` (Task 3).
- Produces: `func speakWord()`, `func speakSentence()` on `StudyViewModel`; `audioUnavailable` flips to `true` on a `voiceUnavailable` throw.

- [ ] **Step 1: Write the failing speech tests**

Append to `StudyViewModelTests.swift`:

```swift
@Test("FR-7 speaking the word sends it to the speech port with the pack's language")
@MainActor
func speakWordSendsTheWord() async {
    let speech = FakeSpeechService()
    let viewModel = makeStudyViewModel(speech: speech)
    await viewModel.start()

    viewModel.speakWord()

    #expect(speech.spoken.count == 1)
    #expect(speech.spoken.first?.text == "chat")
    #expect(speech.spoken.first?.language == LanguageCode("fr"))
}

@Test("FR-7 speaking the sentence sends the card's example sentence")
@MainActor
func speakSentenceSendsTheExample() async {
    let speech = FakeSpeechService()
    let viewModel = makeStudyViewModel(speech: speech)
    await viewModel.start()

    viewModel.speakSentence()

    #expect(speech.spoken.first?.text == "Une phrase avec chat.")
}

@Test("FR-7 an unavailable voice flags audio unavailable and leaves the session usable")
@MainActor
func unavailableVoiceDegradesGracefully() async {
    let speech = FakeSpeechService()
    speech.errorToThrow = .voiceUnavailable(LanguageCode("fr"))
    let viewModel = makeStudyViewModel(speech: speech)
    await viewModel.start()

    viewModel.speakWord()

    #expect(viewModel.audioUnavailable)
    guard case .card = viewModel.state else {
        Issue.record("the session must stay usable, got \(viewModel.state)")
        return
    }
}
```

- [ ] **Step 2: Run and confirm they fail**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests`
Expected: compile failure — no member `speakWord`.

- [ ] **Step 3: Implement speech**

Add to `StudyViewModel`:

```swift
    /// FR-7: playback is always learner-initiated. Nothing auto-plays.
    func speakWord() {
        guard case .card(let card) = state else { return }
        speak(card.entry.display)
    }

    func speakSentence() {
        guard case .card(let card) = state else { return }
        speak(card.entry.example)
    }

    private func speak(_ text: String) {
        do {
            try speech.speak(text, language: languageCode)
        } catch {
            // No voice installed for this language: the card still works, the
            // learner just loses audio (FR-7).
            audioUnavailable = true
        }
    }
```

- [ ] **Step 4: Run and confirm every study test passes**

Run the same command.
Expected: all 12 `StudyViewModel` tests PASS.

- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): speak the word and sentence through the speech port (FR-7)"
```

---

### Task 6: `ProgressViewModel`

**Files:**
- Create: `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift`
- Create: `FullDeck/FullDeckTests/ProgressViewModelTests.swift`

**Interfaces:**
- Consumes: `PackStore`, `ReviewStore`, `ProgressSummary`, `LanguagePack.wordCount`, and `Fakes.swift` helpers.
- Produces: `@MainActor @Observable final class ProgressViewModel` with `enum State: Equatable { case loading, ready(learned: Int, total: Int), failed(String) }`, `private(set) var state: State`, `init(languageCode:packStore:reviewStore:)`, `func load() async`.

- [ ] **Step 1: Write the failing tests**

Create `FullDeck/FullDeckTests/ProgressViewModelTests.swift`:

```swift
import Domain
import Testing

@testable import FullDeck

@MainActor
private func makeProgressViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    seed: [ReviewState] = []
) -> ProgressViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:])
    return ProgressViewModel(
        languageCode: code, packStore: packStore,
        reviewStore: InMemoryReviewStore(seed: seed))
}

@Test("FR-10 progress reports words learned out of the pack's word count")
@MainActor
func progressReportsLearnedOutOfTotal() async {
    let learned = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 21, repetitions: 4,
        nextReviewDate: day(21), firstReviewedDate: day(-30), learnedDate: day(-2))
    let viewModel = makeProgressViewModel(seed: [learned])

    await viewModel.load()

    #expect(viewModel.state == .ready(learned: 1, total: 2))
}

@Test("FR-10 an untouched language reads zero learned")
@MainActor
func untouchedLanguageReadsZero() async {
    let viewModel = makeProgressViewModel()

    await viewModel.load()

    #expect(viewModel.state == .ready(learned: 0, total: 2))
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedProgressState() async {
    let viewModel = makeProgressViewModel(pack: nil)

    await viewModel.load()

    guard case .failed = viewModel.state else {
        Issue.record("expected a failed state, got \(viewModel.state)")
        return
    }
}
```

- [ ] **Step 2: Run and confirm they fail**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests`
Expected: `cannot find 'ProgressViewModel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift`:

```swift
import Domain
import Observation

/// Words learned out of the language's total, and nothing else (FR-10). No
/// streaks, no time-spent, no review counts — those are engagement theater, and
/// the product deliberately does not have them.
///
/// Reads `0` until Phase 9 defines the learned threshold `L` and starts stamping
/// `learnedDate`.
@MainActor
@Observable
final class ProgressViewModel {
    enum State: Equatable {
        case loading
        case ready(learned: Int, total: Int)
        case failed(String)
    }

    private(set) var state: State = .loading

    private let languageCode: LanguageCode
    private let packStore: PackStore
    private let reviewStore: ReviewStore

    init(languageCode: LanguageCode, packStore: PackStore, reviewStore: ReviewStore) {
        self.languageCode = languageCode
        self.packStore = packStore
        self.reviewStore = reviewStore
    }

    func load() async {
        state = .loading
        do {
            let pack = try await packStore.loadPack(languageCode)
            let progress = try await reviewStore.progress(languageCode)
            state = .ready(learned: progress.wordsLearned, total: pack.wordCount)
        } catch {
            state = .failed("Couldn't load your progress.")
        }
    }
}
```

- [ ] **Step 4: Run and confirm they pass**

Run the same command.
Expected: 3 progress tests PASS.

- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): add ProgressViewModel reporting words learned (FR-10)"
```

---

### Task 7: `LanguageSelectionViewModel`

**Files:**
- Create: `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift`
- Create: `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift`

**Interfaces:**
- Consumes: `PackStore.availablePacks()`, `EntitlementStore`, `PackDescriptor`, `StubEntitlementStore` (Task 3).
- Produces: `@MainActor @Observable final class LanguageSelectionViewModel` with `struct Option: Equatable, Identifiable { let descriptor: PackDescriptor; let isUnlocked: Bool; var id: String }`, `enum State: Equatable { case loading, ready([Option]), failed(String) }`, `private(set) var state: State`, `private(set) var activeLanguage: LanguageCode?`, `init(packStore:entitlements:)`, `func load() async`, `func select(_ option: Option)`.

- [ ] **Step 1: Write the failing tests**

Create `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift`:

```swift
import Domain
import Testing

@testable import FullDeck

private let hindiDescriptor = PackDescriptor(
    languageCode: LanguageCode("hi"), displayName: "Hindi", filename: "hi.pack.json",
    unlockedByDefault: false)

@MainActor
private func makeSelectionViewModel(
    descriptors: [PackDescriptor] = [frDescriptor(), hindiDescriptor],
    unlocked: Set<String> = []
) -> LanguageSelectionViewModel {
    LanguageSelectionViewModel(
        packStore: InMemoryPackStore(descriptors: descriptors),
        entitlements: StubEntitlementStore(unlocked: unlocked))
}

@Test("FR-1 the selection screen lists every available pack")
@MainActor
func listsEveryAvailablePack() async {
    let viewModel = makeSelectionViewModel()

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }
    #expect(options.map(\.descriptor.displayName) == ["French", "Hindi"])
}

@Test("FR-2 the launch language is unlocked without a purchase")
@MainActor
func launchLanguageIsUnlocked() async {
    let viewModel = makeSelectionViewModel()

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }
    #expect(options[0].isUnlocked)
    #expect(!options[1].isUnlocked)
}

@Test("FR-14 a purchased language shows as unlocked")
@MainActor
func purchasedLanguageIsUnlocked() async {
    let viewModel = makeSelectionViewModel(unlocked: ["hi"])

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }
    #expect(options[1].isUnlocked)
}

@Test("FR-1 selecting an unlocked pack makes it the active language")
@MainActor
func selectingUnlockedPackActivatesIt() async {
    let viewModel = makeSelectionViewModel()
    await viewModel.load()
    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }

    viewModel.select(options[0])

    #expect(viewModel.activeLanguage == LanguageCode("fr"))
}

@Test("FR-1 selecting a locked pack does not make it active")
@MainActor
func selectingLockedPackDoesNothing() async {
    let viewModel = makeSelectionViewModel()
    await viewModel.load()
    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }

    viewModel.select(options[1])

    #expect(viewModel.activeLanguage == nil)
}
```

- [ ] **Step 2: Run and confirm they fail**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests`
Expected: `cannot find 'LanguageSelectionViewModel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift`:

```swift
import Domain
import Observation

/// Lists the bundled packs with their lock state and tracks which language is
/// active (FR-1, FR-2, FR-14). The purchase sheet itself is Phase 11.
@MainActor
@Observable
final class LanguageSelectionViewModel {
    struct Option: Equatable, Identifiable {
        let descriptor: PackDescriptor
        let isUnlocked: Bool

        var id: String { descriptor.languageCode.rawValue }
    }

    enum State: Equatable {
        case loading
        case ready([Option])
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var activeLanguage: LanguageCode?

    private let packStore: PackStore
    private let entitlements: EntitlementStore

    init(packStore: PackStore, entitlements: EntitlementStore) {
        self.packStore = packStore
        self.entitlements = entitlements
    }

    func load() async {
        state = .loading
        do {
            let descriptors = try await packStore.availablePacks()
            state = .ready(
                descriptors.map { descriptor in
                    // The free launch language is a property of the pack manifest
                    // (FR-2); purchases only ever add to it (FR-14).
                    Option(
                        descriptor: descriptor,
                        isUnlocked: descriptor.unlockedByDefault
                            || entitlements.isUnlocked(descriptor.languageCode))
                })
        } catch {
            state = .failed("Couldn't load the available languages.")
        }
    }

    /// FR-1: selecting a locked pack must not start a session.
    func select(_ option: Option) {
        guard option.isUnlocked else { return }
        activeLanguage = option.descriptor.languageCode
    }
}
```

- [ ] **Step 4: Run and confirm they pass**

Run the same command.
Expected: 5 selection tests PASS.

- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): add LanguageSelectionViewModel with lock state (FR-1, FR-14)"
```

> Note: `InMemoryPackStore.availablePacks()` cannot fail, so the `.failed` branch has no unit test here. It is covered for real in Phase 9 against `JSONPackStore`.

---

### Task 8: The three views

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`
- Modify: `FullDeck/FullDeck/Views/LearningProgressView.swift`
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift`

**Interfaces:**
- Consumes: all three ViewModels (Tasks 3–7).
- Produces: `StudyView(viewModel:)`, `LearningProgressView(viewModel:)`, `LanguageSelectionView(viewModel:)` — each taking its ViewModel through `init`.

Views are thin glue: they read state and send intents, and hold no logic. They are not unit-tested — the ViewModels underneath them are.

- [ ] **Step 1: Write `StudyView`**

Replace `FullDeck/FullDeck/Views/StudyView.swift`:

```swift
import Domain
import SwiftUI

/// The daily study session (FR-3, FR-5, FR-6, FR-7, FR-12). Thin: every decision
/// lives in `StudyViewModel`.
struct StudyView: View {
    // `@Bindable` isn't needed — nothing here writes back into the ViewModel;
    // `let` plus @Observable is enough for SwiftUI to track what it reads.
    let viewModel: StudyViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Study")
                .task { await viewModel.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .card(let card):
            cardView(card)
        case .caughtUp(let nextDue):
            caughtUpView(nextDue)
        case .failed(let message):
            ContentUnavailableView(
                "Something went wrong", systemImage: "exclamationmark.triangle",
                description: Text(message))
        }
    }

    private func cardView(_ card: StudyViewModel.Card) -> some View {
        VStack(spacing: 24) {
            Text("\(card.index) of \(card.total)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Card \(card.index) of \(card.total)")

            VStack(spacing: 8) {
                Text(card.entry.display)
                    .font(.largeTitle)
                Text(card.entry.pos.rawValue.lowercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.speakWord()
            } label: {
                Label("Hear the word", systemImage: "speaker.wave.2")
            }
            .accessibilityLabel("Hear the word \(card.entry.display)")

            if card.isRevealed {
                VStack(spacing: 12) {
                    if let gloss = card.entry.gloss {
                        Text(gloss).font(.title3)
                    }
                    Text(card.entry.example)
                        .font(.body)
                        .multilineTextAlignment(.center)
                    Button {
                        viewModel.speakSentence()
                    } label: {
                        Label("Hear the sentence", systemImage: "speaker.wave.2")
                    }
                    .accessibilityLabel("Hear the example sentence")
                }

                gradeButtons
            } else {
                Button("Reveal") { viewModel.reveal() }
                    .buttonStyle(.borderedProminent)
            }

            if viewModel.audioUnavailable {
                Text("Audio unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            ForEach(Grade.allCases, id: \.self) { grade in
                Button(label(for: grade)) {
                    Task { await viewModel.grade(grade) }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Grade this word \(label(for: grade))")
            }
        }
    }

    private func label(for grade: Grade) -> String {
        switch grade {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func caughtUpView(_ nextDue: Date?) -> some View {
        ContentUnavailableView {
            Label("You're caught up", systemImage: "checkmark.circle")
        } description: {
            if let nextDue {
                Text("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted)).")
            } else {
                Text("Nothing is due right now.")
            }
        }
    }
}
```

- [ ] **Step 2: Write `LearningProgressView`**

Replace `FullDeck/FullDeck/Views/LearningProgressView.swift`:

```swift
import SwiftUI

/// Words learned out of the language's total, and nothing else (FR-10).
struct LearningProgressView: View {
    let viewModel: ProgressViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Progress")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .ready(let learned, let total):
            VStack(spacing: 8) {
                Text("\(learned)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                Text("of \(total) words learned")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(learned) of \(total) words learned")
        case .failed(let message):
            ContentUnavailableView(
                "Something went wrong", systemImage: "exclamationmark.triangle",
                description: Text(message))
        }
    }
}
```

- [ ] **Step 3: Write `LanguageSelectionView`**

Replace `FullDeck/FullDeck/Views/LanguageSelectionView.swift`:

```swift
import SwiftUI

/// Lists the bundled packs with lock state (FR-1, FR-2, FR-14).
struct LanguageSelectionView: View {
    let viewModel: LanguageSelectionViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Languages")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .ready(let options):
            List(options) { option in
                Button {
                    viewModel.select(option)
                } label: {
                    HStack {
                        Text(option.descriptor.displayName)
                        Spacer()
                        if !option.isUnlocked {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        } else if viewModel.activeLanguage
                            == option.descriptor.languageCode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!option.isUnlocked)
                .accessibilityLabel(accessibilityLabel(for: option))
            }
        case .failed(let message):
            ContentUnavailableView(
                "Something went wrong", systemImage: "exclamationmark.triangle",
                description: Text(message))
        }
    }

    private func accessibilityLabel(
        for option: LanguageSelectionViewModel.Option
    ) -> String {
        guard option.isUnlocked else {
            return "\(option.descriptor.displayName), locked"
        }
        let isActive = viewModel.activeLanguage == option.descriptor.languageCode
        return isActive
            ? "\(option.descriptor.displayName), active language"
            : option.descriptor.displayName
    }
}
```

- [ ] **Step 4: Delete the now-broken previews**

Each view file ends with a `#Preview { ... }` that constructs the view with no arguments. Those no longer compile. Delete them — Task 9 adds working previews backed by the sample pack.

- [ ] **Step 5: Build and confirm the app target compiles**

Run: `xcodebuild build -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED. `ContentView` will fail to compile because it still constructs the views with no arguments — that is Task 9's job, so it is acceptable for this step to fail *only* on `ContentView.swift`. If it does, note it and move to Task 9 rather than patching `ContentView` here.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): build the study, progress, and language selection views"
```

---

### Task 9: Composition root

**Files:**
- Create: `FullDeck/FullDeck/Services/AVSpeechService.swift`
- Create: `FullDeck/FullDeck/Services/StubEntitlementStore.swift`
- Create: `FullDeck/FullDeck/AppDependencies.swift`
- Create: `FullDeck/FullDeck/SamplePack.swift`
- Modify: `FullDeck/FullDeck/ContentView.swift`
- Modify: `FullDeck/FullDeck/FullDeckApp.swift`
- Modify: `FullDeck/FullDeckTests/FullDeckTests.swift`

**Interfaces:**
- Consumes: every ViewModel and view above, plus `InMemoryPackStore` / `InMemoryReviewStore` from `Domain`.
- Produces: `struct AppDependencies` (holding `packStore`, `reviewStore`, `speech`, `clock`, `entitlements`, `scheduler`, `sessionBuilder`), `AVSpeechService`, `SystemDayClock`, `NoPurchasesEntitlementStore`, `SamplePack.french`, and `ContentView(dependencies:)`.

- [ ] **Step 1: Write the TTS adapter**

Create `FullDeck/FullDeck/Services/AVSpeechService.swift`:

```swift
import AVFoundation
import Domain

/// On-device TTS (spec D3, FR-7). The only place in the app that knows audio is
/// synthesized rather than recorded — swapping in bundled recordings later means
/// writing a second `SpeechService`, not touching a caller.
@MainActor
final class AVSpeechService: SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: LanguageCode) throws {
        guard let voice = AVSpeechSynthesisVoice(language: language.rawValue) else {
            throw SpeechError.voiceUnavailable(language)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
```

- [ ] **Step 2: Write the entitlement stub and the system clock**

Create `FullDeck/FullDeck/Services/StubEntitlementStore.swift`:

```swift
import Domain
import Foundation

/// Phase 8 stub: nothing is purchased yet, so the only unlocked language is the
/// one the manifest marks `unlockedByDefault` (FR-2). Phase 11 replaces this with
/// the StoreKit-backed implementation — no caller changes.
struct NoPurchasesEntitlementStore: EntitlementStore {
    func isUnlocked(_ languageCode: LanguageCode) -> Bool { false }
}

/// The one place the app reads the wall clock. Everything downstream takes
/// `today` as data, which is what keeps the scheduler and session assembly
/// deterministic under test.
struct SystemDayClock: DayClock {
    var today: Date { Date() }
}
```

- [ ] **Step 3: Write the sample pack**

Create `FullDeck/FullDeck/SamplePack.swift`:

```swift
import Domain

// ponytail: an in-code pack so the app runs before Phase 9 bundles the real
// `fr.pack.json` as an app resource. Delete this file — and the in-memory stores
// in `AppDependencies` — the moment JSONPackStore is wired in Phase 9.
enum SamplePack {
    static let french = LanguagePack(
        schemaVersion: 1, packVersion: "0.0.1-sample",
        languageCode: LanguageCode("fr"), languageName: "French", baseLanguage: "en",
        wordCount: 5,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0",
            attribution: "wordfreq contributors"),
        words: [
            word("je", .pron, rank: 1, gloss: "I", example: "Je suis Paul."),
            word("de", .adp, rank: 2, gloss: "of", example: "Je suis de Paris."),
            word("pas", .adv, rank: 3, gloss: "not", example: "Je ne suis pas de Paris."),
            word("chat", .noun, rank: 4, gloss: "cat", example: "Je ne suis pas un chat."),
            word("aussi", .adv, rank: 5, gloss: "also, too", example: "Moi aussi."),
        ])

    private static func word(
        _ lemma: String, _ pos: PartOfSpeech, rank: Int, gloss: String, example: String
    ) -> WordEntry {
        WordEntry(
            id: WordID("fr:\(lemma):\(pos.rawValue)"), lemma: lemma, display: lemma,
            pos: pos, rank: rank, register: .neutral, isFunctionWord: pos.isFunctionWord,
            gloss: gloss, example: example, aliases: [])
    }

    static let descriptor = PackDescriptor(
        languageCode: LanguageCode("fr"), displayName: "French",
        filename: "fr.pack.json", unlockedByDefault: true)

    static let hindiDescriptor = PackDescriptor(
        languageCode: LanguageCode("hi"), displayName: "Hindi",
        filename: "hi.pack.json", unlockedByDefault: false)
}
```

- [ ] **Step 4: Write the dependency container**

Create `FullDeck/FullDeck/AppDependencies.swift`:

```swift
import Domain

/// The composition root's output: every concrete dependency, constructed once and
/// handed down through initializers. No singletons, no DI framework (ADR-002) —
/// this struct *is* the wiring.
@MainActor
struct AppDependencies {
    let packStore: PackStore
    let reviewStore: ReviewStore
    let speech: SpeechService
    let clock: DayClock
    let entitlements: EntitlementStore
    let scheduler = Scheduler()
    let sessionBuilder = SessionBuilder()

    // ponytail: in-memory stores seeded from SamplePack. Phase 9 swaps these two
    // lines for JSONPackStore + SwiftDataReviewStore and deletes SamplePack.
    static func live() -> AppDependencies {
        AppDependencies(
            packStore: InMemoryPackStore(
                descriptors: [SamplePack.descriptor, SamplePack.hindiDescriptor],
                packs: [LanguageCode("fr"): SamplePack.french]),
            reviewStore: InMemoryReviewStore(),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: NoPurchasesEntitlementStore())
    }
}
```

- [ ] **Step 5: Rewrite `ContentView` to own the active language and build ViewModels**

Replace `FullDeck/FullDeck/ContentView.swift`:

```swift
import Domain
import SwiftUI

/// Root shell: one tab per v1 screen. Owns which language is active — persisting
/// that choice across launches is Phase 9.
struct ContentView: View {
    let dependencies: AppDependencies

    @State private var selectionViewModel: LanguageSelectionViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // `@State` on a ViewModel needs an initial value here because the
        // ViewModel depends on injected services — SwiftUI can't default it.
        _selectionViewModel = State(
            initialValue: LanguageSelectionViewModel(
                packStore: dependencies.packStore,
                entitlements: dependencies.entitlements))
    }

    var body: some View {
        TabView {
            LanguageSelectionView(viewModel: selectionViewModel)
                .tabItem { Label("Languages", systemImage: "globe") }
            studyTab
                .tabItem { Label("Study", systemImage: "rectangle.stack") }
            progressTab
                .tabItem { Label("Progress", systemImage: "chart.bar") }
        }
    }

    @ViewBuilder
    private var studyTab: some View {
        if let language = selectionViewModel.activeLanguage {
            StudyView(
                viewModel: StudyViewModel(
                    languageCode: language, packStore: dependencies.packStore,
                    reviewStore: dependencies.reviewStore,
                    scheduler: dependencies.scheduler,
                    sessionBuilder: dependencies.sessionBuilder,
                    speech: dependencies.speech, clock: dependencies.clock)
            )
            .id(language.rawValue)
        } else {
            chooseALanguage
        }
    }

    @ViewBuilder
    private var progressTab: some View {
        if let language = selectionViewModel.activeLanguage {
            LearningProgressView(
                viewModel: ProgressViewModel(
                    languageCode: language, packStore: dependencies.packStore,
                    reviewStore: dependencies.reviewStore)
            )
            .id(language.rawValue)
        } else {
            chooseALanguage
        }
    }

    private var chooseALanguage: some View {
        ContentUnavailableView(
            "Choose a language", systemImage: "globe",
            description: Text("Pick a language on the Languages tab to start."))
    }
}

#Preview {
    ContentView(dependencies: .live())
}
```

- [ ] **Step 6: Wire the app entry point**

Replace the body of `FullDeck/FullDeck/FullDeckApp.swift`:

```swift
import SwiftUI

@main
struct FullDeckApp: App {
    /// The composition root: dependencies are constructed here, once, and
    /// injected downward. Nothing below reaches for a global.
    @State private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
    }
}
```

- [ ] **Step 7: Update the Phase-4 scaffold test**

In `FullDeck/FullDeckTests/FullDeckTests.swift`, replace the test body so it constructs the root with real wiring:

```swift
@Test("Phase-8 the composition root builds the root view")
@MainActor
func contentViewConstructs() {
    _ = ContentView(dependencies: .live())
}
```

- [ ] **Step 8: Run the full app test suite**

Run: `xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: every test passes (13 ViewModel tests + the scaffold test + the existing UI test).

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck
git commit -m "feat(app): wire the composition root with in-memory stores and TTS"
```

---

### Task 10: Full-gate verification and the phase self-review

**Files:**
- Modify: none expected. Fix whatever the gates flag.

- [ ] **Step 1: Run every gate**

```sh
swift test --package-path Packages/Domain
swift test --package-path Packages/Data
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
swiftlint lint --strict
scripts/determinism-check.sh
scripts/trace-requirements.sh
```

Expected: all pass. `trace-requirements.sh` is informational — it should now show FR-1, FR-3, FR-4, FR-5, FR-6, FR-7, FR-10, FR-12, FR-14 covered.

- [ ] **Step 2: Report, do not paper over**

If any gate fails, report the shortest decisive line of output and fix the cause. Do not lower a floor, weaken a test, or add an exclusion to make a gate pass.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "chore(phase-8): fix gate failures from the final verification pass"
```

---

## Self-Review Notes

- **Spec coverage:** §1.1 → Task 1; §1.2 → Task 2; §1.3, §1.4 → Task 1 (protocols) + Task 9 (`SystemDayClock`, `NoPurchasesEntitlementStore`); §2 → Tasks 3, 5, 9; §3.1 → Tasks 3–5; §3.2 → Task 6; §3.3 → Task 7; §4 → Tasks 8, 9; §5 → every task's test steps + Task 10; §6 → the concurrency annotations throughout.
- **Deviation from the spec:** the spec placed `SystemDayClock` and `FixedDayClock` in Domain sources. This plan keeps only the `DayClock` protocol there, puts `SystemDayClock` in the app target (it is the one place that reads the wall clock) and `FixedDayClock` in the test target. Reason: `SystemDayClock` in Domain would be an untestable line under the 90% coverage floor — its body is exactly the `Date()` call the determinism gate forbids tests from making.
- **Not covered by a unit test, deliberately:** `AVSpeechService` (real TTS), the SwiftUI views (thin glue), and `LanguageSelectionViewModel`'s `.failed` branch (the in-memory double cannot fail).
