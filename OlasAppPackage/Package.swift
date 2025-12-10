// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OlasAppFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "OlasAppFeature",
            targets: ["OlasAppFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../Packages/Olas"),
        .package(url: "https://github.com/pablof7z/NDKSwift", branch: "master")
    ],
    targets: [
        .target(
            name: "OlasAppFeature",
            dependencies: [
                .product(name: "Olas", package: "Olas"),
                .product(name: "NDKSwift", package: "NDKSwift")
            ]
        ),
        .testTarget(
            name: "OlasAppFeatureTests",
            dependencies: [
                "OlasAppFeature"
            ]
        ),
    ]
)
