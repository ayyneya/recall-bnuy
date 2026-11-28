import SwiftUI

// Settings › Discord as the design lays it out: the card on Discord's pop-out, the level, the BattleTag and What Recall
// remembers. A click on the card opens Customize on that part.

/// The dark stage: Discord's mark (and in Customize the device) on the left; the place (a click tries the next while
/// the game isn't running) and the power on the right.
struct DiscordStage<Content:View,Controls:View>: View {
    @Bindable var studio:DiscordStudio
    var height:CGFloat
    var top:CGFloat=0
    var power=true
    @ViewBuilder var content:Content
    @ViewBuilder var controls:Controls
    var body:some View {
        // The dots and the corners sit inside the stage's one-point border, as the design's do.
        ZStack {
            DotPattern().fill(.white.opacity(0.05)).padding(1).allowsHitTesting(false)
            content.padding(.top,top).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        // Off, what's on the stage blurs well away under the cover.
        .blur(radius:power && !studio.power ? 18 : 0)
        .frame(maxWidth:.infinity).frame(height:height)
        // The bars move with the stage as one, so what comes in with another screen rides along at once.
        .overlay(alignment:.topLeading) {
            HStack(spacing:6) {
                DesignIcon("ic:baseline-discord",size:16).foregroundStyle(DiscordColors.ink(0.45))
                    .frame(width:26,height:26).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:8))
                // What the stage is, on Discord's page (Customize names the card here instead).
                if power { Text(L("In Discord")).designFont(11,.semibold).tracking(11*0.04).foregroundStyle(DiscordColors.ink(0.45)) }
                controls
            }.padding(.leading,11).padding(.top,9).geometryGroup()
        }
        .overlay(alignment:.topTrailing) {
            HStack(spacing:4) {
                // Where the player is says nothing at Basic, and nothing runs while off.
                if studio.level != .normal && studio.power { SceneChip(studio:studio).transition(.identity) }
                if power { PowerButton(studio:studio).transition(.atOnce) }
            }.padding(.trailing,11).padding(.top,9).geometryGroup()
        }
        .overlay { if power && !studio.power { OffCover(studio:studio).transition(.opacity) } }
        .background(DiscordColors.stage)
        .clipShape(RoundedRectangle(cornerRadius:20))
        .overlay { RoundedRectangle(cornerRadius:20).strokeBorder(.white.opacity(0.06),lineWidth:1) }
        .environment(\.colorScheme,.dark)
        .animation(.curve(.out,0.52),value:height)
        .animation(.easeOut(duration:0.3),value:studio.power)
    }
}
extension DiscordStage where Controls == EmptyView {
    init(studio:DiscordStudio,height:CGFloat,top:CGFloat=0,power:Bool=true,@ViewBuilder content:()->Content) {
        self.init(studio:studio,height:height,top:top,power:power,content:content) { EmptyView() }
    }
}
/// Dots every 14 points, like a design canvas.
struct DotPattern: Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        for x in stride(from:7,to:rect.width,by:14) { for y in stride(from:7,to:rect.height,by:14) { path.addEllipse(in:CGRect(x:x-1,y:y-1,width:2,height:2)) } }
        return path
    }
}
/// Where the player is in the preview: the game's own state while it runs (a green dot), or one to try.
struct SceneChip: View {
    @Bindable var studio:DiscordStudio
    @State private var inside=false
    var body:some View {
        let match=studio.sceneName == studio.texts.match
        Button { studio.nextScene() } label: {
            HStack(spacing:6) {
                if studio.live != nil {
                    Circle().fill(DiscordColors.online).frame(width:6,height:6).swaying(0.8) { dot,dim in dot.opacity(1-0.65*dim) }
                }
                DesignIcon(match ? "ph:sword-fill" : "ph:squares-four-fill",size:match ? 12.5 : 14)
                Text(studio.sceneName).designFont(11.5,.semibold)
                if studio.sceneVoice {
                    Text(verbatim:"&").designFont(11.5,.semibold).opacity(0.6)
                    DesignIcon("ph:users-three-fill",size:14)
                    Text(L("Voice")).designFont(11.5,.semibold)
                }
            }
            .foregroundStyle(DiscordColors.ink(inside && studio.live == nil ? 0.85 : 0.5))
            .padding(.leading,8).padding(.trailing,9).frame(height:26)
            .background(inside && studio.live == nil ? .white.opacity(0.06) : .clear,in:RoundedRectangle(cornerRadius:8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { inside=$0 }
        // Another state rolls in from five points below.
        .modifier(PartArrival(trigger:[studio.sceneName,String(studio.sceneVoice)],(ArrivalStart(y:5,opacity:0.2),Animation.curve(.out,0.28)),onAppear:false))
        .accessibilityLabel(studio.live != nil ? L("Following the game") : L("Show the next state"))
        .animation(.easeOut(duration:0.25),value:inside)
    }
}
private struct PowerButton: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        Button { studio.setPower(!studio.power) } label: {
            DesignIcon("lucide:power",size:14)
                .foregroundStyle(studio.power ? Color.rgb(90,220,140) : DiscordColors.ink(0.6))
                .frame(width:26,height:26).background(.white.opacity(studio.power ? 0.06 : 0.1),in:RoundedRectangle(cornerRadius:8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Discord activity on or off"))
    }
}
/// The stage while the card is off.
private struct OffCover: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        VStack(spacing:8) {
            DesignIcon("lucide:power-off",size:22).foregroundStyle(DiscordColors.ink(0.6))
            Text(L("Discord activity is off")).designFont(14,.semibold).foregroundStyle(DiscordColors.body)
            Text(L("Recall stops reading the game log and disconnects from Discord: nothing stays loaded. When on, it uses well under 0.1% of your CPU."))
                .designFont(12,line:12*1.5).foregroundStyle(DiscordColors.ink(0.62)).multilineTextAlignment(.center).frame(maxWidth:300)
            FillButton(title:L("Turn on"),height:30,size:12.5,radius:9,padding:14,weight:.bold) { studio.setPower(true) }.padding(.top,6)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        // Over the blurred stage: lightest in the middle, to 94% dark at the edges past seven tenths.
        .background(EllipticalGradient(stops:[.init(color:Self.cover.opacity(0.7),location:0),.init(color:Self.cover.opacity(0.72),location:0.7),
                                              .init(color:Self.cover.opacity(0.8),location:0.8),.init(color:Self.cover.opacity(0.89),location:0.9),
                                              .init(color:Self.cover.opacity(0.94),location:1)],center:.center,startRadiusFraction:0,endRadiusFraction:0.5))
    }
    private static let cover=Color.rgb(23,24,27)
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// Discord's page, for what's drawn across it (LevelFlow).
    static var discordTab:NamedCoordinateSpace { .named("discordTab") }
}
/// Discord's pages are dark by design: the whole app turns dark while they show, every window crossfading.
@MainActor enum DiscordDark {
    /// The app's own appearance from before (nil: the system's), while the pages keep it dark.
    private static var before:NSAppearance??
    static func set(_ on:Bool,fade:Bool=true) {
        guard on != (before != nil) else { return }
        let next=on ? NSAppearance(named:.darkAqua) : before ?? nil
        before=on ? .some(NSApp.appearance) : nil
        let dark={ (appearance:NSAppearance?) in
            appearance.map { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua } ?? (UserDefaults.standard.string(forKey:"AppleInterfaceStyle") == "Dark")
        }
        // A Mac that's dark already stays as it is.
        if fade && dark(next) != dark(NSApp.effectiveAppearance) {
            for window in NSApp.windows where window.isVisible {
                guard let layer=window.contentView?.superview?.layer ?? window.contentView?.layer else { continue }
                let fade=CATransition();fade.type = .fade;fade.duration=0.35;fade.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
                layer.add(fade,forKey:"discordDark")
            }
        }
        NSApp.appearance=next
    }
}
// MARK: Settings › Discord

extension LauncherStyle {
    /// The Settings sheet's own coordinate space, where what travels as its header folds is measured.
    static let sheetSpace="launcherSheet"
}
extension View {
    /// Settings › Discord over Settings while open: Discord's pages in the tabs' place, the header folding into their
    /// breadcrumb.
    func discordPages(_ studio:DiscordStudio,tab:SettingsTab,uninstall:@escaping ()->Void,uninstalling:Bool)->some View {
        modifier(DiscordOverSettings(studio:studio,tab:tab,uninstall:uninstall,uninstalling:uninstalling))
    }
}
/// Over the whole sheet, so Recall's Settings stays as it is under it. The pages' header stays laid out while closed,
/// so the fold is measured first; closing, a copy of Settings' header opens over the real one until it lands.
private struct DiscordOverSettings: ViewModifier {
    @Bindable var studio:DiscordStudio
    let tab:SettingsTab
    let uninstall:()->Void
    let uninstalling:Bool
    @Environment(\.dismiss) private var dismiss
    func body(content:Content)->some View {
        let open=studio.open,folding=studio.fold?.header == true
        content
            .opacity(open ? 0 : 1).allowsHitTesting(!open).accessibilityHidden(open).disabled(open)
            .overlay {
                DesignTipLayer(tips:studio.tips) {
                    ZStack(alignment:.topLeading) {
                        if open { DiscordGround() } else { LauncherBackground().mask(alignment:.top) { Rectangle().frame(height:HeaderFold.band) } }
                        VStack(alignment:.leading,spacing:0) {
                            SettingsHeaderCopy(studio:studio,tab:tab).frame(height:open ? 0 : HeaderFold.chrome,alignment:.top).clipped()
                            DiscordPageHeader(studio:studio)
                            // Coming in, the pages ride up with the folding header; going back, they go at once, as in
                            // the design.
                            if open { DiscordPages(studio:studio) { footer }.transition(.asymmetric(insertion:.ride(HeaderFold.chrome),removal:.atOnce)) }
                        }
                        .padding(.top,22).padding(.horizontal,28).padding(.bottom,20)
                        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
                        .animation(.curve(.out,HeaderFold.length),value:open)
                        HeaderFoldLayer(studio:studio)
                    }
                    .coordinateSpace(.named(LauncherStyle.sheetSpace))
                }
                .font(LauncherStyle.font(14)).tint(.primary)
                .opacity(open || folding ? 1 : 0).allowsHitTesting(open).accessibilityHidden(!open).disabled(!open)
            }
            .onAppear { studio.settingsOpened() }
            .onDisappear { studio.settingsClosed();DiscordDark.set(false) }
            // From the home screen, at once: a crossfade then would ride on the sheet as macOS slides it in.
            .onChange(of:open,initial:true) { was,now in DiscordDark.set(now,fade:was != now) }
    }
    /// Uninstall and Done as the design draws them: a red Uninstall with Lucide's bin, Done on a quiet capsule.
    private var footer:some View {
        HStack {
            Button(role:.destructive,action:uninstall) {
                HStack(spacing:6) { DesignIcon("lucide:trash-2",size:13);Text(L("Uninstall {0}…",Brand.name)).designFont(13,.medium) }.contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.red).disabled(uninstalling).opacity(uninstalling ? 0.4 : 1)
                .help(L("Move {0}, Battle.net and Overwatch to the Trash",Brand.name))
            Spacer()
            Button { dismiss() } label: {
                Text(L("Done")).designFont(13,.medium).foregroundStyle(DiscordColors.body)
                    .padding(.horizontal,16).frame(height:30).background(DiscordColors.veil(0.1),in:Capsule()).contentShape(Capsule())
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }.frame(height:30)
    }
}
/// The sheet under Discord's pages: dark, with the design's light at the top in place of Recall's.
private struct DiscordGround: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body:some View {
        LauncherStyle.ground(scheme).overlay(alignment:.top) { if !reduceTransparency { SettingsGlow() } }
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
/// The design's light: 520 by 420 points, half above the sheet, orange round the title (out by 213) and a touch of pink
/// (out by 239).
private struct SettingsGlow: View {
    var body:some View {
        let orange=Color(red:1,green:128/255,blue:64/255),pink=Color(red:1,green:92/255,blue:138/255)
        ZStack {
            RadialGradient(colors:[orange.opacity(0.13),orange.opacity(0)],center:UnitPoint(x:0.42,y:0.5),startRadius:0,endRadius:213.2)
            RadialGradient(colors:[pink.opacity(0.08),pink.opacity(0)],center:UnitPoint(x:0.62,y:0.56),startRadius:0,endRadius:239.4)
        }
        .frame(width:520,height:420).clipped().offset(y:-210)
    }
}
/// Settings' title and tabs drawn as SettingsSheet draws them, for the fold: the other tabs slip aside, the chosen one
/// fades (HeaderFold.tab), "Settings" travels (HeaderFoldTexts).
private struct SettingsHeaderCopy: View {
    @Bindable var studio:DiscordStudio
    let tab:SettingsTab
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        FoldTime { t in
            let fold=studio.fold?.header == true ? studio.fold : nil,tabs=SettingsTab.allCases,chosen=tabs.firstIndex(of:tab) ?? 0
            VStack(spacing:16) {
                LauncherHeading(title:L("Settings"),subtitle:"",compact:true)
                    .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(LauncherStyle.sheetSpace)) } action:{ if studio.fold == nil { studio.foldFrames[.title]=$0 } }
                    .opacity(fold == nil ? 1 : 0).animation(nil,value:fold)
                HStack(spacing:6) {
                    ForEach(Array(tabs.enumerated()),id:\.element) { place,each in
                        let look=fold.map { HeaderFold.tab(place-chosen,$0,at:t) } ?? (1,0)
                        self.tab(each,selected:place == chosen).opacity(look.opacity).offset(x:look.shift)
                    }
                }
            }
            .padding(.top,6).frame(maxWidth:.infinity)
        }
        .foldClock(studio.folds)
        .accessibilityHidden(true)
    }
    private func tab(_ tab:SettingsTab,selected:Bool)->some View {
        let shape=RoundedRectangle(cornerRadius:14,style:.continuous)
        return VStack(spacing:5) {
            Image(systemName:tab.symbol).font(.system(size:17,weight:.medium)).frame(height:21)
                .foregroundStyle(selected ? AnyShapeStyle(LauncherStyle.accent) : AnyShapeStyle(.secondary))
            Text(tab.title).font(LauncherStyle.font(12,selected ? .semibold : .medium)).foregroundStyle(selected ? .primary : .secondary)
        }.frame(width:78,height:54)
            .background { if selected { shape.fill(LauncherStyle.surface(scheme)).overlay { shape.strokeBorder(.primary.opacity(0.05),lineWidth:1) } } }
    }
}
/// Discord's pages as one column under their breadcrumb. The stage stays put between Discord's page and Customize, only
/// changing height.
struct DiscordPages<Footer:View>: View {
    @Bindable var studio:DiscordStudio
    /// Uninstall and Done, under Discord's page.
    @ViewBuilder var footer:Footer
    var body:some View {
        let home=studio.screen == .home
        // What comes in starts where it would sit, carried as the stage resizes, then moves into place and fades in.
        let ride=studio.ride
        VStack(alignment:.leading,spacing:0) {
            // What leaves goes at once, as in the design (a removal keeps its view on screen as long as it lasts).
            switch studio.screen {
            case .profile,.history:
                Group { if studio.screen == .profile { ProfilePage(studio:studio) } else { HistoryPage(studio:studio) } }
                    .padding(.top,16).frame(maxHeight:.infinity,alignment:.top)
                    .transition(.asymmetric(insertion:.ride(ride.page).combined(with:.opacity).combined(with:.offset(y:22)),removal:Self.gone))
            case .home,.editor:
                // Over the page under it, which starts out under it as it grows.
                CardStage(studio:studio).padding(.top,14).zIndex(1)
                    .transition(.asymmetric(insertion:.ride(ride.header).combined(with:.opacity.combined(with:.offset(y:8)).animation(.curve(.out,0.45))),
                                            removal:Self.gone))
                if home {
                    DiscordHome(studio:studio) { footer }
                        .transition(.asymmetric(insertion:.ride(ride.page).combined(with:.opacity).combined(with:.offset(y:-22)),removal:Self.gone))
                } else {
                    DiscordEditor(studio:studio)
                        .transition(.asymmetric(insertion:.ride(ride.page).combined(with:.opacity).combined(with:.offset(y:22)),removal:Self.gone))
                    // Customize's Done is there at once, where it stays.
                    EditorFooter(studio:studio).padding(.top,12).transition(.atOnce)
                }
            }
        }
        .animation(.curve(.out,0.52),value:studio.screen)
        // Customize's sparks and light, across the page.
        .overlay(alignment:.topLeading) { if let flow=studio.levelFlow { LevelFlow(flow:flow,studio:studio) } }
        .coordinateSpace(.discordTab)
    }
    private static var gone:AnyTransition { .opacity.animation(.linear(duration:0)) }
}
extension DiscordStudio {
    /// How far what comes in starts from where it ends (AnyTransition.ride): the stage's change.
    var ride:(header:CGFloat,page:CGFloat) {
        let staged:Set<Screen>=[.home,.editor]
        guard staged.contains(screen),staged.contains(came.screen) else { return (0,0) }
        return (0,CardStage.height(came.screen,gallery:came.gallery)-CardStage.height(screen,gallery:gallery))
    }
}
/// Discord's own page under the card: the level, the BattleTag and what Recall remembers; off, all dimmed.
struct DiscordHome<Footer:View>: View {
    @Bindable var studio:DiscordStudio
    @ViewBuilder var footer:Footer
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            VStack(alignment:.leading,spacing:10) {
                LevelWords(studio:studio)
                Text(studio.power ? studio.level.detail : L("Off. Nothing runs until you turn it back on."))
                    .designFont(12.5,line:12.5*1.45).foregroundStyle(DiscordColors.ink(0.62)).padding(.leading,4)
                // The rows sit at the bottom, taking what room there is (DiscordRows).
                Spacer(minLength:0)
                DiscordRows(studio:studio).layoutPriority(1)
            }
            .opacity(studio.power ? 1 : 0.28).allowsHitTesting(studio.power)
            .animation(.easeOut(duration:0.35),value:studio.power)
            .frame(maxHeight:.infinity,alignment:.top)
            footer
        }
        .padding(.top,14)
    }
}
/// A fine dashed outline marching round the card while it's the player's own: the dashes divide it exactly, no seam. It
/// fades in after Customize's light has traced the card.
struct MarchingOutline: View {
    /// Whether it shows; it fades in over 0.38 s after `delay`, out over 0.22 s, and the dashes stop once gone.
    var on:Bool
    var delay:Double=0
    @State private var shown=false
    @State private var present=false
    var body:some View {
        GeometryReader { box in
            if present {
                let outline=CardOutline(inset:0.75,radius:7.25),period=outline.period(in:box.size)
                // A period each 1.2 s per ten points, off the clock (a repeatForever took the sheet along as Settings
                // opened).
                TimelineView(.animation(paused:!Moving.shared.now)) { time in
                    let march=period > 0 ? time.date.timeIntervalSinceReferenceDate/(1.2*period/10) : 0
                    outline.stroke(LinearGradient(stops:CardOutline.colors,startPoint:.bottom,endPoint:.top),
                                   style:StrokeStyle(lineWidth:1.5,lineCap:.round,dash:[period/2,period/2],dashPhase:-march.truncatingRemainder(dividingBy:1)*period))
                }
            }
        }
        // Coming back to Discord's page, it shows on the card as the card still moves into place.
        .geometryGroup()
        .opacity(shown ? 0.9 : 0).allowsHitTesting(false)
        .onAppear { if on { show() } }
        .onChange(of:on) { _,on in
            if on { show();return }
            withAnimation(.linear(duration:0.22)) { shown=false } completion:{ if !shown { present=false } }
        }
    }
    private func show() {
        present=true
        withAnimation(.easeOut(duration:0.38).delay(delay)) { shown=true }
    }
}
/// The card's edge as the design draws round it, from the bottom's middle (`inset`, `radius`), or one side to the top's
/// middle (`side`: -1 left, 1 right).
struct CardOutline: Shape {
    var inset:CGFloat=0
    var radius:CGFloat=8
    var side=0
    /// Amber at the bottom to violet at the top.
    static let colors:[Gradient.Stop]=[.init(color:DiscordColors.amber,location:0),.init(color:Color.rgb(255,140,70),location:0.3),
                                       .init(color:Color.rgb(255,112,104),location:0.55),.init(color:Color.rgb(255,92,138),location:0.8),
                                       .init(color:Color.rgb(214,98,230),location:1)]
    func path(in rect:CGRect)->Path {
        let r=radius,left=rect.minX+inset,top=rect.minY+inset,right=rect.maxX-inset,bottom=rect.maxY-inset,middle=rect.midX
        var path=Path()
        path.move(to:CGPoint(x:middle,y:bottom))
        if side == 1 {
            path.addLine(to:CGPoint(x:right-r,y:bottom))
            path.addArc(tangent1End:CGPoint(x:right,y:bottom),tangent2End:CGPoint(x:right,y:bottom-r),radius:r)
            path.addLine(to:CGPoint(x:right,y:top+r))
            path.addArc(tangent1End:CGPoint(x:right,y:top),tangent2End:CGPoint(x:right-r,y:top),radius:r)
            path.addLine(to:CGPoint(x:middle,y:top))
            return path
        }
        path.addLine(to:CGPoint(x:left+r,y:bottom))
        path.addArc(tangent1End:CGPoint(x:left,y:bottom),tangent2End:CGPoint(x:left,y:bottom-r),radius:r)
        path.addLine(to:CGPoint(x:left,y:top+r))
        path.addArc(tangent1End:CGPoint(x:left,y:top),tangent2End:CGPoint(x:left+r,y:top),radius:r)
        if side == -1 { path.addLine(to:CGPoint(x:middle,y:top));return path }
        path.addLine(to:CGPoint(x:right-r,y:top))
        path.addArc(tangent1End:CGPoint(x:right,y:top),tangent2End:CGPoint(x:right,y:top+r),radius:r)
        path.addLine(to:CGPoint(x:right,y:bottom-r))
        path.addArc(tangent1End:CGPoint(x:right,y:bottom),tangent2End:CGPoint(x:right-r,y:bottom),radius:r)
        path.closeSubpath()
        return path
    }
    /// The dashes' period: about ten points, dividing the whole outline exactly.
    func period(in size:CGSize)->CGFloat {
        let length=2*(size.width-2*inset-2*radius)+2*(size.height-2*inset-2*radius)+2*CGFloat.pi*radius
        return length/max(1,(length/10).rounded())
    }
}

/// Customize picked on Discord's page: seven sparks pop from the word, a light curves into the card (0.44 s), two
/// strokes run round to meet at the top (0.5 s), and the outline glows and fades (0.95 s).
struct LevelFlow: View {
    let flow:DiscordStudio.LevelFlowStart
    let studio:DiscordStudio
    var body:some View {
        TimelineView(.animation) { context in
            let time=context.date.timeIntervalSince(flow.at)
            Canvas { canvas,_ in
                sparks(canvas,time)
                if time < 0.44 { light(canvas,time/0.44) } else if time < 1.44 { trace(canvas,time-0.44) }
            }
        }
        .allowsHitTesting(false)
        .task(id:flow.id) {
            try? await Task.sleep(for:.seconds(1.5))
            if studio.levelFlow?.id == flow.id { studio.levelFlow=nil }
        }
    }
    /// The sparks' own chance, the same at every frame: four numbers for each.
    private var chance:[Double] {
        var seed=UInt64(truncatingIfNeeded:flow.id.hashValue)
        return (0..<28).map { _ in seed=seed &* 6364136223846793005 &+ 1442695040888963407;return Double(seed>>11)/Double(1 << 53) }
    }
    private func sparks(_ canvas:GraphicsContext,_ time:Double) {
        let colors=[DiscordColors.amber,DiscordColors.fill,Color.rgb(255,92,138),Color.rgb(214,98,230)]
        let chance=chance,center=CGPoint(x:flow.from.midX,y:flow.from.midY)
        for index in 0..<7 {
            let angle=Double(index)/7*2*Double.pi+chance[index*4]*0.6,distance=18+chance[index*4+1]*14,size=3+chance[index*4+2]*2.5
            let progress=min(1,time/(0.52+chance[index*4+3]*0.16))
            guard progress < 1 else { continue }
            let eased=Ease.bezier(0.2,0.7,0.3,1)(progress),scale=1-0.8*eased,color=colors[index%colors.count]
            let at=CGPoint(x:center.x+cos(angle)*distance*1.6*eased,y:center.y+sin(angle)*distance*eased)
            var layer=canvas
            layer.opacity=1-eased
            layer.addFilter(.shadow(color:color,radius:3))
            layer.fill(Path(ellipseIn:CGRect(x:at.x-size*scale/2,y:at.y-size*scale/2,width:size*scale,height:size*scale)),with:.color(color))
        }
    }
    /// The light, from the top of the word to the bottom of the card: quick out sideways, easing in and out upwards.
    private func light(_ canvas:GraphicsContext,_ progress:Double) {
        let card=studio.cardFrame,start=CGPoint(x:flow.from.midX,y:flow.from.minY),end=CGPoint(x:card.midX,y:card.maxY)
        let across=1-pow(1-progress,2.4),up=progress < 0.5 ? 4*pow(progress,3) : 1-pow(-2*progress+2,3)/2
        let at=CGPoint(x:start.x+(end.x-start.x)*across,y:start.y+(end.y-start.y)*up),size=8*(1-0.25*progress)
        var layer=canvas
        layer.addFilter(.shadow(color:DiscordColors.fill,radius:7))
        layer.addFilter(.shadow(color:DiscordColors.amber,radius:2.5))
        layer.fill(Path(ellipseIn:CGRect(x:at.x-size/2,y:at.y-size/2,width:size,height:size)),with:.color(Color.rgb(255,226,190)))
    }
    private func trace(_ canvas:GraphicsContext,_ time:Double) {
        let card=studio.cardFrame
        guard card.width > 0 else { return }
        let drawn=Ease.bezier(0.4,0,0.2,1)(min(1,time/0.5)),fading=Ease.bezier(0.42,0,1,1)(min(1,time/0.95))
        var layer=canvas
        layer.opacity=fading < 0.5 ? 1 : 2*(1-fading)
        layer.addFilter(.shadow(color:Color.rgb(255,150,90).opacity(0.9),radius:2))
        layer.addFilter(.shadow(color:Color.rgb(255,92,138).opacity(0.5),radius:6))
        let shading=GraphicsContext.Shading.linearGradient(Gradient(stops:CardOutline.colors),startPoint:CGPoint(x:card.midX,y:card.maxY),endPoint:CGPoint(x:card.midX,y:card.minY))
        for side in [-1,1] {
            layer.stroke(CardOutline(radius:8,side:side).path(in:card).trimmedPath(from:0,to:drawn),with:shading,style:StrokeStyle(lineWidth:2,lineCap:.round))
        }
    }
}

/// An eye, then "Basic  Live  Full  Customize ›": the chosen one bright, underlined by a line that glides to another (a
/// ribbon under Customize). Picking Customize sends sparks into the card; picking it again opens it.
struct LevelWords: View {
    @Bindable var studio:DiscordStudio
    @State private var inside:DiscordPresenceLevel?
    /// Where each word's text is, in the row (for the line) and on the page (for the light).
    @State private var words:[DiscordPresenceLevel:CGRect]=[:]
    @State private var customOnTab=CGRect.zero
    /// Where the line glides from, and a count of glides and of each word's springs, which start them.
    @State private var glideFrom:CGRect?
    @State private var glides=0
    @State private var springs:[DiscordPresenceLevel:Int]=[:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        HStack(spacing:14) {
            DesignIcon("lucide:eye",size:16).foregroundStyle(DiscordColors.ink(0.42)).accessibilityHidden(true)
            HStack(spacing:18) {
                ForEach(DiscordPresenceLevel.allCases) { level in word(level) }
            }
            .background(alignment:.topLeading) { line }
            .coordinateSpace(.named(Self.row))
            .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(LauncherStyle.sheetSpace)) } action:{ studio.foldFrames[.levelRow]=$0 }
        }.frame(height:34).padding(.leading,2)
    }
    private static let row="levelWords"
    /// Whether Customize's morph is bringing its word and line back here (StudioMorph carries them till it's done).
    private var comingBack:Bool { studio.fold.map { !$0.opening && $0.studio } ?? false }
    private func word(_ level:DiscordPresenceLevel)->some View {
        let on=studio.level == level,custom=level == .custom
        return Button { pick(level) } label: {
            HStack(spacing:5) {
                Group {
                    if custom { RibbonText(text:level.title,weight:on ? 700 : 650) }
                    else {
                        // Its colour changes over 0.35 s, its weight at once, as the design's do.
                        Text(level.title).designFont(14,on ? .bold : .medium)
                            .animation(.curve(.css,0.35)) { $0.foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.55)) }
                    }
                }
                .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(Self.row)) } action:{ words[level]=$0 }
                .onGeometryChange(for:CGRect.self) { $0.frame(in:.discordTab) } action:{ if custom { customOnTab=$0 } }
                .onGeometryChange(for:CGRect.self) { $0.frame(in:.named(LauncherStyle.sheetSpace)) } action:{ if custom { studio.foldFrames[.customize]=$0 } }
                .opacity(custom && comingBack ? 0 : 1).animation(nil,value:comingBack)
                .keyframeAnimator(initialValue:1.0,trigger:springs[level] ?? 0) { word,progress in
                    word.scaleEffect(1.14-0.14*Ease.outElastic()(progress))
                } keyframes:{ _ in
                    MoveKeyframe(0.0)
                    LinearKeyframe(1.0,duration:0.52)
                }
                if custom && on {
                    DesignIcon("lucide:chevron-right",size:14).foregroundStyle(Color.rgb(255,150,120).opacity(0.8)).padding(.leading,-2)
                        .transition(.asymmetric(insertion:.opacity.combined(with:.offset(y:8)).animation(.curve(.css,0.35)),removal:.identity))
                }
            }
            .frame(height:34)
            .brightness(inside == level ? 0.15 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { inside=$0 ? level : nil }
        .accessibilityLabel(custom && on ? L("Edit your card") : level.title).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func pick(_ level:DiscordPresenceLevel) {
        if studio.level != level && !reduceMotion {
            glideFrom=words[studio.level];glides+=1
            if level == .custom { studio.levelFlow=DiscordStudio.LevelFlowStart(from:customOnTab,at:Date()) } else { springs[level,default:0]+=1 }
        }
        // Customize again opens the editor, with the screen's own move.
        if studio.level == level && level == .custom { withAnimation(.curve(.out,0.52)) { studio.choose(level) } } else { studio.choose(level) }
    }
    /// The line under the chosen word: three points high, a point above the row's bottom.
    private var line:some View {
        let to=words[studio.level] ?? .zero,from=glideFrom ?? to,custom=studio.level == .custom
        return Underline(custom:custom)
            .keyframeAnimator(initialValue:1.0,trigger:glides) { bar,progress in
                let at=GlideStyle.words.span(from:(from.minX,from.width),to:(to.minX,to.width),at:progress)
                bar.frame(width:max(0,at.length),height:3).scaleEffect(y:at.squash).offset(x:at.start,y:30)
            } keyframes:{ _ in
                MoveKeyframe(0.0)
                LinearKeyframe(1.0,duration:GlideStyle.words.duration)
            }
            .opacity(to == .zero || comingBack ? 0 : 1).animation(nil,value:comingBack)
    }
}
/// The level's line: white, or under Customize the ribbon with an orange glow, changing over 0.45 s.
private struct Underline: View {
    let custom:Bool
    var body:some View {
        let glow=custom ? Color.rgb(255,140,80).opacity(0.38) : DiscordColors.ink(0.16)
        ZStack {
            DiscordColors.ink(1).opacity(custom ? 0 : 1)
            // Only while it shows: the ribbon moves every frame.
            if custom { RibbonLine(rounded:false).transition(.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius:2))
        .shadow(color:glow,radius:5).shadow(color:glow,radius:1.5)
        .animation(.curve(.css,0.45),value:custom)
    }
}
/// Customize's word: the design's ribbon of colour moving through the letters.
private struct RibbonText: View {
    let text:String
    let weight:Int
    var body:some View {
        Text(text).designFont(14,weight).foregroundStyle(.clear)
            .overlay { RibbonLine(rounded:false).mask { Text(text).designFont(14,weight) } }
    }
}

/// The BattleTag (with the rank it shows) at Full and Customize, and What Recall remembers, each opening its page.
struct DiscordRows: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        ShrinkingColumn {
            if studio.level == .full || studio.level == .custom {
                RowButton(height:44) { studio.openProfile() } label: {
                    DesignIcon("simple-icons:battledotnet",size:15).foregroundStyle(DiscordColors.ink(0.55))
                    if studio.battleTag.isEmpty {
                        Text(L("Add your BattleTag")).designFont(13,.semibold).foregroundStyle(DiscordColors.body).fixedSize()
                        Text(L("for ranks and records")).designFont(11.5).foregroundStyle(DiscordColors.ink(0.5)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    } else {
                        Text(verbatim:studio.battleTag).designFont(13,.semibold).foregroundStyle(DiscordColors.body).fixedSize()
                        if let chip=studio.tagChip {
                            HStack(spacing:5) {
                                if let icon=chip.icon { RemoteImage(url:icon,fill:false) { Color.clear }.frame(width:16,height:16) } else { DesignIcon("lucide:lock",size:12) }
                                Text(chip.text).designFont(11.5,.semibold)
                            }
                            .foregroundStyle(DiscordColors.ink(0.85))
                            .padding(.leading,chip.icon == nil ? 7 : 5).padding(.trailing,9).frame(height:24)
                            .background(DiscordColors.veil(0.06),in:RoundedRectangle(cornerRadius:7)).fixedSize()
                        }
                        Text(studio.tagNote).designFont(11.5).foregroundStyle(DiscordColors.ink(0.5)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    DesignIcon("lucide:chevron-right",size:14).foregroundStyle(DiscordColors.ink(0.4))
                }
                Rectangle().fill(DiscordColors.veil(0.06)).frame(height:1).padding(.horizontal,12)
            }
            RowButton(height:40) { studio.openHistory() } label: {
                DesignIcon("lucide:database",size:14).foregroundStyle(DiscordColors.ink(0.55))
                Text(L("What Recall remembers")).designFont(12.5,.medium).foregroundStyle(DiscordColors.body).frame(maxWidth:.infinity,alignment:.leading)
                Text(studio.historyNote).designFont(11.5).foregroundStyle(DiscordColors.ink(0.45)).lineLimit(1)
                DesignIcon("lucide:chevron-right",size:14).foregroundStyle(DiscordColors.ink(0.4))
            }
        }
        // Inside its one-point border, as the design's box is.
        .padding(1)
        .background(DiscordColors.veil(0.04),in:RoundedRectangle(cornerRadius:13))
        .clipShape(RoundedRectangle(cornerRadius:13))
        .overlay { RoundedRectangle(cornerRadius:13).strokeBorder(DiscordColors.veil(0.06),lineWidth:1) }
    }
}
/// A column whose rows give up height in proportion when room is short, as the design's flexbox does.
struct ShrinkingColumn: Layout {
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let ideal=subviews.reduce(0) { $0+$1.sizeThatFits(ProposedViewSize(width:proposal.width,height:nil)).height }
        return CGSize(width:proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0,height:min(ideal,proposal.height ?? ideal))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let ideals=subviews.map { $0.sizeThatFits(ProposedViewSize(width:bounds.width,height:nil)).height }
        let total=ideals.reduce(0,+),scale=total > bounds.height && total > 0 ? bounds.height/total : 1
        var y=bounds.minY
        for (subview,ideal) in zip(subviews,ideals) {
            subview.place(at:CGPoint(x:bounds.minX,y:y),proposal:ProposedViewSize(width:bounds.width,height:ideal*scale))
            y+=ideal*scale
        }
    }
}
/// A row that opens a page, faintly lit while pointed at.
struct RowButton<Label:View>: View {
    /// Its height when there's room (ShrinkingColumn gives it less when there isn't).
    var height:CGFloat
    let action:()->Void
    @ViewBuilder var label:Label
    @State private var inside=false
    var body:some View {
        Button(action:action) {
            HStack(spacing:10) { label }
                .padding(.leading,13).padding(.trailing,12).frame(minHeight:0,idealHeight:height,maxHeight:height).frame(maxWidth:.infinity)
                .background(inside ? DiscordColors.veil(0.04) : .clear).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside=$0 }
    }
}

extension DiscordStudio {
    var sceneName:String {
        if let live {
            switch live.place {
            case .match: return texts.match
            case .menu: return texts.menu
            case .unknown: return live.voice != nil ? texts.group : texts.game
            }
        }
        return scene == .match || scene == .matchVoice ? texts.match : texts.menu
    }
    var sceneVoice:Bool { live.map { $0.voice != nil } ?? (scene == .menusVoice || scene == .matchVoice) }
    func nextScene() {
        guard live == nil else { return }
        let all=Scene.allCases
        scene=all[(all.firstIndex(of:scene)!+1)%all.count];held=nil
    }
    /// A part clicked on the home page's card: Customize, on that part.
    func openEditor(at slot:Slot) {
        openEditor();pick(slot)
    }
    /// The ring after Line 2 on the home page, while lines take turns there.
    func homeLineTwoTurn(at now:Date)->(done:Double,label:String)? {
        let inputs=inputs(at:now),lists=DiscordCardDesign.Shown(shown,inputs,turn:turn(at:now))
        guard level == .full || level == .custom,lists.lineTwo.count > 1,inputs.menus,inputs.voice == nil || shown.party == .noCount else { return nil }
        let k=turn(at:now)%lists.lineTwo.count
        return (turnDone(at:now),L("Line {0} of {1}",String(k+1),String(lists.lineTwo.count)))
    }
    /// The chip after the BattleTag: the rank it shows (with its emblem), or that the profile is private.
    var tagChip:(text:String,icon:URL?)? {
        switch profileState {
        case .none: return nil
        case .hidden: return (L("Private"),nil)
        case .missing: return (L("Not found"),nil)
        case .shown: return CardInputs(profile:profile,history:history,launched:Date(),now:Date(),texts:texts).rank(.lastPlayed).map { ($0.name,$0.icon) }
        }
    }
    var tagNote:String {
        if otherAccount { return L("Discord is signed in as another account") }
        if lookingUp { return L("Looking up…") }
        switch profileState {
        case .none: return busy ? L("Too many lookups · try again in a moment") : offline ? L("OverFast didn’t answer · Recall asks again later") : L("Not found yet")
        case .missing: return L("Check the capitals and the number")
        case .hidden: return L("Ranks and records hidden")
        case .shown: return lookedUpAgo.map { L("Looked up {0}",$0) } ?? ""
        }
    }
    var historyNote:String {
        let count=history.runs.count
        return count == 0 ? L("Nothing kept") : count == 1 ? L("1 session on this Mac") : L("{0} sessions on this Mac",String(count))
    }
}

// MARK: the header folding

/// Settings' header folding into Discord's breadcrumb and back: "Settings" travels as real text (resized, never scaled,
/// so it lands sharp), the other tabs slip aside, the chosen one fades, then the title comes in; closing, the other
/// way.
enum HeaderFold {
    /// The header's title and breadcrumb; Customize's word and row, the card's title, and the card on each page
    /// (StudioMorph).
    enum Text: Hashable { case title,settings,customize,levelRow,cardTitle,shellHome,shellEditor }
    /// The header's height, which the breadcrumb moves with: 6 points, the title, 16 and the tabs.
    static let chrome:CGFloat=109
    /// From the sheet's top to just under the tabs, short of Settings' page.
    static let band:CGFloat=22+chrome+8
    static let length=0.52
    /// How long it all plays, the last tab coming back included.
    static let total=0.62
    /// A tab's look `t` seconds in, by its place from the chosen tab: how opaque, and how far to its side.
    static func tab(_ place:Int,_ fold:DiscordStudio.Fold,at t:Double)->(opacity:Double,shift:CGFloat) {
        let away=Double(abs(place)),side=CGFloat(place.signum())
        if fold.opening {
            if place == 0 { return (1-Ease.inOut(t,from:0.04,over:0.22),0) }
            let q=Ease.inOut(t,from:(away-1)*0.024,over:0.24)
            return (1-q,side*12*q)
        }
        if place == 0 { return (Ease.out(t,from:0.14,over:0.26),0) }
        let q=Ease.out((t-0.16-(away-1)*0.024)/0.34)
        return (q,side*12*(1-q))
    }
    /// The title under the breadcrumb: how opaque, how far below its place.
    static func title(_ fold:DiscordStudio.Fold,at t:Double)->(opacity:Double,rise:CGFloat) {
        if fold.opening { let q=Ease.out(t,from:0.09,over:0.44);return (q,10*(1-q)) }
        let q=Ease.inOut(t,over:0.16)
        return (1-q,6*q)
    }
}

extension EnvironmentValues {
    /// Seconds into the fold playing (HeaderFold), as FoldClock counts them; its whole length once none is.
    @Entry var foldTime:Double=HeaderFold.total
}
/// SwiftUI's own clock for the fold (foldTime): linear over its length, starting with the change's other animations so
/// it keeps step with the layout. Two clocks take turns, so a new fold starts from its beginning.
private struct FoldClock: ViewModifier, Animatable {
    var odd:Double,even:Double
    let count:Int
    init(_ count:Int) { self.count=count;odd=Double((count+1)/2);even=Double(count/2) }
    var animatableData:AnimatablePair<Double,Double> { get { AnimatablePair(odd,even) } set { odd=newValue.first;even=newValue.second } }
    func body(content:Content)->some View {
        let played=count%2 == 1 ? odd-Double((count+1)/2-1) : even-Double(count/2-1)
        content.environment(\.foldTime,min(1,max(0,played))*HeaderFold.total)
    }
}
extension View {
    /// The fold's clock: what changes as a fold starts takes its look from the time, not an animation.
    func foldClock(_ count:Int)->some View {
        transaction(value:count) { $0.animation=nil }
            .modifier(FoldClock(count))
            .animation(.linear(duration:HeaderFold.total),value:count)
    }
}
/// Its content, given the fold's time (foldTime).
struct FoldTime<Content:View>: View {
    @Environment(\.foldTime) private var time
    @ViewBuilder let content:(Double)->Content
    var body:some View { content(time) }
}

/// Where "Settings" travels during the fold and Customize's morph, over the whole sheet.
struct HeaderFoldLayer: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        FoldTime { t in
            ZStack(alignment:.topLeading) {
                if let fold=studio.fold {
                    if fold.header { HeaderFoldTexts(studio:studio,fold:fold,t:t) }
                    if fold.studio { StudioMorph(studio:studio,fold:fold,t:t) }
                }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .allowsHitTesting(false)
            .onChange(of:t >= HeaderFold.total,initial:true) { _,over in
                if over,studio.fold?.count == studio.folds { studio.fold=nil }
            }
        }
        .foldClock(studio.folds)
    }
}
/// Text travelling between two places, `p` of the way: two crossfading layers at the same size on the design's curve.
/// The size steps by a 16th of a point, so fonts made on the way are reused.
struct TravellingText<Layer:View>: View {
    let from:CGRect
    let to:CGRect
    let p:Double
    let sizes:(CGFloat,CGFloat)
    let trackings:(CGFloat,CGFloat)
    @ViewBuilder let layer:(_ second:Bool,_ size:CGFloat,_ tracking:CGFloat)->Layer
    var body:some View {
        let e=Ease.out(p),k=Ease.linear(p,from:0.12,over:0.6)
        let size=(mix(sizes.0,sizes.1,e)*16).rounded()/16,tracking=mix(trackings.0,trackings.1,e)
        ZStack(alignment:.topLeading) {
            layer(false,size,tracking).fixedSize().frame(width:0,height:0,alignment:.leading).opacity(1-k)
            layer(true,size,tracking).fixedSize().frame(width:0,height:0,alignment:.leading).opacity(k)
        }
        .frame(width:0,height:0,alignment:.leading).position(x:mix(from.minX,to.minX,e),y:mix(from.midY,to.midY,e))
    }
}
/// "Settings" between the header and the breadcrumb, moving with the bar as the header shrinks.
struct HeaderFoldTexts: View {
    @Bindable var studio:DiscordStudio
    let fold:DiscordStudio.Fold
    let t:Double
    private struct Look { let size:CGFloat;let tracking:CGFloat;let weight:Int;let color:Color }
    /// As LauncherHeading draws it.
    private static let title=Look(size:28,tracking:-0.8,weight:700,color:.primary)
    private static let link=Look(size:12,tracking:0,weight:600,color:DiscordColors.link)
    var body:some View { text(L("Settings"),header:.title,Self.title,link:.settings) }
    @ViewBuilder private func text(_ words:String,header:HeaderFold.Text,_ look:Look,link:HeaderFold.Text)->some View {
        if let top=studio.foldFrames[header],let folded=studio.foldFrames[link] {
            let p=Ease.linear(t,over:HeaderFold.length),a=fold.opening ? look : Self.link,b=fold.opening ? Self.link : look
            // Opening, the breadcrumb comes up with the bar as the header shrinks; closing, it starts where it was.
            TravellingText(from:fold.opening ? top : folded,to:fold.opening ? folded.offsetBy(dx:0,dy:HeaderFold.chrome*(1-Ease.out(p))) : top,
                           p:p,sizes:(a.size,b.size),trackings:(a.tracking,b.tracking)) { second,size,tracking in
                let look=second ? b : a
                SwiftUI.Text(words).font(look.weight == 700 ? LauncherStyle.font(size,.bold) : Font(SystemFont.nsFont(size,look.weight)))
                    .tracking(tracking).foregroundStyle(look.color)
            }
        }
    }
}

/// Customize's morph (560 ms): its word travels to the card's title, taking its size, spacing and colour, hidden behind
/// the card where it crosses; the line under the word fades in last. Closing, the reverse.
struct StudioMorph: View {
    @Bindable var studio:DiscordStudio
    let fold:DiscordStudio.Fold
    let t:Double
    static let length=0.56
    private enum Look { case word,title }
    var body:some View {
        // Where its parts were as the fold started, with the moves since worked out on the fold's own clock.
        let frames=fold.frames
        if let word=frames[.customize],let title=frames[.cardTitle],let row=frames[.levelRow] {
            let p=Ease.linear(t,over:Self.length)
            // How far the layout still has to go: coming back, the word rides Discord's page as the stage grows.
            let left=1-Ease.out(t,over:HeaderFold.length),back=(studio.ride.page-22)*left
            let to=fold.opening ? title : word.offsetBy(dx:0,dy:back)
            let a:Look=fold.opening ? .word : .title,b:Look=fold.opening ? .title : .word
            let line=CGRect(x:word.minX,y:row.minY+30,width:word.width,height:3)
            // The word whitens on its way to the title's colour, so the two crossfade as one colour.
            let white=Self.whiten(fold.opening ? p : 1-p)
            ZStack(alignment:.topLeading) {
                TravellingText(from:fold.opening ? word : title,to:to,p:p,sizes:(size(a),size(b)),trackings:(tracking(a),tracking(b))) { second,size,tracking in
                    layer(second ? b : a,size:size,tracking:tracking,white:white)
                }
                // Hidden where the card is now, as it moves.
                .mask { BehindCard(card:studio.foldFrames[studio.screen == .home ? .shellHome : .shellEditor]).fill(style:FillStyle(eoFill:true)) }
                if fold.opening {
                    MorphFrame().frame(width:line.width,height:line.height).position(x:line.midX,y:line.midY)
                        .opacity(1-Ease.linear(p,from:0.74,over:0.26))
                } else {
                    let q=Ease.linear(p,from:0.74,over:0.26)
                    Underline(custom:true).frame(width:line.width,height:line.height).position(x:line.midX,y:line.midY+back).opacity(q*q*(3-2*q))
                }
            }
        }
    }
    /// How white the word is, `p` of the way to the title: 0.85 by a fifth (smoothly), then on to all of it.
    static func whiten(_ p:Double)->Double {
        let p=min(1,max(0,p))
        if p <= 0.2 { let x=p/0.2;return 0.85*x*x*(3-2*x) }
        return 0.85+0.15*(p-0.2)/0.8
    }
    private func size(_ look:Look)->CGFloat { look == .word ? 14 : 24 }
    private func tracking(_ look:Look)->CGFloat { look == .word ? 0 : -0.7 }
    /// A layer's text; the word keeps its ribbon.
    @ViewBuilder private func layer(_ look:Look,size:CGFloat,tracking:CGFloat,white:Double)->some View {
        let font=Font(SystemFont.nsFont(size,700))
        if look == .word {
            let words=DiscordPresenceLevel.custom.title
            SwiftUI.Text(words).font(font).tracking(tracking).foregroundStyle(.clear)
                .overlay { RibbonLine(rounded:false,still:fold.opening ? fold.at : nil).mask { SwiftUI.Text(words).font(font).tracking(tracking) } }
                .overlay { SwiftUI.Text(words).font(font).tracking(tracking).foregroundStyle(DiscordColors.body).opacity(white) }
        } else {
            SwiftUI.Text(fold.title).font(font).tracking(tracking).foregroundStyle(DiscordColors.body)
        }
    }
}
/// Everywhere but the card (filled even-odd): what passes behind it.
private struct BehindCard: Shape {
    let card:CGRect?
    func path(in rect:CGRect)->Path {
        var path=Path(rect)
        if let card { path.addRect(card) }
        return path
    }
}
/// The design's gradient frame (its ring ghost): a point and a half wide, amber through violet, glowing.
private struct MorphFrame: View {
    var body:some View {
        RoundedRectangle(cornerRadius:2).strokeBorder(LinearGradient(stops:DiscordColors.frame,startPoint:.leading,endPoint:.trailing),lineWidth:1.5)
            .shadow(color:Color.rgb(255,120,90).opacity(0.3),radius:5)
    }
}
