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
    #if DEBUG
        /// The launch argument that selects the fixture below. A UI test passes
        /// it; the app never sets it itself.
        static let allWordsLearnedFixtureArgument = "-uiTestAllWordsLearned"

        /// A UI-test-only wiring for a state the bundled packs cannot reach in a
        /// single run.
        ///
        /// FR-11's completion screen requires every word in the pack to have met
        /// `L` — a 14-day interval — which no amount of tapping produces against
        /// a 1000-word pack and a real clock. So the accessibility audit had
        /// never seen the product's deliberate ending, which is the screen
        /// `CLAUDE.md` says matters most (C-3). Its sibling `caughtUp` needs no
        /// fixture: grading a session to the end reaches it organically.
        ///
        /// Guarded by `#if DEBUG` *and* by a launch argument, so it cannot reach
        /// a Release build or a normal run.
        private static func allWordsLearnedFixture() -> AppDependencies? {
            guard ProcessInfo.processInfo.arguments.contains(allWordsLearnedFixtureArgument)
            else { return nil }

            let code = LanguageCode("fr")
            let word = WordEntry(
                id: WordID("fr:chat:NOUN"), lemma: "chat", display: "chat", pos: .noun,
                rank: 1, register: .neutral, isFunctionWord: false, gloss: "cat",
                example: "Le chat dort.", aliases: [])
            let pack = LanguagePack(
                schemaVersion: 1, packVersion: "1.0.0", languageCode: code,
                languageName: "Français", baseLanguage: "en", wordCount: 1,
                source: PackSource(
                    name: "wordfreq", license: "CC-BY-SA 4.0",
                    attribution: "wordfreq contributors"),
                words: [word])
            // Learned, and not due — an empty queue is what routes `showCurrentCard`
            // to `.complete` rather than to a card.
            let now = Date()
            let learned = ReviewState(
                wordID: word.id, easeFactor: 2.5, intervalDays: 21, repetitions: 4,
                nextReviewDate: now.addingTimeInterval(21 * 86_400),
                firstReviewedDate: now.addingTimeInterval(-60 * 86_400),
                learnedDate: now.addingTimeInterval(-21 * 86_400))

            return AppDependencies(
                packStore: InMemoryPackStore(
                    descriptors: [
                        PackDescriptor(
                            languageCode: code, displayName: "Français",
                            filename: "fr.pack.json", unlockedByDefault: true)
                    ],
                    packs: [code: pack]),
                reviewStore: InMemoryReviewStore(seed: [learned]),
                speech: AVSpeechService(), clock: SystemDayClock(),
                entitlements: NoPurchasesEntitlementStore(), purchases: NoPurchasesService())
        }
    #endif

    static func live() throws -> AppDependencies {
        #if DEBUG
            if let fixture = allWordsLearnedFixture() { return fixture }
        #endif
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
