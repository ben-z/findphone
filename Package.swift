// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "findphone",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "findphone", path: "Sources/findphone"),
        .testTarget(name: "findphoneTests", dependencies: ["findphone"]),
    ]
)
