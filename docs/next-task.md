# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 10.5 part 3 — swipe to grade
**Model:** Sonnet 5, default effort
**Why Sonnet:** Decision 3 of
`docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md`
settles the gesture, the direction mapping and the accessibility
fallback — this is a diff, not a decision.

Phase 10.5 part 2 shipped: the app is warm, not system-blue-on-white.
Seven asset-catalog colorsets, each with a light and dark value.
`AccentColor` was an *empty* colorset, which is why everything rendered
system blue; filling it was the highest-leverage line in the change,
because it is wired as `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`
and so retints the tab bar and every button style with no code at all.
Text moved from SwiftUI's `.primary` / `.secondary` to
`Color.textPrimary` / `Color.textSecondary`, and a `Spacing` enum
(xs 4 … xl 32) replaced the ad-hoc 8/12/16/24 mix. Its values are
deliberately *not* `@ScaledMetric`: Dynamic Type already grows the text
and the stacks with it, and scaling the gaps too pushes the largest
accessibility sizes off screen.

Three tokens are named `AppBackground` / `AppSurface` / `AppSeparator`
rather than the spec's bare `Background` / `Surface` / `Separator`.
Xcode generates Swift symbols from colorset names, and SwiftUI already
declares `.background` and `.separator` on `ShapeStyle` — the bare names
would have made `.background(.background)` an ambiguous overload.
`AppSurface`, `AppSeparator` and `AccentText` have no consumer yet; the
card treatment in part 3 is their first.

Two things worth not rediscovering:

- A `List` paints its own opaque background over anything set on the
  enclosing `NavigationStack` content. `.scrollContentBackground(.hidden)`
  *plus* `.listRowBackground` is what lets the screen base through —
  either one alone leaves system-grey showing.
- **White on the light-mode accent `#D97706` is 3.19:1**, under WCAG AA's
  4.5:1 for normal text. That is what `.borderedProminent` renders, so it
  affects the Reveal button and the completion screen's unlock button.
  `performAudit` in `FullDeckUITests` already excludes the Reveal button's
  contrast finding on the grounds that it is "Apple's own default
  prominent-button appearance" — that justification expired the moment the
  accent became ours, and the exclusion now shields a colour we picked.
  Decide it in part 3, which touches button styling anyway. `#B45309`
  (the `AccentText` value) measures 5.02:1 against white and clears the
  bar.

**Next:** Phase 11 (StoreKit) follows after part 3.

**Carried forward from Phase 10:** the completion screen
(`StudyView.completionView`) and the caught-up screen
(`StudyView.caughtUpView`) are still never reached by the automated
audit — they need a fully-learned / no-cards-due state the fixtures
don't produce. The two manual checklists in
`docs/phase-10-verification.md` (airplane-mode session, VoiceOver/Dynamic
Type walkthrough) also still need Arjun on a real device.

## Then

| # | Task | Model | Effort |
|---|---|---|---|
| 1 | Phase 11 design — StoreKit 2 purchase/entitlement state machine | Opus 5 | xhigh |
| 2 | Phase 11 execution (StoreKitTest, sandbox) | Sonnet 5 | default |
| 3 | Phase 12 — Hindi pack generation, architecture-validation verdict | Opus 5 (verdict) / Sonnet 5 (pipeline runs) | high / default |

Switching happens at the plan boundary, never mid-execution. Writing the plan is the
expensive thinking; executing it is cheap. Two model changes per phase, both at a
natural session break.

---

## Full remaining map

| Phase | Segment | Model | Effort | Why |
|---|---|---|---|---|
| 9 | ~~Define "learned", completion-screen options~~ | ~~Opus 5~~ | ~~high~~ | Done 2026-07-28 |
| 9 | ~~TDD execution, integration tests~~ | ~~Sonnet 5~~ | ~~default~~ | Done 2026-07-28 |
| 10 | ~~a11y, error mapping, localization, offline audit~~ | ~~Sonnet 5~~ | ~~default~~ | Done 2026-07-28 |
| 10.5 | ~~Binary recall scale~~ | ~~Opus 5~~ | ~~default~~ | Done 2026-07-29 |
| 10.5 | ~~Warm minimal token layer~~ | ~~Sonnet 5~~ | ~~default~~ | Done 2026-07-31 |
| 10.5 | Swipe to grade | Sonnet 5 | default | Spec settles gesture + fallback; this is a diff |
| 11 | StoreKit design + state machine | Opus 5 | xhigh | New API surface, purchase correctness, IAP is new to Arjun |
| 11 | Execution | Sonnet 5 | default | StoreKitTest gates it |
| 12 | Hindi verdict — is the abstraction leaking? | Opus 5 | high | Central architectural claim (ADR-004), judgment call |
| 12 | Pack generation runs | Sonnet 5 | default | Pipeline does the work |
| 13 | QA, edge-case matrix, `docs/test-plan.md` | Sonnet 5 | default | Broad but enumerable |
| 14 | Release docs, checklists, `MAINTENANCE.md` | Sonnet 5 | default | Writing, not deciding |
| — | Running gates, reading test output | Haiku 4.5 | — | Mechanical |

## Standing notes

- **Pipeline stays on Sonnet.** `packgen generate` defaults to `sonnet`
  (`pipeline/src/packgen/cli.py:60`). 24+ calls per run against a machine-checked
  constraint with a regenerate loop — Opus there is budget burn for zero quality gain.
- **No ultracode / dynamic workflows.** The build plan is explicitly one phase per
  session, don't skip ahead; multi-agent orchestration fights that sequencing.
- **Search subagents run on Haiku**, spawned without asking. Editing, planning, and
  TDD execution stay on the main thread.
- Model tiers here are a structural argument, not a measured one. Worth checking
  against real usage numbers on a Phase 9 task before treating them as settled.
