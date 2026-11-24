// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ElementAVSynth",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ElementAVCore",
            targets: ["ElementAVCore"]
        )
    ],
    targets: [
        .target(
            name: "ElementAVCore",
            path: "Sources/ElementAVCore"
        ),
        .testTarget(
            name: "ElementAVCoreTests",
            dependencies: ["ElementAVCore"],
            path: "Tests/ElementAVCoreTests"
        )
    ]
)
