// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "grade",
    platforms: [
        .iOS(.v27),
    ],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
    ],
    targets: [
        .target(name: "Engine"),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
    ]
)
