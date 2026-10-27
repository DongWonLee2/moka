// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Moka",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MokaCore", targets: ["MokaCore"]),
        .library(name: "MokaStore", targets: ["MokaStore"]),
        .executable(name: "moka-sim", targets: ["moka-sim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "MokaCore"),
        .target(
            name: "MokaStore",
            dependencies: ["MokaCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(name: "moka-sim", dependencies: ["MokaCore", "MokaStore"]),
        .testTarget(name: "MokaCoreTests", dependencies: ["MokaCore"]),
        .testTarget(name: "MokaStoreTests", dependencies: ["MokaStore"]),
    ]
)
