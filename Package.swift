// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Libmpv",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "Libmpv",
            targets: ["Libmpv"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "Libmpv",
            url: "https://github.com/roverlab/libmpv-test/releases/download/v0.39.0/Libmpv.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    ]
)
