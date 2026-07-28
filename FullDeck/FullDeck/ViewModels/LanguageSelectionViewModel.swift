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

    private let packStore: PackStore
    private let entitlements: EntitlementStore
    private let defaults: UserDefaults
    private static let activeLanguageKey = "activeLanguageCode"

    init(packStore: PackStore, entitlements: EntitlementStore, defaults: UserDefaults = .standard) {
        self.packStore = packStore
        self.entitlements = entitlements
        self.defaults = defaults
    }

    func load() async {
        state = .loading
        do {
            let descriptors = try await packStore.availablePacks()
            state = .ready(
                descriptors.map { descriptor in
                    Option(
                        descriptor: descriptor,
                        isUnlocked: descriptor.unlockedByDefault
                            || entitlements.isUnlocked(descriptor.languageCode))
                })
            // Honored only if the pack is still listed: a pack removed between
            // launches must not leave the app pointing at nothing (FR-9).
            if activeLanguage == nil,
                let saved = defaults.string(forKey: Self.activeLanguageKey),
                descriptors.contains(where: { $0.languageCode.rawValue == saved }) {
                activeLanguage = LanguageCode(saved)
            }
        } catch let error as PackLoadError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(String(localized: "Couldn't load the available languages."))
        }
    }

    /// FR-1: selecting a locked pack must not start a session.
    func select(_ option: Option) {
        guard option.isUnlocked else { return }
        activeLanguage = option.descriptor.languageCode
        defaults.set(option.descriptor.languageCode.rawValue, forKey: Self.activeLanguageKey)
    }
}
