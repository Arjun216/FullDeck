import Domain
import Foundation

/// Phase 8 stub: nothing is purchased yet, so the only unlocked language is the
/// one the manifest marks `unlockedByDefault` (FR-2). Phase 11 replaces this with
/// the StoreKit-backed implementation — no caller changes.
struct NoPurchasesEntitlementStore: EntitlementStore {
    func isUnlocked(_ languageCode: LanguageCode) -> Bool { false }
}

/// The one place the app reads the wall clock. Everything downstream takes
/// `today` as data, which is what keeps the scheduler and session assembly
/// deterministic under test.
struct SystemDayClock: DayClock {
    var today: Date { Date() }
}
