# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 10 — cross-cutting concerns (accessibility audit, error→state
mapping, offline verification, UI localization catalog, observability decision)
**Model:** Sonnet 5, default effort
**Spec:** none written yet — Phase 10 in `docs/build-plan.md` is specific enough
to skip a brainstorm and go straight to a plan, per the same judgment call Phase
9 made in reverse (brainstorm only where a real decision needs Arjun first).

Phase 9 shipped: `L = intervalDays >= 14` (sticky), the completion state and
screen, real `JSONPackStore` + `SwiftDataReviewStore` wiring, the bundled
1000-word French pack, active-language persistence, and integration tests
across the seams. All CLAUDE.md gates green (Domain 98.70%, Data 91.96%,
determinism, lint).

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
| 10 | a11y, error mapping, localization, offline audit | Sonnet 5 | default | Spec'd in the build plan |
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
