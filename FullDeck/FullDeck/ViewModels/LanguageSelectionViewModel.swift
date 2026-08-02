import Domain
import Foundation
import Observation

/// Lists the bundled packs with their lock state and tracks which language is
/// active (FR-1, FR-2, FR-14). The purchase sheet itself is Phase 11.
@MainActor
@Observable
final class LanguageSelectionViewModel {
    struct Option: Equatable, Identifiable {
        let descriptor: PackDescriptor
        let isUnlocked: Bool

        var id: String { descriptor.languageCode.rawValue }
    }

    enum State: Equatable {
        case loading
        case ready([Option])
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var activeLanguage: LanguageCode?
    private(set) var restoreMessage: String?

    /// The unlocked set as of the last *successful* `load()`.
    ///
    /// Held here rather than re-derived from `state`, which answers empty for
    /// every state but `.ready` — including the `.loading` that any concurrent
    /// reload passes through. One genuinely is concurrent: the real adapter's
    /// `refreshEntitlements()` publishes an entitlement change *during*
    /// `purchases.restore()`, and the view reloads on it, so `restore()`'s
    /// before-snapshot could read empty and swallow its own message (D-1).
    private var unlockedCodes: Set<String> = []

    private let packStore: PackStore
    private let entitlements: EntitlementStore
    private let purchases: PurchaseService
    private let defaults: UserDefaults
    private static let activeLanguageKey = "activeLanguageCode"

    init(
        packStore: PackStore, entitlements: EntitlementStore, purchases: PurchaseService,
        defaults: UserDefaults = .standard
    ) {
        self.packStore = packStore
        self.entitlements = entitlements
        self.purchases = purchases
        self.defaults = defaults
    }

    func load() async {
        state = .loading
        do {
            let descriptors = try await packStore.availablePacks()
            let options = descriptors.map { descriptor in
                Option(
                    descriptor: descriptor,
                    isUnlocked: descriptor.unlockedByDefault
                        || entitlements.isUnlocked(descriptor.languageCode))
            }
            unlockedCodes = Set(options.filter(\.isUnlocked).map(\.id))
            state = .ready(options)
            // Honored only if the pack is still listed: a pack removed between
            // launches must not leave the app pointing at nothing (FR-9).
            if activeLanguage == nil,
                let saved = defaults.string(forKey: Self.activeLanguageKey),
                descriptors.contains(where: { $0.languageCode.rawValue == saved }) {
                activeLanguage = LanguageCode(saved)
            }
            // A revoked language must not stay active (spec Decision 4). Review
            // history on disk is deliberately untouched — a re-purchase gets
            // their progress back intact, and destroying it over a billing event
            // would be unrecoverable if the refund turned out to be a mistake.
            if let active = activeLanguage, !isUnlocked(active, in: descriptors) {
                activeLanguage = nil
                defaults.removeObject(forKey: Self.activeLanguageKey)
            }
        } catch let error as PackLoadError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(String(localized: "Couldn't load the available languages."))
        }
    }

    /// FR-15. A restore that worked speaks through the rows unlocking, so this
    /// stays nil unless there is genuinely something to say.
    func restore() async {
        restoreMessage = nil
        let before = unlockedCodes
        do {
            try await purchases.restore()
        } catch {
            restoreMessage = String(localized: "Couldn't restore your purchases.")
            return
        }
        await load()
        // Comparing the unlocked set before and after is how the screen knows
        // whether anything came back, without `PurchaseService` having to report
        // per-language ownership it would only ever use here. A reload that
        // failed has nothing to say about purchases — the error state is already
        // on screen, and a second alert over it would only add noise.
        guard case .ready = state else { return }
        if unlockedCodes == before {
            restoreMessage = String(localized: "No previous purchases found.")
        }
    }

    func clearRestoreMessage() { restoreMessage = nil }

    private func isUnlocked(_ code: LanguageCode, in descriptors: [PackDescriptor]) -> Bool {
        descriptors.contains {
            $0.languageCode == code
                && ($0.unlockedByDefault || entitlements.isUnlocked($0.languageCode))
        }
    }

    /// FR-1: selecting a locked pack must not start a session.
    func select(_ option: Option) {
        guard option.isUnlocked else { return }
        activeLanguage = option.descriptor.languageCode
        defaults.set(option.descriptor.languageCode.rawValue, forKey: Self.activeLanguageKey)
    }
}
