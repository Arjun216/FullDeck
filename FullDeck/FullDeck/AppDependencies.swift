import Data
import Domain
import Foundation

/// The composition root's output: every concrete dependency, constructed once and
/// handed down through initializers. No singletons, no DI framework (ADR-002) —
/// this struct *is* the wiring. It is also the only type in the app that knows
/// the `Data` package exists.
@MainActor
struct AppDependencies {
    let packStore: PackStore
    let reviewStore: ReviewStore
    let speech: SpeechService
    let clock: DayClock
    let entitlements: EntitlementStore
    let scheduler = Scheduler()
    let sessionBuilder = SessionBuilder()

    /// Where Task 6's bundled `manifest.json` + `fr.pack.json` live at runtime.
    /// The bundle root, not a `packs/` subdirectory — Xcode's synchronized-group
    /// resource copy flattens loose files rather than preserving the source
    /// folder structure (confirmed by inspecting the built .app).
    static var bundledPacksDirectory: URL {
        Bundle.main.resourceURL ?? URL(fileURLWithPath: Bundle.main.bundlePath)
    }

    /// The seam integration tests use: same wiring as `live()`, but pointed at a
    /// temp packs directory and an in-memory store.
    static func make(packsDirectory: URL, inMemory: Bool) throws -> AppDependencies {
        let container = try SwiftDataReviewStore.makeContainer(inMemory: inMemory)
        return AppDependencies(
            packStore: JSONPackStore(packsDirectory: packsDirectory),
            reviewStore: SwiftDataReviewStore(modelContainer: container),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: NoPurchasesEntitlementStore())
    }

    /// Throws rather than crashes: opening the SwiftData store can fail on a full
    /// or corrupt disk, and NFR-10 forbids a crash on bad data.
    static func live() throws -> AppDependencies {
        try make(packsDirectory: bundledPacksDirectory, inMemory: false)
    }
}
