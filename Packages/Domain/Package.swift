// swift-tools-version: 6.0
import PackageDescription

// The Domain package: the product's "brain" in pure Swift.
// Zero dependencies by design (architecture.md §1) — it imports only Foundation,
// so it is unit-testable in isolation and cannot reach into UI or persistence.
// swiftLanguageModes: [.v6] turns on Swift 6 strict concurrency for every target
// here, which is what CI's -warnings-as-errors then enforces (architecture.md §4).
let package = Package(
    name: "Domain",
    // The app's floor is iOS 17 (ADR-002 / @Observable); macOS 14 is the
    // matching-era host so `swift test` gets the same Foundation APIs.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"])
    ],
    targets: [
        .target(name: "Domain"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
    ],
    swiftLanguageModes: [.v6]
)
