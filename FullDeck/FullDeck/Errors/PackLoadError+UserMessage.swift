import Domain
import Foundation

/// Phase 10, NFR-10 + build-plan #2: per-case error copy, not one blanket
/// message. A schema mismatch means the *app* is stale; everything else means
/// the bundled pack data itself can't be read — the learner can't tell "not
/// found" from "malformed" apart, so those three share one message.
extension PackLoadError {
    var userMessage: String {
        switch self {
        case .unsupportedSchemaVersion:
            String(localized: "This language needs an app update.")
        case .fileNotFound, .malformedJSON, .validationFailed:
            String(
                localized: "This language's data couldn't be read. Try reinstalling the app.")
        }
    }
}
