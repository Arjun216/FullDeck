import Foundation
import SwiftData

/// SwiftData storage for review state (ADR-001). Never crosses the `ReviewStore`
/// port — `SwiftDataReviewStore` maps to/from the pure `Domain.ReviewState`.
@Model
final class PersistentReviewState {
    @Attribute(.unique) var wordID: String
    /// Denormalized from `wordID`'s prefix so `#Predicate` can filter by
    /// language directly, without string-prefix matching in the query.
    var languageCode: String
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var nextReviewDate: Date
    var firstReviewedDate: Date?
    var learnedDate: Date?

    init(
        wordID: String, languageCode: String, easeFactor: Double, intervalDays: Int,
        repetitions: Int, nextReviewDate: Date, firstReviewedDate: Date?, learnedDate: Date?
    ) {
        self.wordID = wordID
        self.languageCode = languageCode
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
        self.firstReviewedDate = firstReviewedDate
        self.learnedDate = learnedDate
    }
}
