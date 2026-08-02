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
/// **Xcode 26 regression:** `xcodebuild test` from the command line never pushes
/// the scheme's `StoreKitConfigurationFileReference` to the simulator's
/// `storekitd`, so the whole StoreKit test facility is inert. Nothing reports
/// this: `SKTestSession(contentsOf:)` does not throw — it does not throw on
/// deliberately invalid JSON either, which is how long it took to find — every
/// product lookup simply returns empty, and `buyProduct` fails `.notEntitled`.
///
/// **The runtime is not the variable; the command line is.** This was first
/// diagnosed as iOS-26.5-specific, on reports that iOS 18 runtimes were
/// unaffected. Retested 2026-08-01 on an installed iOS 18.5 simulator
/// (`iPhone 16`): all six still skip. Running from the Xcode IDE is the only
/// known way to exercise them.
///
/// So this suite skips rather than failing, on the same principle as the
/// pipeline's UDPipe tests skipping when the 25 MB model is not downloaded: an
/// absent environment is not a broken adapter. The tests are real and they run
/// the moment the environment does.
private func storeKitTestEnvironmentIsAvailable() async -> Bool {
    let id = ProductIdentifier.forLanguage(LanguageCode("hi"))
    guard let products = try? await Product.products(for: [id]) else { return false }
    return !products.isEmpty
}

/// Framework glue, so these are written alongside the adapter rather than before
/// it — an integration test against `SKTestSession` is the honest test here.
///
/// `.serialized` because `SKTestSession` is process-wide state: two of these
/// running at once would see each other's transactions.
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
        var changes = service.entitlementChanges.makeAsyncIterator()
        await changes.next()

        #expect(!service.isUnlocked(hindi))
    }
}
