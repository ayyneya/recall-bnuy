import SwiftUI
import AppKit

// The ways into Settings › Discord from Recall's own screens (one line each in SetupView and SettingsSheet): the home
// panel and General's card, both showing six example cards in turn.

/// One of the example cards. Each shows for `seconds`, on the clock, so every screen shows the same one.
struct ShowcaseCard {
    enum Picture { case web(URL),art(CardArt),game }
    enum Badge { case mac,recall,rank(URL) }
    let lineOne:String
    let lineTwo:String
    let picture:Picture
    var fit=false
    let badge:Badge
    var inMatch=false
    static let seconds=4.0
    static let player="bunni"
    /// Rank emblems and a hero as OverFast gives them; the card loads them the same way.
    private static let emblems="https://static.playoverwatch.com/images/pages/career/icons/rank/"
    private static let emerald=URL(string:emblems+"Rank_EmeraldTier.d82e76cb2deeac6d1f4d4cf4d8914517d903eeeb.png")!
    private static let champion=URL(string:emblems+"Rank_UltimateTier.bc416c2102ab21d39b2398fdf7571cc56503ea2c.png")!
    private static let tracer=URL(string:"https://d15f34w2p8l1cc.cloudfront.net/overwatch/4504f6f15cb3feaa92ecd38e01dcf751cb5abdac2e0bb52d0555727e53277502.png")!
    /// A rank, a one-trick, an Extra picture, a best, the week in the group's voice, a match.
    static let all:[ShowcaseCard]={
        let menus=L("In Menus"),juno=DiscordStudio.heroName("juno"),rank=CareerRank(role:.tank,division:"emerald",tier:1,icon:emerald)
        return [ShowcaseCard(lineOne:L("{0} · {1}",player,menus),lineTwo:L("Tank {0} {1}","↑",rank.name),picture:.web(emerald),fit:true,badge:.mac),
                ShowcaseCard(lineOne:L("{0} · {1}",L("{0} main",juno),menus),lineTwo:L("{0} one-trick",juno),picture:.art(.juno),badge:.rank(champion)),
                ShowcaseCard(lineOne:L("{0} · {1}",player+" :3",menus),lineTwo:L("Cardboard Support"),picture:.art(.jetpackCat),badge:.recall),
                ShowcaseCard(lineOne:L("{0} · {1}",player,menus),lineTwo:L("★ New best: {0}",L("{0} elims","53")),picture:.web(tracer),badge:.rank(emerald)),
                ShowcaseCard(lineOne:L("{0} · {1}",player,menus),lineTwo:"\(L("Week · {0}",L("Comp {0}–{1}","12","9"))) (\(L("{0} of {1}","3","6")))",
                             picture:.art(.winston),badge:.mac),
                ShowcaseCard(lineOne:L("{0} · {1}",player,L("In Match")),lineTwo:L("Match {0} tonight","4"),picture:.game,fit:true,badge:.mac,inMatch:true)]
    }()
    /// The card showing at `date`, and when its turn started.
    static func turn(at date:Date)->(index:Int,start:Date) {
        let k=((date.timeIntervalSinceReferenceDate+0.001)/seconds).rounded(.down)
        return (Int(k.truncatingRemainder(dividingBy:Double(all.count))),Date(timeIntervalSinceReferenceDate:k*seconds))
    }
}
/// The example's turns: its content for the card showing, again as each turn starts.
private struct ShowcaseClock<Content:View>: View {
    @ViewBuilder let content:(_ index:Int,_ start:Date)->Content
    var body:some View {
        // Held on the first card while Recall is hidden or Reduce Motion is on.
        if Moving.shared.now {
            TimelineView(.periodic(from:Date(timeIntervalSinceReferenceDate:0),by:ShowcaseCard.seconds)) { context in
                let turn=ShowcaseCard.turn(at:context.date)
                content(turn.index,turn.start)
            }
        } else { content(0,Date(timeIntervalSinceReferenceDate:0)) }
    }
}

/// Discord's own colours, light or dark with the window, as the design gives them.
private struct Palette {
    let dark:Bool
    init(_ scheme:ColorScheme) { dark=scheme == .dark }
    private func pick(_ d:Color,_ l:Color)->Color { dark ? d : l }
    /// The panel round both: a blurple tint in light, a blurple edge in dark.
    var frame:Color { pick(Color.rgb(88,101,242).opacity(0.05),Color.rgb(88,101,242).opacity(0.09)) }
    var frameEdge:Color { pick(Color.rgb(120,132,255).opacity(0.5),Color.rgb(88,101,242).opacity(0.22)) }
    /// The invite and the row, as Discord's embeds.
    var embed:Color { pick(.rgb(43,45,49),.rgb(242,243,245)) }
    var embedHover:Color { pick(.rgb(53,55,61),.rgb(232,233,237)) }
    var header:Color { pick(.rgb(181,186,193),.rgb(78,80,88)) }
    var strong:Color { pick(.rgb(242,243,245),.rgb(6,6,7)) }
    var text:Color { pick(.rgb(219,222,225),.rgb(49,51,56)) }
    var muted:Color { pick(.rgb(181,186,193),.rgb(92,94,102)) }
    var timer:Color { pick(.rgb(134,197,153),.rgb(36,128,70)) }
    var button:Color { pick(.rgb(78,80,88),.rgb(109,111,120)) }
    var chip:Color { pick(Color.rgb(255,190,92).opacity(0.16),Color.rgb(255,158,26).opacity(0.18)) }
    var chipText:Color { pick(.rgb(255,200,130),.rgb(158,86,0)) }
    var memberDot:Color { pick(.rgb(128,132,142),.rgb(148,155,164)) }
    var pop:Color { pick(.rgb(35,36,40),.white) }
    var popEdge:Color { pick(Color.white.opacity(0.08),Color.black.opacity(0.08)) }
    var popShadow:Color { Color.black.opacity(dark ? 0.45 : 0.16) }
    var block:Color { pick(Color.white.opacity(0.05),.rgb(242,243,245)) }
    var blockSolid:Color { pick(.rgb(43,44,48),.rgb(242,243,245)) }
    /// The turn dots: the others, and the pill's track.
    var dot:Color { pick(Color.white.opacity(0.3),Color.black.opacity(0.2)) }
    var track:Color { pick(Color.white.opacity(0.14),Color.black.opacity(0.1)) }
}

// MARK: the home screen

/// The home screen's Discord panel: the server's invite and the activity example, which opens Settings › Discord.
struct DiscordHomePanel: View {
    @Bindable var studio:DiscordStudio
    /// Opens Settings, on General; nil while Settings can't open (the Move screen), when only Join works.
    let openSettings:(()->Void)?
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        let colors=Palette(scheme)
        VStack(spacing:6) {
            InviteEmbed(colors:colors)
            ActivityRow(studio:studio,colors:colors) { studio.enter(folding:false);openSettings?() }.disabled(openSettings == nil)
        }
        .padding(6)
        .background(colors.frame,in:RoundedRectangle(cornerRadius:16))
        .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(colors.frameEdge,lineWidth:1) }
        // Off, Recall asks Discord nothing: the counts kept show.
        .task(id:studio.power) { if studio.power { InviteCounts.shared.refresh() } }
    }
}
/// "You've been invited to join a server": what the server is for, how many are on it, and Join.
private struct InviteEmbed: View {
    let colors:Palette
    @Environment(\.openURL) private var openURL
    @State private var inside=false
    var body:some View {
        let counts=InviteCounts.shared
        Button { openURL(Brand.discord) } label: {
            VStack(alignment:.leading,spacing:10) {
                Text(L("You’ve been invited to join a server")).discordFont(11,700).tracking(0.22).textCase(.uppercase).foregroundStyle(colors.header)
                HStack(spacing:12) {
                    Image(nsImage:AppIcon.image).resizable().interpolation(.high).scaleEffect(1.25).frame(width:48,height:48)
                        .clipShape(RoundedRectangle(cornerRadius:16))
                    VStack(alignment:.leading,spacing:2) {
                        Text(verbatim:Brand.name).discordFont(16,600,line:20).foregroundStyle(colors.strong)
                        Text(L("Get help, compare setups, and find other Mac Overwatch players.")).discordFont(11.5,line:11.5*1.35,wraps:true)
                            .foregroundStyle(colors.muted).fixedSize(horizontal:false,vertical:true)
                        if let online=counts.online,let members=counts.members {
                            HStack(spacing:5) {
                                Circle().fill(DiscordColors.online).frame(width:8,height:8)
                                Text(L("{0} Online",online.formatted()))
                                Circle().fill(colors.memberDot).frame(width:8,height:8).padding(.leading,9)
                                Text(L("{0} Members",members.formatted()))
                            }
                            .discordFont(12).monospacedDigit().foregroundStyle(colors.muted).lineLimit(1).padding(.top,3)
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    HStack(spacing:7) {
                        DesignIcon("ic:baseline-discord",size:18)
                        Text(L("Join")).discordFont(14,600)
                        DesignIcon("lucide:arrow-up-right",size:11)
                    }
                    .foregroundStyle(.white).padding(.horizontal,11).frame(height:36).background(DiscordLink.blurple,in:RoundedRectangle(cornerRadius:8))
                }
            }
            .padding(.leading,14).padding(.trailing,12).padding(.top,12).padding(.bottom,13)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(inside ? colors.embedHover : colors.embed,in:RoundedRectangle(cornerRadius:11))
            .contentShape(RoundedRectangle(cornerRadius:11))
        }
        .buttonStyle(.plain).onHover { inside=$0 }
        .accessibilityLabel(L("Join the {0} Discord",Brand.name)).accessibilityHint(L("Opens the invite in your browser"))
        .help(L("Open the {0} Discord invite in your browser",Brand.name))
    }
}
/// The activity example: picture and badge, name, Line 2, and Customize (Set up while off). Pointing a moment pops the
/// whole card out above it.
private struct ActivityRow: View {
    @Bindable var studio:DiscordStudio
    let colors:Palette
    let open:()->Void
    @State private var inside=false
    /// Over the example, and over the card popped out from it.
    @State private var pointing=(example:false,card:false)
    /// The example's width, left of Customize: the card popped out is as wide.
    @State private var width:CGFloat=280
    @State private var popped=false
    @State private var waiting:Task<Void,Never>?
    @Environment(\.isEnabled) private var isEnabled
    var body:some View {
        ShowcaseClock { index,start in
            let turn=studio.power ? index : 0,card=ShowcaseCard.all[turn]
            Button { open() } label: {
                VStack(alignment:.leading,spacing:10) {
                    HStack(spacing:7) {
                        NewChip()
                        Text(L("Your Discord activity")).discordFont(11,700).tracking(0.22).textCase(.uppercase).foregroundStyle(colors.header)
                        Spacer(minLength:0)
                        if studio.power {
                            ShowcaseDots(count:ShowcaseCard.all.count,current:index,start:start,dot:colors.dot,track:colors.track).padding(.trailing,2)
                        }
                        ExampleChip(fill:colors.chip,text:colors.chipText)
                    }
                    HStack(spacing:12) {
                        HStack(spacing:12) {
                            ShowcasePicture(card:card,size:44,badge:20,ring:colors.embed).id(turn).transition(.showcasePicture)
                            VStack(alignment:.leading,spacing:3) {
                                HStack(spacing:6) {
                                    ShowcaseAvatar(size:18,dot:4,ring:2,ringColor:colors.embed,on:studio.power)
                                    Text(verbatim:ShowcaseCard.player).discordFont(14,600).foregroundStyle(colors.strong)
                                }
                                Text(studio.power ? card.lineTwo : L("Not shown on Discord")).discordFont(12.5).foregroundStyle(colors.muted).lineLimit(1)
                                    .id(turn).transition(.showcaseLine)
                            }
                        }
                        .frame(maxWidth:.infinity,alignment:.leading).offState(studio.power)
                        .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ width=$0 }
                        .onHover { point(example:$0) }
                        HStack(spacing:2) {
                            Text(studio.power ? L("Customize") : L("Set up")).designFont(13,.semibold)
                            DesignIcon("lucide:chevron-right",size:14)
                        }
                        .foregroundStyle(.white).padding(.leading,12).padding(.trailing,9).frame(height:30).background(colors.button,in:RoundedRectangle(cornerRadius:8))
                    }
                    .animation(.curve(.outCubic,0.36),value:turn)
                }
                .padding(.leading,14).padding(.trailing,12).padding(.top,12).padding(.bottom,14)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(inside ? colors.embedHover : colors.embed,in:RoundedRectangle(cornerRadius:11))
                .contentShape(RoundedRectangle(cornerRadius:11))
            }
            .buttonStyle(.plain)
            .onHover { inside=$0 }
            // Above the row, 8 points over its top, from where the example starts.
            .overlay(alignment:.top) {
                Color.clear.frame(height:0).overlay(alignment:.bottomLeading) {
                    if popped {
                        ShowcasePopout(card:card,on:studio.power,colors:colors,width:width,open:open)
                            .onHover { point(card:$0) }
                            .padding(.leading,14).padding(.bottom,8)
                            .transition(.asymmetric(insertion:.opacity.combined(with:.offset(y:8)).animation(.curve(.out,0.26)),removal:.atOnce))
                    }
                }
            }
            .zIndex(1)
        }
        .accessibilityLabel(L("Your Discord activity. Opens Settings › Discord."))
        .help(L("Customize what friends see on Discord"))
    }
    /// The card pops out 180 ms after the pointer comes, and goes 160 ms after it leaves both.
    private func point(example:Bool?=nil,card:Bool?=nil) {
        if let example { pointing.example=example }
        if let card { pointing.card=card }
        let wanted=(pointing.example || pointing.card) && isEnabled
        waiting?.cancel()
        guard wanted != popped else { return }
        waiting=Task {
            try? await Task.sleep(for:.milliseconds(wanted ? 180 : 160))
            if !Task.isCancelled { popped=wanted }
        }
    }
}
/// The whole card over the row, as Discord's member list pops one out.
private struct ShowcasePopout: View {
    let card:ShowcaseCard
    let on:Bool
    let colors:Palette
    let width:CGFloat
    let open:()->Void
    var body:some View {
        Button { open() } label: {
            VStack(alignment:.leading,spacing:0) {
                LinearGradient(stops:[.init(color:.rgb(126,87,194),location:0),.init(color:.rgb(214,98,230),location:0.55),.init(color:.rgb(255,128,64),location:1)],
                               startPoint:UnitPoint(x:0.1,y:0),endPoint:UnitPoint(x:0.9,y:1))
                    .frame(height:46).offState(on)
                VStack(alignment:.leading,spacing:10) {
                    HStack(alignment:.bottom,spacing:10) {
                        ShowcaseAvatar(size:52,dot:12,ring:3,ringColor:colors.pop,on:on).padding(4).background(colors.pop,in:Circle()).padding(-4)
                        HStack(spacing:8) {
                            Text(verbatim:ShowcaseCard.player).discordFont(16,700).foregroundStyle(colors.strong)
                            Spacer(minLength:0)
                            ExampleChip(fill:colors.chip,text:colors.chipText)
                        }.padding(.bottom,2)
                    }
                    .padding(.top,-24)
                    activity.padding(10).background(colors.block,in:RoundedRectangle(cornerRadius:8)).offState(on)
                    HStack(spacing:5) {
                        DesignIcon("lucide:mouse-pointer-click",size:12)
                        Text(L("Click to customize what friends see")).designFont(11.5)
                    }.foregroundStyle(colors.muted)
                }
                .padding(.horizontal,12).padding(.bottom,12)
            }
            .frame(width:width,alignment:.leading).clipShape(RoundedRectangle(cornerRadius:12))
            .background(colors.pop,in:RoundedRectangle(cornerRadius:12))
            .overlay { RoundedRectangle(cornerRadius:12).strokeBorder(colors.popEdge,lineWidth:1) }
            .shadow(color:colors.popShadow,radius:22,y:18)
            .overlay(alignment:.bottomLeading) {
                Rectangle().fill(colors.pop).frame(width:12,height:12)
                    .overlay(alignment:.bottomTrailing) { Rectangle().fill(colors.popEdge).frame(width:12,height:1) }
                    .overlay(alignment:.trailing) { Rectangle().fill(colors.popEdge).frame(width:1,height:12) }
                    .rotationEffect(.degrees(45)).offset(x:24,y:6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private var activity:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(on ? L("Playing") : L("Off")).discordFont(12,700).foregroundStyle(colors.strong)
            HStack(spacing:10) {
                ShowcasePicture(card:card,size:54,badge:24,ring:colors.blockSolid)
                VStack(alignment:.leading,spacing:0) {
                    Text(verbatim:"Overwatch").discordFont(13.5,600,line:17).foregroundStyle(colors.strong)
                    Text(card.lineOne).discordFont(12.5,line:16).lineLimit(1)
                    Text(card.lineTwo).discordFont(12.5,line:16).lineLimit(1)
                    TimelineView(.periodic(from:.now,by:1)) { context in
                        let seconds=(card.inMatch ? 192 : 2538)+Int(context.date.timeIntervalSinceReferenceDate)%600
                        HStack(spacing:4) { DesignIcon("mdi:controller",size:14);Text(verbatim:DiscordCardView.clock(seconds)).discordFont(12.5,line:16).monospacedDigit() }
                            .foregroundStyle(colors.timer)
                    }
                }
                .foregroundStyle(colors.text).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
    }
}

// MARK: Settings › General

/// General's Discord card in General's style: what it is, the power button, and the example row with Customize.
struct DiscordSettingsCard: View {
    @Bindable var studio:DiscordStudio
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        let colors=Palette(scheme)
        LauncherPanel(inset:16) {
            VStack(alignment:.leading,spacing:6) {
                HStack(alignment:.center,spacing:12) {
                    VStack(alignment:.leading,spacing:2) {
                        HStack(spacing:8) { Text(L("Discord activity")).font(LauncherStyle.font(14,.semibold));NewChip() }
                        Text(studio.power ? L("What friends and your servers see on Discord while you play.") : L("Off. Discord can’t see that you’re playing."))
                            .font(LauncherStyle.font(12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:12)
                    GeneralPowerButton(studio:studio)
                }
                Divider().padding(.vertical,6)
                ShowcaseClock { index,start in
                    let turn=studio.power ? index : 0
                    HStack(spacing:12) {
                        Button { studio.enter() } label: {
                            HStack(spacing:12) {
                                ShowcaseAvatar(size:36,dot:7,ring:3,ringColor:LauncherStyle.surface(scheme),on:studio.power)
                                VStack(alignment:.leading,spacing:1) {
                                    HStack(spacing:7) {
                                        Text(verbatim:ShowcaseCard.player).discordFont(14.5,600)
                                        ExampleChip(fill:colors.chip,text:colors.chipText)
                                        if studio.power { ShowcaseDots(count:ShowcaseCard.all.count,current:index,start:start,dot:colors.dot,track:colors.track) }
                                    }
                                    Text(studio.power ? ShowcaseCard.all[index].lineTwo : L("Not shown on Discord")).discordFont(12.5).foregroundStyle(.secondary).lineLimit(1)
                                        .id(turn).transition(.showcaseLine)
                                }
                            }
                            .offState(studio.power).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(L("Your Discord activity. Opens Settings › Discord."))
                        Button { studio.enter() } label: {
                            HStack(spacing:2) { Text(studio.power ? L("Customize") : L("Set up"));Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)) }
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    .animation(.curve(.outCubic,0.3),value:turn)
                }
            }
        }
    }
}

/// The stage's power button (PowerButton) as General shows it: following light and dark, on green while on.
private struct GeneralPowerButton: View {
    @Bindable var studio:DiscordStudio
    @Environment(\.colorScheme) private var scheme
    @State private var inside=false
    var body:some View {
        let on=studio.power,dark=scheme == .dark
        let green=dark ? Color.rgb(90,220,140) : Color.rgb(40,165,80),veil=dark ? Color.white : Color.black
        Button { studio.setPower(!on) } label: {
            DesignIcon("lucide:power",size:15).foregroundStyle(on ? green : Color.secondary).frame(width:28,height:28)
                .background(inside ? veil.opacity(dark ? 0.16 : 0.1) : on ? green.opacity(0.12) : veil.opacity(dark ? 0.1 : 0.06),in:RoundedRectangle(cornerRadius:8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { inside=$0 }
        .animation(.easeOut(duration:0.3),value:on)
        .accessibilityLabel(L("Discord activity on or off"))
        .help(on ? L("Discord activity is on. Turn it off to unload it entirely: while on, it uses well under 0.1% of your CPU.") : L("Turn Discord activity back on."))
    }
}

// MARK: the parts

/// A card's picture with its badge on its corner, in a ring of what's behind it, as Discord shows them.
private struct ShowcasePicture: View {
    let card:ShowcaseCard
    let size:CGFloat
    /// The badge's ring; the badge is four or five points smaller.
    let badge:CGFloat
    let ring:Color
    var body:some View {
        picture.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:8))
            .overlay(alignment:.bottomTrailing) {
                let inner=(badge*0.8).rounded()
                badgeImage.frame(width:inner,height:inner).clipShape(Circle())
                    .frame(width:badge,height:badge).background(ring,in:Circle()).offset(x:5,y:5)
            }
    }
    @ViewBuilder private var picture:some View {
        switch card.picture {
        case .web(let url): RemoteImage(url:url,fill:!card.fit) { Color.clear }
        case .art(let art): RemoteImage(url:DiscordAssets.art(art.file)) { Color.clear }
        case .game: GameIcon()
        }
    }
    @ViewBuilder private var badgeImage:some View {
        switch card.badge {
        case .mac: RemoteImage(url:DiscordAssets.macBadge) { Color.clear }
        case .recall: Image(nsImage:AppIcon.image).resizable().interpolation(.high).scaleEffect(1.25)
        case .rank(let url): RemoteImage(url:url,fill:false) { Color.clear }.background(DiscordColors.tile)
        }
    }
}
/// The example player's picture (Juno, as on Discord's page) with the online dot, grey while the card is off.
private struct ShowcaseAvatar: View {
    let size:CGFloat
    let dot:CGFloat
    let ring:CGFloat
    let ringColor:Color
    let on:Bool
    var body:some View {
        RemoteImage(url:DiscordAssets.art(CardArt.juno.file)) { Color.clear }.frame(width:size,height:size).clipShape(Circle())
            .overlay(alignment:.bottomTrailing) {
                Circle().fill(on ? DiscordColors.online : Color.rgb(128,132,142)).frame(width:dot,height:dot)
                    .padding(ring).background(ringColor,in:Circle()).offset(x:2,y:2)
            }
    }
}
/// Recall's turn dots, one per card: the current one a filling pill, ones shown already orange.
private struct ShowcaseDots: View {
    let count:Int
    let current:Int
    let start:Date
    let dot:Color
    let track:Color
    var body:some View {
        HStack(spacing:3) {
            ForEach(0..<count,id:\.self) { place in
                let now=place == current
                Capsule().fill(now ? track : place < current ? Self.orange.opacity(0.55) : dot).frame(width:now ? 16 : 5,height:5)
                    .overlay(alignment:.leading) { if now { Fill(start:start).id(start) } }
                    .clipShape(Capsule())
            }
        }
        .animation(.curve(.out,0.3),value:current)
        .accessibilityHidden(true)
    }
    static let orange=Color.rgb(255,140,64)
    /// The pill's fill, run by Core Animation so the window isn't redrawn each frame.
    private struct Fill: NSViewRepresentable {
        let start:Date
        func makeNSView(context:Context)->FillView { FillView(start:start) }
        func updateNSView(_ view:FillView,context:Context) {}
    }
    private final class FillView: NSView {
        private let fill=CALayer()
        init(start:Date) {
            super.init(frame:.zero)
            wantsLayer=true;layer?.masksToBounds=true
            fill.backgroundColor=NSColor(ShowcaseDots.orange).cgColor;fill.anchorPoint=CGPoint(x:0,y:0.5)
            layer?.addSublayer(fill)
            // On the turn's own clock, however late the layer is first drawn.
            let grow=CABasicAnimation(keyPath:"transform.scale.x")
            grow.fromValue=0;grow.toValue=1;grow.duration=ShowcaseCard.seconds
            grow.beginTime=CACurrentMediaTime()-Date().timeIntervalSince(start)
            fill.add(grow,forKey:"grow")
        }
        required init?(coder:NSCoder) { nil }
        /// The pill's capsule, and the fill's, scaled from its left edge.
        override func layout() {
            super.layout()
            CATransaction.begin();CATransaction.setDisableActions(true)
            layer?.cornerRadius=bounds.height/2;fill.cornerRadius=bounds.height/2
            fill.bounds=bounds;fill.position=CGPoint(x:0,y:bounds.midY)
            CATransaction.commit()
        }
        override func hitTest(_ point:NSPoint)->NSView? { nil }
    }
}
/// "NEW", on the ribbon's first two colours.
private struct NewChip: View {
    var body:some View {
        Text(L("NEW")).designFont(10,800).tracking(0.5).foregroundStyle(.white).padding(.horizontal,6).frame(height:16)
            .background(LinearGradient(colors:[.rgb(255,152,104),.rgb(214,98,230)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:5))
    }
}
/// "Example", amber: the card shown isn't the player's.
private struct ExampleChip: View {
    let fill:Color
    let text:Color
    var body:some View {
        Text(L("Example")).designFont(10.5,.bold).foregroundStyle(text).padding(.horizontal,6).frame(height:16).background(fill,in:RoundedRectangle(cornerRadius:5))
    }
}
private enum AppIcon {
    static let image=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap(NSImage.init(contentsOf:)) ?? NSImage(named:NSImage.applicationIconName) ?? NSImage()
}
private extension View {
    /// Half seen and grey while the card is off.
    func offState(_ on:Bool)->some View { opacity(on ? 1 : 0.5).grayscale(on ? 0 : 1).animation(.easeOut(duration:0.3),value:on) }
}
private extension AnyTransition {
    /// A new line rises in; the last one goes at once.
    static var showcaseLine:AnyTransition { .asymmetric(insertion:.opacity.combined(with:.offset(y:4)),removal:.atOnce) }
    /// A new picture settles in.
    static var showcasePicture:AnyTransition { .asymmetric(insertion:.opacity.combined(with:.scale(scale:0.94)),removal:.atOnce) }
}

// MARK: the invite's counts

/// The server's member and online counts, from Discord's public invite record at most once a day (nothing about the
/// player is sent).
@MainActor @Observable final class InviteCounts {
    static let shared=InviteCounts()
    private(set) var online:Int?
    private(set) var members:Int?
    @ObservationIgnored private var answered:Date?
    @ObservationIgnored private var asked=false
    private static let key="discordInviteCounts"
    init() {
        let kept=UserDefaults.standard.dictionary(forKey:Self.key)
        online=kept?["online"] as? Int;members=kept?["members"] as? Int;answered=kept?["at"] as? Date
    }
    /// Asks once a launch, when the last answer is a day old.
    func refresh() {
        guard !asked,answered.map({ Date().timeIntervalSince($0) > 24*3600 }) ?? true,
              let url=URL(string:"https://discord.com/api/v10/invites/\(Brand.discord.lastPathComponent)?with_counts=true") else { return }
        asked=true
        URLSession.cookieless.dataTask(with:URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)) { data,_,_ in
            let record=data.flatMap { try? JSONSerialization.jsonObject(with:$0) } as? [String:Any]
            let online=record?["approximate_presence_count"] as? Int,members=record?["approximate_member_count"] as? Int
            Task { @MainActor in
                guard let online,let members else { return }
                self.online=online;self.members=members;self.answered=Date()
                UserDefaults.standard.set(["online":online,"members":members,"at":Date()],forKey:Self.key)
            }
        }.resume()
    }
}

/// The home screen's content, as it first fills in, grows Recall's window to fit it (the Discord panel is taller
/// than the link it replaced), never past the screen and never shrinking it. Only in the first seconds after launch,
/// so a notice later doesn't move the window under the pointer.
struct DiscordWindowFit: ViewModifier {
    private static let launched=Date()
    func body(content:Content)->some View {
        content.onGeometryChange(for:CGFloat.self,of:{ $0.size.height }) { height in
            guard Date().timeIntervalSince(Self.launched) < 5,let window=NSApp.windows.first(where:{ $0.title == Brand.name && $0.isVisible }),
                  let screen=window.screen ?? NSScreen.main,let shown=window.contentView?.bounds.height,height > shown+1 else { return }
            let frame=window.frame,grown=min(frame.height+height-shown,screen.visibleFrame.height)
            guard grown > frame.height+1 else { return }
            // Grown from its top, then moved up only as far as the screen needs.
            var next=NSRect(x:frame.minX,y:frame.maxY-grown,width:frame.width,height:grown)
            if next.minY < screen.visibleFrame.minY { next.origin.y=screen.visibleFrame.minY }
            window.setFrame(next,display:true,animate:false)
        }
    }
}
