import Foundation
import Darwin
import IOKit.pwr_mgt

public final class ArchiveJob: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var processes = [OwnedProcess]()
    private let compressionTool: CompressionTool
    public init(gzip: URL? = nil, parallelGzip: URL? = nil) {
        compressionTool = parallelGzip.map { CompressionTool(executable: $0, supportsThreads: true) }
            ?? gzip.map { CompressionTool(executable: $0, supportsThreads: false) }
            ?? CompressionTool.locate()
    }
    public func start(request: ArchiveRequest, snapshot: BottleSnapshot) -> AsyncThrowingStream<ArchiveEvent, Error> {
        let pair = AsyncThrowingStream<ArchiveEvent, Error>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lock.lock()
        guard task == nil else { lock.unlock(); pair.continuation.finish(throwing: ArchiveError.busy); return pair.stream }
        task = Task.detached(priority: .utility) {
            do {
                let result = try await self.run(request: request, snapshot: snapshot, continuation: pair.continuation)
                self.finishState()
                pair.continuation.yield(.completed(result))
                pair.continuation.finish()
            } catch {
                self.finishState()
                pair.continuation.finish(throwing: error)
            }
        }
        lock.unlock()
        pair.continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.cancel() }
        }
        return pair.stream
    }
    private func finishState() { lock.lock(); task = nil; processes = []; lock.unlock() }
    private func register(_ process: OwnedProcess) { lock.lock(); processes.append(process); lock.unlock(); if Task.isCancelled { process.cancel() } }
    public func cancel() {
        lock.lock(); let t = task; let p = processes; lock.unlock()
        t?.cancel(); for process in p { process.cancel() }
    }
    private func run(request: ArchiveRequest, snapshot: BottleSnapshot, continuation: AsyncThrowingStream<ArchiveEvent, Error>.Continuation) async throws -> ArchiveResult {
        try Task.checkCancellation()
        guard snapshot.bottle == request.bottle else { throw ArchiveError.invalidBottle }
        let started = Date()
        func report(_ stage: ArchiveStage, _ fraction: Double?, _ processed: UInt64 = 0, _ output: UInt64 = 0, _ remaining: Double? = nil) {
            continuation.yield(.progress(ArchiveProgress(stage: stage, fraction: fraction, processedBytes: processed, outputBytes: output, elapsedSeconds: Date().timeIntervalSince(started), remainingSeconds: remaining)))
        }
        report(.preparing, nil)
        try ArchivePreflight.validate(bottle: request.bottle, destination: request.destination)
        let installation = CrossOverInstallation(app: request.crossOverApp)
        if try await installation.isRunning(request.bottle) { throw ArchiveError.runningBottle }
        try Task.checkCancellation()
        try ArchivePreflight.validate(bottle: request.bottle, destination: request.destination)
        let destination = request.destination.standardizedFileURL.resolvingSymlinksInPath()
        let destinationInfo = try metadata(destination)
        let capacity = try destination.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        let expected = request.estimatedBytes ?? snapshot.archiveInputEstimate
        guard UInt64(max(0, capacity)) > expected + 64 * 1024 * 1024 else {
            throw ArchiveError.failed("There may not be enough free space for this archive. Free space or choose another destination.")
        }
        var assertion: IOPMAssertionID = 0
        let hasAssertion = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Creating bottle archive" as CFString, &assertion) == kIOReturnSuccess
        defer { if hasAssertion { IOPMAssertionRelease(assertion) } }
        let partial = destination.appendingPathComponent(".BottleArchive-" + UUID().uuidString + ".partial")
        let fd = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ArchiveError.unavailableDestination }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let partialInfo = try metadata(partial)
        var published = false
        defer {
            try? output.close()
            if !published, let info = try? metadata(partial), info.st_ino == partialInfo.st_ino, info.st_dev == partialInfo.st_dev { unlink(partial.path) }
        }
        let input = Pipe()
        let compressor = try OwnedProcess.spawn(executable: compressionTool.executable, arguments: compressionTool.arguments(level: request.compression.gzipLevel, threads: request.threads), stdin: input.fileHandleForReading.fileDescriptor, stdout: fd)
        register(compressor)
        try input.fileHandleForReading.close()
        defer { compressor.cancel(); try? input.fileHandleForWriting.close() }
        let exporter: OwnedProcess
        do {
            exporter = try OwnedProcess.spawn(executable: installation.exporter, arguments: ["--bottle", request.bottle.name, "--tar", "-"], environment: installation.environment(for: request.bottle))
        } catch { compressor.cancel(); _ = try? await compressor.wait(); throw error }
        register(exporter)
        let compressionMonitor = Task.detached(priority: .utility) {
            if let status = try? await compressor.wait(), status != 0 { exporter.cancel() }
        }
        defer { compressionMonitor.cancel() }
        defer { exporter.cancel(); try? exporter.stdoutHandle?.close() }
        var processed: UInt64 = 0, lastReport = Date.distantPast
        func checkDestination() throws {
            let current = try metadata(destination)
            guard current.st_ino == destinationInfo.st_ino, current.st_dev == destinationInfo.st_dev else { throw ArchiveError.unavailableDestination }
        }
        do {
            while let data = try exporter.stdoutHandle?.read(upToCount: 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                try input.fileHandleForWriting.write(contentsOf: data)
                processed += UInt64(data.count)
                if Date().timeIntervalSince(lastReport) > 0.15 {
                    try checkDestination()
                    let elapsed = Date().timeIntervalSince(started)
                    let remaining = elapsed > 1 && processed > 0 ? max(0, Double(snapshot.archiveInputEstimate) - Double(processed)) / (Double(processed) / elapsed) : nil
                    var written = stat(); _ = fstat(fd, &written)
                    report(.archiving, min(0.99, Double(processed) / max(1, Double(snapshot.archiveInputEstimate))), processed, UInt64(max(0, written.st_size)), remaining)
                    lastReport = Date()
                }
            }
            try input.fileHandleForWriting.close()
            let exportStatus = try await exporter.wait()
            let compressionStatus = try await compressor.wait()
            try Task.checkCancellation()
            guard compressionStatus == 0 else { throw ArchiveError.failed("Compression failed. Check the free space and destination drive. \(compressor.stderrTail.suffix(1200))") }
            guard exportStatus == 0 else { throw ArchiveError.failed("CrossOver could not export this bottle. \(exporter.stderrTail.suffix(1200))") }
            try output.synchronize()
            try checkDestination()
        } catch {
            exporter.cancel(); compressor.cancel()
            _ = try? await exporter.wait(); _ = try? await compressor.wait()
            try Task.checkCancellation()
            if error is ArchiveError { throw error }
            throw ArchiveError.failed("The archive could not be written. Check the free space, permissions and destination drive.")
        }
        let archiveBytes = UInt64((try metadata(partial)).st_size)
        report(.verifying, 0, 0, archiveBytes)
        _ = try await ArchiveVerifier.verify(url: partial, expectedBottleName: request.bottle.name) { fraction in
            report(.verifying, fraction, UInt64(Double(archiveBytes) * fraction), archiveBytes)
        }
        try Task.checkCancellation()
        try checkDestination()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HHmmss"
        var name = request.bottle.name
        while name.utf8.count > 180 { name.removeLast() }
        let stem = name + " " + formatter.string(from: started)
        var final: URL
        var index = 0
        while true {
            final = destination.appendingPathComponent(stem + (index == 0 ? "" : " \(index)") + ".cxarchive")
            if renamex_np(partial.path, final.path, UInt32(RENAME_EXCL)) == 0 { break }
            guard errno == EEXIST else { throw ArchiveError.unavailableDestination }
            index += 1
        }
        published = true
        report(.completed, 1, processed, archiveBytes, 0)
        return ArchiveResult(archiveURL: final, compression: request.compression, sourceBytes: snapshot.logicalBytes, archiveBytes: archiveBytes, elapsedSeconds: Date().timeIntervalSince(started), verified: true)
    }
}
