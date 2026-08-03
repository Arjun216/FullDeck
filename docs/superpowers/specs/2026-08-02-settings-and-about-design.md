# Settings & About — Design

**Phase:** N-block, part A (of two)
**Date:** 2026-08-02
**Requirements:** FR-16 (attribution & credits), FR-13 (optional daily reminder),
FR-4 (new-word daily cap — the *adjustable* half)
**Status:** Approved 2026-08-02. Not yet implemented.

## What this builds

A Settings screen, and the three things that have been waiting for one.

The app has three tabs and no settings surface at all. That single absence is why
three separate requirements have no implementation: FR-16 needs somewhere to put
credits, FR-13 needs somewhere to toggle a reminder and pick a time, and FR-4
needs somewhere to adjust `N`. Building the container once and filling it is the
whole of this spec.

**FR-16 is a licence obligation, not a feature.** wordfreq's data is CC-BY-SA 4.0;
`CLAUDE.md` records attribution as required "in pack metadata **and the app's
credits**", and FR-16's acceptance criterion says a credits screen must be
reachable from the app. The pack-metadata half has been done and tested since
Phase 6 — `PackValidator` rejects a wordfreq-derived pack whose attribution omits
CC-BY-SA 4.0, and `generate` stamps the credit. The app half does not exist.
Shipping without it is a licence violation. It is the one item on
`docs/known-issues.md` that stops a release outright (N-4).

**FR-4's missing half was found while writing this spec.** `SessionBuilder` and
`StudyViewModel` both accept `newWordCap`, but `ContentView` constructs
`StudyViewModel` without it, so `N` has always been the default 10 and nothing can
change it. The requirement's cap-enforcement clause is well tested; its
adjustability clause has no implementation. This is the same shape as N-4 — a
multi-clause requirement counted as covered because one clause is tested — and it
is the second instance found in two days. See "Traceability" below.

## Scope note — this is part A of two

The N-block is two independent subsystems. They share no types and touch
different layers, so they get separate specs:

| Part | Requirements | Layers touched |
|---|---|---|
| **A — this spec** | FR-16, FR-13, FR-4 | Presentation only |
| **B — later** | FR-17 (trend), FR-18 (hardest words), `StatsService` | Domain + Presentation |

FR-16 and FR-13 are in one spec rather than two because they share the container.
Designing that container twice is the waste the split would cause.

## Decision 1 — the container is a row in the Languages list

A `NavigationLink` row labelled "Settings" in the Languages `List`, beside the
existing "Restore Purchases" row, pushed onto the `NavigationStack` already there.

This is the same call spec Decision 5 made for Restore, and for the same reason:
E-2 records that iOS 26 renders toolbar items at a fixed size and the accessibility
audit fails them outright — "user will not be able to change the font size of this
SwiftUI.AccessibilityNode" — reproduced with a bare `Button("...")` and again with
an explicit `.font(.body)`. Both Restore and the purchase sheet's Done had to move
out of toolbars. A row reuses a pattern already audited clean.

**Rejected — a fourth tab.** Most discoverable and the most conventional home, but
it spends a permanent tab on a screen visited roughly twice, against a deliberate
three-tab shape. `ContentView`'s own doc comment records that TabView tag identity
already broke this project once.

**Rejected — a toolbar gear icon.** E-2 is strictly about toolbar items carrying
*text*, and an icon-only button has none, so this might well pass. It is untested
here and both prior toolbar attempts were backed out. Not worth re-opening for a
screen a row already reaches.

`.navigationTitle("Settings")` is safe. E-2 is about toolbar buttons;
`Languages`, `Study` and `Progress` all pass the audit with navigation titles.

`ContentView`'s tab structure does not change — no new tab, no tag added, nothing
touching the identity problem its doc comment warns about. It does gain an
`@AppStorage` read and one `onChange` for the cap, which is Decision 7 and
unrelated to navigation.

## Decision 2 — credits read each pack's own `PackSource`

`CreditsViewModel` calls `availablePacks()`, loads each pack, and reads
`source: PackSource(name, license, attribution)` off it.

`CLAUDE.md`'s hard rule is that adding a language must mean "add a data pack,"
never "write new app code." A hardcoded wordfreq string would break that: a third
pack from a different source would leave the credits screen silently wrong, and
because this is a licence obligation, wrong here has legal weight rather than
cosmetic weight.

Entries are grouped by the `(name, license, attribution)` triple, so two
wordfreq-derived packs render one credit listing both languages instead of the
same three lines twice.

**Cost, stated plainly:** this loads two full 1000-word JSON packs to display a few
lines. It happens on a screen the learner opened deliberately, off the main actor,
and the same packs are loaded for study anyway. Acceptable.

**Rejected — source fields in `manifest.json`.** Reading the small manifest instead
of full packs would be cheaper and equally correct, but it costs a pack-schema
change, a pipeline change to emit it, and a new validator rule — three moving parts
for a screen nobody opens twice. Revisit only if the load is measurably slow.

### The one hardcoded thing, and why it is safe

`PackSource` carries no URL, so hyperlinking the licence needs a literal. The
licence renders as **text always**, and as a hyperlink **only when the string
matches a known licence** (`CC-BY-SA 4.0` → the Creative Commons deed). An
unrecognised licence degrades to text-only rather than to a wrong link.

Text attribution alone satisfies CC-BY-SA. The licence URI is the "where reasonably
practicable" part of the licence's attribution conditions, which is exactly what a
graceful-degradation map delivers.

## Decision 3 — credits is a section, not a sub-screen

Credits renders as a section inside `SettingsView`, not as a screen pushed from it.

Two packs at three lines each fits comfortably, and attribution is a licence
obligation — putting it one navigation level deeper serves nobody. It keeps its own
ViewModel regardless, because the load is async and can throw.

Reachability, which is FR-16's actual acceptance criterion, is then two taps from
the first screen: Languages → Settings.

## Decision 4 — one new Presentation-owned port

```swift
enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied
}

nonisolated protocol NotificationScheduler: Sendable {
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async throws -> ReminderAuthorization
    func scheduleDailyReminder(hour: Int, minute: Int) async throws
    func cancelDailyReminder() async
}
```

`UNNotificationScheduler` is the concrete adapter and the **only file in the app
that imports `UserNotifications`** — the same containment rule Decision 1 of the
StoreKit spec put on StoreKit, for the same reason.

The port is owned by Presentation, not Domain, on the same test the purchase port
passed: Domain's questions are about words and scheduling review, and a daily
reminder is a platform notification concern. **Domain and Data do not change at
all** in this spec — `Packages/` is untouched.

`authorizationStatus()` does not throw; reading `UNNotificationSettings` cannot
fail. The other two can, and do.

`AppDependencies` gains `notifications:` and `defaults:`. `make()` defaults
`notifications` to a no-op stub, so integration tests and previews never reach the
real notification centre — the pattern `NoPurchasesService` already established.

**Rejected — calling `UNUserNotificationCenter` inline from the ViewModel.**
Smallest possible diff, and it breaks "every layer is testable in isolation via
protocol boundaries." FR-13 would become verifiable only by hand on a device, which
is precisely how NFR-4 and U-6 became permanently unverified.

## Decision 5 — two ViewModels, not one

| Type | Job |
|---|---|
| `SettingsViewModel` | reminder state machine, new-word cap preference |
| `CreditsViewModel` | async pack load, `PackLoadError` → user message |

Folding both into one type would give it three unrelated jobs — permission
reconciliation, a numeric preference, and failable pack I/O — and every reminder
test would then set up packs and a manifest before reaching its assertion.

That is not a general principle being imported; it is the argument
`PurchaseViewModel`'s own doc comment already makes for staying out of
`LanguageSelectionViewModel`. Same shape, same answer.

### Files

| File | Job |
|---|---|
| `FullDeck/Services/NotificationScheduler.swift` | port, `ReminderAuthorization`, no-op stub |
| `FullDeck/Services/UNNotificationScheduler.swift` | the adapter |
| `FullDeck/ViewModels/SettingsViewModel.swift` | reminder + cap |
| `FullDeck/ViewModels/CreditsViewModel.swift` | attribution |
| `FullDeck/Views/SettingsView.swift` | the `Form` |
| `FullDeck/Views/CreditsSection.swift` | attribution rows |

No existing type grows a second job. `ContentView` gains an `@AppStorage` read and
one `onChange` (Decision 7); `LanguageSelectionView` gains one row.

## Decision 6 — the reminder state machine

`SettingsViewModel` holds `isReminderOn`, `reminderTime` (hour/minute), `authorization`,
and `permissionNote`.

Defaults: reminder **off** (FR-13 says so explicitly), time **20:00**. The time
needs a default because the picker has to show something before the learner
touches it, and a reminder is only ever scheduled once they turn the toggle on —
so the default is a starting position, never a scheduled notification.

| Trigger | Behaviour |
|---|---|
| `onAppear()` | Read persisted values, query `authorizationStatus()`. Persisted on but not authorized → cancel any scheduled reminder, force off, persist off, explain. |
| Enable, `.notDetermined` | Request authorization. Authorized → schedule, persist on. Otherwise → revert off, note. |
| Enable, `.denied` | Do **not** re-request. Go straight to the note plus an Open Settings button. |
| Disable | Cancel, persist off, clear the note. |
| Change time while on | Cancel and reschedule. |

The `onAppear()` reconciliation is what makes revoking permission in iOS Settings
turn the toggle off, rather than leaving a promise on screen that cannot be kept.
The toggle is on only when a notification will actually fire.

iOS prompts for notification permission **once per install**. Re-requesting after a
denial silently returns denied, so a UI that keeps asking is a UI that keeps
appearing broken. Hence the separate `.denied` branch.

Exactly one notification, per FR-13: a single
`UNCalendarNotificationTrigger(dateMatching:repeats: true)` under a constant
identifier. Scheduling replaces by identifier, so "exactly one" holds without
bookkeeping.

### Copy

Title **"Time to study"**. No body.

A repeating local notification cannot know the due count at fire time without
background refresh, which §4 of the requirements puts out of scope. Any body
promising ready cards is therefore false on the days there are none. A title that
is always true beats a body that is usually true.

No streak language, no guilt, no "you haven't studied" — §4 rules out
gamification, and a reminder is the easiest place to smuggle it back in.

## Decision 7 — the cap applies immediately, and FR-4 is amended

FR-4's acceptance currently reads "Changing `N` in settings takes effect for the
**next day's** introductions." Honouring that literally needs a pending/active cap
pair with an effective-from date, promoted on day rollover.

**Decided: apply immediately, and amend the requirement.** A learner who lowers the
cap because today is too much wants relief today, not tomorrow. The alternative
buys a small Domain type and its tests to deliver worse behaviour.

FR-4's acceptance sentence becomes: *changing `N` takes effect from the next
session; words already introduced today are never retracted.*

Consequence, stated plainly: lowering the cap below what has already been introduced
today yields zero further new words today, because `max(0, cap - introducedToday)`
clamps at zero. Due reviews are unaffected — FR-4 never caps those.

`SessionBuilder` needs no change. This is the decision that keeps `Packages/`
untouched.

### Reaching an in-flight session

`ContentView` builds `StudyViewModel` only when `activeLanguage` changes, so a cap
edit would not reach an existing session. Rebuilding on cap change would discard
whatever session the learner is in the middle of — the exact failure
`ContentView`'s doc comment warns about for ViewModels constructed per body
evaluation.

Instead: `ContentView` reads the key with `@AppStorage` and assigns
`studyViewModel?.newWordCap` on change. `newWordCap` becomes a `var`. No rebuild,
no lost session, and `@AppStorage` keeps it in sync with whatever
`SettingsViewModel` writes.

Control: a `Stepper`, range 1–30, default 10, one `UserDefaults` key shared as a
constant between the two readers.

## Errors

`CreditsViewModel` reuses `PackLoadError.userMessage`, the path every other
ViewModel already takes.

For the reminder, a throw from `requestAuthorization()` or
`scheduleDailyReminder()` reverts the toggle to off and sets a message. Never a
silent on-state, which would be the toggle lying in the other direction.

**Two distinct off-states, kept distinct:**

| State | Surface |
|---|---|
| Denied | Explanation + Open Settings button |
| Failed to schedule | Plain retryable message |

Collapsing them would repeat D-4, where *product not found* and *store unreachable*
became one string and the setup work then had nothing to diagnose with.

## Testing

Test-first, red-green-refactor, one behaviour at a time. ViewModels are logic under
`CLAUDE.md`, so the tests come first, not after.

`SettingsViewModel` against a `FakeNotificationScheduler` — no simulator, no
permission prompt, milliseconds:

- FR-13 reminders are off by default
- FR-13 enabling requests permission and schedules exactly one reminder
- FR-13 a denied prompt reverts the toggle and explains
- FR-13 enabling when already denied does not prompt again
- FR-13 disabling cancels the scheduled reminder
- FR-13 changing the time reschedules rather than adding a second
- FR-13 permission revoked outside the app turns the toggle off on next appearance
- NFR-10 a scheduling failure surfaces as a message, not a crash
- FR-4 the cap defaults to 10 and persists
- FR-4 the cap clamps to its range

`CreditsViewModel` against `InMemoryPackStore`:

- FR-16 credits list each bundled pack's source, licence and attribution
- FR-16 two packs from one source render one grouped credit
- NFR-10 a pack that cannot load surfaces a message

One XCUITest — **FR-16 credits are reachable from the app** — walking Languages →
Settings → attribution text. A ViewModel test cannot prove reachability, and
reachability is the clause whose absence was N-4.

`SettingsView` joins the NFR-4/5/6 accessibility audit's core screens.

**Determinism:** the reminder time is stored as hour/minute `Int`s, never a `Date`,
so no test needs the wall clock and `determinism-check.sh` stays quiet. The
`DatePicker` builds its `Date` from components in the view layer only.

**Coverage floors are unaffected.** Domain and Data are untouched; the app target
has no floor by design.

### Knowingly thin

`UNNotificationScheduler` gets no unit test. It is a direct passthrough to
`UNUserNotificationCenter` — the same call-the-framework glue as the StoreKit
adapter's thin half. The XCUITest plus a manual device check are the honest
coverage, and this is recorded as such rather than claimed otherwise.

## Traceability

FR-16 currently shows as covered by two pipeline tests naming it, for the
pack-metadata half. Gaining an app-layer test clears the pipeline-only warning on
its own — the flag doing the job it was added for.

FR-4 is the more interesting case, and the one this spec surfaced: it is named by
both app and Domain tests, all of which cover cap *enforcement*, while the
*adjustability* clause had no implementation at all. **No layer heuristic catches
that** — only reading the acceptance criterion against the code does. It is the
concrete argument for the traceability report's rewritten framing: every number it
prints is a floor.

## Out of scope

- Any notification beyond the single daily reminder (§4).
- Suppressing the reminder when nothing is due — needs background refresh (§4).
- Snooze, per-language reminders, multiple reminders.
- A version/build row, an acknowledgements list for code dependencies (there are
  none), or a feedback link.
- Source fields in the pack manifest (Decision 2, rejected alternative).
- FR-17 and FR-18 — part B, its own spec.

## Risks

| Risk | Mitigation |
|---|---|
| iOS prompts for notification permission once per install, so a mis-sequenced prompt is unrecoverable without a device reset | The `.denied` branch never re-requests; manual verification uses a fresh simulator |
| Loading two full packs for a credits screen is slower than it looks | Off the main actor, on a deliberately-opened screen; the manifest alternative is specced and rejected, not unconsidered |
| The `@AppStorage`/`UserDefaults` key is written by one type and read by another | Shared constant, and FR-4's persistence test covers the round trip |
| Amending FR-4 sets a precedent for editing a contract that has been treated as settled | The amendment is recorded here with its reasoning, and changes behaviour in the learner's favour |

## Requirements amendment

`docs/requirements.md` FR-4's acceptance criterion changes as described in
Decision 7. That edit is part of this spec's implementation, not a separate
decision.
