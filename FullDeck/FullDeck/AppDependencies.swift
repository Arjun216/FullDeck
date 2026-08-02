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
    let purchases: PurchaseService
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
    /// The defaults keep the integration tests off the store: `make` on its own
    /// must never reach StoreKit.
    static func make(
        packsDirectory: URL, inMemory: Bool,
        entitlements: EntitlementStore = NoPurchasesEntitlementStore(),
        purchases: PurchaseService = NoPurchasesService()
    ) throws -> AppDependencies {
        let container = try SwiftDataReviewStore.makeContainer(inMemory: inMemory)
        return AppDependencies(
            packStore: JSONPackStore(packsDirectory: packsDirectory),
            reviewStore: SwiftDataReviewStore(modelContainer: container),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: entitlements,
            purchases: purchases)
    }

    /// Xcode sets this in the host process for *unit* tests only. A UI test
    /// launches the app as a separate process without it, which is exactly the
    /// distinction `live()` needs.
    private static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Throws rather than crashes: opening the SwiftData store can fail on a full
    /// or corrupt disk, and NFR-10 forbids a crash on bad data.
    static func live() throws -> AppDependencies {
        // One object behind both ports, so there is exactly one entitlement
        // cache rather than two that can disagree.
        let store = StoreKitPurchaseService()
        // Unit tests are hosted *inside* this app process, so without this guard
        // the app's own `Transaction.updates` listener runs alongside the
        // `SKTestSession` a test creates: two entitlement caches, and two
        // `finish()` calls racing for every transaction the test buys. UI tests
        // launch the app for real and never set this variable, so they still get
        // the listener they are there to exercise.
        if !isHostingUnitTests { store.start() }
        return try make(
            packsDirectory: bundledPacksDirectory, inMemory: false,
            entitlements: store, purchases: store)
    }
}
