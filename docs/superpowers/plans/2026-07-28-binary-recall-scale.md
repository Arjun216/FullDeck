# Binary Recall Scale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four-level recall grade (Again / Hard / Good / Easy) with a binary one (`forgot` / `recalled`), and give `recalled` a positive ease delta so ease can recover instead of only decaying.

**Architecture:** Two commits by design. Task 1 is a repo-wide *refactor* — it renames and deletes enum cases while preserving the scheduling behaviour of the cases that survive, so every surviving test keeps its exact expected values. Task 2 is the one genuine *behaviour change*, driven test-first: `recalled` moves from a 0 ease delta to +0.05. Separating them means Task 2 produces a real red for a real reason, which a combined change could not.

**Tech Stack:** Swift 6 (Domain package, `swiftLanguageModes: [.v6]`), Swift Testing (`@Test` / `#expect`), XCUITest, Xcode String Catalog (`.xcstrings`).

**Spec:** `docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md` (Decision 1).

## Global Constraints

- Test display names start with the requirement ID they verify — e.g. `@Test("FR-8 ...")`. Enforced culturally; reported by `scripts/trace-requirements.sh`.
- No test may read `Date()`, sleep, or use unseeded randomness. `scripts/determinism-check.sh` greps for these and fails CI.
- Coverage floors are hard CI failures: Domain ≥ 90%, Data ≥ 80%.
- Builds compile with warnings-as-errors. An unused constant is a build failure, not a warning — `hardMultiplier` must be deleted, not left behind.
- SwiftLint runs with `--strict`. Zero violations.
- Conventional commits, small and focused.
- The enum case order is load-bearing: `forgot` is declared first so `Grade.allCases` renders fail-left / pass-right, matching the swipe direction planned for Phase C.
- User-facing labels are exactly `Knew it!` and `Let's try this again` — chosen by the product owner over the recommended alternative. Do not "fix" the exclamation mark or the asymmetric length.

---

### Task 1: Reduce `Grade` to two cases, repo-wide

A rename plus a deletion, applied atomically across Domain and the app target. The app target will not compile if the enum changes without its call sites, so this is one commit, not two.

Behaviour preserved: `forgot` behaves exactly as `again` did (−0.20 ease, interval reset). `recalled` behaves exactly as `good` did (**0 ease delta for now** — the +0.05 lands in Task 2). Every surviving test therefore keeps its current expected values unchanged.

Behaviour deleted: the `hard` fixed-step interval and the `easy` positive delta, along with the two tests that covered them.

**Files:**
- Modify: `Packages/Domain/Sources/Domain/Models.swift:32-38`
- Modify: `Packages/Domain/Sources/Domain/Scheduler.swift:20`, `:31-63`
- Modify: `Packages/Domain/Tests/DomainTests/SchedulerTests.swift`
- Modify: `FullDeck/FullDeck/Views/StudyView.swift:126-145`
- Modify: `FullDeck/FullDeck/Localizable.xcstrings`
- Modify: `FullDeck/FullDeckTests/StudyViewModelTests.swift`
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift:111`

**Interfaces:**
- Consumes: nothing — first task.
- Produces: `Domain.Grade` with exactly two cases, `case forgot` then `case recalled`. `Scheduler.schedule(_ state: ReviewState, grade: Grade, today: Date) -> ReviewState` keeps its signature. `Scheduler.hardMultiplier` no longer exists.

- [ ] **Step 1: Replace the enum**

In `Packages/Domain/Sources/Domain/Models.swift`, replace lines 32–38:

```swift
/// The learner's self-assessment after revealing a card (FR-5).
///
/// Binary by decision (spec 2026-07-28): a four-way judgement cost decision time
/// at exactly the moment the learner should be thinking about the word. `forgot`
/// is declared first so `allCases` renders fail-left / pass-right.
public enum Grade: Sendable, CaseIterable {
    case forgot
    case recalled
}
```

- [ ] **Step 2: Rework the scheduler**

In `Packages/Domain/Sources/Domain/Scheduler.swift`, delete line 20 entirely:

```swift
    static let hardMultiplier = 1.2
```

Then replace the body of `schedule` (lines 31–63) with:

```swift
    public func schedule(_ state: ReviewState, grade: Grade, today: Date) -> ReviewState {
        var next = state
        let easeDelta: Double =
            switch grade {
            case .forgot: -0.20
            case .recalled: 0
            }
        next.easeFactor = (state.easeFactor + easeDelta).clamped(to: Self.easeRange)
        // Reset-on-failure (FR-8): a lapse sends the word back to the bottom of
        // the ladder — tomorrow, and the fixed steps again from there.
        next.repetitions = grade == .forgot ? 0 : state.repetitions + 1
        // SM-2's ladder: the first two passes use fixed steps, after which the
        // ease factor takes over and intervals grow multiplicatively.
        let interval =
            switch (grade, state.repetitions) {
            case (.forgot, _): 1
            case (_, 0): 1
            case (_, 1): 6
            default: Int((Double(state.intervalDays) * next.easeFactor).rounded())
            }
        next.intervalDays = interval.clamped(to: Self.intervalRange)
        // Derived from the *clamped* interval — the two must never disagree.
        next.nextReviewDate = DayCalendar.adding(days: next.intervalDays, to: today)
        return stampingMilestones(on: next, previous: state, today: today)
    }
```

Note the `.hard` interval case is gone, and with it the comment about departing from textbook SM-2 — that departure existed only to stop `hard` misbehaving.

- [ ] **Step 3: Update the scheduler tests — mechanical renames**

In `Packages/Domain/Tests/DomainTests/SchedulerTests.swift`, replace every `grade: .good` with `grade: .recalled` and every `grade: .again` with `grade: .forgot`. That covers these tests, whose expected values all stay **exactly as they are**:

`firstPassingReviewSchedulesOneDay`, `secondPassingReviewSchedulesSixDays`, `passingGradeIncrementsRepetitions`, `matureIntervalMultipliesByEaseFactor`, `failingGradeResetsIntervalAndRepetitions`, `intervalNeverGrowsPastCeiling`, `belowLearnedIntervalIsNotLearned`, `crossingLearnedIntervalStampsLearnedDate`, `lapseDoesNotUnlearnWord`, `laterReviewDoesNotRestampLearnedDate`, `firstReviewStampsFirstReviewedDate`, `laterReviewLeavesFirstReviewedDateAlone`.

In `belowLearnedIntervalIsNotLearned`, also update the stale comment on line 138 — it referenced a `.hard` grade that no longer exists:

```swift
    // Ease 2.2 — a word that has lapsed before. 6 × 2.2 = 13.2 → 13, one short.
```

In the invariant walk `schedulingInvariantsHoldAcrossSeededRandomWalk`, change the failing-grade guard on line 250:

```swift
        if grade == .forgot {
```

- [ ] **Step 4: Update the ease-delta table test**

Replace `gradeMovesEaseFactorByItsDelta` (lines 70–85) with:

```swift
@Test(
    "FR-8 each grade moves the ease factor by its own delta",
    arguments: [
        (Grade.forgot, 2.30),
        (Grade.recalled, 2.50),
    ])
func gradeMovesEaseFactorByItsDelta(grade: Grade, expectedEase: Double) {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: grade, today: day(7))

    #expect(abs(next.easeFactor - expectedEase) < 1e-9)
}
```

- [ ] **Step 5: Reduce the clamp test to its floor case**

`recalled` currently carries a 0 delta, so ease cannot rise and the ceiling case has nothing to exercise. Replace `easeFactorStaysInsideItsClamps` (lines 87–101) with:

```swift
@Test("FR-8 repeated failures cannot drive the ease factor below its floor")
func easeFactorStaysAboveItsFloor() {
    let state = ReviewState(
        wordID: chat, easeFactor: 1.35, intervalDays: 10, repetitions: 3,
        nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: .forgot, today: day(10))

    #expect(abs(next.easeFactor - 1.30) < 1e-9)
}
```

The ceiling case is restored in Task 2, once `recalled` can actually raise ease.

- [ ] **Step 6: Delete the two tests for deleted behaviour**

Delete `hardGradeGrowsIntervalBySmallStep` (lines 103–111) and `gradeSchedulesWithTheEaseItJustChanged` (lines 113–121) in full. The first covers the `hard` fixed step, which no longer exists. The second proved scheduling uses the *just-updated* ease — meaningless while `recalled`'s delta is 0, and restored in Task 2.

- [ ] **Step 7: Run the Domain tests**

Run: `swift test --package-path Packages/Domain`
Expected: PASS. This is a refactor — if any surviving test's numbers moved, the refactor was not behaviour-preserving and something above is wrong.

- [ ] **Step 8: Update the study view**

In `FullDeck/FullDeck/Views/StudyView.swift`, replace `gradeButtons` and `label(for:)` (lines 126–145) with:

```swift
    private var gradeButtons: some View {
        HStack(spacing: 12) {
            ForEach(Grade.allCases, id: \.self) { grade in
                Button(label(for: grade)) {
                    Task { await viewModel.grade(grade) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func label(for grade: Grade) -> String {
        switch grade {
        case .forgot: String(localized: "Let's try this again")
        case .recalled: String(localized: "Knew it!")
        }
    }
```

The `.accessibilityLabel("Grade this word \(label(for: grade))")` is deliberately removed. With four terse labels it disambiguated; with these two it would produce "Grade this word Let's try this again", which reads worse than the button's own text. A `Button` with a text label already exposes that text to VoiceOver, so the audit still passes.

- [ ] **Step 9: Update the string catalog**

In `FullDeck/FullDeck/Localizable.xcstrings`, delete these five entries in full: `"Again"`, `"Hard"`, `"Good"`, `"Easy"`, and `"Grade this word %@"`.

Add these two in their place:

```json
    "Knew it!" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "¡Lo sabía!" } }
      }
    },
    "Let's try this again" : {
      "localizations" : {
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Volvamos a intentarlo" } }
      }
    },
```

Validate the file parses before building — `plutil -lint` rejects `.xcstrings` despite it being valid JSON, so use:

Run: `python3 -m json.tool FullDeck/FullDeck/Localizable.xcstrings > /dev/null && echo VALID`
Expected: `VALID`

- [ ] **Step 10: Update the ViewModel tests**

In `FullDeck/FullDeckTests/StudyViewModelTests.swift`, replace every `viewModel.grade(.good)` with `viewModel.grade(.recalled)`. There are ten occurrences, on lines 99, 118, 134, 148, 164, 226, 227, 250, 262 and 359.

- [ ] **Step 11: Update the UI test**

In `FullDeck/FullDeckUITests/FullDeckUITests.swift`, line 111, replace:

```swift
        app.buttons["Grade this word Good"].tap()
```

with:

```swift
        app.buttons["Knew it!"].tap()
```

- [ ] **Step 12: Run the full suite**

Run:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `** TEST SUCCEEDED **`.

Do **not** trust that line alone — confirm a real test count from the `.xcresult` path it prints:

```bash
xcrun xcresulttool get test-results summary --path <path-from-output>
```

Expected: `"result": "Passed"` with `totalTestCount` of 53. A `totalTestCount` of 0 means the run was hollow; re-run the full target without any `-only-testing:` filter.

- [ ] **Step 13: Commit**

```bash
git add Packages/Domain FullDeck
git commit -m "refactor: reduce the recall grade to forgot and recalled

Four-way grading cost decision time at exactly the moment the learner
should be thinking about the word. Drops hard and easy: hard existed
only with a workaround for textbook SM-2 lengthening the interval of a
word you found difficult, and easy was near-inert because the first two
repetitions use fixed steps regardless of grade.

Behaviour-preserving for the cases that survive — forgot schedules as
again did, recalled as good did — so every surviving test keeps its
expected values. The ease delta change is a separate commit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Let `recalled` raise the ease factor

The one genuine behaviour change, and the reason the spec calls it required rather than optional. With `recalled` at a 0 delta, `easeFactor` can only ever move downward — every lapse ratchets it toward the 1.3 floor with no path back. That is Anki's documented "ease hell", and a word that lapsed early would be permanently punished for it.

**Files:**
- Modify: `Packages/Domain/Sources/Domain/Scheduler.swift`
- Modify: `Packages/Domain/Tests/DomainTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `Domain.Grade` with cases `forgot` and `recalled`, and `Scheduler.schedule(_:grade:today:)`, both from Task 1.
- Produces: no signature change. `recalled` now applies a +0.05 ease delta.

- [ ] **Step 1: Write the failing test**

Append to `Packages/Domain/Tests/DomainTests/SchedulerTests.swift`:

```swift
@Test("FR-8 a successful recall lifts the ease factor back off its floor")
func recalledLiftsEaseOffItsFloor() {
    // A word driven to the floor by past lapses. If `recalled` carried a zero
    // delta, ease could only ever decay — the word would be punished forever
    // for lapses it has since recovered from.
    let state = ReviewState(
        wordID: chat, easeFactor: 1.30, intervalDays: 4, repetitions: 2, nextReviewDate: day(4))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(4))

    #expect(next.easeFactor > state.easeFactor)
    #expect(abs(next.easeFactor - 1.35) < 1e-9)
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

Run: `swift test --package-path Packages/Domain --filter recalledLiftsEaseOffItsFloor`
Expected: FAIL. The failure must be `next.easeFactor > state.easeFactor` being false, with ease still 1.30 — the behaviour is genuinely missing. A compile error is not a red; fix it and re-run until it fails for this reason.

- [ ] **Step 3: Give `recalled` its positive delta**

In `Packages/Domain/Sources/Domain/Scheduler.swift`, change the delta table:

```swift
        // Binary scale (spec 2026-07-28): `recalled` must carry a *positive*
        // delta, not zero. At zero, ease could only ever decay toward its floor
        // — Anki's "ease hell" — and a word that lapsed once could never
        // recover from it.
        let easeDelta: Double =
            switch grade {
            case .forgot: -0.20
            case .recalled: 0.05
            }
```

- [ ] **Step 4: Run the new test**

Run: `swift test --package-path Packages/Domain --filter recalledLiftsEaseOffItsFloor`
Expected: PASS.

- [ ] **Step 5: Run the whole Domain suite and expect exactly two failures**

Run: `swift test --package-path Packages/Domain`
Expected: FAIL in exactly these two places — each is a test whose arithmetic genuinely shifts because ease now rises. Steps 6 and 7 fix them. Any *third* failure means something unintended moved; stop and investigate rather than adjusting numbers to fit.

1. `gradeMovesEaseFactorByItsDelta` — `recalled` now yields 2.55, not 2.50.
2. `belowLearnedIntervalIsNotLearned` — ease 2.2 becomes 2.25, so 6 × 2.25 = 13.5 rounds to **14**, which crosses the 14-day learned threshold the test asserts is *not* crossed.

These four are unaffected and must keep their existing expected values — if any of them moves, the change was wrong: `matureIntervalMultipliesByEaseFactor` (6 × 2.55 = 15.3 → 15), `crossingLearnedIntervalStampsLearnedDate` (→ 15), `laterReviewDoesNotRestampLearnedDate` (15 × 2.55 = 38.25 → 38), `intervalNeverGrowsPastCeiling` (capped at 365).

- [ ] **Step 6: Update the ease-delta table test**

```swift
@Test(
    "FR-8 each grade moves the ease factor by its own delta",
    arguments: [
        (Grade.forgot, 2.30),
        (Grade.recalled, 2.55),
    ])
func gradeMovesEaseFactorByItsDelta(grade: Grade, expectedEase: Double) {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: grade, today: day(7))

    #expect(abs(next.easeFactor - expectedEase) < 1e-9)
}
```

- [ ] **Step 7: Re-pitch the below-threshold test**

The test needs a word whose post-recall interval still lands under 14 days. Ease 2.15 becomes 2.20, and 6 × 2.20 = 13.2 → 13. Replace `belowLearnedIntervalIsNotLearned` with:

```swift
@Test("FR-10 a word that lands below the learned interval is not learned")
func belowLearnedIntervalIsNotLearned() {
    // Ease 2.15 — a word that has lapsed before. Recalling lifts it to 2.20,
    // and 6 × 2.20 = 13.2 → 13, one day short of the threshold.
    let state = ReviewState(
        wordID: chat, easeFactor: 2.15, intervalDays: 6, repetitions: 2,
        nextReviewDate: day(7), firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .recalled, today: day(7))

    #expect(next.intervalDays == 13)
    #expect(next.learnedDate == nil)
}
```

- [ ] **Step 8: Restore the ceiling clamp and the fresh-ease tests**

`recalled` can raise ease again, so both tests deleted in Task 1 now have something to assert. Append:

```swift
@Test("FR-8 repeated successes cannot drive the ease factor past its ceiling")
func easeFactorStaysBelowItsCeiling() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.98, intervalDays: 10, repetitions: 3,
        nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(10))

    #expect(abs(next.easeFactor - 3.00) < 1e-9)
}

@Test("FR-8 a grade schedules with the ease it just changed, not the old one")
func gradeSchedulesWithTheEaseItJustChanged() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 10, repetitions: 3, nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(10))

    #expect(next.intervalDays == 26)  // 10 × 2.55 (raised ease), not 10 × 2.5 = 25
}
```

- [ ] **Step 9: Run the Domain suite and the coverage gate**

```bash
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
scripts/determinism-check.sh
```

Expected: all tests pass, coverage at or above 90%, determinism check silent (exit 0).

- [ ] **Step 10: Run the full app suite**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
swiftlint lint --strict
```

Expected: `** TEST SUCCEEDED **` with a verified non-zero test count, and zero lint violations.

- [ ] **Step 11: Commit**

```bash
git add Packages/Domain
git commit -m "fix: let a successful recall raise the ease factor

With recalled carrying a zero ease delta, easeFactor could only ever
decay toward its 1.3 floor — Anki's 'ease hell'. A word that lapsed
early would stay punished for it no matter how reliably it was recalled
afterwards. A +0.05 delta gives it a path back.

Two dependent tests shift with it: the delta table, and the
below-threshold learned test, which needed a lower starting ease to
still land under 14 days once recall lifts it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Record the change in the project docs

This work is not in the original 14-phase build plan and displaces the immediate Phase 11 start. Both living documents need to say so, or the next session picks up a stale instruction.

**Files:**
- Modify: `docs/build-plan.md`
- Modify: `docs/next-task.md:13-49`

**Interfaces:**
- Consumes: the completed work of Tasks 1 and 2.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the redesign to the build plan**

In `docs/build-plan.md`, immediately after the `## PHASE 10 — Cross-Cutting Concerns` section and before `## PHASE 11`, insert:

```markdown
## PHASE 10.5 — Recall Scale & Visual Design (inserted 2026-07-28)

Not in the original plan. Added after reviewing the app on device.

Spec: `docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md`

1. **Binary recall scale** — `Grade` reduces from four cases to `forgot` /
   `recalled`; `recalled` gains a positive ease delta so ease can recover.
2. **Warm minimal token layer** — semantic colorsets and a spacing scale,
   replacing the empty `AccentColor` that left every control system blue.
3. **Swipe to grade** — right for recalled, left for forgot, with both buttons
   retained as the accessible path.

`docs/requirements.md` already parameterised the grade scale as "4-level vs.
binary", so no requirement changes.
```

- [ ] **Step 2: Update the "Right now" block**

In `docs/next-task.md`, replace the `## Right now` block (lines 13–49) with:

```markdown
## Right now

**Task:** Phase 10.5 part 2 — warm minimal token layer
**Model:** Sonnet 5, default effort
**Why Sonnet:** the palette, contrast ratios and token names are all settled in
the spec — this is a diff, not a decision.

Phase 10.5 part 1 shipped: the recall scale is binary. `Grade` is now
`forgot` / `recalled`; the `hard` fixed-step interval and its
departs-from-SM-2 workaround are gone, as is the near-inert `easy` case.
`recalled` carries a +0.05 ease delta — required, not cosmetic: at zero
the ease factor could only ever decay toward its floor, so a word that
lapsed early could never recover. Persistence stores `ReviewState` and
never the grade, so no migration was needed.

**Next:** the token layer (spec Decision 2), then swipe-to-grade
(Decision 3). Phase 11 (StoreKit) follows after.

**Carried forward from Phase 10:** the completion and caught-up screens
are still never reached by the automated accessibility audit, and the two
manual checklists in `docs/phase-10-verification.md` (airplane-mode
session, VoiceOver/Dynamic Type walkthrough) still need Arjun on a real
device.
```

- [ ] **Step 3: Renumber the "Then" table**

In the same file, replace the `## Then` table rows with:

```markdown
| # | Task | Model | Effort |
|---|---|---|---|
| 1 | Phase 10.5 part 3 — swipe to grade | Sonnet 5 | default |
| 2 | Phase 11 design — StoreKit 2 purchase/entitlement state machine | Opus 5 | xhigh |
| 3 | Phase 11 execution (StoreKitTest, sandbox) | Sonnet 5 | default |
| 4 | Phase 12 — Hindi pack generation, architecture-validation verdict | Opus 5 (verdict) / Sonnet 5 (pipeline runs) | high / default |
```

- [ ] **Step 4: Commit**

```bash
git add docs/build-plan.md docs/next-task.md
git commit -m "docs: record the binary recall scale and point at the token layer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Verification

After Task 3, the full gate suite must be green on the branch:

```bash
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
scripts/determinism-check.sh
swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

The Data package is untouched by this plan but is part of the gate — run it to confirm that stays true.

## Known trap

`xcodebuild test` with an `-only-testing:` filter can print `** TEST SUCCEEDED **` and exit 0 while running **zero** tests, due to a stale test-plan cache (seen in Phase 10 after repeated `DerivedData` wipes). Always run the full target, and confirm `totalTestCount` from the `.xcresult` rather than trusting the exit code.
