// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnimeTracker",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .executable(name: "AnimeTracker", targets: ["AnimeTracker"])
    ],
    targets: [
        .executableTarget(
            name: "AnimeTracker",
            path: "Sources"
        )
    ]
)
