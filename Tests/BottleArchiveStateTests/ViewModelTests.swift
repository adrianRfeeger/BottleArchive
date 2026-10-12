import Foundation
import Combine
import Testing
import ArchiveEngine
@testable import AppState
struct ViewModelTests {
 @MainActor func model() -> ArchiveViewModel {ArchiveViewModel(defaults:UserDefaults(suiteName:UUID().uuidString)!,autoDiscover:false)}
 func bottle() throws -> Bottle {let u=FileManager.default.temporaryDirectory.appendingPathComponent("StateTest-"+UUID().uuidString);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true);try Data("[Bottle]".utf8).write(to:u.appendingPathComponent("cxbottle.conf"));try Data(repeating:0,count:500_000).write(to:u.appendingPathComponent("data"));return Bottle(url:u)}
 @MainActor func settle(_ model:ArchiveViewModel) async throws {for _ in 0..<500 {if !model.isEstimating{return};try await Task.sleep(for:.milliseconds(10))};Issue.record("estimate timed out")}
 @Test @MainActor func scansAndEstimatesSelection() async throws {let m=model();let b=try bottle();defer{try? FileManager.default.removeItem(at:b.url)};#expect(m.compression == .balanced);#expect(m.destination.path == "/Volumes/External/Crossover Archives");m.selectBottle(b);try await settle(m);#expect(m.snapshot?.bottle == b);#expect(m.estimate?.gzipLevel == 6)}
 @Test @MainActor func changedCompressionRejectsStaleResult() async throws {let m=model();let b=try bottle();defer{try? FileManager.default.removeItem(at:b.url)};m.selectBottle(b);m.setCompression(.fast);m.setCompression(.maximum);try await settle(m);#expect(m.compression == .maximum);#expect(m.estimate?.gzipLevel == 9)}
 @Test @MainActor func remembersDestinationAndCompression() throws {let d=UserDefaults(suiteName:UUID().uuidString)!;let m=ArchiveViewModel(defaults:d,autoDiscover:false);m.setCompression(.fast);m.setDestination(URL(fileURLWithPath:"/tmp/archives"));let restored=ArchiveViewModel(defaults:d,autoDiscover:false);#expect(restored.destination.path == "/tmp/archives");#expect(restored.compression == .fast)}
 @Test @MainActor func cancelledEstimateClearsBusyState() async throws {let m=model();let b=try bottle();defer{try? FileManager.default.removeItem(at:b.url)};m.selectBottle(b);m.cancel();try await Task.sleep(for:.milliseconds(50));#expect(!m.isEstimating);#expect(!m.isBusy);#expect(m.completedResult == nil)}
 @Test @MainActor func restoresCanonicalManualBottle() async throws {let b=try bottle();defer{try? FileManager.default.removeItem(at:b.url)};let alias=b.url.deletingLastPathComponent().appendingPathComponent("SavedAlias-"+UUID().uuidString);try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:b.url);defer{try? FileManager.default.removeItem(at:alias)};let d=UserDefaults(suiteName:UUID().uuidString)!;d.set(alias.path,forKey:"bottle");let m=ArchiveViewModel(defaults:d,autoDiscover:true);try await Task.sleep(for:.milliseconds(30));#expect(m.selectedBottle == b);m.cancel()}

 @Test @MainActor func publishesSelectionBeforeBottleOptions() async throws {let b=try bottle();defer{try? FileManager.default.removeItem(at:b.url)};let d=UserDefaults(suiteName:UUID().uuidString)!;d.set(b.url.path,forKey:"bottle");let m=ArchiveViewModel(defaults:d,autoDiscover:true);let subscription=m.$bottles.sink { values in if !values.isEmpty {#expect(m.selectedBottle == b)} };try await Task.sleep(for:.milliseconds(40));withExtendedLifetime(subscription){};m.cancel()}

 @Test @MainActor func unavailableDestinationAndBusyCancellation() async throws {let m=model();let b=try bottle();defer{try? FileManager.default.removeItem(at:b.url)};let out=b.url.deletingLastPathComponent().appendingPathComponent("Output-"+UUID().uuidString);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:out)};let app=out.appendingPathComponent("Fake.app"),bin=app.appendingPathComponent("Contents/SharedSupport/CrossOver/bin");try FileManager.default.createDirectory(at:bin,withIntermediateDirectories:true);for (n,body) in [("wine","exit 1"),("cxbottle","sleep 30")]{let u=bin.appendingPathComponent(n);try Data(("#!/bin/sh\n"+body+"\n").utf8).write(to:u);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:u.path)};m.selectBottle(b);try await settle(m);m.setDestination(out.appendingPathComponent("missing"));#expect(!m.canCreateArchive);m.setDestination(out);m.setCrossOver(app);#expect(m.canCreateArchive);m.createArchive();#expect(m.isBusy);#expect(!m.canCreateArchive);m.createArchive();m.cancel();for _ in 0..<500{if !m.isBusy{break};try await Task.sleep(for:.milliseconds(10))};#expect(!m.isBusy);#expect(m.completedResult == nil)}

 @Test @MainActor func remembersThreadsWithoutResampling() async throws {
  let d = UserDefaults(suiteName: UUID().uuidString)!
  let m = ArchiveViewModel(defaults: d, autoDiscover: false)
  let b = try bottle(); defer { try? FileManager.default.removeItem(at: b.url) }
  m.selectBottle(b); try await settle(m)
  let estimate = m.estimate?.estimatedBytes
  #expect(m.threads == 0)
  m.setThreads(4)
  #expect(m.threads == 4)
  #expect(!m.isEstimating && m.estimate?.estimatedBytes == estimate)
  let restored = ArchiveViewModel(defaults: d, autoDiscover: false)
  #expect(restored.threads == 4)
 }

}
