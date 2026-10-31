// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "snapmark",
    platforms: [.macOS("15.2")],
    targets: [
        .executableTarget(name: "Snapmark", path: "Sources/Snapmark")
    ]
)
