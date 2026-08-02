# Known issues

Every defect, gap, and deliberate compromise in the project as of **2026-08-01**,
after Phase 11. One place, so Phase 13 has a target list and Phase 14's
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

The biggest thing on this page is not any single row. It is that **the entire
purchase chain has never touched Apple's servers** (U-1), and **the app has never
been run on its own minimum OS** (U-2).

The one that blocks shipping outright is **N-4**: the CC-BY-SA 4.0 credits screen
does not exist.

---

## D — Defects

### D-1 · Restore's before/after comparison can race with its own reload
`LanguageSelectionViewModel.restore()` snapshots `unlockedCodes()`, calls
`purchases.restore()`, calls `load()`, then compares. But
`StoreKitPurchaseService.refreshEntitlements()` yields on `entitlementChanges`
*during* `purchases.restore()`, and `LanguageSelectionView`'s second `.task`
answers that by calling `load()` too. Two `load()` calls interleave at their
await points.

**Consequence is bounded:** both write identical data, so nothing corrupts. The
comparison can read the other load's result and show — or fail to show — "No
previous purchases found." wrongly.

**Where:** [LanguageSelectionViewModel.swift:78](../FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift:78)
**Fix shape:** have `restore()` compare against the entitlement set rather than
re-derived view state, or serialize `load()` behind a single in-flight task.
**Not yet reproduced** — found by reading, not by a failing test. A regression
test comes first, per `CLAUDE.md`.

### D-2 · `entitlementChanges` is a single-consumer stream with no guard
`AsyncStream` delivers each element to exactly one iterator. One view consumes it
today, so this is correct right now. Add a second observer — a Study-tab listener,
a settings screen — and the two will *split* events rather than both receiving
them, so one of them silently misses unlocks.

**Where:** [StoreKitPurchaseService.swift:22](../FullDeck/FullDeck/Services/StoreKitPurchaseService.swift:22)
**Fix shape:** if a second consumer is ever needed, this has to become a
broadcast. Nothing enforces the single-consumer rule today, and the failure is
silent, which is what makes it worth writing down.

### D-3 · `record()` finishes a transaction before deciding whether it is ours
`await transaction.finish()` runs before the `guard let code =
ProductIdentifier.languageCode(...)`. A transaction for a product of ours that is
not a language unlock gets marked handled by code that then ignores it.

**Harmless today** — there are no non-language products. It becomes a real bug the
day one is added, and it will look like a purchase that vanished.

**Where:** [StoreKitPurchaseService.swift:119](../FullDeck/FullDeck/Services/StoreKitPurchaseService.swift:119)
**Fix shape:** move `finish()` after the guard, or finish explicitly in both branches.

### D-4 · "The store isn't reachable" is shown for a product that doesn't exist
`PurchaseViewModel.loadProduct()` collapses *product not found* and *store
unreachable* into one message. That collapse is deliberate and correct **for the
learner** — the comment says so, and neither case is their fault.

It is misleading **for you**, during App Store Connect setup. An inactive Paid
Applications agreement returns no products, and the app will say the store is
unreachable when the store is perfectly reachable.

**Where:** [PurchaseViewModel.swift:55](../FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift:55)
**Mitigation in place:** [`app-store-connect-setup.md`](app-store-connect-setup.md)
leads with the agreement for exactly this reason. Consider a `#if DEBUG` branch
that distinguishes the two, rather than changing the shipped copy.

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

### N-1 · FR-13, the optional daily reminder
Zero code. No `UNUserNotificationCenter` reference anywhere in the repo. The one
push notification `CLAUDE.md` permits, and it doesn't exist.

### N-2 · FR-17, learning-over-time trend
Model plumbing only — the milestone date exists on `ReviewState`
([Models.swift:53](../Packages/Domain/Sources/Domain/Models.swift:53)) and a
comment says Phase 9 would decide when to use it. Phase 9 didn't. No `StatsService`
type was ever written, despite `architecture.md` §3 listing one.

### N-3 · FR-18, hardest words
Not built. The Progress screen renders learned-of-total and nothing else. The
ranking data already exists — `ReviewState.easeFactor` is stored per word — so
this is a view and a pure ranking function, not new persistence.

### N-4 · FR-16, the credits screen — and it is a licence obligation
**Zero references to FR-16 in any Swift file, and there is no credits or about
view.** `FullDeck/FullDeck/Views/` contains five files: error state, language
selection, progress, purchase sheet, study. None of them shows attribution.

The pack-metadata half *is* done and tested — `PackValidator` rejects a
wordfreq-derived pack whose attribution omits CC-BY-SA 4.0, and `generate`
stamps the credit. That is what makes this easy to miss.

**This is not a feature preference.** wordfreq's data is CC-BY-SA 4.0;
`CLAUDE.md` records attribution as required "in pack metadata **and the app's
credits**", and FR-16's acceptance criterion says a credits screen must be
reachable from the app. Shipping without it is a licence violation, not a gap.

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

### E-1 · StoreKit testing is dead from the command line, on every runtime tried
`xcodebuild test` never pushes the scheme's StoreKit configuration to the
simulator's `storekitd`. It fails **silently**: `SKTestSession` does not throw —
not even on deliberately invalid JSON — it hands back an empty store, so every
product lookup returns nothing and `buyProduct` fails `.notEntitled`.

**Retested on iOS 18.5, 2026-08-01: all six still skip.** This was originally
written up as an iOS 26.5 regression, on reports that iOS 18 runtimes were
unaffected. That was wrong — the runtime is not the variable, the command line
is. `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'` produced the
identical skip, so **installing an older runtime does not help.**

**The skip guard was also asking the wrong question, which is why the IDE run
proved nothing.** `.enabled` is a Swift Testing *trait*: it is evaluated before
the suite's `init()` runs, and `init()` is where `SKTestSession` is created. So
the guard queried the store before anything had loaded a product into it — it
could only ever pass via the scheme's configuration, and it therefore skipped in
the Xcode IDE for exactly the same reason it skipped from the command line.
**An IDE run with the old guard tells you nothing.** Fixed 2026-08-02: the guard
now builds a session first and holds it past the `await`.

**With the guard removed entirely, the real failures are** (2026-08-02):

```
price(for: hindi)      -> nil          (expected "$0.99")
purchase(hindi)        -> throws .productUnavailable
restore()              -> throws .notEntitled
```

So the store is **empty, not broken** — every failure is "no such product". Note
that **two of the six pass against an empty store**, because both assert on
absence (`no product has no price`, `a store error throws`). Don't read that
green as coverage.

Creating the session by hand does not populate the store either, so the scheme
configuration is not the only missing piece. Untried: the Xcode IDE **with the
fixed guard**, and a `.storekit` file regenerated by Xcode rather than
hand-written (`_developerTeamID` and `_applicationInternalID` in ours are
placeholders copied from a public example).
**Hours went into the `.storekit` file before the environment turned out to be the problem.**

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

### C-1 · Six StoreKit adapter tests skip on every run, CLI and CI alike
The consequence of E-1. `StoreKitPurchaseServiceTests` is the adapter's *only*
coverage, and it does not run.

**Adding an iOS 18.5 runtime was tried on 2026-08-01 and did not fix it** — 82
tests, 76 passed, the same 6 skipped. Open it in the Xcode IDE and run the suite
there; that is the only untried lever. Until someone does, these six requirements
have **no executed test anywhere**:

```
FR-14 buying a language unlocks it
FR-14 a language with no product in the store has no price
FR-14 the localized price comes from StoreKit, never a literal
FR-14 a refunded language is dropped from the entitlement cache
FR-15 a purchase made before this install is restored
NFR-10 a store error surfaces as a thrown failure, not a crash
```

**Current suite: 89 total, 83 passed, 6 skipped** (whole scheme, iOS 26.5).

### C-2 · Nine requirement IDs have no named test — and that is a floor, not a count
`scripts/trace-requirements.sh` reports **21/30**. Untested: `FR-13`, `FR-18`,
`NFR-1`, `NFR-2`, `NFR-3`, `NFR-7`, `NFR-8`, `NFR-9`, `NFR-11`. See **C-4** for
why the real number is worse.

Three groups, and they need different answers: FR-13/FR-18 are unbuilt (see N),
NFR-2/NFR-3/NFR-9 are unmeasured (see U), and NFR-1/NFR-7/NFR-8 are properties
proven by code audit rather than by a test that could regress. The last group is
the interesting one — an audit that isn't a test can rot.

### C-3 · Two Study screens the audit has never seen
`StudyView.completionView` and `StudyView.caughtUpView` are never reached by
`testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens` — they need a fully-learned or
no-cards-due state the fixtures don't produce. Carried since Phase 10.
**Where:** [StudyView.swift:266](../FullDeck/FullDeck/Views/StudyView.swift:266)

The completion screen is the product's deliberate ending — the thing `CLAUDE.md`
says matters — and it is the least-tested screen in the app.

### C-4 · The traceability report produces false greens
`scripts/trace-requirements.sh` counts an ID as covered if **any** test file
anywhere names it — one mention is enough, and Python pipeline tests count.
A requirement with several acceptance clauses goes green when one clause is
tested.

That is how N-4 stayed invisible: FR-16 is named by two pipeline tests covering
the pack-metadata half, so the report calls it covered while the credits screen
it also requires does not exist. FR-17 is the same shape — two Domain tests name
it for milestone-date plumbing; the trend view was never built.

**So 21/30 overstates coverage, and by an unknown amount.** The script is
report-only and never gates, which limits the damage, but it cannot be read as
"9 gaps" — it means *at least* 9. Anything the trend report says is a floor.
**Where:** [trace-requirements.sh](../scripts/trace-requirements.sh)

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

The defects are small and mostly latent. The real risk is concentrated in **U**:
the money path is unproven against Apple, the minimum OS is unproven at runtime,
both performance NFRs are unmeasured, and 1000 sentences of Hindi are unread.
U-1 and U-8 need a human, not an agent, and neither is small.

**N-4 is the one that stops a release.** Four requirements have no implementation,
and one of them is a licence condition. It went unnoticed because the pipeline
tests name FR-16 and the traceability report therefore called it covered (C-4) —
which is the most useful thing on this page: a green gate hid a shipping blocker,
and the only reason it surfaced was grepping the view files by hand.
