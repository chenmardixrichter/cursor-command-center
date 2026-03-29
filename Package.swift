// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommandCenter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CommandCenterCore",
            path: "Sources/CommandCenterCore",
            resources: [.copy("Resources/cc-signal.sh")]
        ),
        .executableTarget(
            name: "CommandCenter",
            dependencies: ["CommandCenterCore"],
            path: "Sources/CommandCenter"
        ),
        .executableTarget(
            name: "CommandCenterAutomation",
            dependencies: ["CommandCenterCore"],
            path: "Sources/CommandCenterAutomation"
        ),
    ]
)
