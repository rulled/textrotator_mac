// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TextRotator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TextRotatorCore",
            targets: ["TextRotatorCore"]
        ),
        .executable(
            name: "TextRotator",
            targets: ["TextRotatorApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TextRotatorCore",
            dependencies: [],
            path: "Sources/TextRotatorCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TextRotatorApp",
            dependencies: ["TextRotatorCore"],
            path: "Sources/TextRotatorApp"
        ),
        .testTarget(
            name: "TextRotatorTests",
            dependencies: ["TextRotatorCore"],
            path: "Tests/TextRotatorTests"
        )
    ]
)
