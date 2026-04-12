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
            checksum: "144a55ac1391eba24a401b0c41524a169f4385722133b1a6b87cfe1146665ea3"
        )
    ]
)
