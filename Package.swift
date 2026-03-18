// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogFlux",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "LogFlux", targets: ["LogFlux"]),
    ],
    targets: [
        .target(
            name: "LogFlux",
            path: "Sources/LogFlux"
        ),
        .testTarget(
            name: "LogFluxTests",
            dependencies: ["LogFlux"],
            path: "Tests/LogFluxTests"
        ),
    ]
)
