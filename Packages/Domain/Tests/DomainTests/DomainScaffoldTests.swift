import Testing

@testable import Domain

// Swift Testing (ADR-003): @Test marks a test function; #expect is the assertion.
// This is a scaffolding smoke test — no requirement ID yet because the real
// FR-backed tests begin in Phase 5.
@Test("Phase-4 scaffold: Domain module builds and is importable")
func domainScaffoldImportable() {
    #expect(DomainScaffold.scaffoldMarker() == "phase-4-scaffold")
}
