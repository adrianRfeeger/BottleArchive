// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BottleArchive", platforms: [.macOS(.v15)], products: [.library(name:"ArchiveEngine", targets:["ArchiveEngine"])], targets: [.systemLibrary(name:"CZlib"), .target(name:"ArchiveEngine",dependencies:["CZlib"]), .testTarget(name:"ArchiveEngineTests", dependencies:["ArchiveEngine"])], swiftLanguageModes:[.v5])
