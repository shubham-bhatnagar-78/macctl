// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macctl",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacCtlKit", targets: ["MacCtlKit"]),
        .executable(name: "macctl", targets: ["macctl"]),
        .executable(name: "macctl-daemon", targets: ["macctl-daemon"]),
        .executable(name: "macctl-mcp", targets: ["macctl-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "MacCtlKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MacCtlKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "macctl",
            dependencies: [
                "MacCtlKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/macctl",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "macctl-daemon",
            dependencies: [
                "MacCtlKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/macctl-daemon",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "macctl-mcp",
            dependencies: ["MacCtlKit"],
            path: "Sources/macctl-mcp",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MacCtlKitTests",
            dependencies: ["MacCtlKit"],
            path: "Tests/MacCtlKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
