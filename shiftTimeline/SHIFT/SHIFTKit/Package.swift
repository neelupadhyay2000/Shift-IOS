// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SHIFTKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "Services", targets: ["Services"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    targets: [
        .target(name: "Models"),
        .target(name: "Engine", dependencies: ["Models"]),
        .target(
            name: "ObjCException",
            publicHeadersPath: "include"
        ),
        .target(name: "Services", dependencies: ["Models", "Engine", "ObjCException"], resources: [
            .copy("Resources/Templates"),
        ]),
        .target(name: "TestSupport", dependencies: ["Models"]),
    ]
)
