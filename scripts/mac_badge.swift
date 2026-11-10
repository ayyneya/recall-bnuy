// Draws app/Resources/Discord/MacBadge.png, the Discord card's Mac badge: Apple's logo (the system font's U+F8FF), dark on a
// light circle and nearly filling it, as the design's card shows its Mac badge. Discord loads it from the repository's
// main branch and crops it round; Settings › Discord shows the app's own copy.
//   swift scripts/mac_badge.swift app/Resources/Discord/MacBadge.png
import AppKit
let size:CGFloat=512
let font=NSFont.systemFont(ofSize:size) as CTFont
var glyph=CGGlyph(0)
var character:UniChar=0xF8FF
guard CTFontGetGlyphsForCharacters(font,&character,&glyph,1),let logo=CTFontCreatePathForGlyph(font,glyph,nil) else { fatalError("no Apple logo in the system font") }
// Points along the logo's outline, to find how far it reaches from its middle.
var points:[CGPoint]=[]
logo.applyWithBlock { element in
    let e=element.pointee,p=e.points,from=points.last ?? .zero
    func along(_ point:(CGFloat)->CGPoint) { points+=stride(from:0.05,through:1,by:0.05).map(point) }
    switch e.type {
    case .moveToPoint,.addLineToPoint: points.append(p[0])
    case .addQuadCurveToPoint:
        along { t in let u=1-t;return CGPoint(x:u*u*from.x+2*u*t*p[0].x+t*t*p[1].x,y:u*u*from.y+2*u*t*p[0].y+t*t*p[1].y) }
    case .addCurveToPoint:
        along { t in let u=1-t;return CGPoint(x:u*u*u*from.x+3*u*u*t*p[0].x+3*u*t*t*p[1].x+t*t*t*p[2].x,
                                              y:u*u*u*from.y+3*u*u*t*p[0].y+3*u*t*t*p[1].y+t*t*t*p[2].y) }
    default: break
    }
}
let g=CGContext(data:nil,width:Int(size),height:Int(size),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
g.setFillColor(CGColor(srgbRed:240/255,green:240/255,blue:242/255,alpha:1));g.fillEllipse(in:CGRect(x:0,y:0,width:size,height:size))
// The logo in the circle's middle, its farthest point 92% of the way to the edge.
let bounds=logo.boundingBoxOfPath,center=CGPoint(x:bounds.midX,y:bounds.midY)
let reach=points.map { hypot($0.x-center.x,$0.y-center.y) }.max()!,scale=size/2*0.92/reach
g.translateBy(x:size/2,y:size/2);g.scaleBy(x:scale,y:scale);g.translateBy(x:-center.x,y:-center.y)
g.addPath(logo);g.setFillColor(CGColor(srgbRed:23/255,green:24/255,blue:27/255,alpha:1));g.fillPath()
let png=NSBitmapImageRep(cgImage:g.makeImage()!).representation(using:.png,properties:[:])!
try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
