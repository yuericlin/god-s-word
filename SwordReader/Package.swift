// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwordReader",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SwordReader", targets: ["SwordReader"]),
    ],
    targets: [
        .target(
            name: "SwordReader",
            path: "Sources/SwordReader"
        ),
        .testTarget(
            name: "SwordReaderTests",
            dependencies: ["SwordReader"],
            path: "Tests/SwordReaderTests"
        ),
    ]
)
