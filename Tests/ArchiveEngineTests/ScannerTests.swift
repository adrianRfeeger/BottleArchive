import Foundation
import Testing
@testable import ArchiveEngine
struct ScannerTests {
 @Test func countsFilesButDoesNotFollowLinks() async throws { let f=try Fixture(); defer {f.clean()};try f.write("drive_c/data",Data(repeating:42,count:4096));try f.write("desktopdata/ignored",Data(repeating:0,count:8000));try FileManager.default.createSymbolicLink(at:f.bottle.url.appendingPathComponent("drive_c/external"),withDestinationURL:f.destination); let s=try await BottleScanner.scan(f.bottle);let c=try Data(contentsOf:f.bottle.url.appendingPathComponent("cxbottle.conf"));#expect(s.logicalBytes == UInt64(4096+c.count));#expect(s.externalLinks.count == 1);#expect(s.files.count == 2) }
 @Test func countsHardLinksOnce() async throws {let f=try Fixture();defer{f.clean()};try f.write("one",Data(repeating:1,count:100));try FileManager.default.linkItem(at:f.bottle.url.appendingPathComponent("one"),to:f.bottle.url.appendingPathComponent("two"));let s=try await BottleScanner.scan(f.bottle);#expect(s.logicalBytes == UInt64(100 + (try Data(contentsOf:f.bottle.url.appendingPathComponent("cxbottle.conf"))).count))}
 @Test func rejectsMissingConfiguration() async throws {let f=try Fixture();defer{f.clean()};try FileManager.default.removeItem(at:f.bottle.url.appendingPathComponent("cxbottle.conf"));await #expect(throws:ArchiveError.self){try await BottleScanner.scan(f.bottle)}}
 @Test func cancellation() async throws {let f=try Fixture();defer{f.clean()};let t=Task {try Task.checkCancellation();return try await BottleScanner.scan(f.bottle)};t.cancel();await #expect(throws:CancellationError.self){try await t.value}}
}
struct DiscoveryTests {
 @Test func findsCustomBottle() throws {let f=try Fixture();defer{f.clean()};let b=try BottleDiscovery.discover(home:f.root,configuredRoots:[f.root,f.root]);#expect(b == [f.bottle])}
 @Test func rejectsDestinationSymlinkIntoBottle() throws {let f=try Fixture();defer{f.clean()};let l=f.root.appendingPathComponent("inside");try FileManager.default.createSymbolicLink(at:l,withDestinationURL:f.bottle.url);#expect(throws:ArchiveError.self){try ArchivePreflight.validate(bottle:f.bottle,destination:l)}}
}
