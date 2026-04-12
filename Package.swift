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
            url: "https://github.com/roverlab/libmpv-test/releases/download/v0.1.22/Libmpv.xcframework.zip",
            checksum: "4d46388df8c6d17d9b51416ec1537478a44ac0a4a52ac5d00f89906db0d77061"
        )
    ]
)
