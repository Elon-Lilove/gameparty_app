// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PartyGames",
    platforms: [
        .iOS(.v17),
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
    ]
)
