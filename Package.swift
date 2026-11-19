// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SNSECore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SNSECore", targets: ["SNSECore"]),
        .executable(name: "snse-diag", targets: ["snse-diag"]),
    ],
    targets: [
        .target(name: "SNSECore"),
        .executableTarget(
            name: "snse-diag",
            dependencies: ["SNSECore"],
            path: "Sources/snse-diag"
        ),
        .testTarget(
            name: "SNSECoreTests",
            dependencies: ["SNSECore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
