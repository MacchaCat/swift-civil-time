// swift-tools-version: 6.0

// A separate package so that the library itself has no benchmark target.
// Run with: swift run -c release --package-path Benchmarks

import PackageDescription

let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(
            name: "Benchmarks",
            dependencies: [
                .product(name: "CivilTime", package: "swift-civil-time"),
                .product(name: "CivilTimeFoundation", package: "swift-civil-time"),
            ]
        ),
    ]
)
