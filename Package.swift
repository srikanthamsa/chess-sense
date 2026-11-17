// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ChessSenseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChessSenseCore", targets: ["ChessSenseCore"]),
        .executable(name: "chesssense-diag", targets: ["chesssense-diag"]),
    ],
    targets: [
        .target(name: "ChessSenseCore"),
        .executableTarget(
            name: "chesssense-diag",
            dependencies: ["ChessSenseCore"],
            path: "Sources/chesssense-diag"
        ),
        .testTarget(
            name: "ChessSenseCoreTests",
            dependencies: ["ChessSenseCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
