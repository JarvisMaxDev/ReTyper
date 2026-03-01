// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReTyper",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ReTyper",
            path: "Sources/ReTyper",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
            ]
        ),
        .testTarget(
            name: "ReTyperTests",
            dependencies: ["ReTyper"],
            path: "Tests/ReTyperTests"
        ),
    ]
)
