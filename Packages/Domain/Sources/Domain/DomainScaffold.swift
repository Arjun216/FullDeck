import Foundation

// ponytail: Phase-4 placeholder so the package builds and its test target has
// something to cover. The real Domain types — Scheduler, SessionBuilder, the
// models, and the ports (PackStore / ReviewStore / Clock / EntitlementStore) —
// arrive in Phase 5. Delete this file then.
public enum DomainScaffold {
    /// Proves the Domain module compiles and is importable during scaffolding.
    public static func scaffoldMarker() -> String { "phase-4-scaffold" }
}
