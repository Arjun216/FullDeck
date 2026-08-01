# StoreKit 2 Monetization — Design

**Phase:** 11
**Date:** 2026-08-01
**Requirements:** FR-14 (purchase an additional language), FR-15 (restore purchases),
FR-1/FR-2 (lock state, free launch language)
**Status:** **UNSHELVED 2026-08-01.** Phase 12 landed the real Hindi pack, so there
is something to sell. The API notes below were re-verified against the **iOS 26.5
SDK itself** (not the docs site) on 2026-08-01 — see "API re-verification" at the
end. Nothing in the design changed. Plan:
[`../plans/2026-08-01-storekit-monetization.md`](../plans/2026-08-01-storekit-monetization.md).

*Original shelving note, kept because the reasoning is what reordered the phases:*
**SHELVED 2026-08-01 — do not implement yet.** The design below is
approved and still stands; what changed is when it can happen.

Phase 11 needs something to sell, and the app ships exactly one pack. Decision 0
originally solved that by generating a Hindi pack through the pipeline — but the
pipeline's Hindi path was registered and never exercised: `xx-sent-ud-sm` is absent
from `pipeline/pyproject.toml`, and it is a *sentence segmenter* with no POS tagger
or lemmatizer, while `words.py` reads `token.lemma_` and `token.pos_` off it. spaCy
ships no Hindi pipeline with POS at all. Making Hindi real is Phase 12's job, not a
side errand.

Selling `arjunpathak.FullDeck.language.hi` before that pack exists would let a
purchase succeed and unlock nothing. So **Phase 12 (Hindi) now runs before Phase
11 (monetization)** — the honest order, since monetization depends on a second pack
and not the reverse.

Unshelve this when the Hindi pack is real. Re-check the StoreKit API notes in
Sources first; they were verified on 2026-08-01 and the iOS 26.x
`currentEntitlements` reports in Decision 4 may have been fixed by then.

## What this builds

The first language is free. Every other language is a $0.99 one-time
non-consumable unlock. This phase makes that real: fetch the product, run the
purchase, handle every outcome, restore across reinstalls, and keep the app's
notion of "unlocked" honest against StoreKit rather than a local flag.

Phase 8 stubbed the boundary already. `EntitlementStore.isUnlocked(_:)` exists in
Domain and is consumed by `LanguageSelectionViewModel`; the stub
(`NoPurchasesEntitlementStore`) always returns `false`. This phase replaces the stub
with the StoreKit-backed adapter.

**The `EntitlementStore` swap itself is caller-invisible** — the protocol, its
signature, and `LanguageSelectionViewModel.load()`'s use of it are unchanged, and
`AppDependencies` swaps one conforming type for another. Domain does not change at
all.

What *does* change is the Languages screen, because it gains behaviour it never had:
presenting the purchase sheet from a locked row, reloading after a successful
purchase or restore, a Restore toolbar item, and clearing `activeLanguage` if the
active language is revoked. Those are additions to `LanguageSelectionView` and
`LanguageSelectionViewModel`, not changes to how either talks to `EntitlementStore`.

## Decision 0 — WITHDRAWN: Phase 12 supplies the second pack

*Superseded on 2026-08-01, the day this spec was written. Kept rather than deleted
because the reasoning is what reordered the phases.*

This decision originally had Phase 11 generate a ~50-word Hindi pack through the
existing pipeline, so that there would be something to buy.

It does not survive contact with the pipeline. `LANGUAGE_RULES` has an `"hi"` entry
and `SpacyAnalyzer.MODELS` maps it to `xx_sent_ud_sm`, which reads as support — but
that model is absent from `pipeline/pyproject.toml`, so `packgen words hi` fails at
once, and it is a sentence segmenter with no POS tagger or lemmatizer, while
`words.py:82` reads `token.lemma_` and `token.pos_` off it. spaCy has no Hindi
pipeline with POS. Fixing that means a new NLP dependency or moving tagging into the
Claude prompts — Phase 12's actual work, not a Phase 11 side errand.

**Phase 12 therefore runs first**, and supplies the real Hindi pack. Until then the
Languages screen carries a non-purchasable "coming soon" row so the app reads as
deliberately one-language rather than unfinished. That row is presentation copy in
the app target, *not* a manifest entry: `availablePacks()` returns packs that exist,
and a manifest entry with no pack file would push "a pack that isn't there" into
`PackDescriptor`, the loader and the validator.

## Decision 1 — architecture

Four new types. Three of them are ordinary; only one imports StoreKit.

| Type | Home | Responsibility |
|---|---|---|
| `PurchaseService` | `FullDeck/Services/` | Protocol: product lookup, purchase, restore, entitlement refresh, change stream |
| `StoreKitPurchaseService` | `FullDeck/Services/` | The **only** file importing StoreKit. Implements `PurchaseService` *and* `EntitlementStore` |
| `PurchaseViewModel` | `FullDeck/ViewModels/` | The purchase state machine. Knows nothing about StoreKit |
| `PurchaseSheet` | `FullDeck/Views/` | The sheet presented from a locked language row |

### Why the port lives in the app target

`SpeechService` set this precedent in Phase 8: presentation-owned ports live beside
their adapters in the app target, and Domain holds only ports domain logic actually
needs. Domain never needs to know that buying exists — it needs `isUnlocked`, which
`EntitlementStore` already gives it. Adding a purchase port to Domain would widen its
surface for no domain consumer.

`StoreKitPurchaseService` conforming to both protocols is deliberate: entitlements
and purchases are the same underlying StoreKit state, and splitting them across two
adapters would mean two caches that can disagree.

### Why the state machine is its own type

`LanguageSelectionViewModel` is ~70 lines with one job. Folding six purchase states,
price fetching and restore into it roughly doubles it and gives it two unrelated
jobs, and every purchase test would then need packs, a manifest and `UserDefaults`
set up before reaching the assertion. A separate `PurchaseViewModel` is testable
against a fake in milliseconds, which is what makes the build plan's "build it
test-first" instruction actually followable.

The two communicate one way: on a successful purchase or restore,
`LanguageSelectionViewModel.load()` runs again so the row unlocks.

### Keeping `isUnlocked` synchronous

`EntitlementStore.isUnlocked` is synchronous and `Sendable`; StoreKit is async. The
adapter holds a `Set<LanguageCode>` behind a lock. Reads are synchronous; writes come
from two async sources: a launch-time refresh over `Transaction.currentEntitlements`,
and a long-running listener on `Transaction.updates` started at launch and never
cancelled for the process lifetime.

The port's existing doc comment already anticipates exactly this ("Phase 11's
StoreKit adapter caches its entitlement set behind this same signature"), so no
Domain change is needed.

## Decision 2 — product identifiers

`arjunpathak.FullDeck.language.<code>` — Hindi is
`arjunpathak.FullDeck.language.hi`.

**Derived from `LanguageCode` in the adapter, never stored in the manifest.** This is
ADR-004 ("adding a language means adding a data pack, never writing new app code")
doing real work: a manifest field for product IDs would make every new language a
two-step change and a chance to get them out of sync. The derivation is one function
and is unit-tested.

## Decision 3 — the state machine

```
       ┌──────┐  open sheet   ┌────────────────┐   product found   ┌──────────────┐
       │ idle │──────────────▶│ loadingProduct │──────────────────▶│ ready(price) │
       └──────┘               └────────────────┘                   └──────────────┘
                                      │                              │        ▲
                              not found / store error         buy    │        │ cancelled
                                      ▼                              ▼        │
                              ┌──────────────┐                ┌────────────┐  │
                              │ unavailable  │                │ purchasing │──┘
                              └──────────────┘                └────────────┘
                                                                 │    │    │
                                              ┌──────────────────┘    │    └────────────┐
                                              ▼                       ▼                 ▼
                                       ┌───────────┐          ┌─────────────┐    ┌──────────┐
                                       │ purchased │          │   pending   │    │  failed  │
                                       └───────────┘          └─────────────┘    └──────────┘
```

| From | Event | To | Notes |
|---|---|---|---|
| `idle` | sheet opens | `loadingProduct` | |
| `loadingProduct` | product returned | `ready(price)` | Price is StoreKit's localized display string, never a hardcoded "$0.99" |
| `loadingProduct` | no product / store error | `unavailable(message)` | |
| `ready` | learner taps Buy | `purchasing` | |
| `purchasing` | verified success | `purchased` | Entitlement cache updated, language list reloads |
| `purchasing` | `.userCancelled` | `ready(price)` | **Silently.** Cancelling is not an error and shows no message |
| `purchasing` | `.pending` | `pending` | |
| `purchasing` | failure / failed verification | `failed(message)` | Language stays locked |
| `failed` | retry | `purchasing` | |
| any | restore completes, language now owned | `purchased` | |
| any | restore completes, still not owned | unchanged, with "No previous purchases found." | |

**`pending` is not optional.** Ask to Buy (a family organiser must approve) and bank
SCA challenges both land here. The purchase is neither complete nor failed; the
entitlement arrives later through `Transaction.updates`, possibly after the app has
been relaunched. The sheet says the purchase is waiting for approval and the language
stays locked until it lands.

**Unverified transactions are failures.** `VerificationResult.unverified` is treated
as `failed`, never as success.

## Decision 4 — entitlement refresh is additive, and why

A launch refresh **adds** to the cache. It never removes. A language leaves the
cache on exactly one signal: a transaction arriving through `Transaction.updates`
with a non-nil `revocationDate`.

This is not defensive over-engineering. Apple's developer forums carry open reports
against iOS 26.x of `Transaction.currentEntitlements` yielding an **empty sequence
for a valid, unrefunded non-consumable** — reproduced on devices set to the Buddhist
calendar, and as a regression where family-shared non-consumables vanish after a
restore. If the refresh replaced the cache wholesale, one of those empty reads would
silently re-lock a language the learner paid for. Treating absence as revocation
makes an OS bug indistinguishable from a refund; requiring an explicit
`revocationDate` does not.

The cost is that a genuine revocation is only observed when StoreKit reports it,
rather than being inferred. That is the correct trade: refunds are rare and
explicitly signalled, spurious empty reads are neither.

### On revocation

Revoked → drop from cache → change stream fires → the language list reloads → the row
re-locks. If the revoked language was the *active* one, `activeLanguage` clears and
the learner picks again.

**Review history on disk is never touched.** A re-purchase restores their progress
intact. Destroying a learner's study history over a billing event would be
unrecoverable if the refund were a mistake, and the data costs nothing to keep.

## Decision 5 — the purchase surface

Tapping a locked row presents a **dedicated sheet** (chosen over an inline buy
button): language name, what the unlock includes, StoreKit's localized price, Buy,
and the current state's message. The extra surface buys room to say what $0.99
actually gets, at the cost of one more view to localize and pass the accessibility
audit.

**Restore** is a toolbar item on the Languages screen — the only screen where
entitlement state is visible, so the only place a learner would look for it. It calls
`AppStore.sync()`, which is StoreKit 2's restore and deliberately user-initiated
(it can prompt for an Apple ID password).

No confirm-then-buy alert. StoreKit's own sheet already carries price, terms and
biometric confirmation; a second confirmation for a $0.99 purchase is friction
dressed as courtesy.

## Decision 6 — errors and copy

Typed errors, localized strings, real user-facing states, no crashes (NFR-10).

| Situation | What the learner sees |
|---|---|
| Cancelled | *Nothing.* Sheet returns to the price |
| Purchase failed | "Couldn't complete the purchase. You haven't been charged." |
| Store unreachable / no product | "The store isn't reachable right now." |
| Awaiting approval | "This purchase is waiting for approval." |
| Restore, nothing owned | "No previous purchases found." |

Every string goes through `String(localized:)` into `Localizable.xcstrings` with the
Spanish translations the catalog already carries for the rest of the app (NFR-12).

## Testing

**Test-first (logic):** every `PurchaseViewModel` transition in the table above,
driven against a `FakePurchaseService` in `FullDeckTests`. No simulator, no network,
milliseconds. One behaviour at a time — failing test, confirm it fails for the right
reason, minimal code.

**Tested alongside (glue):** `StoreKitPurchaseService` against `SKTestSession` with a
`FullDeck.storekit` configuration — purchase, restore, revoke, and Ask-to-Buy.
`SKTestSession.setSimulatedError` drives the failure paths, which is the honest way
to test them; `SKTestSession` works with Swift Testing directly (`import StoreKitTest`
alongside `import Testing`).

**Also:** the product-ID derivation is a pure function and gets a unit test. The
accessibility audit (`testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`) extends to
cover the purchase sheet — it runs unfiltered as of Phase 10.5 and must stay that
way. No test reads `Date()`, sleeps, or uses unseeded randomness.

## Doc deliverable

A step-by-step App Store Connect walkthrough for the work outside Xcode: creating the
non-consumable IAP products, enrolling in the Small Business Program (which matters
at $0.99 — it changes the fee split), creating a sandbox tester account, and running
a sandbox purchase end to end to confirm the whole chain works against Apple's real
servers rather than only the local test configuration.

## Out of scope

- **FR-16 credits screen.** The `wordfreq` CC-BY-SA attribution is required before
  release, but it is its own piece of work and does not belong in a purchase phase.
- **Family Sharing.** An App Store Connect toggle, flippable later with no code
  change. It is a pricing decision rather than an engineering one, and it currently
  carries the iOS 26.x entitlement regression noted in Decision 4 — a reason to wait,
  not to rush.
- Subscriptions, promotional codes, in-app refund request UI, win-back offers.
- Server-side receipt validation. There is no backend, by design (spec D6).

## Risks

| Risk | Handling |
|---|---|
| `currentEntitlements` spuriously empty on iOS 26.x | Additive-only refresh (Decision 4). A language is removed only on explicit `revocationDate` |
| Purchase completes while the app is backgrounded or killed | `Transaction.updates` listener starts at launch and delivers missed transactions; `pending` survives relaunch |
| Sandbox behaves differently from the local `.storekit` config | The App Store Connect walkthrough exists precisely to force an end-to-end sandbox run before release |
| Hindi stub pack pre-empts Phase 12's verdict | Recorded in Decision 0. Phase 12 still runs the full pack and owns the verdict |
| StoreKit test data is deleted with the app in the local environment | Tests create their own `SKTestSession` state rather than assuming carry-over between runs |

## Sources

- [`Transaction.currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements) —
  the singular `currentEntitlement(for:)` was deprecated in iOS 18.4 in favour of the
  plural form used here.
- [`Transaction.updates`](https://developer.apple.com/documentation/storekit/transaction/updates)
- [Offering, completing, and restoring in-app purchases](https://developer.apple.com/documentation/storekit/offering-completing-and-restoring-in-app-purchases)
- [`SKTestSession`](https://developer.apple.com/documentation/storekittest/sktestsession)
- [What's new in StoreKit and In-App Purchase — WWDC25](https://developer.apple.com/videos/play/wwdc2025/241/)

## API re-verification — 2026-08-01

Checked against `iPhoneOS26.5.sdk`'s `StoreKit.swiftinterface` and
`StoreKitTest.swiftinterface` directly. Apple's documentation site renders through
JavaScript and cannot be read by fetch, so the SDK is both the more reliable and the
more authoritative source — it is what the compiler enforces.

**Nothing in this design needed to change.** Findings:

- `Transaction.currentEntitlements` (the plural static var this design uses) is
  **not** deprecated. The Sources note above was right: the `deprecated: 18.4`
  attribute belongs to the singular `currentEntitlement(for:)`.
- iOS 18.4 added a *third* form, `Transaction.currentEntitlements(for productID:)`.
  It is unusable here — the deployment target is iOS 17.0 — and unnecessary, since
  the refresh iterates all entitlements anyway.
- `Transaction.updates`, `AppStore.sync()`, `Product.products(for:)` and
  `Product.PurchaseResult`'s three cases are unchanged and current.
- `Product.purchase(options:)` is `@MainActor`. Awaiting it from a nonisolated async
  context is legal; the compiler inserts the hop.
- `Product.PurchaseError` gained `.paymentMethodBindingConfigurationRequired` in
  26.5. It needs no special handling — it falls through the generic failure path.
- `SKTestSession` is current and `NS_SWIFT_SENDABLE`.
  `setSimulatedError(_:forAPI:)` is live; `failTransactionsEnabled`, `failureError`
  and the ObjC `buyProduct(productIdentifier:)` are all deprecated.
- WWDC26's StoreKit additions — multi-user subscriptions, Group Purchases,
  commitment plans, in-app offer-code redemption — are entirely subscription-side.
  None of them touch a one-time non-consumable.
- **The iOS 26.x `currentEntitlements`-empty bug is still open**, with fresh reports
  against Xcode 26.4 / iOS 26.4.1 in May 2026: production-only, not reproducible in
  sandbox. Decision 4's additive-only refresh is reinforced rather than obsolete —
  and note the corollary, that it cannot be exercised before release.
