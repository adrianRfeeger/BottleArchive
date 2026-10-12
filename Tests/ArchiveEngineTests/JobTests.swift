import Foundation
import Testing
import Darwin
@testable import ArchiveEngine
struct JobTests {
 @Test func publishesOnlyVerifiedArchiveAndPreservesOld() async throws {let f=try Fixture();defer{f.clean()};try f.write("drive_c/data",Data(repeating:1,count:100_000));let old=f.destination.appendingPathComponent("old.cxarchive");try Data("existing".utf8).write(to:old);let app=try fakeCrossOver(f);let s=try await BottleScanner.scan(f.bottle);var result:ArchiveResult?;for try await e in ArchiveJob().start(request:requestFor(f,app:app),snapshot:s){if case .completed(let r)=e{result=r}};#expect(result?.verified == true);#expect(result?.archiveURL.pathExtension == "cxarchive");#expect(try Data(contentsOf:old) == Data("existing".utf8));#expect(try FileManager.default.contentsOfDirectory(atPath:f.destination.path).filter{$0.hasSuffix("partial")}.isEmpty)}
 @Test func exporterFailureDoesNotPublish() async throws {let f=try Fixture();defer{f.clean()};let app=try fakeCrossOver(f,exporterBody:"echo broken >&2; exit 7");let s=try await BottleScanner.scan(f.bottle);await #expect(throws:ArchiveError.self){for try await _ in ArchiveJob().start(request:requestFor(f,app:app),snapshot:s){}};#expect(try FileManager.default.contentsOfDirectory(atPath:f.destination.path).isEmpty)}
 @Test func compressorFailureDoesNotPublish() async throws {let f=try Fixture();defer{f.clean()};let app=try fakeCrossOver(f);let s=try await BottleScanner.scan(f.bottle);await #expect(throws:ArchiveError.self){for try await _ in ArchiveJob(gzip:URL(fileURLWithPath:"/usr/bin/false")).start(request:requestFor(f,app:app),snapshot:s){}};#expect(try FileManager.default.contentsOfDirectory(atPath:f.destination.path).isEmpty)}
 @Test func cancellationAndSecondStart() async throws {let f=try Fixture();defer{f.clean()};let app=try fakeCrossOver(f,exporterBody:"sleep 30");let s=try await BottleScanner.scan(f.bottle);let job=ArchiveJob();let stream=job.start(request:requestFor(f,app:app),snapshot:s);await #expect(throws:ArchiveError.self){for try await _ in job.start(request:requestFor(f,app:app),snapshot:s){}};job.cancel();await #expect(throws:CancellationError.self){for try await _ in stream{}};#expect(try FileManager.default.contentsOfDirectory(atPath:f.destination.path).isEmpty)}
 @Test func missingDestinationFails() async throws {let f=try Fixture();defer{f.clean()};let app=try fakeCrossOver(f);let s=try await BottleScanner.scan(f.bottle);try FileManager.default.removeItem(at:f.destination);await #expect(throws:ArchiveError.self){for try await _ in ArchiveJob().start(request:requestFor(f,app:app),snapshot:s){}}}
 @Test func compressorFailureStopsPausedExporter() async throws {
  let f = try Fixture(); defer { f.clean() }
  let app = try fakeCrossOver(f, exporterBody: "sleep 30")
  let snapshot = try await BottleScanner.scan(f.bottle)
  let job = ArchiveJob(gzip: URL(fileURLWithPath: "/usr/bin/false"))
  let timeout = Task {
   do { try await Task.sleep(nanoseconds: 2_000_000_000); job.cancel() } catch {}
  }
  defer { timeout.cancel(); job.cancel() }
  let started = Date()
  await #expect(throws: ArchiveError.self) {
   for try await _ in job.start(request: requestFor(f, app: app), snapshot: snapshot) {}
  }
  #expect(Date().timeIntervalSince(started) < 1.5)
  #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path).isEmpty)
 }

 @Test func destinationReplacementDuringExportDoesNotPublishOrTouchOtherFiles() async throws {
  let f = try Fixture(); defer { f.clean() }
  let app = try fakeCrossOver(f, exporterBody: "echo $$ > \"$CX_BOTTLE_PATH/exporter.pid\"; /usr/bin/tar -cf \"$CX_BOTTLE_PATH/export-test.tar\" -C \"$CX_BOTTLE_PATH\" \"$2\"; /bin/dd if=\"$CX_BOTTLE_PATH/export-test.tar\" bs=512 count=1 2>/dev/null; sleep 1; exec /bin/dd if=\"$CX_BOTTLE_PATH/export-test.tar\" bs=512 skip=1 2>/dev/null")
  let snapshot = try await BottleScanner.scan(f.bottle)
  let old = f.destination.appendingPathComponent("existing.cxarchive")
  let preserved = Data("preserve existing".utf8)
  try preserved.write(to: old)
  let detached = f.root.appendingPathComponent("detached archives")
  let sentinel = f.destination.appendingPathComponent("unrelated.txt")
  var replaced = false
  let started = Date()
  await #expect(throws: ArchiveError.unavailableDestination) {
   for try await event in ArchiveJob().start(request: requestFor(f, app: app), snapshot: snapshot) {
    if case .progress(let progress) = event, progress.stage == .archiving, !replaced {
     try FileManager.default.moveItem(at: f.destination, to: detached)
     try FileManager.default.createDirectory(at: f.destination, withIntermediateDirectories: true)
     try preserved.write(to: sentinel)
     replaced = true
    }
   }
  }
  #expect(replaced)
  #expect(Date().timeIntervalSince(started) < 3)
  let exporterPID = try #require(Int32(String(contentsOf: f.root.appendingPathComponent("exporter.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
  #expect(kill(exporterPID, 0) == -1 && errno == ESRCH)
  #expect(try Data(contentsOf: detached.appendingPathComponent("existing.cxarchive")) == preserved)
  #expect(try Data(contentsOf: sentinel) == preserved)
  #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path) == ["unrelated.txt"])
 }

}
