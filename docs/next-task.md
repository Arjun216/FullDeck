# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 11 design — StoreKit 2 purchase/entitlement state machine
**Model:** Opus 5, xhigh effort
**Why Opus:** new API surface, purchase correctness, and IAP is new to
Arjun. No spec exists yet — this is a decision, not a diff.

**Phase 10.5 is done.** All three parts shipped: the binary recall
scale, the warm token layer, and swipe to grade.

Part 3 shipped: swipe right commits `recalled`, left commits `forgot`,
past a quarter of the card's width. The card tracks the finger with an
offset and a slight tilt, and springs back below threshold. Both buttons
are untouched and remain the accessible path — the swipe is an
accelerator, never the only way. The commit rule lives in `CardSwipe`
rather than the view, so its threshold is unit-tested at the exact
boundary (75 points commits, 74 does not) — something an XCUITest swipe
cannot express. The card also finally got a surface, which is what
consumes `AppSurface` and `AppSeparator`.

Two things worth not rediscovering:

- The drag gesture is attached **unconditionally** and made inert until
  the card is revealed, rather than attached only when revealed. Both
  halves matter. Gating the *grade* keeps FR-5 honest — otherwise the
  swipe is a second path around `reveal()`. Gating by *attachment*
  instead looks equivalent and is not: an unattached gesture lets the
  drag fall through to the `TabView`, which yanks the learner to another
  tab the moment they swipe a beat too early. Found by driving it in the
  simulator; no test caught it.
- `performAudit`'s contrast exclusion is **gone**, and `AccentFill`
  (`#B45309`, the same in both appearances) is why. A prominent fill
  under a white label and an accent used as text have opposite contrast
  requirements — one token cannot serve both. `AccentColor`'s dark value
  has to stay bright to work as text on the dark background (8.15:1),
  and white on that is 2.15:1. The audit now runs unfiltered.

`AccentText` still has no consumer. It is the text-safe accent for
whenever something needs one.

**Next:** Phase 11 (StoreKit). Phase 10.5 is closed.

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
| 1 | Phase 11 execution (StoreKitTest, sandbox) | Sonnet 5 | default |
| 2 | Phase 12 — Hindi pack generation, architecture-validation verdict | Opus 5 (verdict) / Sonnet 5 (pipeline runs) | high / default |

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
| 10.5 | ~~Swipe to grade~~ | ~~Sonnet 5~~ | ~~default~~ | Done 2026-07-31 |
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
