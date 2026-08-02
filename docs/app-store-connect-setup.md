# App Store Connect setup for the language unlocks

Everything in Phase 11 was built against a local StoreKit configuration file. None
of it proves the chain works against Apple's servers. This is the part that happens
outside Xcode, in order, plus the traps worth knowing before you hit them.

Product identifier format, set in code and never in the manifest:
`arjunpathak.FullDeck.language.<code>` — Hindi is
`arjunpathak.FullDeck.language.hi`. It comes from
`ProductIdentifier.forLanguage`, so App Store Connect has to match the code, not
the other way round.

## 1. Agreements, tax, and banking — do this first

App Store Connect → Business. The **Paid Applications** agreement must be active,
with tax and banking details complete.

Until it is, in-app purchases return **no products at all**. A
`Product.products(for:)` that comes back empty in sandbox is far more often this
than a bug in the app. Check here before debugging anything.

## 2. Small Business Program

App Store Connect → Business → enroll.

It moves Apple's commission from 30% to 15% for developers under $1M a year. At
$0.99 that is the difference between $0.69 and $0.84 per sale. Enrollment is not
automatic, and it takes effect the month *after* approval — so enrolling before the
first sale is worth more than enrolling after.

## 3. Create the non-consumable

App Store Connect → the app → Monetization → In-App Purchases → **+**.

- Type: **Non-Consumable**
- Reference Name: `Hindi language unlock` (internal only)
- Product ID: `arjunpathak.FullDeck.language.hi` — must match exactly, and
  **can never be changed or reused** once saved, even if you delete it
- Price: $0.99 (USD tier)
- Localizations: English **and Spanish** — the app ships `es`, and a missing
  localization shows the learner an untranslated name mid-purchase
- Review screenshot + notes: required before the product can be submitted

A product sits in "Ready to Submit" until it goes through review attached to an app
version. It is still purchasable in sandbox before that.

## 4. Sandbox tester

App Store Connect → Users and Access → Sandbox → Test Accounts → **+**.

Use an email address that is not already an Apple ID. On the device: Settings →
Developer → Sandbox Apple Account. Do **not** sign into the real App Store with it.

## 5. The end-to-end sandbox run — the part that matters

On a real device, with a development build:

1. Open Languages. Hindi shows a padlock.
2. Tap the row. The sheet shows **StoreKit's own price string**, not "$0.99"
   hardcoded — if it says the store isn't reachable, go back to step 1 of this doc.
3. Buy it with the sandbox account. The row unlocks; Hindi becomes selectable.
4. Study a few cards so there is progress on disk.
5. **Delete the app. Reinstall it.**
6. Tap **Restore Purchases**. Hindi unlocks again.

Step 6 is the only real test of FR-15. The local configuration file cannot prove it,
because it never leaves the device.

## 6. Ask to Buy

Enable Ask to Buy for the sandbox account and repeat the purchase. Expect:

- the sheet says **"This purchase is waiting for approval."**
- the language stays **locked**
- approving it later unlocks the row **without a relaunch** — that is the
  `Transaction.updates` listener and the entitlement-change stream doing their job

If approval only lands after a relaunch, the listener is not being started in
`AppDependencies.live()`.

## 7. Refund

Refund the sandbox purchase from App Store Connect. Expect the row to re-lock, and
if Hindi was the active language, expect the app to fall back to no active language.

**Study history on disk is deliberately left alone.** A re-purchase gets the
learner's progress back intact. Do not "fix" this.

## Traps

**The additive-only entitlement refresh cannot be tested before release.**
`StoreKitPurchaseService.refreshEntitlements()` only ever *adds* to the entitlement
cache; a language is removed only on an explicit `revocationDate`. That exists
because Apple's forums carry open iOS 26.x reports of
`Transaction.currentEntitlements` returning an empty sequence for a valid,
unrefunded non-consumable. Those reports are **production-only and do not reproduce
in sandbox**, so no amount of sandbox testing will exercise this. It is deliberate,
it is load-bearing, and it must not be "simplified" into a wholesale cache replace.

**StoreKit testing is broken from the command line on iOS 26.5.** `xcodebuild test`
does not push the scheme's StoreKit configuration to the simulator's `storekitd`, so
`SKTestSession` silently yields an empty store — it does not even throw on
deliberately invalid JSON. `StoreKitPurchaseServiceTests` skips itself when it
detects this. **An iOS 18.5 runtime was tried on 2026-08-01 and did not help** —
the runtime is not the variable, the command line is. Opening the project in the
Xcode IDE and running the suite there is the only untried way to exercise those
six tests.

**Family Sharing is off.** It is an App Store Connect toggle, flippable later with no
code change. It currently carries the same iOS 26.x entitlement regression, which is
a reason to wait rather than rush.
