import Domain
import Foundation

/// What the purchase state machine needs from the store (FR-14, FR-15).
///
/// Presentation owns this port and it lives beside its adapter — the precedent
/// `SpeechService` set in Phase 8. Domain never learns that buying exists: it
/// needs `isUnlocked`, which `EntitlementStore` already gives it, and adding a
/// purchase port to Domain would widen its surface for no domain consumer.
/// `nonisolated` because the app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, which would otherwise pin this port to the main actor. Nothing
/// here needs it — the StoreKit adapter's cache is lock-backed, and its
/// `Transaction.updates` loop has no business running on main.
nonisolated protocol PurchaseService: Sendable {
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
///
/// `nonisolated` because the app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, which would otherwise main-actor-isolate even this enum's
/// synthesized `Equatable` — and the StoreKit adapter compares outcomes off the
/// main actor. The same applies to the other types in this file.
nonisolated enum PurchaseOutcome: Equatable {
    case purchased
    case cancelled
    case pending
}

nonisolated enum PurchaseFailure: Error, Equatable {
    case productUnavailable
    /// `VerificationResult.unverified`. Treated as a failure, never as success.
    case unverified
    case storeError
}

nonisolated enum ProductIdentifier {
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
/// `NoPurchasesEntitlementStore` lives in `StubEntitlementStore.swift`.
nonisolated struct NoPurchasesService: PurchaseService {
    var entitlementChanges: AsyncStream<Void> { AsyncStream { $0.finish() } }
    func price(for languageCode: LanguageCode) async throws -> String? { nil }
    func purchase(_ languageCode: LanguageCode) async throws -> PurchaseOutcome {
        throw PurchaseFailure.productUnavailable
    }
    func restore() async throws {}
}
