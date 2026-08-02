# StoreKit 2 Monetization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the second language buyable — Hindi ships locked today with no way to unlock it. FR-14 (purchase), FR-15 (restore), FR-1/FR-2 (lock state, free launch language).

**Architecture:** Four new app-target types. `PurchaseService` is a presentation-owned port (the `SpeechService` precedent from Phase 8). `StoreKitPurchaseService` is the only file that imports StoreKit and conforms to *both* `PurchaseService` and Domain's existing `EntitlementStore`, so entitlements and purchases share one cache. `PurchaseViewModel` is the state machine and knows nothing about StoreKit. `PurchaseSheet` is the surface. **Domain does not change at all.**

**Tech Stack:** StoreKit 2, StoreKitTest (`SKTestSession`), Swift Testing, SwiftUI, `OSAllocatedUnfairLock`.

**Spec:** [`docs/superpowers/specs/2026-08-01-storekit-monetization-design.md`](../specs/2026-08-01-storekit-monetization-design.md). Read Decisions 1–6 before starting. Three deltas from the spec are recorded in "Deviations from the spec" below — read those too.

## Global Constraints

- Deployment target **iOS 17.0**; SDK iOS 26.5; app target compiles Swift 5 mode with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- Product identifier format: `arjunpathak.FullDeck.language.<code>` — **derived from `LanguageCode`, never stored in the manifest** (ADR-004).
- Test-first for all logic, one behaviour at a time: failing test → confirm it fails for the *right* reason → minimal code → green. `StoreKitPurchaseService` is framework glue, tested alongside.
- Every test display name starts with its requirement ID: `@Test("FR-14 …")`.
- No test reads `Date()`, sleeps, or uses unseeded randomness (`scripts/determinism-check.sh` greps for it).
- Every user-facing string goes through `String(localized:)` into `FullDeck/FullDeck/Localizable.xcstrings` **with its Spanish translation** (NFR-12).
- `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens` runs **unfiltered** as of Phase 10.5 and must stay that way.
- SwiftLint `--strict` must report 0 violations.
- All three targets are `PBXFileSystemSynchronizedRootGroup`s — **new files are picked up from disk; never edit `project.pbxproj` to add one.**
- Conventional commits, one per task.

### Verified API notes (checked 2026-08-01 against the iOS 26.5 SDK, not the docs site)

| API | Status |
|---|---|
| `Transaction.currentEntitlements` (plural static var) | **Current.** Not deprecated. The spec's Sources note is right: the *singular* `currentEntitlement(for:)` is what carries `deprecated: 18.4` |
| `Transaction.currentEntitlements(for:)` | New in iOS 18.4 — **unusable here**, deployment target is 17.0. Not needed; we iterate all entitlements |
| `Transaction.updates`, `AppStore.sync()`, `Product.products(for:)` | Current, iOS 15+ |
| `Product.purchase(options:)` | Current, and **`@MainActor`**. Calling it with `await` from a nonisolated async context is legal — the compiler inserts the hop |
| `Product.PurchaseResult` | `.success` / `.userCancelled` / `.pending` unchanged |
| `Product.PurchaseError` | Gained `.paymentMethodBindingConfigurationRequired` in 26.5. Falls through the generic failure path — no special handling |
| `SKTestSession` | Current, `NS_SWIFT_SENDABLE`. `setSimulatedError(_:forAPI:)` is the live error-injection API (iOS 17+) |
| `SKTestSession.failTransactionsEnabled`, `.failureError`, ObjC `buyProduct(productIdentifier:)` | **Deprecated.** Use `setSimulatedError(_:forAPI:)` and Swift `buyProduct(identifier:options:)` |
| WWDC26 StoreKit additions | Multi-user subscriptions, group purchases, commitment plans, offer codes — **all subscription-side.** Nothing touches a one-time non-consumable |
| iOS 26.x `currentEntitlements`-empty bug | **Still open.** Fresh reports on Xcode 26.4 / iOS 26.4.1 (May 2026), production-only, does not reproduce in sandbox. Decision 4's additive-only refresh is *reinforced*, not obsolete |

## Deviations from the spec

Three, all small, all recorded here so a reviewer sees them as intent rather than drift.

1. **Restore lives on `LanguageSelectionViewModel`, not `PurchaseViewModel`.** The spec's state table has restore transitions inside the purchase state machine, but Decision 5 puts the Restore control in the Languages screen toolbar — restore is not scoped to one language. Putting it on the screen that owns the control means the sheet never needs a restore path. `PurchaseService.restore()` returns `Void`; the Languages screen compares the unlocked set before and after to decide whether to say "No previous purchases found."

2. **One string the spec's error table omits: "Couldn't restore your purchases."** `AppStore.sync()` throws on a network failure, and NFR-10 requires a real user-facing state rather than silence.

3. **`PurchaseService` carries an `entitlementChanges` stream.** The launch entitlement refresh is async and can finish *after* `LanguageSelectionViewModel.load()` has already run — without a change signal a paid language reads as locked until the learner navigates away and back. The same stream delivers a late `pending` approval and a revocation.

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `FullDeck/FullDeck/Services/PurchaseService.swift` | The port, `PurchaseOutcome`, `PurchaseFailure`, `ProductIdentifier`, and the `NoPurchasesService` stub |
| `FullDeck/FullDeck/Services/StoreKitPurchaseService.swift` | The adapter. **The only file importing StoreKit** |
| `FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift` | The state machine |
| `FullDeck/FullDeck/Views/PurchaseSheet.swift` | The sheet |
| `FullDeck/FullDeckTests/ProductIdentifierTests.swift` | Derivation, both directions |
| `FullDeck/FullDeckTests/PurchaseViewModelTests.swift` | Every transition, against a fake |
| `FullDeck/FullDeckTests/StoreKitPurchaseServiceTests.swift` | The adapter against `SKTestSession` |
| `FullDeck/FullDeckTests/FullDeck.storekit` | Local StoreKit test configuration |
| `docs/app-store-connect-setup.md` | The out-of-Xcode walkthrough |

**Modify:**

| File | Change |
|---|---|
| `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift` | Restore, the revoked-active-language rule, `restoreMessage` |
| `FullDeck/FullDeck/Views/LanguageSelectionView.swift` | Sheet presentation from a locked row, Restore toolbar item, change-stream observation |
| `FullDeck/FullDeck/AppDependencies.swift` | Hold `purchases`; `live()` builds and starts the StoreKit adapter |
| `FullDeck/FullDeckTests/Fakes.swift` | `FakePurchaseService` |
| `FullDeck/FullDeck/Localizable.xcstrings` | Ten new strings + Spanish |
| `FullDeck/FullDeckUITests/FullDeckUITests.swift` | Audit extends to the purchase sheet |
| `docs/next-task.md` | Point at Phase 13 |

**Untouched on purpose:** everything under `Packages/`. If a task makes you want to edit Domain or Data, stop — that is the ADR-004 signal, and it means the design is wrong, not the package.

---

### Task 1: The port and the product-identifier derivation

Pure functions and a protocol. No StoreKit yet.

**Files:**
- Create: `FullDeck/FullDeck/Services/PurchaseService.swift`
- Test: `FullDeck/FullDeckTests/ProductIdentifierTests.swift`

**Interfaces:**
- Consumes: `Domain.LanguageCode`.
- Produces: `PurchaseService`, `PurchaseOutcome`, `PurchaseFailure`, `ProductIdentifier.forLanguage(_:)`, `ProductIdentifier.languageCode(from:)`, `NoPurchasesService`.

- [ ] **Step 1: Write the failing test**

`FullDeck/FullDeckTests/ProductIdentifierTests.swift`:

```swift
import Domain
import Testing

@testable import FullDeck

@Suite("Product identifiers")
struct ProductIdentifierTests {
    @Test("FR-14 a language's product id is derived from its code, never stored")
    func derivesForward() {
        #expect(
            ProductIdentifier.forLanguage(LanguageCode("hi"))
                == "arjunpathak.FullDeck.language.hi")
    }

    @Test("FR-14 a transaction's product id maps back to its language")
    func derivesBackward() {
        #expect(
            ProductIdentifier.languageCode(from: "arjunpathak.FullDeck.language.hi")
                == LanguageCode("hi"))
    }

    @Test("NFR-10 a product id from outside this app maps to no language")
    func rejectsForeignIdentifiers() {
        // StoreKit hands us every transaction on the account, not only ours.
        #expect(ProductIdentifier.languageCode(from: "com.example.other") == nil)
        #expect(ProductIdentifier.languageCode(from: "arjunpathak.FullDeck.language.") == nil)
    }
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests/ProductIdentifierTests
```

Expected: compile failure, `cannot find 'ProductIdentifier' in scope`. That is a legitimate red for a type that does not exist yet.

- [ ] **Step 3: Write the port and the derivation**

`FullDeck/FullDeck/Services/PurchaseService.swift`:

```swift
import Domain
import Foundation

/// What the purchase state machine needs from the store (FR-14, FR-15).
///
/// Presentation owns this port and it lives beside its adapter — the precedent
/// `SpeechService` set in Phase 8. Domain never learns that buying exists: it
/// needs `isUnlocked`, which `EntitlementStore` already gives it, and adding a
/// purchase port to Domain would widen its surface for no domain consumer.
protocol PurchaseService: Sendable {
    /// Fires every time the entitlement set changes — a purchase, a late
    /// `pending` approval, a revocation, or the launch refresh landing.
    ///
    /// The launch refresh is async and can finish *after* the Languages screen
    /// has already loaded. Without this the learner sees a language they paid
    /// for still wearing a padlock until they navigate away and back.
    var entitlementChanges: AsyncStream<Void> { get }

    /// StoreKit's localized display price, or nil when the store has no such
    /// product. Never a hardcoded "$0.99" — the price is per-storefront.
    func price(for languageCode: LanguageCode) async throws -> String?

    func purchase(_ languageCode: LanguageCode) async throws -> PurchaseOutcome

    /// StoreKit 2's restore. Deliberately user-initiated: it can prompt for an
    /// Apple ID password, so it never runs on its own.
    func restore() async throws
}

/// Cancelling is not an error, so it is an outcome rather than a thrown failure
/// (spec Decision 3: the sheet returns to the price silently).
enum PurchaseOutcome: Equatable {
    case purchased
    case cancelled
    case pending
}

enum PurchaseFailure: Error, Equatable {
    case productUnavailable
    /// `VerificationResult.unverified`. Treated as a failure, never as success.
    case unverified
    case storeError
}

enum ProductIdentifier {
    static let prefix = "arjunpathak.FullDeck.language."

    static func forLanguage(_ code: LanguageCode) -> String { prefix + code.rawValue }

    /// StoreKit hands back every transaction on the account, including products
    /// from other apps sharing a team prefix, so this must be able to say "not
    /// one of ours" rather than assume.
    static func languageCode(from productID: String) -> LanguageCode? {
        guard productID.hasPrefix(prefix) else { return nil }
        let code = String(productID.dropFirst(prefix.count))
        return code.isEmpty ? nil : LanguageCode(code)
    }
}

/// The pre-StoreKit stub, kept for `AppDependencies.make` (integration tests must
/// not reach the store) and SwiftUI previews. Its counterpart
/// `NoPurchasesEntitlementStore` already lives in `StubEntitlementStore.swift`.
struct NoPurchasesService: PurchaseService {
    var entitlementChanges: AsyncStream<Void> { AsyncStream { $0.finish() } }
    func price(for languageCode: LanguageCode) async throws -> String? { nil }
    func purchase(_ languageCode: LanguageCode) async throws -> PurchaseOutcome {
        throw PurchaseFailure.productUnavailable
    }
    func restore() async throws {}
}
```

`LanguageCode` is already `Hashable`, so `==` in the tests works without adding a conformance.

- [ ] **Step 4: Run the tests and confirm they pass**

Same command as Step 2. Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/Services/PurchaseService.swift FullDeck/FullDeckTests/ProductIdentifierTests.swift && git commit -m "feat: add the purchase port and product-id derivation"
```

---

### Task 2: The purchase state machine — loading a product

The first half of `PurchaseViewModel`: idle → loadingProduct → ready / unavailable.

**Files:**
- Create: `FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift`
- Create: `FullDeck/FullDeckTests/PurchaseViewModelTests.swift`
- Modify: `FullDeck/FullDeckTests/Fakes.swift`

**Interfaces:**
- Consumes: `PurchaseService`, `PurchaseOutcome`, `PurchaseFailure` from Task 1.
- Produces: `PurchaseViewModel`, its `State` enum, `loadProduct()`, `buy()`, `didUnlock`. `FakePurchaseService` for later tasks.

- [ ] **Step 1: Add the fake**

Append to `FullDeck/FullDeckTests/Fakes.swift`:

```swift
/// Records what was asked of the store and returns whatever the test set up.
/// A class, not a struct, so a test can read `purchaseCount` after the fact.
final class FakePurchaseService: PurchaseService, @unchecked Sendable {
    var priceToReturn: String? = "$0.99"
    var priceError: Error?
    var outcomeToReturn: PurchaseOutcome = .purchased
    var purchaseError: Error?
    var restoreError: Error?

    private(set) var purchaseCount = 0
    private(set) var restoreCount = 0

    let entitlementChanges: AsyncStream<Void> = AsyncStream { $0.finish() }

    func price(for languageCode: LanguageCode) async throws -> String? {
        if let priceError { throw priceError }
        return priceToReturn
    }

    func purchase(_ languageCode: LanguageCode) async throws -> PurchaseOutcome {
        purchaseCount += 1
        if let purchaseError { throw purchaseError }
        return outcomeToReturn
    }

    func restore() async throws {
        restoreCount += 1
        if let restoreError { throw restoreError }
    }
}
```

`@unchecked Sendable` is honest here: the fake is mutated only from the main actor inside tests, and the alternative (a lock in a test double) is ceremony that proves nothing.

- [ ] **Step 2: Write the failing tests for product loading**

`FullDeck/FullDeckTests/PurchaseViewModelTests.swift`:

```swift
import Domain
import Testing

@testable import FullDeck

@MainActor
@Suite("Purchase state machine")
struct PurchaseViewModelTests {
    func makeViewModel(
        _ purchases: FakePurchaseService
    ) -> PurchaseViewModel {
        PurchaseViewModel(
            languageCode: LanguageCode("hi"), displayName: "हिन्दी", purchases: purchases)
    }

    @Test("FR-14 the sheet opens idle")
    func startsIdle() {
        #expect(makeViewModel(FakePurchaseService()).state == .idle)
    }

    @Test("FR-14 a found product shows StoreKit's localized price")
    func loadsPrice() async {
        let purchases = FakePurchaseService()
        purchases.priceToReturn = "€0,99"
        let viewModel = makeViewModel(purchases)

        await viewModel.loadProduct()

        #expect(viewModel.state == .ready(price: "€0,99"))
    }

    @Test("NFR-10 no product for this language is a state, not a crash")
    func missingProductIsUnavailable() async {
        let purchases = FakePurchaseService()
        purchases.priceToReturn = nil
        let viewModel = makeViewModel(purchases)

        await viewModel.loadProduct()

        #expect(viewModel.state == .unavailable("The store isn't reachable right now."))
    }

    @Test("NFR-10 a store error is the same state as a missing product")
    func storeErrorIsUnavailable() async {
        let purchases = FakePurchaseService()
        purchases.priceError = PurchaseFailure.storeError
        let viewModel = makeViewModel(purchases)

        await viewModel.loadProduct()

        #expect(viewModel.state == .unavailable("The store isn't reachable right now."))
    }
}
```

The message is asserted as a literal string on purpose: these tests run under the English development language, and asserting the rendered copy is what catches a string that never made it into the catalog.

- [ ] **Step 3: Run and confirm they fail for the right reason**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests/PurchaseViewModelTests
```

Expected: `cannot find 'PurchaseViewModel' in scope`.

- [ ] **Step 4: Write the minimal state machine**

`FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift`:

```swift
import Domain
import Foundation
import Observation

/// The purchase state machine (spec Decision 3). Knows nothing about StoreKit —
/// it talks to `PurchaseService`, which is why every transition below is
/// testable against a fake in milliseconds with no simulator and no network.
///
/// Separate from `LanguageSelectionViewModel` on purpose: folding six states,
/// price fetching and restore into that ~70-line type would give it two
/// unrelated jobs, and every purchase test would then need packs, a manifest
/// and `UserDefaults` set up before reaching its assertion.
@MainActor
@Observable
final class PurchaseViewModel {
    enum State: Equatable {
        case idle
        case loadingProduct
        case ready(price: String)
        case purchasing
        case purchased
        case pending
        case failed(String)
        case unavailable(String)
    }

    private(set) var state: State = .idle

    let languageCode: LanguageCode
    let displayName: String

    private let purchases: PurchaseService
    /// Held apart from `state` so a retry out of `.failed` still knows the
    /// price without refetching it.
    private var price: String?

    init(languageCode: LanguageCode, displayName: String, purchases: PurchaseService) {
        self.languageCode = languageCode
        self.displayName = displayName
        self.purchases = purchases
    }

    func loadProduct() async {
        state = .loadingProduct
        // A missing product and an unreachable store are the same thing to the
        // learner: they cannot buy right now, and neither is their fault.
        guard let fetched = try? await purchases.price(for: languageCode) else {
            state = .unavailable(String(localized: "The store isn't reachable right now."))
            return
        }
        price = fetched
        state = .ready(price: fetched)
    }
}
```

- [ ] **Step 5: Run and confirm green**

Same command. Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift FullDeck/FullDeckTests/PurchaseViewModelTests.swift FullDeck/FullDeckTests/Fakes.swift && git commit -m "feat: load a language's price into the purchase state machine"
```

---

### Task 3: The purchase state machine — buying

The five outcomes of `buy()`. Add one test, green it, add the next — not all five then a wall of code.

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift`
- Modify: `FullDeck/FullDeckTests/PurchaseViewModelTests.swift`

**Interfaces:**
- Produces: `PurchaseViewModel.buy()`, `PurchaseViewModel.didUnlock`.

- [ ] **Step 1: Write the failing test for the success path**

Append inside `PurchaseViewModelTests`:

```swift
    @Test("FR-14 a verified purchase unlocks the language")
    func successfulPurchase() async {
        let purchases = FakePurchaseService()
        let viewModel = makeViewModel(purchases)
        await viewModel.loadProduct()

        await viewModel.buy()

        #expect(viewModel.state == .purchased)
        #expect(viewModel.didUnlock)
    }
```

- [ ] **Step 2: Run and confirm it fails**

Expected: `value of type 'PurchaseViewModel' has no member 'buy'`.

- [ ] **Step 3: Implement just the success path**

Add to `PurchaseViewModel`:

```swift
    /// Set once a purchase or a restore lands, so the Languages screen knows to
    /// reload and drop the padlock.
    private(set) var didUnlock = false

    func buy() async {
        guard let price else { return }
        state = .purchasing
        do {
            switch try await purchases.purchase(languageCode) {
            case .purchased:
                didUnlock = true
                state = .purchased
            case .cancelled:
                state = .ready(price: price)
            case .pending:
                state = .pending
            }
        } catch {
            state = .failed(
                String(localized: "Couldn't complete the purchase. You haven't been charged."))
        }
    }
```

Writing the whole `switch` at once is the honest minimum: the enum is exhaustive, so the compiler refuses a partial one, and stubbing the other two arms only to rewrite them in the next step is busywork.

- [ ] **Step 4: Run and confirm green.** Expected: 5 passed.

- [ ] **Step 5: Write the failing test for cancellation**

```swift
    @Test("FR-14 cancelling returns to the price with no error shown")
    func cancellingIsSilent() async {
        let purchases = FakePurchaseService()
        purchases.outcomeToReturn = .cancelled
        let viewModel = makeViewModel(purchases)
        await viewModel.loadProduct()

        await viewModel.buy()

        // Cancelling is a decision, not a failure. Anything that reads as an
        // error here is the app scolding someone for changing their mind.
        #expect(viewModel.state == .ready(price: "$0.99"))
        #expect(!viewModel.didUnlock)
    }
```

- [ ] **Step 6: Run.** Expected: **PASS** — Step 3's exhaustive switch already covers it. That is fine and worth saying out loud: the test still earns its place as the regression guard that stops someone "helpfully" adding an error message to the cancel path later.

- [ ] **Step 7: Write the failing test for pending**

```swift
    @Test("FR-14 an Ask-to-Buy purchase waits rather than failing")
    func pendingPurchase() async {
        let purchases = FakePurchaseService()
        purchases.outcomeToReturn = .pending
        let viewModel = makeViewModel(purchases)
        await viewModel.loadProduct()

        await viewModel.buy()

        // Neither complete nor failed: a family organiser has to approve it, and
        // the entitlement arrives later through Transaction.updates — possibly
        // after the app has been relaunched. The language stays locked.
        #expect(viewModel.state == .pending)
        #expect(!viewModel.didUnlock)
    }

    @Test("NFR-10 a store failure leaves the language locked and says so")
    func failedPurchase() async {
        let purchases = FakePurchaseService()
        purchases.purchaseError = PurchaseFailure.storeError
        let viewModel = makeViewModel(purchases)
        await viewModel.loadProduct()

        await viewModel.buy()

        #expect(
            viewModel.state
                == .failed("Couldn't complete the purchase. You haven't been charged."))
        #expect(!viewModel.didUnlock)
    }

    @Test("NFR-10 an unverified transaction is a failure, never a success")
    func unverifiedIsFailure() async {
        let purchases = FakePurchaseService()
        purchases.purchaseError = PurchaseFailure.unverified
        let viewModel = makeViewModel(purchases)
        await viewModel.loadProduct()

        await viewModel.buy()

        #expect(!viewModel.didUnlock)
        if case .failed = viewModel.state {} else {
            Issue.record("unverified must not unlock anything, got \(viewModel.state)")
        }
    }

    @Test("FR-14 a failed purchase can be retried without reopening the sheet")
    func retryAfterFailure() async {
        let purchases = FakePurchaseService()
        purchases.purchaseError = PurchaseFailure.storeError
        let viewModel = makeViewModel(purchases)
        await viewModel.loadProduct()
        await viewModel.buy()

        purchases.purchaseError = nil
        await viewModel.buy()

        #expect(viewModel.state == .purchased)
        #expect(purchases.purchaseCount == 2)
    }

    @Test("NFR-10 buying before the price loads does not reach the store")
    func buyingBeforeReadyIsANoOp() async {
        let purchases = FakePurchaseService()
        let viewModel = makeViewModel(purchases)

        await viewModel.buy()

        #expect(purchases.purchaseCount == 0)
        #expect(viewModel.state == .idle)
    }
```

- [ ] **Step 8: Run.** Expected: 11 passed. `retryAfterFailure` is the one that proves holding `price` outside `state` was necessary — if it were only in `.ready`, the retry would silently no-op.

- [ ] **Step 9: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/PurchaseViewModel.swift FullDeck/FullDeckTests/PurchaseViewModelTests.swift && git commit -m "feat: handle every purchase outcome in the state machine"
```

---

### Task 4: Restore, and the revoked-active-language rule

Both belong to `LanguageSelectionViewModel` — the screen that owns the Restore control and the active language.

**Files:**
- Modify: `FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift`
- Modify: `FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift`

**Interfaces:**
- Consumes: `PurchaseService` (Task 1), `StubEntitlementStore` (already in `Fakes.swift`), `FakePurchaseService` (Task 2).
- Produces: `LanguageSelectionViewModel.restore()`, `restoreMessage`, and a `purchases:` init parameter.

- [ ] **Step 1: Write the failing test for the revoked active language**

Append to `LanguageSelectionViewModelTests`. Match the existing helper style in that file rather than inventing a new one — read it first.

```swift
    @Test("FR-14 a revoked language stops being the active one")
    func revokedActiveLanguageIsCleared() async {
        let defaults = throwawayDefaults()
        let packStore = FakePackStore(descriptors: [
            frDescriptor(unlockedByDefault: false)
        ])
        var entitlements = StubEntitlementStore(unlocked: ["fr"])
        let viewModel = LanguageSelectionViewModel(
            packStore: packStore, entitlements: entitlements, purchases: FakePurchaseService(),
            defaults: defaults)
        await viewModel.load()
        if case .ready(let options) = viewModel.state { viewModel.select(options[0]) }
        #expect(viewModel.activeLanguage == LanguageCode("fr"))

        // The refund lands: StoreKit reports an explicit revocationDate and the
        // adapter drops it from the cache.
        entitlements = StubEntitlementStore(unlocked: [])
        let afterRevocation = LanguageSelectionViewModel(
            packStore: packStore, entitlements: entitlements, purchases: FakePurchaseService(),
            defaults: defaults)
        await afterRevocation.load()

        #expect(afterRevocation.activeLanguage == nil)
    }
```

If `throwawayDefaults()` and `FakePackStore(descriptors:)` are named differently in that file, use the existing names — do not add duplicates.

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests/LanguageSelectionViewModelTests
```

Expected: compile failure on the unknown `purchases:` argument. Add the parameter (Step 3) and re-run before treating the assertion failure as the real red.

- [ ] **Step 3: Add the parameter and the rule**

In `LanguageSelectionViewModel`, add the stored property and widen `init`:

```swift
    private let purchases: PurchaseService

    init(
        packStore: PackStore, entitlements: EntitlementStore, purchases: PurchaseService,
        defaults: UserDefaults = .standard
    ) {
        self.packStore = packStore
        self.entitlements = entitlements
        self.purchases = purchases
        self.defaults = defaults
    }
```

Then, inside `load()`, after `state = .ready(...)` and after the saved-language restore block, add:

```swift
            // A revoked language must not stay active (spec Decision 4). Review
            // history on disk is deliberately untouched — a re-purchase gets
            // their progress back intact, and destroying it over a billing event
            // would be unrecoverable if the refund turned out to be a mistake.
            if let active = activeLanguage,
                !descriptors.contains(where: {
                    $0.languageCode == active
                        && ($0.unlockedByDefault || entitlements.isUnlocked($0.languageCode))
                }) {
                activeLanguage = nil
                defaults.removeObject(forKey: Self.activeLanguageKey)
            }
```

Fix the other call sites the new parameter breaks by passing `purchases: FakePurchaseService()` in tests and `NoPurchasesService()` in `AppDependencies` — Task 6 replaces the latter with the real adapter.

- [ ] **Step 4: Run and confirm green.**

- [ ] **Step 5: Write the failing tests for restore**

```swift
    @Test("FR-15 restoring a previous purchase unlocks its row")
    func restoreUnlocks() async {
        let defaults = throwawayDefaults()
        let entitlements = StubEntitlementStore(unlocked: [])
        let purchases = FakePurchaseService()
        let viewModel = LanguageSelectionViewModel(
            packStore: FakePackStore(descriptors: [frDescriptor(unlockedByDefault: false)]),
            entitlements: entitlements, purchases: purchases, defaults: defaults)
        await viewModel.load()

        await viewModel.restore()

        #expect(purchases.restoreCount == 1)
    }

    @Test("FR-15 restoring with nothing to restore says so plainly")
    func restoreWithNothingOwned() async {
        let viewModel = LanguageSelectionViewModel(
            packStore: FakePackStore(descriptors: [frDescriptor(unlockedByDefault: false)]),
            entitlements: StubEntitlementStore(unlocked: []),
            purchases: FakePurchaseService(), defaults: throwawayDefaults())
        await viewModel.load()

        await viewModel.restore()

        #expect(viewModel.restoreMessage == "No previous purchases found.")
    }

    @Test("NFR-10 a restore that cannot reach the store reports it")
    func restoreFailureIsReported() async {
        let purchases = FakePurchaseService()
        purchases.restoreError = PurchaseFailure.storeError
        let viewModel = LanguageSelectionViewModel(
            packStore: FakePackStore(descriptors: [frDescriptor(unlockedByDefault: false)]),
            entitlements: StubEntitlementStore(unlocked: []),
            purchases: purchases, defaults: throwawayDefaults())
        await viewModel.load()

        await viewModel.restore()

        #expect(viewModel.restoreMessage == "Couldn't restore your purchases.")
    }
```

- [ ] **Step 6: Run and confirm they fail** — `has no member 'restore'`.

- [ ] **Step 7: Implement restore**

```swift
    /// FR-15. Nil unless the last restore had something to say — a restore that
    /// worked speaks through the rows unlocking, not through a message.
    private(set) var restoreMessage: String?

    func restore() async {
        restoreMessage = nil
        let before = unlockedCodes()
        do {
            try await purchases.restore()
        } catch {
            restoreMessage = String(localized: "Couldn't restore your purchases.")
            return
        }
        await load()
        if unlockedCodes() == before {
            restoreMessage = String(localized: "No previous purchases found.")
        }
    }

    private func unlockedCodes() -> Set<String> {
        guard case .ready(let options) = state else { return [] }
        return Set(options.filter(\.isUnlocked).map(\.id))
    }
```

Comparing the unlocked set before and after is how the screen knows whether anything actually came back, without `PurchaseService` having to report per-language ownership it would only ever use here.

- [ ] **Step 8: Run and confirm green.**

- [ ] **Step 9: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/LanguageSelectionViewModel.swift FullDeck/FullDeckTests/LanguageSelectionViewModelTests.swift && git commit -m "feat: restore purchases and clear a revoked active language"
```

---

### Task 5: The StoreKit adapter

The only file that imports StoreKit. Framework glue — tested alongside, with `SKTestSession`, not before.

**Files:**
- Create: `FullDeck/FullDeck/Services/StoreKitPurchaseService.swift`
- Create: `FullDeck/FullDeckTests/FullDeck.storekit`
- Create: `FullDeck/FullDeckTests/StoreKitPurchaseServiceTests.swift`

**Interfaces:**
- Consumes: `PurchaseService`, `ProductIdentifier`, `PurchaseFailure` (Task 1); `Domain.EntitlementStore`.
- Produces: `StoreKitPurchaseService`, `.start()`.

- [ ] **Step 1: Write the StoreKit test configuration**

`FullDeck/FullDeckTests/FullDeck.storekit`. Put it in the **test** target, not the app — a shipping binary has no use for it. Both are synchronized groups, so dropping the file in is the whole job.

```json
{
  "identifier": "FullDeckTestConfiguration",
  "nonRenewingSubscriptions": [],
  "products": [
    {
      "displayPrice": "0.99",
      "familyShareable": false,
      "internalID": "hi-language-unlock",
      "localizations": [
        {
          "description": "All 1000 words in Hindi.",
          "displayName": "Hindi",
          "locale": "en_US"
        }
      ],
      "productID": "arjunpathak.FullDeck.language.hi",
      "referenceName": "Hindi language unlock",
      "type": "NonConsumable"
    }
  ],
  "settings": { "_askToBuyEnabled": false },
  "subscriptionGroups": [],
  "version": { "major": 3, "minor": 0 }
}
```

- [ ] **Step 2: Write the adapter**

`FullDeck/FullDeck/Services/StoreKitPurchaseService.swift`:

```swift
import Domain
import Foundation
import StoreKit
import os

/// The **only** file in the app that imports StoreKit (spec Decision 1).
///
/// Conforms to both `PurchaseService` and Domain's `EntitlementStore` on
/// purpose: entitlements and purchases are the same underlying StoreKit state,
/// and splitting them across two adapters would mean two caches that can
/// disagree about whether someone owns a language.
///
/// `isUnlocked` has to stay synchronous — Domain's port says so, and every
/// caller is a view building a row. StoreKit is async, so the entitlement set
/// lives behind a lock: reads are synchronous, writes arrive from the launch
/// refresh and the `Transaction.updates` listener.
/// `OSAllocatedUnfairLock` rather than `NSLock` because it is generic over its
/// state and genuinely `Sendable`, so this type needs no `@unchecked`.
final class StoreKitPurchaseService: PurchaseService, EntitlementStore {
    private let unlocked = OSAllocatedUnfairLock(initialState: Set<String>())
    private let continuation: AsyncStream<Void>.Continuation
    let entitlementChanges: AsyncStream<Void>

    /// Held for the process lifetime and never cancelled: a purchase can complete
    /// while the app is backgrounded, and this is what delivers it afterwards.
    private var listener: Task<Void, Never>?

    init() {
        (entitlementChanges, continuation) = AsyncStream.makeStream()
    }

    deinit { listener?.cancel() }

    /// Called once from the composition root.
    func start() {
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.apply(result)
            }
        }
        Task { [weak self] in await self?.refreshEntitlements() }
    }

    // MARK: - EntitlementStore

    func isUnlocked(_ languageCode: LanguageCode) -> Bool {
        unlocked.withLock { $0.contains(languageCode.rawValue) }
    }

    // MARK: - PurchaseService

    func price(for languageCode: LanguageCode) async throws -> String? {
        try await product(for: languageCode)?.displayPrice
    }

    func purchase(_ languageCode: LanguageCode) async throws -> PurchaseOutcome {
        guard let product = try await product(for: languageCode) else {
            throw PurchaseFailure.productUnavailable
        }
        // `Product.purchase(options:)` is @MainActor; awaiting it from this
        // nonisolated context is legal and the compiler inserts the hop.
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseFailure.unverified
            }
            await record(transaction)
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            throw PurchaseFailure.storeError
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlement cache

    /// **Additive. It never removes** (spec Decision 4).
    ///
    /// Apple's forums carry open iOS 26.x reports of
    /// `Transaction.currentEntitlements` yielding an empty sequence for a valid,
    /// unrefunded non-consumable — production only, not reproducible in sandbox,
    /// still unfixed as of Xcode 26.4. If this replaced the cache wholesale, one
    /// of those empty reads would silently re-lock a language someone paid for.
    /// Treating absence as revocation makes an OS bug indistinguishable from a
    /// refund; requiring an explicit `revocationDate` does not.
    func refreshEntitlements() async {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                transaction.revocationDate == nil,
                let code = ProductIdentifier.languageCode(from: transaction.productID)
            else { continue }
            unlocked.withLock { _ = $0.insert(code.rawValue) }
        }
        continuation.yield()
    }

    private func apply(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await record(transaction)
    }

    /// The one place a language enters or leaves the cache. A non-nil
    /// `revocationDate` is the *only* signal that removes one.
    private func record(_ transaction: StoreKit.Transaction) async {
        defer { continuation.yield() }
        await transaction.finish()
        guard let code = ProductIdentifier.languageCode(from: transaction.productID) else {
            return  // Someone else's product on the same account.
        }
        unlocked.withLock {
            if transaction.revocationDate == nil {
                _ = $0.insert(code.rawValue)
            } else {
                _ = $0.remove(code.rawValue)
            }
        }
    }

    private func product(for languageCode: LanguageCode) async throws -> Product? {
        try await Product.products(for: [ProductIdentifier.forLanguage(languageCode)]).first
    }
}
```

- [ ] **Step 3: Write the integration tests**

`FullDeck/FullDeckTests/StoreKitPurchaseServiceTests.swift`:

```swift
import Domain
import StoreKitTest
import Testing

@testable import FullDeck

/// Framework glue, so these are written alongside the adapter rather than before
/// it — an integration test against `SKTestSession` is the honest test here.
/// `.serialized` because `SKTestSession` is process-wide state; two of these
/// running at once would see each other's transactions.
@Suite("StoreKit adapter", .serialized)
struct StoreKitPurchaseServiceTests {
    let hindi = LanguageCode("hi")

    func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "FullDeck")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    @Test("FR-14 the localized price comes from StoreKit, never a literal")
    func fetchesPrice() async throws {
        _ = try makeSession()
        let service = StoreKitPurchaseService()

        #expect(try await service.price(for: hindi) == "$0.99")
    }

    @Test("FR-14 a language with no product in the store has no price")
    func unknownLanguageHasNoPrice() async throws {
        _ = try makeSession()
        let service = StoreKitPurchaseService()

        #expect(try await service.price(for: LanguageCode("zz")) == nil)
    }

    @Test("FR-14 buying a language unlocks it")
    func purchaseUnlocks() async throws {
        _ = try makeSession()
        let service = StoreKitPurchaseService()
        #expect(!service.isUnlocked(hindi))

        #expect(try await service.purchase(hindi) == .purchased)

        #expect(service.isUnlocked(hindi))
    }

    @Test("FR-15 a purchase made before this install is restored")
    func restoreFindsAPastPurchase() async throws {
        let session = try makeSession()
        // Bought on another device / a previous install.
        _ = try await session.buyProduct(identifier: ProductIdentifier.forLanguage(hindi))
        let service = StoreKitPurchaseService()

        try await service.restore()

        #expect(service.isUnlocked(hindi))
    }

    @Test("NFR-10 a store error surfaces as a thrown failure, not a crash")
    func purchaseFailureThrows() async throws {
        let session = try makeSession()
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        let service = StoreKitPurchaseService()

        await #expect(throws: (any Error).self) { try await service.purchase(hindi) }
        #expect(!service.isUnlocked(hindi))
    }

    @Test("FR-14 a refunded language is dropped from the entitlement cache")
    func revocationRelocks() async throws {
        let session = try makeSession()
        let service = StoreKitPurchaseService()
        #expect(try await service.purchase(hindi) == .purchased)
        #expect(service.isUnlocked(hindi))

        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        service.start()
        // The revocation arrives through Transaction.updates; wait on the change
        // stream rather than sleeping (determinism-check forbids sleeps).
        var changes = service.entitlementChanges.makeAsyncIterator()
        await changes.next()

        #expect(!service.isUnlocked(hindi))
    }
}
```

- [ ] **Step 4: Run them**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests/StoreKitPurchaseServiceTests
```

**Two things will plausibly go wrong here — neither is a reason to weaken a test:**

1. `SKTestSession(configurationFileNamed: "FullDeck")` throws "file not found". The synchronized group may not treat `.storekit` as a copyable resource. Fix by locating it explicitly instead:
   ```swift
   let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "FullDeck", withExtension: "storekit"))
   let session = try SKTestSession(contentsOf: url)
   ```
   with `private final class BundleMarker {}` in the test file. If the resource is genuinely not in the bundle, add it to the test target's Copy Bundle Resources phase **through the Xcode GUI** (this is a structural project change — do not hand-edit `project.pbxproj`), and show the resulting diff.
2. `revocationRelocks` hangs waiting on the change stream. `refundTransaction` may not deliver through `Transaction.updates` in the local test environment. If it does not, drop to asserting the unit that is actually ours: call `service.refreshEntitlements()` after the refund and assert the cache did **not** gain the language, and cover the removal branch by asserting `record` is the only writer. Say plainly in the commit message which one you shipped.

- [ ] **Step 5: Confirm the whole suite is still green, then commit**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Confirm the real count — `xcodebuild` will print `** TEST SUCCEEDED **` even when it ran zero tests:

```bash
xcrun xcresulttool get test-results summary --path "$(ls -dt ~/Library/Developer/Xcode/DerivedData/FullDeck-*/Logs/Test/*.xcresult | head -1)"
```

```bash
git add FullDeck/FullDeck/Services/StoreKitPurchaseService.swift FullDeck/FullDeckTests/StoreKitPurchaseServiceTests.swift FullDeck/FullDeckTests/FullDeck.storekit && git commit -m "feat: back entitlements with StoreKit"
```

---

### Task 6: The purchase sheet and the Languages screen

**Files:**
- Create: `FullDeck/FullDeck/Views/PurchaseSheet.swift`
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift`
- Modify: `FullDeck/FullDeck/AppDependencies.swift`
- Modify: `FullDeck/FullDeck/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PurchaseViewModel` (Tasks 2–3), `LanguageSelectionViewModel.restore()` (Task 4), `StoreKitPurchaseService` (Task 5).

- [ ] **Step 1: Wire the adapter into the composition root**

In `AppDependencies.swift`, add the property and widen `make`:

```swift
    let purchases: PurchaseService
```

```swift
    static func make(
        packsDirectory: URL, inMemory: Bool,
        purchases: PurchaseService = NoPurchasesService(),
        entitlements: EntitlementStore = NoPurchasesEntitlementStore()
    ) throws -> AppDependencies {
        let container = try SwiftDataReviewStore.makeContainer(inMemory: inMemory)
        return AppDependencies(
            packStore: JSONPackStore(packsDirectory: packsDirectory),
            reviewStore: SwiftDataReviewStore(modelContainer: container),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: entitlements,
            purchases: purchases)
    }

    static func live() throws -> AppDependencies {
        // One object behind both ports, so there is exactly one entitlement cache.
        let store = StoreKitPurchaseService()
        store.start()
        return try make(
            packsDirectory: bundledPacksDirectory, inMemory: false,
            purchases: store, entitlements: store)
    }
```

The defaults keep `make(packsDirectory:inMemory:)` working unchanged for the integration tests — those must not reach the store.

- [ ] **Step 2: Write the sheet**

`FullDeck/FullDeck/Views/PurchaseSheet.swift`:

```swift
import Domain
import SwiftUI

/// The purchase surface (FR-14, spec Decision 5). A dedicated sheet rather than
/// an inline buy button: the extra room is what lets the app say what $0.99
/// actually buys.
///
/// No confirm-then-buy alert. StoreKit's own sheet already carries the price,
/// the terms and a biometric confirmation; a second one is friction dressed as
/// courtesy.
struct PurchaseSheet: View {
    let viewModel: PurchaseViewModel
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: .spacingLarge) {
                Text(viewModel.displayName)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("All 1000 words. One payment, yours for good.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
                stateContent
            }
            .padding(.spacingLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await viewModel.loadProduct() }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle, .loadingProduct:
            ProgressView()
        case .ready(let price):
            buyButton(price)
        case .purchasing:
            ProgressView()
        case .purchased:
            // The sheet's job is done; the row behind it unlocks.
            Text("Unlocked.")
                .foregroundStyle(Color.textPrimary)
                .task {
                    onUnlocked()
                    dismiss()
                }
        case .pending:
            message("This purchase is waiting for approval.")
        case .failed(let text):
            VStack(spacing: .spacingMedium) {
                message(text)
                if case .ready = viewModel.state {} else if let price = retryPrice {
                    buyButton(price)
                }
            }
        case .unavailable(let text):
            message(text)
        }
    }

    private var retryPrice: String? {
        // `failed` keeps no price of its own; the view model still holds one, and
        // exposing it read-only is cheaper than threading it through the enum.
        viewModel.lastKnownPrice
    }

    private func buyButton(_ price: String) -> some View {
        Button {
            Task { await viewModel.buy() }
        } label: {
            Text("Unlock for \(price)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
    }
}
```

This needs one small addition to `PurchaseViewModel` — expose the held price:

```swift
    /// Read-only so the sheet can offer a retry out of `.failed` without the
    /// price having to live in every state that might precede one.
    var lastKnownPrice: String? { price }
```

Use whatever the spacing tokens are actually named in `Spacing`/the design layer — read one existing view (`StudyView.swift`) first and match it exactly rather than trusting `.spacingLarge` above.

- [ ] **Step 3: Present it from a locked row**

In `LanguageSelectionView`:

```swift
    @State private var purchasing: LanguageSelectionViewModel.Option?
```

Change the row's action:

```swift
        Button {
            // Presentation branch, so it lives here rather than in the view
            // model: `select()` already refuses a locked pack (FR-1), and this
            // decides what the tap *shows* instead.
            if option.isUnlocked {
                viewModel.select(option)
            } else {
                purchasing = option
            }
        } label: {
```

Attach to `content`'s `.ready` case, or to the `NavigationStack` content:

```swift
            .sheet(item: $purchasing) { option in
                PurchaseSheet(
                    viewModel: PurchaseViewModel(
                        languageCode: option.descriptor.languageCode,
                        displayName: option.descriptor.displayName,
                        purchases: purchases),
                    onUnlocked: { Task { await viewModel.load() } })
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore Purchases") {
                        Task { await viewModel.restore() }
                    }
                }
            }
            .alert(
                "Restore Purchases",
                isPresented: .constant(viewModel.restoreMessage != nil),
                actions: { Button("OK") { viewModel.clearRestoreMessage() } },
                message: { Text(viewModel.restoreMessage ?? "") })
            .task {
                // The launch refresh can land after `load()` has already run.
                for await _ in purchases.entitlementChanges { await viewModel.load() }
            }
```

`LanguageSelectionView` needs `let purchases: PurchaseService` added and passed from `ContentView`. Add `clearRestoreMessage()` to the view model:

```swift
    func clearRestoreMessage() { restoreMessage = nil }
```

- [ ] **Step 4: Add every new string to the catalog with its Spanish**

`FullDeck/FullDeck/Localizable.xcstrings` is JSON — add these keys in the same shape as the existing entries (`"localizations" → "es" → "stringUnit" → {"state": "translated", "value": …}`).

| Key (English) | Spanish |
|---|---|
| `All 1000 words. One payment, yours for good.` | `Las 1000 palabras. Un solo pago, tuyas para siempre.` |
| `Unlock for %@` | `Desbloquear por %@` |
| `Unlocked.` | `Desbloqueado.` |
| `Done` | `Listo` |
| `Restore Purchases` | `Restaurar compras` |
| `OK` | `OK` |
| `The store isn't reachable right now.` | `La tienda no está disponible en este momento.` |
| `Couldn't complete the purchase. You haven't been charged.` | `No se pudo completar la compra. No se te ha cobrado.` |
| `This purchase is waiting for approval.` | `Esta compra está esperando aprobación.` |
| `No previous purchases found.` | `No se encontraron compras anteriores.` |
| `Couldn't restore your purchases.` | `No se pudieron restaurar tus compras.` |

- [ ] **Step 5: Build, lint, and run the whole suite**

```bash
swiftlint lint --strict && xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Then look at it. Launch the app in the simulator, open Languages, tap the Hindi row, and screenshot the sheet. Without a StoreKit configuration attached to the *scheme* the product will not load and the sheet will read "The store isn't reachable right now." — that is correct behaviour, not a bug, and it is the state Step 6's audit will cover.

- [ ] **Step 6: Commit**

```bash
git add FullDeck/FullDeck/Views/PurchaseSheet.swift FullDeck/FullDeck/Views/LanguageSelectionView.swift FullDeck/FullDeck/ViewModels/ FullDeck/FullDeck/AppDependencies.swift FullDeck/FullDeck/Localizable.xcstrings && git commit -m "feat: present a purchase sheet from a locked language"
```

---

### Task 7: The sheet passes the accessibility audit

**Files:**
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift`
- Modify: `FullDeck/FullDeck.xcodeproj/xcshareddata/xcschemes/FullDeck.xcscheme`

- [ ] **Step 1: Attach the StoreKit configuration to the scheme**

So the audit sees the sheet in its `ready` state — with a real price and an enabled Buy button — rather than only its `unavailable` state.

This is an XML value edit, not a structural project change. Add to the `<LaunchAction>` element in `FullDeck.xcscheme`:

```xml
      <StoreKitConfigurationFileReference
         identifier = "../../../FullDeckTests/FullDeck.storekit">
      </StoreKitConfigurationFileReference>
```

Show the resulting `git diff` before continuing. If the path does not resolve (the reference is relative to the `.xcodeproj`), set it through Xcode's *Edit Scheme → Run → Options → StoreKit Configuration* picker instead and commit whatever Xcode writes.

- [ ] **Step 2: Extend the audit to the purchase sheet**

In `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`, after the Languages screen is on screen, tap the locked row and audit the sheet. Read the existing test body first and match its navigation style:

```swift
        // The purchase sheet — a whole screen the audit has never seen, and the
        // one place the app asks for money.
        app.buttons["हिन्दी, locked"].tap()
        #expect(app.staticTexts["हिन्दी"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
```

The audit runs **unfiltered**. If it reports a contrast failure, fix the colours — do not add a filter. Phase 12 found a real WCAG bug this way (`.disabled()` dimming a row to 3.33:1); the audit earns its keep precisely by not being narrowed.

- [ ] **Step 3: Run the UI tests**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckUITests
```

If a contrast failure appears, measure it rather than guessing: screenshot the simulator and sample the actual pixels before changing a colour.

- [ ] **Step 4: Commit**

```bash
git add FullDeck/FullDeckUITests/FullDeckUITests.swift FullDeck/FullDeck.xcodeproj/xcshareddata/xcschemes/FullDeck.xcscheme && git commit -m "test: extend the accessibility audit to the purchase sheet"
```

---

### Task 8: The App Store Connect walkthrough, and the phase wrap-up

Everything in this phase so far runs against a local test configuration. None of it proves the chain works against Apple's servers.

**Files:**
- Create: `docs/app-store-connect-setup.md`
- Modify: `docs/next-task.md`
- Modify: `docs/build-plan.md` (mark Phase 11 done)

- [ ] **Step 1: Write the walkthrough**

`docs/app-store-connect-setup.md` — a checklist Arjun can follow without this conversation. Cover, in order:

1. **Create the non-consumable.** App Store Connect → the app → Monetization → In-App Purchases → `+`. Type **Non-Consumable**. Reference Name `Hindi language unlock`, Product ID `arjunpathak.FullDeck.language.hi` — the ID must match `ProductIdentifier.forLanguage` exactly and **can never be changed or reused** once saved. Price Tier: $0.99 (USD). Add the English localization (display name + description) and the Spanish one, since the app ships `es`.
2. **Small Business Program.** Enroll at App Store Connect → Business → Agreements. It moves the commission from 30% to 15% for developers under $1M/year, which at $0.99 is the difference between $0.69 and $0.84 per sale. Enrollment is not automatic and takes effect the month after approval.
3. **Paid Applications agreement + banking and tax.** In-app purchases return **no products at all** until this agreement is active — a `Product.products(for:)` that comes back empty in sandbox is usually this, not a code bug.
4. **Sandbox tester.** Users and Access → Sandbox → Test Accounts. Use an email address not already an Apple ID. On the device: Settings → Developer → Sandbox Apple Account.
5. **The end-to-end sandbox run** — the part that matters. Build to a real device with a development profile, tap the locked Hindi row, buy it with the sandbox account, confirm the row unlocks. Then delete the app, reinstall, tap **Restore Purchases**, and confirm it unlocks again. That second half is the only real test of FR-15.
6. **Ask to Buy.** Enable it for the sandbox account and confirm the sheet shows "This purchase is waiting for approval." and the language stays locked.
7. **Known trap to record:** sandbox does *not* reproduce the iOS 26.x `currentEntitlements`-empty bug (Decision 4) — it is production-only. The additive-only refresh is therefore untestable before release, by design. Say so in the doc so nobody later "simplifies" it away.

- [ ] **Step 2: Run every gate**

```bash
swift test --package-path Packages/Domain && swift test --package-path Packages/Data && scripts/determinism-check.sh && swiftlint lint --strict
```

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Confirm the real test count with `xcresulttool`, not the `** TEST SUCCEEDED **` line.

- [ ] **Step 3: Update the docs**

Rewrite the "Right now" block in `docs/next-task.md` to point at Phase 13, and record what a future session should not have to rediscover — at minimum: that the additive-only refresh is deliberate and why, that restore lives on the Languages screen rather than the sheet, and whatever the `SKTestSession` resource/refund traps in Task 5 turned out to be. Mark Phase 11 done in `docs/build-plan.md`.

- [ ] **Step 4: Self-review and report tech debt**

Per CLAUDE.md, end the phase by saying plainly what was knowingly left behind. Candidates already visible from here:

- The app target still compiles in Swift 5 mode, so `StoreKitPurchaseService`'s concurrency is not checked as strictly as `Packages/` is.
- The additive-only refresh cannot be exercised in sandbox.
- Family Sharing stays off (spec: out of scope, and it carries the same iOS 26.x regression).
- Whatever `revocationRelocks` ended up asserting, if Task 5's fallback was used.

- [ ] **Step 5: Commit and open the PR**

```bash
git add docs/ && git commit -m "docs: record Phase 11 and the App Store Connect setup"
```

---

## Self-review

**Spec coverage.** Decision 1 → Tasks 1, 2, 5. Decision 2 → Task 1. Decision 3 → Tasks 2, 3. Decision 4 → Tasks 4 (revocation clears the active language) and 5 (additive refresh). Decision 5 → Task 6. Decision 6 → Tasks 2, 3, 4, 6 (the strings table). Testing section → Tasks 2, 3, 5, 7. Doc deliverable → Task 8. Decision 0 is withdrawn and needs no task.

**Placeholders.** None. Two places name a fallback instead of a single answer — the `SKTestSession` resource lookup and the refund-delivery test in Task 5 — because both depend on runtime behaviour that cannot be settled by reading. Each says exactly what to do in either case and to report which one shipped.

**Type consistency.** `PurchaseOutcome` (Task 1) is what `FakePurchaseService` returns (Task 2), what `buy()` switches over (Task 3), and what the adapter produces (Task 5). `ProductIdentifier.forLanguage` is used in Tasks 5 and 6 with the signature Task 1 defines. `PurchaseViewModel.lastKnownPrice` is added in Task 6, where its only consumer is.
