import Foundation

public struct ProgressSummary: Equatable, Sendable {
    public let wordsLearned: Int
    public let wordsInProgress: Int
    public let totalReviewed: Int

    public init(wordsLearned: Int, wordsInProgress: Int, totalReviewed: Int) {
        self.wordsLearned = wordsLearned
        self.wordsInProgress = wordsInProgress
        self.totalReviewed = totalReviewed
    }
}

extension ProgressSummary {
    /// Classifies a set of review states into learned/in-progress/total, purely
    /// from their milestone dates (`learnedDate`/`firstReviewedDate`).
    public init(states: [ReviewState]) {
        let learned = states.filter { $0.learnedDate != nil }.count
        let inProgress = states.filter { $0.firstReviewedDate != nil && $0.learnedDate == nil }
            .count
        self.init(
            wordsLearned: learned, wordsInProgress: inProgress,
            totalReviewed: learned + inProgress)
    }
}

/// Read-only bundled content. Adapter: `JSONPackStore` (Phase 7, JSON+Codable, ADR-004).
public protocol PackStore: Sendable {
    func availablePacks() async throws -> [PackDescriptor]
    func loadPack(_ languageCode: LanguageCode) async throws -> LanguagePack
}

/// Mutable per-user state. Adapter: `SwiftDataReviewStore` (Phase 7, ADR-001).
public protocol ReviewStore: Sendable {
    func reviewState(for word: WordID) async throws -> ReviewState?
    func save(_ state: ReviewState) async throws
    /// Ordering guarantee: sorted by `wordID.rawValue`, ascending.
    func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState]
    func progress(_ languageCode: LanguageCode) async throws -> ProgressSummary
}

/// Typed errors `PackStore` implementations throw — never a crash on bad or
/// missing data (NFR-10).
public enum PackLoadError: Error, Equatable, Sendable {
    case fileNotFound(languageCode: LanguageCode)
    case malformedJSON(String)
    /// Fail-closed per schema §9: a pack newer than the loader supports.
    case unsupportedSchemaVersion(found: Int, maxSupported: Int)
    /// `rule` carries the VR id (`"VR-3"`), matching the convention
    /// `fixtures/invalid/expected.json` already uses.
    case validationFailed(rule: String, reason: String)
}

/// Injectable "today" so ViewModels never read the wall clock (NFR: deterministic
/// tests). Day-granular by design — the scheduler only ever needs the date.
///
/// Named `DayClock`, not `Clock` as `architecture.md` §3 sketched it: Swift's
/// concurrency library already exports a `Clock` protocol, and the collision
/// would force `Domain.Clock` at every app-target use site.
public protocol DayClock: Sendable {
    var today: Date { get }
}

/// Is a language purchased/unlocked (FR-14)? Synchronous — it is a local lookup,
/// and Phase 11's StoreKit adapter caches its entitlement set behind this same
/// signature. The Phase 8 stub lives in the app target and always returns false;
/// the free launch language is `PackDescriptor.unlockedByDefault`, not an
/// entitlement.
public protocol EntitlementStore: Sendable {
    func isUnlocked(_ languageCode: LanguageCode) -> Bool
}
