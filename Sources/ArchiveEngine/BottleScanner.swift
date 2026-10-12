import Foundation
import Darwin

func metadata(_ url: URL) throws -> stat {
    var value = stat()
    guard url.withUnsafeFileSystemRepresentation({ lstat($0!, &value) }) == 0 else {
        throw ArchiveError.failed("A file could not be inspected: \(url.lastPathComponent). Check that the bottle is available.")
    }
    return value
}
func isInside(_ child: URL, _ parent: URL) -> Bool {
    let c = child.standardizedFileURL.resolvingSymlinksInPath().path
    let p = parent.standardizedFileURL.resolvingSymlinksInPath().path
    return c == p || c.hasPrefix(p + "/")
}

public enum BottleScanner {
    public static func scan(_ bottle: Bottle) async throws -> BottleSnapshot {
        try Task.checkCancellation()
        let conf = bottle.url.appendingPathComponent("cxbottle.conf")
        guard let s = try? metadata(conf), s.st_mode & S_IFMT == S_IFREG else { throw ArchiveError.invalidBottle }
        var stack = [bottle.url], seen = Set<String>(), files = [FileSampleCandidate](), links = [URL]()
        var bytes: UInt64 = 0, count = 1
        while let directory = stack.popLast() {
            try Task.checkCancellation()
            let children: [URL]
            do { children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
            catch { throw ArchiveError.unreadableSource }
            for child in children {
                try Task.checkCancellation()
                if directory == bottle.url && ["files", "desktopdata"].contains(child.lastPathComponent) { continue }
                let info = try metadata(child)
                count += 1
                switch info.st_mode & S_IFMT {
                case S_IFDIR: stack.append(child)
                case S_IFLNK:
                    if !isInside(child, bottle.url) { links.append(child) }
                case S_IFREG:
                    let key = "\(info.st_dev):\(info.st_ino)"
                    guard seen.insert(key).inserted else { continue }
                    guard access(child.path, R_OK) == 0 else { throw ArchiveError.unreadableSource }
                    let size = UInt64(max(0, info.st_size))
                    bytes += size
                    files.append(FileSampleCandidate(url: child, size: size))
                default: break
                }
            }
        }
        return BottleSnapshot(bottle: bottle, logicalBytes: bytes,
            archiveInputEstimate: bytes + UInt64(count) * 1024 + 10240,
            fileCount: count, files: files, externalLinks: links)
    }
}
