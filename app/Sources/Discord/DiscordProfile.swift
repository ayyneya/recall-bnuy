import SwiftUI
import AppKit

// The top of Discord's pop-out: Juno with the online dot, "You" and the status lines, with the design's easter eggs
// (ProfileFun, functions of time on anime.js's timings). Customize or a page puts the picture back at once.

/// Under the banner: the picture in its ring, "You", and the status lines.
struct DiscordProfileTop: View {
    let fun:ProfileFun
    var body:some View {
        ZStack(alignment:.topLeading) {
            AvatarRing(fun:fun).offset(x:12,y:-36)
            names.padding(.leading,98).padding(.top,2)
        }
        .frame(maxWidth:.infinity,alignment:.topLeading)
    }
    /// "You" with the tag after it on its baseline, and the quote under it, placed by the fonts' own widths.
    private var names:some View {
        let you=L("You"),bold=DiscordFont.nsFont(18,700),small=DiscordFont.nsFont(11)
        let width=(you as NSString).size(withAttributes:[.font:bold]).width
        let drop=DesignText.line(bold,22).baseline-DesignText.line(small,14).baseline
        return ZStack(alignment:.topLeading) {
            Text(you).discordFont(18,700,line:22).foregroundStyle(DiscordColors.title).fixedSize().shadow(color:.black.opacity(0.55),radius:1.5,y:1)
            Text(L("#1 {0} player on Mac",DiscordStudio.heroName("juno"))).discordFont(11,line:14).foregroundStyle(DiscordColors.muted)
                .fixedSize().shadow(color:.black.opacity(0.5),radius:1,y:1).offset(x:width+7,y:drop)
            StatusQuote(text:L("i have no idea what is going on :3"),fun:fun).offset(y:23)
        }
    }
}

/// The online dot: Discord's green in a ring of the pop-out's colour.
private struct OnlineDot: View {
    var body:some View { Circle().fill(DiscordColors.online).frame(width:14,height:14).padding(4).background(DiscordColors.popout,in:Circle()) }
}

/// The design's Juno, the same for every player: never the player's Discord picture.
private struct AvatarPicture: View {
    static let juno=Bundle.main.url(forResource:"Juno",withExtension:"png").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
    var body:some View { Image(nsImage:Self.juno).resizable().interpolation(.high) }
}

/// The picture in its ring, with the online dot: pointing bulges it, a click pumps it (ProfileFun).
private struct AvatarRing: View {
    let fun:ProfileFun
    var body:some View {
        TimelineView(.animation(paused:!fun.ticking)) { context in
            let t=context.date.timeIntervalSinceReferenceDate,look=fun.ring(at:t)
            ZStack {
                ZStack {
                    AvatarPicture()
                    if let lens=look.lens { Image(decorative:lens,scale:2).resizable() }
                }
                .frame(width:66,height:66).clipShape(Circle())
                .scaleEffect(look.scale).rotationEffect(.degrees(look.turn))
                .opacity(look.hidden ? 0 : 1)
                .contentShape(Circle())
                .onHover { fun.point($0) }
                .onTapGesture { fun.pop() }
            }
            .frame(width:76,height:76).background(DiscordColors.popout,in:Circle())
            .overlay(alignment:.bottomTrailing) {
                OnlineDot().scaleEffect(look.dot.scale).offset(y:look.dot.y).opacity(look.dot.opacity).offset(x:-3,y:-3)
            }
            .onChange(of:context.date) { fun.tick(at:t) }
        }
    }
}

// MARK: the status line

/// The status line: pointing makes each letter jump, tip and run through pink, cyan, yellow and green (1.3 s, 26 ms
/// apart; again after 1.5 s).
private struct StatusQuote: View {
    let text:String
    let fun:ProfileFun
    private static let font=DiscordFont.nsFont(12)
    var body:some View {
        Group {
            if fun.wobbles.isEmpty {
                Text(text).discordFont(12,line:15).foregroundStyle(DiscordColors.muted).fixedSize().shadow(color:.black.opacity(0.45),radius:1,y:1)
            } else {
                // Each letter its own text, as wide as it is alone, where the ones before it end.
                let letters=Array(text).map(String.init),widths=letters.map { ($0 as NSString).size(withAttributes:[.font:Self.font]).width }
                let starts=widths.indices.map { widths[..<$0].reduce(0,+) }
                TimelineView(.animation(paused:!fun.ticking)) { context in
                    let t=context.date.timeIntervalSinceReferenceDate
                    ZStack(alignment:.topLeading) {
                        ForEach(letters.indices,id:\.self) { i in
                            let look=Self.look(i,at:t,fun.wobbles)
                            Text(verbatim:letters[i]).discordFont(12,line:15).foregroundStyle(look.color).fixedSize()
                                .frame(width:widths[i],height:15,alignment:.leading)
                                .shadow(color:.black.opacity(0.45),radius:1,y:1)
                                .rotationEffect(.degrees(look.turn))
                                .offset(x:starts[i],y:look.rise)
                        }
                    }
                    .frame(width:widths.reduce(0,+),height:15,alignment:.topLeading)
                    .onChange(of:context.date) { fun.tick(at:t) }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { if $0 { fun.wobble(letters:text.count) } }
    }
    /// The design's colours, one after another, and back.
    private static let colours:[(Double,Double,Double)]=[(181,186,193),(255,92,196),(64,224,255),(255,230,64),(140,255,120),(181,186,193)]
    /// A letter's rise, tilt and colour: anime.js's keyframes and colour blending.
    private static func look(_ i:Int,at t:Double,_ wobbles:[Double])->(rise:Double,turn:Double,color:Color) {
        let delay=0.026*Double(i)
        guard let start=wobbles.last(where:{ $0+delay <= t }),t-start-delay < 1.3 else { return (0,0,DiscordColors.muted) }
        let local=t-start-delay
        func step(_ count:Int)->(Int,Double) {
            let length=1.3/Double(count),k=min(count-1,Int(local/length))
            return (k,Ease.inOutSine((local-Double(k)*length)/length))
        }
        let (k,e)=step(4),rises=[0.0,-7,3,-2,0],turns=[0.0,-16,12,-5,0]
        let (j,f)=step(5),a=colours[j],b=colours[j+1]
        func blend(_ x:Double,_ y:Double)->Double { (x*x+(y*y-x*x)*f).squareRoot().rounded()/255 }
        return (rises[k]+(rises[k+1]-rises[k])*e,turns[k]+(turns[k+1]-turns[k])*e,Color(red:blend(a.0,b.0),green:blend(a.1,b.1),blue:blend(a.2,b.2)))
    }
}

/// The bulge while pumped: each pump runs from the last one's target; the newest running is the one seen.
struct FunLens {
    let rest:Double
    private(set) var tweens:[Tween]=[]
    private(set) var target:Double
    init(_ rest:Double) { self.rest=rest;target=rest }
    mutating func animate(at t:Double,to value:Double,_ duration:Double,_ curve:Ease) {
        tweens.append(Tween(start:t,from:target,keys:[Tween.Key(to:value,duration:duration,curve:curve)]));target=value
    }
    func value(at t:Double)->Double {
        let begun=tweens.filter { $0.start <= t }
        if let running=begun.last(where:{ t < $0.end }) { return running.value(at:t) }
        return begun.max { $0.end < $1.end }?.last ?? rest
    }
    mutating func cut(after t:Double) { tweens.removeAll { $0.start > t };target=tweens.last?.last ?? rest }
}

/// Random numbers that come out the same for the same seed: a pumped picture's tremble, its cracks and its pieces.
struct FunRandom {
    private var state:UInt64
    init(_ seed:UInt64) { state=seed }
    mutating func next()->UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z=state
        z=(z^(z>>30)) &* 0xBF58476D1CE4E5B9
        z=(z^(z>>27)) &* 0x94D049BB133111EB
        return z^(z>>31)
    }
    mutating func range(_ a:Double,_ b:Double)->Double { a+(b-a)*Double(next()>>11)/Double(1 << 53) }
}

// MARK: the picture's pixels

/// Where the picture cracks: seven spokes and three rings round the nose, a little crooked; the cells are the burst's
/// pieces.
struct Fracture {
    static let nose=CGPoint(x:0.533,y:0.53)
    let cells:[[CGPoint]]
    private let spokes:[[[CGPoint]]]
    private let rings:[[[CGPoint]]]
    init(_ random:inout FunRandom) {
        let c=Self.nose,k=7,radii=[0.22,0.46,0.8],r0=random.range(0,2*Double.pi)
        var angles:[Double]=[]
        for i in 0..<k { angles.append(r0+(Double(i)+random.range(-0.28,0.28))*(2*Double.pi/Double(k))) }
        var points:[[CGPoint]]=[]
        for angle in angles {
            var spoke:[CGPoint]=[]
            for r in radii { let b=angle+random.range(-0.09,0.09),rr=r+random.range(-0.035,0.035);spoke.append(CGPoint(x:c.x+cos(b)*rr,y:c.y+sin(b)*rr)) }
            points.append(spoke)
        }
        var cells:[[CGPoint]]=[]
        for i in 0..<k { let j=(i+1)%k;cells.append([c,points[i][0],points[j][0]]);cells.append([points[i][0],points[i][2],points[j][2],points[j][0]]) }
        // Each crack wobbles a little at its middle, the same way every time it's drawn.
        func jag(_ a:CGPoint,_ b:CGPoint)->[CGPoint] {
            let n=random.range(-0.06,0.06)
            return [a,CGPoint(x:(a.x+b.x)/2-(b.y-a.y)*n,y:(a.y+b.y)/2+(b.x-a.x)*n),b]
        }
        var spokes:[[[CGPoint]]]=[]
        for p in points { let first=jag(c,p[0]),second=jag(p[0],p[1]),third=jag(p[1],p[2]);spokes.append([first,second,third]) }
        var rings:[[[CGPoint]]]=[]
        for r in 0..<2 {
            var ring:[[CGPoint]]=[]
            for i in 0..<k { ring.append(jag(points[i][r],points[(i+1)%k][r])) }
            rings.append(ring)
        }
        self.cells=cells;self.spokes=spokes;self.rings=rings
    }
    /// The cracks showing at a stage (1 from the fourth pump, 3 at the last).
    func lines(_ stage:Int)->[[CGPoint]] {
        guard stage > 0 else { return [] }
        var lines:[[CGPoint]]=[]
        for (i,spoke) in spokes.enumerated() {
            if stage >= 2 || [0,3,5,7].contains(i) { lines.append(spoke[0]) }
            if (stage == 1 && (i == 3 || i == 7)) || (stage >= 2 && i%3 != 1) { lines.append(spoke[1]) }
            if stage >= 3 && i%2 == 0 { lines.append(spoke[2]) }
        }
        if stage >= 2 { for (i,line) in rings[0].enumerated() where i%3 == 0 || (stage >= 3 && i%3 == 2) { lines.append(line) } }
        if stage >= 3 { for (i,line) in rings[1].enumerated() where i%3 == 1 { lines.append(line) } }
        return lines
    }
}

/// The picture as the design's canvases hold it, 132 pixels across: bulge, cracks, and the burst's pieces.
final class LensPicture {
    static let side=132
    private static let space=CGColorSpace(name:CGColorSpace.sRGB)!
    private static let alpha=CGImageAlphaInfo.premultipliedLast.rawValue
    private let pixels:[UInt8]
    private var last:(strength:Double,image:CGImage)?
    init?(_ image:CGImage) {
        let side=Self.side
        var pixels=[UInt8](repeating:0,count:side*side*4)
        let drawn=pixels.withUnsafeMutableBytes { bytes->Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,space:Self.space,bitmapInfo:Self.alpha) else { return false }
            context.interpolationQuality = .high
            context.draw(image,in:CGRect(x:0,y:0,width:side,height:side))
            return true
        }
        guard drawn else { return nil }
        self.pixels=pixels
    }
    /// The bulge: a lens on the tip of the nose, magnified most in the middle.
    func bulged(_ strength:Double)->CGImage {
        if let last,last.strength == strength { return last.image }
        let w=Self.side,size=Double(w),cx=0.533*size,cy=0.53*size,r=0.5*size,s=min(0.97,strength)
        var out=pixels
        pixels.withUnsafeBufferPointer { source in
            for y in 0..<w {
                for x in 0..<w {
                    let dx=Double(x)+0.5-cx,dy=Double(y)+0.5-cy,d2=dx*dx+dy*dy
                    guard d2 < r*r else { continue }
                    let u=1-d2.squareRoot()/r,f=1-s*u*u
                    let sx=min(size-1.001,max(0,cx+dx*f-0.5)),sy=min(size-1.001,max(0,cy+dy*f-0.5))
                    let ix=Int(sx),iy=Int(sy),fx=sx-Double(ix),fy=sy-Double(iy)
                    let i00=(iy*w+ix)*4,i10=i00+4,i01=i00+w*4,i11=i01+4,o=(y*w+x)*4
                    for c in 0..<3 {
                        let top=Double(source[i00+c])*(1-fx)+Double(source[i10+c])*fx,bottom=Double(source[i01+c])*(1-fx)+Double(source[i11+c])*fx
                        out[o+c]=UInt8(min(255,max(0,(top*(1-fy)+bottom*fy).rounded())))
                    }
                }
            }
        }
        let image=CGImage(width:w,height:w,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:Self.space,bitmapInfo:CGBitmapInfo(rawValue:Self.alpha),
                          provider:CGDataProvider(data:Data(out) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
        last=(strength,image)
        return image
    }
    /// The cracks at a stage: a dark line under a white one, round-ended (the design's 2.8 and 1.6 pixels).
    static func cracks(_ lines:[[CGPoint]])->CGImage? {
        let side=Self.side,w=CGFloat(side)
        guard !lines.isEmpty,let context=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:alpha) else { return nil }
        // Down the canvas, as the design draws.
        context.translateBy(x:0,y:w);context.scaleBy(x:1,y:-1)
        context.setLineCap(.round);context.setLineJoin(.round)
        func trace(_ shift:CGFloat) {
            context.beginPath()
            for line in lines {
                for (i,p) in line.enumerated() {
                    let q=CGPoint(x:p.x*w+shift,y:p.y*w+shift)
                    if i == 0 { context.move(to:q) } else { context.addLine(to:q) }
                }
            }
        }
        trace(1.2);context.setStrokeColor(CGColor(srgbRed:40/255,green:10/255,blue:50/255,alpha:0.5));context.setLineWidth(2.8);context.strokePath()
        trace(0);context.setStrokeColor(CGColor(srgbRed:1,green:1,blue:1,alpha:0.9));context.setLineWidth(1.6);context.strokePath()
        return context.makeImage()
    }
    /// What the pieces show: the picture as it is at the burst, cut to its circle, a little pinker, cracks and all.
    func pieces(_ strength:Double,cracks:CGImage?)->CGImage {
        let side=Self.side,rect=CGRect(x:0,y:0,width:side,height:side)
        let context=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:0,space:Self.space,bitmapInfo:Self.alpha)!
        context.addEllipse(in:rect);context.clip()
        context.draw(bulged(strength),in:rect)
        context.setFillColor(CGColor(srgbRed:1,green:92/255,blue:140/255,alpha:0.25*0.55));context.fill(rect)
        if let cracks { context.draw(cracks,in:rect) }
        return context.makeImage()!
    }
}

// MARK: the pump and the burst

/// The picture's easter eggs. Pointing bulges it; each click pumps it, and from the third it strains, blushes and
/// cracks; left alone it settles. The sixth bursts it into pieces bouncing in the pop-out (". . . oh moons"), then it
/// grows back. All a function of time from the clicks, so a new click replans what follows.
@MainActor @Observable final class ProfileFun {
    /// Whether anything is moving: the timelines run only then.
    private(set) var ticking=false
    /// When the status line was pointed at (only the last two can still be moving), and when its last letter is still.
    private(set) var wobbles:[Double]=[]
    @ObservationIgnored private var wobbleEnds = -Double.infinity
    /// The pop-out's size, which the pieces bounce inside.
    @ObservationIgnored var shell=CGSize(width:372,height:285)
    private var hover:Hover?
    private var rig:Rig?
    /// When a bulge last went with a rig (as it settled or grew back): one made before then is gone.
    private var bulgeGone = -Double.infinity
    @ObservationIgnored private var picture:LensPicture?

    private var now:Double { Date().timeIntervalSinceReferenceDate }

    /// Pointing at the picture or away from it (not while it's pumped).
    func point(_ inside:Bool) {
        let t=now
        if let rig,t < rig.over { return }
        guard lens() != nil else { return }
        let alive=hover.map { $0.born > gone(at:t) } ?? false
        hover=Hover(inside:inside,start:t,from:alive ? hover!.value(at:t) : 0,born:alive ? hover!.born : t)
        ticking=true
    }
    /// A click on the picture: another pump, or the burst on the sixth (none while it bursts).
    func pop() {
        let t=now
        if let rig,t >= rig.over { bulgeGone=max(bulgeGone,rig.bulgeLost ?? t);self.rig=nil }
        if let rig,rig.bursting(at:t) { return }
        guard let lens=lens() else { return }
        var rig=self.rig ?? Rig(start:t,seed:UInt64.random(in:0...UInt64.max))
        rig.click(at:t)
        if rig.boom == t { rig.prepareBurst(lens,shell:shell) }
        self.rig=rig;ticking=true
    }
    /// Pointing at the status line: its letters wobble, once 1.5 s have passed since they last began.
    func wobble(letters:Int) {
        let t=now
        guard t-(wobbles.last ?? -10) >= 1.5 else { return }
        wobbles=Array(wobbles.suffix(1))+[t]
        wobbleEnds=t+0.026*Double(max(0,letters-1))+1.3
        ticking=true
    }
    /// Customize or a page opened: the picture back at once (the status line goes on as it is, as the design's does).
    func kill() {
        // Only when something's there: a write here is another update in the middle of the page opening.
        guard rig != nil || hover != nil else { return }
        bulgeGone=now;rig=nil;hover=nil
        tick(at:now)
    }
    /// Called as the timelines run: forgets a rig that's done, and stops them once nothing moves.
    func tick(at t:Double) {
        if let rig,t >= rig.done { bulgeGone=max(bulgeGone,rig.bulgeLost ?? t);self.rig=nil }
        let moving=rig != nil || (hover?.moving(at:t) ?? false) || t < wobbleEnds
        if moving != ticking { ticking=moving }
    }

    // MARK: what shows

    struct DotLook { var x=0.0,y=0.0,scale=1.0,opacity=1.0 }
    /// The picture in its own ring: hidden while its pumped copy shows, growing back after a burst, the bulge over it.
    struct RingLook {
        var hidden=false
        var scale=1.0
        var turn=0.0
        var lens:CGImage?
        var dot=DotLook()
    }
    func ring(at t:Double)->RingLook {
        var look=RingLook()
        if let hover,hover.born > gone(at:t),!(rig.map { t >= $0.start && hover.born <= $0.start } ?? false),hover.shown(at:t) {
            look.lens=picture?.bulged(0.62*hover.value(at:t))
        }
        guard let rig,t >= rig.start else { return look }
        if let settle=rig.settle,t >= settle {
            if rig.dotFlight != nil { look.dot=Rig.dotBack(from:settle,at:t) }
        } else if let regrow=rig.regrow,t >= regrow {
            look.scale=Tween(start:regrow,from:0,keys:[.init(to:1.2,duration:0.24),.init(to:0.92,duration:0.13,curve:.inOutQuad),.init(to:1,duration:0.44,curve:.outElastic(1,0.5))]).value(at:t)
            look.turn=Tween(start:regrow,from:-30,keys:[.init(to:10,duration:0.3),.init(to:0,duration:0.56,curve:.outElastic(1,0.5))]).value(at:t)
            look.dot=Rig.dotBack(from:regrow+0.42,at:t)
        } else {
            look.hidden=true;look.dot.opacity=0
        }
        return look
    }
    /// The pumped copy over the picture's ring.
    struct PumpLook {
        var lens:CGImage
        var cracks:CGImage?
        var face:Double
        var scaleX:Double
        var scaleY:Double
        var shake:CGSize
        var strain:Double
        var tint:Double
        var dot:DotLook
    }
    func pump(at t:Double)->PumpLook? {
        guard let rig,let lens=picture,t >= rig.start,!(rig.settle.map { t >= $0 } ?? false),!(rig.burst.map { t >= $0.at } ?? false) else { return nil }
        return PumpLook(lens:lens.bulged(rig.lens.value(at:t)),cracks:rig.cracks[rig.stage(at:t)],face:rig.face.value(at:t),scaleX:rig.scaleX.value(at:t),
                        scaleY:rig.scaleY.value(at:t),shake:rig.shake(at:t),strain:rig.strain.value(at:t),tint:rig.tint.value(at:t),dot:rig.flyingDot(at:t))
    }
    /// The burst and how long since it.
    func burst(at t:Double)->(Burst,Double)? {
        guard let burst=rig?.burst,t >= burst.at else { return nil }
        return (burst,t-burst.at)
    }
    /// The pop-out jolting and flaring as it bursts.
    struct Jolt {
        var shift=CGSize.zero
        var saturation=1.0,contrast=1.0,brightness=1.0,hue=0.0
    }
    func jolt(at t:Double)->Jolt {
        guard let burst=rig?.burst,t >= burst.at else { return Jolt() }
        let since=t-burst.at
        var jolt=Jolt()
        if let shift=burst.shifts.indices.contains(Int(since*60)) ? burst.shifts[Int(since*60)] : nil { jolt.shift=shift }
        // Its colours: the design's filter keyframes (at 0, 6, 55 and 100%) over 780 ms, eased out as a whole.
        if since < 0.78 {
            let p=Ease.bezier(0,0,0.58,1)(since/0.78),stops=[0,0.06,0.55,1.0]
            let k=min(2,stops.lastIndex { $0 <= p } ?? 0),f=(p-stops[k])/(stops[k+1]-stops[k])
            func at(_ values:[Double])->Double { values[k]+(values[k+1]-values[k])*f }
            jolt.saturation=at([1,3.2,2.6,1]);jolt.contrast=at([1,1.75,1.6,1]);jolt.brightness=at([1,1.15,1.08,1]);jolt.hue=at([0,-10,0,0])
        }
        return jolt
    }

    // MARK: inside

    /// When the bulge made before `t` went with a rig.
    private func gone(at t:Double)->Double {
        guard let rig,let lost=rig.bulgeLost,lost <= t else { return bulgeGone }
        return max(bulgeGone,lost)
    }
    /// The picture's pixels, made the first time they're needed.
    private func lens()->LensPicture? {
        if picture == nil { picture=AvatarPicture.juno.cgImage(forProposedRect:nil,context:nil,hints:nil).flatMap(LensPicture.init) }
        return picture
    }

    /// The hover bulge: in over 560 ms (overshooting), out over 320 ms, from where it was.
    struct Hover {
        let inside:Bool
        let start:Double
        let from:Double
        let born:Double
        var length:Double { inside ? 0.56 : 0.32 }
        func value(at t:Double)->Double {
            let p=Ease.linear(t,from:start,over:length)
            let e=inside ? 1+2.4*pow(p-1,3)+1.4*pow(p-1,2) : 1-pow(1-p,3)
            return from+((inside ? 1 : 0)-from)*e
        }
        func shown(at t:Double)->Bool { inside || t < start+length }
        func moving(at t:Double)->Bool { t < start+length }
    }

    /// The pumped picture, from the first click until it settles back or has grown back after bursting.
    struct Rig {
        let start:Double
        let seed:UInt64
        let fracture:Fracture
        /// The cracks at each stage, 0 (none) to 3.
        let cracks:[CGImage?]
        /// How many pumps it holds after each click and each pump let out (those planned after the last click too).
        private var steps:[(at:Double,count:Int)]=[]
        private(set) var lens=FunLens(0.62)
        private(set) var scaleX=Track(1),scaleY=Track(1),face=Track(1),strain=Track(0),tint=Track(0)
        private var amplitude:[(at:Double,value:Double)]=[]
        private var stages:[(at:Double,value:Int)]=[]
        private(set) var dotFlight:Double?
        private(set) var settle:Double?
        private(set) var boom:Double?
        private(set) var burst:Burst?
        init(start:Double,seed:UInt64) {
            self.start=start;self.seed=seed
            var random=FunRandom(seed)
            let fracture=Fracture(&random)
            self.fracture=fracture
            cracks=(0...3).map { LensPicture.cracks(fracture.lines($0)) }
        }
        var regrow:Double? { burst.map { $0.at+4.3 } }
        /// When it's over for clicks and pointing: settled, or cleared away after growing back.
        var over:Double { settle ?? regrow.map { $0+1.5 } ?? .infinity }
        /// When nothing of it moves any more.
        var done:Double {
            if let settle { return settle+(dotFlight != nil ? 0.56 : 0) }
            return regrow.map { $0+1.5 } ?? .infinity
        }
        /// When the hover's bulge goes with it.
        var bulgeLost:Double? { settle ?? regrow }
        func bursting(at t:Double)->Bool { boom.map { t >= $0 } ?? false }
        func stage(at t:Double)->Int { stages.last { $0.at <= t }?.value ?? 0 }

        mutating func click(at t:Double) {
            cut(after:t)
            // A click while it settles doesn't stop it settling (the design's settling isn't called off).
            let settling=settle
            let count=(steps.last { $0.at <= t }?.count ?? 0)+1
            steps.append((t,count))
            if count >= 6 { blowUp(at:t);return }
            pump(at:t,count,up:true)
            var time=t+1.7,left=count
            while left > 0 {
                left-=1
                steps.append((time,left));pump(at:time,left,up:false)
                if left == 0 { settle=time+0.56 } else { time+=0.48 }
            }
            if let settling { settle=settling }
        }
        private mutating func cut(after t:Double) {
            steps.removeAll { $0.at > t }
            lens.cut(after:t);scaleX.cut(after:t);scaleY.cut(after:t);face.cut(after:t);strain.cut(after:t);tint.cut(after:t)
            amplitude.removeAll { $0.at > t };stages.removeAll { $0.at > t }
            if let settle,settle-0.56 > t { self.settle=nil }
        }
        /// A pump in (a click) or out (left alone): the ring squashes and stretches, the face follows a beat later;
        /// from the third it strains.
        private mutating func pump(at t:Double,_ count:Int,up:Bool) {
            let k=Double(count),ps=1+0.06*k,fs=1+0.085*max(0,k-1)
            lens.animate(at:t,to:0.62+0.066*k,up ? 0.78 : 0.52,up ? .outElastic(1,0.42) : .outQuad)
            if up {
                scaleX.animate(at:t,[.init(to:ps*1.13,duration:0.07),.init(to:ps*0.93,duration:0.15,curve:.inOutQuad),.init(to:ps,duration:0.64,curve:.outElastic(1,0.5))])
                scaleY.animate(at:t,[.init(to:ps*0.85,duration:0.07),.init(to:ps*1.1,duration:0.15,curve:.inOutQuad),.init(to:ps,duration:0.64,curve:.outElastic(1,0.5))])
            } else {
                scaleX.animate(at:t,[.init(to:ps*0.9,duration:0.09),.init(to:ps,duration:0.54,curve:.outElastic(1,0.45))])
                scaleY.animate(at:t,[.init(to:ps*1.08,duration:0.09),.init(to:ps,duration:0.54,curve:.outElastic(1,0.45))])
            }
            face.animate(at:t,[.init(to:fs*(up ? 1.07 : 0.96),duration:0.13,delay:0.045),.init(to:fs,duration:0.72,curve:.outElastic(1,0.38))])
            let strain=max(0,k-2)
            self.strain.transition(at:t,to:strain,0.35)
            tint.transition(at:t,to:min(0.85,k*0.15),0.4)
            amplitude.append((t,strain*0.55))
            stages.append((t,max(0,count-3)))
            // The third pump in: the online dot can't hold on and pops off.
            if up && count == 3 && dotFlight == nil { dotFlight=t }
        }
        /// The wind-up: it swells hard against its ring, trembling, takes one last breath in... and bursts 470 ms on.
        private mutating func blowUp(at t:Double) {
            boom=t
            amplitude.append((t,1.5));stages.append((t,3))
            tint.transition(at:t,to:0.9,0.4)
            lens.animate(at:t,to:0.97,0.43,.inQuad)
            face.animate(at:t,[.init(to:1.44,duration:0.3,curve:.inQuad),.init(to:1.38,duration:0.095),.init(to:1.5,duration:0.07,curve:.inQuad)])
            scaleX.animate(at:t,[.init(to:1.34,duration:0.3,curve:.inQuad),.init(to:1.4,duration:0.095),.init(to:1.28,duration:0.07,curve:.inQuad)])
            scaleY.animate(at:t,[.init(to:1.34,duration:0.3,curve:.inQuad),.init(to:1.28,duration:0.095),.init(to:1.42,duration:0.07,curve:.inQuad)])
        }
        mutating func prepareBurst(_ picture:LensPicture,shell:CGSize) {
            guard let boom else { return }
            let at=boom+0.47,grown=face.value(at:at),nudge=shake(at:at)
            let width=66*grown*scaleX.value(at:at),height=66*grown*scaleY.value(at:at)
            // The ring's middle in the pop-out: 12 in, 36 above the banner's 58.
            let box=CGRect(x:50+nudge.width-width/2,y:60+nudge.height-height/2,width:width,height:height)
            burst=Burst(at:at,box:box,texture:picture.pieces(lens.value(at:at),cracks:cracks[3]),fracture:fracture,size:shell,seed:seed)
        }
        /// The tremble: a small random nudge about 30 times a second, as far as the strain goes.
        func shake(at t:Double)->CGSize {
            let amplitude=amplitude.last { $0.at <= t }?.value ?? 0
            guard amplitude > 0 else { return .zero }
            var random=FunRandom(seed^(UInt64(max(0,t*30))&*0x2545F4914F6CDD1D))
            return CGSize(width:random.range(-1,1)*amplitude,height:random.range(-1,1)*amplitude)
        }
        /// The pumped copy's dot, flying off in an arc on the third pump.
        func flyingDot(at t:Double)->DotLook {
            guard let f=dotFlight,t >= f else { return DotLook() }
            return DotLook(x:Tween(start:f,from:0,keys:[.init(to:70,duration:0.82,curve:.linear)]).value(at:t),
                           y:Tween(start:f,from:0,keys:[.init(to:-32,duration:0.28),.init(to:170,duration:0.56,curve:.inQuad)]).value(at:t),
                           scale:Tween(start:f,from:1,keys:[.init(to:1.25,duration:0.09),.init(to:1,duration:0.2)]).value(at:t),
                           opacity:Tween(start:f,from:1,keys:[.init(to:1,duration:0.6),.init(to:0,duration:0.24)]).value(at:t))
        }
        /// The dot dropping back in from above, bouncing.
        static func dotBack(from start:Double,at t:Double)->DotLook {
            DotLook(y:Tween(start:start,from:-34,keys:[.init(to:0,duration:0.56,curve:.outBounce)]).value(at:t),
                    scale:Tween(start:start,from:0.4,keys:[.init(to:1,duration:0.32,curve:.outBack(2))]).value(at:t),
                    opacity:Tween(start:start,from:0,keys:[.init(to:1,duration:0.12)]).value(at:t))
        }
    }
}

/// The burst, worked out once as the design does: the cells, then confetti in Juno's colours bouncing off the pop-out's
/// walls; and the jolt.
struct Burst {
    enum Kind {
        /// A cell of the picture (its corners in the picture's units) and the point it turns about.
        case cell([CGPoint],anchor:CGPoint)
        case dot(size:Double,color:Color)
        case star(size:Double,color:Color)
    }
    struct Piece {
        let kind:Kind
        /// Where it starts, the point it turns about, in the pop-out.
        let origin:CGPoint
        let fadeAt:Double
        let fadeFor:Double
        let shrink:Double
    }
    struct Spot { let x:Double;let y:Double;let turn:Double }
    let at:Double
    /// The face as it burst, in the pop-out, and the tip of its nose.
    let box:CGRect
    let nose:CGPoint
    let texture:CGImage
    let pieces:[Piece]
    /// Where each piece is, 60 times a second.
    let frames:[[Spot]]
    /// The pop-out's shift, 60 times a second.
    let shifts:[CGSize]
    init(at:Double,box:CGRect,texture:CGImage,fracture:Fracture,size:CGSize,seed:UInt64) {
        self.at=at;self.box=box;self.texture=texture
        var random=FunRandom(seed^0x5DEECE66D)
        let nose=CGPoint(x:box.minX+Fracture.nose.x*box.width,y:box.minY+Fracture.nose.y*box.height)
        self.nose=nose
        struct Body { var x=0.0,y=0.0,vx:Double,vy:Double,a=0.0,va:Double;let g:Double,e:Double,m:Double;let cx:Double,cy:Double }
        var pieces:[Piece]=[],bodies:[Body]=[]
        for cell in fracture.cells {
            let gx=cell.map(\.x).reduce(0,+)/Double(cell.count),gy=cell.map(\.y).reduce(0,+)/Double(cell.count)
            let ax=min(0.95,max(0.05,gx)),ay=min(0.95,max(0.05,gy))
            let dx=gx-Fracture.nose.x,dy=gy-Fracture.nose.y,length=hypot(dx,dy),dist=length == 0 ? 0.01 : length
            let speed=150+dist*420+random.range(0,80)
            let origin=CGPoint(x:box.minX+ax*box.width,y:box.minY+ay*box.height)
            bodies.append(Body(vx:dx/dist*speed+random.range(-25,25),vy:dy/dist*speed-random.range(120,220),va:random.range(-380,380),g:1300,e:0.3,m:9,cx:origin.x,cy:origin.y))
            pieces.append(Piece(kind:.cell(cell,anchor:CGPoint(x:ax,y:ay)),origin:origin,fadeAt:random.range(0.9,1.2),fadeFor:0.5,shrink:0.6))
        }
        let colors=[Color.rgb(255,150,205),Color.rgb(205,160,255),Color.rgb(140,220,255),Color.rgb(255,236,170),Color.white]
        for i in 0..<8 {
            let z=random.range(5,10),star=i%3 != 0
            let angle=random.range(0,2*Double.pi),speed=random.range(220,460)
            bodies.append(Body(vx:cos(angle)*speed,vy:sin(angle)*speed-160,va:random.range(-900,900),g:760,e:0.5,m:4,cx:nose.x,cy:nose.y))
            pieces.append(Piece(kind:star ? .star(size:z,color:colors[i%5]) : .dot(size:z,color:colors[i%5]),origin:nose,fadeAt:random.range(0.45,0.8),fadeFor:0.45,shrink:0.3))
        }
        self.pieces=pieces
        let dt=1.0/60,life=pieces.map { $0.fadeAt+$0.fadeFor }.max() ?? 0,wide=Double(size.width),high=Double(size.height)
        var frames:[[Spot]]=[bodies.map { Spot(x:$0.x,y:$0.y,turn:$0.a) }],time=0.0
        while time < life {
            time+=dt
            for i in bodies.indices {
                var b=bodies[i]
                b.vy+=b.g*dt;b.x+=b.vx*dt;b.y+=b.vy*dt;b.a+=b.va*dt
                let px=b.cx+b.x,py=b.cy+b.y
                if px < b.m { b.x=b.m-b.cx;b.vx=abs(b.vx)*b.e;b.va*=0.7 } else if px > wide-b.m { b.x=wide-b.m-b.cx;b.vx = -abs(b.vx)*b.e;b.va*=0.7 }
                if py < b.m { b.y=b.m-b.cy;b.vy=abs(b.vy)*b.e } else if py > high-b.m {
                    b.y=high-b.m-b.cy;b.vy = -abs(b.vy)*b.e;b.vx*=0.76;b.va*=0.55
                    if abs(b.vy) < 50 { b.vy=0 }
                }
                bodies[i]=b
            }
            frames.append(bodies.map { Spot(x:$0.x,y:$0.y,turn:$0.a) })
        }
        self.frames=frames
        // The jolt: anime.js shakes the pop-out, whose transform eases every change over 0.5 s, so the shake shows
        // smoothed and late.
        let x=Tween(start:0,from:0,keys:[.init(to:-3,duration:0.045),.init(to:2.5,duration:0.05),.init(to:-1.5,duration:0.055),.init(to:0,duration:0.07)])
        let y=Tween(start:0,from:0,keys:[.init(to:2,duration:0.045),.init(to:-2,duration:0.05),.init(to:1,duration:0.055),.init(to:0,duration:0.07)])
        var shifts:[CGSize]=[],from=CGSize.zero,to=CGSize.zero,since=0.0
        func eased(_ t:Double)->CGSize {
            let p=Ease.out(min(1,(t-since)/0.5))
            return CGSize(width:mix(from.width,to.width,p),height:mix(from.height,to.height,p))
        }
        for n in 0...Int(0.75*60) {
            let t=Double(n)*dt,target=t < 0.22 ? CGSize(width:x.value(at:t),height:y.value(at:t)) : .zero
            if target != to { from=eased(t);to=target;since=t }
            shifts.append(eased(t))
        }
        self.shifts=shifts
    }
    /// Where a piece is, between the frames worked out.
    func spot(_ i:Int,at time:Double)->Spot {
        let frame=time*60,n=min(frames.count-1,Int(frame)),m=min(frames.count-1,n+1),f=frame-Double(Int(frame))
        let a=frames[n][i],b=frames[m][i]
        return Spot(x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f,turn:a.turn+(b.turn-a.turn)*f)
    }
}

/// Over the pop-out: the pumped picture straining in its ring, and the burst, inside the pop-out's corners.
struct ProfileFunLayer: View {
    let fun:ProfileFun
    var body:some View {
        TimelineView(.animation(paused:!fun.ticking)) { context in
            let t=context.date.timeIntervalSinceReferenceDate
            ZStack(alignment:.topLeading) {
                if let burst=fun.burst(at:t) { BurstView(burst:burst.0,time:burst.1).clipShape(RoundedRectangle(cornerRadius:10)) }
                if let look=fun.pump(at:t) { PumpedPicture(look:look).offset(x:12,y:22) }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .allowsHitTesting(false)
        }
    }
}

/// The pop-out flaring as the picture bursts: CSS's saturate, contrast, brightness and hue-rotate in turn.
struct FunJolt: ViewModifier {
    let fun:ProfileFun
    func body(content:Content)->some View {
        TimelineView(.animation(paused:!fun.ticking)) { context in
            let jolt=fun.jolt(at:context.date.timeIntervalSinceReferenceDate)
            content.offset(jolt.shift)
                .saturation(jolt.saturation).contrast(jolt.contrast*jolt.brightness).brightness((jolt.brightness-1)/2).hueRotation(.degrees(jolt.hue))
        }
    }
}

/// The pumped copy: the ring glowing pink as it strains, the bulging face blushing and cracking, and its dot.
private struct PumpedPicture: View {
    let look:ProfileFun.PumpLook
    var body:some View {
        ZStack(alignment:.topLeading) {
            ZStack {
                if look.strain > 0 {
                    // The design's box-shadows: a blurred pink glow, under a ring as wide as the strain.
                    Circle().fill(Color.rgb(255,90,150).opacity(0.2*look.strain)).blur(radius:4.5*look.strain)
                    Circle().fill(Color.rgb(255,120,170).opacity(0.16*look.strain)).padding(-look.strain)
                }
                Circle().fill(DiscordColors.popout)
            }
            .frame(width:76,height:76)
            ZStack {
                Image(decorative:look.lens,scale:2)
                Blush().opacity(look.tint)
                if let cracks=look.cracks { Image(decorative:cracks,scale:2) }
            }
            .frame(width:66,height:66).clipShape(Circle())
            .scaleEffect(look.face)
            .offset(x:5,y:5)
            OnlineDot().scaleEffect(look.dot.scale).offset(x:51+look.dot.x,y:51+look.dot.y).opacity(look.dot.opacity)
        }
        .frame(width:76,height:76,alignment:.topLeading)
        .scaleEffect(x:look.scaleX,y:look.scaleY)
        .offset(look.shake)
    }
}
/// Pink cheeks: the design's two radial gradients.
private struct Blush: View {
    var body:some View {
        let pink=Color.rgb(255,92,140)
        ZStack {
            ForEach([0.33,0.73],id:\.self) { x in
                let reach=0.22*hypot(max(x,1-x)*66,max(0.64,0.36)*66)
                RadialGradient(colors:[pink.opacity(0.6),pink.opacity(0)],center:UnitPoint(x:x,y:0.64),startRadius:0,endRadius:reach)
            }
        }
    }
}

/// The burst: a flash and ring from the nose, the pieces, and ". . . oh moons", all fading out after 3.7 s.
private struct BurstView: View {
    let burst:Burst
    let time:Double
    private static let words=L(". . . oh moons")
    private static let font=DiscordFont.nsFont(22,600)
    var body:some View {
        Canvas { context,_ in
            let nose=burst.nose
            if time < 0.26 {
                let scale=0.5+0.9*Ease.outQuad(time/0.24),radius=60*scale
                var c=context
                c.opacity=0.7*(1-Ease.inQuad(time/0.26))
                let glow=Gradient(stops:[.init(color:.white.opacity(0.95),location:0),.init(color:Color.rgb(255,220,240).opacity(0.5),location:0.4),
                                          .init(color:Color.rgb(255,220,240).opacity(0),location:0.7)])
                c.fill(Path(ellipseIn:CGRect(x:nose.x-radius,y:nose.y-radius,width:radius*2,height:radius*2)),
                       with:.radialGradient(glow,center:nose,startRadius:0,endRadius:60*2.squareRoot()*scale))
            }
            if time < 0.56 {
                let scale=0.4+1.7*Ease.outExpo(time/0.56),border=(6-5*Ease.outQuad(time/0.64))*scale,radius=50*scale-border/2
                var c=context
                c.opacity=0.6*(1-Ease.inQuad(time/0.56))
                c.stroke(Path(ellipseIn:CGRect(x:nose.x-radius,y:nose.y-radius,width:radius*2,height:radius*2)),with:.color(Color.rgb(255,190,225).opacity(0.9)),lineWidth:border)
            }
            for (i,piece) in burst.pieces.enumerated() {
                let fade=time < piece.fadeAt ? 1 : max(0,1-(time-piece.fadeAt)/piece.fadeFor)
                guard fade > 0 else { continue }
                let spot=burst.spot(i,at:time),scale=piece.shrink+(1-piece.shrink)*fade
                var c=context
                c.opacity=fade
                c.translateBy(x:piece.origin.x+spot.x,y:piece.origin.y+spot.y)
                c.rotate(by:.degrees(spot.turn))
                c.scaleBy(x:scale,y:scale)
                switch piece.kind {
                case .cell(let cell,let anchor):
                    let box=burst.box
                    c.translateBy(x:-anchor.x*box.width,y:-anchor.y*box.height)
                    c.clip(to:Path { path in path.addLines(cell.map { CGPoint(x:$0.x*box.width,y:$0.y*box.height) });path.closeSubpath() })
                    c.addFilter(.shadow(color:.black.opacity(0.35),radius:1,x:0,y:2))
                    c.draw(Image(decorative:burst.texture,scale:1),in:CGRect(origin:.zero,size:box.size))
                case .dot(let z,let color):
                    c.addFilter(.shadow(color:Color.rgb(255,200,240).opacity(0.8),radius:3))
                    c.fill(Path(ellipseIn:CGRect(x:-z/2,y:-z/2,width:z,height:z)),with:.color(color))
                case .star(let z,let color):
                    let points=[(0.5,0.0),(0.62,0.38),(1,0.5),(0.62,0.62),(0.5,1),(0.38,0.62),(0,0.5),(0.38,0.38)]
                    c.fill(Path { path in path.addLines(points.map { CGPoint(x:($0.0-0.5)*z,y:($0.1-0.5)*z) });path.closeSubpath() },with:.color(color))
                }
            }
        }
        .overlay(alignment:.top) { words }
    }
    /// ". . . oh moons": a dot every 170 ms, a breath, then the letters 45 ms apart, each fading in from the left.
    private var words:some View {
        let since=time-0.14,letters=Array(Self.words).map(String.init),widths=letters.map { ($0 as NSString).size(withAttributes:[.font:Self.font]).width }
        return ZStack(alignment:.topLeading) {
            ForEach(letters.indices,id:\.self) { i in
                let begin=i < 6 ? Double(i)*0.17 : 1.28+Double(i-6)*0.045,local=since-begin,out=since-3.7-0.022*Double(i)
                let opacity=local <= 0 ? 0 : Ease.outQuad(local/0.36)*(out > 0 ? 1-Ease.inQuad(out/0.3) : 1)
                Text(verbatim:letters[i]).discordFont(22,600,line:28).foregroundStyle(DiscordColors.title).fixedSize()
                    .frame(width:widths[i],height:28,alignment:.leading)
                    .shadow(color:.black.opacity(0.5),radius:1.5,y:1)
                    .offset(x:widths[..<i].reduce(0,+)-(local > 0 ? 6*(1-Ease.outCubic(local/0.42)) : 0))
                    .opacity(opacity)
            }
        }
        .frame(width:widths.reduce(0,+),height:28,alignment:.topLeading)
        .padding(.top,17)
        .opacity(since > 0 ? 1 : 0)
    }
}
