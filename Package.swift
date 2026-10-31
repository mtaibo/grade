// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "grade",
    platforms: [
        .iOS(.v27),
        // Only for `swift test` on a Mac.
        .macOS(.v26),
    ],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
    ],
    targets: [
        .target(name: "Engine"),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
        // The app's model files (no UI), built here too so `swift test` covers saving, importing
        // and archiving without a simulator. The app compiles the same files itself.
        .target(
            name: "AppModel",
            dependencies: ["Engine"],
            path: "App/Sources/Model"
        ),
        .testTarget(name: "AppModelTests", dependencies: ["AppModel", "Engine"]),
    ]
)
