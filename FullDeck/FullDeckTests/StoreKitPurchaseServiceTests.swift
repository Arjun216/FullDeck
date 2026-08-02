import Domain
import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import FullDeck

/// Only there to name the test bundle for `Bundle(for:)`.
private final class BundleMarker {}

/// Is there a working StoreKit test environment in this process?
///
/// **The answer, settled 2026-08-02: it is the runtime.** On an **iOS 18.5**
/// simulator this suite runs against a real store and five of its six tests
/// pass. On **iOS 26.5** every `SKTestSession` call fails with
/// `SKInternalErrorDomain Code=3` — "Error saving configuration file" — so the
/// store stays empty, `price` returns nil and `purchase` throws
/// `.productUnavailable`. Same code, same `.storekit` file, same command.
///
/// Getting here took three wrong turns worth not repeating:
///
/// 1. **The old guard queried before any session existed.** `.enabled` is a
///    trait, evaluated before the suite's `init()` — and `init()` is where the
///    session is created. So it could only pass via the scheme, and it skipped
///    in the Xcode IDE for the same reason it skipped from the CLI, which made
///    an IDE run look like evidence when it was not. It now builds a session
///    first and holds it past the `await`.
/// 2. **The `.storekit` file was schema version 4**, hand-written from a public
///    example. Xcode 26 writes version 5. Regenerating it changed nothing, but
///    the committed file is now Xcode's own output.
/// 3. **The scheme's `StoreKitConfigurationFileReference` had one `../` too
///    many** and had never resolved since Phase 11. Fixing it changed nothing
///    here — `SKTestSession(contentsOf:)` loads the file by URL out of the test
///    bundle and never consults the scheme — but it is what the *app* uses when
///    you ⌘R with a test store, so it was genuinely broken.
///
/// Two of the six pass even against a dead store, because both assert on
/// *absence*. Don't read those greens as coverage.
///
/// The suite skips rather than fails when the environment is dead, on the same
/// principle as the pipeline's UDPipe tests skipping without their model: an
/// absent environment is not a broken adapter. To see the underlying errors
/// instead of a skip, comment out the `.enabled` argument below.
private func storeKitTestEnvironmentIsAvailable() async -> Bool {
    guard
        let url = Bundle(for: BundleMarker.self).url(
            forResource: "FullDeck", withExtension: "storekit"),
        let session = try? SKTestSession(contentsOf: url)
    else { return false }
    let id = ProductIdentifier.forLanguage(LanguageCode("hi"))
    let products = try? await Product.products(for: [id])
    // Touch `session` *after* the await so ARC cannot release it mid-query —
    // a released session tears the store down and the probe answers its own
    // question wrong.
    session.disableDialogs = true
    return !(products ?? []).isEmpty
}

/// Framework glue, so these are written alongside the adapter rather than before
/// it — an integration test against `SKTestSession` is the honest test here.
///
/// `.serialized` because `SKTestSession` is process-wide state: two of these
/// running at once would see each other's transactions.
///
/// To see a real failure instead of a skip — the only way to learn *why* the
/// store is empty — comment out the `.enabled` argument below. Expect
/// `.productUnavailable` / `.notEntitled` while the environment is inert.
@Suite(
    "StoreKit adapter", .serialized,
    .enabled("no StoreKit test environment in this process — see the note above") {
        await storeKitTestEnvironmentIsAvailable()
    })
struct StoreKitPurchaseServiceTests {
    let hindi = LanguageCode("hi")

    /// A stored property, not a local in each test. `SKTestSession` configures
    /// the process's StoreKit environment only for as long as it is alive, and
    /// `_ = try makeSession()` releases it immediately — after which
    /// `Product.products(for:)` returns nothing and every test fails as
    /// `.productUnavailable`, with the real reason nowhere in the failure.
    /// Swift Testing builds a fresh suite instance per test, so this is also
    /// how each test gets a clean store.
    let session: SKTestSession

    init() throws {
        // Not `SKTestSession(configurationFileNamed:)`: that searches
        // `Bundle.main`, which for a hosted unit test is the *app* bundle, while
        // FullDeck.storekit is a resource of the test bundle.
        let url = try #require(
            Bundle(for: BundleMarker.self).url(forResource: "FullDeck", withExtension: "storekit"),
            "FullDeck.storekit is missing from the test bundle")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    @Test("FR-14 the localized price comes from StoreKit, never a literal")
    func fetchesPrice() async throws {
        let service = StoreKitPurchaseService()

        #expect(try await service.price(for: hindi) == "$0.99")
    }

    @Test("FR-14 a language with no product in the store has no price")
    func unknownLanguageHasNoPrice() async throws {
        let service = StoreKitPurchaseService()

        #expect(try await service.price(for: LanguageCode("zz")) == nil)
    }

    @Test("FR-14 buying a language unlocks it")
    func purchaseUnlocks() async throws {
        let service = StoreKitPurchaseService()
        #expect(!service.isUnlocked(hindi))

        #expect(try await service.purchase(hindi) == .purchased)

        #expect(service.isUnlocked(hindi))
    }

    @Test("FR-15 a purchase made before this install is restored")
    func restoreFindsAPastPurchase() async throws {
        // Bought on another device, or on a previous install of this one.
        _ = try await session.buyProduct(identifier: ProductIdentifier.forLanguage(hindi))
        let service = StoreKitPurchaseService()

        try await service.restore()

        #expect(service.isUnlocked(hindi))
    }

    @Test("NFR-10 a store error surfaces as a thrown failure, not a crash")
    func purchaseFailureThrows() async throws {
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        let service = StoreKitPurchaseService()

        await #expect(throws: (any Error).self) { try await service.purchase(hindi) }
        #expect(!service.isUnlocked(hindi))
    }

    @Test("FR-14 a refunded language is dropped from the entitlement cache")
    func revocationRelocks() async throws {
        let service = StoreKitPurchaseService()
        service.start()
        #expect(try await service.purchase(hindi) == .purchased)
        #expect(service.isUnlocked(hindi))

        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))

        // The revocation arrives through Transaction.updates. Wait on the change
        // stream rather than sleeping — determinism-check forbids sleeps, and a
        // sleep long enough to be reliable is a slow test besides.
        //
        // Wait for the *transition*, not for a state and not for "the next
        // event". AsyncStream buffers, and by now it holds two stale snapshots:
        // an empty one from `start()`'s launch refresh, and `{hi}` from the
        // purchase. "Next event" is the empty one, so the original assertion ran
        // before the refund — that was D-2. But "first snapshot without Hindi"
        // is *also* the empty one, because not-yet-bought and refunded look
        // identical as states. Only having seen Hindi present and then absent
        // means the revocation actually landed.
        var sawItUnlocked = false
        for await unlocked in service.entitlementChanges {
            if unlocked.contains(hindi) {
                sawItUnlocked = true
            } else if sawItUnlocked {
                break
            }
        }

        #expect(!service.isUnlocked(hindi))
    }
}
