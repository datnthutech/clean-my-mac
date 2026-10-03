// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiskKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DiskKit", targets: ["DiskKit"]),
    ],
    targets: [
        .target(name: "DiskKit"),
        .testTarget(name: "DiskKitTests", dependencies: ["DiskKit"]),
    ]
)
