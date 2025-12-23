// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NWCTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.build/DerivedData/SourcePackages/checkouts/NDKSwift")
    ],
    targets: [
        .executableTarget(
            name: "NWCTest",
            dependencies: [
                .product(name: "NDKSwiftCore", package: "NDKSwift")
            ]
        )
    ]
)
