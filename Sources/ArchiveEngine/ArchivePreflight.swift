import Foundation
import Darwin
public enum ArchivePreflight {
    public static func validate(bottle: Bottle, destination: URL) throws {
        guard let s = try? metadata(bottle.url.appendingPathComponent("cxbottle.conf")), s.st_mode & S_IFMT == S_IFREG else { throw ArchiveError.invalidBottle }
        guard access(bottle.url.path, R_OK | X_OK) == 0 else { throw ArchiveError.unreadableSource }
        if isInside(destination, bottle.url) { throw ArchiveError.destinationInsideBottle }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &directory), directory.boolValue else { throw ArchiveError.unavailableDestination }
        let probe = destination.appendingPathComponent(".BottleArchive-probe-" + UUID().uuidString)
        let fd = open(probe.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ArchiveError.unavailableDestination }
        close(fd)
        unlink(probe.path)
        let values = try destination.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard (values.volumeAvailableCapacity ?? 0) > 1024 * 1024 else { throw ArchiveError.unavailableDestination }
    }
}
