import AppKit
import Foundation
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let set=output.appendingPathComponent("BottleArchive.iconset")
try FileManager.default.createDirectory(at:set,withIntermediateDirectories:true)
func image(_ size:Int)->Data {
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
 let s=CGFloat(size),rect=NSRect(x:s*0.07,y:s*0.07,width:s*0.86,height:s*0.86)
 let shape=NSBezierPath(roundedRect:rect,xRadius:s*0.2,yRadius:s*0.2)
 let gradient=NSGradient(starting:NSColor(red:0.69,green:0.49,blue:0.93,alpha:1),ending:NSColor(red:0.42,green:0.26,blue:0.74,alpha:1))!
 gradient.draw(in:shape,angle:-65)
 let symbol=NSImage(systemSymbolName:"archivebox.fill",accessibilityDescription:nil)!.withSymbolConfiguration(.init(pointSize:s*0.5,weight:.medium))!
 let white=NSImage(size:symbol.size);white.lockFocus();NSColor.white.set();NSRect(origin:.zero,size:symbol.size).fill();symbol.draw(at:.zero,from:.zero,operation:.destinationIn,fraction:1);white.unlockFocus()
 white.draw(in:NSRect(x:s*0.22,y:s*0.24,width:s*0.56,height:s*0.51))
 NSGraphicsContext.restoreGraphicsState()
 return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512]{try image(size).write(to:set.appendingPathComponent("icon_\(size)x\(size).png"));try image(size*2).write(to:set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))}
let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");p.arguments=["-c","icns",set.path,"-o",output.appendingPathComponent("BottleArchive.icns").path];try p.run();p.waitUntilExit();if p.terminationStatus != 0{exit(1)}
