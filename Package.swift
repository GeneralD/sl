// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "sl",
            dependencies: ["SLCore", "OverlayKit", "TrainScene"],
            path: "Sources/sl"
        ),
        .target(
            name: "SLCore",
            path: "Sources/SLCore"
        ),
        .target(
            name: "OverlayKit",
            dependencies: ["SLCore"],
            path: "Sources/OverlayKit"
        ),
        .target(
            name: "TrainScene",
            dependencies: ["SLCore", "OverlayKit"],
            path: "Sources/TrainScene"
        ),
        .target(
            name: "SLTestKit",
            path: "Sources/SLTestKit"
        ),
        .executableTarget(
            name: "slChecks",
            dependencies: ["SLCore", "OverlayKit", "TrainScene", "SLTestKit"],
            path: "Sources/slChecks"
        ),
    ]
)
