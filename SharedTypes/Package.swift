// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SharedTypes",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SharedTypes",
            targets: ["SharedTypes"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SharedTypes",
            dependencies: []),
    ]
) 