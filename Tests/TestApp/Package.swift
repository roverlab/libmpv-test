// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TestApp",
    platforms: [
        .iOS(.v13)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TestApp",
            dependencies: [
                .target(name: "Libmpv")
            ]
        ),
        .binaryTarget(
            name: "Libmpv",
            path: "../../lib/Libmpv.xcframework"
        ),
        .testTarget(
            name: "TestAppTests",
            dependencies: ["TestApp"]
        )
    ]
)
