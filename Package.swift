// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RecordPlayer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.4"
        )
    ],
    targets: [
        .executableTarget(
            name: "RecordPlayer",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/RecordPlayer",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "RecordPlayerTests",
            dependencies: ["RecordPlayer"],
            path: "Tests/RecordPlayerTests"
        )
    ]
)
