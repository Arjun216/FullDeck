# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 11 — StoreKit 2 monetization. Unshelve
`docs/superpowers/specs/2026-08-01-storekit-monetization-design.md` and
**re-verify its StoreKit API notes before writing the plan** (last
checked 2026-08-01; the spec already flags an open iOS 26.x bug where
`currentEntitlements` returns empty for valid non-consumables, which is
why its entitlement refresh is additive-only).
**Model:** Opus 5 to re-check the design, Sonnet 5 for execution.

**Ship Phase 11 soon.** Hindi now shows as **locked with no way to unlock
it** — safe, since `select()` refuses locked packs, but a worse state
than the "coming soon" row it replaced.

**Phase 12 is done (2026-08-01).** Hindi ships: 1000 words, locked.
Verdict in [`docs/phase-12-verdict.md`](phase-12-verdict.md) — read that
rather than re-deriving it. ADR-004 held for the app layer: one file
changed, +6/−29, all six insertions comments, nothing in `Packages/`.

Four things worth not rediscovering:

- **The pipeline's "adding a language is a table entry" claim is now
  qualified**, and `pipeline/README.md` says so. It is a table entry
  *provided a POS-tagging model exists for the language*. spaCy publishes
  none for Hindi, so Phase 12 wrote a whole second backend
  (`UDPipeAnalyzer`) before any table row meant anything. Check step 0
  first for language three.
- **`words.py`'s "alphabetic" test was Latin-script-specific.** Devanagari
  writes vowels as combining marks (Mn/Mc), which `str.isalpha()` calls
  non-letters — it discarded 2707 of Hindi's top 3000 forms, `के`
  included. Fixed in the shared rule. `rejected.json` is where this kind
  of thing surfaces; read it before trusting a candidate list.
- **Taggers and dictionaries can disagree about what a lemma is.** UD
  Hindi cites verbs by bare stem (`कर`), the pack by infinitive (`करना`),
  and §6 compares them as strings — 333 of the first-run violations, one
  cause. `LEMMA_NORMALIZERS` in `analyze.py` reconciles it per language.
  French needed none, which is why this stayed hidden for a whole
  language.
- **`.disabled()` fails WCAG on the warm background.** SwiftUI dims a
  disabled row: the locked `हिन्दी` label measured 3.33:1 against
  `AppBackground`, under the 4.5:1 floor, where `Français` sits at
  16.86:1. Latent since Phase 8 — French is never locked, so no locked
  row ever existed to expose it. The locked row is now a normal enabled
  button; FR-1 is enforced in `select()`, and Phase 11 needs it tappable
  anyway for the purchase sheet.

Nine §6 waivers, all documented in `pipeline/work/hi/exceptions.json` and
printed on every `pack` run. They are *unverifiable*, not unsatisfiable:
correct Hindi sentences whose target word UDPipe cannot recognise
(nukta-stripped lemmas, dropped imperatives, collapsed causatives).

`AccentText` still has no consumer. It is the text-safe accent for
whenever something needs one.

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
| 1 | Phase 13 — QA, edge-case matrix, `docs/test-plan.md` | Sonnet 5 | default |
| 2 | Phase 13 — human read of the 1000 Hindi sentences (D4 review) | Sonnet 5 | default |
| 3 | Phase 14 — release docs, checklists, `MAINTENANCE.md` | Sonnet 5 | default |

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
| — | ~~Hindi "coming soon" row~~ | ~~Sonnet 5~~ | ~~default~~ | Done 2026-08-01 |
| 12 | ~~Fix the pipeline's Hindi tagger~~ | ~~Opus 5~~ | ~~high~~ | Done 2026-08-01 — UDPipe backend; no spaCy Hindi POS model exists |
| 12 | ~~Pack generation runs~~ | ~~Sonnet 5~~ | ~~default~~ | Done 2026-08-01 — 1000 words, 9 waivers |
| 12 | ~~Hindi verdict — is the abstraction leaking?~~ | ~~Opus 5~~ | ~~high~~ | Done 2026-08-01 — `docs/phase-12-verdict.md` |
| 11 | StoreKit design — unshelve, re-verify the API notes | Opus 5 | xhigh | Written 2026-08-01; APIs need a re-check before the plan |
| 11 | Execution | Sonnet 5 | default | StoreKitTest gates it. Phase 12 is done, so this is unblocked |
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
