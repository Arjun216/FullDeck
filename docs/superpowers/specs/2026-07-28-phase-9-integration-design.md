# Phase 9 — Integration & the "Done" State: Design

**Phase:** 9 (Integration & the "Done" state) · **Status:** Approved for planning · **Date:** 2026-07-28

This is the design for two things the build plan pairs in one phase: the definition of
**`L`** — what makes a single word "learned" — and the wiring that replaces every Phase 8
fake with the real Phase 6/7 implementations, tested by integration tests across the seams.

Builds on: `build-plan.md` PHASE 9, `requirements.md` FR-9/FR-10/FR-11/FR-12/FR-17 and
NFR-10/NFR-11, the Phase 5 `Scheduler`, the Phase 7 `JSONPackStore` + `SwiftDataReviewStore`,
and the Phase 8 ViewModels.

---

## Scope

**In scope:**

- Domain: the learned rule `L`, and milestone stamping (`firstReviewedDate`, `learnedDate`)
  moved into `Scheduler.schedule`.
- Presentation: a `.complete` state on `StudyViewModel` and `ProgressViewModel`, and the
  completion screen.
- Composition root: real `JSONPackStore` + `SwiftDataReviewStore`; `SamplePack` deleted;
  the 1000-word French pack bundled as an app resource.
- Persisting the active language across launches (deferred here from Phase 8).
- Integration tests in `FullDeckTests` running real Data adapters against real Domain.

**Out of scope (explicitly deferred):**

- The actual purchase. The completion screen's primary button routes to the Languages tab;
  StoreKit is Phase 11 behind the existing `EntitlementStore` port.
- Hindi in the production manifest — its pack does not exist until Phase 12 (see §3.2).
- User-facing error copy and the accessibility audit (Phase 10), visual design (Phase 13).
- FR-17's progress trend. `learnedDate` becomes real in this phase, which is what FR-17
  will later read; the trend view itself is not built here.

---

## 1. The learned rule `L`

### 1.1 The decision

**`L` = `intervalDays >= 14`**, evaluated on the state the scheduler just produced.
**Sticky**: once `learnedDate` is set it is never cleared, including on a lapse.

Chosen from three candidates against the actual ladder (fresh word, all `good` — intervals
1, 6, 15, 38, 95):

| Rule | Fires on | Elapsed |
|---|---|---|
| `intervalDays >= 14` | 3rd pass | day 7 |
| `intervalDays >= 21` (Anki "mature") | 4th pass | day 22 |
| `repetitions >= 5` | 5th pass | day 60 |

Interval-based over count-based because the interval already carries the ease factor: a word
graded `hard` has ease ≈ 2.2, so its third pass lands at 6 × 2.2 = 13.2 days and does *not*
cross — it needs a fourth. A count rule would call a word you keep barely getting "learned"
at the same moment as one you nail. Difficulty is priced in for free.

`L` is not the constraint on completion. At the FR-4 cap of 10 new words/day, meeting all
1000 words takes 100 days minimum; the threshold adds a week to that, not months.

### 1.2 Why sticky

Three independent reasons, any one sufficient:

1. `requirements.md:221` already commits to it — FR-17's trend is *reconstructed from*
   `learnedDate`, "which assumes 'learned' is a sticky milestone". Clearing the date destroys
   the historical climb it reconstructs.
2. A lapse resets `intervalDays` to 1. Non-sticky would mean any `.again` on any of 1000
   words drops the count below 1000 and retracts the completion screen — the opposite of
   FR-11's deliberate ending.
3. It is honest. The word *was* learned; it is now due again. The review still happens
   either way, so nothing about the learner's actual practice changes.

### 1.3 Where it lives

`Scheduler.schedule` gains both milestone stamps. Both are pure functions of
`(state, grade, today)` — precisely the scheduler's existing inputs — and the scheduler
already returns a whole new `ReviewState`.

```swift
// Packages/Domain/Sources/Domain/Scheduler.swift
/// A word counts as learned once it survives a two-week gap (Phase 9, FR-10/FR-11).
/// Interval-based rather than repetition-based so a low-ease word has to earn it:
/// at ease 2.2 the third pass lands at 13.2 days and does not cross.
static let learnedIntervalDays = 14
```

```swift
// ...at the end of schedule(), after next.intervalDays is clamped:
if next.firstReviewedDate == nil { next.firstReviewedDate = today }
// Sticky (FR-17): set once on the crossing review, never cleared — not even by a lapse,
// which resets intervalDays to 1.
if state.learnedDate == nil, next.intervalDays >= Self.learnedIntervalDays {
    next.learnedDate = today
}
```

This **deletes** the `firstReviewedDate` stamping block currently in
`StudyViewModel.grade()` (`StudyViewModel.swift:115-117`). That logic was always domain
logic parked in a ViewModel because Phase 8 had nowhere better; it now sits in the one type
that owns review-state transitions, and inherits the scheduler's seeded-random-walk
invariants for free.

`ProgressSummary.init(states:)` needs no change — it already classifies on `learnedDate`
and has been returning 0 only because nothing stamped it.

### 1.4 Tests (test-first — this is logic)

Red before green, one behavior at a time:

- `FR-10 a word below the learned interval is not learned` — state at `intervalDays: 6`,
  `repetitions: 2`, `easeFactor: 2.2` (a word that took a `.hard` earlier), grade `.good`
  → 6 × 2.2 = 13.2 → 13, so `learnedDate == nil`. The same state at ease 2.5 gives 15 and
  *does* cross — that contrast is the point of an interval rule over a count rule.
- `FR-10 crossing the learned interval stamps learnedDate` — the pass that produces ≥ 14
  sets it to `today`.
- `FR-10 a lapse does not un-learn a word` — learned state, grade `.again` → `intervalDays
  == 1`, `learnedDate` unchanged.
- `FR-10 a later review does not restamp learnedDate` — the date stays the *first* crossing.
- `FR-4 the first review stamps firstReviewedDate` and `FR-4 a later review leaves it alone`
  — moved down from the ViewModel tests.

Two additions to the existing seeded random walk in `SchedulerTests`:

- `learnedDate` is monotone: once non-nil it never changes and never returns to nil.
- `learnedDate != nil` implies some step in the walk produced `intervalDays >= 14`.

---

## 2. The completion state

### 2.1 What "done" means mechanically

**Done = no new word is ever introduced again. Reviews continue forever.**

This is forced, not chosen. A word is learned on its third pass while its next review is
still scheduled; `learnedDate` is sticky, so learned words keep coming due. FR-11's own
wording — "shows the completion state rather than a **new card**" — is consistent with this.
Halting the scheduler instead would show a completion screen while words were genuinely due.

`SessionBuilder` needs **no change**. Its new-word filter is `statesByWord[$0.id] == nil`;
when all 1000 words have states that set is empty on its own. Due reviews still assemble
normally.

### 2.2 The predicate

Completion is `learned == pack.wordCount` — a comparison the ViewModels can already make
from a `ProgressSummary` and a `LanguagePack`. No new Domain type. It is *not* "the session
queue is empty", which is FR-12's caught-up state and stays distinct.

### 2.3 `StudyViewModel`

```swift
enum State: Equatable {
    case loading
    case card(Card)
    case caughtUp(nextDue: Date?)
    /// FR-11: every word in the pack has met `L`. No new words will be introduced;
    /// due reviews still are.
    case complete(nextDue: Date?)
    case failed(String)
}
```

`showCurrentCard()`'s empty-queue branch chooses between `.caughtUp` and `.complete` on the
predicate. Ordering matters: `.complete` wins, and it is only reachable with an empty queue —
if a review is due, the card is shown. `start()` caches `pack.wordCount` alongside the states
it already loads, so the check costs nothing extra.

### 2.4 `ProgressViewModel`

`.ready(learned:total:)` gains `isComplete` derived from the same comparison (a computed
property on the case payload, not a fourth case — the progress screen shows the same
`1000 / 1000` either way, with an added line).

### 2.5 The screen

Chosen from three proposals: **ending + unlock as the primary action.**

- Headline: "You've learned all 1000 words in French."
- The next review date beneath it, same as the caught-up screen.
- Primary button: **"Add another language — $0.99"**, which selects the Languages tab.

The $0.99 is stated because hiding it would be the dark pattern, not showing it. No
confetti, no summary statistics, no "keep your streak alive" — the ending is the product
feature (`CLAUDE.md`: "the app has a deliberate ending"). Copy is provisional; Phase 10 owns
the localization catalog and Phase 13 the visual pass.

### 2.6 Tests

ViewModel tests with fakes, test-first:

- `FR-11 a pack with every word learned shows the completion state`
- `FR-11 the completion state is not shown while a review is due` — all learned, one word
  due → `.card`, not `.complete`.
- `FR-12 an unfinished pack with an empty queue still shows caught-up` — the regression that
  keeps the two states distinct.
- `FR-11 no new words are introduced in the completion state` — the `SessionBuilder`
  guarantee, asserted rather than assumed.

---

## 3. Wiring the real layers

### 3.1 Composition root

```swift
// AppDependencies.live()
packStore: JSONPackStore(packsDirectory: Bundle.main.resourceURL!.appending(path: "packs")),
reviewStore: try SwiftDataReviewStore(modelContainer: ...),
```

`SamplePack.swift` is deleted, along with the `ponytail:` comment in `AppDependencies` that
scheduled its own removal for this phase.

`live()` becomes failable or throwing: `SwiftDataReviewStore`'s container can fail to open
(disk full, corrupt store). NFR-10 forbids a crash, so `FullDeckApp` renders the existing
`ErrorStateView` when construction fails rather than force-unwrapping. This is the one
signature change the wiring forces.

### 3.2 Bundling the pack

`pipeline/packs/fr.pack.json` (schema v1, 1000 words, tracked in git) is copied to
`FullDeck/FullDeck/Resources/packs/fr.pack.json`, with a production `manifest.json` beside
it listing that one pack, `unlocked_by_default: true`.

No `project.pbxproj` edit is needed. The app target uses `PBXFileSystemSynchronizedRootGroup`
(Xcode 16 synchronized folders), so a new directory under `FullDeck/FullDeck/` is picked up
automatically and non-source files land in Copy Bundle Resources — **flattened** to the bundle
root rather than preserving the `Resources/packs/` subdirectory (confirmed against a built
`.app`), so the composition root reads from `Bundle.main.resourceURL` directly, not a `packs/`
subpath.

**Consequence, accepted:** the Languages tab shows one row until Phase 12. `SamplePack`'s
in-code Hindi descriptor demonstrated the locked state; a production manifest cannot list a
pack whose file does not exist without `loadPack` failing. The locked-state UI stays covered
by `LanguageSelectionViewModelTests` against fakes, which is where it was tested anyway.

**Known debt:** `pipeline/packs/fr.pack.json` and the bundled copy can drift. Two files, one
copy, no automation — a `scripts/sync-packs.sh` earns its keep when Hindi makes it two packs
in Phase 12, not now.

### 3.3 Active language across launches

`ContentView.swift:5` flags this as Phase 9 work. `LanguageSelectionViewModel` takes an
injected `UserDefaults` (defaulting to `.standard`); tests pass a throwaway suite name.

No new protocol. `UserDefaults` is already an injectable dependency, and a protocol with one
real implementation to wrap a type that is *itself* injectable is ceremony. If the store ever
needs to be something else, the protocol can be extracted then.

Restore rule: on launch, a persisted code is honored only if `availablePacks()` still lists
it — a pack removed between launches must not leave the app pointing at nothing.

---

## 4. Integration tests

New file `FullDeckTests/IntegrationTests.swift`. Real `JSONPackStore` over a temp directory,
real `SwiftDataReviewStore` on an in-memory `ModelContainer`, real `Scheduler` /
`SessionBuilder`, real ViewModels. Only `SpeechService` and `DayClock` stay fakes —
`FixedDayClock` because `scripts/determinism-check.sh` forbids reading the wall clock, and
`FakeSpeechService` because there is no audio in a test run.

| Test | Requirement |
|---|---|
| Full session flow: load pack → grade several words → states persist → progress updates | FR-9, FR-10 |
| A second ViewModel over the same store sees the saved state ("relaunch") | FR-9, NFR-11 |
| Completion reached end-to-end on a small pack, advancing the clock across reviews | FR-11 |
| A corrupt pack surfaces `.failed`, not a crash | NFR-10 |
| A missing pack surfaces `.failed` | NFR-10 |

The completion test runs against a **small fixture pack**, not the 1000-word French one —
driving 1000 words to `L` would need ~3000 grade calls. A separate cheap test asserts the
real bundled pack loads and reports 1000 words, which is the part that would actually break.

These are framework glue (`CLAUDE.md`: "an integration test is the honest test there"), so
they are written alongside the wiring rather than strictly before it. The Domain rule in §1
and the ViewModel states in §2 are logic and stay strictly test-first.

---

## 5. Dependency direction

Nothing here points outward. Domain gains one constant and one stamping rule and imports
nothing new. Data is untouched — `PersistentReviewState` already persists both milestone
dates and `SwiftDataReviewStore.save` already writes them, so the Phase 7 store round-trips
a learned word with no change. The only new dependency is the app target on `Data`, which
is the composition root's job by definition.

---

## 6. Open questions / deferred

- **New-word cap settings screen** (FR-4's user-adjustable half) — still deferred; `N` stays
  a constant 10.
- **Pack sync automation** — §3.2, deferred to Phase 12.
- **Intra-session relearning steps** — the `ponytail:` note on `Scheduler` still stands; a
  lapsed word returns tomorrow, not in ten minutes. Revisit at the Phase 13 spot-check.
- **Completion copy** is provisional pending Phase 10's localization catalog.
