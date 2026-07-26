import Foundation
import Testing

@Test("Fixtures.root resolves to the repo-root fixtures directory")
func fixturesRootResolvesCorrectly() {
    let fileManager = FileManager.default

    #expect(fileManager.fileExists(atPath: Fixtures.url("fr-mini.pack.json").path))
    var isDirectory: ObjCBool = false
    #expect(
        fileManager.fileExists(
            atPath: Fixtures.root.appendingPathComponent("invalid").path,
            isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}
