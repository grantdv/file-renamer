// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileRenamer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "FileRenamer", path: "Sources/FileRenamer")
    ]
)
