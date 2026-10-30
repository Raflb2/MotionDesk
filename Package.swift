// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MotionDesk",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MotionDesk", path: "Sources/MotionDesk")
    ]
)
