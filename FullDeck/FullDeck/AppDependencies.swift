import Domain

/// The composition root's output: every concrete dependency, constructed once and
/// handed down through initializers. No singletons, no DI framework (ADR-002) —
/// this struct *is* the wiring.
@MainActor
struct AppDependencies {
    let packStore: PackStore
    let reviewStore: ReviewStore
    let speech: SpeechService
    let clock: DayClock
    let entitlements: EntitlementStore
    let scheduler = Scheduler()
    let sessionBuilder = SessionBuilder()

    // ponytail: in-memory stores seeded from SamplePack. Phase 9 swaps these two
    // lines for JSONPackStore + SwiftDataReviewStore and deletes SamplePack.
    static func live() -> AppDependencies {
        AppDependencies(
            packStore: InMemoryPackStore(
                descriptors: [SamplePack.descriptor, SamplePack.hindiDescriptor],
                packs: [LanguageCode("fr"): SamplePack.french]),
            reviewStore: InMemoryReviewStore(),
            speech: AVSpeechService(),
            clock: SystemDayClock(),
            entitlements: NoPurchasesEntitlementStore())
    }
}
