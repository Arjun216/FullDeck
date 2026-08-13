# Test plan & QA

Phase 13. What is tested, what is not, what the numbers are, and what a person
still has to do before this ships. Defect and gap IDs refer to
[`known-issues.md`](known-issues.md).

**Written 2026-08-04.** Every number here was measured on this date on an Apple
silicon Mac against an iPhone 17 simulator (iOS 26.5), unless it says otherwise.

---

## 0. The short version

The app is **not yet release-quality**, and the two things blocking it are the
same two that `known-issues.md` has been carrying since Phase 11. Neither is a
code defect:

1. **The purchase chain has never touched Apple's servers** (U-1). Every
   StoreKit test runs against `SKTestSession` or a fake. Nobody has ever bought
   a language.
2. **The app has never run on iOS 17.0, its own minimum** (U-2), or on any
   physical device. NFR-9 is the one requirement with no test naming it, and
   that is honest rather than an oversight.

Add to those one thing Phase 13 could not close on its own:

3. **CI has not executed since 2026-08-01** (E-6) — GitHub rejects every job on
   a billing failure. Everything in this document was verified locally and by
   nothing else. Clearing it needs Arjun.

Phase 13 found and fixed **one real defect** (the error screen, §3.1), added
**14 tests**, and measured the two performance NFRs. Nothing it found is a
blocker.

---

## 1. Coverage review

Measured with `--enable-code-coverage` and `xccov`, 2026-08-04.

| Layer | Line coverage | Floor | |
|---|---|---|---|
| `Packages/Domain` | **98.27%** | 90% | pass |
| `Packages/Data` | **91.86%** | 80% | pass |
| `pipeline` (validator + rules + review) | **100%** | 95% | pass |
| `FullDeck.app` | 87.60% | none, by design | — |

The app target has no floor on purpose (CLAUDE.md): a coverage percentage over
SwiftUI view bodies is noise, and chasing it produces tests written for the
number. What the per-file breakdown is *good* for is finding files that have
never executed at all, and it found three.

### What the breakdown showed, and what was done

| File | Was | Now | |
|---|---|---|---|
| `ErrorStateView.swift` | **0%** | covered | Never rendered by any test. It had a shipped accessibility defect nobody could see — §3.1. |
| `UNNotificationScheduler.swift` | **0%** | 3 tests on the part we author | The passthrough stays untested; `reminderRequest(hour:minute:)` came out of it and is asserted. |
| `AVSpeechService.swift` | 33% | still 33% | Deliberate — see below. |
| `StoreKitPurchaseService.swift` | 43% | unchanged | U-1. Needs Apple's servers, not a test. |

**`AVSpeechService` stays uncovered on purpose.** A test was written. It passes,
and it costs **55 seconds** — the first touch of `AVSpeechSynthesisVoice` loads
the system voice catalogue. Against that: the guard's consumer is already
covered with a fake (`StudyViewModelTests`, "unavailableVoiceDegradesGracefully"),
deleting the guard would produce *wrong audio* rather than a crash, and the
simulator's voice set is not the phone's, so passing would not have meant much.
It is step 7 of the manual checklist instead, where "does this sound like
French" can actually be answered.

### Requirement traceability

`scripts/trace-requirements.sh` reports **26 of 30** requirements named by at
least one test, up from 25 — the Swift Testing matcher only ever took the first
ID after the quote, so a test naming two requirements had its second silently
dropped.

The four unnamed:

- **NFR-1, NFR-7, NFR-8** — offline-first, local-only data, no tracking. These
  are claims about what the app *cannot* do, and no runtime test establishes
  one: a run that made no network request has not shown that none is possible.
  `scripts/privacy-audit.sh` audits the source and the dependency graph instead,
  which is what both requirements' acceptance criteria actually ask for. It runs
  in CI. Currently: no networking API in any source, no remote SPM dependency in
  either the packages or the Xcode project, no IDFA.
- **NFR-9** — iOS 17.0 minimum, iPhone, portrait. Genuinely unverified (U-2).

---

## 2. UI tests

**11 XCUITest methods**, all passing.

### The three critical flows the build plan names

| Flow | Covered by | |
|---|---|---|
| Complete a study session | `testNFR4NFR5NFR6AccessibilityAuditOnTheCaughtUpScreen` grades a full session to its end | yes |
| Reach the completion state | `testFR11AccessibilityAuditOnTheCompletionScreen`, via the `-uiTestAllWordsLearned` fixture | yes |
| Unlock a second language | `testFR14TappingALockedLanguageOpensThePurchaseSheet` — the sheet opens and says something honest | **partial** |

The third stops where U-1 stops. `xcodebuild test` from the command line gives
the app no StoreKit test environment on iOS 26.5, so the sheet reaches
`unavailable` rather than `ready`, and no purchase can complete. The adapter has
its own on-demand workflow (`.github/workflows/storekit-adapter.yml`) because
E-5 makes the first purchase in a process cost 91–324 s. **A completed purchase
has still never happened anywhere.**

### Two things about the UI suite that will bite whoever runs it next

**The audit can time out.** `testFR11AccessibilityAuditOnTheCompletionScreen`
failed once during this phase with `Audit failed to complete in time`
(`accessibilityAudit` error −56) on a loaded machine, and passed on re-run. It is
an infrastructure timeout, not a finding. Re-run before investigating; if it
becomes frequent, that is a machine-load problem rather than an app problem.

**Tests that need a card must not use the shared store** (C-8). The UI tests
share one on-disk SwiftData store across methods *and across runs on the same
machine*, so whether the Study screen has a card depends on how much that
simulator has already been studied. Two tests written in this phase failed for
exactly that reason after the performance suite spent the day's session — and
the failure reads as "no card on screen", which looks like a broken app.
`-uiTestFreshSession` is the fix: an in-memory store, twenty words, a full
session on every launch. Any test whose subject is *the card* should pass it;
tests whose subject is *persistence* (`testFR9…Backgrounded` aside, which needs
both) should not.

### Snapshot tests: decided against

The build plan says "if the chosen tooling supports it and it's currently
maintained". `pointfreeco/swift-snapshot-testing` is both. It is still the wrong
call here:

- It is the first third-party dependency the app would take, against an NFR-8
  audit that currently reads "no remote packages" as an absolute.
- Image snapshots of SwiftUI are brittle across OS and device — this project has
  already been bitten by iOS 26 rendering changes (E-2).
- The question a snapshot answers — "did this screen change?" — has no reviewer
  here. A one-developer project with no design review re-records the golden
  image and moves on, which is churn, not a gate.

What replaces it is stronger for this app: `performAccessibilityAudit()` on
every core screen, now including the largest accessibility text size (§3), which
asks "is this screen *usable*" rather than "is it identical".

---

## 3. Edge-case matrix

Every row the build plan names, plus where it is verified. **14 tests were added
for this section.** One row found a defect.

| # | Case | Verified by | Result |
|---|---|---|---|
| 1 | Empty / corrupt pack | `JSONPackStoreTests` (typed errors per `fixtures/invalid/`), `IntegrationTests.corruptPackSurfacesFailedStateEndToEnd`, `EdgeCaseUITests.testNFR10AnUnreadablePackShowsTheErrorStateRatherThanCrashing` | **defect found — §3.1** |
| 2 | Interrupted purchase | `PurchaseViewModelTests` — `.pending` (Ask to Buy), `failedRequestIsRetryable`, `restoreIsNotFooledByAConcurrentReload` | pass |
| 3 | Backgrounded mid-session | `EdgeCaseUITests.testFR9AStudySessionSurvivesBeingBackgrounded` — home, then `activate()`, same card | pass |
| 4 | Device date changed | `ClockChangeTests`, 6 cases | pass, with one documented answer — §3.2 |
| 5 | Very large Dynamic Type | `EdgeCaseUITests.testNFR5CoreScreensSurviveTheLargestAccessibilityTextSize` — audits four screens at AX XXXL | pass |
| 6 | VoiceOver navigation | `performAccessibilityAudit()` on 6 screens; a real VoiceOver walkthrough is manual step 9 | partial — see note |
| 7 | TTS voice unavailable | `StudyViewModelTests.unavailableVoiceDegradesGracefully` (fake); the real adapter is manual step 7 | partial |
| 8 | Rapid repeated input | `StudyViewModelTests.doubleTappedGradeIsAppliedOnce`, `SettingsViewModelTests.overlappingRemindersAreSerialized` | pass |

**On row 6.** The audit checks labels, contrast, hit areas and clipping. It does
not check whether the *reading order* makes sense or whether a session is
actually completable by ear. No automated tool checks that. Manual step 9.

### 3.1 The defect: the error screen was unreadable, and unreachable

`ErrorStateView` is what all three top-level screens show when content fails to
load. The bundled packs are valid, so **no sequence of taps could reach it** —
it sat at 0% coverage, and the accessibility audit had never seen it.

A `-uiTestUnreadablePack` fixture (a listed language with no pack behind it,
`#if DEBUG` + launch argument, like its `allWordsLearned` sibling) made it
reachable. The audit then failed it twice on the same node:

1. The description rendered in the system `.secondary` — under 4.5:1 on the warm
   background. This is the **fifth** appearance of a defect this codebase has
   fixed four times (`caughtUpView`, the Settings headers, the credits link, the
   completion screen) and the only one to reach `main`.
2. With the colour corrected it still reported "user will not be able to change
   the font size of this SwiftUI.AccessibilityNode", and an explicit
   `.font(.body)` did not move it.

The screen is now four ordinary views instead of a `ContentUnavailableView`.
`caughtUpView` uses the same component and passes, so this is not a verdict on
the component — the difference appears to be a *runtime* `String` description
rather than a literal. Rather than keep guessing at a system view's internals,
every attribute is now ours.
`EdgeCaseUITests.testNFR5AccessibilityAuditOnTheErrorState` is the regression
test.

**The lesson worth keeping:** the defect was not hard to find once the screen
could be rendered. It was invisible for four phases because nothing could render
it. A 0% file in a coverage table is not a number — it is a screen nobody has
looked at.

### 3.2 The device-clock answer worth stating out loud

Moving the device clock **back** gives that calendar day its own new-word
allowance, so a learner can study more than FR-4's cap by changing the date.

This is intended. The cap is *per calendar day*; §4 rules out treating the
learner as an adversary; and a local-only app with no server cannot know the
real date anyway. `ClockChangeTests` asserts it rather than leaving it as an
accident someone later "fixes".

---

## 4. Performance

**Not a CI gate**, per the build plan: a shared GitHub runner cannot hold a
100 ms assertion steady, and gating it would produce flakes rather than signal.
`.github/workflows/ci.yml` skips `PerformanceUITests`. Run it with:

```bash
scripts/measure-performance.sh
```

| Requirement | Target | Measured | |
|---|---|---|---|
| **NFR-3** grade → persist → next card ready | ≤ 100 ms | **avg 1.87 ms** (0.61–8.46, n=10) | pass, with three orders of magnitude to spare |
| **NFR-2** cold launch | ≤ 2.0 s | **avg 2.07 s** (1.70–2.57, n=5) | **over target — unresolved** |

### NFR-3 is measured in-process, and why that matters

A card-advance test lived in `PerformanceUITests` and reported **1.49 s**. That
number was the test harness: `waitForExistence` polls on roughly one-second
intervals, so every XCUITest timing has a ~1 s floor no matter how fast the app
is. **A 100 ms target is below XCUITest's resolution**, and any project measuring
UI latency that way is measuring its own runner.

`FullDeckTests/GradeLatencyTests` measures the same transition in-process
against a real *on-disk* SwiftData store (`inMemory: false` — the shipped store
writes to disk, and measuring an in-memory one would measure a persistence layer
nobody runs). That covers scheduling, persistence, and picking the next card:
every millisecond between the tap and the next card being ready to draw.

It does not cover the SwiftUI render or the display link. "No perceptible frame
drops (target 60 fps)" is the other half of NFR-3 and needs Instruments on a
device — manual step 12.

### NFR-2 is over target, and the number is not trustworthy either

2.07 s against a 2.0 s target, on hardware faster than the baseline device, is
close enough to matter. But the measurement is not good enough to convict:

- It is a **Debug** build. Debug launches slower — no optimization, testability
  enabled, and `XCTApplicationLaunchMetric` includes XCUITest's own attach.
- A **Release** run was attempted and produced *worse* numbers (avg 3.5 s, one
  run at 6.07 s) alongside a `CoreSimulator … server died` error in the log.
  That run is invalid, and it says something about simulator launch timings in
  general: the spread here (1.70–2.57 s in Debug) is wider than the margin being
  measured.

**Conclusion: NFR-2 is unmeasured, not failed.** A simulator cannot settle it.
The acceptance measurement is a Release build on the baseline device — which is
what TestFlight installs — and it is manual step 11.

---

## 5. Content QA — the sentence spot-check (spec D4)

Every machine-checkable rule (VR-1…VR-18) runs on every `packgen pack`. What no
rule catches is a sentence that is *valid and still wrong*: correct grammar,
only permitted vocabulary, and nothing a French speaker would say.

```bash
uv run --project pipeline packgen sample fr          # draw 100, seeded
# fill in the `verdict` column: ok / bad, and `note` for anything rejected
uv run --project pipeline packgen review fr          # queue the rejects
uv run --project pipeline packgen generate fr --retry && uv run --project pipeline packgen pack fr
```

- The sheet is `pipeline/work/fr/review/spot-check.csv`, committed. **It is
  drawn and waiting for Arjun; 0 of 100 verdicts are recorded.**
- Seeded (`--seed 13`), so "the 100 sentences we checked" survives a
  regeneration and can be re-drawn identically.
- CSV because it opens in Numbers, in Excel and in a text editor, and the
  reviewer is not a programmer at the moment they are reviewing.
- A **blank verdict is unreviewed, not approved** — the distinction matters when
  the question is "did we actually check 100 sentences". An unrecognised verdict
  raises rather than being guessed at: a typo that silently approves a sentence
  defeats the exercise.
- Rejections join the validator's own failures in `work/fr/retry/`, so the
  existing loop regenerates them. A human saying "no one says that" and VR-10
  saying "uses a rarer word" are the same problem from the pipeline's side.

**This is a release blocker in the sense that D4 asks for it and it has not been
done.** It needs a French speaker for an hour, not an agent.

---

## 6. Manual QA checklist

Run on a **physical iPhone**, on a **Release/TestFlight build**, before any
release. Nothing in this list can be automated — each item is here because a
machine cannot answer it.

Setup: delete the app first so the run starts from a genuine first launch.

| # | Step | Requirement | Pass when |
|---|---|---|---|
| 1 | Launch for the first time. | FR-1, FR-2 | Languages screen; Français selectable, हिन्दी shows a padlock. |
| 2 | Select Français, go to Study. | FR-3 | A card appears with a word and its part of speech. |
| 3 | Tap Reveal. | FR-5, FR-6 | Answer and exactly one example sentence appear — and the sentence uses no word you have not met. |
| 4 | Grade a card each way; note the words. | FR-8 | A forgotten word returns in the same session or the next day; a known one does not. |
| 5 | Swipe a revealed card right, then left. | FR-5 | The swipe grades it the same way the buttons do. |
| 6 | Grade the whole session to its end. | FR-12 | "You're caught up", with the next review date. |
| 7 | **Tap "Hear the word" and "Hear the sentence".** | FR-7 | Audio plays, and it sounds like **French** — not English reading French letters. Then turn on Airplane Mode and repeat: TTS is on-device and must still work. |
| 8 | Settings → turn on the daily reminder, pick a time 2 minutes out. | FR-13 | The notification fires at that time. **Then leave the app for a day and confirm it fires again** — `repeats: true` is unit-tested, but only a second day proves it. |
| 9 | **Turn VoiceOver on. Complete a full session by ear alone.** | NFR-4 | Every control announces what it is; reading order matches the screen; nothing is announced as a bare "button". |
| 10 | Settings → Accessibility → largest text size. Visit all four screens. | NFR-5 | No truncation, clipping or overlap. (Audited automatically too, but see it.) |
| 11 | **Force-quit, then cold-launch and time it with a stopwatch.** | NFR-2 | Interactive screen in ≤ 2.0 s. **This is the open question from §4 — record the number.** |
| 12 | Xcode → Instruments → Animation Hitches, during a session. | NFR-3 | No sustained hitches while revealing and advancing. |
| 13 | Grade a card, then force-quit immediately. Relaunch. | NFR-11 | The grade survived. |
| 14 | Airplane Mode: complete a session, check Progress. | NFR-1 | Everything works except purchase/restore. |
| 15 | **Buy हिन्दी with a real sandbox account.** | FR-14, U-1 | The purchase completes, the padlock clears, Hindi is studyable. |
| 16 | Delete and reinstall. Tap Restore Purchases. | FR-15 | Hindi unlocks again without paying. |
| 17 | Tap Restore with nothing bought. | FR-15 | It says "No previous purchases found" — not silence (D-1). |
| 18 | Settings → Credits. | FR-16 | The wordfreq attribution and a working CC-BY-SA 4.0 link. |
| 19 | Progress tab after two days of study. | FR-10, FR-17, FR-18 | Count, trend chart with two lines, hardest-words list. |
| 20 | **Install on a device running iOS 17.0.** | NFR-9, U-2 | It launches and a session completes. Never once been done. |

Steps 7, 8, 9, 11, 15 and 20 are the ones that have **never been performed by
anyone**. They are bolded for that reason, not because they are harder.

---

## 7. TestFlight

### Setting it up

1. **App Store Connect → My Apps → +** — the bundle id `arjunpathak.FullDeck`
   must already exist as an App ID.
   [`app-store-connect-setup.md`](app-store-connect-setup.md) has what was
   already done in Phase 11 for the in-app purchase.
2. **Xcode → Product → Archive** (a Release build, on a real device destination
   — "Any iOS Device", not a simulator). Distribute App → TestFlight.
3. **Export compliance.** The app uses no encryption beyond what iOS provides,
   so add `ITSAppUsesNonExemptEncryption = false` to Info.plist and this stops
   being asked on every upload.
4. **Internal testing** first — up to 100 of your own devices, no review
   required, available in minutes. Put the build here and run the whole of §6 on
   it yourself before anyone else sees it.
5. **External testing** — up to 10,000 testers, needs a Beta App Review (usually
   a day). You need a public link, a description of what to test, and a contact
   email.
6. **The in-app purchase works in TestFlight** against the sandbox, and testers
   are not charged. This is how U-1 finally closes: step 15 of §6, performed by
   someone who is not you, on a device that is not yours.

### What to ask testers for

Keep it to five questions. A long form gets no answers.

1. **"Did any example sentence sound wrong, unnatural, or like something no one
   says?"** — the highest-value question in the whole beta, and the one thing
   testers can do that no tool can. Ask for the *word* it belonged to. This
   feeds §5's reject loop directly.
2. "Did anything crash, freeze, or show an error?"
3. "Was the audio pronunciation right?" — a heritage speaker will hear things
   the spot-check reader misses.
4. "Did the app ever feel slow?" — the honest way to ask about NFR-2/NFR-3
   without asking for a stopwatch.
5. "Was anything confusing the first time you saw it?" — asked once, of new
   testers only. It expires; a tester who has used it a week cannot answer it
   any more.

**Recruit for the language, not for testing.** Two or three French learners and
one native or heritage speaker will find more than twenty general testers,
because question 1 is the one that matters and only they can answer it.

**Do not ask** for feature requests. §4 of `CLAUDE.md` has already decided what
this app is not, and a beta feedback form is a bad place to relitigate it.

---

## 8. Verdict

**Not release-quality yet.** Not because of anything found in Phase 13 — the
suite is green, the domain is at 98%, the one defect found is fixed with a
regression test, and NFR-3 has three orders of magnitude of headroom.

It is not release-quality because of what has **never been done**, all of which
needs a person and a phone:

| Blocker | Why it is blocking | Who |
|---|---|---|
| No purchase has ever completed (U-1) | FR-14 is a third of the business model and has only ever run against a fake | Arjun, via TestFlight sandbox |
| Never run on a device, never on iOS 17.0 (U-2, NFR-9) | The minimum supported OS is a claim, not a fact | Arjun |
| 100 sentences unreviewed (D4, §5) | The sheet is drawn; 0 verdicts recorded | A French speaker |
| VoiceOver walkthrough never done (NFR-4, §6 step 9) | The audit checks labels; it cannot check whether a session is completable by ear | Arjun |
| CI has not run since 2026-08-01 (E-6) | "The suite is green" currently means "green on one laptop" | Arjun — it is a billing failure |
| NFR-2 unmeasured (§4) | 2.07 s on a simulator, target 2.0 s, instrument too noisy to convict | Arjun, §6 step 11 |

None of these is a code change. The engineering work of Phase 13 is done; what
remains is the part that was always going to need hands, ears, and a phone.
