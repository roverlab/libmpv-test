// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibMpv-iOS",
    platforms: [
        .iOS(.v13)
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
            path: "lib/Libmpv.xcframework"
        ),
        .testTarget(
            name: "MPVScreenshotTests",
            dependencies: ["Libmpv"],
            path: "Tests"
        )
    ]
)
