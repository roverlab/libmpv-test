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
            checksum: "b1c1e68c1de91c21a35bcf49904acf0d129d14be399cc9442349c904a4c12736"
        )
    ]
)
