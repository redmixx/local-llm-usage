// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "local-llm-usage-tests",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "LocalLLMUsageCore",
            path: "Sources/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "local-llm-usage-tests",
            dependencies: [
                "LocalLLMUsageCore"
            ],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
