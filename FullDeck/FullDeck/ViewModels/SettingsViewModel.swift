import Domain
import Foundation
import Observation

/// Owns the two things the learner can change: the daily reminder (FR-13) and
/// the new-word cap (FR-4).
///
/// Separate from `CreditsViewModel` on purpose: credits is failable async pack
/// I/O, this is preferences. Folding them together would make every reminder
/// test set up packs and a manifest before reaching its assertion — the same
/// argument `PurchaseViewModel` makes for staying out of
/// `LanguageSelectionViewModel`.
@MainActor
@Observable
final class SettingsViewModel {
    static let newWordsPerDayKey = "newWordsPerDay"
    /// 1000 words at 30/day is a bit over a month; at 1/day it is most of three
    /// years. Both ends are defensible, and the Stepper clamps to them.
    static let capRange = 1...30

    private let defaults: UserDefaults
    private var storedCap: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.newWordsPerDayKey)
        // `integer(forKey:)` answers 0 for a key that was never written, which is
        // outside the range — so absent and "set to zero" are the same thing here,
        // and both mean "use the default".
        storedCap = stored == 0 ? SessionBuilder.defaultNewWordCap : Self.clamp(stored)
    }

    /// FR-4. Clamped on write, so a hand-edited or stale defaults value cannot
    /// put the session builder outside its range.
    var newWordsPerDay: Int {
        get { storedCap }
        set {
            storedCap = Self.clamp(newValue)
            defaults.set(storedCap, forKey: Self.newWordsPerDayKey)
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, capRange.lowerBound), capRange.upperBound)
    }
}
