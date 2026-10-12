import Foundation
import Darwin
import ProcessSupport

public final class OwnedProcess: @unchecked Sendable {
    public let pid: Int32
    public let stdoutHandle: FileHandle?
    private let condition = NSCondition()
    private var exitStatus: Int32?
    private var errorData = Data()
    private var errorsFinished = false
    private var didCancel = false
    public var stderrTail: String {
        condition.lock(); defer { condition.unlock() }
        return String(decoding: errorData, as: UTF8.self)
    }
    private init(pid: Int32, output: FileHandle?, errors: FileHandle) {
        self.pid = pid; self.stdoutHandle = output
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? errors.close()
                self.condition.lock(); self.errorsFinished = true; self.condition.broadcast(); self.condition.unlock()
            }
            while let chunk = try? errors.read(upToCount: 8192), !chunk.isEmpty {
                self.condition.lock()
                self.errorData.append(chunk)
                if self.errorData.count > 65536 { self.errorData = self.errorData.suffix(65536) }
                self.condition.unlock()
            }
        }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 255
            _ = ps_wait(pid, &status)
            // A finished owner must not leave descendants holding its pipe ends open.
            kill(-pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                if kill(-pid, 0) == 0 { kill(-pid, SIGKILL) }
            }
            self.condition.lock(); self.exitStatus = status; self.condition.broadcast(); self.condition.unlock()
        }
    }
    public static func spawn(executable: URL, arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
                             stdin: Int32? = nil, stdout: Int32? = nil) throws -> OwnedProcess {
        ps_ignore_sigpipe()
        func makePipe() throws -> (FileHandle, FileHandle) {
            var fds: [Int32] = [0, 0]
            guard pipe(&fds) == 0 else { throw ArchiveError.failed("A pipe could not be created.") }
            for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
            return (FileHandle(fileDescriptor: fds[0], closeOnDealloc: true), FileHandle(fileDescriptor: fds[1], closeOnDealloc: true))
        }
        let errors = try makePipe()
        let output = stdout == nil ? try makePipe() : nil
        let null = stdin == nil ? try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null")) : nil
        defer { try? errors.1.close(); try? output?.1.close(); try? null?.close() }
        var argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        var envp = environment.sorted(by: { $0.key < $1.key }).map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for v in argv { free(v) }; for v in envp { free(v) } }
        var pid: Int32 = 0
        let code = argv.withUnsafeMutableBufferPointer { av in
            envp.withUnsafeMutableBufferPointer { ev in
                ps_spawn(executable.path, av.baseAddress, ev.baseAddress, stdin ?? null!.fileDescriptor,
                         stdout ?? output!.1.fileDescriptor, errors.1.fileDescriptor, &pid)
            }
        }
        guard code == 0 else {
            try? errors.0.close(); try? output?.0.close()
            throw ArchiveError.failed("Could not start \(executable.lastPathComponent): \(String(cString: strerror(code))).")
        }
        return OwnedProcess(pid: pid, output: output?.0, errors: errors.0)
    }
    public func wait() async throws -> Int32 {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    self.condition.lock()
                    while self.exitStatus == nil || !self.errorsFinished { self.condition.wait() }
                    let status = self.exitStatus!
                    self.condition.unlock()
                    continuation.resume(returning: status)
                }
            }
        }, onCancel: { self.cancel() })
    }
    public func cancel() {
        condition.lock()
        if didCancel { condition.unlock(); return }
        didCancel = true
        let finished = exitStatus != nil && errorsFinished
        condition.unlock()
        guard !finished else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if kill(-self.pid, 0) == 0 { kill(-self.pid, SIGKILL) }
        }
    }
}
