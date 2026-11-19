// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileRenamer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Shared engine: models, AI client, naming rules, folder watching, store.
        .target(
            name: "FileRenamerCore",
            path: "Sources/FileRenamerCore"
        ),
        // The menu bar app.
        .executableTarget(
            name: "FileRenamer",
            dependencies: ["FileRenamerCore"],
            path: "Sources/FileRenamer"
        ),
        // Finder Services plugin (right-click → Services → Rename with AI FileRenamer).
        .executableTarget(
            name: "FileRenamerService",
            dependencies: ["FileRenamerCore"],
            path: "Sources/FileRenamerService"
        ),
    ]
)
