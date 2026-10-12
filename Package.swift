// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BottleArchive", defaultLocalization: "en", platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BottleArchive", targets: ["BottleArchive"]),
        .executable(name: "pigz", targets: ["pigz"]),
        .library(name: "ArchiveEngine", targets: ["ArchiveEngine"])
    ],
    targets: [
        .systemLibrary(name: "CZlib"), .systemLibrary(name: "CArchive"),
        .target(name: "ProcessSupport"),
        .target(name: "ArchiveEngine", dependencies: ["CZlib", "CArchive", "ProcessSupport"]),
        .target(name: "AppState", dependencies: ["ArchiveEngine"]),
        .executableTarget(name: "BottleArchive", dependencies: ["AppState", "ArchiveEngine"], resources: [.process("Resources")]),
        .executableTarget(name: "pigz", path: "Vendor/pigz", exclude: ["README", "UPSTREAM.md"], sources: ["pigz.c", "yarn.c", "try.c"], cSettings: [.define("NOZOPFLI")], linkerSettings: [.linkedLibrary("z")]),
        .testTarget(name: "ArchiveEngineTests", dependencies: ["ArchiveEngine"]),
        .testTarget(name: "BottleArchiveStateTests", dependencies: ["AppState", "ArchiveEngine"])
    ], swiftLanguageModes: [.v5]
)
