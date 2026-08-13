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
    let notifications: NotificationScheduler
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
        purchases: PurchaseService = NoPurchasesService(),
        notifications: NotificationScheduler = NoNotificationScheduler()
    ) throws -> AppDependencies {
        let container = try SwiftDataReviewStore.makeContainer(inMemory: inMemory)
        return AppDependencies(
            packStore: JSONPackStore(packsDirectory: packsDirectory),
            reviewStore: SwiftDataReviewStore(modelContainer: container),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: entitlements,
            purchases: purchases,
            notifications: notifications)
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

        /// Selects `unreadablePackFixture()`. Same guarding as its sibling.
        static let unreadablePackFixtureArgument = "-uiTestUnreadablePack"

        /// Selects `freshSessionFixture()`. Same guarding again.
        static let freshSessionFixtureArgument = "-uiTestFreshSession"

        /// A guaranteed full study session, in memory (C-8).
        ///
        /// The UI tests share one on-disk store — across methods *and across
        /// runs on the same machine* — so "is there a card on the Study screen"
        /// depends on how much that simulator has already been studied. Two
        /// Phase 13 tests that assume a card failed for exactly that reason
        /// after the performance suite had spent the day's session, and the
        /// failure reads as a broken app rather than as an exhausted fixture.
        ///
        /// Twenty words and no review state, so every launch offers a full
        /// session and nothing carries over. Any test whose subject is *the
        /// card* rather than *persistence* should use this.
        private static func freshSessionFixture() -> AppDependencies? {
            guard ProcessInfo.processInfo.arguments.contains(freshSessionFixtureArgument)
            else { return nil }

            let code = LanguageCode("fr")
            let words = (1...20).map { rank in
                WordEntry(
                    id: WordID("fr:mot\(rank):NOUN"), lemma: "mot\(rank)",
                    display: "mot\(rank)", pos: .noun, rank: rank, register: .neutral,
                    isFunctionWord: false, gloss: "word \(rank)",
                    example: "Voici le mot\(rank).", aliases: [])
            }
            let pack = LanguagePack(
                schemaVersion: 1, packVersion: "1.0.0", languageCode: code,
                languageName: "Français", baseLanguage: "en", wordCount: words.count,
                source: PackSource(
                    name: "wordfreq", license: "CC-BY-SA 4.0",
                    attribution: "wordfreq contributors"),
                words: words)

            return AppDependencies(
                packStore: InMemoryPackStore(
                    descriptors: [
                        PackDescriptor(
                            languageCode: code, displayName: "Français",
                            filename: "fr.pack.json", unlockedByDefault: true)
                    ],
                    packs: [code: pack]),
                // Empty, and in memory: nothing this test does outlives it.
                reviewStore: InMemoryReviewStore(),
                speech: AVSpeechService(), clock: SystemDayClock(),
                entitlements: NoPurchasesEntitlementStore(), purchases: NoPurchasesService(),
                notifications: NoNotificationScheduler())
        }

        /// NFR-10's failure path, made reachable (Phase 13's edge-case matrix).
        ///
        /// The bundled packs are valid, so no sequence of taps reaches
        /// `ErrorStateView` — the coverage review found it at **0%**, meaning the
        /// screen the app shows when content is broken had never been rendered,
        /// let alone audited. A corrupt file on a real device is not something a
        /// test can arrange, so the store is arranged instead: the language is
        /// listed, and loading it fails.
        ///
        /// `availablePacks()` deliberately still succeeds. An `errorOverride`
        /// would fail that too, and then the learner never gets past "Choose a
        /// language" — which exercises a different screen than the one this is
        /// for.
        private static func unreadablePackFixture() -> AppDependencies? {
            guard ProcessInfo.processInfo.arguments.contains(unreadablePackFixtureArgument)
            else { return nil }

            let code = LanguageCode("fr")
            return AppDependencies(
                packStore: InMemoryPackStore(
                    descriptors: [
                        PackDescriptor(
                            languageCode: code, displayName: "Français",
                            filename: "fr.pack.json", unlockedByDefault: true)
                    ],
                    // No pack behind the descriptor, so `loadPack` throws
                    // `.fileNotFound` — the same typed error a deleted or
                    // unreadable file produces in `JSONPackStore`.
                    packs: [:]),
                reviewStore: InMemoryReviewStore(),
                speech: AVSpeechService(), clock: SystemDayClock(),
                entitlements: NoPurchasesEntitlementStore(), purchases: NoPurchasesService(),
                notifications: NoNotificationScheduler())
        }

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
                entitlements: NoPurchasesEntitlementStore(), purchases: NoPurchasesService(),
                notifications: NoNotificationScheduler())
        }
    #endif

    static func live() throws -> AppDependencies {
        #if DEBUG
            if let fixture = allWordsLearnedFixture() { return fixture }
            if let fixture = unreadablePackFixture() { return fixture }
            if let fixture = freshSessionFixture() { return fixture }
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
            entitlements: store, purchases: store,
            notifications: UNNotificationScheduler())
    }
}
