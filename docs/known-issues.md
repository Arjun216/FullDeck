# Known issues

Every defect, gap, and deliberate compromise in the project as of **2026-08-01**,
after Phase 11, and kept current — last updated **2026-08-02**. One place, so Phase 13 has a target list and Phase 14's
`MAINTENANCE.md` has something to inherit.

Each entry has an ID. Phase 13's `docs/test-plan.md` should reference them.

**Categories, in descending order of "should this worry me":**

| | Meaning |
|---|---|
| **D** | Defect. Something is wrong. |
| **U** | Unverified. No evidence either way — the honest majority. |
| **N** | Requirement with no implementation. |
| **L** | Deliberate limitation. Decided, documented, not to be "fixed" casually. |
| **E** | Toolchain/environment, not our code. |
| **C** | Test-coverage gap. |
| **W** | Content waiver. |

**Read E-6 first. CI has not executed since 2026-08-01** — GitHub rejects every
job on a billing failure, three seconds in, before any step. The last green run
predates Phase 11. Everything since has been verified locally and by nothing
else, so "CI is green" is currently unavailable information rather than a pass.
Clearing it needs Arjun, not an agent.

**Every D is now closed** (D-1 through D-5, all fixed 2026-08-02). The section is
kept rather than deleted: each entry records what the bug taught, and three of
them taught something about the *tests* rather than the code.

The biggest thing on this page is not any single row. It is that **the entire
purchase chain has never touched Apple's servers** (U-1), and **the app has never
been run on its own minimum OS** (U-2).

**N-4 is closed (2026-08-02): the credits screen exists, and nothing on this page
blocks a release outright any more.** N-1 closed with it. What remains under **N**
is N-2 and N-3, the two Progress requirements, which are part B of the N-block and
have their own spec still to be written.

---

## D — Defects

All five are fixed. Kept for the reasoning, and because two of them were only
ever *found* by reading rather than by a test — which is the argument for keeping
this page at all.

### D-1 · Restore's before/after comparison raced its own reload — FIXED 2026-08-02
`restore()` derived its before-snapshot from `state` via a `unlockedCodes()`
method that answered `[]` for every state but `.ready` — including the
`.loading` any concurrent reload passes through. And one genuinely is
concurrent: `StoreKitPurchaseService.refreshEntitlements()` yields on
`entitlementChanges` *during* `purchases.restore()`, and `LanguageSelectionView`'s
second `.task` answers that by calling `load()`.

So a restore that found nothing read `before == []`, then `after == {fr}`, and
**silently swallowed "No previous purchases found."** — the learner taps Restore
and the screen says nothing at all.

The snapshot is now a stored `unlockedCodes` property written by each successful
`load()`, so it never passes through a false empty. The *after* read was never at
risk: `await load()` returns and the comparison runs with no suspension between.

**Two things learned, both worth keeping:**

*`Task.yield()` cannot hold a race window open.* The first attempt started a
reload in a `Task` and yielded once — the reload ran to **completion**, `state`
was `.ready`, and the test passed against the unfixed code. A diagnostic
`#expect(state == .loading)` is what proved the window never opened. The test now
uses a `GatedPackStore` that parks `availablePacks()` on a continuation until
released.

*A passing `xcodebuild` run can mean zero tests ran.* `-only-testing:` needs the
Swift Testing function's **parentheses** — `.../restoreIsNotFooledByAConcurrentReload()`.
Without them nothing matches, and it still prints `** TEST SUCCEEDED **`. Verify
with `xcrun xcresulttool get test-results tests --path <bundle>` when a red is
expected and green appears.

**Where:** [LanguageSelectionViewModel.swift:31](../FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift:31)
**Test:** `FR-15 a reload landing mid-restore doesn't swallow the no-purchases message`

### D-2 · `entitlementChanges` carried no identity — FIXED 2026-08-02
The stream was `AsyncStream<Void>`. It is now `AsyncStream<Set<LanguageCode>>`,
emitting the whole unlocked set on every change, so a waiter can wait for the
state it wants instead of for "something happened". The adapter's cache became
`Set<LanguageCode>` at the same time, which deleted the `rawValue` juggling — the
fix is a smaller file than the bug was.

`revocationRelocks` now passes; the whole suite is **6 of 6 on iOS 18.5**.

**Two things learned in the fixing, both worth keeping:**

*Carrying state is necessary but not sufficient.* The first attempt waited for
`!unlocked.contains(hindi)` and still failed — because `start()`'s launch refresh
publishes an **empty** set before the purchase, and *not yet bought* is
indistinguishable from *refunded* as a state. The test has to wait for the
**transition**: Hindi seen present, then absent.

*The buffering is the real hazard.* `AsyncStream` queues elements yielded before
anyone iterates, so by the time a test starts reading there are already stale
snapshots waiting. Any future "wait for a change" code has the same trap.

**Still open, still latent:** the stream is single-consumer. `AsyncStream` hands
each element to exactly one iterator, one view reads it today, and a second
observer would split events rather than both receiving them. Not fixed —
one reader, and a broadcast for a hypothetical second is not worth building yet.

**Where:** [PurchaseService.swift:32](../FullDeck/FullDeck/Services/PurchaseService.swift:32),
[StoreKitPurchaseService.swift](../FullDeck/FullDeck/Services/StoreKitPurchaseService.swift)

### D-3 · `record()` finished a transaction before deciding whether it was ours — FIXED 2026-08-02
`await transaction.finish()` ran before the `guard let code =
ProductIdentifier.languageCode(...)`, so a transaction for a product of ours that
is not a language unlock was marked handled by code that then ignored it. Harmless
while there is only one product; the day a second exists it is a purchase that
vanishes.

`finish()` now sits **after** the guard. Finishing is a claim of responsibility —
it is what stops StoreKit re-delivering — so declining to finish is the honest
answer for a transaction nobody has handled, and re-delivery is how a later
version gets its chance.

**Proven by a test that had to invent a product.** `FullDeck.storekit` gained
`arjunpathak.FullDeck.notALanguage`, bought via `session.buyProduct` so it arrives
through `Transaction.updates` — the only route into `record()` with a foreign
product, since `purchase(_:)` builds its identifier from a language code and can
never produce one. The assertion is that the transaction is still listed in
`StoreKit.Transaction.unfinished`; against the old code that list came back empty.

The test takes **~120–150 s**: it is the first purchase in the process, which is
E-5, not a hang. The first attempt bounded it at `.timeLimit(.minutes(1))` and the
timeout looked exactly like a deadlock — raising the bound to 5 minutes is what
told the two apart.

**Where:** [StoreKitPurchaseService.swift:125](../FullDeck/FullDeck/Services/StoreKitPurchaseService.swift:125)
**Test:** `FR-14 a transaction that is not a language unlock is left unfinished`

### D-5 · The scheme's StoreKit config path never resolved — FIXED 2026-08-02
`StoreKitConfigurationFileReference` was `../../../FullDeckTests/FullDeck.storekit`
in both `TestAction` and `LaunchAction`, which resolves to
`Language_App/FullDeckTests/`. The file is at `Language_App/FullDeck/FullDeckTests/`
— one `../` too many, wrong since Phase 11.

Xcode reports it as *"StoreKit Configuration file for scheme FullDeck can't be
found"*. No filtered `xcodebuild` output ever showed it; Arjun found it in the IDE.

**Consequence:** running the app (⌘R) never had a test store, so any manual
purchase check would have hit the real App Store. It does **not** affect
`StoreKitPurchaseServiceTests`, which loads the file by URL from the test bundle
and never consults the scheme — which is exactly why it stayed invisible.

**Where:** `FullDeck.xcodeproj/xcshareddata/xcschemes/FullDeck.xcscheme`
Fixed to `../../`. Verify with ⌘R: the purchase sheet should show $0.99 with no
Apple Account prompt.

### D-4 · "The store isn't reachable" was indistinguishable from "no such product" — FIXED 2026-08-02
`PurchaseViewModel.loadProduct()` used `try?`, which collapses a *thrown store
error* and a *nil product* into the same branch. The collapse is deliberate and
correct **for the learner** — neither case is their fault and neither is
actionable — but it left nothing at all to tell them apart during App Store
Connect setup, where an inactive Paid Applications agreement returns no products
from a store that is perfectly reachable.

**The shipped copy is unchanged.** The `try?` became a `do`/`catch` with an
explicit `guard`, and the two branches now set `unavailableCause`
(`.noSuchProduct` / `.storeError`) and log which one fired. Both still produce
`.unavailable("The store isn't reachable right now.")`.

A `#if DEBUG` branch was considered and rejected: it would have made the shipped
string the one path no test ever exercises. A property plus a log line keeps one
code path and makes the distinction assertable — the two existing NFR-10 tests
gained a cause assertion each rather than a new test appearing beside them.

`os.Logger` is device-local and sends nothing anywhere, so this does not reopen
**L-2**.

**Where:** [PurchaseViewModel.swift:66](../FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift:66)
**Still true:** [`app-store-connect-setup.md`](app-store-connect-setup.md) leads
with the agreement, and should keep doing so — a log line only helps someone who
thinks to look at the console.

---

## U — Unverified

Nothing here is known to be broken. Nothing here is known to work either.

### U-1 · The purchase chain has never reached Apple's servers
Every Phase 11 test ran against a local `.storekit` configuration file or a fake.
Product lookup, purchase, `AppStore.sync()`, Ask to Buy, and refund have not been
exercised against App Store Connect once.

**The delete/reinstall/Restore cycle is the only real test of FR-15**, and a local
config file cannot perform it — it never leaves the device.
**Owner:** Arjun. **Steps:** [`app-store-connect-setup.md`](app-store-connect-setup.md) §5.

### U-2 · The app has never been run on iOS 17.0, its own minimum
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` on all four configurations, and both packages
declare `.iOS(.v17)`. There are **no `@available` guards anywhere in the app**, so
the compiler enforces that no newer API is referenced — the *build* half of NFR-9
is genuinely proven.

The *run* half is not. CI and every local run use iOS 26.5. Runtime behaviour
differences (SwiftUI layout, `ContentUnavailableView`, StoreKit 2, sheet
presentation) would not show up.
**Phase 13:** add one CI destination on the oldest runtime available, or drop the
claim to what is actually tested.

### U-3 · NFR-2, cold launch ≤ 2.0 s — never measured
Requirements name Phase 13 as the measurement point and an iPhone SE (3rd gen) /
iPhone 12 class baseline. No number exists yet.

### U-4 · NFR-3, reveal and advance ≤ 100 ms, 60 fps — never measured
Same as above. Note the swipe gesture and `@ScaledMetric` work landed after these
targets were written, and neither has been profiled.

### U-5 · NFR-1 offline session — code-audited, not run
The audit is genuinely strong: there is no networking code in the app target or
either package, so offline operation holds by construction rather than by a check
that could regress. The airplane-mode walkthrough still hasn't been done.
**Checklist:** [`phase-10-verification.md`](phase-10-verification.md).

### U-6 · NFR-4 VoiceOver walkthrough — needs a human
The automated audit proves labels *exist*. It cannot judge whether they are
*meaningful*, which is the actual requirement. Needs a device.

### U-7 · NFR-5 at AX5 — automated only
`performAccessibilityAudit()` catches clipping at large sizes on every push. The
manual pass at the largest slider position hasn't happened.

### U-8 · The 1000 Hindi sentences have had a spot-check, not a read
Spec decision D4 requires a human read before beta. French got one; Hindi has had
sampling only. 1000 sentences.
**This is a Phase 13 deliverable, and it is the largest single unit of human work left.**

### U-9 · The additive-only entitlement refresh cannot be tested before release
`refreshEntitlements()` only ever adds; only an explicit `revocationDate` removes.
It defends against open iOS 26.x reports of `Transaction.currentEntitlements`
returning empty for a valid non-consumable — **production-only, does not reproduce
in sandbox**. No amount of testing before shipping will exercise it.

Load-bearing. Do not "simplify" it into a wholesale cache replace.
**Where:** [StoreKitPurchaseService.swift:101](../FullDeck/FullDeck/Services/StoreKitPurchaseService.swift:101)

---

## N — Requirements with no implementation

These are in `docs/requirements.md` and have no code. Not bugs — decisions that
were never revisited. Each needs either an implementation or a scope cut before
Phase 14 writes release notes claiming otherwise.

**All closed as of 2026-08-02.** Every requirement in `docs/requirements.md` now
has an implementation, and `architecture.md` §3's `StatsService` — named in
Phase 9, written in neither — exists. The section stays because how these were
*found* is the lesson: N-4 was a licence obligation the traceability report
called covered, and N-5 was found by reading FR-4's acceptance criterion against
the code. Neither was findable by any automated check this project has.

### N-1 · FR-13, the optional daily reminder — FIXED 2026-08-02
Built on the Settings screen, over a Presentation-owned `NotificationScheduler`
port. `UNNotificationScheduler` is the only file importing `UserNotifications`.
Eight behaviours are covered against a fake; one constant request identifier is
what makes "exactly one reminder" true without bookkeeping.

**The bug a fake could never have caught:** `.task` fires on *view* appearance,
and the only way to revoke notification permission is to leave for iOS Settings
and come back — which resumes the app without re-creating the view. The toggle
therefore stayed on for a reminder that could no longer fire. Fixed with
`onChange(of: scenePhase)`. A ViewModel test calls `refreshAuthorization()`
itself and so can never tell you whether anything else does; only running it by
hand does.

**A false alarm worth recording too.** The first manual run looked like it had
found exactly that bug — the toggle stayed on after "revoking" permission. It had
not: the tap on iOS Settings' own switch never landed, so nothing was revoked and
the app was right. Two subsequent taps at the same coordinates also silently did
nothing; a short `touch_path` drag worked. **On this simulator a tap that misses
and a feature that is broken look identical**, and the fix was only justified
afterwards, on how `.task` works rather than on the observation.

### N-2 · FR-17, learning-over-time trend — FIXED 2026-08-02
`StatsService.trend(states:today:)` — the type `architecture.md` §3 named in
Phase 9 and nobody wrote — plus a Swift Charts section on Progress. Pure Domain,
five tests, no new persistence: `firstReviewedDate` and `learnedDate` were
already on `ReviewState`.

**Both curves are cumulative, and that was the decision.** FR-17 asks for words
that have *moved into* learning and into learned, which is cumulative, so both
rise and the gap between them is the in-flight set. Plotting the *currently*
learning population instead would fall as words graduate — a line that drops
when the learner succeeds, on the one screen whose point is the climb.

**`learnedInLast` reads off the series**, never recomputes from the states, so
the accessibility label and the curve cannot disagree. Both ends inclusive,
which is what makes the 7-day figure match FR-17's own acceptance example.

**The bug only running it could find:** the spec said hide the trend when the
series is empty. After a first session every review shares one date, and a
`LineMark` with a single x value draws no segment — so the section rendered
axis labels around an empty plot. The rule is now "fewer than two days". The
ViewModel test asserted the series was right, and it was; the series was never
the problem.

### N-3 · FR-18, hardest words — FIXED 2026-08-02
`StatsService.hardestWords(in:states:limit:)`, five on the Progress screen,
read-only. Five tests. No schema change.

**Ease factor cannot answer "has this word ever been failed."** `Scheduler`
adds **+0.05** on every pass, so a word that lapsed once and has since been
recalled four times sits at exactly 2.50 — byte-identical to one never failed.
FR-18 anticipates this in its own text ("ease factor; *optionally a lapse
count*") and `ReviewState` has no lapse count.

Decided: rank by ease ascending, surface only words below
`ReviewState.startingEase`. That satisfies the acceptance as written — a
never-failed word never drops below the start, so it is never surfaced — and a
recovered word leaving the list is correct rather than lossy. FR-18 asks what
the learner *finds* hard; a permanent record of old mistakes is closer to a
shame list than to help.

A `lapses: Int` field was rejected on cost: a Domain model change, a SwiftData
migration, and every construction site including fixtures, to deliver behaviour
we would then have to soften.

### N-4 · FR-16, the credits screen — FIXED 2026-08-02
**Was the one item on this page that stopped a release.** wordfreq's data is
CC-BY-SA 4.0; `CLAUDE.md` requires attribution "in pack metadata **and the app's
credits**", and FR-16's acceptance says a credits screen must be reachable from
the app. The pack-metadata half had been enforced by `PackValidator` since Phase
6 — which is precisely what made the missing half survive four phases.

Now a Credits section on the Settings screen, two taps from launch, reading each
pack's own `PackSource` rather than a hardcoded string, so a third pack from a
different source appears with no app code touched (ADR-004). Grouped by source,
so two wordfreq packs render one credit naming both languages. The licence
hyperlinks only when the string is recognised and degrades to plain text
otherwise — text attribution alone satisfies CC-BY-SA.

**Reachability is the acceptance criterion, and needed a UI test.** No ViewModel
test can prove a screen can be got to, which is the shape of the original gap.

### N-5 · FR-4's adjustable half had no implementation — FIXED 2026-08-02
Found while writing the Settings spec, not by any tool. `SessionBuilder` and
`StudyViewModel` both accepted `newWordCap`; `ContentView` never passed one, so
`N` was permanently 10 and FR-4's "user-adjustable" clause was fiction.

**Nothing automated would have caught this.** FR-4 is named by app *and* Domain
tests — all covering cap *enforcement*. The layer-aware traceability report added
for C-4 sees app-layer coverage and is satisfied. Only reading an acceptance
criterion against the code finds it, which is also how N-4 surfaced. That is two
half-unimplemented requirements found in two days by hand and none by machine;
see C-4.

FR-4's acceptance was amended at the same time, from "next day" to "next
session" — see `docs/requirements.md` and Decision 7 of the spec.

> **Scope decision, made 2026-08-01: all four ship.** FR-13, FR-17 and FR-18 are
> in; FR-16 was never optional. Two consequences worth stating before anyone
> starts:
>
> 1. **There is no settings surface in the app.** Three tabs, no fourth screen,
>    no toolbar entry point. FR-13 needs somewhere to toggle the reminder and
>    pick a time, and FR-16 needs somewhere to put credits. They want the same
>    container — design it once.
> 2. **FR-17 and FR-18 both land on the Progress screen**, which currently shows
>    one number. §4 of the requirements rules out activity dashboards
>    (time-spent, review counts, streak chains); FR-17's own text says the trend
>    is reconstructed from milestone dates, *not* a study-activity log. Build to
>    that line.
>
> This is more work than it looks: a new screen, a notification permission flow,
> `StatsService` (named in `architecture.md` §3, never written), and two progress
> views. Closer to its own phase than a Phase 13 tail.
>
> **Update 2026-08-02.** Split into two parts, and part A shipped: the Settings
> screen carrying FR-16, FR-13 and FR-4's missing half
> ([spec](superpowers/specs/2026-08-02-settings-and-about-design.md),
> [plan](superpowers/plans/2026-08-02-settings-and-about.md)). Part B — FR-17,
> FR-18 and `StatsService` — is untouched and needs its own spec. The two parts
> share no types and touch different layers, which is why they were split.

### N-6 · The app's display name is "FullDeck", not "Full Deck"
`CLAUDE.md` records the user-facing name as **Full Deck**, set via the target's
Display Name. No `INFOPLIST_KEY_CFBundleDisplayName` exists in the project, so
iOS falls back to the bundle name: the Home Screen, the Settings app and the
notification permission prompt all say "FullDeck".

Caught because the permission prompt reads *"FullDeck" Would Like to Send You
Notifications* while the app's own denial note says "Full Deck" — the two are
visibly inconsistent on adjacent screens.

**Not fixed here:** it is a `project.pbxproj` build-setting addition, and those
go through Xcode rather than a text edit. One setting, `INFOPLIST_KEY_CFBundleDisplayName = "Full Deck"`,
on all four configurations.

---

## L — Deliberate limitations

Documented decisions. Changing one means revisiting its rationale, not just its code.

| ID | Limitation | Where the reasoning lives |
|---|---|---|
| **L-1** | Scheduling is day-granular; a lapsed word returns tomorrow, not in ten minutes | [Scheduler.swift:11](../Packages/Domain/Sources/Domain/Scheduler.swift:11) |
| **L-2** | No analytics, crash reporting, or telemetry of any kind — not a placeholder | [`phase-10-verification.md`](phase-10-verification.md) NFR-7/8 |
| **L-3** | A revoked language keeps its study history on disk; a re-purchase restores progress intact | [LanguageSelectionViewModel.swift:61](../FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift:61) |
| **L-4** | The validator has no nukta-insensitive lemma comparison; nine waivers instead | [`phase-12-verdict.md`](phase-12-verdict.md) §6 |
| **L-5** | Locked rows are **not** `.disabled()` — SwiftUI's dimming took the label to 3.33:1, under AA. FR-1 is enforced in `select()` | [LanguageSelectionView.swift:132](../FullDeck/FullDeck/Views/LanguageSelectionView.swift:132) |
| **L-6** | The app target still compiles in Swift 5 mode with migration aids; only Domain and Data enforce Swift 6 strict concurrency | `CLAUDE.md`, [`architecture.md`](architecture.md) §4 |
| **L-7** | `suspicious_lemmas` is Latin-tuned and flags real Hindi verbs; it is a report, never a gate | [`phase-12-verdict.md`](phase-12-verdict.md) §4 |
| **L-8** | VR-16's manifest half is unimplemented — it needs the pack manifest | [validate.py:168](../pipeline/src/packgen/validate.py:168) |
| **L-9** | The wordfreq pool scan takes tens of seconds; it runs once per language | [words.py:78](../pipeline/src/packgen/words.py:78) |

L-6 is the one with a real expiry date: it is deferred to its own phase, tracked
separately from Phase 10, and the `nonisolated` annotations Phase 11 had to add
across `PurchaseService` are what the deferral costs.

---

## E — Toolchain and environment

Not our code. Each one cost real time to diagnose, so each is written down.

### E-1 · `SKTestSession` is broken on iOS 26.5 — and works on 18.5
Every `SKTestSession` call on an iOS 26.5 simulator fails with
`SKInternalErrorDomain Code=3`, *"Error saving configuration file"*. The store
never populates, so `price` returns nil and `purchase` throws
`.productUnavailable`. On **iOS 18.5 the identical code, config and command
work** — five of the six tests pass. Same bug signature is filed against
Flutter's StoreKit plugin on 26.3/26.4.

Nothing in this project causes it and nothing in this project fixes it. Run the
suite on an 18.x simulator.

Three wrong turns on the way here, all worth not repeating:

1. **The skip guard queried before any session existed.** `.enabled` is a trait,
   evaluated before the suite's `init()` — and `init()` is where the session is
   created. So it could only ever pass via the scheme, which meant it skipped in
   the Xcode IDE for the same reason it skipped from the CLI. **An IDE run with
   that guard proved nothing**, and it is what made the runtime look innocent.
2. **The `.storekit` file was schema version 4**, hand-written from a public
   example; Xcode 26 writes version 5. Regenerating it changed no behaviour. The
   committed file is now Xcode's own output regardless.
3. **The scheme's config path had one `../` too many** and had never resolved
   since Phase 11 — see D-5. Irrelevant to this suite, real for the app.

Filtered `xcodebuild` output is what hid the diagnosis for two days: the
`[SKTestSession] Error saving configuration file` lines were printed on every
run, and every grep dropped them.

### E-5 · The first StoreKit purchase in a process costs minutes — NOT FIXED
`purchaseUnlocks` takes **91–324 seconds**. Measured across four runs on iOS 18.5:

```
baseline                    236 s / 91 s   (two clones, same run)
app's listener removed      324 s / 119 s
```

**A 2.6× spread on identical code**, and removing the app's competing
`Transaction.updates` listener made no difference — that hypothesis is dead, and
the variance is larger than any effect a single before/after run could detect.

It is **the first purchase in the process**, not purchasing generally:
`purchaseFailureThrows` runs the same `service.purchase()` path in 4–9 s, and
`revocationRelocks` completes a *successful* purchase in 5–13 s. Everything after
the first one is fast. That is a one-time initialization cost inside StoreKit,
in the same family as E-1, and not something this project's code causes or can
remove.

**Confirmed independently 2026-08-02 by D-3's new test**, which does not use
`product.purchase()` at all — `session.buyProduct()` alone. Run on its own it took
**116–147 s**; run inside the full suite, after `purchaseUnlocks` has already paid
the initialization cost, it took **2.7 s**. Same code, same store, 40×. Whatever
this is, it is per-process and it is not the purchase API being called.

**A timeout here looks exactly like a deadlock.** That test was first bounded at
`.timeLimit(.minutes(1))` and failed at 60.000 s, which reads as a hang; raising
the bound to 5 minutes is the only thing that distinguished the two. Bound new
tests in this suite generously.

**Practical consequence:** the adapter suite cannot go in a per-push gate. It
already skips on iOS 26.5 (E-1); if an iOS 18 destination is ever added, exclude
this suite from it and run it on demand or nightly instead.

**Do not "fix" this by replacing `product.purchase()` with
`session.buyProduct()`** — that would make the test fast by no longer testing the
adapter's purchase path, which is the one thing it exists to cover.

### E-6 · CI has not run since 2026-08-01 — GitHub billing, and it needs you
Every workflow run since **2026-08-01T21:39Z** has failed, and none of them
reached a step. The jobs are rejected before they start:

> The job was not started because recent account payments have failed or your
> spending limit needs to be increased. Please check the 'Billing & plans'
> section in your settings.

**The last green run was 2026-08-01T18:04Z — the Phase 12 merge.** Everything
after it has been gated by nothing:

- **Phase 11 (StoreKit) has never had a CI run at all.** It merged on 2026-08-02.
- The D-1/D-3/D-4 fixes, the C-3 audit work, and the C-4 rewrite have only ever
  been run locally.

Nothing is wrong with the workflow — it fails identically on `main` and on every
branch, on both jobs, three seconds in. **Only Arjun can clear it**, in GitHub's
Billing & plans settings. Until then, treat "CI is green" as unavailable
information rather than as a pass, and run the gates locally:

```sh
swift test --package-path Packages/Domain && swift test --package-path Packages/Data
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
swiftlint lint --strict && scripts/determinism-check.sh
```

This is also why **C-1 cannot be closed yet**: its wiring is verified locally and
cannot be verified where it actually has to work.

### E-2 · iOS 26 toolbar titles are not Dynamic Type scalable
The accessibility audit fails them outright: "user will not be able to change the
font size of this SwiftUI.AccessibilityNode". Reproduced with a bare
`Button("...")` and again with an explicit `.font(.body)`.

Both Restore and the purchase sheet's Done moved out of toolbars because of it.
**Don't put user-facing text in a toolbar on this OS.**

### E-3 · `swift format` and SwiftLint contradict each other
`swift format --in-place` puts the opening brace of a multi-line `if` condition on
its own line; SwiftLint's `opening_brace` rejects exactly that. **SwiftLint wins —
it is the gate.** [LanguageSelectionViewModel.swift:55](../FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift:55)
is left in SwiftLint's shape on purpose, so `swift format lint` reports one
permanent error there. Don't fix it.

### E-4 · `StoreKitTest` forces a warnings-as-errors carve-out
Apple's own header references `SKPaymentTransactionState`, which Apple deprecated
in iOS 18. `FullDeckTests` passes `-Xcc -Wno-deprecated-declarations` to survive
it. C headers only; `SWIFT_TREAT_WARNINGS_AS_ERRORS` stays on everywhere and no
Swift warning is suppressed.

---

## C — Test-coverage gaps

### C-1 · The adapter has no CI coverage — WIRED 2026-08-02, unverifiable until E-6 clears
**The stated cause of this entry was wrong, and was never measured.** It claimed
CI picks iOS 26.5 and the suite therefore skips on every push. CI runs on
`macos-15` using the runner's *default* Xcode, whose simulator runtime is iOS
18.x — where the suite runs rather than skips. Nobody had checked either way, and
the old logs have expired, so the real answer is still unknown.

What is now known is worse: **CI has not executed since 2026-08-01 (E-6)**, so
the suite has never run in CI for a reason that has nothing to do with runtimes.
Phase 11 landed after the last green run. The main job now prints
`xcrun simctl list runtimes` so the first run that does complete answers this
instead of the next person guessing again.

Wiring, both verified locally against the exact commands, neither verifiable in
CI until billing clears:

- The per-push job passes `-skip-testing:FullDeckTests/StoreKitPurchaseServiceTests`.
  E-5's 91–324 s first purchase cannot sit in a per-push gate.
- A new dispatch-only workflow, [`storekit-adapter.yml`](../.github/workflows/storekit-adapter.yml),
  runs *only* that suite, and **only on an iOS 18.x destination**. No cron:
  a nightly schedule spends macOS minutes (billed 10×) every night whether the
  adapter changed or not, which is a poor trade against an account that is
  already over its limit.
- **It fails rather than skips when no iOS 18 runtime exists.** A skip reports
  green, and a green that proves nothing is the disease this entry describes.

**On iOS 18.5, seven of seven pass** (2026-08-02):

```
✔ FR-14 the localized price comes from StoreKit, never a literal
✔ FR-14 a language with no product in the store has no price
✔ FR-14 buying a language unlocks it
✔ FR-15 a purchase made before this install is restored
✔ NFR-10 a store error surfaces as a thrown failure, not a crash
✔ FR-14 a refunded language is dropped from the entitlement cache          (D-2)
✔ FR-14 a transaction that is not a language unlock is left unfinished     (D-3)
```

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
```

**Adding an iOS 18 destination to CI would close this and serve U-2 at the same
time** — 18.x is far nearer the iOS 17.0 minimum we claim than 26.5 is. D-2 no
longer blocks it. **E-5 still does**: one test takes minutes and cannot sit in a
per-push gate, so such a destination must exclude this suite or run it on a
separate schedule.

Note two of the seven pass against a *dead* store too, because both assert on
absence. Those greens are not coverage.

### C-2 · Nine requirement IDs have no named test — and that is a floor, not a count
`scripts/trace-requirements.sh` reports **21/30**. Untested: `FR-13`, `FR-18`,
`NFR-1`, `NFR-2`, `NFR-3`, `NFR-7`, `NFR-8`, `NFR-9`, `NFR-11`. See **C-4** for
why the real number is worse.

Three groups, and they need different answers: FR-13/FR-18 are unbuilt (see N),
NFR-2/NFR-3/NFR-9 are unmeasured (see U), and NFR-1/NFR-7/NFR-8 are properties
proven by code audit rather than by a test that could regress. The last group is
the interesting one — an audit that isn't a test can rot.

### C-6 · Settings was a screen the audit had never seen — CLOSED 2026-08-02, and it was hiding two defects
Adding `SettingsView` to `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens` failed
immediately, twice, and both were real:

1. **Section headers.** SwiftUI's default header grey against the warm
   `AppBackground` — *"Contrast is not high enough … unless font size is
   larger"*. The project's own `TextSecondary` measures 7.36:1 there, so the fix
   was to stop inheriting the system colour. Same family as L-5.
2. **Links.** `AccentColor` (#D97706) failed outright on the licence link.
   `AccentFill` (#B45309) measures 4.84:1 and passes — the substitution the
   prominent buttons already made.

The second one **also applied to the "Open Settings" link**, which the audit never
reached because it renders only after a permission denial. It would have shipped
failing. A screen entering the audit for the first time is worth more than the
same screen re-audited, and this is the second time that has proved true — see
C-3.

### C-3 · Two Study screens the audit had never seen — CLOSED 2026-08-02, and they were hiding three defects
`StudyView.completionView` and `StudyView.caughtUpView` were never reached by the
audit, carried since Phase 10. Both now have one, and **the audit failed three
times before it passed** — every one a real accessibility defect that had been
shipping:

1. **The completion screen's "Add another language — $0.99" button clipped** at
   larger Dynamic Type. A `Button("…")` string label stays on one line inside a
   bordered button, and this is the app's longest button label. Fixed with an
   explicit `Text` label and `fixedSize(horizontal: false, vertical: true)`.
2. **The completion screen's "Next review …" line clipped** for the same reason
   the card view already had a `ScrollView` — content taller than the screen at
   AX sizes. `completionView` now scrolls too. The precedent and its comment
   were nine lines away in the same file.
3. **The caught-up screen's "Next review …" line failed contrast** — "Contrast
   is not high enough … unless font size is larger". `ContentUnavailableView`
   renders its description in `.secondary`, which is under AA on the warm
   background. `completionView` already carried a comment about this exact
   trap; `caughtUpView` never got the fix because *the system* supplied the
   styling rather than this file.

The two screens needed opposite things to reach. `caughtUp` is organic — grade a
session to its end; day-granular scheduling (L-1) is what makes the loop
terminate, since even a forgotten word returns tomorrow. `complete` is not
reachable by tapping at all: FR-11 wants every word in the pack at `L`, a 14-day
interval, against 1000 words and a real clock. It gets a `#if DEBUG` fixture
wiring in `AppDependencies`, selected by a launch argument the app never sets
itself, that swaps in a one-word `InMemoryPackStore` and a pre-seeded
`InMemoryReviewStore`.

**The lesson is the one C-3 predicted:** the least-audited screen in the app was
the product's deliberate ending, and it was broken in two ways. Screens that
require an unusual state are exactly the screens that rot.

**Where:** [StudyView.swift:266](../FullDeck/FullDeck/Views/StudyView.swift:266),
[AppDependencies.swift:56](../FullDeck/FullDeck/AppDependencies.swift:56)

**Left alone deliberately:** `PurchaseSheet.buyButton` has the same
one-line-label shape, but a shorter string, and it passes the audit today. It is
not a shared code path with the completion button, so there is nothing to fix
once; changing a passing screen on suspicion is how you break a passing screen.

### C-4 · The traceability report produced false greens — REWRITTEN 2026-08-02
`scripts/trace-requirements.sh` counted an ID as covered if **any** test file
anywhere named it. Two mechanisms, both now closed:

1. **A doc comment counted as a test.** `NFR-4`, `NFR-5`, `NFR-6` and `NFR-12`
   were "covered" by a single comment line in `FullDeckUITests.swift`. Deleting
   that comment would have dropped the number without changing one test.
2. **It could not see XCTest at all.** A Swift identifier cannot contain a
   hyphen, so `testNFR4NFR5NFR6AccessibilityAudit...` — the real audit — never
   matched, and the comment above it was the only evidence there was.

The matcher now requires the ID to *start a test's display name*, in the three
spellings the frameworks allow (`@Test("FR-8 …")`, a pytest docstring, and the
unhyphenated XCTest identifier). It reports which **layers** name each ID, and
warns when a requirement whose text says "the app" is named only by pipeline
tests — **which is exactly the shape that hid N-4**, and FR-16 is flagged today.

`--self-test` runs the matcher against inline fixtures and is gated in CI. It
fails against the old matcher on both mechanisms, which is how it was verified.

**The headline is still 21/30, and that is the honest outcome:** the same 21 IDs
are named, but four of them now rest on a test rather than on prose. The report
no longer calls itself coverage — a requirement with several acceptance clauses
is still "named" by a test covering one of them, so **every number it prints is
a floor.** That limitation cannot be automated away and is now stated in the
output rather than in this file only.

**Where:** [trace-requirements.sh](../scripts/trace-requirements.sh)

**Confirmed the hard way, 2026-08-02.** FR-16's pipeline-only flag cleared on its
own when the credits screen landed — the warning working exactly as designed.
Then **N-5 landed outside its reach entirely**: FR-4's adjustability clause had
no implementation while FR-4 carried app *and* Domain tests for its enforcement
clause, so every signal this script can produce was green. Two half-built
requirements in two days, one caught by the layer heuristic and one invisible to
it. The floor is real, and reading acceptance criteria against code is still the
only thing that finds the second kind.

### C-7 · The trend chart is on an audited screen the audit cannot reach
`testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens` visits Progress and **passed
first time** when FR-17 and FR-18 landed. That green is not evidence about the
chart, because the chart was not on screen.

The trend renders only with **two or more days** of milestones, and a UI test
runs inside one day. Hardest words needs at least one *forgot* grade, which this
method never performs — it may appear if another test in the same run happens to
have graded one, which is worse than never, because then the coverage is
incidental and silent.

So the two new sections carry the audit's most valuable property — being looked
at by a machine on every push — for neither of them. That is C-3's shape exactly:
*screens that require an unusual state are exactly the screens that rot*, and
this one was created the same day C-3 closed.

Not fixed here, because the honest fix is the one C-3 used: a `#if DEBUG`
fixture selected by a launch argument, seeding a review store with milestones
across several days and one lapsed word. That is real work and it belongs to
whoever next touches the audit rather than being bolted onto this change.

**What passed instead:** the Domain series and ranking are covered by ten tests,
and the chart's colours were chosen against the audit's own thresholds up front
(Decision 6) rather than corrected after a failure. Neither is a substitute for
the audit having seen it.

**Where:** [LearningProgressView.swift](../FullDeck/FullDeck/Views/LearningProgressView.swift),
[FullDeckUITests.swift:197](../FullDeck/FullDeckUITests/FullDeckUITests.swift:197)

### C-5 · `UNNotificationScheduler` has no automated test — deliberate
Every method is a direct passthrough to `UNUserNotificationCenter`. A unit test
would assert that Apple's framework was called, which is not a fact about this
app. The FR-13 state machine above it is covered against a fake; the adapter is
covered by the manual device run recorded in N-1.

Same call as the thin half of `StoreKitPurchaseService`, and recorded here rather
than left to look like coverage.

**One path is still manually verified only:** the revoked-permission
reconciliation. Driving iOS Settings from XCUITest to revoke a permission is
brittle enough that it would cost more reliability than it buys. Re-run it by
hand when `SettingsView`'s lifecycle modifiers change.

---

## W — Content waivers

Ten total, each documented in its language's `exceptions.json` and printed on
every `pack` run.

### W-1 · Nine Hindi VR-10 waivers
All one shape: the sentence is correct Hindi and genuinely uses its target word,
but UDPipe cannot report a matching lemma — nukta stripping, dropped imperatives,
collapsed causatives, archaic base forms.

**They are unverifiable, not unsatisfiable** — a meaningful distinction. Compare
W-2, which is a genuinely unsatisfiable constraint.
**Where:** `pipeline/work/hi/exceptions.json`. Pending the U-8 human review.

### W-2 · One French waiver — `fr:se:PRON`
A genuinely unsatisfiable §6 constraint.
**Where:** `pipeline/work/fr/exceptions.json`.

---

## What this list says about the project

The defects were small and mostly latent, and they are now all fixed. The real
risk was never there — it is concentrated in **U**: the money path is unproven
against Apple, the minimum OS is unproven at runtime, both performance NFRs are
unmeasured, and 1000 sentences of Hindi are unread. U-1 and U-8 need a human, not
an agent, and neither is small.

Worth noting what closing the D section actually cost: three of the five bugs
were straightforward once reproduced, and the *reproduction* was the whole job.
`Task.yield()` did not hold a race window open (D-1), a `-only-testing:` id
without parentheses reported success while running nothing (D-1), and a
one-minute timeout was indistinguishable from a deadlock (D-3). In each case the
first "passing" run was a lie, and the only thing that caught it was refusing to
believe a green that arrived before the fix.

**N-4 is the one that stops a release.** Four requirements have no implementation,
and one of them is a licence condition. It went unnoticed because the pipeline
tests name FR-16 and the traceability report therefore called it covered (C-4) —
which is the most useful thing on this page: a green gate hid a shipping blocker,
and the only reason it surfaced was grepping the view files by hand.
