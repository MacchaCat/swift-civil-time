// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-civil-time",
    products: [
        // Calendar dates and wall-clock times. No dependencies, no Foundation.
        .library(name: "CivilTime", targets: ["CivilTime"]),
        // Conversions between the civil types and Foundation's Date, TimeZone and DateComponents.
        .library(name: "CivilTimeFoundation", targets: ["CivilTimeFoundation"]),
    ],
    targets: [
        .target(name: "CivilTime"),
        .target(
            name: "CivilTimeFoundation",
            dependencies: ["CivilTime"]
        ),
        .testTarget(
            name: "CivilTimeTests",
            dependencies: ["CivilTime"]
        ),
        .testTarget(
            name: "CivilTimeFoundationTests",
            dependencies: ["CivilTime", "CivilTimeFoundation"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
