// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "C1Control2026",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "C1Control2026", targets: ["C1Control2026"])
    ],
    targets: [
        .executableTarget(
            name: "C1Control2026",
            path: "Sources/C1Control2026"
        )
    ]
)
