import Domain
import Foundation

@testable import FullDeck

// A fixed instant on a UTC day boundary. Tests never read the wall clock
// (scripts/determinism-check.sh enforces this).
let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

/// A non-`PackLoadError` failure to inject into `InMemoryReviewStore.save(_:)`
/// — `ReviewStore` failures are opaque, unlike the finite `PackLoadError` set.
struct FakeStoreError: Error, Equatable, Sendable {}

func entry(_ lemma: String, rank: Int) -> WordEntry {
    WordEntry(
        id: WordID("fr:\(lemma):NOUN"), lemma: lemma, display: lemma, pos: .noun,
        rank: rank, register: .neutral, isFunctionWord: false, gloss: "gloss of \(lemma)",
        example: "Une phrase avec \(lemma).", aliases: [])
}

func frPack(_ entries: [WordEntry]) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode("fr"),
        languageName: "French", baseLanguage: "en", wordCount: entries.count,
        source: PackSource(
            name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors"),
        words: entries)
}

/// A `ReviewState` that has met `L` — for tests that need a pack already learned.
func learnedState(_ entry: WordEntry, on learned: Date = day(7)) -> ReviewState {
    ReviewState(
        wordID: entry.id, easeFactor: 2.5, intervalDays: 15, repetitions: 3,
        nextReviewDate: day(22), firstReviewedDate: day0, learnedDate: learned)
}

func frDescriptor(unlockedByDefault: Bool = true) -> PackDescriptor {
    PackDescriptor(
        languageCode: LanguageCode("fr"), displayName: "French", filename: "fr.pack.json",
        unlockedByDefault: unlockedByDefault)
}

struct FixedDayClock: DayClock {
    let today: Date
}

struct StubEntitlementStore: EntitlementStore {
    var unlocked: Set<String> = []

    func isUnlocked(_ languageCode: LanguageCode) -> Bool {
        unlocked.contains(languageCode.rawValue)
    }
}

@MainActor
final class FakeSpeechService: SpeechService {
    private(set) var spoken: [(text: String, language: LanguageCode)] = []
    private(set) var stopCount = 0
    var errorToThrow: SpeechError?

    func speak(_ text: String, language: LanguageCode) throws {
        if let errorToThrow { throw errorToThrow }
        spoken.append((text, language))
    }

    func stop() {
        stopCount += 1
    }
}

/// Builds a `StudyViewModel` over in-memory doubles. Every test that needs a
/// different pack, state set, or "today" passes it here rather than reaching
/// into the ViewModel.
@MainActor
func makeStudyViewModel(
    pack: LanguagePack? = frPack([entry("chat", rank: 1), entry("chien", rank: 2)]),
    today: Date = day0,
    newWordCap: Int = SessionBuilder.defaultNewWordCap,
    speech: FakeSpeechService = FakeSpeechService(),
    reviewStore: InMemoryReviewStore = InMemoryReviewStore(),
    errorOverride: PackLoadError? = nil
) -> StudyViewModel {
    let code = LanguageCode("fr")
    let packStore = InMemoryPackStore(
        descriptors: [frDescriptor()], packs: pack.map { [code: $0] } ?? [:],
        errorOverride: errorOverride)
    return StudyViewModel(
        languageCode: code, packStore: packStore, reviewStore: reviewStore,
        scheduler: Scheduler(), sessionBuilder: SessionBuilder(), speech: speech,
        clock: FixedDayClock(today: today), newWordCap: newWordCap)
}

/// Records what was asked of the store and returns whatever the test set up.
/// A class, not a struct, so a test can read `purchaseCount` after the fact.
///
/// `@unchecked Sendable` is honest here: it is mutated only from the main actor
/// inside tests, and a lock in a test double would be ceremony proving nothing.
///
/// Conforms to both ports, like `StoreKitPurchaseService` does, so a test can
/// pass one object as `purchases` *and* `entitlements` — which is what makes a
/// restore observably change what `isUnlocked` answers.
final class FakePurchaseService: PurchaseService, EntitlementStore, @unchecked Sendable {
    var priceToReturn: String? = "$0.99"
    var priceError: Error?
    var outcomeToReturn: PurchaseOutcome = .purchased
    var purchaseError: Error?
    var restoreError: Error?
    /// What a successful restore will turn up, mirroring the real adapter's
    /// cache gaining entries once `AppStore.sync()` lands.
    var unlockedAfterRestore: Set<String> = []

    private var unlocked: Set<String> = []

    private(set) var purchaseCount = 0
    private(set) var restoreCount = 0

    let entitlementChanges: AsyncStream<Void> = AsyncStream { $0.finish() }

    func price(for languageCode: LanguageCode) async throws -> String? {
        if let priceError { throw priceError }
        return priceToReturn
    }

    func purchase(_ languageCode: LanguageCode) async throws -> PurchaseOutcome {
        purchaseCount += 1
        if let purchaseError { throw purchaseError }
        return outcomeToReturn
    }

    func restore() async throws {
        restoreCount += 1
        if let restoreError { throw restoreError }
        unlocked = unlockedAfterRestore
    }

    func isUnlocked(_ languageCode: LanguageCode) -> Bool {
        unlocked.contains(languageCode.rawValue)
    }
}
