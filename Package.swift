// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BottleArchive", platforms: [.macOS(.v15)], products: [.library(name:"ArchiveEngine", targets:["ArchiveEngine"])], targets: [.target(name:"ArchiveEngine"), .testTarget(name:"ArchiveEngineTests", dependencies:["ArchiveEngine"])], swiftLanguageModes:[.v5])
