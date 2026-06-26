// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSnap",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MacSnap",
            path: "Sources/MacSnap",
            swiftSettings: [
                .swiftLanguageMode(.v5)   // AppKit/NSObject ergonomics; avoids strict-concurrency churn for a V1
            ]
        )
    ]
)
