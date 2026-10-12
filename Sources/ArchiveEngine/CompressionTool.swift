import Foundation
import ProcessSupport

public enum CompressionThreads {
    public static func resolved(_ requested: Int, processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> Int {
        let available = max(1, processorCount)
        return requested <= 0 ? (available > 2 ? available - 2 : available) : min(available, requested)
    }
}

public struct CompressionTool: Sendable {
    public let executable: URL
    public let supportsThreads: Bool
    public init(executable: URL, supportsThreads: Bool) { self.executable = executable; self.supportsThreads = supportsThreads }
    public static func locate(bundleURL: URL = Bundle.main.bundleURL, executableURL: URL? = nil) -> CompressionTool {
        let executableDirectory = (executableURL ?? runningExecutableURL()).deletingLastPathComponent()
        let packaged = bundleURL.appendingPathComponent("Contents/Helpers/pigz")
        let development = executableDirectory.appendingPathComponent("pigz")
        var candidates = [packaged, development]
        if executableDirectory.lastPathComponent == "MacOS", executableDirectory.deletingLastPathComponent().lastPathComponent == "Contents" {
            candidates.insert(executableDirectory.deletingLastPathComponent().appendingPathComponent("Helpers/pigz"), at: 0)
        }
        if let helper = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return CompressionTool(executable: helper, supportsThreads: true)
        }
        return CompressionTool(executable: URL(fileURLWithPath: "/usr/bin/gzip"), supportsThreads: false)
    }
    private static func runningExecutableURL() -> URL {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = buffer.withUnsafeMutableBufferPointer { ps_executable_path($0.baseAddress, UInt32($0.count)) }
        return URL(fileURLWithPath: length > 0 ? String(cString: buffer) : CommandLine.arguments[0])
    }
    public func arguments(level: Int, threads: Int, processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> [String] {
        let base = ["-n", "-\(level)", "-c"]
        return supportsThreads ? base + ["-p", String(CompressionThreads.resolved(threads, processorCount: processorCount))] : base
    }
}
