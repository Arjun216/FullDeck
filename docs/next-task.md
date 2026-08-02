# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 13 — QA and the edge-case matrix, `docs/test-plan.md`.
**Model:** Sonnet 5.

**Branch state:** `storekit-monetization` is pushed and not yet merged. Phase 13
should start from a merged `main`.

**Start from [`docs/known-issues.md`](known-issues.md)** — every defect, gap and
deliberate compromise in the project, with IDs. Phase 13's `test-plan.md` should
reference them rather than re-deriving the list. The short version: the defects
are small and latent; the risk is that the purchase chain has never reached
Apple's servers (U-1), the app has never been run on its own iOS 17 minimum
(U-2), both performance NFRs are unmeasured (U-3, U-4), and 1000 Hindi sentences
are unread (U-8).

**Scope decided 2026-08-01: FR-13, FR-16, FR-17 and FR-18 all ship.** None has an
implementation today. **FR-16 is the blocker** — the CC-BY-SA 4.0 credits screen
is a licence obligation, not a feature, and the app has no view that shows
attribution. FR-13 needs a settings surface that also does not exist; put it and
FR-16 in the same container. FR-17 needs `StatsService`, which `architecture.md`
§3 names and nobody wrote. This is closer to its own phase than a Phase 13 tail —
plan it as one.

**The bugs are going to a separate session.** Don't start them here.

**Before shipping, someone has to do the App Store Connect work** —
[`docs/app-store-connect-setup.md`](app-store-connect-setup.md) is the
step-by-step. Nothing in Phase 11 was proved against Apple's servers; the
sandbox run in §5 (buy, delete the app, reinstall, Restore) is the only
real test of FR-15.

**Phase 11 is done (2026-08-01).** Hindi is buyable. Domain unchanged —
the `EntitlementStore` swap was caller-invisible, as designed. Three
things worth not rediscovering:

- **StoreKit testing is broken from the command line on iOS 26.5.**
  `xcodebuild test` never pushes the scheme's StoreKit configuration to
  the simulator's `storekitd`, and it fails *silently*: `SKTestSession`
  doesn't throw, not even on deliberately invalid JSON — it hands back an
  empty store, so every product lookup returns nothing and `buyProduct`
  fails `.notEntitled`. `StoreKitPurchaseServiceTests` detects this and
  skips its six tests. **Retested on iOS 18.5 (2026-08-01): all six still
  skip**, so the runtime is not the variable — the command line is. The
  Xcode IDE is the only untried lever. Hours went into the `.storekit`
  file before the environment turned out to be the problem.
- **iOS 26 toolbar titles aren't Dynamic Type scalable**, and the
  accessibility audit fails them: "user will not be able to change the
  font size of this SwiftUI.AccessibilityNode". Reproduced with a bare
  `Button("...")` and again with an explicit `.font(.body)`. Both Restore
  and the purchase sheet's Done moved out of toolbars because of it.
  Don't put user-facing text in a toolbar on this OS.
- **A `Button`'s hit area is only what its label draws.** A row of
  `Text` + `Spacer` + glyph is dead in the gap between them. This
  presented as *one* broken row: `Français` is wide enough to keep
  catching taps, `हिन्दी` is not, so the same code looked selectively
  broken — and the element still reported `hittable=true, enabled=true`.
  `.contentShape(Rectangle())` has to go on the **label's content**, not
  on the `Button`. Arjun found it by noticing the padlock itself worked.

**The additive-only entitlement refresh is deliberate and untestable
before release.** `refreshEntitlements()` only ever adds; a language
leaves the cache only on an explicit `revocationDate`. The iOS 26.x bug
it defends against — `currentEntitlements` empty for a valid
non-consumable — is production-only and does not reproduce in sandbox.
Do not "simplify" it into a wholesale cache replace.

**Phase 12 is done (2026-08-01).** Hindi ships: 1000 words. Verdict in
[`docs/phase-12-verdict.md`](phase-12-verdict.md) — read that rather than
re-deriving it. ADR-004 held for the app layer: one file changed,
+6/−29, all six insertions comments, nothing in `Packages/`.

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
| 1 | The App Store Connect setup + sandbox run (needs Arjun, not an agent) | — | — |
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
| 11 | ~~StoreKit design — unshelve, re-verify the API notes~~ | ~~Opus 5~~ | ~~xhigh~~ | Done 2026-08-01 — verified against the iOS 26.5 SDK; design unchanged |
| 11 | ~~Execution~~ | ~~Opus 5~~ | ~~default~~ | Done 2026-08-01 — SKTestSession suite skips on the iOS 26.5 CLI regression |
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
- **`AGENTS.md` is a pointer at `CLAUDE.md`, nothing more.** A local plugin
  regenerates identical personal prose-style rules into `.clinerules/`,
  `.cursor/`, `.opencode/`, `.windsurf/`, `.github/copilot-instructions.md` and
  `AGENTS.md` on session start. Those five paths are gitignored — they carried no
  project content, and an agent that read one got style rules where it expected
  engineering standards. If the plugin overwrites `AGENTS.md` again, restore the
  pointer; don't commit the rest.
