// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SHIFTKit",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "Services", targets: ["Services"]),
    ],
    targets: [
        .target(name: "Models"),
        .target(name: "Engine", dependencies: ["Models"]),
        .target(name: "Services", dependencies: ["Engine"]),
    ]
)
