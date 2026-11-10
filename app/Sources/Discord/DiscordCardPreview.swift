import SwiftUI
import AppKit

// Discord's card, drawn from the very activity Recall sends, so the preview can't say what the real card wouldn't. On a
// phone Discord shows no hover text or buttons.

enum DiscordColors {
    static let popout=Color.rgb(35,36,40)
    static let card=Color.rgb(71,71,77)
    static let title=Color.rgb(242,243,245)
    static let text=Color.rgb(219,222,225)
    static let muted=Color.rgb(181,186,193)
    static let timer=Color.rgb(134,197,153)
    static let button=Color.rgb(97,98,106)
    static let tile=Color.rgb(43,45,49)
    static let stage=Color.rgb(30,31,34)
    static let online=Color.rgb(35,165,90)
    /// The part being changed, outlined on the card.
    static let pick=Color.rgb(255,128,64)
    /// Text and marks on the accent fill.
    static let onAccent=Color.rgb(28,28,32)
    /// Good news: up a division, a first session.
    static let good=Color.rgb(94,214,160)
    /// Erasing for good.
    static let danger=Color.rgb(255,69,58)
    /// What went wrong, and what can't be used.
    static let warning=Color.rgb(255,110,100)
    /// Something that just happened.
    static let news=Color.rgb(255,110,110)
    /// In a match.
    static let inMatch=Color.rgb(110,170,255)
    /// In the group's voice chat, and tonight.
    static let voice=Color.rgb(96,206,222)
    /// The ribbon's first colour.
    static let amber=Color.rgb(255,184,92)
    /// Words on a chosen tile.
    static let chosen=Color.rgb(255,176,128)
    /// Small marks in the accent's light.
    static let glow=Color.rgb(255,170,120)
}

extension URLSession {
    /// Pictures and public records: cached, but no cookie kept or sent, and named only as Recall.
    static let cookieless:URLSession={
        let configuration=URLSessionConfiguration.default
        configuration.httpCookieStorage=nil;configuration.httpShouldSetCookies=false;configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders=["User-Agent":Brand.name]
        return URLSession(configuration:configuration)
    }()
}
/// Pictures from the web (heroes, ranks, the player's icon), kept once loaded. Discord loads the same ones.
@MainActor final class RemoteImages {
    static let shared=RemoteImages()
    private var images:[URL:NSImage]=[:]
    private var loading:Set<URL>=[]
    private var waiting:[URL:[()->Void]]=[:]
    /// Pictures that didn't come, and when: asked again only after a few minutes, not for every view that shows them.
    private var failed:[URL:Date]=[:]
    func image(_ url:URL)->NSImage? { images[url] ?? bundled(url) }
    /// The Mac badge and the Extra pictures: the app's own copies of the files Discord loads.
    private func bundled(_ url:URL)->NSImage? {
        guard let file=url == DiscordAssets.macBadge ? DiscordAssets.macBadgeFile : CardArt.allCases.first(where:{ DiscordAssets.art($0.file) == url })?.file,
              let image=Bundle.main.url(forResource:file,withExtension:nil).flatMap(NSImage.init(contentsOf:)) else { return nil }
        images[url]=image
        return image
    }
    func load(_ url:URL,done:@escaping ()->Void) {
        if image(url) != nil || failed[url].map({ Date().timeIntervalSince($0) < 300 }) == true { done();return }
        waiting[url,default:[]].append(done)
        guard !loading.contains(url) else { return }
        loading.insert(url)
        var request=URLRequest(url:url,cachePolicy:.returnCacheDataElseLoad,timeoutInterval:15)
        request.setValue(Brand.name,forHTTPHeaderField:"User-Agent")
        URLSession.cookieless.dataTask(with:request) { data,_,_ in
            let image=data.flatMap(NSImage.init(data:))
            Task { @MainActor in
                self.loading.remove(url);if let image { self.images[url]=image;self.failed[url]=nil } else { self.failed[url]=Date() }
                self.waiting.removeValue(forKey:url)?.forEach { $0() }
            }
        }.resume()
    }
    /// Loads them all, for a picture of the window taken at once (the tests' renders).
    func preload(_ urls:[URL]) async {
        await withCheckedContinuation { (done:CheckedContinuation<Void,Never>) in
            var left=Set(urls).count
            if left == 0 { done.resume();return }
            for url in Set(urls) { load(url) { left-=1;if left == 0 { done.resume() } } }
        }
    }
    /// The game's picture, shown when Recall sends none: Overwatch's icon, looked up once from Discord's public
    /// application record.
    private(set) var gameIcon:URL?
    /// Everyone who asked while it's being looked up hears when it's in.
    private var iconWaiting:[()->Void]=[]
    func lookUpGameIcon(done:@escaping ()->Void={}) {
        guard gameIcon == nil,let record=URL(string:"https://discord.com/api/v10/applications/\(DiscordAssets.applicationID)/rpc") else { done();return }
        iconWaiting.append(done)
        guard iconWaiting.count == 1 else { return }
        URLSession.cookieless.dataTask(with:URLRequest(url:record,cachePolicy:.returnCacheDataElseLoad,timeoutInterval:15)) { data,response,_ in
            let icon=(data.flatMap { try? JSONSerialization.jsonObject(with:$0) } as? [String:Any])?["icon"] as? String
            // For the support report: a listing Discord no longer has would stop every card.
            if let status=(response as? HTTPURLResponse)?.statusCode { DiscordAssets.listing=status == 200 ? "found" : status == 404 ? "missing" : nil }
            Task { @MainActor in
                if let icon,!icon.isEmpty,icon.allSatisfy({ $0.isASCII && $0.isHexDigit }) { self.gameIcon=URL(string:"https://cdn.discordapp.com/app-icons/\(DiscordAssets.applicationID)/\(icon).png?size=256") }
                let waiting=self.iconWaiting;self.iconWaiting=[];waiting.forEach { $0() }
            }
        }.resume()
    }
}
struct RemoteImage<Placeholder:View>: View {
    let url:URL?
    var fill=true
    @ViewBuilder var placeholder:Placeholder
    /// The picture loaded, with its address: one that comes in after the address changed isn't shown.
    @State private var loaded:(url:URL,image:NSImage)?
    var body:some View {
        Group {
            if let image=loaded.flatMap({ $0.url == url ? $0.image : nil }) ?? url.flatMap({ RemoteImages.shared.image($0) }) {
                if let moving=MovingImage.of(image),Moving.shared.now {
                    // A GIF plays, as Discord plays it (SwiftUI's Image shows its first frame only).
                    TimelineView(.periodic(from:.distantPast,by:moving.step)) { context in
                        Image(decorative:moving.frame(at:context.date),scale:1).resizable().interpolation(.high).aspectRatio(contentMode:fill ? .fill : .fit)
                    }
                } else {
                    Image(nsImage:image).resizable().interpolation(.high).aspectRatio(contentMode:fill ? .fill : .fit)
                }
            } else { placeholder }
        }
        .task(id:url) {
            guard let url else { loaded=nil;return }
            if let image=RemoteImages.shared.image(url) { loaded=(url,image);return }
            RemoteImages.shared.load(url) { if let image=RemoteImages.shared.image(url) { loaded=(url,image) } }
        }
    }
}
/// A GIF's frames and how long each shows, read once for each image.
struct MovingImage {
    let frames:[CGImage]
    let delays:[Double]
    /// The shortest frame: how often to look.
    var step:Double { delays.min() ?? 0.1 }
    /// The frame showing at `date`, all of them looping on one clock.
    func frame(at date:Date)->CGImage {
        let total=delays.reduce(0,+)
        var t=date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:total)
        for (frame,delay) in zip(frames,delays) { if t < delay { return frame };t-=delay }
        return frames[frames.count-1]
    }
    @MainActor private static var known:[ObjectIdentifier:MovingImage?]=[:]
    /// nil for a still image.
    @MainActor static func of(_ image:NSImage)->MovingImage? {
        let id=ObjectIdentifier(image)
        if let seen=known[id] { return seen }
        var found:MovingImage?
        if let rep=image.representations.first as? NSBitmapImageRep,let count=rep.value(forProperty:.frameCount) as? Int,count > 1 {
            var frames:[CGImage]=[],delays:[Double]=[]
            for index in 0..<count {
                rep.setProperty(.currentFrame,withValue:index)
                guard let frame=rep.cgImage else { continue }
                frames.append(frame);delays.append(max(0.02,rep.value(forProperty:.currentFrameDuration) as? Double ?? 0.1))
            }
            rep.setProperty(.currentFrame,withValue:0)
            if frames.count > 1 { found=MovingImage(frames:frames,delays:delays) }
        }
        known[id]=found
        return found
    }
}
/// Overwatch's own picture, as Discord shows it when the card sends none.
struct GameIcon: View {
    @State private var url=RemoteImages.shared.gameIcon
    var body:some View {
        RemoteImage(url:url) { Color.clear }
            .task { RemoteImages.shared.lookUpGameIcon { url=RemoteImages.shared.gameIcon } }
    }
}

// MARK: the design's tooltips

/// The design's tooltips: a dark bubble 200 ms after the pointer stops, inside the sheet. Discord's own (what friends
/// see on hover) wear Discord's mark and font.
@MainActor @Observable final class DesignTips {
    nonisolated static let space="discordSheet"
    struct Tip: Equatable { let text:String;let discord:Bool;let frame:CGRect;let below:Bool }
    var tip:Tip?
    /// The preview shows a phone: Discord's tips don't show.
    var phone=false
    @ObservationIgnored var discordTipShown:()->Void={}
    @ObservationIgnored private var waiting:Task<Void,Never>?
    func show(_ tip:Tip) {
        guard !(tip.discord && phone) else { return }
        waiting?.cancel()
        waiting=Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(200))
            guard let self,!Task.isCancelled else { return }
            self.tip=tip
            if tip.discord { self.discordTipShown() }
        }
    }
    func hide(_ text:String?=nil) {
        waiting?.cancel()
        if text == nil || tip?.text == text { tip=nil }
    }
}
extension View {
    /// A tooltip in the design's style (needs a DesignTipLayer above it); nil or empty shows none.
    func designTip(_ text:String?,discord:Bool=false,below:Bool=false)->some View { modifier(DesignTipped(text:text,discord:discord,below:below)) }
}
private struct DesignTipped: ViewModifier {
    let text:String?
    let discord:Bool
    let below:Bool
    @Environment(DesignTips.self) private var tips:DesignTips?
    @State private var frame=CGRect.zero
    func body(content:Content)->some View {
        content
            .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(DesignTips.space)) } action:{ frame=$0 }
            .onHover { inside in
                guard let tips,let text,!text.isEmpty else { return }
                if inside { tips.show(.init(text:text,discord:discord,frame:frame,below:below)) } else { tips.hide(text) }
            }
            .onDisappear { if let text { tips?.hide(text) } }
    }
}
/// Where the tooltips show: the sheet, with its own coordinate space.
struct DesignTipLayer<Content:View>: View {
    let tips:DesignTips
    @ViewBuilder var content:Content
    @State private var size=CGSize.zero
    var body:some View {
        content
            .coordinateSpace(.named(DesignTips.space))
            .environment(tips)
            .overlay(alignment:.topLeading) {
                GeometryReader { sheet in
                    if let tip=tips.tip {
                        bubble(tip)
                            .onGeometryChange(for:CGSize.self) { $0.size } action:{ size=$0 }
                            .offset(place(tip,in:sheet.size))
                            .transition(.asymmetric(insertion:.opacity.combined(with:.offset(y:tip.below ? -3 : 3)),removal:.opacity))
                            .id(tip.text)
                    }
                }.allowsHitTesting(false)
            }
            .animation(.easeOut(duration:0.16),value:tips.tip)
    }
    private func bubble(_ tip:DesignTips.Tip)->some View {
        // At most 260 points of words (CSS's max-width, inside the padding), as tall as they wrap to there.
        CappedWidth(most:260) {
            HStack(alignment:.top,spacing:7) {
                if tip.discord { DesignIcon("ic:baseline-discord",size:13).foregroundStyle(Color.rgb(150,160,255)).padding(.top,2) }
                Text(tip.text).font(tip.discord ? .discord(13,500) : Font(SystemFont.nsFont(11.5,500)))
                    .cssLines(tip.discord ? DiscordFont.nsFont(13,500) : NSFont.systemFont(ofSize:11.5),tip.discord ? 13*1.4 : 11.5*1.4,wraps:true)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }
        .foregroundStyle(DiscordColors.ink(0.92))
        .padding(.horizontal,tip.discord ? 10 : 9).padding(.vertical,tip.discord ? 7 : 6)
        .background(Color.rgb(17,18,20).opacity(0.95),in:RoundedRectangle(cornerRadius:8))
        .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(.white.opacity(0.07),lineWidth:1) }
        // One shadow for the whole bubble, not one for each line of text in it.
        .compositingGroup().shadow(color:.black.opacity(0.5),radius:14,y:10)
        .environment(\.colorScheme,.dark)
    }
    /// As wide as its one line, up to `most`; past that, wrapping at `most` and as tall as that makes it.
    private struct CappedWidth: Layout {
        let most:CGFloat
        func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
            guard let view=subviews.first else { return .zero }
            let width=min(most,view.sizeThatFits(.unspecified).width)
            return CGSize(width:width,height:view.sizeThatFits(ProposedViewSize(width:width,height:nil)).height)
        }
        func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
            subviews.first?.place(at:bounds.origin,proposal:ProposedViewSize(width:bounds.width,height:nil))
        }
    }
    /// Centred on what it's about, above it (below when asked, or when there's no room), inside the sheet.
    private func place(_ tip:DesignTips.Tip,in sheet:CGSize)->CGSize {
        let x=min(max(10,tip.frame.midX-size.width/2),sheet.width-size.width-10)
        var y=tip.below ? tip.frame.maxY+8 : tip.frame.minY-size.height-8
        if y < 10 || y+size.height > sheet.height-10 { y=tip.below ? tip.frame.minY-size.height-8 : tip.frame.maxY+8 }
        return CGSize(width:x,height:y)
    }
}

// MARK: the card

/// What takes turns, pinned on the card (My cards): how many pictures, badges, Line 1s and Line 2s.
struct CardPins: Equatable { var picture=0,badge=0,lineOne=0,lineTwo=0 }

/// The card, as Discord draws it (desktop or phone).
struct DiscordCardView: View {
    let activity:[String:Any]
    var now=Date()
    var phone=false
    /// The part being changed (Customize), outlined; a click on a part picks it.
    var selected:DiscordStudio.Slot?
    /// How long the selected part's outline waits before it fades in (as Customize opens).
    var outlineWait=0.0
    var pick:((DiscordStudio.Slot)->Void)?
    /// Counts of what takes turns, pinned to the parts (My cards).
    var pins:CardPins?
    /// Line 2's place in its turn while lines take turns (Discord's page), as a small ring after it.
    var lineTwoTurn:(done:Double,label:String)?
    /// The level and the clock's turn: a level's parts spring in one after another; a turn's Line 2 rises; anything
    /// else brightens.
    var level:DiscordPresenceLevel?=nil
    var turn:Int?=nil
    @State private var shownLevel:DiscordPresenceLevel?
    @State private var shownTurn:Int?
    @State private var shownDetails:String?
    @State private var shownBadge:String?
    /// Nothing arrives as the card itself first shows.
    @State private var appeared=false
    private static var badgeSprung=false
    private enum Arrival { case level,clock,other }
    private var arrival:Arrival {
        if let level,let shownLevel,level != shownLevel { return .level }
        if let turn,let shownTurn,turn != shownTurn { return .clock }
        return .other
    }
    private var assets:[String:String] { activity["assets"] as? [String:String] ?? [:] }
    private var details:String? { activity["details"] as? String }
    private var state:String? {
        guard let state=activity["state"] as? String else { return nil }
        // Discord puts the party's size after line 2.
        if let size=(activity["party"] as? [String:Any])?["size"] as? [Int],size.count == 2 { return "\(state) (\(L("{0} of {1}",String(size[0]),String(size[1]))))" }
        return state
    }
    private var buttons:[String] { (activity["buttons"] as? [[String:String]] ?? []).compactMap { $0["label"] } }
    private var elapsed:String {
        let start=(activity["timestamps"] as? [String:Int])?["start"] ?? Int(now.timeIntervalSince1970)
        return Self.clock(max(0,Int(now.timeIntervalSince1970)-start))
    }
    static func clock(_ seconds:Int)->String {
        let hours=seconds/3600
        return hours > 0 ? String(format:"%d:%02d:%02d",hours,seconds/60%60,seconds%60) : String(format:"%d:%02d",seconds/60,seconds%60)
    }
    var body:some View {
        Group { if phone { phoneCard } else { desktopCard } }
            .overlayPreferenceValue(CardPartBounds.self) { bounds in
                // The design's: a 260 ms ease-out fade in, or out at once.
                if let selected,let anchor=bounds[selected] {
                    PartHighlight(slot:selected,anchor:anchor)
                        .transition(.asymmetric(insertion:.opacity.animation(.easeOut(duration:0.26).delay(outlineWait)),removal:.atOnce))
                }
            }
            .environment(\.colorScheme,.dark)
            .onAppear { shownLevel=level;shownTurn=turn;shownDetails=details;shownBadge=assets["small_image"];appeared=true }
            .onChange(of:level) { _,level in
                shownLevel=level
                if let level,level != .normal { Self.badgeSprung=true }
            }
            .onChange(of:turn) { _,turn in shownTurn=turn }
            .onChange(of:details) { _,details in shownDetails=details }
            .onChange(of:assets["small_image"]) { _,badge in shownBadge=badge }
    }
    /// In Customize, what the clock changes glows for a moment.
    private var glows:Bool { arrival == .clock && selected != nil }
    /// How a line arrives: with a level, fading in (Line 2 a moment after Line 1); with the clock, Line 2 rising;
    /// otherwise brightening.
    private func lineArrival(second:Bool)->(start:ArrivalStart,animation:Animation)? {
        guard appeared else { return nil }
        switch arrival {
        case .level:
            let after=second && details != nil && details != shownDetails
            return (ArrivalStart(opacity:0.001),.curve(.outCubic,0.4).delay(after ? 0.07 : 0))
        case .clock where second: return (ArrivalStart(y:4,opacity:0),.curve(.outCubic,0.3))
        default: return (ArrivalStart(opacity:0.4),.curve(.outQuad,0.24))
        }
    }
    /// The badge as a level changes it: springing from small the first time up from Basic; otherwise fading in.
    private var badgeArrival:(start:ArrivalStart,animation:Animation)? {
        guard appeared,arrival == .level,let level,let shownLevel else { return nil }
        if shownLevel == .normal { return Self.badgeSprung ? nil : (ArrivalStart(scale:0.3),.curve(.outElastic(1,0.5),0.85)) }
        return level != .normal && assets["small_image"] != shownBadge ? (ArrivalStart(opacity:0.35),.curve(.outQuad,0.26)) : nil
    }
    /// The buttons: with a level, fading in a moment after the lines; otherwise at once.
    private var buttonsArrival:(start:ArrivalStart,animation:Animation)? {
        guard appeared else { return nil }
        return arrival == .level ? (ArrivalStart(opacity:0.001),.curve(.outCubic,0.4).delay(0.15)) : (ArrivalStart(opacity:0),.curve(.css,0.35))
    }
    private var desktopCard:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(L("Playing")).discordFont(13,700).foregroundStyle(DiscordColors.title)
                Spacer()
                DesignIcon("mdi:dots-horizontal",size:18).foregroundStyle(DiscordColors.text)
            }.frame(height:18)
            HStack(alignment:.center,spacing:12) {
                pictures(size:64,radius:8,badge:28,inner:22,badgeBack:DiscordColors.card)
                VStack(alignment:.leading,spacing:1) {
                    Text(verbatim:"Overwatch").discordFont(16,600,line:20).foregroundStyle(DiscordColors.title)
                        .designTip(phone ? nil : L("Always shown. Discord takes the name from the game."))
                    lines(height:18,pinned:true)
                }.font(.discord(14)).foregroundStyle(DiscordColors.text).frame(maxWidth:.infinity,alignment:.leading)
            }
            if !buttons.isEmpty {
                part(.buttons) {
                    HStack(spacing:8) {
                        ForEach(buttons,id:\.self) { label in
                            Text(verbatim:label).discordFont(14,500).foregroundStyle(.white).lineLimit(1)
                                .frame(maxWidth:.infinity).frame(height:32).background(DiscordColors.button,in:RoundedRectangle(cornerRadius:8))
                        }
                    }
                }
                .modifier(PartArrival(trigger:0,buttonsArrival)).transition(.identity)
            }
        }
        .padding(EdgeInsets(top:10,leading:12,bottom:12,trailing:12))
        .background(DiscordColors.card,in:RoundedRectangle(cornerRadius:8))
    }
    private var phoneCard:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("Playing")).discordFont(14,700).foregroundStyle(DiscordColors.title)
            HStack(alignment:.center,spacing:14) {
                pictures(size:76,radius:10,badge:30,inner:24,badgeBack:DiscordColors.tile)
                VStack(alignment:.leading,spacing:0) {
                    Text(verbatim:"Overwatch").discordFont(17,600,line:22).foregroundStyle(DiscordColors.title)
                    lines(height:20,pinned:false)
                }.font(.discord(15)).foregroundStyle(DiscordColors.text).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
        .padding(14)
        .background(DiscordColors.tile,in:RoundedRectangle(cornerRadius:14))
    }
    /// Line 1, Line 2 and the timer, in the font the column around them sets.
    private var lineFont:NSFont { DiscordFont.nsFont(phone ? 15 : 14) }
    @ViewBuilder private func lines(height:CGFloat,pinned:Bool)->some View {
        if let details {
            HStack(spacing:7) {
                part(.lineOne,text:true) { Text(verbatim:details).cssLines(lineFont,height).lineLimit(1) }
                if pinned,let count=pins?.lineOne,count > 1 { Pin(count:count) }
            }
            .modifier(TurnGlow(trigger:details,on:glows)).modifier(PartArrival(trigger:details,lineArrival(second:false)))
            .frame(height:height).transition(.identity)
        }
        if let state {
            HStack(spacing:7) {
                part(.lineTwo,text:true) { Text(verbatim:state).cssLines(lineFont,height).lineLimit(1) }
                if pinned,let count=pins?.lineTwo,count > 1 { Pin(count:count) }
                if pinned,let turn=lineTwoTurn { TurnRing(done:turn.done).accessibilityLabel(turn.label) }
            }
            .modifier(TurnGlow(trigger:state,on:glows)).modifier(PartArrival(trigger:state,lineArrival(second:true)))
            .frame(height:height).transition(.identity)
        }
        part(.timer,text:true) {
            HStack(spacing:5) { DesignIcon("mdi:controller",size:16);Text(verbatim:elapsed).cssLines(lineFont,height).monospacedDigit() }.foregroundStyle(DiscordColors.timer)
        }.frame(height:height)
    }
    private func pictures(size:CGFloat,radius:CGFloat,badge:CGFloat,inner:CGFloat,badgeBack:Color)->some View {
        let large=assets["large_image"].flatMap(URL.init(string:)),small=assets["small_image"].flatMap(URL.init(string:))
        return part(.picture,text:false) {
            LargePicture(url:large,size:size,radius:radius)
                .modifier(TurnGlow(trigger:large,on:glows,corner:radius))
                .designTip(phone ? nil : assets["large_text"],discord:true,below:true)
        }
        .overlay(alignment:.topLeading) { if let count=pins?.picture,count > 1 { Pin(count:count).offset(x:-7,y:-7) } }
        .overlay(alignment:.bottomTrailing) {
            if let small {
                part(.badge,text:false) {
                    BadgeLayers(url:small,size:inner,back:phone ? DiscordColors.stage : DiscordColors.tile)
                        .frame(width:badge,height:badge).background(badgeBack,in:Circle())
                        .modifier(TurnGlow(trigger:small,on:glows,corner:badge/2))
                        .designTip(phone ? nil : assets["small_text"],discord:true,below:true)
                }
                .modifier(PartArrival(trigger:level,badgeArrival,onAppear:false)).transition(.identity)
                .offset(x:6,y:6)
                .overlay(alignment:.topLeading) { if let count=pins?.badge,count > 1 { Pin(count:count).offset(x:-(size-24-badge+6),y:-(size-30-badge+6)) } }
            }
        }
    }
    /// A part of the card: its bounds for the outline, and a click picks it (Customize).
    private func part<Content:View>(_ slot:DiscordStudio.Slot,text:Bool=true,@ViewBuilder _ content:()->Content)->some View {
        content()
            .anchorPreference(key:CardPartBounds.self,value:.bounds) { [slot:$0] }
            .contentShape(Rectangle())
            .onTapGesture { pick?(slot) }
            .pointerStyle(pick == nil ? nil : .link)
    }
}

/// What the clock changed in Customize glows for 1.4 s: a line with a halo, a picture with a ring. A change of
/// `trigger` while `on` starts it.
private struct TurnGlow: ViewModifier {
    let trigger:AnyHashable?
    let on:Bool
    var corner:CGFloat?=nil
    func body(content:Content)->some View {
        content.keyframeAnimator(initialValue:0.0,trigger:trigger) { view,glow in
            Group {
                if glow <= 0 { view }
                else if let corner {
                    view.overlay { RoundedRectangle(cornerRadius:corner+2).strokeBorder(Color.rgb(255,160,110).opacity(0.85*glow),lineWidth:2).padding(-2) }
                        .shadow(color:Color.rgb(255,140,90).opacity(0.6*glow),radius:11)
                } else {
                    view.shadow(color:Color.rgb(255,170,110).opacity(0.95*glow),radius:6)
                        .shadow(color:Color.rgb(255,210,170).opacity(0.7*glow),radius:1)
                }
            }
        } keyframes:{ _ in
            MoveKeyframe(on ? 1.0 : 0)
            LinearKeyframe(0.0,duration:1.4,timingCurve:.bezier(startControlPoint:UnitPoint(x:0.22,y:1),endControlPoint:UnitPoint(x:0.36,y:1)))
        }
    }
}
/// The large picture: another fades in over 0.3 s over the one before (Overwatch's own when there's none).
private struct LargePicture: View {
    let url:URL?
    let size:CGFloat
    let radius:CGFloat
    @State private var before:URL??
    var body:some View {
        KeyframeAnimator(initialValue:0.0,trigger:url) { fading in
            ZStack {
                tile(url).opacity(1-fading)
                if fading > 0,let before { tile(before).opacity(fading) }
            }
        } keyframes:{ _ in
            MoveKeyframe(1.0)
            LinearKeyframe(0.0,duration:0.3,timingCurve:.bezier(startControlPoint:UnitPoint(x:0.25,y:0.1),endControlPoint:UnitPoint(x:0.25,y:1)))
        }
        .onChange(of:url) { old,_ in before=old }
    }
    private func tile(_ url:URL?)->some View {
        Group {
            if let url { RemoteImage(url:url) { DiscordColors.tile } } else { GameIcon() }
        }
        .frame(width:size,height:size).background(url == nil ? .clear : DiscordColors.tile)
        .clipShape(RoundedRectangle(cornerRadius:radius))
    }
}

/// The badge: another kind cross-fades over 0.3 s; another rank's emblem just takes its place.
private struct BadgeLayers: View {
    let url:URL
    let size:CGFloat
    let back:Color
    @State private var rank:URL?
    /// The Mac badge and Recall's icon, once shown (Recall's loads from the repository).
    @State private var icons:Set<URL>=[]
    private static func isRank(_ url:URL)->Bool { url != DiscordAssets.macBadge && url != DiscordAssets.badge }
    var body:some View {
        ZStack {
            if let rank=Self.isRank(url) ? url : rank { BadgeImage(url:rank,size:size,back:back).opacity(Self.isRank(url) ? 1 : 0) }
            ForEach([DiscordAssets.macBadge,DiscordAssets.badge],id:\.self) { icon in
                if icon == url || icons.contains(icon) { BadgeImage(url:icon,size:size,back:back).opacity(icon == url ? 1 : 0) }
            }
        }
        .animation(.curve(.css,0.3),value:Self.isRank(url) ? nil : url)
        .onChange(of:url,initial:true) { _,url in if Self.isRank(url) { rank=url } else { icons.insert(url) } }
    }
}
/// The badge: the rank's emblem whole (a little inside the circle, by `inset`), or Recall's icon filling the circle.
struct BadgeImage: View {
    let url:URL
    let size:CGFloat
    var back:Color=DiscordColors.tile
    var inset:CGFloat=1
    var body:some View {
        let icon=url == DiscordAssets.badge
        RemoteImage(url:url,fill:icon) { back }
            .scaleEffect(icon ? 1.25 : url == DiscordAssets.macBadge ? 1 : inset)
            .frame(width:size,height:size).background(back).clipShape(Circle())
    }
}
/// "⟳ 3": a list of this many takes turns here. It pops in a quarter second after it shows.
struct Pin: View {
    let count:Int
    var body:some View {
        HStack(spacing:2) { DesignIcon("lucide:repeat",size:9);Text("\(count)").designFont(10,.heavy).monospacedDigit() }
            .foregroundStyle(DiscordColors.onAccent)
            .padding(.leading,4).padding(.trailing,5).frame(height:16)
            .background(DiscordColors.accent,in:Capsule())
            .overlay { Capsule().strokeBorder(DiscordColors.card,lineWidth:2).padding(-2) }
            .allowsHitTesting(false)
            .popIn(0.35,delay:0.25).transition(.identity)
    }
}
/// A ring filled clockwise from the top, `done` of the way round, over its faint track: how far a turn has gone.
struct Ring: View {
    let done:Double
    var width:CGFloat=2
    var track:Color = .white.opacity(0.16)
    var fill=AnyShapeStyle(DiscordColors.accent)
    var round=true
    var body:some View {
        ZStack {
            Circle().stroke(track,lineWidth:width)
            Circle().trim(from:0,to:done).stroke(fill,style:StrokeStyle(lineWidth:width,lineCap:round ? .round : .butt)).rotationEffect(.degrees(-90))
        }
    }
}
/// How far Line 2 is through its turn.
struct TurnRing: View {
    let done:Double
    var body:some View {
        Ring(done:done,width:2.6,fill:AnyShapeStyle(DiscordColors.fill),round:false)
            .frame(width:9.4,height:9.4).frame(width:12,height:12).animation(.linear(duration:1),value:done)
    }
}

/// The parts' places on the card, for the outline.
struct CardPartBounds: PreferenceKey {
    static let defaultValue:[DiscordStudio.Slot:Anchor<CGRect>]=[:]
    static func reduce(value:inout [DiscordStudio.Slot:Anchor<CGRect>],nextValue:()->[DiscordStudio.Slot:Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}
/// The outline around the part being changed: it glides to another part, then quiets down after a moment.
private struct PartHighlight: View {
    let slot:DiscordStudio.Slot
    let anchor:Anchor<CGRect>
    @State private var quiet=false
    /// It glides only from one part to another: where it first shows, it just appears.
    @State private var placed=false
    var body:some View {
        GeometryReader { proxy in
            let bounds=proxy[anchor],text=[.lineOne,.lineTwo,.timer].contains(slot)
            let padX:CGFloat=text ? 6 : 4,padY:CGFloat=text ? 1 : 4,radius:CGFloat=slot == .badge ? (bounds.height+padY*2)/2 : text ? 5 : 10
            RoundedRectangle(cornerRadius:radius)
                .fill(DiscordColors.pick.opacity(quiet ? 0 : 0.13))
                .overlay { RoundedRectangle(cornerRadius:radius).strokeBorder(DiscordColors.pick.opacity(quiet ? 0.32 : 0.8),lineWidth:1.5) }
                .frame(width:bounds.width+padX*2,height:bounds.height+padY*2)
                .offset(x:bounds.minX-padX,y:bounds.minY-padY)
                .transaction { if !placed { $0.animation=nil } }
                .animation(placed ? .timingCurve(0.33,1,0.68,1,duration:0.3) : nil,value:bounds)
        }
        .allowsHitTesting(false)
        .onAppear { DispatchQueue.main.async { placed=true } }
        .task(id:slot) {
            withAnimation(.easeOut(duration:0.2)) { quiet=false }
            try? await Task.sleep(for:.milliseconds(1300))
            guard !Task.isCancelled else { return }
            withAnimation(.curve(.css,0.9)) { quiet=true }
        }
    }
}

/// The card on Discord's pop-out: on Discord's page with its banner and Juno; in Customize just the card.
struct DiscordShell<Card:View>: View {
    var profile=true
    /// The easter eggs (DiscordProfile.swift), kept here so they outlast the card's redrawing.
    var fun=ProfileFun()
    /// Told where the pop-out is in the sheet (LauncherStyle.sheetSpace), as it changes.
    var place:((CGRect)->Void)?=nil
    @ViewBuilder var card:Card
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            // The design's banner: a 115° sweep from indigo through violet to pink, lit cyan near the top right.
            ZStack {
                LinearGradient(stops:DiscordColors.banner,startPoint:UnitPoint(x:0.06,y:-0.81),endPoint:UnitPoint(x:0.94,y:1.81))
                GeometryReader { box in
                    let cyan=Color.rgb(38,183,211)
                    EllipticalGradient(colors:[cyan.opacity(0.55),cyan.opacity(0)],center:.center,startRadiusFraction:0,endRadiusFraction:0.275)
                        .frame(width:2.4*box.size.width,height:2.8*box.size.height).position(x:0.85*box.size.width,y:0)
                }
            }
            .frame(height:profile ? 58 : 0).clipShape(UnevenRoundedRectangle(topLeadingRadius:10,topTrailingRadius:10))
            DiscordProfileTop(fun:fun)
                .frame(height:profile ? 52 : 10,alignment:.top).opacity(profile ? 1 : 0).allowsHitTesting(profile)
            card.padding([.horizontal,.bottom],10)
        }
        .frame(width:372)
        // The pop-out's own shadow, not one under each line inside it.
        .background { RoundedRectangle(cornerRadius:10).fill(DiscordColors.popout).shadow(color:.black.opacity(0.45),radius:16,y:12) }
        .overlay(alignment:.topLeading) { ProfileFunLayer(fun:fun) }
        .onGeometryChange(for:CGSize.self) { $0.size } action:{ fun.shell=$0 }
        .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(LauncherStyle.sheetSpace)) } action:{ place?($0) }
        .modifier(FunJolt(fun:fun))
        .onChange(of:profile) { _,shown in if !shown { fun.kill() } }
        .environment(\.colorScheme,.dark)
    }
}
