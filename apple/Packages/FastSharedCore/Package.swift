// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FastSharedCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FastSharedCore", targets: ["FastSharedCore"])
    ],
    targets: [
        .target(
            name: "FastSharedCore",
            path: "Sources/FastSharedCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FastSharedCoreTests",
            dependencies: ["FastSharedCore"],
            path: "Tests/FastSharedCoreTests",
            resources: [.process("Resources")]
        )
    ]
)
