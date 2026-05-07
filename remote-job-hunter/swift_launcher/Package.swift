// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteJobHunterApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RemoteJobHunterApp", targets: ["RemoteJobHunterApp"]),
    ],
    targets: [
        .executableTarget(
            name: "RemoteJobHunterApp",
            path: "Sources/RemoteJobHunterApp"
        ),
    ]
)
