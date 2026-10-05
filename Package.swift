// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "LiricoKit",
    platforms: [
        .macOS(.v10_15),
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
        .package(url: "https://github.com/MxIris-Library-Forks/SwiftCF", from: "0.2.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.9.0"),
        .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", from: "0.5.4"),
    ],
    targets: [
        .target(
            name: "LiricoKit",
            dependencies: [
                "LyricsCore",
                "LyricsService",
                "LyricsServiceUI",
            ]
        ),
        .target(
            name: "LyricsCore",
            dependencies: [
                .product(name: "Regex", package: "Regex"),
                .product(name: "SwiftCF", package: "SwiftCF"),
            ]
        ),
        .target(
            name: "LyricsService",
            dependencies: [
                "LyricsCore",
                .product(name: "Regex", package: "Regex"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ]
        ),
        .target(
            name: "LyricsServiceUI",
            dependencies: [
                "LyricsCore",
                "LyricsService",
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
