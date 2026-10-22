// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "Anon",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "AnonCore", targets: ["AnonCore"]),
        .library(name: "AnonCrypto", targets: ["AnonCrypto"]),
        .library(name: "AnonRouter", targets: ["AnonRouter"]),
        .library(name: "AnonNetwork", targets: ["AnonNetwork"]),
        .library(name: "AnonTransports", targets: ["AnonTransports"])
    ],
    targets: [
        .target(name: "AnonCore", path: "Sources/AnonCore"),
        .target(name: "AnonCrypto", path: "Sources/AnonCrypto"),
        .target(name: "AnonRouter", dependencies: ["AnonCore"], path: "Sources/AnonRouter"),
        .target(name: "AnonNetwork", dependencies: ["AnonCore"], path: "Sources/AnonNetwork"),
        .target(name: "AnonTransports", dependencies: ["AnonCore", "AnonRouter"], path: "Sources/AnonTransports"),
        .testTarget(
            name: "AnonRouterTests",
            dependencies: ["AnonCore", "AnonCrypto", "AnonRouter", "AnonTransports"],
            path: "Tests/AnonRouterTests"
        )
    ]
)