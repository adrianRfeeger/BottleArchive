import Foundation
public struct CrossOverInstallation: Sendable {
    public let app: URL
    public var root: URL { app.appendingPathComponent("Contents/SharedSupport/CrossOver") }
    public var exporter: URL { root.appendingPathComponent("bin/cxbottle") }
    public var wine: URL { root.appendingPathComponent("bin/wine") }
    public init(app: URL) { self.app = app }
    public static func locate() -> URL? {
        let candidates = [URL(fileURLWithPath: "/Applications/CrossOver.app"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/CrossOver.app")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: CrossOverInstallation(app: $0).exporter.path) }
    }
    public func environment(for bottle: Bottle) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CX_BOTTLE_LOCKED")
        env["CX_BOTTLE_PATH"] = bottle.url.deletingLastPathComponent().path
        env["WINEPREFIX"] = bottle.url.path
        env["CX_BOTTLE"] = bottle.name
        env["CX_ROOT"] = root.path
        return env
    }
    public func isRunning(_ bottle: Bottle) async throws -> Bool {
        guard FileManager.default.isExecutableFile(atPath: wine.path), FileManager.default.isExecutableFile(atPath: exporter.path) else {
            throw ArchiveError.failed("Choose an installed CrossOver app before creating an archive.")
        }
        let probe = try OwnedProcess.spawn(executable: wine, arguments: ["--no-lock", "--bottle", bottle.name, "--ux-app", "wineserver", "-k0"], environment: environment(for: bottle))
        defer { try? probe.stdoutHandle?.close() }
        let status = try await probe.wait()
        if status == 0 { return true }
        guard status == 1 else { throw ArchiveError.failed("CrossOver could not check whether the bottle is running. Open CrossOver and close the bottle's applications, then try again.") }
        return false
    }
}
