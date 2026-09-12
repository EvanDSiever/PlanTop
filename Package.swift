// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SongTop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SongTop",
            targets: ["SongTop"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SongTop",
            dependencies: [],
            path: "Sources/SongTop"
        )
    ]
)
