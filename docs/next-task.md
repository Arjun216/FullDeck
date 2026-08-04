# Next task & model

Living file. Answers one question: **what do I do next, and on which model.**
Whoever finishes a task updates the "Right now" block to point at the next one.

Rule of thumb behind every row: **Opus for the decision, Sonnet for the diff.**
Where a written spec or plan already exists, Sonnet is sufficient — the plan carries
the rationale. Where no spec exists yet (a threshold to choose, a state machine to
design), Opus earns its cost.

---

## Right now

**Task:** Phase 13 — QA and the edge-case matrix, [`docs/test-plan.md`](test-plan.md).
Start from [`known-issues.md`](known-issues.md) and reference its IDs rather than
re-deriving the list.
**Model:** Sonnet 5.

**Review fixes landed 2026-08-04** on `fix/n-block-review`: the six Important
findings from the N-block code review. Two changed behaviour rather than tests —
`Scheduler` now rounds ease to two decimals (a recovered word was staying on
FR-18's list, off by 1e-15), and the reminder writes are ordered instead of one
loose `Task` per `DatePicker` tick. `ProgressSummary` is gone in favour of
`[ReviewState].learnedCount`. **The audit *does* reach the trend chart** once a
machine has studied on two days, and found four real defects on it — C-7 is
corrected in `known-issues.md`, and its `#if DEBUG` fixture is now about
determinism, not reach.

**The N-block is complete (2026-08-02).** Part B shipped on branch
`feat/progress-trend-and-hardest-words`, stacked on `feat/settings-and-about`:
FR-17's trend and FR-18's hardest words, both on `StatsService` — the type
`architecture.md` §3 named in Phase 9 and nobody wrote until now. **Every
requirement in `docs/requirements.md` now has an implementation**, and nothing on
`known-issues.md` blocks a release.

Three things from part B worth not rediscovering:

- **`easeFactor` cannot tell you whether a word was ever failed.** `Scheduler`
  adds +0.05 per pass, so one lapse plus four recalls lands back on exactly 2.50.
  FR-18 ranks by it anyway and filters below `startingEase`; a recovered word
  leaving the list is the behaviour we want.
- **A `LineMark` with one x value draws nothing.** After a first session every
  review shares a date, so the trend section rendered axis labels around an empty
  plot. Hiding below *two* days, not below one. Only running it found this — the
  ViewModel test asserted the series was right, and it was.
- **The new chart is on an audited screen the audit cannot reach** (C-7). It
  passed first time because the chart was not on screen. Needs the `#if DEBUG`
  fixture trick C-3 used.

Three things from part A worth not rediscovering:

- **`.task` does not fire when the app returns from the background.** Revoking
  notification permission means leaving for iOS Settings, so the reconciliation
  needs `onChange(of: scenePhase)` as well. No ViewModel test can catch it — such
  a test calls the method itself and cannot know whether anything else does.
- **A simulator tap that misses looks exactly like a broken feature.** Two taps
  on iOS Settings' own switch silently did nothing and produced a confident,
  wrong bug report; a short `touch_path` drag worked. Confirm the *precondition*
  changed before believing the app is at fault.
- **Adding a screen to the accessibility audit found two shipping contrast
  defects**, one of them on a link the audit still cannot reach. Second time a
  first-ever audit has paid for itself — see C-3 and C-6.

**CI has not run since 2026-08-01 — see E-6, and it needs you.** GitHub rejects
every job three seconds in, before any step: *"recent account payments have
failed or your spending limit needs to be increased."* The last green run was
the Phase 12 merge, so **Phase 11 has never been through CI**, and neither has
any of the work below. All of it is verified locally and by nothing else. This
is the cheapest high-value thing on the page to fix, and only you can do it.

**Branch state:** Phase 11 is merged (PR #8, 2026-08-02). Branch
`fix/known-issues-defects` is off `main` and carries six commits, unmerged:

- **D-1, D-3, D-4 fixed** (2026-08-02), joining D-2 and D-5. **The D section is
  closed.** StoreKit suite is 7 of 7 on iOS 18.5.
- **C-4** — the traceability matcher no longer counts a doc comment as a test,
  reports evidence by layer, and warns on app requirements with pipeline-only
  evidence. FR-16 is flagged, which is the shape that hid N-4. Self-test gated
  in CI.
- **C-3 closed, and it was hiding three real accessibility defects** on the
  completion and caught-up screens — two clipped at large Dynamic Type, one
  under the AA contrast floor. All shipping until now.
- **C-1 wired** (per-push skip + a dispatch-only adapter workflow), and its
  stated cause corrected: it claimed CI lands on iOS 26.5, which was never
  measured and is probably wrong. Cannot be closed until E-6 clears.

Then `feat/settings-and-about` (part A) is stacked on that, and
`feat/progress-trend-and-hardest-words` (part B) on top of it. **Three unmerged
branches, none through CI** — see E-6 above.

Remaining: **C-2** and **C-7** (the trend chart is unaudited), and the **U**
block, most of which needs you on a device rather than an agent. The N section
is closed.

**Start from [`docs/known-issues.md`](known-issues.md)** — every defect, gap and
deliberate compromise in the project, with IDs. Phase 13's `test-plan.md` should
reference them rather than re-deriving the list. The short version: the defects
are small and latent; the risk is that the purchase chain has never reached
Apple's servers (U-1), the app has never been run on its own iOS 17 minimum
(U-2), both performance NFRs are unmeasured (U-3, U-4), and 1000 Hindi sentences
are unread (U-8).

**Scope decided 2026-08-01: FR-13, FR-16, FR-17 and FR-18 all ship. All four
shipped 2026-08-02**, plus FR-4's adjustable cap, which the part A spec found had
never been implemented either. It ran as two specs — a Settings container for
FR-16/FR-13/FR-4, and `StatsService` for FR-17/FR-18 — rather than one, because
they share no types and touch different layers.

**Three things the bug session learned about this repo's tests**, all costly to
rediscover:

- **`-only-testing:` needs the Swift Testing function's parentheses.** Without
  them nothing matches and `xcodebuild` still prints `** TEST SUCCEEDED **`. A
  green that arrives before the fix should be checked with
  `xcrun xcresulttool get test-results tests --path <bundle>`.
- **`Task.yield()` cannot hold a concurrency race open.** It let the whole
  competing `load()` run to completion, and the test passed against the unfixed
  code. Park the suspension explicitly on a continuation — `GatedPackStore` in
  `LanguageSelectionViewModelTests.swift` is the pattern.
- **In the StoreKit suite a timeout looks exactly like a deadlock.** E-5's
  first-purchase cost is minutes; bound new tests there at 5 minutes, not 1.

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
