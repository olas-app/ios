// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olas",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Olas", targets: ["Olas"])
    ],
    dependencies: [
        .package(url: "https://github.com/pablof7z/NDKSwift", branch: "master"),
        .package(url: "https://github.com/iankoex/UnifiedBlurHash", from: "1.0.0"),
        .package(url: "https://github.com/breez/breez-sdk-spark-swift", from: "0.6.1")
    ],
    targets: [
        .target(
            name: "Olas",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
                .product(name: "NDKSwiftUI", package: "NDKSwift"),
                .product(name: "UnifiedBlurHash", package: "UnifiedBlurHash"),
                .product(name: "BreezSdkSpark", package: "breez-sdk-spark-swift")
            ],
            exclude: ["OlasApp.swift"]
        ),
        .testTarget(
            name: "OlasTests",
            dependencies: ["Olas"]
        )
    ]
)
