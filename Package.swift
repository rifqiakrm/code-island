// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeIsland",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/simibac/ConfettiSwiftUI.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodeIsland",
            dependencies: [
                .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI"),
            ],
            path: "Sources/CodeIsland",
            resources: [
                .copy("../../Resources/Sounds"),
                .copy("../../Resources/cli-icons"),
            ]
        ),
        .executableTarget(
            name: "CodeIslandBridge",
            path: "Sources/CodeIslandBridge"
        ),
    ]
)
