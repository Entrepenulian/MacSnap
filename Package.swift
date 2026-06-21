// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macshot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "macshot",
            path: "Sources/macshot",
            swiftSettings: [
                .swiftLanguageMode(.v5)   // AppKit/NSObject ergonomics; avoids strict-concurrency churn for a V1
            ]
        )
    ]
)
