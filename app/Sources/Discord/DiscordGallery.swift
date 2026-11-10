import SwiftUI
import AppKit

// My cards: own and ready-made cards on the stage, the middle one playing, its neighbours peeking in; under it its name
// (click to rename), Use or Edit, Duplicate, Share, Delete, and adding a card from a code.

struct DiscordGallery: View {
    @Bindable var studio:DiscordStudio
    /// The design's carousel: each step slides the cards along over 0.62 s.
    static let slide=Animation.curve(.out,0.62)
    /// The card in the middle's place: over the caption (and the stage's border, a point at the bottom).
    static let caption:CGFloat=268+1
    /// How the card in the middle comes in: from a neighbour's place on a step or a delete, back where it was on Undo.
    static func cardArrival(_ move:DiscordStudio.GallerySlide?)->(start:ArrivalStart,animation:Animation)? {
        guard let move,move.moving else { return nil }
        if move.kind == .restore { return (ArrivalStart(opacity:0,scale:0.9),slide) }
        return (ArrivalStart(x:move.way*277,opacity:0.9,scale:0.6/0.86),slide)
    }
    var body:some View {
        // Inside the stage's one-point border, as the design's are.
        VStack(spacing:0) {
            GalleryCards(studio:studio).frame(height:548-2-34-268)
            GalleryCaption(studio:studio).frame(height:268)
        }
        .padding(.vertical,1)
        .focusable().focusEffectDisabled()
        .onKeyPress(.leftArrow) { studio.galleryStep(-1);return .handled }
        .onKeyPress(.rightArrow) { studio.galleryStep(1);return .handled }
        .onExitCommand { studio.openGallery(false) }
    }
}

/// The neighbours at the sides of the card in the middle (CardStage's own card, shrunk into its place), and the arrows.
private struct GalleryCards: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let items=studio.galleryItems,place=studio.galleryPlace
        TimelineView(.seconds) { context in
            ZStack {
                if place > 0 { neighbour(items[place-1],now:context.date,leading:true) }
                if place < items.count-1 { neighbour(items[place+1],now:context.date,leading:false) }
                HStack {
                    arrow("lucide:chevron-left",name:L("Previous card"),enabled:place > 0) { studio.galleryStep(-1) }
                    Spacer()
                    arrow("lucide:chevron-right",name:L("Next card"),enabled:place < items.count-1) { studio.galleryStep(1) }
                }
                // Eight points inside the stage's border, and a point under the middle.
                .padding(.horizontal,9).offset(y:1)
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    /// A neighbour, smaller and to the side: a click shows it.
    private func neighbour(_ item:DiscordStudio.GalleryItem,now:Date,leading:Bool)->some View {
        let activity=studio.galleryActivity(item,at:now)
        return Button { studio.galleryStep(leading ? -1 : 1) } label: {
            VStack(spacing:0) { DiscordCardView(activity:activity,now:now) }
                .padding(10).frame(width:300)
                .background(DiscordColors.popout,in:RoundedRectangle(cornerRadius:10))
                .compositingGroup().shadow(color:.black.opacity(0.45),radius:16,y:12)
        }
        .buttonStyle(NeighbourStyle())
        .scaleEffect(0.74,anchor:leading ? .trailing : .leading)
        .frame(width:300)
        .modifier(PartArrival(trigger:studio.gallerySlide?.id,neighbourArrival(leading:leading)))
        .offset(x:leading ? -(166+150) : 166+150)
        .accessibilityLabel(leading ? L("Previous card") : L("Next card"))
        .transition(.identity)
    }
    /// A neighbour fades in as My cards opens. On a step, one side's was the middle card and shrinks there; the other
    /// comes from further out. Delete and Undo slide cards the same way.
    private func neighbourArrival(leading:Bool)->(start:ArrivalStart,animation:Animation)? {
        guard let slide=studio.gallerySlide,slide.moving else { return (ArrivalStart(opacity:0),Animation.curve(.css,0.5).delay(0.1)) }
        let way=slide.way
        let anchor:UnitPoint=leading ? .trailing : .leading
        if slide.kind != .step && leading { return nil }
        if (way > 0) == leading || slide.kind == .restore { return (ArrivalStart(x:way*326,scale:1.066/0.74,anchor:anchor),DiscordGallery.slide) }
        return (ArrivalStart(x:way*150,opacity:0,scale:0.6/0.74,anchor:anchor),DiscordGallery.slide)
    }
    /// Lighter and larger than the design's, with an edge (hard to see over the cards), lighter still when pointed at.
    private func arrow(_ icon:String,name:String,enabled:Bool,_ action:@escaping ()->Void)->some View {
        Button(action:action) { EmptyView() }
            .buttonStyle(GalleryArrowStyle(icon:icon)).opacity(enabled ? 1 : 0).allowsHitTesting(enabled).accessibilityLabel(name)
            .animation(.easeOut(duration:0.25),value:enabled)
    }
}
private struct GalleryArrowStyle: ButtonStyle {
    let icon:String
    @State private var inside=false
    func makeBody(configuration:Configuration)->some View {
        DesignIcon(icon,size:18).foregroundStyle(.white)
            .frame(width:34,height:34)
            .background(inside ? Color.rgb(82,85,95) : Color.rgb(58,60,67).opacity(0.92),in:Circle())
            .overlay { Circle().strokeBorder(.white.opacity(inside ? 0.24 : 0.16),lineWidth:1) }
            .compositingGroup().shadow(color:.black.opacity(0.45),radius:8,y:4).contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration:0.2),value:inside)
            .onHover { inside=$0 }
    }
}
private struct NeighbourStyle: ButtonStyle {
    @State private var inside=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.brightness(inside ? 0.06 : 0).onHover { inside=$0 }
    }
}

/// Under the cards: the name, what it shows, what can be done with it, the dots, and adding a card from a code.
private struct GalleryCaption: View {
    @Bindable var studio:DiscordStudio
    @FocusState private var renameFocused:Bool
    @FocusState private var importFocused:Bool
    var body:some View {
        let items=studio.galleryItems,place=studio.galleryPlace
        VStack(spacing:8) {
            if let item=studio.galleryItem {
                HStack(spacing:8) {
                    if studio.renaming == item.design.id {
                        TextField("",text:$studio.renameDraft)
                            .textFieldStyle(.plain).font(LauncherStyle.font(18,.bold)).multilineTextAlignment(.center)
                            .frame(width:190,height:28).overlay(alignment:.bottom) { Rectangle().fill(DiscordColors.fill).frame(height:2) }
                            .focused($renameFocused).onAppear { renameFocused=true }
                            .onSubmit { studio.finishRename() }.onExitCommand { studio.renaming=nil }
                            .onChange(of:renameFocused) { _,focused in if !focused { studio.finishRename() } }
                            .onChange(of:studio.renameDraft) { _,draft in if draft.count > 24 { studio.renameDraft=String(draft.prefix(24)) } }
                    } else {
                        NameButton(name:item.name,renamable:!item.readyMade) { studio.startRename(item) }
                    }
                    if item.design.id == studio.shelf.inUse.id {
                        tag(L("In use on Discord"),icon:"rc:check-fill",back:DiscordColors.accent.opacity(0.16),fore:DiscordColors.chosen)
                    }
                    if item.readyMade { tag(L("System"),icon:nil,back:.white.opacity(0.08),fore:DiscordColors.ink(0.62)) }
                }.frame(height:30)
                // The design balances its lines (text-wrap: balance).
                let description=studio.galleryDescription(item)
                Text(description).designFont(12,line:12*1.45).foregroundStyle(DiscordColors.ink(0.62))
                    .multilineTextAlignment(.center).frame(width:DesignText.balanced(description,SystemFont.nsFont(12),within:390)).frame(minHeight:34,alignment:.top)
                    .fixedSize(horizontal:false,vertical:true)
                HStack(spacing:6) {
                    let inUse=item.design.id == studio.shelf.inUse.id
                    MainButton(title:inUse ? L("Edit this card") : L("Use this card"),icon:inUse ? "lucide:pencil" : "lucide:check") {
                        if inUse { studio.openGallery(false) } else { studio.use(item) }
                    }
                    ActButton(icon:"lucide:copy",tip:L("Duplicate")) { studio.duplicate(item) }
                    ActButton(icon:"lucide:share-2",tip:L("Share as a code"),on:studio.sharing) {
                        studio.finishRename();studio.sharing.toggle();studio.importing=false;studio.copied=false
                    }
                    if let undo=studio.deleteUndo { UndoDeleteButton(studio:studio,undo:undo).transition(.identity) }
                    else { ActButton(icon:"lucide:trash-2",tip:studio.canDelete(item) ? L("Delete") : L("Your only card can’t be deleted"),enabled:studio.canDelete(item)) { studio.delete(item) } }
                }
                if studio.sharing { SharePanel(studio:studio,code:studio.code(item)).popIn(0.3).transition(.identity) }
            }
            if studio.importing { importPanel.popIn(0.3).transition(.identity) }
            Spacer(minLength:0)
            HStack(spacing:0) {
                let mine=studio.shelf.mine.count
                ForEach(Array(items.enumerated()),id:\.offset) { index,item in
                    Button { studio.galleryStep(index-place) } label: {
                        Capsule().fill(index == place ? DiscordColors.accent : .white.opacity(0.22)).frame(width:index == place ? 18 : 6,height:6)
                            .padding(.vertical,4).padding(.horizontal,2.5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.leading,index == mine && index > 0 ? 10 : 0)
                    .designTip(item.name).accessibilityLabel(item.name)
                }
            }.frame(height:14).animation(.curve(.out,0.35),value:place)
            HStack(spacing:12) {
                Text(L("{0} of {1}",String(place+1),String(items.count))).designFont(11).monospacedDigit()
                if studio.hiddenCount > 0 {
                    smallButton(studio.hiddenCount == 1 ? L("Bring back 1 system card") : L("Bring back {0} system cards",String(studio.hiddenCount)),icon:"lucide:rotate-ccw",color:DiscordColors.ink(0.6)) { studio.bringBack() }
                }
                smallButton(studio.importing ? L("Cancel") : L("Add from a code"),icon:"lucide:clipboard-paste",color:DiscordColors.link) {
                    studio.finishRename();studio.importing.toggle();studio.sharing=false;studio.importDraft="";studio.importFailed=false
                }
            }.foregroundStyle(DiscordColors.ink(0.42)).frame(height:16)
        }
        .padding(.top,2).padding(.horizontal,20).padding(.bottom,14)
        .animation(.curve(.out,0.3),value:studio.sharing)
        .animation(.curve(.out,0.3),value:studio.importing)
        // As My cards opens; and on a step, in from the side the cards come from.
        .fadeIn(0.32,delay:0.2)
        .modifier(PartArrival(trigger:studio.gallerySlide?.id,studio.gallerySlide.flatMap { $0.moving ? (ArrivalStart(x:$0.way*26,opacity:0),Animation.curve(.out,0.44)) : nil },onAppear:false))
    }
    private func tag(_ text:String,icon:String?,back:Color,fore:Color)->some View {
        HStack(spacing:4) { if let icon { DesignIcon(icon,size:13) };Text(text).designFont(11,.bold) }
            .foregroundStyle(fore)
            .padding(.leading,icon == nil ? 8 : 6).padding(.trailing,8).frame(height:22)
            .background(back,in:RoundedRectangle(cornerRadius:7)).fixedSize()
    }
    private func smallButton(_ title:String,icon:String,color:Color,_ action:@escaping ()->Void)->some View {
        Button(action:action) { HStack(spacing:4) { DesignIcon(icon,size:11);Text(title).designFont(11,.semibold) }.foregroundStyle(color) }
            .buttonStyle(.plain)
    }
    private var importPanel:some View {
        VStack(spacing:5) {
            HStack(spacing:8) {
                DesignIcon("lucide:clipboard-paste",size:13).foregroundStyle(DiscordColors.link)
                TextField(L("Paste a code"),text:$studio.importDraft)
                    .textFieldStyle(.plain).font(.system(size:15,weight:.bold,design:.monospaced)).multilineTextAlignment(.center)
                    .focused($importFocused).onAppear { importFocused=true }
                    .onSubmit { studio.importCode() }.onExitCommand { studio.importing=false }
                    .onChange(of:studio.importDraft) { _,draft in
                        studio.importFailed=false
                        let upper=draft.uppercased();if upper != draft { studio.importDraft=upper }
                    }
                FillButton(title:L("Add"),height:26,size:12,radius:7,padding:11,weight:.bold) { studio.importCode() }
            }
            .padding(.leading,11).padding(.trailing,4).frame(width:340,height:38)
            .background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            .overlay { if studio.importFailed { RoundedRectangle(cornerRadius:10).strokeBorder(DiscordColors.warning.opacity(0.7),lineWidth:1.5) } }
            Text(studio.importNewer ? L("A newer Recall made this card. Update Recall to add it.") : studio.importFailed ? L("No card has that code.") : L("Paste someone’s code to add their card."))
                .designFont(11).foregroundStyle(studio.importFailed ? Color.rgb(255,130,120) : DiscordColors.ink(0.45))
        }
    }
}
/// The card's name: a click renames one of yours (a dashed line under it says so).
private struct NameButton: View {
    let name:String
    let renamable:Bool
    let action:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:action) {
            Text(name).designFont(18,.bold).tracking(-0.3).foregroundStyle(.white).lineLimit(1)
                .overlay(alignment:.bottom) {
                    Rectangle().stroke(style:StrokeStyle(lineWidth:1.5,dash:[4,3])).frame(height:0.1).offset(y:6)
                        .foregroundStyle(DiscordColors.ink(inside && renamable ? 0.5 : 0))
                }
                .padding(.horizontal,2).frame(height:30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).allowsHitTesting(renamable).onHover { inside=$0 }
        .designTip(renamable ? L("Click to rename") : nil)
        .animation(.easeOut(duration:0.2),value:inside)
    }
}
private struct MainButton: View {
    let title:String
    let icon:String
    let action:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:action) {
            HStack(spacing:6) { DesignIcon(icon,size:13);Text(title).designFont(12.5,.bold) }
                .foregroundStyle(.white)
                .padding(.leading,13).padding(.trailing,16).frame(height:32)
                .background(inside ? DiscordColors.fillHover : DiscordColors.fill,in:RoundedRectangle(cornerRadius:9))
                .compositingGroup().shadow(color:DiscordColors.pick.opacity(0.28),radius:9,y:6).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside=$0 }
    }
}
private struct ActButton: View {
    let icon:String
    let tip:String
    var on=false
    var enabled=true
    let action:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:action) {
            DesignIcon(icon,size:14)
                .foregroundStyle(on ? DiscordColors.chosen : inside && enabled ? .white : DiscordColors.ink(0.75))
                .frame(width:32,height:32)
                .background(on ? DiscordColors.accent.opacity(0.2) : .white.opacity(inside && enabled ? 0.12 : 0.06),in:RoundedRectangle(cornerRadius:9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35).onHover { inside=$0 }
        .designTip(tip).accessibilityLabel(tip)
    }
}
/// Delete: the bin shakes and goes red, then turns into Undo, a ring running down the seconds; when they run out it
/// spins faster and goes in a puff.
private struct UndoDeleteButton: View {
    @Bindable var studio:DiscordStudio
    let undo:DiscordStudio.DeleteUndo
    @State private var turned=false
    @State private var shakes=0
    var body:some View {
        let red=DiscordColors.warning,blue=DiscordColors.inMatch,tint=turned ? blue : red
        TimelineView(.animation(paused:undo.leaving == nil && !turned)) { context in
            let left=max(0,undo.until.timeIntervalSince(context.date)),window=DiscordStudio.DeleteUndo.window
            let gone=undo.leaving.map { Ease.linear(context.date.timeIntervalSince($0),over:DiscordStudio.DeleteUndo.spin) } ?? 0
            Button { studio.undoDelete() } label: {
                ZStack {
                    DesignIcon("lucide:trash-2",size:14).opacity(turned ? 0 : 1)
                    // Run out, the arrow winds back up (a fifth of the spin) so it's seen whirling before the puff.
                    UndoRing(left:undo.leaving == nil ? left/window : min(0.8,gone*4),seconds:undo.leaving == nil ? max(1,Int(left.rounded(.up))) : 0)
                        .opacity(turned ? 1 : 0).modifier(SpinAway(gone:gone))
                }
                .foregroundStyle(tint)
                .frame(width:32,height:32)
                .background(tint.opacity(0.2*(1-max(0,gone-0.6)/0.4)),in:RoundedRectangle(cornerRadius:9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).allowsHitTesting(undo.leaving == nil).accessibilityLabel(L("Undo"))
        }
        .keyframeAnimator(initialValue:0.0,trigger:shakes) { view,x in view.offset(x:x) } keyframes:{ _ in
            LinearKeyframe(-3.0,duration:0.06);LinearKeyframe(3.0,duration:0.07);LinearKeyframe(-2.5,duration:0.07)
            LinearKeyframe(2.0,duration:0.07);LinearKeyframe(0.0,duration:0.08)
        }
        // Its bubble, in the tooltips' style, its foot six points over the button; it goes as Undo spins away.
        .overlay(alignment:.top) {
            Text(undo.text).designFont(11.5,.medium).foregroundStyle(DiscordColors.ink(0.92)).fixedSize()
                .padding(.horizontal,9).padding(.vertical,6)
                .background(Color.rgb(17,18,20).opacity(0.95),in:RoundedRectangle(cornerRadius:8))
                .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(.white.opacity(0.07),lineWidth:1) }
                .compositingGroup().shadow(color:.black.opacity(0.5),radius:14,y:10)
                .alignmentGuide(.top) { $0[.bottom]+6 }
                .popIn(0.3).allowsHitTesting(false)
                .opacity(undo.leaving == nil ? 1 : 0).animation(.easeOut(duration:0.25),value:undo.leaving == nil)
        }
        // Red, then blue after the shake, by its own animation (see PartArrival).
        .animation(.easeInOut(duration:0.3).delay(0.4),value:turned)
        .onAppear { shakes+=1;turned=true }
    }
}
/// Undo's countdown: a ring running down anticlockwise, the seconds in its middle.
private struct UndoRing: View {
    /// The share of the seconds left, 1 to 0; and the seconds (none once they've run out).
    let left:Double
    let seconds:Int
    var body:some View {
        ZStack {
            Ring(done:left,track:.white.opacity(0.1),fill:AnyShapeStyle(.foreground))
            if left > 0.02 {
                Arrowhead().frame(width:6,height:6).offset(y:-9).rotationEffect(.degrees(360*left))
            }
            if seconds > 0 { Text(verbatim:"\(seconds)").designFont(10,.heavy).monospacedDigit() }
        }
        .frame(width:18,height:18)
    }
}
/// A small triangle pointing left (anticlockwise, at the top of the ring).
private struct Arrowhead: Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        path.move(to:CGPoint(x:rect.minX,y:rect.midY));path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY));path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
        path.closeSubpath()
        return path
    }
}
/// Undo going, `gone` 0 to 1: spinning back ever faster and smaller, then a puff (a ring and six specks) as it fades.
private struct SpinAway: ViewModifier {
    let gone:Double
    func body(content:Content)->some View {
        let puff=max(0,(gone-0.62)/0.38)
        content
            .rotationEffect(.degrees(-1080*gone*gone*gone))
            .scaleEffect(1-0.5*gone*gone)
            .opacity(1-puff).blur(radius:3*puff)
            .overlay {
                if puff > 0 {
                    ZStack {
                        Circle().stroke(.white.opacity(0.55*(1-puff)),lineWidth:1.5).frame(width:10+22*puff,height:10+22*puff)
                        ForEach(0..<6,id:\.self) { index in
                            Circle().fill(.white.opacity(0.8*(1-puff))).frame(width:3-1.5*puff,height:3-1.5*puff)
                                .offset(y:-(6+12*puff)).rotationEffect(.degrees(Double(index)*60+20))
                        }
                    }.allowsHitTesting(false)
                }
            }
    }
}
/// The card's code, to copy and send: everything chosen travels in it, nothing else.
private struct SharePanel: View {
    @Bindable var studio:DiscordStudio
    let code:String
    var body:some View {
        VStack(spacing:5) {
            HStack(spacing:8) {
                DesignIcon("lucide:share-2",size:13).foregroundStyle(DiscordColors.link)
                Text(verbatim:code).font(.system(size:code.count > 30 ? 13 : 16,weight:.bold,design:.monospaced)).tracking(code.count > 30 ? 0.3 : 1.5)
                    .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3).textSelection(.enabled)
                    .frame(maxWidth:.infinity).padding(.vertical,6)
                FillButton(title:studio.copied ? L("Copied") : L("Copy"),height:26,size:12,radius:7,padding:11,weight:.bold) {
                    NSPasteboard.general.clearContents();NSPasteboard.general.setString(code,forType:.string);studio.copied=true
                }
            }
            .padding(.leading,11).padding(.trailing,4).frame(minHeight:38).frame(maxWidth:code.count > 12 ? 420 : 230)
            .background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            Text(L("Only your choices and the card’s name travel: no stats, no BattleTag.")).designFont(11).foregroundStyle(DiscordColors.ink(0.45))
        }
    }
}

extension DiscordStudio {
    /// What takes turns on the gallery's card, pinned to its parts.
    var galleryPins:CardPins {
        let card=shown
        return CardPins(picture:card.pictures?.count ?? card.lineTwo.count,badge:card.badges.count,lineOne:card.lineOne.count,lineTwo:card.lineTwo.count)
    }
    /// A gallery card at its first turn (the neighbours).
    func galleryActivity(_ item:GalleryItem,at now:Date)->[String:Any] { item.design.activity(inputs(at:now),turn:0) }
}
