import Foundation
import Darwin
import Testing
@testable import ArchiveEngine
struct OwnedProcessTests {
 @Test func reportsStatusAndErrors() async throws {let p=try OwnedProcess.spawn(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","echo failure >&2; exit 7"]);let code=try await p.wait();#expect(code == 7);#expect(p.stderrTail.contains("failure"))}
 @Test func boundsErrorCapture() async throws {let p=try OwnedProcess.spawn(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","/usr/bin/yes issue | /usr/bin/head -c 100000 >&2"]);_ = try await p.wait();#expect(p.stderrTail.utf8.count <= 65536);#expect(!p.stderrTail.isEmpty)}
 @Test func cancellationKillsOnlyOwnedGroup() async throws {let unrelated=Process();unrelated.executableURL=URL(fileURLWithPath:"/bin/sleep");unrelated.arguments=["30"];try unrelated.run();defer{unrelated.terminate()};let p=try OwnedProcess.spawn(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","sleep 30 & wait"]);#expect(p.pid > 0);p.cancel();let code=try await p.wait();#expect(code != 0);#expect(unrelated.isRunning);#expect(kill(p.pid,0) != 0)}
 @Test func nonexistentExecutable() {#expect(throws:ArchiveError.self){try OwnedProcess.spawn(executable:URL(fileURLWithPath:"/no/such/program"),arguments:[])}}
 @Test func closesOrphanPipes() async throws {let p=try OwnedProcess.spawn(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","sleep 30 & exit 3"]);let began=Date();#expect(try await p.wait() == 3);#expect(Date().timeIntervalSince(began) < 3)}
}
