# Phase 9 — Integration & the "Done" State: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define what makes a word "learned", build the completion screen, and replace every Phase 8 fake with the real Phase 6/7 implementations, proven by integration tests across the seams.

**Architecture:** The learned rule is one constant plus two stamping lines inside `Scheduler.schedule` — pure Domain, test-first. The completion state is a comparison (`learned == pack.wordCount`) surfaced as a new case on `StudyViewModel.State`; `SessionBuilder` needs no change because its new-word filter is already empty once every word has a state. The composition root swaps `InMemoryPackStore`/`InMemoryReviewStore` for `JSONPackStore`/`SwiftDataReviewStore`, and grows a test seam so integration tests reach the real adapters without the test target linking `Data`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test`/`#expect`), SwiftData, Swift Package Manager local packages (`Packages/Domain`, `Packages/Data`).

**Design doc:** [`docs/superpowers/specs/2026-07-28-phase-9-integration-design.md`](../specs/2026-07-28-phase-9-integration-design.md)

## Global Constraints

- **Test-first for logic.** One behavior at a time: write the failing test, run it, confirm it fails *because the behavior is missing* (a compile error is not a red — fix and re-run), then the minimal code to green it. Applies to Tasks 1, 3, 4, 8. Tasks 6, 7, 9 are framework glue — tested alongside.
- **Requirement traceability.** Every `@Test` display name starts with its requirement ID: `@Test("FR-10 …")`.
- **Test determinism.** No test may call `Date()`, `Date.now`, `Task.sleep`, `Thread.sleep`, `arc4random`, or `.random(` without `using:`. `scripts/determinism-check.sh` greps for these. Use the existing `day0`/`day(_:)` helpers.
- **Coverage floors (hard CI fail):** Domain ≥ 90%, Data ≥ 80%. No floor on the app target.
- **Warnings are errors.** Packages build with `-Xswiftc -warnings-as-errors`; the Xcode targets set `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- **Dependency direction.** Domain imports nothing but Foundation. Data imports Domain. Only the app target may import `Data`.
- **`L = 14`.** The learned threshold is `intervalDays >= 14`, and `learnedDate` is **sticky** — set once, never cleared, not even by a lapse.
- **Lint:** `swiftlint lint --strict` is gated. Match surrounding comment density and naming; this codebase comments the *why*, not the *what*.
- **Conventional commits**, small and focused. Commit at the end of every task.

---

## File Structure

**Domain (`Packages/Domain`)**
- Modify `Sources/Domain/Scheduler.swift` — add `learnedIntervalDays`, stamp both milestone dates.
- Modify `Tests/DomainTests/SchedulerTests.swift` — six example tests + two invariants.

**Presentation (`FullDeck/FullDeck`)**
- Modify `ViewModels/StudyViewModel.swift` — remove the moved stamping, add `.complete`.
- Modify `ViewModels/ProgressViewModel.swift` — add `State.isComplete`.
- Modify `ViewModels/LanguageSelectionViewModel.swift` — inject `UserDefaults`, persist/restore the active language.
- Modify `Views/StudyView.swift` — render `.complete`, take an `onAddLanguage` closure.
- Modify `Views/LearningProgressView.swift` — one extra line when complete.
- Modify `ContentView.swift` — pass the tab-switch closure into `StudyView`.
- Modify `AppDependencies.swift` — real adapters, throwing factory, test seam.
- Modify `FullDeckApp.swift` — render `ErrorStateView` when the composition root fails.
- Delete `SamplePack.swift`.
- Create `Resources/packs/fr.pack.json` and `Resources/packs/manifest.json`.

**Tests (`FullDeck/FullDeckTests`)**
- Modify `StudyViewModelTests.swift`, `ProgressViewModelTests.swift`, `LanguageSelectionViewModelTests.swift`, `Fakes.swift`.
- Create `IntegrationTests.swift`.

---

### Task 1: The learned rule in Domain

**Files:**
- Modify: `Packages/Domain/Sources/Domain/Scheduler.swift:23` (add constant), `:57` (add stamping before `return next`)
- Test: `Packages/Domain/Tests/DomainTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `ReviewState` (`Models.swift`), `Scheduler.schedule(_:grade:today:)`, the file-private `day0` / `day(_:)` / `chat` helpers already at the top of `SchedulerTests.swift`.
- Produces: `Scheduler.learnedIntervalDays: Int` (internal, value `14`), and the guarantee that `schedule` returns a state with `firstReviewedDate` and `learnedDate` populated. Tasks 2, 3, 4 and 9 rely on this.

Run every test in this task with:

```bash
swift test --package-path Packages/Domain
```

- [ ] **Step 1: Write the first failing test — below the threshold**

Append to `Packages/Domain/Tests/DomainTests/SchedulerTests.swift`, above the `// MARK: - Invariants` divider:

```swift
// MARK: - The learned threshold (Phase 9)

@Test("FR-10 a word that lands below the learned interval is not learned")
func belowLearnedIntervalIsNotLearned() {
    // Ease 2.2 — this word took a `.hard` earlier. 6 × 2.2 = 13.2 → 13, one short.
    let state = ReviewState(
        wordID: chat, easeFactor: 2.2, intervalDays: 6, repetitions: 2,
        nextReviewDate: day(7), firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .good, today: day(7))

    #expect(next.intervalDays == 13)
    #expect(next.learnedDate == nil)
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

Run: `swift test --package-path Packages/Domain --filter belowLearnedIntervalIsNotLearned`

Expected: **PASS**, not fail. `learnedDate` defaults to `nil` and nothing sets it yet, so this test is green from the start. That is correct and expected — it is the guard that the *next* test doesn't over-fire. Keep it.

- [ ] **Step 3: Write the failing test that actually drives the code**

```swift
@Test("FR-10 crossing the learned interval stamps learnedDate")
func crossingLearnedIntervalStampsLearnedDate() {
    // Ease 2.5 — same shape as the test above, one notch easier. 6 × 2.5 = 15.
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2,
        nextReviewDate: day(7), firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .good, today: day(7))

    #expect(next.intervalDays == 15)
    #expect(next.learnedDate == day(7))
}
```

- [ ] **Step 4: Run it and confirm the red**

Run: `swift test --package-path Packages/Domain --filter crossingLearnedIntervalStampsLearnedDate`

Expected: FAIL on `#expect(next.learnedDate == day(7))` — actual `nil`. If it fails to *compile* instead, that is not a red: fix the typo and re-run until it fails on the expectation.

- [ ] **Step 5: Add the constant**

In `Packages/Domain/Sources/Domain/Scheduler.swift`, below `static let intervalRange = 1...365`:

```swift
    /// A word counts as learned once it survives a two-week gap (FR-10, FR-11).
    /// Interval-based rather than repetition-based so a low-ease word has to earn
    /// it: at ease 2.2 the third pass lands at 13.2 days and does not cross.
    static let learnedIntervalDays = 14
```

- [ ] **Step 6: Stamp `learnedDate`**

In `schedule(_:grade:today:)`, between `next.nextReviewDate = …` and `return next`:

```swift
        // Sticky (FR-17): set once on the crossing review and never cleared — not
        // even by a lapse, which resets intervalDays to 1. The progress trend is
        // reconstructed from this date, so clearing it would erase history.
        if state.learnedDate == nil, next.intervalDays >= Self.learnedIntervalDays {
            next.learnedDate = today
        }
```

- [ ] **Step 7: Run both tests**

Run: `swift test --package-path Packages/Domain --filter LearnedInterval`
Expected: both PASS.

- [ ] **Step 8: Write the failing stickiness test**

```swift
@Test("FR-10 a lapse does not un-learn a word")
func lapseDoesNotUnlearnWord() {
    let learned = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 15, repetitions: 3,
        nextReviewDate: day(22), firstReviewedDate: day0, learnedDate: day(7))

    let next = Scheduler().schedule(learned, grade: .again, today: day(22))

    #expect(next.intervalDays == 1)
    #expect(next.learnedDate == day(7))
}

@Test("FR-10 a later review does not restamp learnedDate")
func laterReviewDoesNotRestampLearnedDate() {
    let learned = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 15, repetitions: 3,
        nextReviewDate: day(22), firstReviewedDate: day0, learnedDate: day(7))

    let next = Scheduler().schedule(learned, grade: .good, today: day(22))

    #expect(next.intervalDays == 38)
    #expect(next.learnedDate == day(7))
}
```

- [ ] **Step 9: Run them**

Run: `swift test --package-path Packages/Domain --filter Unlearn` then `--filter Restamp`

Expected: both PASS. The `state.learnedDate == nil` guard from Step 6 already covers stickiness — these two lock the behavior in against a future edit that drops the guard. If either fails, the guard is wrong; fix Step 6, don't relax the test.

- [ ] **Step 10: Write the failing `firstReviewedDate` tests**

These move the stamping down from `StudyViewModel`, so they are genuinely red.

```swift
@Test("FR-4 a first review stamps firstReviewedDate")
func firstReviewStampsFirstReviewedDate() {
    let state = ReviewState(wordID: chat)

    let next = Scheduler().schedule(state, grade: .good, today: day0)

    #expect(next.firstReviewedDate == day0)
}

@Test("FR-4 a later review leaves firstReviewedDate alone")
func laterReviewLeavesFirstReviewedDateAlone() {
    let state = ReviewState(
        wordID: chat, intervalDays: 1, repetitions: 1, nextReviewDate: day(1),
        firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .good, today: day(1))

    #expect(next.firstReviewedDate == day0)
}
```

- [ ] **Step 11: Run and confirm the first one is red**

Run: `swift test --package-path Packages/Domain --filter FirstReviewedDate`
Expected: `firstReviewStampsFirstReviewedDate` FAILS (actual `nil`); `laterReviewLeavesFirstReviewedDateAlone` passes.

- [ ] **Step 12: Stamp `firstReviewedDate`**

In `schedule(_:grade:today:)`, immediately *above* the `learnedDate` block added in Step 6:

```swift
        // FR-4's per-day new-word cap counts introductions by this date. It lives
        // here rather than in the caller because it is a pure function of the same
        // (state, grade, today) the scheduler already takes.
        if next.firstReviewedDate == nil { next.firstReviewedDate = today }
```

- [ ] **Step 13: Run**

Run: `swift test --package-path Packages/Domain --filter FirstReviewedDate`
Expected: both PASS.

- [ ] **Step 14: Add the two milestone invariants to the random walk**

In `schedulingInvariantsHoldAcrossSeededRandomWalk`, declare `var everCrossedLearnedInterval = false` **outside** the loop, beside `var state` and `var today`. Then, **inside** the loop after the existing `#expect`s:

```swift
        if next.intervalDays >= Scheduler.learnedIntervalDays { everCrossedLearnedInterval = true }
        #expect(
            next.firstReviewedDate != nil,
            "step \(step): a reviewed word has no firstReviewedDate")
        if let previouslyLearned = state.learnedDate {
            #expect(
                next.learnedDate == previouslyLearned,
                "step \(step): learnedDate moved after it was set")
        }
        #expect(
            next.learnedDate == nil || everCrossedLearnedInterval,
            "step \(step): learnedDate was set without any interval reaching the threshold")
```

- [ ] **Step 15: Run the whole Domain suite with coverage**

```bash
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
```

Expected: all tests PASS, coverage gate PASSES.

- [ ] **Step 16: Commit**

```bash
git add Packages/Domain/Sources/Domain/Scheduler.swift Packages/Domain/Tests/DomainTests/SchedulerTests.swift
git commit -m "feat(domain): define the learned threshold and stamp review milestones"
```

---

### Task 2: Drop the moved stamping from StudyViewModel

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift:113-117`
- Test: `FullDeck/FullDeckTests/StudyViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1's stamping guarantee.
- Produces: nothing new. `grade()` keeps its signature.

The app suite needs a simulator:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 1: Find the existing test that covers the stamping**

Run: `grep -n "firstReviewedDate" FullDeck/FullDeckTests/StudyViewModelTests.swift`

There is a test named `firstGradeStampsFirstReviewedDate` (referenced by name in `scripts/determinism-check.sh:31`). It asserts the ViewModel stamps the date. It must keep passing — the behavior is unchanged, only its owner moved.

- [ ] **Step 2: Delete the stamping from the ViewModel**

In `StudyViewModel.grade()`, remove these three lines and the comment above them:

```swift
            // Stamping the first review here is what makes FR-4's per-day cap
            // countable. `learnedDate` stays Phase 9's job.
            if next.firstReviewedDate == nil {
                next.firstReviewedDate = today
            }
```

`var next` becomes `let next` — Swift will warn otherwise, and warnings are errors here.

- [ ] **Step 3: Run the app suite**

Run the `xcodebuild test` command above.
Expected: PASS, including `firstGradeStampsFirstReviewedDate`. Task 1 now produces the date the test asserts. If it fails, Task 1's Step 12 is wrong — fix there, not here.

- [ ] **Step 4: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/StudyViewModel.swift
git commit -m "refactor(app): move milestone stamping out of StudyViewModel into the scheduler"
```

---

### Task 3: The completion state on StudyViewModel

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift` (State enum, `start()`, `showCurrentCard()`)
- Test: `FullDeck/FullDeckTests/StudyViewModelTests.swift`, `FullDeck/FullDeckTests/Fakes.swift`

**Interfaces:**
- Consumes: `ProgressSummary.init(states:)` from `Packages/Domain/Sources/Domain/Ports.swift`, `LanguagePack.wordCount`.
- Produces: `StudyViewModel.State.complete(nextDue: Date?)`. Task 5 renders it; Task 9 asserts it end-to-end.

- [ ] **Step 1: Add a learned-state helper to the test fakes**

In `FullDeck/FullDeckTests/Fakes.swift`, below `entry(_:rank:)`:

```swift
/// A `ReviewState` that has met `L` — for tests that need a pack already learned.
func learnedState(_ entry: WordEntry, on learned: Date = day(7)) -> ReviewState {
    ReviewState(
        wordID: entry.id, easeFactor: 2.5, intervalDays: 15, repetitions: 3,
        nextReviewDate: day(22), firstReviewedDate: day0, learnedDate: learned)
}
```

- [ ] **Step 2: Write the failing test**

Append to `FullDeck/FullDeckTests/StudyViewModelTests.swift`:

```swift
@Test("FR-11 a pack with every word learned shows the completion state")
@MainActor
func everyWordLearnedShowsCompletionState() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let seed = pack.words.map { learnedState($0) }
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    #expect(viewModel.state == .complete(nextDue: day(22)))
}
```

- [ ] **Step 3: Run it and confirm the red**

Run the `xcodebuild test` command from Task 2.
Expected: FAIL to compile — `.complete` does not exist. That is a compile error, so per the global constraints it is not yet a valid red. Continue to Step 4 and re-run; the point of this step is to see the *specific* missing symbol, not a green.

- [ ] **Step 4: Add the case**

In `StudyViewModel.State`, after `case caughtUp(nextDue: Date?)`:

```swift
        /// FR-11: every word in the pack has met `L`. No new words will ever be
        /// introduced again; due reviews still are. Distinct from `caughtUp`,
        /// which means "nothing due today" on an unfinished pack.
        case complete(nextDue: Date?)
```

- [ ] **Step 5: Re-run to get a real red**

Run the `xcodebuild test` command.
Expected: FAIL on the expectation — actual `.caughtUp(nextDue: day(22))`. This is the honest red.

- [ ] **Step 6: Track the pack's word count**

Add a stored property beside `private var states: [ReviewState] = []`:

```swift
    /// Cached from the loaded pack so the completion check costs no extra I/O.
    private var wordCount = 0
```

In `start()`, immediately after `let pack = try await packStore.loadPack(languageCode)`:

```swift
            wordCount = pack.wordCount
```

- [ ] **Step 7: Choose the state in `showCurrentCard()`**

Replace the empty-queue branch:

```swift
        guard position < queue.count else {
            // FR-11 wins over FR-12: a finished pack is done, not merely caught up.
            // Only reachable with an empty queue — if a review is due, the card shows.
            let nextDue = nextDueDate()
            state =
                wordCount > 0 && ProgressSummary(states: states).wordsLearned == wordCount
                ? .complete(nextDue: nextDue)
                : .caughtUp(nextDue: nextDue)
            return
        }
```

- [ ] **Step 8: Run and confirm green**

Run the `xcodebuild test` command.
Expected: PASS.

- [ ] **Step 9: Write the two boundary tests**

```swift
@Test("FR-11 the completion state is not shown while a review is due")
@MainActor
func completionStateNotShownWhileReviewIsDue() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    var seed = pack.words.map { learnedState($0) }
    seed[0].nextReviewDate = day(10)  // learned, but due today
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[0], isRevealed: false, index: 1, total: 1)))
}

@Test("FR-12 an unfinished pack with an empty queue still shows caught up")
@MainActor
func unfinishedPackWithEmptyQueueShowsCaughtUp() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    // Both seen, neither learned, neither due — caught up, not complete.
    let seed = pack.words.map {
        ReviewState(
            wordID: $0.id, intervalDays: 6, repetitions: 2, nextReviewDate: day(22),
            firstReviewedDate: day0)
    }
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    #expect(viewModel.state == .caughtUp(nextDue: day(22)))
}

@Test("FR-11 no new words are introduced once the pack is complete")
@MainActor
func noNewWordsIntroducedWhenComplete() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let seed = pack.words.map { learnedState($0) }
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), newWordCap: 100,
        reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    // A cap of 100 against a 2-word pack: if anything could still be introduced,
    // this would be a card.
    #expect(viewModel.state == .complete(nextDue: day(22)))
}
```

- [ ] **Step 10: Run all three**

Run the `xcodebuild test` command.
Expected: all PASS. `completionStateNotShownWhileReviewIsDue` proves the ordering in Step 7; `unfinishedPackWithEmptyQueueShowsCaughtUp` is the regression that keeps FR-11 and FR-12 distinct.

- [ ] **Step 11: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/StudyViewModel.swift FullDeck/FullDeckTests/StudyViewModelTests.swift FullDeck/FullDeckTests/Fakes.swift
git commit -m "feat(app): add the completion state to StudyViewModel"
```

---

### Task 4: `isComplete` on ProgressViewModel

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/ProgressViewModel.swift`
- Test: `FullDeck/FullDeckTests/ProgressViewModelTests.swift`

**Interfaces:**
- Consumes: the existing `ProgressViewModel.State.ready(learned:total:)`.
- Produces: `ProgressViewModel.State.isComplete: Bool`. Task 5 reads it.

- [ ] **Step 1: Write the failing test**

Append to `FullDeck/FullDeckTests/ProgressViewModelTests.swift`:

```swift
@Test("FR-11 progress reports the pack as complete when every word is learned")
@MainActor
func progressReportsCompleteWhenAllLearned() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeProgressViewModel(
        pack: pack, seed: pack.words.map { learnedState($0) })

    await viewModel.load()

    #expect(viewModel.state == .ready(learned: 2, total: 2))
    #expect(viewModel.state.isComplete)
}

@Test("FR-11 a partly learned pack is not complete")
@MainActor
func partlyLearnedPackIsNotComplete() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeProgressViewModel(pack: pack, seed: [learnedState(pack.words[0])])

    await viewModel.load()

    #expect(!viewModel.state.isComplete)
}

@Test("FR-11 an empty or unloaded pack is never complete")
@MainActor
func unloadedPackIsNotComplete() async {
    let viewModel = makeProgressViewModel()

    #expect(!viewModel.state.isComplete)  // still .loading
}
```

- [ ] **Step 2: Run and confirm the missing symbol**

Run the `xcodebuild test` command from Task 2.
Expected: compile failure — `isComplete` does not exist on `State`.

- [ ] **Step 3: Add it**

In `ProgressViewModel.swift`, at **file scope** — after the closing brace of the class, not inside it. Swift does not allow an extension nested in a class body:

```swift
extension ProgressViewModel.State {
    /// FR-11. `total > 0` guards the degenerate case: an empty pack is not an
    /// achievement, and `.loading` is not a verdict.
    var isComplete: Bool {
        if case .ready(let learned, let total) = self { return total > 0 && learned == total }
        return false
    }
}
```

- [ ] **Step 4: Run**

Run the `xcodebuild test` command.
Expected: all three PASS.

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/ProgressViewModel.swift FullDeck/FullDeckTests/ProgressViewModelTests.swift
git commit -m "feat(app): report pack completion from ProgressViewModel"
```

---

### Task 5: The completion screen

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`, `FullDeck/FullDeck/Views/LearningProgressView.swift`, `FullDeck/FullDeck/ContentView.swift`

**Interfaces:**
- Consumes: `StudyViewModel.State.complete(nextDue:)` (Task 3), `ProgressViewModel.State.isComplete` (Task 4).
- Produces: `StudyView.init(viewModel:onAddLanguage:)` — the second parameter is `() -> Void`.

Views are thin glue; there are no unit tests for them here. The gate is that the app builds and the suite stays green.

**Deviation from the spec, deliberate:** §2.5 writes the headline as "You've learned all 1000 words in French." `StudyViewModel.State.complete` carries only `nextDue`, so the view knows neither the count nor the language name; threading both through solely for a string that Phase 10's localization catalog will rewrite is not worth the payload change. The copy below is language-agnostic. If Phase 10 wants the specific wording, that is the phase that owns the catalog and can add the payload then.

- [ ] **Step 1: Give `StudyView` a way to switch tabs**

Add a stored property beside `let viewModel: StudyViewModel`:

```swift
    /// FR-11's completion screen offers another language; only `ContentView` knows
    /// how to select a tab, so it hands the action down rather than the view
    /// reaching for shared state.
    let onAddLanguage: () -> Void
```

- [ ] **Step 2: Render the new case**

In `StudyView.content`, add a branch after `case .caughtUp(let nextDue):`:

```swift
        case .complete(let nextDue):
            completionView(nextDue)
```

And add the view builder beside `caughtUpView`:

```swift
    /// FR-11: the deliberate ending. The price is stated rather than hidden —
    /// concealing it would be the dark pattern. No summary statistics, no streak.
    private func completionView(_ nextDue: Date?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("You've learned all the words in this language.")
                .font(.title2)
                .multilineTextAlignment(.center)
            if let nextDue {
                Text("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Button("Add another language — $0.99", action: onAddLanguage)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens the languages list")
        }
        .padding()
        .accessibilityElement(children: .contain)
    }
```

- [ ] **Step 3: Pass the closure from `ContentView`**

In `ContentView.studyTab`, change the `StudyView` construction:

```swift
            StudyView(viewModel: studyViewModel, onAddLanguage: { selectedTab = .languages })
                .id(language.rawValue)
```

- [ ] **Step 4: Add the completion line to the progress screen**

In `LearningProgressView.content`, inside the `.ready` branch's `VStack`, after the "of N words learned" `Text`:

```swift
                if viewModel.state.isComplete {
                    Text("Every word. That's the whole deck.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 5: Build and run the suite**

Run the `xcodebuild test` command from Task 2.
Expected: builds clean (no warnings — they are errors), all tests PASS.

- [ ] **Step 6: Lint**

```bash
swiftlint lint --strict
```

Expected: no violations.

- [ ] **Step 7: Commit**

```bash
git add FullDeck/FullDeck/Views FullDeck/FullDeck/ContentView.swift
git commit -m "feat(app): add the completion screen"
```

---

### Task 6: Bundle the real French pack

**Files:**
- Create: `FullDeck/FullDeck/Resources/packs/fr.pack.json` (copied), `FullDeck/FullDeck/Resources/packs/manifest.json`

**Interfaces:**
- Produces: a `packs/` directory inside the app bundle containing `manifest.json` and `fr.pack.json`. Tasks 7 and 9 read it via `Bundle.main.resourceURL`.

No `project.pbxproj` edit is needed: the app target uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16 synchronized folders), so a new directory under `FullDeck/FullDeck/` is picked up automatically and non-source files land in Copy Bundle Resources.

- [ ] **Step 1: Copy the pack**

```bash
mkdir -p FullDeck/FullDeck/Resources/packs && cp pipeline/packs/fr.pack.json FullDeck/FullDeck/Resources/packs/fr.pack.json
```

- [ ] **Step 2: Write the production manifest**

Create `FullDeck/FullDeck/Resources/packs/manifest.json`:

```json
{
  "packs": [
    {
      "language_code": "fr",
      "display_name": "Français",
      "filename": "fr.pack.json",
      "unlocked_by_default": true
    }
  ]
}
```

Only French. A manifest entry whose pack file does not exist makes `loadPack` throw, and Hindi's pack does not exist until Phase 12. The Languages tab will show one row until then; the locked-state UI stays covered by `LanguageSelectionViewModelTests` against fakes.

- [ ] **Step 3: Confirm the pack is what you think it is**

```bash
python3 -c "import json; d=json.load(open('FullDeck/FullDeck/Resources/packs/fr.pack.json')); print(d['schema_version'], d['word_count'], len(d['words']))"
```

Expected: `1 1000 1000`.

- [ ] **Step 4: Build and confirm the resources land in the bundle**

Run the `xcodebuild test` command from Task 2, then:

```bash
find ~/Library/Developer/Xcode/DerivedData -name "fr.pack.json" -path "*FullDeck.app*" | head -1
```

Expected: one path inside `FullDeck.app/packs/`. **If nothing is found**, the synchronized group did not pick the folder up — open `FullDeck/FullDeck.xcodeproj` in Xcode, confirm `Resources` appears under the FullDeck group, and check the two files are in Build Phases → Copy Bundle Resources. Do not hand-edit `project.pbxproj`.

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/Resources
git commit -m "feat(app): bundle the 1000-word French pack and a production manifest"
```

---

### Task 7: Wire the real layers

**Files:**
- Modify: `FullDeck/FullDeck/AppDependencies.swift`, `FullDeck/FullDeck/FullDeckApp.swift`
- Delete: `FullDeck/FullDeck/SamplePack.swift`

**Interfaces:**
- Consumes: `JSONPackStore(packsDirectory:maxSupportedSchemaVersion:audioAssetsDirectory:)` and `SwiftDataReviewStore(modelContainer:)` from the `Data` package; `PersistentReviewState` for the container's schema.
- Produces:
  - `AppDependencies.make(packsDirectory: URL, inMemory: Bool) throws -> AppDependencies` — the shared factory.
  - `AppDependencies.live() throws -> AppDependencies` — now **throwing**.
  - `AppDependencies.bundledPacksDirectory: URL` — `Bundle.main.resourceURL` + `packs`.
  Task 9's integration tests call `make(packsDirectory:inMemory:)` through `@testable import FullDeck`, which is why the test target never has to link `Data` itself.

- [ ] **Step 1: Rewrite `AppDependencies`**

Replace the whole file:

```swift
import Data
import Domain
import Foundation
import SwiftData

/// The composition root's output: every concrete dependency, constructed once and
/// handed down through initializers. No singletons, no DI framework (ADR-002) —
/// this struct *is* the wiring. It is also the only type in the app that knows
/// the `Data` package exists.
@MainActor
struct AppDependencies {
    let packStore: PackStore
    let reviewStore: ReviewStore
    let speech: SpeechService
    let clock: DayClock
    let entitlements: EntitlementStore
    let scheduler = Scheduler()
    let sessionBuilder = SessionBuilder()

    /// Where Task 6's bundled `manifest.json` + `fr.pack.json` live at runtime.
    static var bundledPacksDirectory: URL {
        Bundle.main.resourceURL?.appending(path: "packs")
            ?? URL(fileURLWithPath: Bundle.main.bundlePath).appending(path: "packs")
    }

    /// The seam integration tests use: same wiring as `live()`, but pointed at a
    /// temp packs directory and an in-memory store.
    static func make(packsDirectory: URL, inMemory: Bool) throws -> AppDependencies {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(
            for: PersistentReviewState.self, configurations: configuration)
        return AppDependencies(
            packStore: JSONPackStore(packsDirectory: packsDirectory),
            reviewStore: SwiftDataReviewStore(modelContainer: container),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: NoPurchasesEntitlementStore())
    }

    /// Throws rather than crashes: opening the SwiftData store can fail on a full
    /// or corrupt disk, and NFR-10 forbids a crash on bad data.
    static func live() throws -> AppDependencies {
        try make(packsDirectory: bundledPacksDirectory, inMemory: false)
    }
}
```

- [ ] **Step 2: Delete the sample pack**

```bash
git rm FullDeck/FullDeck/SamplePack.swift
```

- [ ] **Step 3: Handle the failure in `FullDeckApp`**

Replace the body of `FullDeckApp`:

```swift
@main
struct FullDeckApp: App {
    /// The composition root: dependencies are constructed here, once, and
    /// injected downward. Nothing below reaches for a global. Construction can
    /// fail (the SwiftData store may not open), and NFR-10 says that is a state,
    /// never a crash.
    @State private var dependencies: Result<AppDependencies, Error> = Result {
        try AppDependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            switch dependencies {
            case .success(let dependencies):
                ContentView(dependencies: dependencies)
            case .failure:
                ErrorStateView(message: "Couldn't open your saved progress.")
            }
        }
    }
}
```

`Result { }`'s initializer runs the closure immediately, so this is still one construction at launch.

- [ ] **Step 4: Fix the preview**

At the bottom of `ContentView.swift`, `#Preview` calls `.live()`, which now throws. Replace it:

```swift
#Preview {
    // The preview shares the app's real wiring; if the store can't open there is
    // nothing to preview, so a failure here is a preview-only crash, not shipped.
    // swiftlint:disable:next force_try
    ContentView(dependencies: try! AppDependencies.live())
}
```

`force_try` is on by default and CI runs `--strict`, so the disable comment is required, not optional. Suppress the one line; do not touch `.swiftlint.yml`.

- [ ] **Step 5: Build and run the suite**

Run the `xcodebuild test` command from Task 2.
Expected: builds clean, all tests PASS. Existing ViewModel tests are unaffected — they build their own in-memory doubles and never touch `AppDependencies`.

- [ ] **Step 6: Run the app in the simulator and confirm real data**

Launch the app and confirm the Languages tab lists **Français**, selecting it starts a session, and the first card is a top-frequency French word (rank 1 is `de`) rather than `chat` from the deleted sample pack.

- [ ] **Step 7: Commit**

```bash
git add FullDeck/FullDeck
git commit -m "feat(app): wire JSONPackStore and SwiftDataReviewStore into the composition root"
```

---

### Task 8: Persist the active language across launches

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift`
- Test: `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift`

**Interfaces:**
- Consumes: `PackStore.availablePacks()`.
- Produces: `LanguageSelectionViewModel.init(packStore:entitlements:defaults:)` — `defaults: UserDefaults = .standard`. `ContentView` keeps calling the two-argument form.

`UserDefaults` is injected directly rather than hidden behind a new protocol: it is already an injectable dependency, and a protocol with one real implementation wrapping a type that is itself injectable is ceremony.

- [ ] **Step 1: Write the failing restore test**

Append to `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift`:

```swift
/// A throwaway suite so a test never reads or writes the simulator's real
/// defaults. Fixed name (not a UUID) and wiped on entry, so runs are repeatable.
private func emptyDefaults() -> UserDefaults {
    let suite = "com.fulldeck.tests.languageSelection"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    return UserDefaults(suiteName: suite)!
}

@Test("FR-9 the active language is restored on the next launch")
@MainActor
func activeLanguageIsRestoredOnNextLaunch() async {
    let defaults = emptyDefaults()
    let packStore = InMemoryPackStore(descriptors: [frDescriptor()], packs: [:])

    let first = LanguageSelectionViewModel(
        packStore: packStore, entitlements: StubEntitlementStore(), defaults: defaults)
    await first.load()
    guard case .ready(let options) = first.state, let option = options.first else {
        Issue.record("expected a ready state with one option")
        return
    }
    first.select(option)

    let second = LanguageSelectionViewModel(
        packStore: packStore, entitlements: StubEntitlementStore(), defaults: defaults)
    await second.load()

    #expect(second.activeLanguage == LanguageCode("fr"))
}

@Test("FR-9 a persisted language that is no longer available is not restored")
@MainActor
func unavailablePersistedLanguageIsNotRestored() async {
    let defaults = emptyDefaults()
    defaults.set("hi", forKey: "activeLanguageCode")
    let viewModel = LanguageSelectionViewModel(
        packStore: InMemoryPackStore(descriptors: [frDescriptor()], packs: [:]),
        entitlements: StubEntitlementStore(), defaults: defaults)

    await viewModel.load()

    #expect(viewModel.activeLanguage == nil)
}
```

- [ ] **Step 2: Run and confirm the missing parameter**

Run the `xcodebuild test` command from Task 2.
Expected: compile failure — no `defaults:` parameter.

- [ ] **Step 3: Add the dependency**

In `LanguageSelectionViewModel.swift`, add `import Foundation` at the top, then:

```swift
    private let defaults: UserDefaults
    private static let activeLanguageKey = "activeLanguageCode"

    init(packStore: PackStore, entitlements: EntitlementStore, defaults: UserDefaults = .standard) {
        self.packStore = packStore
        self.entitlements = entitlements
        self.defaults = defaults
    }
```

- [ ] **Step 4: Re-run for the real red**

Run the `xcodebuild test` command.
Expected: `activeLanguageIsRestoredOnNextLaunch` FAILS — `activeLanguage` is `nil`. `unavailablePersistedLanguageIsNotRestored` passes (nothing restores anything yet).

- [ ] **Step 5: Persist on select**

At the end of `select(_:)`:

```swift
        defaults.set(option.descriptor.languageCode.rawValue, forKey: Self.activeLanguageKey)
```

- [ ] **Step 6: Restore on load**

In `load()`, inside the `do` block after `state = .ready(...)`:

```swift
            // Honored only if the pack is still listed: a pack removed between
            // launches must not leave the app pointing at nothing (FR-9).
            if activeLanguage == nil,
                let saved = defaults.string(forKey: Self.activeLanguageKey),
                descriptors.contains(where: { $0.languageCode.rawValue == saved })
            {
                activeLanguage = LanguageCode(saved)
            }
```

- [ ] **Step 7: Run**

Run the `xcodebuild test` command.
Expected: both new tests PASS, and the five existing `LanguageSelectionViewModel` tests still PASS — they construct the ViewModel without `defaults:`, which now defaults to `.standard`.

- [ ] **Step 8: Update the stale comment**

`ContentView.swift:5` says persisting the active language "is Phase 9". Change it to record what now happens:

```swift
/// Root shell: one tab per v1 screen. Which language is active is owned by
/// `LanguageSelectionViewModel` and persisted across launches there.
```

- [ ] **Step 9: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift FullDeck/FullDeck/ContentView.swift FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift
git commit -m "feat(app): persist the active language across launches"
```

---

### Task 9: Integration tests across the seams

**Files:**
- Create: `FullDeck/FullDeckTests/IntegrationTests.swift`

**Interfaces:**
- Consumes: `AppDependencies.make(packsDirectory:inMemory:)` and `AppDependencies.bundledPacksDirectory` (Task 7), `StudyViewModel`, `ProgressViewModel`, the `Fakes.swift` helpers.

These are framework glue, so they are written alongside rather than strictly first. Real `JSONPackStore` over a temp directory, real `SwiftDataReviewStore` on an in-memory container, real `Scheduler` and `SessionBuilder`, real ViewModels. Only `DayClock` and `SpeechService` stay fakes — the first because the determinism gate forbids the wall clock, the second because there is no audio in a test run.

- [ ] **Step 1: Write the fixture helper**

Create `FullDeck/FullDeckTests/IntegrationTests.swift`:

```swift
import Domain
import Foundation
import Testing

@testable import FullDeck

// The fixture builder below reshapes the bundled pack as untyped JSON, which needs
// two casts. `force_cast` is a default rule and CI runs --strict, so the file
// disables it rather than wrapping test-fixture plumbing in ten lines of ceremony.
// swiftlint:disable force_cast

/// Writes a real packs directory to a temp location by truncating the bundled
/// French pack to its first `wordCount` entries. Truncation keeps every rule the
/// Swift validator checks: ranks stay 1...n and unique, ids stay unique, and
/// `word_count` is rewritten to match (VR-2). Hand-writing a fixture would risk
/// tripping a rule the plan can't foresee; real data can't.
@MainActor
private func makeTempPacksDirectory(wordCount: Int) throws -> URL {
    let source = AppDependencies.bundledPacksDirectory.appending(path: "fr.pack.json")
    var pack = try JSONSerialization.jsonObject(with: Data(contentsOf: source))
        as! [String: Any]
    let words = (pack["words"] as! [[String: Any]]).prefix(wordCount)
    pack["words"] = Array(words)
    pack["word_count"] = words.count

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "packs-\(wordCount)-\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: pack)
        .write(to: directory.appending(path: "fr.pack.json"))
    try JSONSerialization.data(withJSONObject: [
        "packs": [[
            "language_code": "fr", "display_name": "Français",
            "filename": "fr.pack.json", "unlocked_by_default": true,
        ]]
    ]).write(to: directory.appending(path: "manifest.json"))
    return directory
}

@MainActor
private func makeStudy(
    _ dependencies: AppDependencies, today: Date, newWordCap: Int = 10
) -> StudyViewModel {
    StudyViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore, scheduler: dependencies.scheduler,
        sessionBuilder: dependencies.sessionBuilder, speech: FakeSpeechService(),
        clock: FixedDayClock(today: today), newWordCap: newWordCap)
}
```

- [ ] **Step 2: Write the bundled-pack smoke test**

```swift
@Test("FR-1 the bundled French pack loads and reports 1000 words")
@MainActor
func bundledFrenchPackLoads() async throws {
    let dependencies = try AppDependencies.make(
        packsDirectory: AppDependencies.bundledPacksDirectory, inMemory: true)

    let pack = try await dependencies.packStore.loadPack(LanguageCode("fr"))

    #expect(pack.wordCount == 1000)
    #expect(pack.words.count == 1000)
    #expect(pack.words.first?.rank == 1)
}
```

- [ ] **Step 3: Run it**

Run the `xcodebuild test` command from Task 2.
Expected: PASS. If it fails with `fileNotFound`, Task 6 Step 4's bundle check was skipped — go back and confirm the resources copy.

- [ ] **Step 4: Write the full-session-plus-relaunch test**

```swift
@Test("FR-9 grades persist through the real store and survive a relaunch")
@MainActor
func gradesPersistAcrossRelaunch() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 5)
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)
    let study = makeStudy(dependencies, today: day0, newWordCap: 3)

    await study.start()
    for _ in 0..<3 {
        study.reveal()
        await study.grade(.good)
    }

    // "Relaunch": a brand-new ViewModel over the same store.
    let progress = ProgressViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore)
    await progress.load()

    let states = try await dependencies.reviewStore.allStates(LanguageCode("fr"))
    #expect(states.count == 3)
    #expect(states.allSatisfy { $0.firstReviewedDate == day0 })
    #expect(progress.state == .ready(learned: 0, total: 5))
}
```

Three words graded `.good` on day 0 land at `intervalDays == 1`, well under `L` — so `learned` is 0. That is the point: the first pass does not make a word learned.

- [ ] **Step 5: Run it**

Run the `xcodebuild test` command.
Expected: PASS.

- [ ] **Step 6: Write the completion test**

```swift
@Test("FR-11 a pack studied to the learned threshold reaches the completion state")
@MainActor
func studyingToThresholdReachesCompletion() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 3)
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)

    // Three passes take every word to interval 15 (1 → 6 → 15), crossing L = 14
    // on the third. Reviews land on day 0, day 1, and day 7.
    for reviewDay in [0, 1, 7] {
        let study = makeStudy(dependencies, today: day(reviewDay), newWordCap: 3)
        await study.start()
        while case .card = study.state {
            study.reveal()
            await study.grade(.good)
        }
    }

    let progress = ProgressViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore)
    await progress.load()
    #expect(progress.state == .ready(learned: 3, total: 3))
    #expect(progress.state.isComplete)

    let afterwards = makeStudy(dependencies, today: day(8), newWordCap: 3)
    await afterwards.start()
    #expect(afterwards.state == .complete(nextDue: day(22)))
}
```

- [ ] **Step 7: Run it**

Run the `xcodebuild test` command.
Expected: PASS. If `learned` reads 0, Task 1's threshold is not being reached — print the states' `intervalDays` and check the ladder (1, 6, 15) held.

- [ ] **Step 8: Write the two robustness tests**

```swift
@Test("NFR-10 a corrupt pack surfaces a failed state instead of crashing")
@MainActor
func corruptPackSurfacesFailedState() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 3)
    try Data("{ not json".utf8).write(to: directory.appending(path: "fr.pack.json"))
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)

    let study = makeStudy(dependencies, today: day0)
    await study.start()

    #expect(study.state == .failed("Couldn't load this language."))
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedState() async throws {
    let directory = try makeTempPacksDirectory(wordCount: 3)
    try FileManager.default.removeItem(at: directory.appending(path: "fr.pack.json"))
    let dependencies = try AppDependencies.make(packsDirectory: directory, inMemory: true)

    let progress = ProgressViewModel(
        languageCode: LanguageCode("fr"), packStore: dependencies.packStore,
        reviewStore: dependencies.reviewStore)
    await progress.load()

    #expect(progress.state == .failed("Couldn't load your progress."))
}
```

- [ ] **Step 9: Run the whole app suite**

Run the `xcodebuild test` command.
Expected: every test PASSES.

- [ ] **Step 10: Re-enable the lint rule at the end of the file**

Add as the last line of `IntegrationTests.swift`:

```swift
// swiftlint:enable force_cast
```

- [ ] **Step 11: Commit**

```bash
git add FullDeck/FullDeckTests/IntegrationTests.swift
git commit -m "test(app): add integration tests across the domain, data and presentation seams"
```

---

### Task 10: Gates, docs, and the phase self-review

**Files:**
- Modify: `docs/next-task.md`

- [ ] **Step 1: Run every gate CI runs**

```bash
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
scripts/determinism-check.sh
swiftlint lint --strict
```

Expected: all pass. `determinism-check.sh` is the one most likely to bite — it greps test sources for `Date()`, `Date.now`, sleeps, and unseeded `.random(`. `IntegrationTests.swift` uses `ProcessInfo.processInfo.globallyUniqueString` rather than `UUID()` partly for readability; if the gate objects to anything, replace the offending call rather than loosening the script.

- [ ] **Step 2: Run the app suite once more**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 3: Check requirement traceability**

```bash
scripts/trace-requirements.sh
```

Report-only, never blocks. FR-9, FR-10, FR-11 and FR-12 should now all show covering tests. Note any that do not.

- [ ] **Step 4: Update the living task doc**

In `docs/next-task.md`, rewrite the "Right now" block to name the next task — Phase 10 (accessibility audit, error→state mapping, offline verification, localization catalog, observability decision) on **Sonnet 5, default effort** — and shift the "Then" table up by one row.

- [ ] **Step 5: Report the tech debt**

`CLAUDE.md` requires a self-review pass naming knowingly-left debt at the end of each phase. At minimum:
- `pipeline/packs/fr.pack.json` and the bundled copy can drift; a `scripts/sync-packs.sh` waits for Phase 12 when Hindi makes it two packs.
- The Languages tab shows one row until Phase 12.
- Completion-screen copy is provisional pending Phase 10's localization catalog.
- The app target still compiles in Swift 5 mode; the strict-concurrency migration is Phase 10.

- [ ] **Step 6: Commit**

```bash
git add docs/next-task.md
git commit -m "docs: point the task doc at Phase 10"
```
