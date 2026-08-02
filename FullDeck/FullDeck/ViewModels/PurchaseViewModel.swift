import Domain
import Foundation
import Observation

/// The purchase state machine (spec Decision 3). Knows nothing about StoreKit —
/// it talks to `PurchaseService`, which is why every transition below is testable
/// against a fake in milliseconds with no simulator and no network.
///
/// Separate from `LanguageSelectionViewModel` on purpose: folding six states,
/// price fetching and restore into that ~70-line type would give it two unrelated
/// jobs, and every purchase test would then need packs, a manifest and
/// `UserDefaults` set up before reaching its assertion.
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

    /// Set once a purchase lands, so the Languages screen knows to reload and
    /// drop the padlock.
    private(set) var didUnlock = false

    let languageCode: LanguageCode
    let displayName: String

    private let purchases: PurchaseService
    /// Held apart from `state` so a retry out of `.failed` still knows the price
    /// without refetching it.
    private var price: String?

    init(languageCode: LanguageCode, displayName: String, purchases: PurchaseService) {
        self.languageCode = languageCode
        self.displayName = displayName
        self.purchases = purchases
    }

    /// Read-only so the sheet can offer a retry out of `.failed` without the
    /// price having to live in every state that might precede one.
    var lastKnownPrice: String? { price }

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

    func buy() async {
        guard let price else { return }
        state = .purchasing
        do {
            switch try await purchases.purchase(languageCode) {
            case .purchased:
                didUnlock = true
                state = .purchased
            case .cancelled:
                // Cancelling is a decision, not a failure. Anything that reads
                // as an error here is the app scolding someone for changing
                // their mind.
                state = .ready(price: price)
            case .pending:
                // Neither complete nor failed: a family organiser has to approve
                // it, and the entitlement arrives later through
                // Transaction.updates -- possibly after a relaunch.
                state = .pending
            }
        } catch {
            state = .failed(
                String(localized: "Couldn't complete the purchase. You haven't been charged."))
        }
    }
}
