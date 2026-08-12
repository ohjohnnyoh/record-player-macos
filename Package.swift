// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RecordPlayer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RecordPlayer",
            path: "Sources/RecordPlayer"
        )
    ]
)
