import AppKit
import Foundation
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 48, y: 48, width: 928, height: 928)
let shape = NSBezierPath(roundedRect: rect, xRadius: 214, yRadius: 214)
NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.10, alpha: 1))!.draw(in: shape, angle: -80)
let colors: [NSColor] = [.init(calibratedRed: 0.43, green: 0.79, blue: 0.68, alpha: 1), .init(calibratedRed: 0.74, green: 0.77, blue: 0.85, alpha: 1), .init(calibratedRed: 0.89, green: 0.66, blue: 0.51, alpha: 1), .init(calibratedRed: 0.69, green: 0.64, blue: 0.95, alpha: 1)]
for (i,h) in [230.0,410,320,510].enumerated() {
 colors[i].setFill()
 NSBezierPath(roundedRect: NSRect(x: 244 + Double(i)*144, y: 257, width: 102, height: h), xRadius: 51, yRadius: 51).fill()
}
image.unlockFocus()
let base = NSBitmapImageRep(data: image.tiffRepresentation!)!
var entries: [[String: String]] = []
for size in [16,32,128,256,512] {
 for scale in [1,2] {
  let pixels=size*scale
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
  NSGraphicsContext.current?.imageInterpolation = .high
  NSImage(cgImage:base.cgImage!,size:NSSize(width:1024,height:1024)).draw(in:NSRect(x:0,y:0,width:pixels,height:pixels))
  NSGraphicsContext.restoreGraphicsState()
  let name="icon-\(size)@\(scale)x.png"
  try bitmap.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(name))
  entries.append(["idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x","filename":name])
 }
}
try JSONSerialization.data(withJSONObject:["images":entries,"info":["author":"xcode","version":1]],options:.prettyPrinted).write(to:destination.appendingPathComponent("Contents.json"))
