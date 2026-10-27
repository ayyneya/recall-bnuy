// Pawpad's placeholder artwork: a white paw print on Aniimo's sea-and-sky blue, as a square
// 1024-pixel PNG for scripts/app_icon.swift to package. Replace with final artwork when there is some.
import AppKit
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let side=1024
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:side,pixelsHigh:side,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let bounds=NSRect(x:0,y:0,width:side,height:side)
NSGradient(colors:[NSColor(calibratedRed:0.47,green:0.80,blue:1.0,alpha:1),NSColor(calibratedRed:0.10,green:0.45,blue:0.85,alpha:1)])!.draw(in:bounds,angle:-90)
// A band of sunlight, the yellow of Aniimo's Install button.
NSColor(calibratedRed:1.0,green:0.82,blue:0.12,alpha:0.9).setFill()
NSBezierPath(ovalIn:NSRect(x:612,y:640,width:300,height:300)).fill()
let configuration=NSImage.SymbolConfiguration(pointSize:560,weight:.bold).applying(.init(paletteColors:[.white]))
if let paw=NSImage(systemSymbolName:"pawprint.fill",accessibilityDescription:nil)?.withSymbolConfiguration(configuration) {
    let size=paw.size,origin=NSPoint(x:(CGFloat(side)-size.width)/2,y:(CGFloat(side)-size.height)/2-30)
    NSGraphicsContext.current?.cgContext.setShadow(offset:CGSize(width:0,height:-14),blur:36,color:NSColor(calibratedWhite:0,alpha:0.28).cgColor)
    paw.draw(in:NSRect(origin:origin,size:size))
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
