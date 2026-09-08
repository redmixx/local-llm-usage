// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "local-llm-usage-tests",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.13.0")
    ],
    targets: [
        .target(
            name: "LocalLLMUsageCore",
            path: "Sources/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "local-llm-usage-tests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                "LocalLLMUsageCore"
            ],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
