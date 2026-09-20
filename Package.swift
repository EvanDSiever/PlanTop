// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlanTop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PlanTop",
            targets: ["PlanTop"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PlanTop",
            dependencies: [],
            path: "Sources/PlanTop"
        )
    ]
)

