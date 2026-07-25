import Domain
import Foundation

// ponytail: Phase-4 placeholder. The real adapters — JSONPackStore and the
// SwiftData-backed ReviewStore, both conforming to Domain ports — arrive in
// Phase 7. Delete this file then. (Named DataScaffold, not `Data`, to avoid
// shadowing Foundation.Data.)
public enum DataScaffold {
    /// Proves the Data layer can see and call into Domain at compile time —
    /// i.e. the inward Domain→Data dependency is wired correctly.
    public static func scaffoldMarker() -> String {
        "data-sees-\(Grade.allCases.count)-grades"
    }
}
