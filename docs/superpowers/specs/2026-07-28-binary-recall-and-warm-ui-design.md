# Binary recall scale + warm minimal UI — design

**Date:** 2026-07-28
**Status:** approved, pending implementation
**Supersedes:** the 4-level grade scale chosen in Phase 5; the stock-default visual
treatment shipped in Phase 8.

## Context

Phases 5–10 delivered a working, tested, accessible single-language app. Reviewing
it running on device surfaced two problems that no test could have caught, because
neither is a correctness failure:

1. **The grading scale is heavier than the product.** Four buttons (Again / Hard /
   Good / Easy) ask the learner to make a four-way judgement on every card, in an
   app whose stated thesis is "do one thing well."
2. **There is no visual design.** Phase 8 built the screens functionally and never
   applied a design pass. `AccentColor.colorset` is empty, so every control falls
   back to system blue; Phase 10 worked around the resulting contrast failures by
   forcing `.foregroundStyle(.primary)` on individual elements rather than fixing
   the cause.

This spec covers both, sequenced mechanics-first so the visual work targets the
final control count instead of restyling buttons that are about to be deleted.

## Decision 1 — binary recall scale

### The change

```swift
public enum Grade: Sendable, CaseIterable {
    case forgot
    case recalled
}
```

Replacing `again / hard / good / easy`.

### Why

**Decision cost is a real cost.** The four-button spectrum introduces decision
paralysis at exactly the moment the learner should be thinking about the word, not
about the interface. Anki's own pre-FSRS recommended guidance is a two-button
Again/Good system.

**"Hard" is the known-bad button.** In textbook SM-2 it multiplies the interval by
the ease factor, so reporting difficulty *lengthens* the gap before you see the word
again — the opposite of what the learner intends. `Scheduler.swift` already departs
from textbook SM-2 with a fixed 1.2× step to blunt this. Removing the button removes
the need for the workaround.

**"Easy" is nearly a no-op here.** The first two repetitions use fixed steps (1 day,
6 days) regardless of grade. Easy only moved ease 2.5 → 2.65, so a word the learner
already knows still takes three successful reps to cross the 14-day "learned"
threshold — the same as Good. It buys almost nothing while costing a quarter of the
decision surface.

**It maps cleanly to the interaction.** Binary is left/right. A four-way directional
mapping is either ambiguous or requires a gesture vocabulary nobody wants to learn.

### Scheduler changes, and the trap in them

Current ease deltas: `again -0.20, hard -0.15, good 0, easy +0.15`.

Naively deleting Hard and Easy leaves `recalled` at a 0 delta — which means **ease
can only ever decay**, ratcheting monotonically toward the 1.3 floor with no path
back up. This is Anki's well-documented "ease hell" and a significant part of why
FSRS was written. Avoiding it is a required part of this change, not an optional
refinement.

New deltas:

| Grade | Ease delta |
|---|---|
| `forgot` | −0.20 |
| `recalled` | +0.05 |

The interval switch simplifies — the `.hard` case and the `hardMultiplier` constant
are deleted outright:

```swift
let interval =
    switch (grade, state.repetitions) {
    case (.forgot, _): 1
    case (_, 0): 1
    case (_, 1): 6
    default: Int((Double(state.intervalDays) * next.easeFactor).rounded())
    }
```

### What does not change

- **The learned rule.** 1 → 6 → 15 days; still three successful reps to cross the
  14-day threshold. FR-10, FR-11, FR-17 unaffected.
- **Reset-on-failure.** `forgot` sets interval to 1 and repetitions to 0.
- **All scheduler invariants.** `nextReviewDate ≥ today`; ease and interval stay
  inside their clamps; a failing grade never lengthens an interval; `(state, grade,
  today)` stays pure.
- **`SessionBuilder`.** Never references `Grade`.
- **Persistence.** The store holds `ReviewState` (ease, interval, repetitions,
  milestone dates) and never the grade itself. **No SwiftData migration, no stored
  data invalidated.**

### Blast radius

Seven files, ~30 references:

| File | What changes |
|---|---|
| `Domain/Models.swift` | the enum |
| `Domain/Scheduler.swift` | delta table, interval switch, delete `hardMultiplier` |
| `DomainTests/SchedulerTests.swift` | cases per grade; invariant walk over 2 grades |
| `FullDeck/ViewModels/StudyViewModel.swift` | passthrough only |
| `FullDeck/Views/StudyView.swift` | button row, `label(for:)` |
| `FullDeckTests/StudyViewModelTests.swift` | grade references |
| `FullDeckUITests/FullDeckUITests.swift` | `"Grade this word Good"` accessibility label |

### Effect on FR-18 (hardest words, not yet built)

FR-18 ranks by ease factor. Under binary grading ease becomes a pure function of
failure count rather than a mix of failures and self-reported difficulty — arguably a
cleaner signal for that ranking. The optional `lapses` counter that FR-18 mentions
becomes more attractive, since ease is now the only per-word difficulty signal. Not
in scope here; flagged for whichever phase builds FR-18.

## Decision 2 — warm minimal token layer

### Colors

Semantic tokens as asset-catalog colorsets (free light/dark resolution, no Swift
code to resolve them). Filling in `AccentColor` is the single highest-leverage
change: it retints the tab bar, `.borderedProminent`, and every plain button at once.

| Token | Light | Dark | Use |
|---|---|---|---|
| `AccentColor` | `#D97706` | `#F59E0B` | fills, selected tab, prominent buttons |
| `AccentText` | `#B45309` | `#FCD34D` | accent used *as text* |
| `Background` | `#FFFBEB` | `#1C1917` | screen base |
| `Surface` | `#FFFFFF` | `#292524` | card / row |
| `TextPrimary` | `#1C1917` | `#FAFAF9` | word, headings, body |
| `TextSecondary` | `#57534E` | `#A8A29E` | part-of-speech tag, counters |
| `Separator` | `#F5E9C8` | `#44403C` | hairlines |

### Contrast, computed

Verified against the light background `#FFFBEB`:

| Pair | Ratio | Verdict |
|---|---|---|
| `#1C1917` text | 16.87:1 | passes AA + AAA |
| `#57534E` text | 7.36:1 | passes AA + AAA |
| `#B45309` text | 4.84:1 | passes AA normal text |
| `#D97706` fill | 3.07:1 | passes AA **large text / graphics only** |

Dark mode: `#F59E0B` on `#1C1917` is 8.15:1.

**`#D97706` must never be used as body text.** It clears the 3:1 bar for graphical
objects and large text but fails the 4.5:1 normal-text bar. `#B45309` is the
text-safe variant. Getting this backwards regresses the Phase 10 accessibility
audit, which is a gating CI test.

### Typography and spacing

- **Type:** keep SwiftUI's semantic styles (`.largeTitle`, `.body`, `.footnote`).
  Tokens set weight and color only, never hardcoded point sizes — Dynamic Type and
  NFR-5 depend on the semantic styles staying intact.
- **Spacing:** a 4pt scale as named constants (`xs 4, sm 8, md 16, lg 24, xl 32`)
  replacing the current ad-hoc 8/12/16/24 mix.

## Decision 3 — swipe to grade

Swipe right = `recalled`, swipe left = `forgot`. The card tracks the finger with a
live directional hint.

**Both buttons remain visible and functional.** Current iOS accessibility guidance
identifies gesture-only features as the top accessibility failure: every custom
gesture needs a visible-control equivalent. Two buttons are also larger targets than
the four they replace. The swipe is an accelerator, never the only path.

**Reveal stays.** CLAUDE.md's second core mechanic is that the learner attempts the
answer *before* it is revealed. The flow is: see word → attempt → Reveal → swipe to
record whether the attempt was right. Allowing a grade before reveal would convert
verified self-testing into unverified self-assessment, which is the exact failure
mode active recall exists to prevent. The existing `gradingBeforeRevealDoesNothing`
behavior is retained and keeps its test.

### Button labels

`Knew it!` and `Let's try this again`.

Chosen by the product owner over the recommended `Knew it` / `Not yet`. Two concerns
were raised and consciously accepted:

- **Asymmetry and wrapping.** Four words beside two produces unequal button widths,
  and the longer label wraps at accessibility Dynamic Type sizes. The `ScrollView`
  added in Phase 10 prevents clipping, so this is cosmetic, not a functional
  regression.
- **Voice mismatch.** "Knew it!" is the learner reporting on themselves; "Let's try
  this again" is the app addressing the learner. The two buttons speak as different
  parties.

The rationale for accepting: softening the failure side is deliberate and consistent
with the project's no-streak-guilt stance. Recorded here so the choice reads as
intentional rather than accidental.

## Out of scope

- **No engagement mechanics.** No autoplay-next, no infinite queue, no variable
  reward, no streaks. The session still ends when the day's cards are done. Research
  on gamified language apps finds documented anxiety and frustration effects and
  measures engagement far more often than learning; the deliberate ending stays.
- **No progress bar** on the Progress screen. The count already states the position;
  a filling bar toward 1000 is the closest available thing to a treadmill visual.
- **No layout restructuring** in the token pass — card containers and spacing rework
  are judged after the palette is in place.
- **No Swift 6 migration** of the app target; still tracked separately.

## Phasing

| Phase | Content | Test posture |
|---|---|---|
| A | Binary grade scale: `Grade`, `Scheduler`, ViewModel, view, all affected tests | Test-first. Domain logic — write the failing test, watch it fail for the right reason, then implement. |
| B | Warm minimal token layer: colorsets, `Theme.swift`, applied across the three screens | Alongside implementation. Framework glue; the Phase 10 accessibility audit is the real gate. |
| C | Swipe-to-grade gesture over the binary scale | Alongside. Buttons keep their existing tests; the gesture adds its own. |

Each phase is a separate implementation plan and a separate branch.

## Traceability

`docs/requirements.md` parameterised this deliberately:

> **`G` (recall-grade scale)** — how the learner grades a recall attempt (4-level
> vs. binary). Chosen in **Phase 5**; referenced abstractly here.

FR-8's acceptance criteria are written as "a passing grade" / "a failing grade" —
scale-agnostic. **No requirements amendment is needed.** FR-7's reveal-before-grade
acceptance criteria are likewise unaffected.

`docs/build-plan.md` and `docs/next-task.md` both need updating: this work is not in
the original 14-phase plan and displaces the immediate Phase 11 start.

## Risks

| Risk | Mitigation |
|---|---|
| Ease-hell regression if `recalled` is left at a 0 delta | Explicit +0.05; an invariant test asserts ease can recover from the floor across a seeded walk |
| Amber used as body text, failing WCAG AA | Two separate tokens (`AccentColor` fill vs `AccentText`); the Phase 10 audit is a gating CI test |
| Swipe becomes the only grading path | Buttons keep their own tests; the audit checks label presence |
| Losing recall granularity permanently | Persistence stores `ReviewState`, not grades — reintroducing a wider scale later needs no data migration |

## Sources

- [Anki forums — switching from 2 answer buttons to 3 or 4](https://forums.ankiweb.net/t/switching-from-2-answer-button-system-to-3-or-4/51664) — the pre-FSRS recommended two-button guidance
- [Pass/Fail 2](https://github.com/lambdadog/passfail2) — decision-paralysis rationale; the Hard-button interval critique
- [FSRS for Anki](https://github.com/open-spaced-repetition/fsrs4anki) — pass/fail mapping onto a modern scheduler
- [iOS accessibility playbook 2026](https://www.forasoft.com/blog/article/accessibility-ios-app-development) — gesture-only features as the primary accessibility failure; every custom gesture needs an alternate
- [Gamification, motivation, and contradiction: a critical analysis of Duolingo](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6846283) and [the good, the bad and the ugly of Duolingo gamification](https://uxdesign.cc/the-good-the-bad-and-the-ugly-of-duolingo-gamification-3a12f0e80dc7) — anxiety/pressure effects; competitive mechanics distracting from the learning objective
