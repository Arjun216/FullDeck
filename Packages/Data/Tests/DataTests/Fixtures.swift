import Foundation

/// Locates the shared `/fixtures` directory at the repo root from any test file,
/// via the compile-time source path — test-only file reads, so no SPM resource
/// bundling or symlinks are needed.
enum Fixtures {
    static let root: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Fixtures.swift -> DataTests/
            .deletingLastPathComponent()  // DataTests/ -> Tests/
            .deletingLastPathComponent()  // Tests/ -> Data/
            .deletingLastPathComponent()  // Data/ -> Packages/
            .deletingLastPathComponent()  // Packages/ -> repo root
            .appendingPathComponent("fixtures")
    }()

    static func url(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }
}
