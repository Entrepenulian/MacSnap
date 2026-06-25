// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macsnap",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "macsnap",
            path: "Sources/macsnap",
            swiftSettings: [
                .swiftLanguageMode(.v5)   // AppKit/NSObject ergonomics; avoids strict-concurrency churn for a V1
            ]
        )
    ]
)
