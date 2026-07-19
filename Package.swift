// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PartyGames",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "PartyGames",
            targets: ["PartyGames"]
        ),
    ],
    targets: [
        .target(
            name: "PartyGames",
            path: "PartyGames",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "PartyGamesUnitTests",
            dependencies: ["PartyGames"],
            path: "Tests/PartyGamesUnitTests"
        ),
    ]
)
