import Foundation
import Testing
@testable import ArchiveEngine
struct ParallelCompressionTests {
 @Test func automaticLeavesTwoCoresAndClampsManualCounts() {
  #expect(CompressionThreads.resolved(0, processorCount: 18) == 16)
  #expect(CompressionThreads.resolved(0, processorCount: 2) == 2)
  #expect(CompressionThreads.resolved(100, processorCount: 18) == 18)
  #expect(CompressionThreads.resolved(-10, processorCount: 18) == 16)
  #expect(CompressionThreads.resolved(4, processorCount: 18) == 4)
 }
 @Test func parallelToolReceivesExplicitThreadsAndGzipStaysCompatible() {
  let parallel = CompressionTool(executable: URL(fileURLWithPath: "/pigz"), supportsThreads: true)
  #expect(parallel.arguments(level: 9, threads: 0, processorCount: 18) == ["-n", "-9", "-c", "-p", "16"])
  let system = CompressionTool(executable: URL(fileURLWithPath: "/usr/bin/gzip"), supportsThreads: false)
  #expect(system.arguments(level: 6, threads: 8) == ["-n", "-6", "-c"])
 }
 @Test func jobPassesSelectedThreadsToParallelCompressor() async throws {
  let f = try Fixture(); defer { f.clean() }
  let app = try fakeCrossOver(f)
  let helper = f.root.appendingPathComponent("pigz")
  let arguments = f.root.appendingPathComponent("compression.args")
  let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"\(arguments.path)\"\nexec /usr/bin/gzip \"$1\" \"$2\" \"$3\"\n"
  try Data(script.utf8).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
  let snapshot = try await BottleScanner.scan(f.bottle)
  let request = ArchiveRequest(bottle: f.bottle, destination: f.destination, compression: .maximum, crossOverApp: app, threads: 4)
  var completed = false
  for try await event in ArchiveJob(parallelGzip: helper).start(request: request, snapshot: snapshot) {
   if case .completed(let result) = event { completed = result.verified }
  }
  #expect(completed)
  #expect(try String(contentsOf: arguments, encoding: .utf8).split(separator: "\n").map(String.init) == ["-n", "-9", "-c", "-p", "4"])
 }

}
