import Domain
import Foundation
import SwiftData

@ModelActor
public actor SwiftDataReviewStore: ReviewStore {
    public func reviewState(for word: WordID) async throws -> ReviewState? {
        let wordID = word.rawValue
        let descriptor = FetchDescriptor<PersistentReviewState>(
            predicate: #Predicate { $0.wordID == wordID })
        return try modelContext.fetch(descriptor).first.map(Self.toDomain)
    }

    public func save(_ state: ReviewState) async throws {
        let wordID = state.wordID.rawValue
        let descriptor = FetchDescriptor<PersistentReviewState>(
            predicate: #Predicate { $0.wordID == wordID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.easeFactor = state.easeFactor
            existing.intervalDays = state.intervalDays
            existing.repetitions = state.repetitions
            existing.nextReviewDate = state.nextReviewDate
            existing.firstReviewedDate = state.firstReviewedDate
            existing.learnedDate = state.learnedDate
        } else {
            modelContext.insert(Self.toPersistent(state))
        }
        try modelContext.save()
    }

    public func allStates(_ languageCode: LanguageCode) async throws -> [ReviewState] {
        let code = languageCode.rawValue
        let descriptor = FetchDescriptor<PersistentReviewState>(
            predicate: #Predicate { $0.languageCode == code },
            sortBy: [SortDescriptor(\.wordID)])
        return try modelContext.fetch(descriptor).map(Self.toDomain)
    }

    private static func toDomain(_ persisted: PersistentReviewState) -> ReviewState {
        ReviewState(
            wordID: WordID(persisted.wordID),
            easeFactor: persisted.easeFactor,
            intervalDays: persisted.intervalDays,
            repetitions: persisted.repetitions,
            nextReviewDate: persisted.nextReviewDate,
            firstReviewedDate: persisted.firstReviewedDate,
            learnedDate: persisted.learnedDate)
    }

    private static func toPersistent(_ state: ReviewState) -> PersistentReviewState {
        PersistentReviewState(
            wordID: state.wordID.rawValue,
            languageCode: state.wordID.languageCode.rawValue,
            easeFactor: state.easeFactor,
            intervalDays: state.intervalDays,
            repetitions: state.repetitions,
            nextReviewDate: state.nextReviewDate,
            firstReviewedDate: state.firstReviewedDate,
            learnedDate: state.learnedDate)
    }
}

extension SwiftDataReviewStore {
    /// Builds the `ModelContainer` for this store's schema. `PersistentReviewState`
    /// never crosses the `ReviewStore` port (architecture.md §1) and stays
    /// internal to this package — this factory is the one door a composition
    /// root outside `Data` needs to open a container for it.
    public static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: PersistentReviewState.self, configurations: configuration)
    }
}
