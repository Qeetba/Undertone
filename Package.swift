// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Undertone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "UndertoneCore"
        ),
        .executableTarget(
            name: "Undertone",
            dependencies: ["UndertoneCore"]
        ),
        .testTarget(
            name: "UndertoneTests",
            dependencies: ["UndertoneCore"]
        )
    ]
)
