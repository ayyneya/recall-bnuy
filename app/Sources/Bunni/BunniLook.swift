import SwiftUI
import AppKit
import CoreText

// Bunni's own look, from the RecallBnuy Look design (its chosen options, November 27): Recall's layout and type in
// pastel pink, light and dark; the pink icon; the BUNNI sticker with its ears beside the name; the compact Josh card;
// what's different from Recall in About; Bunni's notes apart from Recall's in What's New. Recall's files only call in
// here, so a Recall update merges with few clashes.
enum Bunni {
    /// What's New's heading over Bunni's own notes ("From bunni").
    static let handle="bunni"
    /// Who makes Bunni, as About credits it: "bunni (pyxee)".
    static let author="\(handle) (pyxee)"
    /// The Recall release this build is based on: "1.6.7" of "1.6.7-bunni".
    static var base:String { String(UpdateCheck.installed.split(separator:"-").first ?? Substring(UpdateCheck.installed)) }
    static let fork=URL(string:"https://github.com/\(Brand.forkPath)")!
    /// Recall's Discord invite, in the Discord app when one is installed (discord://-/invite/<code>: the app opens the
    /// path in its own window, as Discord's desktop code does with any discord:// link), else in the browser.
    @MainActor static func openDiscordInvite() {
        if let app=URL(string:"discord://-/invite/\(Brand.discord.lastPathComponent)"),NSWorkspace.shared.urlForApplication(toOpen:app) != nil {
            NSWorkspace.shared.open(app)
        } else { NSWorkspace.shared.open(Brand.discord) }
    }

    // MARK: colours (the design's "Pastel" theme with the pink accent)

    private static func hex(_ value:UInt32,_ alpha:Double=1)->Color {
        Color(red:Double(value >> 16 & 255)/255,green:Double(value >> 8 & 255)/255,blue:Double(value & 255)/255).opacity(alpha)
    }
    private static func pick(_ scheme:ColorScheme,_ light:Color,_ dark:Color)->Color { scheme == .dark ? dark : light }
    /// The accent: buttons, the coffee cup, the update arrow, the glow (#FF5C93).
    static let accent=hex(0xFF5C93)
    /// The sticker's outline and strong pink fills (#D81B6A).
    static let tag=hex(0xD81B6A)
    static func ground(_ s:ColorScheme)->Color { pick(s,hex(0xFFF0F6),hex(0x1B1120)) }
    static func surface(_ s:ColorScheme)->Color { pick(s,hex(0xFFFAFD),hex(0x2A1A2F)) }
    /// Text, and its secondary level.
    static func ink(_ s:ColorScheme)->Color { pick(s,hex(0x4B1D38),hex(0xFFEEF5)) }
    static func secondary(_ s:ColorScheme)->Color { pick(s,hex(0x97607E),hex(0xCDA6BB)) }
    /// Pink as text and icons: headings, the tiles' icons, links (#C2185B on light, 5.6:1).
    static func pink(_ s:ColorScheme)->Color { pick(s,hex(0xC2185B),hex(0xFF8FB8)) }
    /// A soft pink card (What's different).
    static func soft(_ s:ColorScheme)->Color { pick(s,hex(0xFFE0EC),hex(0x47213A)) }
    static func hair(_ s:ColorScheme)->Color { pick(s,hex(0xD6508C,0.14),hex(0xFF96C3,0.13)) }
    /// A sunken panel (Recall's notes under Bunni's).
    static func well(_ s:ColorScheme)->Color { pick(s,hex(0xD6508C,0.08),Color.black.opacity(0.3)) }
    static func glow(_ s:ColorScheme)->Color { pick(s,hex(0xFF78AF,0.22),hex(0xFF5C93,0.13)) }
    /// The title bar: the surface with a little of the ground.
    static let titleBar=NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(red:38/255,green:23/255,blue:43/255,alpha:1)
            : NSColor(red:1,green:247/255,blue:251/255,alpha:1)
    }
    /// The Discord panel in pastel: its frame, edge, embeds, text and button.
    enum Discord {
        static func frame(_ s:ColorScheme)->Color { pick(s,hex(0xFF78AF,0.11),hex(0xFF78AF,0.06)) }
        static func edge(_ s:ColorScheme)->Color { pick(s,hex(0xE6508C,0.26),hex(0xFF82B4,0.34)) }
        static func embed(_ s:ColorScheme)->Color { pick(s,hex(0xFFFAFD),hex(0x301F36)) }
        static func embedHover(_ s:ColorScheme)->Color { pick(s,hex(0xFCEDF4),hex(0x3A2741)) }
        static func header(_ s:ColorScheme)->Color { pick(s,hex(0x8D5572),hex(0xD9B3C7)) }
        static func text(_ s:ColorScheme)->Color { pick(s,hex(0x6A3352),hex(0xF0D7E3)) }
        static func button(_ s:ColorScheme)->Color { pick(s,hex(0xB0628A),hex(0x6E3F58)) }
        static func chip(_ s:ColorScheme)->Color { hex(0xFF78AF,0.18) }
        static func chipText(_ s:ColorScheme)->Color { pick(s,hex(0xB3245F),hex(0xFFB3CF)) }
    }
}

/// Bunni's pink for text and icons, light or dark with the view.
struct BunniPink: ShapeStyle {
    func resolve(in environment:EnvironmentValues)->Color { Bunni.pink(environment.colorScheme) }
}
/// Faint text (a credit, a placeholder): Bunni's plum at about the system's tertiary strength.
struct BunniFaint: ShapeStyle {
    /// A slight underline under a link that looks like plain text (the version).
    static let under=Color.secondary.opacity(0.45)
    func resolve(in environment:EnvironmentValues)->Color { Bunni.ink(environment.colorScheme).opacity(environment.colorScheme == .dark ? 0.36 : 0.42) }
}
extension View {
    /// Text and its secondary level in Bunni's plum, for a window's or pop-up's content.
    func bunniInk()->some View { modifier(BunniInk()) }
}
/// The third level (and the fourth, which takes it) is what bordered buttons fill with, so it is a faint plum like
/// the system's grey; faint text that used it takes BunniFaint.
private struct BunniInk: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content:Content)->some View { content.foregroundStyle(Bunni.ink(scheme),Bunni.secondary(scheme),Bunni.ink(scheme).opacity(scheme == .dark ? 0.12 : 0.09)) }
}

// MARK: the logo

/// The home screen's logo: the pink icon and the name where Recall's wordmark is, the BUNNI sticker tucked under the
/// end of the name, its ears moving (the design's "Tucked" lockup).
struct BunniLockup: View {
    var badge:String?
    var body:some View {
        ZStack(alignment:.topLeading) {
            Color.clear.frame(width:360,height:84)
            BunniIcon(side:82)
                .overlay(alignment:.bottomTrailing) {
                    if let badge {
                        Image(systemName:badge).font(.system(size:84*0.2,weight:.semibold))
                            .foregroundStyle(LauncherStyle.ink).frame(width:84*0.4,height:84*0.4)
                            .background(LauncherStyle.accent,in:Circle())
                            .overlay { Circle().strokeBorder(.background,lineWidth:2) }
                            .offset(x:84*0.08,y:84*0.04)
                    }
                }.offset(x:74,y:1)
            // The name's baseline at 58, as the design sets it.
            Text(verbatim:Brand.name).font(.system(size:42,weight:.bold)).tracking(-1).foregroundStyle(.primary)
                .fixedSize().offset(x:171,y:58-40)
            BunniSticker(word:true).frame(width:100,height:80).offset(x:262,y:12)
        }.frame(width:360,height:84)
            .accessibilityElement().accessibilityLabel(Brand.name).accessibilityAddTraits(.isHeader)
    }
}
/// The pink icon at a side, as the app icon's rounded square (the .icns has a margin round it).
struct BunniIcon: View {
    var side:CGFloat
    private static let image=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap(NSImage.init(contentsOf:))
        ?? NSImage(named:NSImage.applicationIconName) ?? NSImage()
    var body:some View {
        Image(nsImage:Self.image).resizable().interpolation(.high).frame(width:side*1024/824,height:side*1024/824)
            .frame(width:side,height:side).accessibilityHidden(true)
    }
}
/// About's name line: the name with the sticker beside it.
struct BunniNameLine: View {
    var body:some View {
        HStack(alignment:.center,spacing:5) {
            Text(verbatim:Brand.name).font(LauncherStyle.font(30,.bold)).tracking(-0.8).accessibilityAddTraits(.isHeader)
            Color.clear.frame(width:96,height:29)
                .overlay { BunniSticker(word:true).frame(width:96,height:77).rotationEffect(.degrees(-3)).offset(y:-10) }
                .accessibilityHidden(true)
        }.padding(.top,6).padding(.bottom,10)
    }
}

/// The ears and the BUNNI word, drawn as the design's SVG (a 150 × 120 box): a white then a pink outline, the
/// ears' inner pink and shade, the letters white over pink. The ears move while the window is in front, and hold
/// still behind other windows, with Reduce Motion, and in the background.
struct BunniSticker: View {
    var word=true
    @State private var ears=BunniEars()
    @Environment(\.appearsActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Only with its window key, the app in front and visible, and Reduce Motion off: otherwise not a frame is drawn.
    private var moving:Bool { active && !reduceMotion && Moving.shared.now }
    var body:some View {
        TimelineView(.animation(minimumInterval:nil,paused:!moving)) { timeline in
            Canvas { context,size in
                ears.advance(to:timeline.date,moving:moving)
                context.scaleBy(x:size.width/150,y:size.height/120)
                let shapes=ears.shapes()
                let round=StrokeStyle(lineWidth:12,lineCap:.round,lineJoin:.round)
                for shape in shapes { context.stroke(shape.outer,with:.color(.white),style:round) }
                for shape in shapes { context.stroke(shape.outer,with:.color(Bunni.tag),style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round)) }
                for shape in shapes {
                    context.fill(shape.outer,with:.color(BunniSticker.earFill))
                    context.fill(shape.inner,with:.color(BunniSticker.earInner))
                    var shade=context;shade.blendMode = .multiply
                    shade.fill(shape.shade,with:.color(BunniSticker.earShade))
                }
                if word, let letters=BunniWord.path {
                    context.stroke(letters,with:.color(.white),style:round)
                    context.stroke(letters,with:.color(Bunni.tag),style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round))
                    let box=letters.boundingRect
                    context.fill(letters,with:.linearGradient(Gradient(stops:[.init(color:.white,location:0),.init(color:.white,location:0.6),
                                                                              .init(color:BunniSticker.letterShade,location:0.6),.init(color:BunniSticker.letterShade,location:1)]),
                                                             startPoint:CGPoint(x:box.midX,y:box.minY),endPoint:CGPoint(x:box.midX,y:box.maxY)))
                }
            }
        }.shadow(color:Color(red:60/255,green:16/255,blue:40/255).opacity(0.28),radius:1,x:0,y:2)
            .accessibilityHidden(true)
    }
    static let earFill=Color(red:1,green:245/255,blue:249/255)
    /// The accent 62% on white, the tag 30% on #FFD9E6 (multiplied), the accent 30% on white.
    static let earInner=Color(red:1,green:154/255,blue:188/255)
    static let earShade=Color(red:243/255,green:160/255,blue:193/255)
    static let letterShade=Color(red:1,green:206/255,blue:223/255)
}

/// BUNNI in Fredoka Bold, 34 units, a unit apart, centred on x 76 at y 108, each letter turned and nudged as in the design.
private enum BunniWord {
    static let path:Path?={
        guard let font=font(size:34) else { return nil }
        let characters=Array("BUNNI".utf16)
        var glyphs=[CGGlyph](repeating:0,count:characters.count)
        guard CTFontGetGlyphsForCharacters(font,characters,&glyphs,characters.count) else { return nil }
        var advances=[CGSize](repeating:.zero,count:glyphs.count)
        CTFontGetAdvancesForGlyphs(font,.horizontal,glyphs,&advances,glyphs.count)
        let spacing:CGFloat=1,turns:[CGFloat]=[-7,4,-3,5,-1],nudges:[CGFloat]=[0,-2,3,-2,1]
        let width=advances.reduce(0) { $0+$1.width }+spacing*CGFloat(glyphs.count)
        var x=76-width/2,y:CGFloat=108,path=Path()
        for (index,glyph) in glyphs.enumerated() {
            y+=nudges[index]
            if let outline=CTFontCreatePathForGlyph(font,glyph,nil) {
                let place=CGAffineTransform(scaleX:1,y:-1).concatenating(CGAffineTransform(rotationAngle:turns[index] * .pi/180))
                    .concatenating(CGAffineTransform(translationX:x,y:y))
                path.addPath(Path(outline),transform:place)
            }
            x+=advances[index].width+spacing
        }
        return path
    }()
    /// Fredoka (bundled, OFL) at its bold weight; the system's rounded bold without the file.
    static func font(size:CGFloat)->CTFont? {
        if let url=Bundle.main.url(forResource:"Fredoka",withExtension:"woff2"),let data=try? Data(contentsOf:url),
           let descriptor=(CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor])?.first {
            return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithVariation(descriptor,0x77676874 as CFNumber,700),size,nil)
        }
        let system=NSFont.systemFont(ofSize:size,weight:.bold)
        return (system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor:$0,size:size) } ?? system) as CTFont
    }
}

/// The two ears: springs that settle each ear at its pose, a slow drift, and now and then a flick, a swivel, a shrug or a
/// lift; one ear flops, and every so often they swap (the design's "Swaps sides" ears, "Wild" fidget).
final class BunniEars {
    struct Shapes { let outer:Path;let inner:Path;let shade:Path }
    private enum Side: CaseIterable { case left,right }
    private struct Shape { var base:CGPoint;var l1,l2,w,th,ph:Double }
    private final class Ear {
        var rest,th,ph,thGoal,phGoal,f,seed:Double
        var curl=0.0,vt=0.0,vp=0.0,vc=0.0,swapT=0.0
        init(_ shape:Shape,floppy:Bool) { rest=shape.ph;th=shape.th;ph=shape.ph;thGoal=shape.th;phGoal=shape.ph;f=floppy ? 1 : 0;seed=Double.random(in:0..<40) }
    }
    /// "Wild": everything comes 0.6 times as long apart as "Lively".
    private let pace=0.6
    /// Every twitch, swivel, shrug, lift and the drift 17.5% bigger than the design's (owner, November 28).
    private let reach=1.175
    private var ears:[Side:Ear]=[:]
    private var queue:[(at:Double,run:()->Void)]=[]
    private var clock=0.0,earNext=1.0,last:Date?
    private var flopSide:Side=Bool.random() ? .left : .right
    private var flopNext=6+Double.random(in:0..<8)

    private func shape(_ side:Side,floppy:Bool)->Shape {
        switch (side,floppy) {
        case (.left,true): Shape(base:CGPoint(x:58,y:80),l1:36,l2:50,w:13,th:-0.34,ph:-2)
        case (.left,false): Shape(base:CGPoint(x:60,y:80),l1:38,l2:36,w:13,th:-0.2,ph:0.26)
        case (.right,true): Shape(base:CGPoint(x:94,y:80),l1:36,l2:50,w:13,th:0.34,ph:2)
        case (.right,false): Shape(base:CGPoint(x:90,y:80),l1:38,l2:36,w:13,th:0.2,ph:-0.26)
        }
    }
    private func floppy(_ side:Side)->Bool { side == flopSide }
    private func blend(_ side:Side,_ f:Double)->Shape {
        let a=shape(side,floppy:false),b=shape(side,floppy:true),m={ (x:Double,y:Double) in x+(y-x)*f }
        return Shape(base:CGPoint(x:m(a.base.x,b.base.x),y:m(a.base.y,b.base.y)),l1:m(a.l1,b.l1),l2:m(a.l2,b.l2),w:m(a.w,b.w),th:0,ph:0)
    }
    private func ear(_ side:Side)->Ear {
        if let ear=ears[side] { return ear }
        let ear=Ear(shape(side,floppy:floppy(side)),floppy:floppy(side));ears[side]=ear;return ear
    }

    /// Moves time on to a frame's date (a step at most 1/30 s); still, it keeps the date without moving.
    func advance(to date:Date,moving:Bool) {
        defer { last=date }
        guard moving,let last else { return }
        step(min(0.033,max(0,date.timeIntervalSince(last))))
    }
    private func later(_ ms:Double,_ run:@escaping ()->Void) { queue.append((clock+ms/1000,run)) }
    private func beat() {
        let up=Side.allCases.filter { !floppy($0) }.map(ear),flop=Side.allCases.filter(floppy).map(ear)
        let sign={ Bool.random() ? -1.0 : 1.0 }
        var moves:[(String,Double)]=[]
        if !up.isEmpty { moves+=[("flick",5),("swivel",3)] }
        if !flop.isEmpty { moves+=[("shrug",3),("lift",1.6)] }
        moves.append(("rest",2.4))
        var roll=Double.random(in:0..<moves.reduce(0) { $0+$1.1 }),move="rest"
        for candidate in moves { roll-=candidate.1;if roll <= 0 { move=candidate.0;break } }
        switch move {
        case "flick":
            let e=up.randomElement()!,s=sign(),size=(2.4+Double.random(in:0..<1.6))*reach
            e.vt+=s*size;later(95) { e.vt-=s*size*0.7 }
            if Double.random(in:0..<1) < 0.35 { later(260) { e.vt+=s*size*0.8 };later(345) { e.vt-=s*size*0.55 } }
            let reach=reach
            if let other=flop.first { later(70) { other.vp+=s*0.9*reach;other.vt+=s*0.5*reach } }
        case "swivel":
            let e=up.randomElement()!,rest=e.thGoal
            e.thGoal=rest+sign()*(0.09+Double.random(in:0..<0.12))*reach
            later(800+Double.random(in:0..<1700)) { e.thGoal=rest }
        case "shrug":
            let e=flop.randomElement()!,direction:Double=e.rest > 0 ? -1 : 1
            e.vp+=direction*(1.8+Double.random(in:0..<1.3))*reach;e.vt+=direction*0.6*reach
        case "lift":
            let e=flop.randomElement()!,direction:Double=e.rest > 0 ? -1 : 1
            e.phGoal=e.rest+direction*(0.42+Double.random(in:0..<0.2))*reach
            let reach=reach
            later(480+Double.random(in:0..<420)) { e.phGoal=e.rest;e.vp-=direction*1.1*reach }
        default: break
        }
    }
    private func step(_ dt:Double) {
        clock+=dt
        flopNext-=dt
        if flopNext <= 0 { flopSide=flopSide == .left ? .right : .left;flopNext=(9+Double.random(in:0..<14))*pace;queue=[] }
        for side in Side.allCases {
            let floppy=floppy(side),p=shape(side,floppy:floppy),e=ear(side)
            if e.rest != p.ph { e.rest=p.ph;e.thGoal=p.th;e.phGoal=p.ph;e.swapT=1.4 }
            let goal:Double=floppy ? 1 : 0
            e.f+=(goal-e.f)*min(1,dt*3.5)
            e.swapT=max(0,e.swapT-dt)
            let t:Double=clock+e.seed
            let drift:Double=(sin(t*0.63)*0.5+sin(t*1.17+1.3)*0.32+sin(t*1.91+2.1)*0.18)*reach
            let kt:Double=floppy ? 58 : 105,ct:Double=floppy ? 9.5 : 13.5,kp:Double=floppy ? 30 : 70,cp:Double=floppy ? 4.6 : 11
            let at:Double = -kt*(e.th-e.thGoal-drift*0.028)-ct*e.vt
            e.vt+=at*dt;e.th+=e.vt*dt
            let sway:Double=drift*(floppy ? 0.07 : 0.03),pull:Double=floppy ? at*0.16 : 0
            let ap:Double = -kp*(e.ph-e.phGoal-sway)-cp*e.vp-pull
            e.vp+=ap*dt;e.ph+=e.vp*dt
            let ac:Double = -42*(e.curl+e.vp*0.075)-7.5*e.vc
            e.vc+=ac*dt;e.curl+=e.vc*dt
            if floppy && e.swapT == 0 {
                let lo=abs(p.ph)-0.74,hi=abs(p.ph)+0.2,sign:Double=p.ph < 0 ? -1 : 1,a=abs(e.ph)
                if a > hi { e.ph=sign*hi;e.vp *= -0.28 }
                if a < lo { e.ph=sign*lo;e.vp *= -0.2 }
            }
        }
        earNext-=dt
        if earNext <= 0 { beat();earNext=(1.1+pow(Double.random(in:0..<1),1.6)*4.2)*pace }
        let due=queue.filter { $0.at <= clock };queue.removeAll { $0.at <= clock }
        for item in due { item.run() }
    }
    func shapes()->[Shapes] {
        Side.allCases.map { side in
            let e=ear(side)
            return Self.paths(blend(side,e.f),th:e.th,ph:e.ph,curl:e.curl)
        }
    }
    /// One ear's outline, inner and shade along a curved spine from its base.
    private static func paths(_ p:Shape,th:Double,ph:Double,curl:Double)->Shapes {
        func rot(_ q:CGPoint,_ c:CGPoint,_ a:Double)->CGPoint {
            let x=q.x-c.x,y=q.y-c.y,s=sin(a),k=cos(a);return CGPoint(x:c.x+x*k-y*s,y:c.y+x*s+y*k)
        }
        let b=p.base,j=CGPoint(x:b.x+p.l1*sin(th),y:b.y-p.l1*cos(th))
        let t0=CGPoint(x:j.x+p.l2*sin(th+ph),y:j.y-p.l2*cos(th+ph))
        let c1=CGPoint(x:b.x+(j.x-b.x)*2/3,y:b.y+(j.y-b.y)*2/3)
        let c2=rot(CGPoint(x:t0.x+(j.x-t0.x)*2/3,y:t0.y+(j.y-t0.y)*2/3),j,curl*0.5),tip=rot(t0,j,curl)
        func at(_ t:Double)->CGPoint {
            let u=1-t,a=u*u*u,bb=3*u*u*t,c=3*u*t*t,d=t*t*t
            return CGPoint(x:a*b.x+bb*c1.x+c*c2.x+d*tip.x,y:a*b.y+bb*c1.y+c*c2.y+d*tip.y)
        }
        func dir(_ t:Double)->CGPoint {
            let u=1-t,x=3*u*u*(c1.x-b.x)+6*u*t*(c2.x-c1.x)+3*t*t*(tip.x-c2.x),y=3*u*u*(c1.y-b.y)+6*u*t*(c2.y-c1.y)+3*t*t*(tip.y-c2.y)
            let l=hypot(x,y) == 0 ? 1 : hypot(x,y);return CGPoint(x:x/l,y:y/l)
        }
        let n=16,bend=min(1,abs(ph+curl*0.6)/2),side:Double=ph >= 0 ? 1 : -1
        var outerA:[CGPoint]=[],outerB:[CGPoint]=[],innerA:[CGPoint]=[],innerB:[CGPoint]=[],rim:[CGPoint]=[],edge:[CGPoint]=[]
        for i in 0...n {
            let v=1-pow(1-Double(i)/Double(n),1.7),c=at(v),d=dir(v),w=p.w*pow(max(0,sin(.pi*(0.14+0.86*v))),0.55)
            outerA.append(CGPoint(x:c.x-d.y*w,y:c.y+d.x*w));outerB.append(CGPoint(x:c.x+d.y*w,y:c.y-d.x*w))
            let ti=0.2+0.7*v,ci=at(ti),di=dir(ti),wi=(p.w-6.5)*pow(max(0,sin(.pi*(0.06+0.94*v))),0.6)
            innerA.append(CGPoint(x:ci.x-di.y*wi,y:ci.y+di.x*wi));innerB.append(CGPoint(x:ci.x+di.y*wi,y:ci.y-di.x*wi))
            let band=w*(0.2*sin(.pi*min(1,v*1.02))+0.78*bend*exp(-pow((v-0.5)/0.2,2)))
            edge.append(CGPoint(x:c.x-side*d.y*w,y:c.y+side*d.x*w))
            rim.append(CGPoint(x:c.x-side*d.y*(w-band),y:c.y+side*d.x*(w-band)))
        }
        return Shapes(outer:smooth(outerA+outerB.reversed().dropFirst()),inner:smooth(innerA+innerB.reversed().dropFirst()),shade:smooth(edge+rim.reversed()))
    }
    /// A closed curve through every point (Catmull-Rom as cubic Béziers).
    private static func smooth(_ points:[CGPoint])->Path {
        var path=Path()
        let m=points.count
        guard m > 2 else { return path }
        func q(_ i:Int)->CGPoint { points[((i%m)+m)%m] }
        path.move(to:points[0])
        for i in 0..<m {
            let a=q(i-1),b=q(i),c=q(i+1),e=q(i+2)
            path.addCurve(to:c,control1:CGPoint(x:b.x+(c.x-a.x)/6,y:b.y+(c.y-a.y)/6),control2:CGPoint(x:c.x-(e.x-b.x)/6,y:c.y-(e.y-b.y)/6))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: the home screen

/// Josh's card made compact: one line and the two buttons, smaller.
struct BunniSupportCard: View {
    let placement:Brand.Placement
    /// The line opens About, where Josh's letter is.
    let openAbout:()->Void
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        HStack(spacing:12) {
            HStack(spacing:12) {
                AuthorPhoto(size:30)
                Text(L("{0} is made by Josh.",Brand.name)).font(LauncherStyle.font(12.5)).lineLimit(3).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                .onTapGesture(perform:openAbout).accessibilityAddTraits(.isButton).accessibilityAction(.default,openAbout)
                .help(L("About {0}",Brand.name))
            HStack(spacing:6) {
                MosaicButton(placement:placement,compact:true)
                CoffeeButton(compact:true)
            }.fixedSize()
        }.padding(.leading,14).padding(.trailing,12).padding(.vertical,10).frame(maxWidth:.infinity,alignment:.leading)
            .background(LauncherStyle.surface(scheme),in:RoundedRectangle(cornerRadius:16,style:.continuous))
            .overlay { RoundedRectangle(cornerRadius:16,style:.continuous).strokeBorder(Bunni.hair(scheme),lineWidth:1) }
            .accessibilityElement(children:.contain).accessibilityLabel(L("Support {0}",Brand.name))
    }
}
/// The home status line's last link, in pink: what's different from Recall, in About.
struct BunniDifferentLink: View {
    let open:()->Void
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        Button(L("What’s different"),action:open).buttonStyle(.borderless).fontWeight(.semibold).foregroundStyle(Bunni.pink(scheme))
            .help(L("See what’s different in {0} from {1}",Brand.forkName,Brand.name))
    }
}

// MARK: About

/// Under the version: who makes Bunni, and the Recall release it's based on.
struct BunniCredit: View {
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        var line=AttributedString(L("{0} by {1}, based on {2} {3}",Brand.forkName,Bunni.author,Brand.name,Bunni.base))
        if let range=line.range(of:Brand.forkName) { line[range].foregroundColor=Bunni.pink(scheme);line[range].font=LauncherStyle.font(11.5,.semibold) }
        return Text(line).font(LauncherStyle.font(11.5)).foregroundStyle(.secondary)
    }
}
/// GitHub, in two: Recall's repository (Asher) and Bunni's.
struct BunniRepositoryLinks: View {
    var body:some View {
        HStack(spacing:0) {
            BunniGitHubMark().fill(.white).frame(width:20,height:20).padding(.leading,14).padding(.trailing,2).accessibilityHidden(true)
            Link(destination:Brand.repository) {
                HStack(spacing:6) {
                    Text(verbatim:"Asher")
                    Image(systemName:"arrow.up.right").font(.system(size:9,weight:.semibold)).accessibilityHidden(true)
                }.padding(.leading,8).padding(.trailing,14).frame(maxHeight:.infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("{0} on GitHub",Brand.name)).help(L("Open the project repository in your browser"))
            Link(destination:Bunni.fork) {
                HStack(spacing:6) {
                    Text(verbatim:Brand.forkName)
                    Image(systemName:"arrow.up.right").font(.system(size:9,weight:.semibold)).accessibilityHidden(true)
                }.padding(.horizontal,14).frame(maxHeight:.infinity).background(Bunni.tag).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("{0} on GitHub",Brand.forkName)).help(L("Open {0}’s repository in your browser",Brand.forkName))
        }.font(LauncherStyle.font(14,.semibold)).foregroundStyle(.white).frame(height:38)
            .background(.black).clipShape(Capsule()).fixedSize()
    }
}
/// GitHub's mark (the same shape as Recall's own link; see GITHUB-MARK-NOTICE.txt).
private struct BunniGitHubMark: Shape {
    func path(in rect:CGRect)->Path {
        // GitHub's 16-point mark, scaled to the rect.
        let svg:[(Character,[CGFloat])]=[("M",[8,0]),("C",[3.58,0,0,3.58,0,8]),("C",[0,11.54,2.29,14.53,5.47,15.59]),("C",[5.87,15.66,6.02,15.42,6.02,15.21]),
            ("C",[6.02,15.02,6.01,14.39,6.01,13.72]),("C",[4,14.09,3.48,13.23,3.32,12.78]),("C",[3.23,12.55,2.84,11.84,2.5,11.65]),
            ("C",[2.22,11.5,1.82,11.13,2.49,11.12]),("C",[3.12,11.11,3.57,11.7,3.72,11.94]),("C",[4.44,13.15,5.59,12.81,6.05,12.6]),
            ("C",[6.12,12.08,6.33,11.73,6.56,11.53]),("C",[4.78,11.33,2.92,10.64,2.92,7.58]),("C",[2.92,6.71,3.23,5.99,3.74,5.43]),
            ("C",[3.66,5.23,3.38,4.41,3.82,3.31]),("C",[3.82,3.31,4.49,3.1,6.02,4.13]),("C",[6.66,3.95,7.34,3.86,8.02,3.86]),
            ("C",[8.7,3.86,9.38,3.95,10.02,4.13]),("C",[11.55,3.09,12.22,3.31,12.22,3.31]),("C",[12.66,4.41,12.38,5.23,12.3,5.43]),
            ("C",[12.81,5.99,13.12,6.7,13.12,7.58]),("C",[13.12,10.65,11.25,11.33,9.47,11.53]),("C",[9.76,11.78,10.01,12.26,10.01,13.01]),
            ("C",[10.01,14.08,10,14.94,10,15.21]),("C",[10,15.42,10.15,15.67,10.55,15.59]),("C",[13.71,14.53,16,11.53,16,8]),("C",[16,3.58,12.42,0,8,0])]
        var path=Path()
        for (command,v) in svg {
            if command == "M" { path.move(to:CGPoint(x:v[0],y:v[1])) }
            else { path.addCurve(to:CGPoint(x:v[4],y:v[5]),control1:CGPoint(x:v[0],y:v[1]),control2:CGPoint(x:v[2],y:v[3])) }
        }
        path.closeSubpath()
        let scale=min(rect.width,rect.height)/16
        return path.applying(CGAffineTransform(scaleX:scale,y:scale).concatenating(CGAffineTransform(translationX:rect.minX,y:rect.minY)))
    }
}
/// The bunny face on What's different's pink tile.
private struct BunniFace: Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        path.move(to:CGPoint(x:9.5,y:10.5));path.addLine(to:CGPoint(x:9.5,y:5))
        path.addArc(center:CGPoint(x:11.3,y:5),radius:1.8,startAngle:.degrees(180),endAngle:.degrees(0),clockwise:false)
        path.addLine(to:CGPoint(x:13.1,y:10))
        path.move(to:CGPoint(x:13.4,y:10));path.addLine(to:CGPoint(x:14.7,y:5.4))
        path.addArc(center:CGPoint(x:16.4,y:5.95),radius:1.78,startAngle:.degrees(198),endAngle:.degrees(18),clockwise:false)
        path.addLine(to:CGPoint(x:16.4,y:11.5))
        path.addEllipse(in:CGRect(x:12.5-4.8,y:15.5-4.8,width:9.6,height:9.6))
        let scale=min(rect.width,rect.height)/24
        return path.applying(CGAffineTransform(scaleX:scale,y:scale).concatenating(CGAffineTransform(translationX:rect.minX,y:rect.minY)))
    }
}
private struct BunniTile: View {
    var body:some View {
        BunniFace().stroke(.white,style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round)).frame(width:18,height:18)
            .frame(width:30,height:30).background(Bunni.tag,in:RoundedRectangle(cornerRadius:9,style:.continuous)).accessibilityHidden(true)
    }
}
/// The pink glow round Bunni's own notes (the design's "Soft").
private struct BunniGlow: ViewModifier {
    var radius:CGFloat
    /// What's different's card: a faint edge and a little light round it (the design's was too strong, owner, November 28).
    var faint=false
    func body(content:Content)->some View {
        content.overlay { RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(Bunni.accent.opacity(faint ? 0.3 : 0.6),lineWidth:faint ? 1 : 1.5) }
            .background { RoundedRectangle(cornerRadius:radius,style:.continuous).fill(Bunni.accent.opacity(faint ? 0.14 : 0.38)).blur(radius:faint ? 6 : 9).padding(faint ? -1 : -3) }
    }
}
/// What's different in Bunni from the Recall release it's based on, each part opening to its points.
struct BunniDifferences: View {
    @Environment(\.colorScheme) private var scheme
    @State private var open:Set<Int>=[0]
    private var parts:[(symbol:String,title:String,summary:String,points:[(String,String)])] { [
        ("bubble.left.fill",L("Discord"),L("Customize your Discord card, and share codes"),[
            (L("Your Discord card."),L("Pick what friends see, line by line, in Settings.")),
            (L("Share codes."),L("Send your card to a friend as a short code.")),
        ]),
    ] }
    /// A point: its lead in bold, then the rest.
    private static func point(_ lead:String,_ rest:String)->AttributedString {
        var bold=AttributedString(lead);bold.font=LauncherStyle.font(13,.semibold)
        return bold+AttributedString(" "+rest)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:10) {
                BunniTile()
                Text(L("What’s different in {0}",Brand.forkName)).font(LauncherStyle.font(14,.bold)).foregroundStyle(Bunni.pink(scheme)).accessibilityAddTraits(.isHeader)
                Spacer(minLength:8)
                Text(L("vs {0} {1}",Brand.name,Bunni.base)).font(LauncherStyle.font(12)).foregroundStyle(.secondary)
            }.padding(.bottom,4)
            ForEach(parts.indices,id:\.self) { index in
                let part=parts[index],isOpen=open.contains(index)
                VStack(alignment:.leading,spacing:0) {
                    Rectangle().fill(Bunni.hair(scheme)).frame(height:1)
                    Button {
                        if isOpen { open.remove(index) } else { open.insert(index) }
                    } label: {
                        HStack(spacing:12) {
                            Image(systemName:part.symbol).font(.system(size:15,weight:.medium)).foregroundStyle(Bunni.pink(scheme)).frame(width:19).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:1) {
                                Text(part.title).font(LauncherStyle.font(14,.semibold))
                                Text(part.summary).font(LauncherStyle.font(12.5)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:0)
                            Image(systemName:"chevron.down").font(.system(size:12,weight:.semibold)).foregroundStyle(Bunni.pink(scheme))
                                .rotationEffect(.degrees(isOpen ? 180 : 0)).accessibilityHidden(true)
                        }.padding(.vertical,6).frame(minHeight:48).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityValue(isOpen ? L("Expanded") : L("Collapsed"))
                    if isOpen {
                        VStack(alignment:.leading,spacing:6) {
                            ForEach(part.points.indices,id:\.self) { i in
                                HStack(alignment:.firstTextBaseline,spacing:8) {
                                    Text(verbatim:"•").foregroundStyle(.secondary)
                                    Text(Self.point(part.points[i].0,part.points[i].1)).fixedSize(horizontal:false,vertical:true)
                                }.font(LauncherStyle.font(13))
                            }
                        }.padding(.leading,31).padding(.bottom,12)
                    }
                }
            }
        }.padding(.horizontal,18).padding(.top,14).padding(.bottom,16)
            .background(Bunni.soft(scheme),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .modifier(BunniGlow(radius:18,faint:true))
    }
}

// MARK: What's New and the update

/// What's New for Bunni: Bunni's own notes raised and glowing, then Recall's (since the release Bunni was last based
/// on) sunk below them.
struct BunniWhatsNew: View {
    @Environment(\.colorScheme) private var scheme
    static var mine:[(symbol:String,title:String,detail:String)] { [
        ("bubble.left.fill",L("Your Discord card"),L("Pick what friends see, line by line, in Settings.")),
        ("square.and.pencil",L("Share codes"),L("Send your card to a friend as a short code.")),
    ] }
    /// Recall 1.6.4 to 1.6.7, in short (Bunni was last based on 1.6.3).
    static var recall:[(symbol:String,title:String,detail:String)] { [
        ("arrow.down.circle",L("Installing games"),L("Fixed Battle.net freezing when you click Install on a game.")),
        ("film",L("Highlights"),L("Highlights save as MP4 in Movies › Overwatch. The Highlights window names clips after their hero, trims them, and makes a copy small enough for Discord.")),
        ("externaldrive",L("Move Overwatch"),L("Move Overwatch to another drive or folder from Settings › General, without downloading it again.")),
        ("keyboard",L("Faster key response"),L("A new experimental switch in Settings › Advanced gets key presses to Overwatch 1 to 3 ms sooner.")),
        ("wrench.and.screwdriver",L("More fixes"),L("Custom renderer settings, Repair Game Files, and fixed flickering effects such as Ana’s Sleep Dart and Sombra’s Hack.")),
    ] }
    var body:some View {
        ScrollView {
            VStack(spacing:14) {
                BunniNotesPanel(raised:true,title:L("From {0}",Bunni.handle),items:Self.mine)
                BunniNotesPanel(raised:false,title:L("From {0} {1}",Brand.name,Bunni.base),items:Self.recall)
            }.padding(24)
        }.scrollBounceBehavior(.basedOnSize).padding(-24).frame(maxHeight:.infinity)
    }
}
/// A panel of notes: raised (Bunni's: pink heading and icons, a soft glow) or sunk (Recall's: quieter, grey icons).
struct BunniNotesPanel: View {
    var raised:Bool
    var title:String
    var items:[(symbol:String,title:String,detail:String)]
    /// Bullets instead of icons and titles (the update prompt).
    var bullets=false
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        let panel=VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                if raised {
                    Image(systemName:"sparkles").font(.system(size:15,weight:.medium)).accessibilityHidden(true)
                } else {
                    Image(nsImage:BunniRecallIcon.image).resizable().interpolation(.high).frame(width:18,height:18)
                        .clipShape(RoundedRectangle(cornerRadius:5,style:.continuous)).accessibilityHidden(true)
                }
                Text(title).font(LauncherStyle.font(raised ? 14 : 13,raised ? .bold : .semibold)).accessibilityAddTraits(.isHeader)
            }.foregroundStyle(raised ? Bunni.pink(scheme) : Bunni.secondary(scheme))
            ForEach(items.indices,id:\.self) { index in
                let item=items[index]
                if bullets {
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Text(verbatim:"•").foregroundStyle(.secondary)
                        Text(item.detail).lineSpacing(2).fixedSize(horizontal:false,vertical:true)
                    }.font(LauncherStyle.font(13))
                } else {
                    HStack(alignment:.top,spacing:14) {
                        Image(systemName:item.symbol).font(.system(size:raised ? 16 : 15,weight:.medium))
                            .foregroundStyle(raised ? Bunni.pink(scheme) : Bunni.secondary(scheme)).frame(width:20).padding(.top,1).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:2) {
                            Text(item.title).font(LauncherStyle.font(raised ? 14 : 13,raised ? .semibold : .medium))
                            Text(item.detail).font(LauncherStyle.font(raised ? 13 : 12.5)).lineSpacing(2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                }
            }
        }.padding(.horizontal,20).padding(.vertical,18).frame(maxWidth:.infinity,alignment:.leading)
        if raised {
            panel.background(LauncherStyle.surface(scheme),in:RoundedRectangle(cornerRadius:22,style:.continuous))
                .shadow(color:.black.opacity(0.06),radius:0.5,y:1).shadow(color:Color(red:70/255,green:30/255,blue:40/255).opacity(0.13),radius:11,y:8)
                .modifier(BunniGlow(radius:22))
        } else {
            panel.background(Bunni.well(scheme),in:RoundedRectangle(cornerRadius:22,style:.continuous))
                .overlay { RoundedRectangle(cornerRadius:22,style:.continuous).stroke(Color.black.opacity(0.14),lineWidth:1).blur(radius:1.5).offset(y:1)
                    .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous)) }
        }
    }
}
/// Recall's own orange icon, beside Recall's notes and on Recall's Discord invite.
enum BunniRecallIcon {
    static let image=Bundle.main.url(forResource:"RecallIcon",withExtension:"png").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
}
/// Recall's orange icon in the app icon's rounded square, at a side.
struct BunniRecallMark: View {
    var side:CGFloat
    var body:some View {
        Image(nsImage:BunniRecallIcon.image).resizable().interpolation(.high).frame(width:side,height:side)
            .clipShape(RoundedRectangle(cornerRadius:side*185.4/824,style:.continuous)).accessibilityHidden(true)
    }
}
/// Under the update prompt's heading: where the update comes from.
struct BunniUpdateSource: View {
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        HStack(spacing:6) {
            BunniGitHubMark().fill(Bunni.pink(scheme)).frame(width:14,height:14).accessibilityHidden(true)
            Text(L("From {0}’s GitHub, signed with {0}’s certificate",Brand.forkName))
        }.font(LauncherStyle.font(12.5)).foregroundStyle(Bunni.pink(scheme)).frame(maxWidth:.infinity)
    }
}


// MARK: one place for every notice (the canvas's "Notices 1 · One line", owner, November 28)

/// A notice on the setup, opening, running and home screens: its icons in the row, and its card as Recall draws it.
struct BunniNotice: Identifiable {
    enum Icon { case symbol(String), app(NSImage) }
    let id:String
    var icons:[Icon]
    /// How many things it counts as (the busy apps' card: one per app or setting).
    var weight=1
    /// Something under way (shaders being prepared): the row leads with it, a spinner in front.
    var busy:String?=nil
    let card:AnyView
    init<Card:View>(_ id:String,icons:[Icon],weight:Int=1,busy:String?=nil,@ViewBuilder card:()->Card) {
        self.id=id;self.icons=icons;self.weight=weight;self.busy=busy;self.card=AnyView(card())
    }
}
/// Every notice in one row of one height, where they used to stack up and push the window about; Review opens
/// their cards in a popover over the page, so nothing below moves. With none, the row says so.
struct BunniNotices: View {
    let notices:[BunniNotice]
    @State private var open=false
    @State private var listHeight:CGFloat=0
    @Environment(\.colorScheme) private var scheme
    private var count:Int { notices.reduce(0) { $0+$1.weight } }
    var body:some View {
        Group {
            if notices.isEmpty {
                HStack(spacing:8) {
                    Text(L("Nothing is slowing Overwatch down."))
                    BunniMemoryUsed()
                }.font(LauncherStyle.font(13)).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,minHeight:48)
                    .overlay { RoundedRectangle(cornerRadius:14,style:.continuous).strokeBorder(Bunni.hair(scheme),lineWidth:1) }
            } else {
                Button { open.toggle() } label: { row }.buttonStyle(.plain)
                    .popover(isPresented:$open,arrowEdge:.bottom) { list }
                    .accessibilityHint(L("Shows each one, with what you can do about it"))
            }
        }.animation(nil,value:notices.count)
    }
    /// What the row says: what's under way first, then the busy apps, else a count; "· 2 more" for the rest.
    private var headline:String {
        if let busy=notices.first(where:{ $0.busy != nil }) {
            let rest=count-busy.weight
            return busy.busy!+(rest > 0 ? " · "+L("{0} more",String(rest)) : "")
        }
        if let load=notices.first(where:{ $0.id == "load" }) {
            let rest=count-load.weight
            return L("Review apps that affect your FPS")+(rest > 0 ? " · "+L("{0} more",String(rest)) : "")
        }
        return count == 1 ? L("1 thing needs a look") : L("{0} things need a look",String(count))
    }
    private var row:some View {
        HStack(spacing:10) {
            // Spinning only while Bunni is in front (Moving), like everything else that moves.
            if notices.contains(where:{ $0.busy != nil }) && Moving.shared.now {
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width:20,height:20).accessibilityHidden(true)
            }
            HStack(spacing:-5) {
                ForEach(Array(notices.flatMap(\.icons).prefix(4).enumerated()),id:\.offset) { _,icon in
                    Group {
                        switch icon {
                        case .app(let image): Image(nsImage:image).resizable().interpolation(.high)
                        case .symbol(let name):
                            Image(systemName:name).font(.system(size:10.5,weight:.semibold)).foregroundStyle(.primary)
                                .frame(width:20,height:20).background(Bunni.surface(scheme),in:RoundedRectangle(cornerRadius:6,style:.continuous))
                        }
                    }.frame(width:20,height:20)
                }
            }.accessibilityHidden(true)
            Text(headline).font(LauncherStyle.font(13.5)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength:8)
            BunniMemoryUsed()
            Image(systemName:"chevron.right").font(.system(size:11,weight:.bold)).foregroundStyle(Bunni.pink(scheme))
                .rotationEffect(.degrees(open ? 90 : 0)).accessibilityHidden(true)
        }.padding(.leading,14).padding(.trailing,12).frame(maxWidth:.infinity,minHeight:48)
            .background(Bunni.accent.opacity(0.09),in:RoundedRectangle(cornerRadius:14,style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:14,style:.continuous))
    }
    /// The cards as Recall draws them, scrolling past 480 points.
    private var list:some View {
        let cards=VStack(spacing:12) { ForEach(notices) { $0.card } }.padding(14).frame(width:LauncherStyle.contentWidth)
            .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { listHeight=$0 }
        return ScrollView { cards }.scrollBounceBehavior(.basedOnSize)
            .frame(width:LauncherStyle.contentWidth,height:min(max(listHeight,60),480))
            .font(LauncherStyle.font(14)).tint(.primary).bunniInk()
    }
}
/// The running screen's heading, smaller, with nothing under it: what to do is in the buttons and the line below them.
struct BunniRunningHeading: View {
    let title:String
    var body:some View {
        Text(title).font(LauncherStyle.font(26,.bold)).tracking(-0.5).multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader).padding(.top,-2)
    }
}
/// Under Show Overwatch: one quiet line in a slot of its own height, so it never moves anything as it changes.
struct BunniRunningHint: View {
    let game:Bool
    let windowGone:Bool
    var body:some View {
        HStack(spacing:6) {
            if game && windowGone { Image(systemName:"hourglass").font(.system(size:12,weight:.medium)).accessibilityHidden(true) }
            Text(!game ? L("Play from the Battle.net window.") : windowGone ? L("Just exited? Closing can take up to a minute.") : L("Can’t see it? Check your other desktops."))
        }.font(LauncherStyle.font(13)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(height:20)
    }
}
extension FirstMatchTip {
    /// Whether the tip draws anything (its body's cases, as a notice to count).
    static func shows(learned:Int?,hidden:Hidden)->Bool {
        let count=learned ?? 0
        let smooth=count >= Self.smooth
        let nearly = !smooth && count >= Self.nearlySmooth
        switch hidden {
        case .smooth: return !smooth && !nearly && learned != nil
        case .almost: return smooth || (!nearly && learned != nil)
        case .collapsed: return smooth || learned != nil
        case .shown: return true
        }
    }
}

/// The Mac's memory in use, rounded to whole GB, as Activity Monitor's "Memory Used" counts it (apps, wired and
/// compressed); read with each look at the busy apps, so never while they aren't being watched.
@MainActor @Observable final class BunniMemory {
    static let shared=BunniMemory()
    private(set) var usedGB:Int?
    let totalGB=Int((Double(ProcessInfo.processInfo.physicalMemory)/Double(1<<30)).rounded())
    func update() {
        var stats=vm_statistics64(),count=mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to:&stats) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics64(mach_host_self(),HOST_VM_INFO64,$0,&count) } }
        guard result == KERN_SUCCESS else { return }
        let pages=UInt64(stats.internal_page_count)-UInt64(stats.purgeable_count)+UInt64(stats.wire_count)+UInt64(stats.compressor_page_count)
        usedGB=Int((Double(pages*UInt64(vm_kernel_page_size))/Double(1<<30)).rounded())
    }
}
struct BunniMemoryUsed: View {
    var body:some View {
        if let used=BunniMemory.shared.usedGB {
            Text(L("{0}/{1} GB RAM",String(used),String(BunniMemory.shared.totalGB))).font(LauncherStyle.font(12)).monospacedDigit()
                .foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }
}
/// Whether Bunni is the app in front: with Overwatch running, nothing is looked at until the player comes back.
@MainActor @Observable final class BunniFront {
    static let shared=BunniFront()
    private(set) var active=NSApp?.isActive ?? true
    private var watches:[NSObjectProtocol]=[]
    private init() {
        for name in [NSApplication.didBecomeActiveNotification,NSApplication.didResignActiveNotification] {
            watches.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { _ in
                MainActor.assumeIsolated { BunniFront.shared.active=NSApp.isActive } })
        }
    }
}
extension Bunni {
    /// With Overwatch running, Recall stops counting other apps' memory against it (it already has its own), so the
    /// apps named before it started went from the list though they still run. They stay until they end or are quit.
    @MainActor static func keepingApps(_ load:MacLoad,from before:MacLoad,gameRunning:Bool)->MacLoad {
        guard gameRunning else { return load }
        var load=load
        let named=Set(load.apps.map(\.pid))
        for app in before.apps where !named.contains(app.pid) && NSRunningApplication(processIdentifier:app.pid).map({ !$0.isTerminated }) == true {
            load.apps.append(app)
        }
        return load
    }
}

// MARK: its own app ID beside Recall's

extension Bunni {
    /// Recall's app ID, and Bunni's own (scripts/fork_release.py sets it): macOS keeps permissions per app ID, so with its
    /// own Bunni gets an Input Monitoring and Microphone line of its own and both apps can be allowed.
    static let recallID="org.overwatch2mac.launcher",bunniID="org.overwatch2mac.launcher.bunni"
    static var identifiers:[String] { Array(Set([recallID,bunniID,Bundle.main.bundleIdentifier ?? recallID])) }
    /// Once, the first time Bunni runs under its own ID: Recall's preferences, so the install location (and with it the
    /// game, its shaders and the Battle.net sign-in, all in the shared data folder), the mouse mode and every other
    /// choice carry over. Anything Bunni already has stays.
    static func adoptRecallSettings() {
        let defaults=UserDefaults.standard,flag="bunniAdoptedRecallSettings"
        guard Bundle.main.bundleIdentifier != recallID,!defaults.bool(forKey:flag) else { return }
        for (key,value) in defaults.persistentDomain(forName:recallID) ?? [:] where defaults.object(forKey:key) == nil {
            defaults.set(value,forKey:key)
        }
        defaults.set(true,forKey:flag)
    }
}
