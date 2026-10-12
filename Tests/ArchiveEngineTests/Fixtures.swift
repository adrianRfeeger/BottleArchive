import Foundation
import ArchiveEngine
struct Fixture {
 let root: URL; let bottle: Bottle; let destination: URL
 init() throws { root=FileManager.default.temporaryDirectory.appendingPathComponent("BottleArchiveTest-"+UUID().uuidString); let u=root.appendingPathComponent("Test bottle é"); bottle=Bottle(url:u); destination=root.appendingPathComponent("archives"); try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true); try Data("[Bottle]\n".utf8).write(to:u.appendingPathComponent("cxbottle.conf")) }
 func write(_ name:String,_ data:Data) throws {let u=bottle.url.appendingPathComponent(name);try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:u)}
 func clean(){try? FileManager.default.removeItem(at:root)}
}

func fakeCrossOver(_ fixture:Fixture, exporterBody:String="exec /usr/bin/tar -cf - --exclude=\"$2/desktopdata\" --exclude=\"$2/files\" -C \"$CX_BOTTLE_PATH\" \"$2\"") throws -> URL {
 let app=fixture.root.appendingPathComponent("CrossOver.app"),bin=app.appendingPathComponent("Contents/SharedSupport/CrossOver/bin")
 try FileManager.default.createDirectory(at:bin,withIntermediateDirectories:true)
 for (name,body) in [("cxbottle",exporterBody),("wine","exit 1")]{let u=bin.appendingPathComponent(name);try Data(("#!/bin/sh\n"+body+"\n").utf8).write(to:u);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:u.path)}
 return app
}
func requestFor(_ f:Fixture,app:URL) -> ArchiveRequest {ArchiveRequest(bottle:f.bottle,destination:f.destination,compression:.fast,crossOverApp:app)}
