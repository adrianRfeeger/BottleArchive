import Foundation
import Testing
@testable import ArchiveEngine
func makeArchive(_ f:Fixture,additionalRoots:[String]=[]) throws -> URL {
 let u=f.destination.appendingPathComponent(UUID().uuidString+".cxarchive")
 let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/tar");p.arguments=["-czf",u.path,"-C",f.root.path,f.bottle.name]+additionalRoots;p.environment=ProcessInfo.processInfo.environment.merging(["COPYFILE_DISABLE":"1"]){_,new in new};try p.run();p.waitUntilExit();guard p.terminationStatus==0 else{throw ArchiveError.failed("fixture tar failed")};return u
}
struct VerifierTests {
 @Test func validArchiveWithUnicodeAndExternalLink() async throws {let f=try Fixture();defer{f.clean()};try f.write("drive_c/"+String(repeating:"é",count:80)+"/data.txt",Data("payload".utf8));try FileManager.default.createSymbolicLink(at:f.bottle.url.appendingPathComponent("external"),withDestinationURL:f.destination);let u=try makeArchive(f);let r=try await ArchiveVerifier.verify(url:u,expectedBottleName:f.bottle.name,progress:{_ in});#expect(r.entryCount >= 5);#expect(r.verifiedBytes > 0)}
 @Test func rejectsTruncatedAndCorrupt() async throws {let f=try Fixture();defer{f.clean()};let u=try makeArchive(f);let d=try Data(contentsOf:u);try d.prefix(d.count/2).write(to:u);await #expect(throws:ArchiveError.self){try await ArchiveVerifier.verify(url:u,expectedBottleName:f.bottle.name,progress:{_ in})};var corrupted=d;corrupted[corrupted.count-8] ^= 255;try corrupted.write(to:u);await #expect(throws:ArchiveError.self){try await ArchiveVerifier.verify(url:u,expectedBottleName:f.bottle.name,progress:{_ in})}}
 @Test func rejectsMissingConfigAndExtraRoot() async throws {let f=try Fixture();defer{f.clean()};try FileManager.default.removeItem(at:f.bottle.url.appendingPathComponent("cxbottle.conf"));let u=try makeArchive(f);await #expect(throws:ArchiveError.self){try await ArchiveVerifier.verify(url:u,expectedBottleName:f.bottle.name,progress:{_ in})};try f.write("cxbottle.conf",Data("config".utf8));try Data("other".utf8).write(to:f.root.appendingPathComponent("other"));let v=try makeArchive(f,additionalRoots:["other"]);await #expect(throws:ArchiveError.self){try await ArchiveVerifier.verify(url:v,expectedBottleName:f.bottle.name,progress:{_ in})}}
 @Test func cancellation() async throws {let f=try Fixture();defer{f.clean()};let u=try makeArchive(f);let t=Task{try await ArchiveVerifier.verify(url:u,expectedBottleName:f.bottle.name,progress:{_ in})};t.cancel();await #expect(throws:CancellationError.self){try await t.value}}
}
