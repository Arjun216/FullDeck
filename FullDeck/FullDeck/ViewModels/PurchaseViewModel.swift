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

    let languageCode: LanguageCode
    let displayName: String

    private let purchases: PurchaseService

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
        state = .ready(price: fetched)
    }
}
