# Progress: Trend & Hardest Words Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write `StatsService` as `architecture.md:151` has described it since Phase 9, and render its two outputs — FR-17's cumulative learning trend and FR-18's hardest-words list — on the Progress screen.

**Architecture:** Two pure functions in Domain over data `ReviewState` already carries. `ProgressViewModel` loads the pack and `allStates` once and derives all three sections; `ReviewStore.progress(_:)` is deleted as a redundant second path to the same number. Swift Charts renders the trend.

**Tech Stack:** Swift 6 (Domain/Data), Swift Testing (`@Test`), SwiftUI, Swift Charts (system framework, iOS 16+), XCTest for the audit.

**Spec:** [`../specs/2026-08-02-progress-trend-and-hardest-words-design.md`](../specs/2026-08-02-progress-trend-and-hardest-words-design.md)

## Global Constraints

- **Test-first for Domain.** `StatsService` is pure logic: one failing test, run it, confirm it fails *because the behaviour is missing* (a compile error is not a red — fix and re-run), then minimal code. The view is framework glue and is tested alongside.
- **Every test display name starts with its requirement ID:** `@Test("FR-18 a lower ease factor ranks higher")`.
- **Domain coverage floor is 90%, Data is 80%** — both hard CI failures. `StatsService` lands in Domain and must be thoroughly covered; deleting `ReviewStore.progress` moves the Data ratio, so re-check that gate.
- **No test may read `Date()`/`Date.now`, sleep, or use unseeded randomness.** Use the `day(_:)` helpers and pass `today:` explicitly. `scripts/determinism-check.sh` greps test sources.
- **Warnings are errors** everywhere; Domain and Data are `swiftLanguageModes: [.v6]` with strict concurrency.
- **SwiftLint `--strict` is the gate** and must report 0 violations.
- **No new dependencies.** Swift Charts is a system framework.
- **`DayCalendar` is internal to Domain** — usable inside `StatsService`, never exposed in a public signature.
- **New Swift files under `FullDeck/FullDeck/` need no Xcode work** (`PBXFileSystemSynchronizedRootGroup`). Do not hand-edit `project.pbxproj`. Files under `Packages/` are picked up by SwiftPM automatically.
- **Colour rules for anything new on screen:** text needs 4.5:1, graphical marks 3:1, both against `AppBackground` (#FFFBEB). `TextSecondary` measures 7.36:1 and `AccentFill` 4.84:1. **SwiftUI's default greys do not pass** — that is what C-6 caught twice.
- **Five hardest words, read-only.** No tap targets.

### Commands

```sh
swift test --package-path Packages/Domain
swift test --package-path Packages/Data
```

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

Coverage gates:

```sh
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
```

Standalone gates:

```sh
swiftlint lint --strict
scripts/determinism-check.sh
scripts/trace-requirements.sh
```

**If a UI test fails to launch** with `FBSOpenApplicationServiceErrorDomain Code=1`, that is the runner, not your code. Run `xcrun simctl shutdown all` and retry once.

## File Structure

| File | Responsibility |
|---|---|
| `Packages/Domain/Sources/Domain/StatsService.swift` | **Create.** `TrendPoint`, `StatsService`, the `[TrendPoint]` window helper |
| `Packages/Domain/Tests/DomainTests/StatsServiceTests.swift` | **Create.** FR-17 + FR-18 |
| `Packages/Domain/Sources/Domain/Models.swift:8` | **Modify.** `ReviewState.startingEase` |
| `Packages/Domain/Sources/Domain/Ports.swift:40` | **Modify.** Delete `progress(_:)` from `ReviewStore` |
| `Packages/Domain/Sources/Domain/InMemoryReviewStore.swift:31` | **Modify.** Delete `progress(_:)` |
| `Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift:41` | **Modify.** Delete its `progress` test |
| `Packages/Data/Sources/Data/SwiftDataReviewStore.swift:39` | **Modify.** Delete `progress(_:)` |
| `Packages/Data/Tests/DataTests/SwiftDataReviewStoreTests.swift` | **Modify.** Delete its two `progress` tests |
| `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift` | **Modify.** `Snapshot`, `StatsService`, `DayClock`, load from states |
| `FullDeck/FullDeck/Views/LearningProgressView.swift` | **Modify.** Scroll, chart, hardest list |
| `FullDeck/FullDeck/ContentView.swift` | **Modify.** Pass stats + clock |
| `FullDeck/FullDeckTests/ProgressViewModelTests.swift` | **Modify.** Rewrite for `Snapshot`, add FR-17/FR-18 cases |
| `docs/known-issues.md` | **Modify.** Close N-2 and N-3 |
| `docs/next-task.md` | **Modify.** Point at Phase 13 |

---

### Task 1: FR-18 — hardest words

**Files:**
- Create: `Packages/Domain/Sources/Domain/StatsService.swift`
- Create: `Packages/Domain/Tests/DomainTests/StatsServiceTests.swift`
- Modify: `Packages/Domain/Sources/Domain/Models.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ReviewState.startingEase: Double`; `StatsService()` with `hardestWords(in: LanguagePack, states: [ReviewState], limit: Int) -> [WordEntry]`.

- [ ] **Step 1: Add `ReviewState.startingEase`**

In `Packages/Domain/Sources/Domain/Models.swift`, inside `struct ReviewState`, above `public let wordID`:

```swift
    /// The ease every word starts at. `Scheduler` moves it by −0.20 on a lapse
    /// and +0.05 on a pass, so a word *below* this value has been failed more
    /// than it has recovered — which is what FR-18 ranks by.
    public static let startingEase = 2.5
```

Change the initializer's default from `easeFactor: Double = 2.5` to:

```swift
        easeFactor: Double = ReviewState.startingEase,
```

- [ ] **Step 2: Write the first failing test**

`Packages/Domain/Tests/DomainTests/StatsServiceTests.swift`:

```swift
import Foundation
import Testing

@testable import Domain

/// A fixed instant on a UTC day boundary. Domain tests never read the wall
/// clock — `scripts/determinism-check.sh` enforces it.
private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)

private func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

private func word(_ lemma: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID("fr:\(lemma):NOUN"), lemma: lemma, display: lemma, pos: .noun,
        rank: rank, register: .neutral, isFunctionWord: false, gloss: "gloss of \(lemma)",
        example: "Une phrase avec \(lemma).", aliases: [])
}

private func pack(_ entries: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "Français", baseLanguage: "en", wordCount: entries.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: entries)
}

private func state(_ entry: WordEntry, ease: Double) -> ReviewState {
    ReviewState(wordID: entry.id, easeFactor: ease)
}

@Test("FR-18 a lower ease factor ranks higher")
func lowerEaseRanksHigher() {
    let easy = word("chat", rank: 1)
    let hard = word("chien", rank: 2)
    let deck = pack([easy, hard])

    let ranked = StatsService().hardestWords(
        in: deck, states: [state(easy, ease: 2.3), state(hard, ease: 1.8)], limit: 5)

    #expect(ranked.map(\.lemma) == ["chien", "chat"])
}
```

- [ ] **Step 3: Run it and confirm it fails for the right reason**

```sh
swift test --package-path Packages/Domain --filter lowerEaseRanksHigher
```

Expected: build failure — `StatsService` does not exist. That is a compile error, not a red. Write the type in Step 4, then re-run.

- [ ] **Step 4: Write `StatsService.hardestWords`**

`Packages/Domain/Sources/Domain/StatsService.swift`:

```swift
import Foundation

/// Progress computed from a pack plus `ReviewStore.allStates(...)` — the type
/// `architecture.md` §3 has named since Phase 9. Pure, and needs no new port:
/// every input is already on `ReviewState`.
public struct StatsService: Sendable {
    public init() {}

    /// FR-18. Words the learner currently finds hardest, hardest first.
    ///
    /// Ranked by ease alone, because ease *is* the running difficulty estimate.
    /// `Scheduler` adds +0.05 on every pass, so a word that lapsed once and has
    /// since been recalled four times is back at `startingEase` and drops off
    /// this list — correct, not a bug: FR-18 asks what is hard *now*, and a
    /// permanent record of old mistakes is closer to a shame list than to help.
    ///
    /// A state whose word is no longer in the pack is skipped rather than
    /// crashing: packs are versioned and a word can leave one (NFR-10).
    public func hardestWords(
        in pack: LanguagePack, states: [ReviewState], limit: Int
    ) -> [WordEntry] {
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`, which traps on a
        // duplicate. The validator forbids duplicate IDs; bad data must still not
        // crash the app.
        let byID = Dictionary(
            pack.words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return
            states
            .filter { $0.easeFactor < ReviewState.startingEase }
            .compactMap { state in byID[state.wordID].map { (state.easeFactor, $0) } }
            // Ties break on rank so the list cannot reorder between two loads —
            // a flickering list is also an unreproducible test.
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1.rank < rhs.1.rank : lhs.0 < rhs.0
            }
            .prefix(limit)
            .map(\.1)
    }
}
```

- [ ] **Step 5: Run it and confirm it passes**

```sh
swift test --package-path Packages/Domain --filter lowerEaseRanksHigher
```

Expected: PASS.

- [ ] **Step 6: Write the remaining four FR-18 tests**

Append to `StatsServiceTests.swift`:

```swift
@Test("FR-18 a word never failed is not surfaced as hard")
func neverFailedWordIsNotSurfaced() {
    let untouched = word("chat", rank: 1)
    let passing = word("chien", rank: 2)
    let deck = pack([untouched, passing])

    let ranked = StatsService().hardestWords(
        in: deck,
        states: [
            state(untouched, ease: ReviewState.startingEase),
            // Two passes above the start: +0.05 each.
            state(passing, ease: ReviewState.startingEase + 0.10),
        ],
        limit: 5)

    #expect(ranked.isEmpty)
}

@Test("FR-18 equal ease factors order by rank, deterministically")
func equalEaseOrdersByRank() {
    let later = word("chien", rank: 9)
    let earlier = word("chat", rank: 2)
    let deck = pack([later, earlier])

    let ranked = StatsService().hardestWords(
        in: deck, states: [state(later, ease: 2.0), state(earlier, ease: 2.0)], limit: 5)

    #expect(ranked.map(\.lemma) == ["chat", "chien"])
}

@Test("FR-18 a state whose word is no longer in the pack is skipped")
func stateWithoutAPackWordIsSkipped() {
    let present = word("chat", rank: 1)
    let removed = word("disparu", rank: 2)
    let deck = pack([present])

    let ranked = StatsService().hardestWords(
        in: deck, states: [state(removed, ease: 1.4), state(present, ease: 2.1)], limit: 5)

    #expect(ranked.map(\.lemma) == ["chat"])
}

@Test("FR-18 the limit is honoured")
func hardestWordsHonoursTheLimit() {
    let entries = (1...10).map { word("mot\($0)", rank: $0) }
    let deck = pack(entries)
    let states = entries.enumerated().map { index, entry in
        state(entry, ease: 1.4 + Double(index) * 0.05)
    }

    #expect(StatsService().hardestWords(in: deck, states: states, limit: 5).count == 5)
}
```

- [ ] **Step 7: Run the Domain suite**

```sh
swift test --package-path Packages/Domain
```

Expected: PASS. If `neverFailedWordIsNotSurfaced` fails, the filter is using `<=` where it must use `<`.

- [ ] **Step 8: Commit**

```bash
git add Packages/Domain/Sources/Domain/StatsService.swift \
        Packages/Domain/Tests/DomainTests/StatsServiceTests.swift \
        Packages/Domain/Sources/Domain/Models.swift
git commit -m "feat: rank the words the learner finds hardest (FR-18)

Ease factor is the running difficulty estimate, so FR-18 ranks by it
directly and surfaces only words below the 2.5 start. No lapse count, no
schema migration.

That has a consequence worth stating: Scheduler adds +0.05 on every pass, so
a word that lapsed once and has since been recalled four times returns to
exactly 2.50 and leaves this list. Correct rather than lossy -- FR-18 asks
what is hard now, and a permanent record of old mistakes is closer to a
shame list than to help.

2.5 was an initializer default and is now ReviewState.startingEase, so the
filter and the default cannot drift apart."
```

---

### Task 2: FR-17 — the cumulative trend

**Files:**
- Modify: `Packages/Domain/Sources/Domain/StatsService.swift`
- Modify: `Packages/Domain/Tests/DomainTests/StatsServiceTests.swift`

**Interfaces:**
- Consumes: `StatsService` from Task 1.
- Produces: `TrendPoint(day:started:learned:)`; `StatsService.trend(states:today:) -> [TrendPoint]`; `Array<TrendPoint>.learnedInLast(_ days: Int) -> Int`.

- [ ] **Step 1: Write the failing test**

Append to `StatsServiceTests.swift`:

```swift
@Test("FR-17 cumulative counts at a past date match the milestones")
func trendCountsMatchMilestones() {
    let first = word("chat", rank: 1)
    let second = word("chien", rank: 2)
    let states = [
        ReviewState(wordID: first.id, firstReviewedDate: day(0), learnedDate: day(2)),
        ReviewState(wordID: second.id, firstReviewedDate: day(1), learnedDate: nil),
    ]

    let series = StatsService().trend(states: states, today: day(3))

    #expect(series.count == 4)
    #expect(series.map(\.started) == [1, 2, 2, 2])
    #expect(series.map(\.learned) == [0, 0, 1, 1])
}
```

- [ ] **Step 2: Run it and confirm it fails**

```sh
swift test --package-path Packages/Domain --filter trendCountsMatchMilestones
```

Expected: build failure — `trend` and `TrendPoint` do not exist. Add them in Step 3, then re-run.

- [ ] **Step 3: Write `TrendPoint` and `trend`**

Add to `StatsService.swift`, above `struct StatsService`:

```swift
/// One day on FR-17's outcome trend. Both counts are cumulative — FR-17 asks
/// for words that have *moved into* learning and into learned — so both curves
/// rise monotonically and the gap between them is the in-flight set.
///
/// Plotting the *currently* learning population instead would fall as words
/// graduate: a line that drops when the learner succeeds, on the one screen
/// whose point is the climb toward 1000.
public struct TrendPoint: Equatable, Sendable {
    public let day: Date
    /// Cumulative words that have entered learning by this day.
    public let started: Int
    /// Cumulative words that have met `L` by this day. Never exceeds `started`.
    public let learned: Int

    public init(day: Date, started: Int, learned: Int) {
        self.day = day
        self.started = started
        self.learned = learned
    }
}
```

Add to `StatsService`:

```swift
    /// FR-17. One point per day from the earliest `firstReviewedDate` to
    /// `today`, both ends inclusive.
    ///
    /// `today` is a parameter rather than an injected clock, matching
    /// `Scheduler.schedule(_:grade:today:)` — the type stays a pure function of
    /// its arguments, so determinism is structural rather than a discipline.
    ///
    /// Per-day rather than only on days something changed: a cumulative count
    /// is truthful under any interpolation the chart picks, where sparse points
    /// would draw a diagonal across a week when nothing happened.
    public func trend(states: [ReviewState], today: Date) -> [TrendPoint] {
        let started = states.compactMap(\.firstReviewedDate).map(DayCalendar.startOfDay).sorted()
        let learned = states.compactMap(\.learnedDate).map(DayCalendar.startOfDay).sorted()
        guard let first = started.first else { return [] }
        let end = DayCalendar.startOfDay(today)
        guard first <= end else { return [] }

        var points: [TrendPoint] = []
        var startedIndex = 0
        var learnedIndex = 0
        var day = first
        while day <= end {
            while startedIndex < started.count, started[startedIndex] <= day { startedIndex += 1 }
            while learnedIndex < learned.count, learned[learnedIndex] <= day { learnedIndex += 1 }
            points.append(TrendPoint(day: day, started: startedIndex, learned: learnedIndex))
            day = DayCalendar.adding(days: 1, to: day)
        }
        return points
    }
```

- [ ] **Step 4: Run it and confirm it passes**

```sh
swift test --package-path Packages/Domain --filter trendCountsMatchMilestones
```

Expected: PASS.

- [ ] **Step 5: Write the window helper's failing test**

```swift
@Test("FR-17 words learned in the last 7 days equals the milestones within 7 days")
func learnedInLastSevenDays() {
    let old = word("chat", rank: 1)
    let recent = word("chien", rank: 2)
    let edge = word("cheval", rank: 3)
    let states = [
        ReviewState(wordID: old.id, firstReviewedDate: day(0), learnedDate: day(1)),
        ReviewState(wordID: recent.id, firstReviewedDate: day(0), learnedDate: day(28)),
        // Exactly on the boundary: today − 7 counts as within the last 7 days.
        ReviewState(wordID: edge.id, firstReviewedDate: day(0), learnedDate: day(23)),
    ]

    let series = StatsService().trend(states: states, today: day(30))

    #expect(series.learnedInLast(7) == 2)
    #expect(series.learnedInLast(30) == 3)
}
```

- [ ] **Step 6: Run it and confirm it fails**

```sh
swift test --package-path Packages/Domain --filter learnedInLastSevenDays
```

Expected: build failure — `learnedInLast` does not exist.

- [ ] **Step 7: Write the window helper**

Append to `StatsService.swift`:

```swift
extension Array where Element == TrendPoint {
    /// FR-17's acceptance sentence, read off the series rather than recomputed
    /// from the states — one derivation, so the number and the curve cannot
    /// disagree.
    ///
    /// Both ends inclusive: a milestone dated exactly `today − days` counts as
    /// within the window, so the baseline is the day *before* it.
    public func learnedInLast(_ days: Int) -> Int {
        guard let latest = last else { return 0 }
        let baselineDay = DayCalendar.adding(days: -(days + 1), to: latest.day)
        let baseline = self.last(where: { $0.day <= baselineDay })?.learned ?? 0
        return latest.learned - baseline
    }
}
```

- [ ] **Step 8: Run it and confirm it passes**

Expected: PASS.

- [ ] **Step 9: Write the three remaining FR-17 tests**

```swift
@Test("FR-17 learned never exceeds started at any point in a series")
func learnedNeverExceedsStarted() {
    let entries = (1...20).map { word("mot\($0)", rank: $0) }
    let states = entries.enumerated().map { index, entry in
        ReviewState(
            wordID: entry.id,
            firstReviewedDate: day(index),
            learnedDate: index.isMultiple(of: 3) ? day(index + 5) : nil)
    }

    let series = StatsService().trend(states: states, today: day(40))

    #expect(series.allSatisfy { $0.learned <= $0.started })
}

@Test("FR-17 no milestones yields an empty series")
func noMilestonesYieldsEmptySeries() {
    let untouched = word("chat", rank: 1)

    let series = StatsService().trend(
        states: [ReviewState(wordID: untouched.id)], today: day(10))

    #expect(series.isEmpty)
}

@Test("FR-17 the series is a pure function of its states and today")
func trendIsPure() {
    let entry = word("chat", rank: 1)
    let states = [
        ReviewState(wordID: entry.id, firstReviewedDate: day(0), learnedDate: day(4))
    ]
    let service = StatsService()

    #expect(
        service.trend(states: states, today: day(9))
            == service.trend(states: states, today: day(9)))
}
```

- [ ] **Step 10: Run the Domain suite with coverage and check the gate**

```sh
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
```

Expected: PASS, and the gate reports ≥ 90%.

- [ ] **Step 11: Commit**

```bash
git add Packages/Domain/Sources/Domain/StatsService.swift \
        Packages/Domain/Tests/DomainTests/StatsServiceTests.swift
git commit -m "feat: the cumulative learning trend (FR-17)

One point per day from the earliest first-review to today, both counts
cumulative. FR-17 asks for words that have 'moved into' learning and into
learned, which is cumulative, so both curves rise and the gap between them
carries the in-flight set. Plotting currently-learning would fall as words
graduate -- a line that drops when the learner succeeds.

learnedInLast reads its answer off the series rather than recomputing from
the states, so the number in the accessibility label and the shape of the
curve cannot disagree. Both ends inclusive, which is what makes the 7-day
figure match FR-17's own acceptance example instead of being off by one.

today is a parameter, not an injected clock, matching Scheduler -- the type
stays pure and determinism is structural."
```

---

### Task 3: `ProgressViewModel` on states, and `ReviewStore.progress` deleted

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift`
- Modify: `FullDeck/FullDeck/ContentView.swift`
- Modify: `Packages/Domain/Sources/Domain/Ports.swift:40`
- Modify: `Packages/Domain/Sources/Domain/InMemoryReviewStore.swift:31`
- Modify: `Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift:41`
- Modify: `Packages/Data/Sources/Data/SwiftDataReviewStore.swift:39`
- Modify: `Packages/Data/Tests/DataTests/SwiftDataReviewStoreTests.swift`
- Test: `FullDeck/FullDeckTests/ProgressViewModelTests.swift`

**Interfaces:**
- Consumes: `StatsService.trend(states:today:)`, `StatsService.hardestWords(in:states:limit:)`.
- Produces: `ProgressViewModel.Snapshot(learned:total:trend:hardest:)`; `ProgressViewModel.State.ready(Snapshot)`; `ProgressViewModel.hardestWordLimit = 5`; `ProgressViewModel(languageCode:packStore:reviewStore:stats:clock:)`.

- [ ] **Step 1: Rewrite `ProgressViewModel`**

Replace the body of `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift`:

```swift
import Domain
import Foundation
import Observation

/// Words learned out of the language's total (FR-10), the outcome trend
/// (FR-17), and the hardest words (FR-18). No streaks, no time-spent, no review
/// counts — §4 rules those out, and this screen stays outcome-only.
@MainActor
@Observable
final class ProgressViewModel {
    /// Everything the screen draws, derived from one pack load and one states
    /// load. A struct rather than loose associated values: the screen now has
    /// three sections and a four-tuple in an enum case reads like nothing.
    struct Snapshot: Equatable {
        let learned: Int
        let total: Int
        let trend: [TrendPoint]
        let hardest: [WordEntry]
    }

    enum State: Equatable {
        case loading
        case ready(Snapshot)
        case failed(String)
    }

    /// Five reads as "here is what to watch"; ten starts to read as a report
    /// card, and in an app that bans streak-guilt the length of a list of your
    /// own mistakes is a tone decision.
    static let hardestWordLimit = 5

    private(set) var state: State = .loading

    private let languageCode: LanguageCode
    private let packStore: PackStore
    private let reviewStore: ReviewStore
    private let stats: StatsService
    private let clock: DayClock

    init(
        languageCode: LanguageCode, packStore: PackStore, reviewStore: ReviewStore,
        stats: StatsService = StatsService(), clock: DayClock
    ) {
        self.languageCode = languageCode
        self.packStore = packStore
        self.reviewStore = reviewStore
        self.stats = stats
        self.clock = clock
    }

    func load() async {
        state = .loading
        do {
            let pack = try await packStore.loadPack(languageCode)
            // One read of the states feeds all three sections. `ReviewStore` used
            // to expose a `progress(_:)` that recomputed the count store-side;
            // two paths to one number can disagree, so it was deleted.
            let states = try await reviewStore.allStates(languageCode)
            state = .ready(
                Snapshot(
                    learned: ProgressSummary(states: states).wordsLearned,
                    total: pack.wordCount,
                    trend: stats.trend(states: states, today: clock.today),
                    hardest: stats.hardestWords(
                        in: pack, states: states, limit: Self.hardestWordLimit)))
        } catch let error as PackLoadError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(String(localized: "Couldn't load your progress."))
        }
    }
}

extension ProgressViewModel.State {
    /// FR-11. `total > 0` guards the degenerate case: an empty pack is not an
    /// achievement, and `.loading` is not a verdict.
    var isComplete: Bool {
        if case .ready(let snapshot) = self {
            return snapshot.total > 0 && snapshot.learned == snapshot.total
        }
        return false
    }
}
```

- [ ] **Step 2: Pass the clock from `ContentView`**

In `makeViewModels(for:)`, change the `ProgressViewModel` construction to:

```swift
        progressViewModel = ProgressViewModel(
            languageCode: language, packStore: dependencies.packStore,
            reviewStore: dependencies.reviewStore, clock: dependencies.clock)
```

- [ ] **Step 3: Delete `progress(_:)` from the port and both stores**

`Packages/Domain/Sources/Domain/Ports.swift` — delete this line from `protocol ReviewStore`:

```swift
    func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary
```

`Packages/Domain/Sources/Domain/InMemoryReviewStore.swift` — delete the whole method:

```swift
    public func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary {
        let states = try await allStates(languageCode)
        return ProgressSummary(states: states)
    }
```

`Packages/Data/Sources/Data/SwiftDataReviewStore.swift` — delete the identical method.

**Do not delete `ProgressSummary`.** It names FR-17's buckets and `ProgressSummary(states:)` is how the hero count is still derived.

- [ ] **Step 4: Delete the three tests that exercised it**

`Packages/Domain/Tests/DomainTests/InMemoryReviewStoreTests.swift` — delete
`@Test("FR-10 InMemoryReviewStore progress counts learned, in-progress and total")`
and its `progressComputesFromMilestoneDates()` body.

`Packages/Data/Tests/DataTests/SwiftDataReviewStoreTests.swift` — delete
`@Test("FR-10 progress counts learned and in-progress words from milestone dates")`
and `@Test("NFR-10 progress for a language with no saved state is all zeros")`
with their bodies.

These tested a method that no longer exists. `ProgressSummary(states:)` is
covered in Domain, and `allStates` has its own tests.

- [ ] **Step 5: Run both package suites and the coverage gates**

```sh
swift test --package-path Packages/Domain
swift test --package-path Packages/Data
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
```

Expected: PASS. **The Data gate is the one to watch** — removing tested lines moves the ratio. If it drops below 80, do not add a test for the sake of the number; report it and stop.

- [ ] **Step 6: Rewrite `ProgressViewModelTests` for `Snapshot`**

Every existing assertion of the form `.ready(learned: 1, total: 2)` no longer
compiles. Replace the file's helper and those assertions:

```swift
@MainActor
private func makeProgressViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    seed: [ReviewState] = [],
    today: Date = day(0),
    errorOverride: PackLoadError? = nil
) -> ProgressViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:],
        errorOverride: errorOverride)
    return ProgressViewModel(
        languageCode: code, packStore: packStore,
        reviewStore: InMemoryReviewStore(seed: seed), clock: FixedDayClock(today: today))
}

/// Unwraps `.ready` so a test can assert on one field without matching a
/// whole `Snapshot`.
@MainActor
private func snapshot(_ viewModel: ProgressViewModel) -> ProgressViewModel.Snapshot? {
    if case .ready(let snapshot) = viewModel.state { return snapshot }
    return nil
}
```

Then update the four count assertions:

- `progressReportsLearnedOutOfTotal`: `#expect(snapshot(viewModel)?.learned == 1)` and `#expect(snapshot(viewModel)?.total == 2)`
- `untouchedLanguageReadsZero`: `#expect(snapshot(viewModel)?.learned == 0)` and `#expect(snapshot(viewModel)?.total == 2)`
- `progressReportsCompleteWhenAllLearned`: `#expect(snapshot(viewModel)?.learned == 2)`, `#expect(snapshot(viewModel)?.total == 2)`, `#expect(viewModel.state.isComplete)`
- `progressSchemaVersionMismatchSurfacesUpdateMessage` is unchanged — it asserts `.failed`.

- [ ] **Step 7: Add the two new ViewModel tests**

```swift
@Test("FR-17 a load populates the trend from the states' milestone dates")
@MainActor
func loadPopulatesTheTrend() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeProgressViewModel(
        pack: pack,
        seed: [
            ReviewState(
                wordID: pack.words[0].id, firstReviewedDate: day(0), learnedDate: day(2))
        ],
        today: day(3))

    await viewModel.load()

    #expect(snapshot(viewModel)?.trend.count == 4)
    #expect(snapshot(viewModel)?.trend.last?.learned == 1)
}

@Test("FR-18 a load populates the hardest words, hardest first")
@MainActor
func loadPopulatesHardestWords() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeProgressViewModel(
        pack: pack,
        seed: [
            ReviewState(wordID: pack.words[0].id, easeFactor: 2.2),
            ReviewState(wordID: pack.words[1].id, easeFactor: 1.7),
        ])

    await viewModel.load()

    #expect(snapshot(viewModel)?.hardest.map(\.lemma) == ["chien", "chat"])
}
```

- [ ] **Step 8: Run the app unit bundle**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Packages/ FullDeck/FullDeck/ViewModels/ProgressViewModel.swift \
        FullDeck/FullDeck/ContentView.swift \
        FullDeck/FullDeckTests/ProgressViewModelTests.swift
git commit -m "refactor: derive all progress from states, and delete ReviewStore.progress

ProgressViewModel now makes exactly two calls -- loadPack and allStates --
and derives the count, the trend and the hardest words from the result.

ReviewStore.progress(_:) had one app caller. Once the ViewModel holds the
states it was a second path to a number Domain already computes purely, and
two paths to one number can disagree. The port method, both implementations
and their three tests are gone; ProgressSummary stays, because it is the type
that names FR-17's buckets and still derives the hero count.

State.ready carries a Snapshot rather than two loose ints -- three sections
would otherwise be a four-tuple in an enum case."
```

---

### Task 4: The Progress screen

**Files:**
- Modify: `FullDeck/FullDeck/Views/LearningProgressView.swift`

**Interfaces:**
- Consumes: `ProgressViewModel.Snapshot`, `TrendPoint`, `Array<TrendPoint>.learnedInLast(_:)`.
- Produces: nothing.

- [ ] **Step 1: Rewrite the view**

Replace `FullDeck/FullDeck/Views/LearningProgressView.swift`:

```swift
import Charts
import Domain
import SwiftUI

/// Words learned out of the total (FR-10), the outcome trend (FR-17), and the
/// hardest words (FR-18). Outcome-only: §4 rules out time-spent, review counts
/// and streak chains, and none of them appears here.
struct LearningProgressView: View {
    let viewModel: ProgressViewModel

    // Dynamic Type: 64pt at the default text size, scaling on the .largeTitle
    // curve — a bare .system(size:) would ignore the user's setting entirely.
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Progress")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .ready(let snapshot):
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero(snapshot)
                    // Hidden rather than shown empty: a flat line at zero says
                    // nothing, where the hardest-words empty state says
                    // something true.
                    if !snapshot.trend.isEmpty {
                        trend(snapshot.trend)
                    }
                    hardest(snapshot.hardest)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    private func hero(_ snapshot: ProgressViewModel.Snapshot) -> some View {
        VStack(spacing: Spacing.sm) {
            Text("\(snapshot.learned)")
                .font(.system(size: countSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Text("of \(snapshot.total) words learned")
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
            if viewModel.state.isComplete {
                Text("Every word. That's the whole deck.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.learned) of \(snapshot.total) words learned")
    }

    private func trend(_ series: [TrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Over time")
            Chart {
                ForEach(series, id: \.day) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Words", point.started),
                        series: .value("Series", "started")
                    )
                    .foregroundStyle(Color.textSecondary)
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Words", point.learned),
                        series: .value("Series", "learned")
                    )
                    .foregroundStyle(Color.accentFill)
                }
            }
            // Axis labels are *text*, so they need 4.5:1 and SwiftUI's default
            // axis grey does not clear it on this background — the same defect
            // C-6 caught on the Settings section headers, one screen over.
            .chartXAxis {
                AxisMarks { AxisValueLabel().foregroundStyle(Color.textSecondary) }
            }
            .chartYAxis {
                AxisMarks { AxisValueLabel().foregroundStyle(Color.textSecondary) }
            }
            .frame(height: chartHeight)
            // One label, not hundreds of marks. VoiceOver reading a per-day
            // series individually is worse than silence, and the numbers are
            // FR-17's own acceptance sentence.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(series.learnedInLast(7)) words learned in the last 7 days, "
                    + "\(series.learnedInLast(30)) in the last 30")
        }
    }

    private func hardest(_ words: [WordEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Hardest words")
            if words.isEmpty {
                // True, useful, and not a scolding.
                Text("Nothing has tripped you up yet.")
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(words, id: \.id) { word in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(word.display)
                            .foregroundStyle(Color.textPrimary)
                        Text(word.gloss)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.textSecondary)
    }
}
```

- [ ] **Step 2: Build and run the app suite**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

Expected: PASS.

- [ ] **Step 3: Look at it**

```sh
xcodebuild build -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Launch, pick Français, grade a few cards, then open Progress. Check: the hero
count is unchanged, the trend section is absent on a fresh install and appears
once a word has been reviewed, and hardest words reads "Nothing has tripped you
up yet." until a card is graded *forgot*.

- [ ] **Step 4: Run the gates**

```sh
swiftlint lint --strict
scripts/determinism-check.sh
```

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/Views/LearningProgressView.swift
git commit -m "feat: show the outcome trend and the hardest words (FR-17, FR-18)

A scrolling Progress screen: the hero count unchanged, then the cumulative
trend, then five hardest words. The trend hides until a milestone exists --
an empty curve says nothing -- while hardest words always shows, because
'nothing has tripped you up yet' is worth knowing.

Chart colours are chosen against the audit rather than by eye. Axis labels
are text and need 4.5:1, which SwiftUI's default axis grey misses on this
background -- the same defect C-6 caught on the Settings headers one screen
over. Marks are graphical objects at 3:1; AccentFill and TextSecondary clear
either bar.

The chart is one accessibility element with one label, not hundreds of
marks, and the label states FR-17's acceptance sentence -- so a screen-reader
user gets the numeric form of the requirement instead of a shape."
```

---

### Task 5: Audit, gates, and documentation

**Files:**
- Modify: `docs/known-issues.md`
- Modify: `docs/next-task.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Run the accessibility audit**

Progress is already one of the audited screens, so no test changes are needed.

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckUITests/FullDeckUITests/testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens'
```

**Expect findings.** The last two screens added to this audit produced four real
contrast defects between them. To read what failed:

```sh
BUNDLE=$(ls -td ~/Library/Developer/Xcode/DerivedData/FullDeck-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool export attachments --path "$BUNDLE" \
  --test-id 'FullDeckUITests/testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens()' \
  --output-path /tmp/audit
cat /tmp/audit/*.txt
```

The exported `Element Screenshot` PNG shows exactly which element failed. **Fix
the colour; never filter the audit** — a filter that outlives its problem hides
the next real regression.

- [ ] **Step 2: Run every gate**

```sh
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

Expected: all pass. `trace-requirements.sh` should now name **FR-18**, which has
never had a test — it was one of the IDs under "Named by none".

- [ ] **Step 3: Update `docs/known-issues.md`**

- Mark **N-2** (FR-17) and **N-3** (FR-18) FIXED 2026-08-02, each with what it
  taught: N-2 that "moved into" is cumulative and why the alternative reading
  loses; N-3 that ease rises on a pass, so ease alone cannot answer "ever
  failed", and why ranking by it anyway is right.
- Update the **N** section preamble — with N-1 through N-5 closed, no requirement
  in `docs/requirements.md` is unimplemented. N-6 (the display name) remains.
- Add whatever the audit found in Step 1 to **C-6**, which already records the
  Settings findings. If it found nothing, say so — that is also information,
  and it would be the first new screen in three to pass first time.
- Note that `StatsService` now exists, closing the `architecture.md` §3 gap the
  N-2 entry pointed at.

- [ ] **Step 4: Update `docs/next-task.md`**

Replace the "Right now" block: the N-block is complete, and the next task is
**Phase 13 — QA and the edge-case matrix, `docs/test-plan.md`**. Keep the
pointer to `known-issues.md`, and keep E-6 (CI billing) at the top, since it
still blocks every gate from running anywhere but locally.

- [ ] **Step 5: Commit**

```bash
git add docs/known-issues.md docs/next-task.md
git commit -m "docs: close N-2 and N-3, and finish the N-block

StatsService exists, so architecture.md §3's named-but-never-written type is
real and every requirement in requirements.md now has an implementation.

Two findings worth keeping. FR-17's 'moved into' is cumulative, so both
curves rise and the gap between them is the in-flight set -- plotting
currently-learning would have drawn a line that falls when the learner
succeeds. And ease factor rises +0.05 on every pass, so it cannot answer
'ever failed'; FR-18 ranks by it regardless, because what it can answer --
what is hard now -- is the more useful question."
```

---

## Self-Review

**Spec coverage.** Decision 1 (ease proxy, `startingEase`, rejected alternatives)
→ Task 1. Decision 2 (`TrendPoint`, cumulative, per-day, span and boundary) →
Task 2. Decision 3 (`StatsService` signatures, `today` as parameter, `[WordEntry]`
return, missing-word skip, rank tie-break, no `limit` default) → Tasks 1 and 2.
Decision 4 (states as single source, deletion, `Snapshot`, `ProgressSummary`
stays) → Task 3. Decision 5 (scroll, three blocks, empty-state table, five,
read-only) → Task 4. Decision 6 (chart accessibility, the three rules, already
audited) → Tasks 4 and 5. Errors → Task 3 Step 1, unchanged in shape. Testing →
all ten Domain tests plus two ViewModel tests. Out of scope and risks carry no
tasks by definition. No spec section is unassigned.

**Placeholders.** None. Every code step carries real code; no "handle edge
cases", no "similar to Task N".

**Type consistency.** `TrendPoint(day:started:learned:)` is spelled identically
in Tasks 2, 3 and 4. `hardestWords(in:states:limit:)` and `trend(states:today:)`
match between definition, ViewModel call site and tests. `learnedInLast(_:)` is
the same in Task 2's helper, its test and Task 4's label.
`ProgressViewModel.Snapshot`'s four fields — `learned`, `total`, `trend`,
`hardest` — match across Tasks 3 and 4. `ReviewState.startingEase` is the same in
Models.swift, the filter, and the FR-18 test. `FixedDayClock(today:)` already
exists in `Fakes.swift`.

**One risk the plan cannot remove.** Task 3 Step 5 may drop the Data package
below its 80% floor, because deleting tested code moves a ratio. The step says to
report it rather than write a test for the number — that is Arjun's call, not
something to paper over.
