import SwiftUI

// Customize's panels, one per part (the design's "slots"). A click uses only that choice, a hold adds or removes it,
// and pointing shows it on the card first.

struct EditorPanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            switch studio.slot {
            case .lineTwo: LineTwoPanel(studio:studio)
            case .picture: PicturePanel(studio:studio)
            case .badge: BadgePanel(studio:studio)
            case .lineOne: LineOnePanel(studio:studio)
            case .timer: TimerPanel(studio:studio)
            case .buttons: ButtonsPanel(studio:studio)
            case .party: PartyPanel(studio:studio)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// When the profile can't be read: why, where to fix it, and the example data, in one row.
struct ProfileNotice: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let hidden=studio.profileState == .hidden,none=studio.battleTag.isEmpty,missing=studio.profileState == .missing
        HStack(spacing:8) {
            DesignIcon(hidden ? "lucide:lock" : "simple-icons:battledotnet",size:13).foregroundStyle(DiscordColors.warning.opacity(0.85))
            Text(hidden ? L("Private profile") : none ? L("Needs your BattleTag") : missing ? L("No profile with this BattleTag") : L("Not found yet")).designFont(12,.semibold).foregroundStyle(DiscordColors.ink(0.75)).lineLimit(1)
            LinkButton(title:hidden ? L("Make public") : none ? L("Add") : L("Your profile")) { studio.openProfile() }
            Spacer(minLength:6)
            Button { studio.example.toggle();studio.preview=nil } label: {
                HStack(spacing:5) { DesignIcon(studio.example ? "lucide:circle-dot" : "lucide:circle",size:12);Text(L("Example")).designFont(12,.semibold) }
                    .foregroundStyle(studio.example ? DiscordColors.bright : DiscordColors.ink(0.6)).contentShape(Rectangle())
            }
            .buttonStyle(.plain).designTip(L("Preview with example data")).accessibilityLabel(L("Preview with example data"))
        }
        .padding(.leading,11).padding(.trailing,10).frame(height:34)
        .background(DiscordColors.veil(0.04),in:RoundedRectangle(cornerRadius:10))
        .padding(.top,8)
    }
}

// MARK: Line 2

struct LineTwoPanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let inputs=studio.inputs(at:Date()),voice=inputs.voice != nil && studio.design.party == .sayVoice
        VStack(alignment:.leading,spacing:0) {
            PanelHeading(studio:studio,title:L("Line 2"),subtitle:voice ? L("In group voice, Discord’s count takes this line. The lines come back when you leave voice.")
                                                                          : L("The second line under Overwatch. The lines in the list take turns, in this order."),turns:studio.design.lineTwo.count > 1)
            if studio.profileState != .shown { ProfileNotice(studio:studio) }
            LineTwoList(studio:studio,voice:voice).padding(.top,8)
            let open=studio.openLine.flatMap { studio.design.lineTwo.indices.contains($0) ? $0 : nil }
            RuleHeading(text:open.map { L("Change line {0}",String($0+1)) } ?? L("Add a line")) {
                if open != nil { LinkButton(title:L("Done"),size:11.5) { studio.closeLine() } }
            }
            // Right under the heading: the design's margins there collapse into the heading's own four points.
            TopicTiles(studio:studio)
            HStack(alignment:.top,spacing:8) {
                Circle().fill(studio.topic.color).frame(width:6,height:6).padding(.top,6)
                Text(studio.topic.about).designFont(11.5,line:11.5*1.45,wraps:true).foregroundStyle(DiscordColors.ink(0.6)).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,minHeight:34,alignment:.topLeading).padding(.horizontal,2).padding(.top,9)
            switch studio.topic {
            case .hero: HeroPicker(studio:studio).padding(.top,8)
            case .rank: RankTiles(studio:studio).padding(.top,8)
            case .record: RecordOptions(studio:studio).padding(.top,8)
            case .highlights: DynamicOrder(studio:studio).padding(.top,10)
            default: EmptyView()
            }
            if let open,studio.design.lineTwo[open].piece != .highlights { SecondPiece(studio:studio,index:open).padding(.top,10) }
            LineCatalog(studio:studio).padding(.top,4)
            if let note=studio.topicNote {
                Text(note).designFont(11.5,line:11.5*1.45,wraps:true).foregroundStyle(DiscordColors.ink(0.42)).fixedSize(horizontal:false,vertical:true)
                    .padding(.horizontal,2).padding(.top,6)
            }
        }
    }
}

/// The card's lines: the one showing glows; a click opens one; drag to reorder.
struct LineTwoList: View {
    @Bindable var studio:DiscordStudio
    let voice:Bool
    @Namespace private var glide
    @State private var dragging:Int?
    var body:some View {
        TimelineView(.seconds) { context in
            let inputs=studio.inputs(at:context.date),design=studio.design
            let shown=DiscordCardDesign.Shown(design,inputs,turn:studio.turn(at:context.date))
            let current=shown.lineTwo.isEmpty || voice ? nil : shown.lineTwo[studio.turn(at:context.date)%shown.lineTwo.count].piece
            PanelBox {
                ForEach(Array(design.lineTwo.enumerated()),id:\.offset) { index,line in
                    let avail=studio.availability(line.piece,inputs),text=studio.lineText(line,inputs)
                    let live=design.lineTwo.count > 1 && line.piece == current && design.lineTwo.firstIndex { $0.piece == current } == index
                    let selected=studio.openLine == index
                    ListRow(number:index+1,text:text,sub:studio.explain(line),matchesToo:line.piece.safeInMatch ? inputs.inMatch : nil,
                            note:avail == .ok || avail == .match || (line.piece.topic == .moment && avail == .news) ? nil : studio.note(avail),
                            live:live,turnDone:studio.turnDone(at:context.date),selected:selected,available:avail == .ok || avail == .news,
                            removable:design.lineTwo.count > 1 || line.piece != .highlights,remove:{ studio.removeLine(index,line) }) {
                        if case .hero(let key,_)=line.piece,let portrait=studio.portrait(key ?? inputs.topHeroes.first,inputs) {
                            RemoteImage(url:portrait) { DiscordColors.tile }.frame(width:24,height:24).clipShape(Circle())
                        } else { RowIcon(icon:line.piece.topic.icon) }
                    }
                    .background { if selected { RoundedRectangle(cornerRadius:9).fill(DiscordColors.veil(0.075)).matchedGeometryEffect(id:"open",in:glide) } }
                    .onTapGesture { withAnimation(.curve(.out,0.35)) { studio.openLineToggle(index,shown:shown) } }
                    .reorderable("line",index:index,dragging:$dragging,tick:context.date,move:{ studio.moveLine(from:$0,to:$1) }) {
                        Text(verbatim:text).discordFont(14).padding(8)
                    }
                }
                if design.lineTwo.count == 1 && !voice {
                    HoldHint(text:L("Hold a line below to add it. They take turns.")).padding(EdgeInsets(top:7,leading:12,bottom:5,trailing:10)).transition(.identity)
                }
            }
        }
    }
}

/// Line 2's topics; a number on a tile counts the card's lines from it.
struct TopicTiles: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:5),count:4),spacing:5) {
            ForEach(DiscordStudio.Topic.allCases,id:\.self) { topic in
                TopicTile(topic:topic,on:studio.topic == topic,count:studio.design.lineTwo.filter { $0.piece.topic == topic }.count) { studio.topic=topic }
            }
        }
    }
}
private struct TopicTile: View {
    let topic:DiscordStudio.Topic
    let on:Bool
    let count:Int
    let choose:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:choose) {
            VStack(spacing:5) {
                Group {
                    if topic == .moment { Ping(color:topic.color,size:9) } else { DesignIcon(topic.icon,size:14).foregroundStyle(topic.color) }
                }
                .frame(width:26,height:26).background(topic.color.opacity(on ? 0.24 : 0.13),in:RoundedRectangle(cornerRadius:8))
                Text(topic.name).designFont(11,.semibold).lineLimit(1)
            }
            .foregroundStyle(on || inside ? DiscordColors.bright : DiscordColors.ink(0.72))
            .frame(maxWidth:.infinity).frame(height:58)
            .background(on ? topic.color.opacity(0.13) : DiscordColors.veil(0.035),in:RoundedRectangle(cornerRadius:11))
            .overlay { if on { RoundedRectangle(cornerRadius:11).strokeBorder(topic.color.opacity(0.65),lineWidth:1.5) } }
            .overlay(alignment:.topTrailing) {
                if count > 0 {
                    Text("\(count)").designFont(9.5,.heavy).foregroundStyle(DiscordColors.onAccent)
                        .padding(.horizontal,4).frame(minWidth:15,minHeight:15).background(DiscordColors.accent,in:Capsule()).padding(5)
                        .popIn(0.3).transition(.identity)
                }
            }
            .brightness(inside ? 0.08 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { inside=$0 }.accessibilityLabel(topic.name).accessibilityAddTraits(on ? .isSelected : [])
        .animation(.easeOut(duration:0.2),value:on)
    }
}
/// A dot sending out a ring now and then (the design's dcPing, every 2.2 s).
struct Ping: View {
    let color:Color
    var size:CGFloat=7
    var body:some View {
        ZStack {
            Circle().fill(color)
                .keyframeAnimator(initialValue:0.0,repeating:true) { ring,out in ring.scaleEffect(1+1.5*out).opacity(0.75*(1-out)) } keyframes:{ _ in
                    LinearKeyframe(1.0,duration:1.65,timingCurve:.bezier(startControlPoint:UnitPoint(x:0,y:0),endControlPoint:UnitPoint(x:0.2,y:1)))
                    LinearKeyframe(1.0,duration:0.55)
                }
            Circle().fill(color)
        }
        .frame(width:size,height:size)
    }
}

/// The heroes by time played, most first; "Show more heroes". The chosen hero's time below (or the one pointed at).
struct HeroPicker: View {
    @Bindable var studio:DiscordStudio
    @State private var caption:String?
    var body:some View {
        let inputs=studio.sampleInputs(at:Date()),all=studio.heroOrder(inputs),shown=studio.allHeroes ? all : Array(all.prefix(10))
        let chosen=studio.hero ?? all.first
        VStack(alignment:.leading,spacing:0) {
            FlowLayout(spacing:6) {
                ForEach(shown,id:\.self) { key in
                    let on=key == chosen
                    Button { studio.chooseHero(key == all.first ? nil : key) } label: {
                        RemoteImage(url:inputs.profile?.heroes[key]?.portrait) { DiscordColors.tile }
                            .frame(width:28,height:28).background(DiscordColors.tile).clipShape(Circle())
                            .overlay { if on { Circle().strokeBorder(DiscordColors.accent,lineWidth:2).padding(-2) } }
                            .opacity(on ? 1 : 0.72).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(inputs.heroName(key))
                    .onHover { inside in caption=inside ? studio.heroCaption(key,inputs) : nil }
                }
                if all.count > 10 {
                    Button(studio.allHeroes ? L("Fewer heroes") : L("Show more heroes")) { withAnimation(.snappy) { studio.allHeroes.toggle() } }
                        .buttonStyle(.plain).designFont(11.5,.semibold).foregroundStyle(DiscordColors.ink(0.55)).frame(height:28).padding(.horizontal,4)
                }
            }
            Text(caption ?? chosen.map { studio.heroCaption($0,inputs) } ?? L("No heroes yet"))
                .designFont(11.5).foregroundStyle(DiscordColors.ink(0.55)).frame(height:17,alignment:.bottom).padding(.top,3)
        }
    }
}

/// The record's modes and its win rate; an open record line changes with them.
struct RecordOptions: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        HStack(alignment:.top,spacing:10) {
            Text(L("Mode")).designFont(11.5).foregroundStyle(DiscordColors.ink(0.45)).frame(width:44,alignment:.leading).padding(.top,8)
            FlowLayout(spacing:10,lineSpacing:4) {
                WordPicker(choices:[(RecordMode.competitive,L("Competitive")),(.quickPlay,L("Quick Play")),(.both,L("Both"))],chosen:studio.mode) { studio.setRecord(mode:$0,winRate:studio.winRate) }
                DesignSwitch(label:L("Win rate"),on:studio.winRate) { studio.setRecord(mode:studio.mode,winRate:!studio.winRate) }
            }
        }
    }
}

/// Dynamic's order, each with what it would say, the one that applies marked.
struct DynamicOrder: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let inputs=studio.inputs(at:Date()),steps=studio.highlightSteps(inputs)
        let now=inputs.inMatch ? nil : steps.firstIndex { $0.applies }
        VStack(spacing:1) {
            ForEach(Array(steps.enumerated()),id:\.offset) { index,step in
                let on=index == now
                HStack(spacing:10) {
                    Text(verbatim:"\(index+1)").designFont(11,.bold).monospacedDigit().foregroundStyle(DiscordColors.ink(on ? 0.85 : 0.35)).frame(width:12)
                    DesignIcon(step.icon,size:13).foregroundStyle(step.color.opacity(on ? 1 : 0.6)).frame(width:16)
                    VStack(alignment:.leading,spacing:1) {
                        Text(step.when).designFont(11).foregroundStyle(DiscordColors.ink(0.5)).lineLimit(1)
                        Text(verbatim:step.text).discordFont(13).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.65)).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if on {
                        Text(L("Now")).designFont(10.5,.bold).foregroundStyle(DiscordColors.glow)
                            .padding(.horizontal,7).frame(height:18).background(DiscordColors.accent.opacity(0.16),in:RoundedRectangle(cornerRadius:6))
                            .popIn(0.3).transition(.identity)
                    }
                }
                .padding(.horizontal,10).frame(height:42)
                .background(on ? DiscordColors.accent.opacity(0.08) : .clear,in:RoundedRectangle(cornerRadius:9))
            }
        }
        .padding(4).background(DiscordColors.veil(0.03),in:RoundedRectangle(cornerRadius:12))
    }
}

/// "A second piece after it": what can follow the open line, as long as the line stays short enough to read.
struct SecondPiece: View {
    @Bindable var studio:DiscordStudio
    let index:Int
    var body:some View {
        let inputs=studio.sampleInputs(at:Date()),line=studio.design.lineTwo[index]
        let main=line.piece.text(inputs,rank:studio.design.rank) ?? line.piece.label
        let seconds=studio.seconds(for:line.piece,main:main,inputs:inputs)
        if !seconds.isEmpty || line.second != nil {
            VStack(alignment:.leading,spacing:5) {
                Text(L("A second piece after it")).designFont(11.5,.semibold).foregroundStyle(DiscordColors.ink(0.5)).padding(.leading,2)
                VStack(spacing:1) {
                    row(nil,pre:"",text:L("{0}, nothing else",main),on:line.second == nil)
                    ForEach(seconds,id:\.piece) { second in row(second.piece,pre:main+" · ",text:second.text,on:line.second == second.piece) }
                }.padding(4).background(DiscordColors.veil(0.03),in:RoundedRectangle(cornerRadius:12))
            }
        }
    }
    private func row(_ piece:CardPiece?,pre:String,text:String,on:Bool)->some View {
        Button { if !on { studio.setSecond(piece,line:index) } } label: {
            HStack(spacing:10) {
                Circle().strokeBorder(on ? DiscordColors.accent : DiscordColors.veil(0.25),lineWidth:1.5)
                    .overlay { if on { Circle().fill(DiscordColors.accent).frame(width:6,height:6) } }.frame(width:14,height:14)
                Text(verbatim:pre).foregroundStyle(DiscordColors.ink(0.42)).followed(by:Text(verbatim:text).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.75)))
                    .discordFont(13).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
            }
            .padding(.horizontal,10).frame(height:32)
            .background(on ? DiscordColors.veil(0.06) : .clear,in:RoundedRectangle(cornerRadius:8))
            .rowHover(8,veil:0.05).contentShape(Rectangle())
        }.buttonStyle(.plain).pointing(studio) { $0.lineTwo[index].second=piece }
    }
}

/// The lines the topic offers, as they'd read on the card: click to use only that one, hold to add it.
struct LineCatalog: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let inputs=studio.inputs(at:Date()),sample=studio.sampleInputs(at:Date())
        VStack(spacing:1) {
            ForEach(studio.topic.catalog(hero:studio.hero,mode:studio.mode,winRate:studio.winRate),id:\.self) { piece in
                CatalogRow(studio:studio,piece:piece,inputs:inputs,sample:sample)
            }
        }
    }
}
struct CatalogRow: View {
    @Bindable var studio:DiscordStudio
    let piece:CardPiece
    let inputs:CardInputs
    let sample:CardInputs
    var body:some View {
        let row=CatalogRowState(studio:studio,piece:piece,inputs:inputs,sample:sample)
        HStack(spacing:9) {
            CatalogRowText(row:row).frame(maxWidth:.infinity,alignment:.leading)
            if let note=row.note { NoteMark(note:note) }
            TrailingMark(number:row.number,icon:row.icon,filled:row.filled,dim:row.bar && !row.ready || row.blocked,pulse:row.ready)
        }
        .foregroundStyle(row.current || row.on ? DiscordColors.bright : row.bar && !row.ready || row.blocked ? DiscordColors.ink(0.5) : DiscordColors.ink(0.78))
        .padding(.vertical,row.tall ? 7 : 0).padding(.leading,10).padding(.trailing,6).frame(minHeight:34)
        .background(row.current ? DiscordColors.accent.opacity(0.08) : .clear,in:RoundedRectangle(cornerRadius:9))
        .rowHover(9,veil:0.055,enabled:!(row.bar && !row.ready) && !row.blocked)
        .clickOrHold(row.hold,click:{ if row.blocked { return };if row.bar { if row.ready { studio.unlock(piece,sample) } } else { studio.onlyLine(piece) } },hold:{ studio.toggleLine(piece) })
        .onHover { inside in
            guard !row.bar && !row.blocked else { return }
            if inside {
                let open=row.open,piece=piece
                studio.point(news:piece.topic == .moment) { card in
                    if let open,open < card.lineTwo.count { card.lineTwo[open].piece=piece } else { card.lineTwo=[CardLine(piece:piece)];card.pictures=nil }
                }
            } else { studio.stopPointing() }
        }
    }
}
/// What a catalog row shows and does: whether it's in the list, being changed to, earned, and why it can't show.
struct CatalogRowState {
    let text:String
    let on:Bool
    let number:Int?
    let open:Int?
    let current:Bool
    let bar:Bool
    let ready:Bool
    let progress:(done:Double,earned:String?,needed:String?)?
    let when:(icon:String?,text:String)?
    let note:(text:String,icon:String)?
    /// The time its numbers cover, and what Recall is still building for it.
    let period:String?
    let learning:String?
    let icon:String
    let filled:Bool
    let hold:HoldMode?
    let weight:Int
    /// It needs the profile, which can't be read: it can't be added, or put in place of another, till it can.
    let blocked:Bool
    var tall:Bool { when != nil || learning != nil || bar }
    @MainActor init(studio:DiscordStudio,piece:CardPiece,inputs:CardInputs,sample:CardInputs) {
        let design=studio.design,place=design.lineTwo.firstIndex { $0.piece == piece }
        open=studio.openLine.flatMap { design.lineTwo.indices.contains($0) ? $0 : nil }
        on=place != nil
        let changing=open != nil
        current=open.map { design.lineTwo[$0].piece == piece } ?? false
        let avail=studio.availability(piece,inputs),full=(!on && design.lineTwo.count >= 6)
        // Progress is the player's own: without a profile there's none to show (the example's isn't theirs).
        progress=inputs.profile == nil ? nil : piece.progress(sample)
        let unlocked=(progress == nil || on || studio.unlocked.contains(piece.key))
        bar=(progress != nil && !unlocked)
        ready=(bar && (progress?.done ?? 0) >= 1)
        if piece.topic == .moment { when=(nil,piece.about) }
        else if piece == .highlights { when=("rc:pick",L("Recall shows the first that applies, right now")) }
        else if let progress,unlocked,let earned=progress.earned { when=("rc:key",earned) }
        else { when=nil }
        let quiet=(piece.topic == .moment && (avail == .news || avail == .ok)) || avail == .locked || bar
        note=quiet ? nil : studio.note(avail)
        text=piece == .highlights ? L("Dynamic") : studio.sampleText(piece,sample)
        period=piece.period
        learning=when == nil ? piece.learning(inputs) : nil
        blocked=avail == .profile && !on && !current
        number=on && !changing ? (place ?? 0)+1 : nil
        icon=changing ? (current ? "lucide:check" : blocked ? "lucide:lock" : "lucide:arrow-right") : bar ? "rc:key" : avail == .locked || blocked ? "lucide:lock" : "lucide:plus"
        filled=ready || current || (on && !changing)
        if changing || bar || blocked { hold=nil } else if on { hold=design.lineTwo.count > 1 ? .remove : nil } else { hold=full ? nil : .add }
        weight=current ? 600 : 500
    }
}
private struct CatalogRowText: View {
    let row:CatalogRowState
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            HStack(spacing:6) {
                Text(verbatim:row.text).discordFont(13.5,row.weight).lineLimit(1)
                if let period=row.period {
                    Text(period).designFont(10,.semibold).foregroundStyle(DiscordColors.ink(0.5)).fixedSize()
                        .padding(.horizontal,5).frame(height:16).background(DiscordColors.veil(0.06),in:RoundedRectangle(cornerRadius:5))
                }
            }
            if let learning=row.learning,!row.bar {
                HStack(spacing:6) {
                    DesignIcon("lucide:hourglass",size:10)
                    Text(learning).designFont(11).lineLimit(1)
                }.foregroundStyle(DiscordColors.ink(0.5))
            }
            if let when=row.when,!row.bar {
                HStack(spacing:6) {
                    if let icon=when.icon { DesignIcon(icon,size:10).foregroundStyle(icon == "rc:pick" ? DiscordColors.link : Color.rgb(255,190,92)) }
                    else { Ping(color:DiscordColors.news) }
                    Text(when.text).designFont(11).lineLimit(1)
                }.foregroundStyle(DiscordColors.ink(0.5))
            }
            if row.bar,let progress=row.progress { EarnBar(done:progress.done,ready:row.ready,needed:progress.needed).padding(.top,1) }
        }
    }
}
/// How far an earned line is: a bar, growing to it as it shows, and what it still takes (or that the key is ready).
private struct EarnBar: View {
    let done:Double
    let ready:Bool
    let needed:String?
    @State private var grown=false
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            GeometryReader { box in
                ZStack(alignment:.leading) {
                    Capsule().fill(DiscordColors.veil(0.08))
                    // Grown by its own animation, not one from onAppear that the rest of the panel would ride (see PartArrival).
                    Capsule().fill(fill).frame(width:grown ? box.size.width*min(1,done) : 0)
                        .animation(.curve(.out,1.1).delay(0.15),value:grown)
                }
            }.frame(height:4).onAppear { grown=true }
            Text(ready ? L("You’ve earned it. Click the key to unlock it.") : needed ?? "").designFont(10.5).lineLimit(1)
                .foregroundStyle(ready ? DiscordColors.chosen : DiscordColors.ink(0.5))
        }
    }
    private var fill:AnyShapeStyle {
        ready ? AnyShapeStyle(DiscordColors.accent) : AnyShapeStyle(LinearGradient(colors:[DiscordColors.accent.opacity(0.3),DiscordColors.accent],startPoint:.leading,endPoint:.trailing))
    }
}
/// The circle at a catalog row's end: its place in the list, or what a click does (add, change to it, unlock).
private struct TrailingMark: View {
    let number:Int?
    let icon:String
    let filled:Bool
    let dim:Bool
    let pulse:Bool
    var body:some View {
        ZStack {
            if let number { Text("\(number)").designFont(11,.heavy).monospacedDigit() } else { DesignIcon(icon,size:12) }
        }
        .foregroundStyle(filled ? DiscordColors.onAccent : dim ? DiscordColors.ink(0.4) : DiscordColors.ink(0.6))
        .frame(width:22,height:22)
        .background(filled ? DiscordColors.accent : .clear,in:Circle())
        .overlay { if !filled { Circle().strokeBorder(DiscordColors.veil(0.16),lineWidth:1.5) } }
        .overlay { if pulse { Circle().strokeBorder(DiscordColors.accent.opacity(0.22),lineWidth:3).padding(-3) } }
        .compositingGroup().shadow(color:pulse ? DiscordColors.accent.opacity(0.55) : .clear,radius:7)
        .swaying(0.9,on:pulse) { mark,beat in mark.scaleEffect(1+0.12*beat) }
        .animation(.easeOut(duration:0.25),value:filled)
    }
}

// MARK: the image

struct PicturePanel: View {
    @Bindable var studio:DiscordStudio
    @State private var caption:String?
    var body:some View {
        let inputs=studio.inputs(at:Date()),sample=studio.sampleInputs(at:Date()),design=studio.design,own=design.pictures != nil
        let listCount=own ? design.pictures!.count : DiscordCardDesign.Shown(design,inputs,turn:0).lineTwo.count
        VStack(alignment:.leading,spacing:0) {
            PanelHeading(studio:studio,title:L("Image"),subtitle:L("The large picture. In a match it’s always the Overwatch logo."),turns:listCount > 1)
            if studio.profileState != .shown { ProfileNotice(studio:studio) }
            ModeTabs(studio:studio,own:own,sample:sample).padding(.top,8)
            PictureList(studio:studio,own:own)
            RuleHeading(text:L("Add an image"))
            ImageTabs(studio:studio)
            FlowLayout(spacing:7,lineSpacing:7) {
                ForEach(Array(studio.imageChoices(sample).enumerated()),id:\.element.picture) { index,choice in
                    let place=design.pictures?.firstIndex(of:choice.picture),mine=design.pictures?.count ?? 0
                    PictureTile(picture:choice.picture,inputs:sample,rank:design.rank,number:place.map { $0+1 },rolls:true)
                        .clickOrHold(place != nil && own ? (mine > 1 ? .remove : nil) : (mine < 6 || !own ? .add : nil),radius:10,
                                     click:{ if !(place != nil && mine == 1) { studio.only(choice.picture,in:\.ownPictures) } },
                                     hold:{ studio.toggle(choice.picture,in:\.ownPictures) })
                        .onHover { inside in
                            caption=inside ? choice.name : nil
                            if inside { studio.point { $0.pictures=[choice.picture] } } else { studio.stopPointing() }
                        }
                        .accessibilityLabel(choice.name)
                        // One after another as they show, 22 ms apart (the first dozen).
                        .popIn(0.35,delay:Double(min(index,12))*0.022)
                }
                if studio.imageTab == .heroes && studio.heroesOfRole(sample).count > 10 {
                    Button(studio.allHeroes ? L("Fewer heroes") : L("Show more heroes")) { withAnimation(.snappy) { studio.allHeroes.toggle() } }
                        .buttonStyle(.plain).designFont(11.5,.semibold).foregroundStyle(DiscordColors.ink(0.55)).frame(height:38).padding(.horizontal,6)
                }
            }.padding(.top,8)
            Text(caption ?? L("Click one to use only it. Press and hold to add it to the list."))
                .designFont(11.5).foregroundStyle(DiscordColors.ink(0.55)).lineLimit(1).frame(height:17).padding(.top,7)
        }
    }
}
/// "One per line" or "Your own list" as two tabs, the chosen one joining the list below.
private struct ModeTabs: View {
    @Bindable var studio:DiscordStudio
    let own:Bool
    let sample:CardInputs
    var body:some View {
        let rank=studio.design.rank
        let lineTwo=studio.design.lineTwo.prefix(3).map { $0.piece.picture(sample,rank:rank) }
        let mine=Array((studio.design.pictures ?? [.playerIcon,.lastHero,.overwatch]).prefix(3))
        HStack(alignment:.bottom,spacing:4) {
            ModeTab(on:!own,title:L("One per line"),sub:L("Follows Line 2"),icon:"rc:line2",pictures:lineTwo,joinsLeft:false,sample:sample,rank:rank) { studio.followLineTwo() }
            ModeTab(on:own,title:L("Your own list"),sub:L("They take turns"),icon:"ph:squares-four-fill",pictures:mine,joinsLeft:true,sample:sample,rank:rank) { studio.ownPictures() }
        }
    }
}
private struct ModeTab: View {
    let on:Bool
    let title:String
    let sub:String
    let icon:String
    let pictures:[CardPicture]
    /// The tab sits on the right and meets the box on its left (or the other way round).
    let joinsLeft:Bool
    let sample:CardInputs
    let rank:RankChoice
    let choose:()->Void
    private var shape:UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii:on ? .init(topLeading:12,bottomLeading:0,bottomTrailing:0,topTrailing:12) : .init(topLeading:11,bottomLeading:11,bottomTrailing:11,topTrailing:11))
    }
    var body:some View {
        Button { if !on { withAnimation(.curve(.out,0.35)) { choose() } } } label: {
            HStack(spacing:10) {
                badge.frame(width:36,height:30,alignment:.topLeading)
                VStack(alignment:.leading,spacing:1) {
                    Text(title).designFont(12.5,.semibold).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.72)).lineLimit(1)
                    Text(sub).designFont(10.5).foregroundStyle(DiscordColors.ink(0.5)).lineLimit(1)
                }.fixedSize().frame(maxWidth:.infinity,alignment:.leading)
            }
            .padding(.horizontal,10).frame(height:on ? 56 : 48).frame(maxWidth:.infinity)
            .background(DiscordColors.veil(on ? 0.05 : 0.02),in:shape)
            .overlay(alignment:joinsLeft ? .bottomLeading : .bottomTrailing) {
                if on { Fillet(left:joinsLeft).fill(DiscordColors.veil(0.05)).frame(width:8,height:8).offset(x:joinsLeft ? -8 : 8) }
            }
            .padding(.bottom,on ? 0 : 8)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
    @ViewBuilder private var badge:some View {
        // Each pops in as the tab changes, the pictures one after another.
        if on {
            DesignIcon(icon,size:16).foregroundStyle(DiscordColors.accent)
                .frame(width:30,height:30).background(DiscordColors.accent.opacity(0.16),in:RoundedRectangle(cornerRadius:9)).offset(x:3)
                .popIn(0.35).transition(.identity)
        } else {
            ZStack(alignment:.topLeading) {
                ForEach(Array(pictures.enumerated()),id:\.offset) { index,picture in
                    PictureTile(picture:picture,inputs:sample,rank:rank,size:20,radius:5)
                        .overlay { RoundedRectangle(cornerRadius:5).strokeBorder(Color.rgb(36,37,41),lineWidth:1.5).padding(-1.5) }
                        .offset(x:CGFloat(index)*8,y:CGFloat(index)*5)
                        .popIn(0.35,delay:Double(index)*0.05)
                }
            }.transition(.identity)
        }
    }
}
/// The inside curve between a tab and the box it opens into.
private struct Fillet: Shape {
    let left:Bool
    func path(in rect:CGRect)->Path {
        var path=Path()
        if left {
            path.move(to:CGPoint(x:rect.maxX,y:rect.minY));path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY));path.addLine(to:CGPoint(x:rect.minX,y:rect.maxY))
            path.addArc(center:CGPoint(x:rect.minX,y:rect.minY),radius:rect.width,startAngle:.degrees(90),endAngle:.degrees(0),clockwise:true)
        } else {
            path.move(to:CGPoint(x:rect.minX,y:rect.minY));path.addLine(to:CGPoint(x:rect.minX,y:rect.maxY));path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
            path.addArc(center:CGPoint(x:rect.maxX,y:rect.minY),radius:rect.width,startAngle:.degrees(90),endAngle:.degrees(180),clockwise:false)
        }
        return path
    }
}
/// The pictures that take turns: Line 2's, each from its line, or the player's own list.
private struct PictureList: View {
    @Bindable var studio:DiscordStudio
    let own:Bool
    var body:some View {
        TimelineView(.seconds) { context in
            PanelBox(veil:0.05,corners:own ? .init(topLeading:12,bottomLeading:12,bottomTrailing:12,topTrailing:0) : .init(topLeading:0,bottomLeading:12,bottomTrailing:12,topTrailing:12)) {
                if let pictures=studio.design.pictures { OwnPictureRows(studio:studio,pictures:pictures,now:context.date) }
                else { FollowedPictureRows(studio:studio,now:context.date) }
            }
        }
    }
}
private struct OwnPictureRows: View {
    @Bindable var studio:DiscordStudio
    let pictures:[CardPicture]
    let now:Date
    @State private var dragging:Int?
    var body:some View {
        let inputs=studio.inputs(at:now),sample=studio.sampleInputs(at:now),rank=studio.design.rank,turn=studio.turn(at:now),done=studio.turnDone(at:now)
        let places=DiscordCardDesign.Shown(studio.design,inputs,turn:turn).picturePlaces
        ForEach(Array(pictures.enumerated()),id:\.offset) { index,picture in
            let live=places.count > 1 && places[turn%places.count] == index
            ListRow(number:index+1,text:picture.name,sub:picture.heroSub(sample),live:live,turnDone:done,removable:pictures.count > 1,remove:{ studio.toggle(picture,in:\.ownPictures) }) {
                PictureTile(picture:picture,inputs:sample,rank:rank,size:24,radius:8)
            }
            .onTapGesture { studio.hold(picture:index) }
            .reorderable("picture",index:index,dragging:$dragging,tick:now,move:{ studio.movePicture(from:$0,to:$1) }) {
                PictureTile(picture:picture,inputs:sample,rank:rank,size:24,radius:8)
            }
        }
        if pictures.count == 1 { HoldHint(text:L("Hold an image below to add it. They take turns.")).padding(EdgeInsets(top:7,leading:12,bottom:5,trailing:10)) }
    }
}
private struct FollowedPictureRows: View {
    @Bindable var studio:DiscordStudio
    let now:Date
    var body:some View {
        let inputs=studio.inputs(at:now),sample=studio.sampleInputs(at:now),design=studio.design,turn=studio.turn(at:now),done=studio.turnDone(at:now)
        let shown=DiscordCardDesign.Shown(design,inputs,turn:turn).lineTwo.map(\.piece)
        let lines=design.lineTwo.enumerated().filter { shown.contains($0.element.piece) }
        ForEach(lines,id:\.offset) { index,line in
            let picture=line.piece.picture(sample,rank:design.rank)
            let live=shown.count > 1 && shown[turn%shown.count] == line.piece
            ListRow(number:index+1,text:picture.shownName(sample,rank:design.rank),sub:L("With “{0}” on Line 2",line.piece.label),live:live,turnDone:done) {
                PictureTile(picture:picture,inputs:sample,rank:design.rank,size:24,radius:8)
            }
        }
    }
}
/// Suggested, Heroes (by role) and Extra, with the design's gliding underline.
private struct ImageTabs: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        HStack(spacing:14) {
            ForEach(DiscordStudio.ImageTab.allCases,id:\.self) { tab in
                let on=studio.imageTab == tab
                Button { studio.imageTab=tab;studio.allHeroes=false } label: {
                    // Its colour changes over a quarter second, its weight at once.
                    Text(tab.name).designFont(12.5,on ? .semibold : .medium)
                        .animation(.curve(.css,0.25)) { $0.foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.52)) }
                        .glideItem(tab).frame(height:32)
                }.buttonStyle(.plain)
            }
            if studio.imageTab == .heroes {
                HStack(spacing:1) {
                    ForEach([CareerRank.Role.tank,.damage,.support],id:\.self) { role in
                        let on=studio.role == role
                        // The role's own icon, its name when pointed at: the names didn't fit beside the tabs.
                        Button { studio.role=role;studio.allHeroes=false } label: {
                            DesignIcon("ow:"+role.rawValue,size:13).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.55))
                                .padding(.horizontal,8).frame(height:22).background(on ? DiscordColors.veil(0.14) : .clear,in:RoundedRectangle(cornerRadius:6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).designTip(role.label).accessibilityLabel(role.label)
                    }
                }
                .padding(2).background(DiscordColors.veil(0.05),in:RoundedRectangle(cornerRadius:8)).padding(.leading,-4)
                .popIn(0.3,curve:.curve(.css,0.3)).transition(.identity)
            }
        }
        // The ribbon under the chosen tab: two points high, two below its words.
        .glider(studio.imageTab,style:.tabs,axis:.horizontal,across:{ ($0.maxY+2,2) }) { RibbonLine() }
        .padding(.bottom,3)
    }
}
/// The design's ribbon sliding along a line or through a word (its dcShift).
struct RibbonLine: View {
    var rounded=true
    /// Held as it was at that moment (Customize's morph carries the word as it left); moving otherwise.
    var still:Date?=nil
    var body:some View {
        if let still { ribbon(at:still) } else { TimelineView(.animation(paused:!Moving.shared.now)) { ribbon(at:$0.date) } }
    }
    private func ribbon(at date:Date)->some View {
        GeometryReader { box in
            let width=max(box.size.width,1),shift=CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:3))*width
            HStack(spacing:0) {
                ForEach(0..<2,id:\.self) { _ in LinearGradient(stops:DiscordColors.ribbon,startPoint:.leading,endPoint:.trailing).frame(width:3*width) }
            }.offset(x:-shift)
        }
        .clipShape(RoundedRectangle(cornerRadius:rounded ? 2 : 0))
    }
}
/// A picture as it would be now; the game's own picture when there's none.
struct PictureTile: View {
    let picture:CardPicture
    let inputs:CardInputs
    let rank:RankChoice
    var size:CGFloat=38
    var radius:CGFloat=10
    var number:Int?=nil
    /// Last hero rolls through heroes, as it follows whoever was played last (where it's offered).
    var rolls=false
    @State private var lift=false
    var body:some View {
        let image=picture.image(inputs,rank:rank,turn:0),whole=picture == .overwatch || picture == .rankEmblem || picture == .recall
        let roll=rolls && picture == .lastHero ? inputs.lastHeroRoll : []
        Group {
            if roll.count > 2 {
                Rolling(steps:roll.count-1,height:size) {
                    ForEach(Array(roll.enumerated()),id:\.offset) { _,url in RemoteImage(url:url,fill:true) { DiscordColors.tile }.frame(width:size,height:size) }
                }
            } else if let image { RemoteImage(url:image.url,fill:!whole || picture == .recall) { DiscordColors.tile } } else { GameIcon() }
        }
        .padding(picture == .rankEmblem ? size*0.08 : 0)
        .frame(width:size,height:size)
        .background(whole ? DiscordColors.veil(0.05) : DiscordColors.tile)
        .clipShape(RoundedRectangle(cornerRadius:radius))
        .overlay { if number != nil { RoundedRectangle(cornerRadius:radius).strokeBorder(DiscordColors.accent,lineWidth:2).padding(-2) } }
        .overlay(alignment:.topTrailing) {
            if let number {
                Text("\(number)").designFont(10,.heavy).foregroundStyle(DiscordColors.onAccent)
                    .padding(.horizontal,4).frame(minWidth:16,minHeight:16).background(DiscordColors.accent,in:Capsule())
                    .overlay { Capsule().strokeBorder(DiscordColors.stage,lineWidth:2).padding(-2) }.offset(x:4,y:-4)
                    .popIn(0.3).transition(.identity)
            }
        }
        .offset(y:lift && size >= 38 ? -2 : 0)
        .onHover { inside in withAnimation(.curve(.out,0.25)) { lift=inside } }
    }
}

private extension CardInputs {
    /// What Last hero rolls through: the last hero, the two most played others, the last again.
    var lastHeroRoll:[URL] {
        guard let last=profile?.last?.hero,let portrait=profile?.hero?.portrait else { return [] }
        let others=topHeroes.filter { $0 != last }.prefix(2).compactMap { profile?.heroes[$0]?.portrait }
        return others.isEmpty ? [] : [portrait]+others+[portrait]
    }
}

// MARK: the badge, line 1, the timer, the buttons

struct BadgePanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        TimelineView(.seconds) { context in
            let inputs=studio.inputs(at:context.date),sample=studio.sampleInputs(at:context.date),design=studio.design,count=design.badges.count,turn=studio.turn(at:context.date)
            let places=DiscordCardDesign.Shown(design,inputs,turn:turn).badgePlaces
            let large=(studio.activity(at:context.date)["assets"] as? [String:String])?["large_image"].flatMap(URL.init(string:))
            VStack(alignment:.leading,spacing:0) {
                PanelHeading(studio:studio,title:L("Badge"),subtitle:L("The small circle on the image. In a match it’s the Mac badge, or Recall’s icon."),turns:count > 1)
                if studio.profileState != .shown { ProfileNotice(studio:studio) }
                VStack(spacing:2) {
                    ForEach(CardBadge.allCases,id:\.self) { badge in
                        let place=design.badges.firstIndex(of:badge),on=place != nil
                        ChoiceRow(title:badge.name,sub:studio.badgeAbout(badge,sample),on:on,mark:.pick,number:count > 1 ? place.map { $0+1 } : nil,
                                  live:places.count > 1 && inputs.menus && place == places[turn%places.count],turnDone:studio.turnDone(at:context.date)) {
                            BadgeThumb(large:large,badge:badge,rank:sample.rank(design.rank)?.icon)
                        }
                        .clickOrHold(on ? (count > 1 ? .remove : nil) : .add,radius:11,click:{ studio.only(badge,in:\.badges) },hold:{ studio.toggle(badge,in:\.badges) })
                        .pointing(studio) { $0.badges=[badge] }
                    }
                }.padding(.top,8)
                if count == 1 { HoldHint(text:L("Hold another badge to add it. They take turns.")).padding(.horizontal,10).padding(.top,4) }
                if design.badges.contains(.rank) {
                    RuleHeading(text:L("Which rank"))
                    // 4 more: the design's margins here collapse into the heading's own four points.
                    RankTiles(studio:studio).padding(.top,4)
                    Note(text:L("The rank you pick here is also the one every rank line shows."))
                }
            }
        }
    }
}
/// The card's picture as it is now, with this badge.
private struct BadgeThumb: View {
    let large:URL?
    let badge:CardBadge
    let rank:URL?
    var body:some View {
        Group { if let large { RemoteImage(url:large) { DiscordColors.tile } } else { GameIcon() } }
            .frame(width:42,height:42).background(DiscordColors.tile).clipShape(RoundedRectangle(cornerRadius:8))
            .overlay(alignment:.bottomTrailing) {
                Group {
                    if badge == .rank,let rank { RemoteImage(url:rank,fill:false) { Color.clear }.frame(width:16,height:16) }
                    else { BadgeImage(url:badge == .recall ? DiscordAssets.badge : DiscordAssets.macBadge,size:16,back:DiscordColors.stage) }
                }
                .frame(width:20,height:20).background(DiscordColors.stage,in:Circle())
                .overlay { Circle().strokeBorder(Color.rgb(36,37,41),lineWidth:2.5).padding(-2.5) }
                // Over the picture's corner, taking no room (the row is as tall as the picture).
                .offset(x:5,y:5)
            }
    }
}
/// A quiet note at a panel's end.
struct Note: View {
    let text:String
    var body:some View {
        Text(text).designFont(11.5,line:11.5*1.45,wraps:true).foregroundStyle(DiscordColors.ink(0.42)).fixedSize(horizontal:false,vertical:true)
            .padding(.horizontal,4).padding(.top,10)
    }
}

struct LineOnePanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        TimelineView(.seconds) { context in
            let sample=studio.sampleInputs(at:context.date),inputs=studio.inputs(at:context.date),design=studio.design,count=design.lineOne.count
            VStack(alignment:.leading,spacing:0) {
                PanelHeading(studio:studio,title:L("Line 1"),subtitle:L("Where you are, read live from the game, and what goes in front of it."),turns:count > 1)
                if studio.profileState != .shown { ProfileNotice(studio:studio) }
                VStack(spacing:2) {
                    ForEach(LineOne.allCases,id:\.self) { item in
                        let place=design.lineOne.firstIndex(of:item),on=place != nil
                        let needsProfile=[LineOne.nameAndTitle,.main,.rank].contains(item) && inputs.profile == nil
                        ChoiceRow(title:item.name,sub:needsProfile ? L("Needs your profile") : item == .rank ? L("Name in a match") : nil,on:on,mark:.pick,
                                  number:count > 1 ? place.map { $0+1 } : nil,live:count > 1 && place == studio.turn(at:context.date)%count,turnDone:studio.turnDone(at:context.date)) {
                            Text(verbatim:(item == .phrase ? (design.phrase ?? LinePhrase(words:.roadTo)).words.shape : sample.lineOne(item,rank:design.rank)) ?? studio.texts.menu)
                                .discordFont(13.5).foregroundStyle(DiscordColors.text).lineLimit(1).frame(maxWidth:180,alignment:.trailing)
                        }
                        .clickOrHold(on ? (count > 1 ? .remove : nil) : (count < 5 ? .add : nil),radius:11,
                                     click:{ if item == .phrase && design.phrase == nil { studio.choosePhrase(.roadTo) } else { studio.only(item,in:\.lineOne) } },
                                     hold:{ if item == .phrase && design.phrase == nil { studio.edit { $0.phrase=LinePhrase(words:.roadTo);$0.lineOne.append(.phrase) } } else { studio.toggle(item,in:\.lineOne,most:5) } })
                        .pointing(studio) { $0.lineOne=[item];if item == .phrase && $0.phrase == nil { $0.phrase=LinePhrase(words:.roadTo) } }
                    }
                }.padding(.top,8)
                if count == 1 { HoldHint(text:L("Hold another to add it. They take turns.")).padding(.horizontal,10).padding(.top,4) }
                if design.lineOne.contains(.phrase) { PhrasePicker(studio:studio,sample:sample).padding(.top,12) }
            }
        }
    }
}

/// Line 1's phrase: Recall's words and the blank's filling, Auto or from a list. Nothing is typed.
struct PhrasePicker: View {
    @Bindable var studio:DiscordStudio
    let sample:CardInputs
    var body:some View {
        let phrase=studio.design.phrase
        VStack(alignment:.leading,spacing:8) {
            Text(L("The phrase")).designFont(11.5,.semibold).foregroundStyle(DiscordColors.ink(0.5)).padding(.leading,2)
            FlowLayout(spacing:4,lineSpacing:4) {
                ForEach(LinePhrase.Words.allCases,id:\.self) { words in
                    let on=phrase?.words == words
                    Button { if !on { studio.choosePhrase(words) } } label: {
                        Text(words.shape).designFont(12,on ? .semibold : .medium).lineLimit(1)
                            .foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.62))
                            .padding(.horizontal,10).frame(height:26)
                            .background(on ? DiscordColors.veil(0.14) : DiscordColors.veil(0.04),in:RoundedRectangle(cornerRadius:7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                    .pointing(studio) { $0.phrase=LinePhrase(words:words);if !$0.lineOne.contains(.phrase) { $0.lineOne=[.phrase] } }
                }
            }
            if let phrase,phrase.words.kind != .none {
                Text(L("What fills the blank")).designFont(11.5,.semibold).foregroundStyle(DiscordColors.ink(0.5)).padding(.leading,2).padding(.top,4)
                FlowLayout(spacing:4,lineSpacing:4) {
                    ForEach(blanks(phrase.words.kind),id:\.0) { blank,label in
                        let on=phrase.blank == blank
                        Button { if !on { studio.fillPhrase(blank) } } label: {
                            Text(label).designFont(12,on ? .semibold : .medium).lineLimit(1)
                                .foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.62))
                                .padding(.horizontal,10).frame(height:26)
                                .background(on ? DiscordColors.veil(0.14) : DiscordColors.veil(0.04),in:RoundedRectangle(cornerRadius:7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                        .pointing(studio) { $0.phrase=LinePhrase(words:phrase.words,blank:blank) }
                    }
                }
            }
            if phrase?.words.tonight == true { HoldHint(text:L("About tonight: it comes off your card when you quit Overwatch.")).padding(.horizontal,2) }
        }
        .padding(10).background(DiscordColors.veil(0.03),in:RoundedRectangle(cornerRadius:12))
    }
    /// Auto first (with what it fills now, when it can), then the list.
    private func blanks(_ kind:LinePhrase.Words.Kind)->[(LinePhrase.Blank,String)] {
        let auto=studio.design.phrase.flatMap { sample.phrase(LinePhrase(words:$0.words),rank:studio.design.rank) }.map { L("Auto ({0})",$0) } ?? L("Auto")
        switch kind {
        case .none: return []
        case .rank: return [(.auto,auto)]+CareerRank.divisions.map { (.rank($0),CareerRank.name($0)) }
        case .role: return [(.auto,auto)]+[CareerRank.Role.tank,.damage,.support].map { (.role($0),$0.label) }
        case .hero:
            let heroes=studio.heroOrder(sample)
            let keys=heroes.isEmpty ? DiscordCardCode.heroes.filter { $0 != "jetpack-cat" } : heroes
            return [(.auto,auto)]+keys.map { (.hero($0),sample.heroName($0)) }
        }
    }
}
extension LinePhrase.Words {
    /// The words with their blank shown as "…", for the picker.
    var shape:String {
        switch self {
        case .roadTo: return L("Road to …")
        case .grindingTo: return L("Grinding to …")
        case .learning: return L("Learning …")
        case .maining: return L("Maining …")
        case .practicing: return L("Practicing …")
        case .rolePlayer: return L("… player")
        case .climbingIn: return L("Climbing in …")
        case .offRole: return L("Off-role …")
        case .flexing: return L("Flexing")
        case .chillNight: return L("Chill night")
        case .tryhard: return L("Tryhard mode")
        case .warmingUp: return L("Warming up")
        case .oneMore: return L("One more game")
        case .lastGame: return L("Last game")
        case .withFriends: return L("With friends")
        case .soloQueue: return L("Solo queue")
        }
    }
}

struct TimerPanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            PanelHeading(studio:studio,title:L("Timer"),subtitle:L("Discord always shows a timer."))
            TimelineView(.seconds) { context in
                let inputs=studio.inputs(at:context.date)
                let match:Date={ if case .match(let since)=inputs.place { return since };return studio.previewMatchStart }()
                VStack(spacing:2) {
                    row(.session,title:L("The whole session"),sub:L("Counts from when you opened Overwatch"),since:inputs.launched,now:context.date)
                    row(.match,title:L("Each match"),sub:L("Starts over when a match starts; the menus count the session"),since:match,now:context.date)
                }.padding(.top,8)
            }
        }
    }
    private func row(_ timer:CardTimer,title:String,sub:String,since:Date,now:Date)->some View {
        ChoiceRow(title:title,sub:sub,on:studio.design.timer == timer) {
            HStack(spacing:5) { DesignIcon("mdi:controller",size:14);Text(verbatim:DiscordCardView.clock(max(0,Int(now.timeIntervalSince(since))))).discordFont(13.5,600).monospacedDigit() }
                .foregroundStyle(DiscordColors.timer)
        }
        .onTapGesture { if studio.design.timer != timer { studio.edit { $0.timer=timer } } }
        .pointing(studio) { $0.timer=timer }
    }
}

struct ButtonsPanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let inputs=studio.inputs(at:Date())
        VStack(alignment:.leading,spacing:0) {
            PanelHeading(studio:studio,title:L("Buttons"),subtitle:L("Friends see them under your card. Discord never shows you your own."))
            VStack(spacing:2) {
                ChoiceRow(title:L("First button"),sub:L("Always there"),mark:.fixed) { sample(L("Get {0} for Mac",Brand.name),locked:true) }
                ForEach([SecondButton?.some(.careerProfile),.heroPage,.patchNotes,nil],id:\.self) { button in
                    let label=button.flatMap { b in (studio.sample(inputs) { $0.button=b }["buttons"] as? [[String:String]])?.dropFirst().first?["label"] }
                    ChoiceRow(title:button?.name ?? L("Only Get Recall"),sub:studio.buttonAbout(button,hasLabel:label != nil),on:studio.design.button == button) {
                        if button != nil { sample(label ?? button!.name,locked:false) }
                    }
                    .onTapGesture { if studio.design.button != button { studio.edit { $0.button=button } } }
                    .pointing(studio) { $0.button=button }
                }
            }.padding(.top,8)
        }
    }
    private func sample(_ label:String,locked:Bool)->some View {
        HStack(spacing:5) { Text(verbatim:label).discordFont(13,600).lineLimit(1);if locked { DesignIcon("lucide:lock",size:11).opacity(0.7) } }
            .foregroundStyle(.white)
            .padding(.horizontal,12).frame(minWidth:96).frame(height:28)
            .background(Color.rgb(78,80,88),in:RoundedRectangle(cornerRadius:6))
    }
}

// MARK: the party

struct PartyPanel: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        var inputs=studio.inputs(at:Date())
        if inputs.voice == nil { inputs.voice=GroupVoice(count:3,channel:"preview",party:"preview") }
        let base=studio.sample(inputs) { $0.party = .noCount }
        return VStack(alignment:.leading,spacing:0) {
            PanelHeading(studio:studio,title:L("Party"),subtitle:L("While you’re in the group’s voice chat. Discord can show how many are in it, never who."))
            VStack(spacing:6) {
                ForEach([PartyChoice.sayVoice,.addCount,.noCount],id:\.self) { party in
                    let on=studio.design.party == party
                    let line=party == .sayVoice ? studio.texts.voice : (base["state"] as? String ?? studio.texts.menu)
                    HStack(spacing:12) {
                        Circle().strokeBorder(on ? DiscordColors.accent : DiscordColors.veil(0.25),lineWidth:1.5)
                            .overlay { if on { Circle().fill(DiscordColors.accent).frame(width:7,height:7) } }.frame(width:16,height:16)
                        VStack(alignment:.leading,spacing:7) {
                            Text(party.name).designFont(12.5,.semibold).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.78))
                            HStack(spacing:10) {
                                MiniPicture(activity:base)
                                VStack(alignment:.leading,spacing:0) {
                                    Text(verbatim:base["details"] as? String ?? studio.texts.menu).discordFont(12.5,line:16).lineLimit(1)
                                    Text(verbatim:line+(party == .noCount ? "" : " ")).followed(by:Text(verbatim:party == .noCount ? "" : "(\(L("{0} of {1}","3","6")))").fontWeight(.semibold).foregroundColor(Color.rgb(255,180,130)))
                                        .discordFont(12.5,line:16).lineLimit(1)
                                }.foregroundStyle(DiscordColors.text).frame(maxWidth:.infinity,alignment:.leading)
                            }
                            .padding(.horizontal,10).padding(.vertical,7).background(DiscordColors.card,in:RoundedRectangle(cornerRadius:8))
                        }
                    }
                    .padding(EdgeInsets(top:9,leading:11,bottom:10,trailing:12))
                    .background(on ? DiscordColors.accent.opacity(0.08) : DiscordColors.veil(0.03),in:RoundedRectangle(cornerRadius:12))
                    .overlay { if on { RoundedRectangle(cornerRadius:12).strokeBorder(DiscordColors.accent.opacity(0.6),lineWidth:1.5) } }
                    .rowHover(12,veil:0.06,enabled:!on)
                    .contentShape(Rectangle())
                    .onTapGesture { if !on { studio.edit { $0.party=party } } }
                    .pointing(studio) { $0.party=party }
                    .animation(.easeOut(duration:0.25),value:on)
                }
            }.padding(.top,8)
            Note(text:L("No Ask to Join: Overwatch has no way for Recall to let a friend into your group, and Discord would take your buttons away for it."))
        }
    }
}
/// The card's large picture, small (the party's mini cards).
private struct MiniPicture: View {
    let activity:[String:Any]
    var body:some View {
        let url=(activity["assets"] as? [String:String])?["large_image"].flatMap(URL.init(string:))
        Group { if let url { RemoteImage(url:url) { DiscordColors.tile } } else { GameIcon() } }
            .frame(width:34,height:34).background(url == nil ? .clear : DiscordColors.tile).clipShape(RoundedRectangle(cornerRadius:6))
    }
}

/// Lays its views out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing:CGFloat=6
    var lineSpacing:CGFloat?=nil
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let rows=arrange(width:proposal.width ?? .infinity,subviews)
        return CGSize(width:proposal.width ?? rows.map(\.width).max() ?? 0,height:rows.last.map { $0.y+$0.height } ?? 0)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        for row in arrange(width:bounds.width,subviews) {
            for item in row.items { subviews[item.index].place(at:CGPoint(x:bounds.minX+item.x,y:bounds.minY+row.y+(row.height-item.size.height)/2),proposal:ProposedViewSize(item.size)) }
        }
    }
    private struct Row { var items:[(index:Int,x:CGFloat,size:CGSize)]=[];var y:CGFloat=0;var width:CGFloat=0;var height:CGFloat=0 }
    private func arrange(width:CGFloat,_ subviews:Subviews)->[Row] {
        var rows=[Row()]
        for (index,subview) in subviews.enumerated() {
            let size=subview.sizeThatFits(.unspecified)
            if rows[rows.count-1].width > 0 && rows[rows.count-1].width+spacing+size.width > width {
                let last=rows[rows.count-1];rows.append(Row(y:last.y+last.height+(lineSpacing ?? spacing)))
            }
            var row=rows[rows.count-1]
            let x=row.width > 0 ? row.width+spacing : 0
            row.items.append((index,x,size));row.width=x+size.width;row.height=max(row.height,size.height)
            rows[rows.count-1]=row
        }
        return rows
    }
}
