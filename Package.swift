// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OhMyServers",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OhMyServersCore", targets: ["OhMyServersCore"]),
        .executable(name: "OhMyServers", targets: ["OhMyServers"])
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.7.0")
    ],
    targets: [
        .target(
            name: "OhMyServersCore",
            dependencies: [
                .product(name: "Citadel", package: "Citadel")
            ]
        ),
        .executableTarget(
            name: "OhMyServers",
            dependencies: ["OhMyServersCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "OhMyServersCoreTests",
            dependencies: ["OhMyServersCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
