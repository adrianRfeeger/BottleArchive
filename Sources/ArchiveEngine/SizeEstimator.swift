import Foundation
import Darwin
import CZlib

public struct ArchiveSizeEstimate: Sendable {
    public let estimatedBytes: UInt64
    public let sampledBytes: UInt64
    public let gzipLevel: Int
}

public enum SizeEstimator {
    public static func estimate(snapshot: BottleSnapshot, compression: CompressionPreset) async throws -> ArchiveSizeEstimate {
        try Task.checkCancellation()
        let groups = Dictionary(grouping: snapshot.files.filter { $0.size > 0 }) { file in
            let band = file.size < 16384 ? 0 : file.size < 1048576 ? 1 : file.size < 67108864 ? 2 : 3
            return file.url.pathExtension.lowercased() + ":" + String(band)
        }.values.sorted { $0.reduce(UInt64(0)) { $0 + $1.size } > $1.reduce(UInt64(0)) { $0 + $1.size } }
        let budget = 64 * 1024 * 1024
        var sampled = 0, estimate = Double(snapshot.archiveInputEstimate - snapshot.logicalBytes)
        for group in groups {
            try Task.checkCancellation()
            let weight = group.reduce(UInt64(0)) { $0 + $1.size }
            var groupRaw = 0, groupCompressed = 0
            for file in group.sorted(by: { $0.size > $1.size }).prefix(8) {
                guard sampled < budget else { break }
                guard isInside(file.url, snapshot.bottle.url) else { throw ArchiveError.unreadableSource }
                let fd = open(file.url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw ArchiveError.unreadableSource }
                defer { close(fd) }
                var info = stat()
                var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                      UInt64(info.st_size) == file.size,
                      fcntl(fd, F_GETPATH, &pathBuffer) == 0,
                      isInside(URL(fileURLWithPath: String(cString: pathBuffer)), snapshot.bottle.url) else { throw ArchiveError.unreadableSource }
                let chunk = min(Int(file.size), 1024 * 1024)
                let positions = file.size <= UInt64(chunk) ? [UInt64(0)] : [0, (file.size - UInt64(chunk)) / 2, file.size - UInt64(chunk)]
                for position in Array(Set(positions)).sorted() {
                    try Task.checkCancellation()
                    let length = min(chunk, budget - sampled)
                    guard length > 0 else { break }
                    var bytes = [UInt8](repeating: 0, count: length)
                    let got = pread(fd, &bytes, length, off_t(position))
                    guard got == length else { throw ArchiveError.unreadableSource }
                    var destinationLength = compressBound(uLong(length))
                    var compressed = [UInt8](repeating: 0, count: Int(destinationLength))
                    let status = compress2(&compressed, &destinationLength, bytes, uLong(length), Int32(compression.gzipLevel))
                    guard status == Z_OK else { throw ArchiveError.failed("The archive size could not be estimated.") }
                    groupRaw += length
                    groupCompressed += Int(destinationLength) + 6
                    sampled += length
                }
            }
            estimate += Double(weight) * (groupRaw == 0 ? 1 : Double(groupCompressed) / Double(groupRaw))
        }
        return ArchiveSizeEstimate(estimatedBytes: UInt64(max(0, estimate.rounded())), sampledBytes: UInt64(sampled), gzipLevel: compression.gzipLevel)
    }
}
