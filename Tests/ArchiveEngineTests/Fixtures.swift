import Foundation
import ArchiveEngine
struct Fixture {
 let root: URL; let bottle: Bottle; let destination: URL
 init() throws { root=FileManager.default.temporaryDirectory.appendingPathComponent("BottleArchiveTest-"+UUID().uuidString); let u=root.appendingPathComponent("Test bottle é"); bottle=Bottle(url:u); destination=root.appendingPathComponent("archives"); try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true); try Data("[Bottle]\n".utf8).write(to:u.appendingPathComponent("cxbottle.conf")) }
 func write(_ name:String,_ data:Data) throws {let u=bottle.url.appendingPathComponent(name);try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:u)}
 func clean(){try? FileManager.default.removeItem(at:root)}
}
