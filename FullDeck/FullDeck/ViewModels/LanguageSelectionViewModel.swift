import Domain
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

    init(packStore: PackStore, entitlements: EntitlementStore) {
        self.packStore = packStore
        self.entitlements = entitlements
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
        } catch {
            state = .failed("Couldn't load the available languages.")
        }
    }

    /// FR-1: selecting a locked pack must not start a session.
    func select(_ option: Option) {
        guard option.isUnlocked else { return }
        activeLanguage = option.descriptor.languageCode
    }
}
