import SwiftUI

// Customize as the design lays it out: the card on its stage, its parts down the left, the part being changed on the
// right. A click on the card picks a part; the card's name opens My cards.

struct DiscordEditor: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            if !studio.gallery {
                HStack(alignment:.top,spacing:10) {
                    EditorRail(studio:studio).frame(width:158)
                    PanelScroller { EditorPanel(studio:studio).padding(.horizontal,2).padding(.bottom,12) }
                }
                .padding(.top,12).frame(maxHeight:.infinity,alignment:.top)
                // Back from My cards, under the shrinking stage; going to it, they go at once.
                .popIn(0.42).transition(.asymmetric(insertion:.ride(CardStage.height(.editor,gallery:true)-CardStage.height(.editor,gallery:false)),removal:.identity))
            }
        }
        // Its room and no more while the stage shrinks over it: the rail runs on past its foot, cut off as in the
        // design.
        .frame(minHeight:0,maxHeight:.infinity,alignment:.top)
        .clipShape(Band())
        .animation(.curve(.out,0.52),value:studio.gallery)
    }
    /// The editor's height and well past its sides.
    private struct Band: Shape { func path(in rect:CGRect)->Path { Path(rect.insetBy(dx:-40,dy:0)) } }
}

/// The breadcrumb: "Settings" on Discord's page; "Settings › Discord" past it. In Customize the title is the card's
/// name, which opens My cards.
struct DiscordPageHeader: View {
    @Bindable var studio:DiscordStudio
    /// The design's 46, with seven points (not two) between the breadcrumb and the title, which sat too close.
    static let height:CGFloat=52
    var body:some View {
        FoldTime { t in
            let fold=studio.fold,home=studio.screen == .home
            let title=fold.flatMap { $0.header ? HeaderFold.title($0,at:t) : nil } ?? (opacity:1,rise:0)
            // Customize's morph carries the card's title here: unseen till it lands.
            let carried=fold.map { $0.studio && $0.opening && t < StudioMorph.length } ?? false
            let named=fold.map { $0.studio && !$0.opening ? Ease.linear(t,from:0.16,over:0.24) : 1 } ?? 1
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:5) {
                    settings
                    if !home {
                        DesignIcon("lucide:chevron-right",size:11).foregroundStyle(DiscordColors.ink(0.55))
                        LinkButton(title:L("Discord")) { studio.closePage() }
                    }
                }
                titleRow(carried:carried,named:named).opacity(title.opacity).offset(y:title.rise).animation(nil,value:fold)
            }
            .frame(height:Self.height,alignment:.bottom)
        }
        .foldClock(studio.folds)
        .animation(.curve(.out,0.35),value:studio.gallery)
        // One piece moving with the header as it folds: what's in it doesn't animate as a fold starts (foldClock).
        .geometryGroup()
    }
    /// Back to Settings' tabs; hidden while its copy travels with the header (HeaderFold).
    private var settings:some View {
        LinkButton(title:L("Settings")) { studio.leave() }
            .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(LauncherStyle.sheetSpace)) } action:{ frame in
                if studio.fold == nil { studio.foldFrames[.settings]=frame.offsetBy(dx:0,dy:studio.open ? 0 : -HeaderFold.chrome) }
            }
            .opacity(studio.fold?.header == true ? 0 : 1).animation(nil,value:studio.fold)
    }
    /// "Discord" on Discord's page (over Customize's card menu, measured for the morph); in Customize the card menu; a
    /// page's title.
    private func titleRow(carried:Bool,named:Double)->some View {
        ZStack(alignment:.leading) {
            switch studio.screen {
            case .home,.editor:
                let home=studio.screen == .home
                Button { studio.openGallery(!studio.gallery) } label: {
                    // Fourteen points between icon and name, not the design's nine (too close, said the player).
                    HStack(spacing:14) {
                        DesignIcon("rc:cards",size:18).foregroundStyle(DiscordColors.link)
                            .frame(width:30,height:30).background(DiscordColors.accent.opacity(studio.gallery ? 0.24 : 0.12),in:RoundedRectangle(cornerRadius:9))
                        Text(studio.gallery ? L("My cards") : studio.design.shownName).designFont(24,.bold).tracking(-0.7).lineLimit(1)
                            // The name changes at once, as the design's does.
                            .foregroundStyle(DiscordColors.body).contentTransition(.identity)
                            .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(LauncherStyle.sheetSpace)) } action:{ frame in
                                if studio.open { studio.foldFrames[.cardTitle]=frame }
                            }
                            .opacity(carried ? 0 : 1)
                        DesignIcon("lucide:chevron-down",size:16).foregroundStyle(DiscordColors.ink(0.45)).rotationEffect(.degrees(studio.gallery ? 180 : 0))
                    }.frame(height:32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(L("My cards")).accessibilityValue(studio.gallery ? L("Open") : L("Closed"))
                .opacity(home ? 0 : 1).allowsHitTesting(!home).accessibilityHidden(home)
                if home { Text(L("Discord")).designFont(24,.bold).tracking(-0.7).foregroundStyle(DiscordColors.body).opacity(named).accessibilityAddTraits(.isHeader) }
            case .profile,.history:
                Text(studio.screen == .profile ? L("Your profile") : L("What Recall remembers")).designFont(24,.bold).tracking(-0.7).foregroundStyle(DiscordColors.body)
            }
        }.frame(minHeight:32)
    }
}

/// The card on its stage: Discord's pop-out on Discord's page, a computer or phone in Customize, the gallery in My
/// cards. One stage for all three, so moving between them only changes its height.
struct CardStage: View {
    @Bindable var studio:DiscordStudio
    /// The stage's height on Discord's page, in Customize, and in My cards.
    static func height(_ screen:DiscordStudio.Screen,gallery:Bool)->CGFloat { screen == .home ? 396 : gallery ? 548 : 252 }
    var body:some View {
        let home=studio.screen == .home
        DiscordStage(studio:studio,height:Self.height(studio.screen,gallery:studio.gallery),top:home ? 0 : 34,power:home) {
            // My cards gathers round the card as it shrinks into place: the same card, not a crossfade.
            ZStack(alignment:.top) {
                if studio.gallery { DiscordGallery(studio:studio).transition(.identity) }
                card(home:home)
            }
        } controls: {
            if !home && !studio.gallery { DeviceToggle(studio:studio).transition(.atOnce) }
            // On Discord's page too (the player asked for it): the pictures and badge say more when pointed at.
            if home && studio.power && !studio.hoverSeen {
                StageChip(icon:"lucide:mouse",text:L("Point at pictures"),nudge:true).allowsHitTesting(false).fadeIn(0.5,delay:0.8).transition(.identity)
            }
        }
        .overlay(alignment:.topLeading) {
            if !home && !studio.gallery {
                if studio.device == .phone {
                    StageChip(icon:"lucide:smartphone",text:L("No hover or buttons"))
                        .designTip(L("Discord on phones shows the lines and the pictures, but no hover text and no buttons."),discord:true)
                        .padding(.leading,153).padding(.top,10).fadeIn(0.3).transition(.identity)
                } else if !studio.hoverSeen {
                    StageChip(icon:"lucide:mouse",text:L("Point at pictures"),nudge:true).allowsHitTesting(false)
                        .padding(.leading,164).padding(.top,10).fadeIn(0.5,delay:0.8).transition(.identity)
                }
            }
        }
        .overlay(alignment:studio.device == .phone ? .bottom : .bottomLeading) {
            if !home && studio.usesExample && !studio.gallery {
                Text(L("Example data")).designFont(11,.bold).foregroundStyle(Color.rgb(255,200,130))
                    .padding(.horizontal,8).frame(height:18).background(Color.rgb(255,190,92).opacity(0.14),in:RoundedRectangle(cornerRadius:6))
                    .padding(.leading,studio.device == .phone ? 0 : 13).padding(.bottom,studio.device == .phone ? 5 : 6)
                    .transition(.atOnce)
            }
        }
        .animation(.curve(.out,0.52),value:studio.gallery)
        .animation(.easeOut(duration:0.3),value:studio.device)
    }
    /// The card: on Discord's page, in Customize (the part being changed marked), in the middle of My cards (smaller,
    /// sped up). Off, under the stage's cover.
    private func card(home:Bool)->some View {
        let gallery=studio.gallery
        return TimelineView(.seconds) { context in
            let now=home ? studio.homeTime(context.date) : context.date
            let activity=studio.activity(at:now)
            // From now, not the timeline's tick (up to a second before it).
            let outlineDelay:Double=studio.levelFlow.map { flow in max(0,0.88-Date().timeIntervalSince(flow.at)) } ?? 0
            if home || gallery || studio.device == .desktop {
                // Where the layout puts it, which it has from the moment a fold starts: what the morph needs.
                DiscordShell(profile:home,fun:studio.profileFun,place:{ studio.foldFrames[home ? .shellHome : .shellEditor]=$0 }) {
                    DiscordCardView(activity:activity,now:now,selected:home || gallery ? nil : studio.slot,outlineWait:studio.fold?.opening == true ? 0.1 : 0,
                                    pick:home ? (studio.power ? { studio.openEditor(at:$0) } : nil) : gallery ? nil : { studio.pick($0) },
                                    pins:gallery ? studio.galleryPins : nil,lineTwoTurn:home ? studio.homeLineTwoTurn(at:now) : nil,
                                    level:home ? studio.level : nil,turn:studio.turn(at:now))
                        .modifier(LevelReveal(level:studio.level,on:home))
                        // After Customize's light has traced the card, when it's running.
                        .overlay { MarchingOutline(on:home && studio.level == .custom && studio.power,delay:outlineDelay) }
                        .overlay(alignment:.top) {
                            if !home {
                                HStack(spacing:5) {
                                    TurnDots(studio:studio,now:context.date)
                                    if gallery && studio.loopLength(at:context.date) > 1 {
                                        HStack(spacing:3) { DesignIcon("rc:ff",size:9);Text(L("Sped up")).designFont(10,.bold) }
                                            .foregroundStyle(Color.rgb(255,190,140).opacity(0.9)).fixedSize().transition(.atOnce)
                                    }
                                }.offset(y:10).transition(.atOnce)
                            }
                        }
                        .onGeometryChange(for:CGRect.self) { $0.frame(in:.discordTab) } action:{ studio.cardFrame=$0 }
                }
                .scaleEffect(gallery ? 0.86 : 1)
                // A step in My cards: the next comes in from its neighbour's place. Put back, a card pops in the
                // middle.
                .modifier(PartArrival(trigger:nil,gallery ? DiscordGallery.cardArrival(studio.gallerySlide) : nil))
                .id(studio.galleryItem?.design.id)
                .transition(.identity)
                .padding(.bottom,gallery ? DiscordGallery.caption : 0)
                .frame(maxHeight:.infinity)
            } else {
                PhoneFrame {
                    DiscordCardView(activity:activity,now:context.date,phone:true,selected:studio.slot,pick:{ studio.pick($0) },turn:studio.turn(at:context.date))
                        .overlay(alignment:.top) { TurnDots(studio:studio,now:context.date).offset(y:10) }
                }
                .transition(.opacity)
            }
        }
    }
}
/// The card's box when a level changes its height: the parts move at once, the box follows over 0.32 s, clipping them.
private struct LevelReveal: ViewModifier {
    let level:DiscordPresenceLevel
    let on:Bool
    @State private var height:CGFloat?
    @State private var sized:DiscordPresenceLevel?
    func body(content:Content)->some View {
        // One shape on every screen, so the card stays the same card as Customize opens and closes.
        content
            .fixedSize(horizontal:false,vertical:true)
            .onGeometryChange(for:CGFloat.self) { $0.size.height } action:{ new in
                if on,let sized,sized != level { withAnimation(.timingCurve(0.3,0.75,0.35,1,duration:0.32)) { height=new } } else { height=new }
                sized=level
            }
            .frame(height:on ? height : nil,alignment:.top)
            .background(DiscordColors.card,in:RoundedRectangle(cornerRadius:8))
            .clipShape(RoundedRectangle(cornerRadius:8))
    }
}
/// A quiet chip on the stage ("Point at pictures"), its icon nudging every 2.6 seconds.
private struct StageChip: View {
    let icon:String
    let text:String
    var nudge=false
    var body:some View {
        HStack(spacing:6) {
            DesignIcon(icon,size:12).foregroundStyle(DiscordColors.glow)
                .keyframeAnimator(initialValue:CGSize.zero,repeating:nudge) { view,offset in view.offset(offset) } keyframes:{ _ in
                    KeyframeTrack(\.self) {
                        LinearKeyframe(CGSize.zero,duration:1.82)
                        LinearKeyframe(CGSize(width:1,height:-1),duration:0.26,timingCurve:.easeInOut)
                        LinearKeyframe(CGSize(width:-1,height:1),duration:0.26,timingCurve:.easeInOut)
                        LinearKeyframe(CGSize.zero,duration:0.26,timingCurve:.easeInOut)
                    }
                }
            Text(text).designFont(11,.semibold)
        }
        .foregroundStyle(DiscordColors.ink(0.62))
        .padding(.leading,7).padding(.trailing,9).frame(height:24)
        .background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:7))
        .environment(\.colorScheme,.dark)
    }
}
private struct DeviceToggle: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        HStack(spacing:2) {
            button(.desktop,icon:"lucide:monitor",name:L("Desktop"))
            button(.phone,icon:"lucide:smartphone",name:L("Phone"))
        }.padding(2).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:8))
    }
    private func button(_ device:DiscordStudio.Device,icon:String,name:String)->some View {
        let on=studio.device == device
        return Button { withAnimation(.curve(.out,0.4)) { studio.device=device } } label: {
            HStack(spacing:5) { DesignIcon(icon,size:13);if on { Text(name).designFont(11.5,.semibold).transition(.opacity) } }
                .foregroundStyle(on ? .white : DiscordColors.ink(0.45))
                .padding(.leading,on ? 7 : 6).padding(.trailing,on ? 9 : 6).frame(height:22)
                .background(on ? .white.opacity(0.16) : .clear,in:RoundedRectangle(cornerRadius:6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
    }
}
/// A phone's top edge and notch around the card, running past the stage's bottom.
struct PhoneFrame<Content:View>: View {
    @ViewBuilder var content:Content
    var body:some View {
        // The design's phone: 393 points wide, with its edge and notch, running out under the stage.
        VStack(spacing:0) { content }
            .padding(.top,36).padding(.horizontal,16)
            .frame(maxHeight:.infinity,alignment:.top)
            .overlay(alignment:.top) { Capsule().fill(.black).frame(width:120,height:26).padding(.top,9) }
            .padding([.top,.horizontal],5)
            .frame(width:393)
            .background(Color.rgb(26,27,30))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius:44,topTrailingRadius:44))
            .overlay { PhoneEdge().stroke(Color.rgb(58,60,66),lineWidth:5) }
            .offset(x:-0.5)
            .padding(.top,43-34).padding(.bottom,-30)
            .environment(\.colorScheme,.dark)
    }
}
/// The phone's edge: its sides and top, rounded, open at the bottom.
private struct PhoneEdge: Shape {
    func path(in rect:CGRect)->Path {
        let r=rect.insetBy(dx:2.5,dy:2.5),radius:CGFloat=44-2.5
        var path=Path()
        path.move(to:CGPoint(x:r.minX,y:rect.maxY))
        path.addLine(to:CGPoint(x:r.minX,y:r.minY+radius))
        path.addArc(center:CGPoint(x:r.minX+radius,y:r.minY+radius),radius:radius,startAngle:.degrees(180),endAngle:.degrees(270),clockwise:false)
        path.addLine(to:CGPoint(x:r.maxX-radius,y:r.minY))
        path.addArc(center:CGPoint(x:r.maxX-radius,y:r.minY+radius),radius:radius,startAngle:.degrees(270),endAngle:.degrees(0),clockwise:false)
        path.addLine(to:CGPoint(x:r.maxX,y:rect.maxY))
        return path
    }
}
/// The card's turns, as dots at its top: the one showing fills as its time passes; a click shows another.
struct TurnDots: View {
    static let most=12
    @Bindable var studio:DiscordStudio
    let now:Date
    var label:String?=nil
    var body:some View {
        let length=studio.loopLength(at:now),turn=studio.turn(at:now),k=turn%max(1,length),done=studio.turnDone(at:now)
        // A long loop (lists of 3, 4 and 5 take 60 turns) shows the dots round the current one, as many as fit.
        let shown=min(length,Self.most),first=min(max(0,k-shown/2),length-shown)
        if length > 1 {
            HStack(spacing:0) {
                ForEach(first..<first+shown,id:\.self) { index in
                    let on=index == k
                    Capsule().fill(on ? .white.opacity(0.2) : index < k ? DiscordColors.accent.opacity(0.55) : .white.opacity(0.24))
                        .overlay(alignment:.leading) { if on { Capsule().fill(DiscordColors.accent).frame(width:20*done).animation(done < 0.1 ? nil : .linear(duration:1),value:done) } }
                        .frame(width:on ? 20 : 6,height:6).clipShape(Capsule())
                        .shadow(color:on ? Color.rgb(255,140,90).opacity(0.4) : .clear,radius:4)
                        .padding(.horizontal,2.5).frame(height:18).contentShape(Rectangle())
                        .onTapGesture { withAnimation(.curve(.out,0.5)) { studio.jump(to:index,at:now) } }
                }
            }
            .overlay(alignment:.top) {
                let text=label ?? (studio.held != nil ? L("Holding {0} of {1} while you edit",String(k+1),String(length)) : nil)
                if let text {
                    Text(text).designFont(10.5,.semibold).monospacedDigit().foregroundStyle(DiscordColors.ink(0.85)).fixedSize()
                        .padding(.horizontal,7).frame(height:19).background(Color.rgb(17,18,20).opacity(0.92),in:RoundedRectangle(cornerRadius:6))
                        .offset(y:-24).transition(.opacity.combined(with:.offset(y:3))).allowsHitTesting(false)
                }
            }
            .opacity(studio.preview != nil ? 0.35 : 1)
            .animation(.curve(.out,0.5),value:k)
            .environment(\.colorScheme,.dark)
        }
    }
}

/// The card's parts in order, each with what it is now, and a ring and count when several take turns.
struct EditorRail: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        TimelineView(.seconds) { context in
            let now=context.date
            VStack(alignment:.leading,spacing:1) {
                item(.picture,title:L("Image"),now:now) { picture(now) }
                item(.badge,title:L("Badge"),now:now,height:36,leading:38,child:true,nameSize:12) { badge(now) }
                // The icons in the middle of the row, the two words on one baseline, as the design's row sets them.
                HStack(spacing:9) {
                    DesignIcon("ph:game-controller-fill",size:12).foregroundStyle(DiscordColors.ink(0.35)).frame(width:14,height:14).padding(.trailing,-5)
                    HStack(alignment:.firstTextBaseline,spacing:4) {
                        Text(L("Game")).designFont(11,.semibold).foregroundStyle(DiscordColors.ink(0.42)).fixedSize()
                        Text(verbatim:"Overwatch").designFont(11).foregroundStyle(DiscordColors.ink(0.5)).fixedSize()
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    DesignIcon("lucide:lock",size:11).foregroundStyle(DiscordColors.ink(0.35))
                }
                .padding(.leading,17).padding(.trailing,9).frame(height:26)
                .designTip(L("Always shown. Discord takes the name from the game."))
                item(.lineOne,title:L("Line 1"),now:now) { icon("rc:line1") }
                item(.lineTwo,title:L("Line 2"),now:now) { icon("rc:line2") }
                item(.timer,title:L("Timer"),now:now) { icon("ph:timer-fill") }
                item(.buttons,title:L("Buttons"),now:now) { icon("rc:buttons") }
                item(.party,title:L("Party"),now:now) { icon("ph:users-three-fill") }
            }
            .glider(studio.slot,style:.rows,axis:.vertical) { RoundedRectangle(cornerRadius:11).fill(.white.opacity(0.07)) }
        }
    }
    private func item<Tile:View>(_ slot:DiscordStudio.Slot,title:String,now:Date,height:CGFloat=42,leading:CGFloat=11,child:Bool=false,nameSize:CGFloat=12.5,@ViewBuilder tile:()->Tile)->some View {
        let on=studio.slot == slot,count=studio.railCount(slot,at:now)
        return Button { studio.pick(slot) } label: {
            HStack(spacing:9) {
                tile()
                VStack(alignment:.leading,spacing:1) {
                    Text(title).designFont(nameSize,.semibold).lineLimit(1)
                        .animation(.curve(.css,0.25)) { $0.foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.75)) }
                    Text(studio.railSummary(slot,at:now)).designFont(11).foregroundStyle(DiscordColors.ink(0.5)).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
                if count > 1 {
                    HStack(spacing:3) {
                        Ring(done:studio.turnDone(at:now),track:.white.opacity(0.13)).frame(width:10,height:10).padding(1.5)
                        Text("\(count)").designFont(10.5,.bold).monospacedDigit()
                    }.foregroundStyle(DiscordColors.ink(0.55))
                }
            }
            .padding(.leading,leading).padding(.trailing,9).frame(height:height)
            .glideItem(slot)
            .overlay(alignment:.topLeading) { if child { Connector().stroke(.white.opacity(0.13),lineWidth:1.5).frame(width:11.5,height:23.5).offset(x:24,y:-6).allowsHitTesting(false) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func icon(_ name:String)->some View {
        DesignIcon(name,size:14).foregroundStyle(DiscordColors.ink(0.65))
            .frame(width:26,height:26).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
    }
    private func picture(_ now:Date)->some View {
        let url=(studio.activity(at:now)["assets"] as? [String:String])?["large_image"].flatMap(URL.init(string:))
        return Group { if let url { RemoteImage(url:url) { DiscordColors.tile } } else { GameIcon().padding(2.6) } }
            .frame(width:26,height:26).background(url == nil ? .clear : DiscordColors.tile).clipShape(RoundedRectangle(cornerRadius:8))
    }
    private func badge(_ now:Date)->some View {
        let url=(studio.activity(at:now)["assets"] as? [String:String])?["small_image"].flatMap(URL.init(string:)) ?? DiscordAssets.macBadge
        return BadgeImage(url:url,size:20,back:DiscordColors.stage,inset:0.86)
    }
}
/// The rail's line from the image down to its badge: the design's left and bottom borders.
private struct Connector: Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        path.move(to:CGPoint(x:rect.minX+0.75,y:rect.minY))
        path.addArc(tangent1End:CGPoint(x:rect.minX+0.75,y:rect.maxY-0.75),tangent2End:CGPoint(x:rect.maxX,y:rect.maxY-0.75),radius:6.25)
        path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY-0.75))
        return path
    }
}

/// The panel's scroll: no scroll bars; the edges fade where there's more, and a bobbing arrow at the bottom scrolls on.
struct PanelScroller<Content:View>: View {
    @ViewBuilder var content:Content
    @State private var above=false
    @State private var below=false
    @State private var position=ScrollPosition()
    @State private var offset:CGFloat=0
    @State private var page:CGFloat=0
    var body:some View {
        ScrollView { content }
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for:[CGFloat].self) { [$0.contentOffset.y,$0.contentSize.height,$0.containerSize.height] } action:{ _,value in
                offset=value[0];page=value[2]
                above=value[0] > 2;below=value[0]+value[2] < value[1]-2
            }
            .mask {
                VStack(spacing:0) {
                    LinearGradient(colors:[.black.opacity(above ? 0 : 1),.black],startPoint:.top,endPoint:.bottom).frame(height:18)
                    Color.black
                    LinearGradient(colors:[.black,.black.opacity(below ? 0 : 1)],startPoint:.top,endPoint:.bottom).frame(height:28)
                }
            }
            .overlay(alignment:.bottom) {
                if below {
                    Button { withAnimation(.smooth) { position.scrollTo(y:offset+page*0.7) } } label: { BobbingChevron() }
                        .buttonStyle(.plain).accessibilityLabel(L("Scroll down")).transition(.opacity)
                }
            }
            .animation(.easeOut(duration:0.25),value:below)
    }
}
private struct BobbingChevron: View {
    var body:some View {
        DesignIcon("lucide:chevron-down",size:15).foregroundStyle(DiscordColors.ink(0.7))
            .swaying(0.8) { chevron,down in chevron.offset(y:-1+3*down) }.frame(width:30,height:20).contentShape(Rectangle())
    }
}

/// What was just done, with its Undo; and Done.
struct EditorFooter: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        HStack(spacing:0) {
            if let toast=studio.toast {
                HStack(spacing:8) {
                    DesignIcon("lucide:check",size:14).foregroundStyle(DiscordColors.fill)
                    Text(toast.text).designFont(12).foregroundStyle(DiscordColors.bright).lineLimit(1).truncationMode(.tail)
                    if toast.undo != nil {
                        Button { studio.undo() } label: {
                            Text(L("Undo")).designFont(12,.semibold).foregroundStyle(.white)
                                .padding(.horizontal,11).frame(height:26).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.trailing,12).popIn(0.36).id(toast.text).transition(.identity)
            }
            Spacer(minLength:0)
            FillButton(title:L("Done")) { studio.closePage() }.background { Button("",action:studio.escape).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true) }
        }
        .frame(height:30)
        .animation(.curve(.out,0.36),value:studio.toast?.text)
    }
}
/// The design's orange button, a little lighter while pointed at.
struct FillButton: View {
    let title:String
    var icon:String?=nil
    var height:CGFloat=30
    var size:CGFloat=13
    var radius:CGFloat?=nil
    var padding:CGFloat=16
    var weight:Font.Weight = .semibold
    let action:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:action) {
            HStack(spacing:6) {
                if let icon { DesignIcon(icon,size:13) }
                Text(title).designFont(size,weight)
            }
            .foregroundStyle(.white).padding(.horizontal,padding).frame(height:height)
            .background(inside ? DiscordColors.fillHover : DiscordColors.fill,in:RoundedRectangle(cornerRadius:radius ?? height/2))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside=$0 }
    }
}
