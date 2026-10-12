import Foundation
import CryptoKit
import Testing
@testable import ArchiveEngine
@Suite(.serialized) struct CrossOverRoundTripTests {
 @Test(.enabled(if:ProcessInfo.processInfo.environment["BOTTLE_ARCHIVE_INTEGRATION"] == "1"))
 func restoresAllCompressionLevels() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("BottleArchive-CrossOver-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:root)}
  let app=try #require(CrossOverInstallation.locate());let install=CrossOverInstallation(app:app)
  let bottle=Bottle(url:root.appendingPathComponent("Fixture Bottle é"))
  func run(_ executable:URL,_ args:[String],env:[String:String]) async throws -> Int32 {let p=try OwnedProcess.spawn(executable:executable,arguments:args,environment:env);defer{try? p.stdoutHandle?.close()};let status=try await p.wait();if status != 0{print(p.stderrTail)};return status}
  var env=install.environment(for:bottle)
  #expect(try await run(install.exporter,["--bottle",bottle.name,"--create","--template","win10_64"],env:env) == 0)
  let target=bottle.url.appendingPathComponent("drive_c/Fixture/"+String(repeating:"é",count:70)+"/payload.bin")
  try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
  let data=Data((0..<60000).map{UInt8($0 % 251)});try data.write(to:target)
  try FileManager.default.setAttributes([.posixPermissions:0o640],ofItemAtPath:target.path)
  let empty=target.deletingLastPathComponent().appendingPathComponent("empty");try Data().write(to:empty)
  let link=bottle.url.appendingPathComponent("drive_c/external-fixture")
  try FileManager.default.createSymbolicLink(at:link,withDestinationURL:root)
  // The fixture's Wine server is ours; stop it before export, never another bottle.
  _ = try await run(install.wine,["--bottle",bottle.name,"--ux-app","wineserver","-k"],env:env)
  _ = try await run(install.wine,["--bottle",bottle.name,"--ux-app","wineserver","-w"],env:env)
  let output=root.appendingPathComponent("archives");try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  let snapshot=try await BottleScanner.scan(bottle)
  for compression in CompressionPreset.allCases {
   var result:ArchiveResult?
   let request=ArchiveRequest(bottle:bottle,destination:output,compression:compression,crossOverApp:app)
   for try await event in ArchiveJob().start(request:request,snapshot:snapshot){if case .completed(let value)=event{result=value}}
   let archive=try #require(result?.archiveURL)
   let restoreRoot=root.appendingPathComponent("restore-"+compression.rawValue);try FileManager.default.createDirectory(at:restoreRoot,withIntermediateDirectories:true)
   env=install.environment(for:Bottle(url:restoreRoot.appendingPathComponent("Restored Bottle")))
   #expect(try await run(install.exporter,["--bottle","Restored Bottle","--restore",archive.path],env:env) == 0)
   let restored=restoreRoot.appendingPathComponent("Restored Bottle")
   let relative=String(target.path.dropFirst(bottle.url.path.count)).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
   let restoredData=try Data(contentsOf:restored.appendingPathComponent(relative))
   #expect(SHA256.hash(data:restoredData) == SHA256.hash(data:data))
   let attributes=try FileManager.default.attributesOfItem(atPath:restored.appendingPathComponent(relative).path)
   #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
   #expect(try FileManager.default.destinationOfSymbolicLink(atPath:restored.appendingPathComponent("drive_c/external-fixture").path) == root.path)
   #expect(try Data(contentsOf:restored.appendingPathComponent(relative).deletingLastPathComponent().appendingPathComponent("empty")).isEmpty)
   #expect(FileManager.default.fileExists(atPath:restored.appendingPathComponent("cxbottle.conf").path))
   print("CrossOver restored \(compression.rawValue): \(archive.lastPathComponent), \(result!.archiveBytes) bytes")
  }
 }
}
