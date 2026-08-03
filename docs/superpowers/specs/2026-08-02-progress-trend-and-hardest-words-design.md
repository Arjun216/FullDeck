# Progress: Trend & Hardest Words — Design

**Phase:** N-block, part B (of two)
**Date:** 2026-08-02
**Requirements:** FR-17 (learning-over-time trend), FR-18 (hardest words)
**Status:** Approved 2026-08-02. Not yet implemented.
**Part A:** [`2026-08-02-settings-and-about-design.md`](2026-08-02-settings-and-about-design.md) — shipped.

## What this builds

`StatsService`, and the two Progress sections it feeds.

The Progress screen shows one number: words learned out of the pack total. FR-17
and FR-18 have asked for more since Phase 1 and were never built — Phase 9
stamped the milestone dates FR-17 needs and left a comment saying a later phase
would decide what to do with them. `architecture.md:151` names the type that
would do it:

> `StatsService` — computes progress from a pack + `ReviewStore.allStates(...)`:
> words-learned count (FR-10), the learning-over-time trend from per-word
> milestone dates (FR-17), and hardest-words ranking by ease factor (FR-18).
> Pure; needs no new port.

This spec writes that type as described, four phases late, and renders its two
outputs.

**Neither requirement needs new persistence.** Every input already exists on
`ReviewState`: `firstReviewedDate`, `learnedDate`, `easeFactor`. That is the
whole reason part B is small enough to follow part A rather than precede it.

## Decision 1 — hardness is `easeFactor`, and no lapse count is added

**The finding that forced this decision:** `Scheduler` gives `.recalled` an ease
delta of **+0.05**, clamped to `1.3...3.0`. Ease therefore *rises* on every pass.
A word that failed once (2.50 → 2.30) and has since been recalled four times sits
at exactly 2.50 — byte-identical to a word that has never been failed. **Ease
factor cannot answer "has this word ever been failed."**

FR-18 anticipates the problem in its own text — "ease factor; *optionally a lapse
count*" — and `ReviewState` has no lapse count.

**Decided: rank by `easeFactor` ascending, surface only words below
`ReviewState.startingEase` (2.5).** No new field, no migration.

This satisfies FR-18's acceptance as written. "A word never failed is not
surfaced as hard" holds: a never-reviewed word sits at exactly 2.5 and a
never-failed reviewed word sits above it, so neither passes the filter. The
criterion does not require the converse — that every word ever failed must
appear — and the converse is the behaviour we do not want anyway.

**The edge case is a feature, not a defect.** A word that lapsed once and has
since been recalled four times drops off the list. That is correct: FR-18 asks
for the words the learner *finds* hardest, and ease is a running difficulty
estimate, not a permanent record. Marking a word the learner has since mastered
would be closer to a shame list than to help.

**Rejected — adding `lapses: Int` to `ReviewState`.** It answers "ever failed"
exactly, and costs a Domain model change, a SwiftData schema change with a
migration, and an update to every construction site including fixtures — to
deliver behaviour we would then have to soften.

**Rejected — filtering on `repetitions`.** It resets to 0 on every lapse and
climbs on every pass, so it tracks *recency of failure*, not difficulty, and a
brand-new word is indistinguishable from a just-failed one.

### One small Domain change

`2.5` currently lives only as an initializer default on `ReviewState`. It becomes
`public static let startingEase = 2.5`, with the initializer defaulting to it, so
the filter and the default cannot drift apart.

## Decision 2 — both trend curves are cumulative

```swift
public struct TrendPoint: Equatable, Sendable {
    public let day: Date
    /// Cumulative words that have entered learning by this day.
    public let started: Int
    /// Cumulative words that have met `L` by this day. Never exceeds `started`.
    public let learned: Int
}
```

FR-17 asks for how many words have **"moved into"** learning and into learned.
*Moved into* is cumulative, so `started` counts every word ever reviewed, not the
population currently mid-learning.

Both curves therefore rise monotonically, and **the gap between them is the
in-flight set** — the same information, without the misleading shape.

**The alternative reading, and why it loses:** plotting *currently* learning
would fall as words graduate. On a screen whose entire point is the climb toward
1000, a line that drops when the learner succeeds reads as regression. It would
also sit awkwardly against `CLAUDE.md`'s deliberate-ending framing.

One point per day across the span from **the earliest `firstReviewedDate` across
all states** to `today`, inclusive at both ends, stepped with `DayCalendar` so the
arithmetic is day-granular like the rest of Domain. A year is 365 points and
three years is ~1100 — trivial either way, and a per-day series is truthful under
any interpolation the chart chooses, where sparse points would draw a diagonal
across a week when nothing happened.

A state with no `firstReviewedDate` — a word never reviewed — contributes to no
day. If no state has one, the series is empty and the section hides.

**Boundary, pinned:** a milestone dated exactly `today - 7 days` counts as
*within* the last 7 days. Both ends inclusive, so "the last 7 days" spans 8
points and the arithmetic matches the acceptance example rather than being off by
one against it.

## Decision 3 — `StatsService` is pure, and takes `today` as a parameter

```swift
public struct StatsService: Sendable {
    public init() {}

    /// FR-17.
    public func trend(states: [ReviewState], today: Date) -> [TrendPoint]

    /// FR-18.
    public func hardestWords(
        in pack: LanguagePack, states: [ReviewState], limit: Int
    ) -> [WordEntry]
}
```

`limit` has no default. Five is a presentation decision (Decision 5) and belongs
at the call site, not baked into a Domain signature where a test would have to
work around it.

`today` is a parameter rather than an injected `Clock`, matching
`Scheduler.schedule(_:grade:today:)`. The type stays a pure function of its
arguments, and `scripts/determinism-check.sh` is satisfied by construction rather
than by discipline.

`hardestWords` returns `[WordEntry]`, not `[WordID]`, because the view needs the
display form and the gloss. A state whose word is no longer in the pack is
skipped rather than crashing — packs are versioned and a word can leave one.

Ties break on `rank`. Two words at the same ease must order the same way on every
run, or the list flickers between loads and the test is unreproducible.

## Decision 4 — states become the single source, and `ReviewStore.progress` goes

`ProgressViewModel.load()` makes exactly two calls — `loadPack` and `allStates` —
and derives all three sections from the result. The hero count comes from the
existing `ProgressSummary(states:)`.

`ReviewStore.progress(_:)` had exactly one app caller: `ProgressViewModel`. Once
the ViewModel holds the states, that method is a second path to a number Domain
already computes purely, and **two paths to one number can disagree**. Deleted:
the port method, the SwiftData implementation, the `InMemoryReviewStore` twin,
and its Data test.

`ProgressSummary` itself stays. It is the type that names FR-17's buckets — new,
learning, learned — and it is how the hero count is still derived.

`ProgressViewModel` gains a `StatsService` and a `DayClock`, and `State.ready`
carries a `Snapshot` struct rather than two loose integers:

```swift
struct Snapshot: Equatable {
    let learned: Int
    let total: Int
    let trend: [TrendPoint]
    let hardest: [WordEntry]
}
```

## Decision 5 — the screen, and what each section does when empty

A `ScrollView` of three blocks, hero unchanged at the top.

| Section | When empty |
|---|---|
| Words learned | Always shown — zero of 1000 is a true and meaningful statement |
| Trend | **Hidden.** An empty curve says nothing |
| Hardest words | **Shown**, with "Nothing has tripped you up yet." |

The asymmetry is deliberate. "No words have given you trouble" is worth knowing;
an empty chart is furniture.

**Rejected — all sections always visible.** A predictable shape, at the cost of a
first-run screen showing a zero, an empty chart and an empty list: three empty
boxes as the first impression of the product's outcome screen.

**Rejected — details behind a `NavigationLink`.** Protects the current screen's
simplicity, but FR-17 and FR-18 both say *the progress view* shows these, and
burying a requirement one tap deep to keep a screen tidy is the wrong trade.

Five hardest words, read-only. Five reads as "here is what to watch"; ten starts
to read as a report card, and in an app that bans streak-guilt the length of a
list of your own mistakes is a tone decision. Read-only because study order is
the scheduler's job — letting the learner jump to a chosen word would put a
second, manual path into a deck the spaced-repetition engine is supposed to own,
and `CLAUDE.md` calls that engine non-negotiable.

Completion and hardest words coexist: finishing the deck does not erase that some
words were hard on the way, and the completion line stays the hero.

## Decision 6 — chart accessibility, learned from part A

Swift Charts is a system framework on iOS 16+, so it adds no dependency against
the deployment target of 17.0.

Three rules, two of them carried directly from the defects the Settings audit
caught yesterday (C-6):

1. **Axis labels are text and need `Color.textSecondary` explicitly.** SwiftUI's
   default axis grey is the same system colour that just failed contrast on the
   warm background one screen over. Without this it ships broken in the identical
   way.
2. **Marks are graphical objects**, held to 3:1 rather than 4.5:1. `AccentFill`
   (4.84:1 on `AppBackground`) for `learned`, `TextSecondary` (7.36:1) for
   `started`. Both clear either bar, so the choice survives a reclassification.
3. **`.accessibilityElement(children: .ignore)` plus one label.** A per-day
   series is hundreds of marks; VoiceOver reading them individually is worse than
   silence. The label states FR-17's own acceptance sentence — "12 words learned
   in the last 7 days, 40 in the last 30" — so a screen-reader user gets the
   numeric form of the requirement rather than a shape they cannot see.

   **Those two numbers are read off the same series**, as
   `learned(today) - learned(today - n)`, never computed by a second pass over
   the states. One derivation, so the label and the curve cannot disagree — the
   same argument Decision 4 makes for deleting `ReviewStore.progress`. A series
   shorter than the window clamps to its first point.

Chart height uses `@ScaledMetric`, matching how the hero count already scales.

**Progress is already in `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`**, so
the chart and the list are audited on the next run with no new test code. Given
that the last two screens added to that audit produced four real contrast
defects between them, expect findings here and fix the colours rather than
filtering the audit.

## Errors

Unchanged in shape. `PackLoadError.userMessage` for pack failures, a generic
string for the opaque `ReviewStore` ones, one `.failed` state for the whole
screen. A Progress screen showing a hero count with a broken trend beneath it
would be worse than an honest error.

## Testing

`StatsService` is pure Domain: strict test-first, red-green-refactor, one
behaviour at a time. It counts against the **90% Domain coverage floor**.

**FR-17**

- cumulative counts at a past date match the milestones
- words learned in the last 7 days equals the count of milestones within 7 days
- `learned` never exceeds `started` at any point in a series
- no milestones yields an empty series
- the series is a pure function of `(states, today)`

**FR-18**

- a lower ease factor ranks higher
- a word never failed is not surfaced
- equal ease factors order by rank, deterministically
- a state whose word is no longer in the pack is skipped
- the limit is honoured

**App target**

- FR-10/FR-17/FR-18 a load populates all three sections
- NFR-10 a failed load surfaces a message

**No new UI test.** The audit already visits Progress.

**The deletion is verified by the compiler.** Removing `ReviewStore.progress(_:)`
breaks any caller that still exists; its Data test is removed with it.

## Out of scope

- Any study-activity metric — time spent, review counts, session logs, heatmaps,
  streak chains (§4, explicitly).
- A lapse count on `ReviewState` (Decision 1, rejected alternative).
- Tapping a hardest word to study it, or to hear it (Decision 5).
- Per-language comparison, export, or sharing.
- Date-range pickers or zoom on the trend. It shows the whole history.

## Risks

| Risk | Mitigation |
|---|---|
| Swift Charts is new surface for the accessibility audit, which has caught four contrast defects on new screens in two days | Decision 6 pre-empts the two known causes; Progress is already audited, so findings surface on the next run rather than after release |
| A per-day series over a long history is many points | ~1100 points at three years, all `Int` pairs; measured against NFR-3 only if the screen feels slow |
| `easeFactor < 2.5` is a proxy, and a reader may later mistake it for "ever failed" | Decision 1 records why, and the `startingEase` constant makes the comparison self-documenting |
| Deleting `ReviewStore.progress` touches the Data package and its coverage floor (80%) | The test goes with the code, so the ratio moves only if the remaining lines are less covered; re-check the gate after |
