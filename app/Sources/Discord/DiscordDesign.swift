import SwiftUI
import AppKit
import CoreText

// The design's look for Discord's pages: its colours, SVG icons (Lucide, Phosphor, Material Design Icons, Material
// Icons, Simple Icons, and its own "rc" set; licenses/DESIGN-ICONS-NOTICE.txt) and Noto Sans.

extension Color {
    /// A colour as the design writes it, 0 to 255 a channel.
    static func rgb(_ r:Double,_ g:Double,_ b:Double)->Color { Color(red:r/255,green:g/255,blue:b/255) }
}
extension DiscordColors {
    /// What's chosen in Customize's lists, rings and counts.
    static let accent=Color.rgb(255,150,96)
    /// Links and the breadcrumb.
    static let link=Color.rgb(255,152,104)
    /// Customize's buttons, and the same a little lighter while pointed at.
    static let fill=Color.rgb(236,106,46)
    static let fillHover=Color.rgb(246,120,58)
    /// The design's text on dark: white with a touch of blue at the given strength (black in light mode).
    static func ink(_ alpha:Double)->Color {
        Color(nsColor:NSColor(name:nil) { appearance in
            appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(srgbRed:235/255,green:235/255,blue:245/255,alpha:alpha)
                                                                       : NSColor(white:0,alpha:min(1,alpha*1.15))
        })
    }
    /// The design's "#fff": white on dark, the label colour on light.
    static let bright=Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? .white : .labelColor })
    /// The design's text where it gives no colour of its own (its page's rgba(255,255,255,0.92)); the label colour on light.
    static let body=Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(white:1,alpha:0.92) : .labelColor })
    /// A white veil of the given strength (black in light mode): the design's rgba(255,255,255,a) surfaces.
    static func veil(_ alpha:Double)->Color {
        Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(white:1,alpha:alpha) : NSColor(white:0,alpha:alpha) })
    }
    /// The design's ribbon (Customize, the underlines): amber, orange, pink, violet, orange, amber, blended "in oklch"
    /// as the browser does.
    static let ribbon:[Gradient.Stop]=oklch([(255,184,92),(255,128,64),(255,92,138),(214,98,230),(236,106,46),(255,184,92)])
    /// The design's gradient frame (Customize's morph): amber, orange, pink, violet, blended the same way.
    static let frame:[Gradient.Stop]=oklch([(255,184,92),(255,128,64),(255,92,138),(214,98,230)])
    private static func oklch(_ colors:[(Double,Double,Double)])->[Gradient.Stop] {
        let points=colors.map { OKLCH.point($0.0/255,$0.1/255,$0.2/255) }
        var stops:[Gradient.Stop]=[]
        for index in 0..<points.count-1 {
            let a=points[index],b=points[index+1]
            var turn=b.h-a.h
            if turn > Double.pi { turn -= 2*Double.pi } else if turn < -Double.pi { turn += 2*Double.pi }
            for step in 0..<8 {
                let t=Double(step)/8
                stops.append(.init(color:OKLCH.color(a.l+(b.l-a.l)*t,a.c+(b.c-a.c)*t,a.h+turn*t),location:(Double(index)+t)/Double(points.count-1)))
            }
        }
        stops.append(.init(color:OKLCH.color(points.last!.l,points.last!.c,points.last!.h),location:1))
        return stops
    }
}
extension DiscordColors {
    /// The banner's sweep: indigo, violet, pink, blended in OKLab.
    static let banner:[Gradient.Stop]=OKLCH.labStops([(0.42,0.15,285,0),(0.52,0.19,315,0.55),(0.6,0.19,345,1)])
}
/// sRGB to OKLCH and back (OKLab), as CSS's "in oklch" blends; out-of-range channels clipped.
private enum OKLCH {
    /// Stops blended straight through OKLab between OKLCH colours (lightness, chroma, hue in degrees, location).
    static func labStops(_ points:[(Double,Double,Double,Double)])->[Gradient.Stop] {
        var stops:[Gradient.Stop]=[]
        for index in 0..<points.count-1 {
            let a=points[index],b=points[index+1],ha=a.2*Double.pi/180,hb=b.2*Double.pi/180
            let (aa,ab,ba,bb)=(a.1*cos(ha),a.1*sin(ha),b.1*cos(hb),b.1*sin(hb))
            for step in 0..<8 {
                let t=Double(step)/8,x=aa+(ba-aa)*t,y=ab+(bb-ab)*t
                stops.append(.init(color:color(a.0+(b.0-a.0)*t,(x*x+y*y).squareRoot(),atan2(y,x)),location:a.3+(b.3-a.3)*t))
            }
        }
        let last=points[points.count-1]
        stops.append(.init(color:color(last.0,last.1,last.2*Double.pi/180),location:last.3))
        return stops
    }
    static func point(_ r:Double,_ g:Double,_ b:Double)->(l:Double,c:Double,h:Double) {
        func linear(_ x:Double)->Double { x <= 0.04045 ? x/12.92 : pow((x+0.055)/1.055,2.4) }
        let (R,G,B)=(linear(r),linear(g),linear(b))
        let l=cbrt(0.4122214708*R+0.5363325363*G+0.0514459929*B),m=cbrt(0.2119034982*R+0.6806995451*G+0.1073969566*B)
        let s=cbrt(0.0883024619*R+0.2817188376*G+0.6299787005*B)
        let L=0.2104542553*l+0.7936177850*m-0.0040720468*s,A=1.9779984951*l-2.4285922050*m+0.4505937099*s
        let Bb=0.0259040371*l+0.7827717662*m-0.8086757660*s
        return (L,(A*A+Bb*Bb).squareRoot(),atan2(Bb,A))
    }
    static func color(_ L:Double,_ C:Double,_ h:Double)->Color {
        let a=C*cos(h),b=C*sin(h)
        let l=pow(L+0.3963377774*a+0.2158037573*b,3),m=pow(L-0.1055613458*a-0.0638541728*b,3),s=pow(L-0.0894841775*a-1.2914855480*b,3)
        func encoded(_ x:Double)->Double { min(max(x <= 0.0031308 ? 12.92*x : 1.055*pow(x,1/2.4)-0.055,0),1) }
        return Color(.sRGB,red:encoded(4.0767416621*l-3.3077115913*m+0.2309699292*s),green:encoded(-1.2684380046*l+2.6097574011*m-0.3413193965*s),
                     blue:encoded(-0.0041960863*l-0.7034186147*m+1.7076147010*s))
    }
}

/// One of the design's icons, at a size (its height, as the design sizes them), in the foreground style.
struct DesignIcon: View {
    let name:String
    var size:CGFloat=14
    init(_ name:String,size:CGFloat=14) { self.name=name;self.size=size }
    var body:some View {
        let image=DesignIcons.image(name,height:size)
        Group {
            if let image { Image(nsImage:image).renderingMode(.template) } else { Color.clear }
        }.frame(width:image?.size.width ?? size,height:size).accessibilityHidden(true)
    }
}

@MainActor enum DesignIcons {
    private static var cache:[String:NSImage]=[:]
    /// The icon drawn from its SVG at the size it's shown (so it stays sharp), as a template the view tints.
    static func image(_ name:String,height:CGFloat)->NSImage? {
        let key="\(name)@\(height)"
        if let image=cache[key] { return image }
        guard let (width,tall,body)=bodies[name] else { return nil }
        let paths=body.replacingOccurrences(of:"currentColor",with:"#000")
        let svg="<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(tall)\" viewBox=\"0 0 \(width) \(tall)\">\(paths)</svg>"
        guard let image=NSImage(data:Data(svg.utf8)) else { return nil }
        image.size=NSSize(width:height*CGFloat(width)/CGFloat(tall),height:height)
        image.isTemplate=true
        cache[key]=image
        return image
    }
    /// Each icon's viewBox and SVG, as the design has them (app/Resources/Discord/DiscordIcons.json).
    private struct Body: Decodable { let w:Int;let h:Int;let svg:String }
    private static let bodies:[String:(Int,Int,String)]={
        guard let url=Bundle.main.url(forResource:"DiscordIcons",withExtension:"json"),let data=try? Data(contentsOf:url),
              let table=try? JSONDecoder().decode([String:Body].self,from:data) else { return [:] }
        return table.mapValues { ($0.w,$0.h,$0.svg) }
    }()
}

/// A font's size and weight, for the caches of them.
private struct FontKey: Hashable { let size:CGFloat;let weight:Int }
/// Noto Sans, the stand-in for Discord's gg sans (not free to bundle): Latin and Latin Extended. Other scripts fall
/// back as in Discord.
enum DiscordFont {
    private static let registered:[CTFontDescriptor]={
        guard let folder=Bundle.main.resourceURL else { return [] }
        return ["NotoSans-Latin","NotoSans-LatinExt"].compactMap { name in
            guard let data=try? Data(contentsOf:folder.appendingPathComponent(name+".woff2")) else { return nil }
            return (CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor])?.first
        }
    }()
    private static let lock=NSLock()
    nonisolated(unsafe) private static var fonts:[FontKey:NSFont]=[:]
    /// Noto Sans at a size and weight (400 regular, 600 semibold, 700 bold), or the system font without the files.
    static func nsFont(_ size:CGFloat,_ weight:Int=400)->NSFont {
        lock.lock();defer { lock.unlock() }
        let key=FontKey(size:size,weight:weight)
        if let font=fonts[key] { return font }
        let systemWeight:NSFont.Weight=weight >= 700 ? .bold : weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        guard let latin=registered.first else { return NSFont.systemFont(ofSize:size,weight:systemWeight) }
        // The weight axis ('wght'), then Latin Extended for the letters the Latin file doesn't have.
        let axis=0x77676874 as CFNumber
        var descriptor=CTFontDescriptorCreateCopyWithVariation(latin,axis,CGFloat(weight))
        // Then the system font at the same weight, so Hangul and Han are bold too.
        var cascade=[CTFontCopyFontDescriptor(NSFont.systemFont(ofSize:size,weight:systemWeight) as CTFont)]
        if registered.count > 1 { cascade.insert(CTFontDescriptorCreateCopyWithVariation(registered[1],axis,CGFloat(weight)),at:0) }
        descriptor=CTFontDescriptorCreateCopyWithAttributes(descriptor,[kCTFontCascadeListAttribute:cascade as CFArray] as CFDictionary)
        let font=CTFontCreateWithFontDescriptor(descriptor,size,nil) as NSFont
        fonts[key]=font
        return font
    }
}
/// SF Pro as the browser sets it: on the weight axis (AppKit's named weights run lighter and narrower).
enum SystemFont {
    private static let lock=NSLock()
    nonisolated(unsafe) private static var fonts:[FontKey:NSFont]=[:]
    static func nsFont(_ size:CGFloat,_ weight:Int=400)->NSFont {
        lock.lock();defer { lock.unlock() }
        let key=FontKey(size:size,weight:weight)
        if let font=fonts[key] { return font }
        // From the system font at the nearest named weight (its fallbacks for Hangul and Han follow it), then the axis.
        let named:NSFont.Weight=weight >= 700 ? .bold : weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        let descriptor=CTFontDescriptorCreateCopyWithVariation(CTFontCopyFontDescriptor(NSFont.systemFont(ofSize:size,weight:named) as CTFont),0x77676874 as CFNumber,CGFloat(weight))
        let font=CTFontCreateWithFontDescriptor(descriptor,size,nil) as NSFont
        fonts[key]=font
        return font
    }
    /// A SwiftUI weight as CSS numbers it.
    static func css(_ weight:Font.Weight)->Int {
        switch weight {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }
}
extension Font {
    /// Discord's text, as the design shows it (Noto Sans).
    static func discord(_ size:CGFloat,_ weight:Int=400)->Font { Font(DiscordFont.nsFont(size,weight)) }
}
extension Text {
    /// One text after another on the same line, each in its own style (`+` is deprecated on macOS 26).
    func followed(by next:Text)->Text { Text("\(self)\(next)") }
}

/// Text as the design's browser sets it: ascent and descent rounded to the half point; a `line-height` adds or takes
/// the difference, half above and the rest below.
enum DesignText {
    /// The width under `text-wrap: balance`: the narrowest taking no more lines than `width`, found by halving.
    static func balanced(_ text:String,_ font:NSFont,within width:CGFloat)->CGFloat {
        let storage=NSTextStorage(string:text,attributes:[.font:font]),layout=NSLayoutManager(),box=NSTextContainer(size:CGSize(width:width,height:.greatestFiniteMagnitude))
        box.lineFragmentPadding=0;layout.addTextContainer(box);storage.addLayoutManager(layout)
        func lines(_ width:CGFloat)->Int {
            box.size=CGSize(width:width,height:.greatestFiniteMagnitude)
            var count=0,index=0
            while index < layout.numberOfGlyphs { var range=NSRange();layout.lineFragmentRect(forGlyphAt:index,effectiveRange:&range);index=NSMaxRange(range);count+=1 }
            return count
        }
        let count=lines(width)
        guard count > 1 else { return width }
        var low:CGFloat=0,high=width
        while high-low > 0.25 { let middle=(low+high)/2;if lines(middle) > count { low=middle } else { high=middle } }
        return ceil(high*2)/2
    }
    /// How tall a line is and where its baseline sits below the line's top, for a CSS line-height in points (nil: normal).
    static func line(_ font:NSFont,_ height:CGFloat?)->(height:CGFloat,baseline:CGFloat) {
        let ascent=(font.ascender*2).rounded()/2,descent=(-font.descender*2).rounded()/2,height=height ?? ascent+descent
        return (height,ascent+(height-ascent-descent+0.001).rounded(.down)/2)
    }
    /// SwiftUI's own line spacing (without leading) and first baseline.
    static func plain(_ font:NSFont)->(pitch:CGFloat,baseline:CGFloat) {
        let pitch=NSAttributedString(string:"Ag",attributes:[.font:font]).boundingRect(with:CGSize(width:10_000,height:10_000),options:.usesLineFragmentOrigin).height
        return (pitch,NSLayoutManager().defaultBaselineOffset(for:font))
    }
    /// How cssLines sets a font's lines: with line spacing or an exact line height, then padding.
    struct Setting { let height:CGFloat,plain:Bool,spacing:CGFloat,top:CGFloat,bottom:CGFloat }
    static func setting(_ font:NSFont,_ height:CGFloat?,wraps:Bool)->Setting {
        let line=line(font,height),plain=plain(font)
        if !wraps || line.height >= plain.pitch {
            let top=line.baseline-plain.baseline
            return Setting(height:line.height,plain:true,spacing:max(0,line.height-plain.pitch),top:top,bottom:line.height-plain.pitch-top)
        }
        let shift=line.baseline-font.pointSize.rounded(.up)
        return Setting(height:line.height,plain:false,spacing:0,top:shift,bottom:-shift)
    }
    /// A font at a size, weight and line, worked out once (a page sets a hundred texts each build).
    static func style(discord:Bool,_ size:CGFloat,_ weight:Int,_ height:CGFloat?,wraps:Bool)->(font:Font,lines:Setting) {
        let key=StyleKey(discord:discord,size:size,weight:weight,height:height,wraps:wraps)
        lock.lock()
        if let known=styles[key] { lock.unlock();return known }
        lock.unlock()
        let font=discord ? DiscordFont.nsFont(size,weight) : SystemFont.nsFont(size,weight)
        let made=(Font(font),setting(font,height,wraps:wraps))
        lock.lock();styles[key]=made;lock.unlock()
        return made
    }
    private struct StyleKey: Hashable { let discord:Bool;let size:CGFloat;let weight:Int;let height:CGFloat?;let wraps:Bool }
    private static let lock=NSLock()
    nonisolated(unsafe) private static var styles:[StyleKey:(font:Font,lines:Setting)]=[:]
}
extension View {
    /// Lines as the browser sets them (DesignText): each `height` tall, the first baseline where the browser puts it.
    /// Text that `wraps` gets an exact line height (TextKit) where SwiftUI's own would be taller.
    func cssLines(_ font:NSFont,_ height:CGFloat?=nil,wraps:Bool=false)->some View {
        setLines(DesignText.setting(font,height,wraps:wraps))
    }
    @ViewBuilder fileprivate func setLines(_ set:DesignText.Setting)->some View {
        if set.plain {
            ExactLines(line:set.height) { lineSpacing(set.spacing).padding(.top,set.top).padding(.bottom,set.bottom) }
        } else {
            ExactLines(line:set.height) { lineHeight(.exact(points:set.height)).padding(.top,set.top).padding(.bottom,set.bottom) }
        }
    }
    /// The app's font set as the design sets it (`line`: CSS line-height; `wraps`: may take more than one line).
    func designFont(_ size:CGFloat,_ weight:Font.Weight = .regular,line:CGFloat?=nil,wraps:Bool=false)->some View {
        designFont(size,SystemFont.css(weight),line:line,wraps:wraps)
    }
    /// The same at a CSS weight between SwiftUI's (Customize's 650).
    func designFont(_ size:CGFloat,_ weight:Int,line:CGFloat?=nil,wraps:Bool=false)->some View {
        let style=DesignText.style(discord:false,size,weight,line,wraps:wraps)
        return font(style.font).setLines(style.lines)
    }
    /// Discord's font (Noto Sans) the same way.
    func discordFont(_ size:CGFloat,_ weight:Int=400,line:CGFloat?=nil,wraps:Bool=false)->some View {
        let style=DesignText.style(discord:true,size,weight,line,wraps:wraps)
        return font(style.font).setLines(style.lines)
    }
}

/// A text as tall as its lines add up to (SwiftUI rounds up to the pixel; the browser doesn't).
private struct ExactLines: Layout {
    let line:CGFloat
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        subviews.reduce(CGSize.zero) { size,view in
            let own=view.sizeThatFits(proposal),exact=(own.height/line).rounded()*line
            return CGSize(width:max(size.width,own.width),height:max(size.height,own.height >= exact && own.height-exact < 0.501 ? exact : own.height))
        }
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        for view in subviews { view.place(at:bounds.origin,proposal:ProposedViewSize(view.sizeThatFits(proposal))) }
    }
}

/// A column as the design's flexbox lays it out: `flexGrow` takes the room left; short of room, `flexShrink` views give
/// up height in proportion, none below its least.
struct FlexColumn: Layout {
    var spacing:CGFloat=0
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let heights=heights(width:proposal.width,room:proposal.height,subviews)
        return CGSize(width:proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0,
                      height:proposal.height ?? heights.reduce(0,+)+gaps(subviews))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        var y=bounds.minY
        for (subview,height) in zip(subviews,heights(width:bounds.width,room:bounds.height,subviews)) {
            subview.place(at:CGPoint(x:bounds.minX,y:y),proposal:ProposedViewSize(width:bounds.width,height:height))
            y+=height+spacing
        }
    }
    private func gaps(_ subviews:Subviews)->CGFloat { spacing*CGFloat(max(0,subviews.count-1)) }
    private func heights(width:CGFloat?,room:CGFloat?,_ subviews:Subviews)->[CGFloat] {
        let basis=subviews.map { $0[FlexGrow.self] ? 0 : $0.sizeThatFits(ProposedViewSize(width:width,height:nil)).height }
        guard let room else { return basis }
        let free=room-basis.reduce(0,+)-gaps(subviews)
        var heights=basis
        if free >= 0 {
            let growing=subviews.indices.filter { subviews[$0][FlexGrow.self] }
            for i in growing { heights[i]=free/CGFloat(growing.count) }
            return heights
        }
        // Share what's over among the views that can give, by size, again as each reaches its least.
        let least=subviews.map { $0[FlexShrink.self] ? $0.sizeThatFits(ProposedViewSize(width:width,height:0)).height : 0 }
        var open=subviews.indices.filter { subviews[$0][FlexShrink.self] && basis[$0] > least[$0] }
        while !open.isEmpty {
            let fixed=subviews.indices.filter { !open.contains($0) }.reduce(0) { $0+heights[$1] }
            let over=fixed+open.reduce(0) { $0+basis[$1] }+gaps(subviews)-room,total=open.reduce(0) { $0+basis[$1] }
            guard over > 0 else { break }
            var stuck:[Int]=[]
            for i in open {
                heights[i]=basis[i]-over*basis[i]/total
                if heights[i] < least[i] { heights[i]=least[i];stuck.append(i) }
            }
            if stuck.isEmpty { break }
            open.removeAll { stuck.contains($0) }
        }
        return heights
    }
}
private struct FlexShrink: LayoutValueKey { static let defaultValue=false }
private struct FlexGrow: LayoutValueKey { static let defaultValue=false }
extension View {
    /// In a FlexColumn: gives up height when the column is short of room, down to its least.
    func flexShrink()->some View { layoutValue(key:FlexShrink.self,value:true) }
    /// In a FlexColumn: takes the room left over.
    func flexGrow()->some View { layoutValue(key:FlexGrow.self,value:true) }
}
