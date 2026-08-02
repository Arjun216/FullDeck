import Domain
import Foundation
import StoreKit
import os

/// The **only** file in the app that imports StoreKit (spec Decision 1).
///
/// Conforms to both `PurchaseService` and Domain's `EntitlementStore` on purpose:
/// entitlements and purchases are the same underlying StoreKit state, and
/// splitting them across two adapters would mean two caches that can disagree
/// about whether someone owns a language.
///
/// `isUnlocked` has to stay synchronous — Domain's port says so, and every caller
/// is a view building a row. StoreKit is async, so the entitlement set lives
/// behind a lock: reads are synchronous, writes arrive from the launch refresh
/// and the `Transaction.updates` listener. `OSAllocatedUnfairLock` rather than
/// `NSLock` because it is generic over its state and genuinely `Sendable`, so
/// this type needs no `@unchecked`.
nonisolated final class StoreKitPurchaseService: PurchaseService, EntitlementStore {
    private let unlocked = OSAllocatedUnfairLock(initialState: Set<LanguageCode>())
    private let continuation: AsyncStream<Set<LanguageCode>>.Continuation
    let entitlementChanges: AsyncStream<Set<LanguageCode>>

    /// Held for the process lifetime and never cancelled: a purchase can complete
    /// while the app is backgrounded, and this is what delivers it afterwards.
    private let listener = OSAllocatedUnfairLock(initialState: Task<Void, Never>?.none)

    init() {
        (entitlementChanges, continuation) = AsyncStream.makeStream()
    }

    deinit {
        listener.withLock { $0?.cancel() }
        continuation.finish()
    }

    /// Called once from the composition root.
    func start() {
        let task = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.apply(result)
            }
        }
        listener.withLock { existing in
            existing?.cancel()
            existing = task
        }
        Task { [weak self] in await self?.refreshEntitlements() }
    }

    // MARK: - EntitlementStore

    func isUnlocked(_ languageCode: LanguageCode) -> Bool {
        unlocked.withLock { $0.contains(languageCode) }
    }

    /// Every yield carries the whole set, so a waiter can wait for the state it
    /// wants rather than for "something changed" — see the port's doc comment.
    private func publish() {
        continuation.yield(unlocked.withLock { $0 })
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
            unlocked.withLock { _ = $0.insert(code) }
        }
        publish()
    }

    private func apply(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await record(transaction)
    }

    /// The one place a language enters or leaves the cache. A non-nil
    /// `revocationDate` is the *only* signal that removes one.
    private func record(_ transaction: StoreKit.Transaction) async {
        defer { publish() }
        await transaction.finish()
        guard let code = ProductIdentifier.languageCode(from: transaction.productID) else {
            return  // Someone else's product on the same account.
        }
        unlocked.withLock {
            if transaction.revocationDate == nil {
                _ = $0.insert(code)
            } else {
                _ = $0.remove(code)
            }
        }
    }

    private func product(for languageCode: LanguageCode) async throws -> Product? {
        try await Product.products(for: [ProductIdentifier.forLanguage(languageCode)]).first
    }
}
