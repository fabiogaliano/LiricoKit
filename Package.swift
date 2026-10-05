// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "LiricoKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "LiricoKit",
            targets: ["LiricoKit"]
        ),
        // Apple Music support is a separate product so widget/extension
        // targets are never forced to link WebKit.
        .library(
            name: "LiricoKitAppleMusic",
            targets: ["LyricsServiceAppleMusic"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ddddxxx/Regex", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "LiricoKit",
            dependencies: [
                "LyricsCore",
                "LyricsService",
            ]
        ),
        .target(
            name: "LyricsCore",
            dependencies: [
                .product(name: "Regex", package: "Regex"),
            ]
        ),
        .target(
            name: "LyricsService",
            dependencies: [
                "LyricsCore",
                .product(name: "Regex", package: "Regex"),
            ]
        ),
        .target(
            name: "LyricsServiceAppleMusic",
            dependencies: [
                "LyricsCore",
                "LyricsService",
            ]
        ),
        .testTarget(
            name: "LiricoKitTests",
            dependencies: [
                "LyricsCore",
                "LyricsService",
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
