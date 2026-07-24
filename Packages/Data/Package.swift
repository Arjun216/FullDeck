// swift-tools-version: 6.0
import PackageDescription

// The Data package: concrete persistence (JSON language packs + SwiftData review
// state) that implements the Domain ports. It depends on Domain — dependencies
// point inward only (architecture.md §1). The local `.package(path:)` below is
// what wires that dependency; Domain has no idea Data exists.
let package = Package(
    name: "Data",
    products: [
        .library(name: "Data", targets: ["Data"])
    ],
    dependencies: [
        .package(path: "../Domain")
    ],
    targets: [
        .target(
            name: "Data",
            dependencies: [.product(name: "Domain", package: "Domain")]
        ),
        .testTarget(name: "DataTests", dependencies: ["Data"]),
    ],
    swiftLanguageModes: [.v6]
)
