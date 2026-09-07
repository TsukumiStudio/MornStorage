// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MornStorage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MornStorage", targets: ["MornStorage"])],
    targets: [
        .executableTarget(name: "MornStorage"),
        .testTarget(name: "MornStorageTests", dependencies: ["MornStorage"])
    ]
)
