import Foundation

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
    public static func locate() -> CompressionTool {
        let packaged = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/pigz")
        let development = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("pigz")
        if let helper = [packaged, development].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return CompressionTool(executable: helper, supportsThreads: true)
        }
        return CompressionTool(executable: URL(fileURLWithPath: "/usr/bin/gzip"), supportsThreads: false)
    }
    public func arguments(level: Int, threads: Int, processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> [String] {
        let base = ["-n", "-\(level)", "-c"]
        return supportsThreads ? base + ["-p", String(CompressionThreads.resolved(threads, processorCount: processorCount))] : base
    }
}
