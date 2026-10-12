import Foundation
public enum CompressionPreset: String, CaseIterable, Codable, Sendable { case fast, balanced, maximum
 public var gzipLevel: Int { self == .fast ? 1 : self == .balanced ? 6 : 9 }
}
public struct Bottle: Hashable, Sendable { public let url: URL; public var name: String { url.lastPathComponent }; public init(url: URL) { self.url=URL(fileURLWithPath:url.standardizedFileURL.resolvingSymlinksInPath().path,isDirectory:true) } }
public enum ArchiveError: Error, LocalizedError, Equatable { case invalidBottle, destinationInsideBottle, unavailableDestination, unreadableSource, runningBottle, busy, failed(String), invalidArchive(String)
 public var errorDescription: String? { switch self { case .invalidBottle: return "Choose a bottle containing cxbottle.conf."; case .destinationInsideBottle: return "Choose a destination outside the bottle."; case .unavailableDestination: return "The destination is unavailable or cannot be written to. Reconnect the drive or choose another folder."; case .unreadableSource: return "Some bottle files cannot be read. Check their permissions."; case .runningBottle:return "Close the applications in this bottle, then try again."; case .busy:return "An archive job is already running."; case .failed(let s), .invalidArchive(let s):return s } }
}
public struct FileSampleCandidate: Sendable { public let url: URL; public let size: UInt64 }
public struct BottleSnapshot: Sendable { public let bottle: Bottle; public let logicalBytes: UInt64; public let archiveInputEstimate: UInt64; public let fileCount: Int; public let files: [FileSampleCandidate]; public let externalLinks:[URL] }
