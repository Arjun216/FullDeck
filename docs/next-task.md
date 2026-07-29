# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 10.5 part 2 — warm minimal token layer
**Model:** Sonnet 5, default effort
**Why Sonnet:** the palette, contrast ratios and token names are all settled in
`docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md` — this
is a diff, not a decision.

Phase 10.5 part 1 shipped: the recall scale is binary. `Grade` is now
`forgot` / `recalled`; the `hard` fixed-step interval and its
departs-from-SM-2 workaround are gone, as is the near-inert `easy` case.
`recalled` carries a +0.05 ease delta — required, not cosmetic: at zero
the ease factor could only ever decay toward its floor, so a word that
lapsed early could never recover. Persistence stores `ReviewState` and
never the grade, so no migration was needed. Buttons read "Knew it!" and
"Let's try this again".

Removing the redundant `Grade this word …` accessibility label unmasked a
contrast failure the audit had never been able to see: the override made
each `Button` one opaque element, hiding its blue-on-grey label text from
the check. Fixed with `.foregroundStyle(.primary)`. Worth remembering —
an explicit `accessibilityLabel` on a container can hide its children
from `performAccessibilityAudit()`.

**Next:** the token layer (spec Decision 2), then swipe-to-grade
(Decision 3). Phase 11 (StoreKit) follows after.

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
| 1 | Phase 10.5 part 3 — swipe to grade | Sonnet 5 | default |
| 2 | Phase 11 design — StoreKit 2 purchase/entitlement state machine | Opus 5 | xhigh |
| 3 | Phase 11 execution (StoreKitTest, sandbox) | Sonnet 5 | default |
| 4 | Phase 12 — Hindi pack generation, architecture-validation verdict | Opus 5 (verdict) / Sonnet 5 (pipeline runs) | high / default |

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
