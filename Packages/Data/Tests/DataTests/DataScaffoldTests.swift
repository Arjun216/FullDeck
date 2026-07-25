import Testing

@testable import Data

@Test("Phase-4 scaffold: Data layer can import and call into Domain")
func dataScaffoldSeesDomain() {
    #expect(DataScaffold.scaffoldMarker() == "data-sees-4-grades")
}
