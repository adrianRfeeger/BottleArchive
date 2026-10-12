import Foundation
import Darwin
import CArchive

public struct VerificationResult: Sendable {
    public let entryCount: Int
    public let bottleName: String
    public let verifiedBytes: UInt64
}
private final class ArchiveReadContext {
    let fd: Int32, size: Double
    let report: @Sendable (Double) -> Void
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: 256 * 1024, alignment: 8)
    var readBytes: Double = 0
    init(fd: Int32, size: UInt64, report: @escaping @Sendable (Double) -> Void) { self.fd = fd; self.size = Double(size); self.report = report }
    deinit { buffer.deallocate() }
}
private func archiveReadCallback(_ reader: OpaquePointer?, _ client: UnsafeMutableRawPointer?, _ output: UnsafeMutablePointer<UnsafeRawPointer?>?) -> Int {
    guard let client else { return -1 }
    let context = Unmanaged<ArchiveReadContext>.fromOpaque(client).takeUnretainedValue()
    if Task.isCancelled { return -1 }
    let count = Darwin.read(context.fd, context.buffer, 256 * 1024)
    if count >= 0 {
        output?.pointee = UnsafeRawPointer(context.buffer)
        context.readBytes += Double(count)
        context.report(0.5 + min(0.5, context.readBytes / max(1, context.size) * 0.5))
    }
    return count
}
public enum ArchiveVerifier {
    public static func verify(url: URL, expectedBottleName: String, progress: @escaping @Sendable (Double) -> Void) async throws -> VerificationResult {
        try Task.checkCancellation()
        let before = try metadata(url)
        guard before.st_mode & S_IFMT == S_IFREG else { throw ArchiveError.invalidArchive("The archive is not a regular file.") }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ArchiveError.invalidArchive("The archive could not be opened for verification.") }
        let source = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? source.close() }
        let input = Pipe()
        let check = try OwnedProcess.spawn(executable: URL(fileURLWithPath: "/usr/bin/gzip"), arguments: ["-t"], stdin: input.fileHandleForReading.fileDescriptor)
        try input.fileHandleForReading.close()
        defer { check.cancel(); try? input.fileHandleForWriting.close(); try? check.stdoutHandle?.close() }
        var processed: UInt64 = 0
        do {
            while let data = try source.read(upToCount: 256 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                try input.fileHandleForWriting.write(contentsOf: data)
                processed += UInt64(data.count)
                progress(min(0.5, Double(processed) / max(1, Double(before.st_size)) * 0.5))
            }
            try input.fileHandleForWriting.close()
            guard try await check.wait() == 0 else { throw ArchiveError.invalidArchive("The compressed archive is damaged or incomplete. Create a new archive.") }
        } catch {
            check.cancel()
            _ = try? await check.wait()
            try Task.checkCancellation()
            if error is ArchiveError { throw error }
            throw ArchiveError.invalidArchive("The archive could not be read completely. Check the destination drive.")
        }
        try Task.checkCancellation()
        guard lseek(fd, 0, SEEK_SET) == 0, let reader = archive_read_new() else { throw ArchiveError.invalidArchive("Could not start archive verification.") }
        defer { archive_read_free(reader) }
        archive_read_support_filter_gzip(reader)
        archive_read_support_format_tar(reader)
        let context = ArchiveReadContext(fd: fd, size: UInt64(before.st_size), report: progress)
        let retained = Unmanaged.passRetained(context)
        defer { retained.release() }
        let opaque = retained.toOpaque()
        guard archive_read_open(reader, opaque, nil, archiveReadCallback, nil) == ARCHIVE_OK else { throw ArchiveError.invalidArchive("The file does not contain a readable bottle archive.") }
        var entry: OpaquePointer?, count = 0, foundConfiguration = false
        while true {
            try Task.checkCancellation()
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry, let rawName = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else {
                throw ArchiveError.invalidArchive("The archive contains an unreadable entry.")
            }
            let name = String(cString: rawName)
            let parts = name.split(separator: "/").filter { $0 != "." }
            guard !name.hasPrefix("/"), !parts.contains(".."), parts.first.map(String.init) == expectedBottleName else {
                throw ArchiveError.invalidArchive("The archive does not contain exactly the selected bottle.")
            }
            if parts.count == 2 && parts[1] == "cxbottle.conf" && archive_entry_filetype(entry) == 0o100000 {
                foundConfiguration = true
            }
            if let link = archive_entry_hardlink(entry) {
                let target = String(cString: link).split(separator: "/").filter { $0 != "." }
                guard target.first.map(String.init) == expectedBottleName, !target.contains("..") else {
                    throw ArchiveError.invalidArchive("The archive contains an invalid hard link.")
                }
            }
            guard archive_read_data_skip(reader) == ARCHIVE_OK else { throw ArchiveError.invalidArchive("The archive contents are incomplete.") }
            count += 1
        }
        guard foundConfiguration else { throw ArchiveError.invalidArchive("The archive is missing cxbottle.conf.") }
        let after = try metadata(url)
        guard before.st_ino == after.st_ino, before.st_dev == after.st_dev, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw ArchiveError.invalidArchive("The archive changed during verification. Try again.")
        }
        progress(1)
        return VerificationResult(entryCount: count, bottleName: expectedBottleName, verifiedBytes: UInt64(before.st_size))
    }
}
