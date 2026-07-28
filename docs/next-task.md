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
**Why Opus:** new API surface (StoreKit 2), purchase correctness has real money/
trust stakes, and IAP is new territory for Arjun — this is a "design a state
machine" decision, not a diff.

Phase 10 shipped: an automated accessibility audit (XCUITest
`performAccessibilityAudit()`) across the three core screens, wired into the
existing UI test target; typed `PackLoadError` cases now surface distinct
user-facing messages instead of one blanket string per ViewModel; a confirmed
offline-first code audit (zero networking symbols outside pack-metadata
attribution text) plus a manual verification checklist in
`docs/phase-10-verification.md`; a documented no-analytics decision; and a
Spanish UI localization catalog (`Localizable.xcstrings`) proven by a runtime
XCUITest. All CLAUDE.md gates green (Domain 98.72%, Data 91.96%, determinism,
lint, full `xcodebuild test`).

While writing the accessibility audit, found and fixed several real
pre-existing bugs never caught before: two UI tests referenced a stale
English "French" label and a stale 5-word/"chat" session from before Phase 9
swapped in the real 1000-word pack (never exercised end-to-end until this
phase); several default Button/List-row styles rendered text in system blue,
failing WCAG AA contrast at that size; and one Dynamic-Type clipping risk.

**Residual risk to flag:** the completion screen (`StudyView.completionView`)
and the caught-up screen (`StudyView.caughtUpView`) were never reached by the
automated audit — they require a fully-learned pack / no-cards-due state the
test fixtures don't produce. Their buttons use the same styles already
verified elsewhere (`.borderedProminent`, `ContentUnavailableView`), so this
is low-risk, but it's not the same as a passing audit run against them
directly. Worth a quick manual check or a targeted fixture if Phase 11 or 13
touches either screen. The two manual checklists in
`docs/phase-10-verification.md` (airplane-mode session, VoiceOver/Dynamic
Type walkthrough) are also still unchecked — they need Arjun on a real
device.

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
