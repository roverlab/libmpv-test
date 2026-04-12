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
        ),
        .library(
            name: "LibmpvSwift",
            targets: ["LibmpvSwift"]
        )
    ],
    targets: [
        .target(
            name: "Libmpv",
            dependencies: [],
            cSettings: [
                .headerSearchPath("Sources/Libmpv/include"),
                .unsafeFlags([
                    "-fobjc-arc",
                    "-fmodules"
                ])
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("resolv"),
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .unsafeFlags([
                    "-L./lib",
                    "-lmpv",
                    "-lswresample",
                    "-lavformat",
                    "-lavcodec",
                    "-lavutil",
                    "-lass",
                    "-lfreetype",
                    "-lharfbuzz",
                    "-lfribidi",
                    "-luchardet"
                ])
            ]
        ),
        .target(
            name: "LibmpvSwift",
            dependencies: ["Libmpv"],
            path: "Sources/LibmpvSwift"
        ),
        .testTarget(
            name: "MPVScreenshotTests",
            dependencies: [
                "LibmpvSwift"
            ],
            path: "Tests",
            cSettings: [
                .headerSearchPath("../Sources/Libmpv/include")
            ]
        )
    ]
)
