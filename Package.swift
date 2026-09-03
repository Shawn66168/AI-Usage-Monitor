// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AIUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AIUsageMonitor",
            targets: ["AIUsageMonitor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AIUsageMonitor",
            path: "Sources/AIUsageMonitor"
        )
    ]
)
