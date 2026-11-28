import SwiftUI
import AppKit

// The pieces Customize's panels are built from, and the click-or-hold every choice answers to.

enum HoldMode { case add,remove }

extension View {
    /// A click uses only this one; holding half a second adds it or takes it out (`mode`) while a fill sweeps. No mode:
    /// click only.
    func clickOrHold(_ mode:HoldMode?,radius:CGFloat=9,click:@escaping ()->Void,hold:@escaping ()->Void)->some View {
        modifier(ClickOrHold(mode:mode,radius:radius,click:click,hold:hold))
    }
    /// Shows a change on the card while the pointer rests on this choice (after a moment, as in the design).
    func pointing(_ studio:DiscordStudio,_ change:@escaping (inout DiscordCardDesign)->Void)->some View {
        onHover { inside in if inside { studio.point(change) } else { studio.stopPointing() } }
    }
    /// The design's hover on a row: a faint veil.
    func rowHover(_ radius:CGFloat,veil:Double=0.055,enabled:Bool=true)->some View { modifier(RowHover(radius:radius,veil:veil,enabled:enabled)) }
}
private struct RowHover: ViewModifier {
    let radius:CGFloat
    let veil:Double
    let enabled:Bool
    @State private var inside=false
    func body(content:Content)->some View {
        content.background { if inside && enabled { RoundedRectangle(cornerRadius:radius).fill(DiscordColors.veil(veil)) } }
            .onHover { inside=$0 }
            .animation(.easeOut(duration:0.2),value:inside)
    }
}
private struct ClickOrHold: ViewModifier {
    let mode:HoldMode?
    let radius:CGFloat
    let click:()->Void
    let hold:()->Void
    @State private var pressed=false
    @State private var held=false
    @State private var moved=false
    @State private var sweep=false
    @State private var pop=false
    @State private var timer:Task<Void,Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content:Content)->some View {
        content
            .overlay(alignment:.leading) {
                GeometryReader { box in
                    Rectangle().fill(mode == .remove ? DiscordColors.veil(0.13) : DiscordColors.accent.opacity(0.3))
                        .frame(width:sweep ? box.size.width : 0)
                }
                .opacity(sweep ? 1 : 0)
                .clipShape(RoundedRectangle(cornerRadius:radius)).allowsHitTesting(false)
            }
            .scaleEffect(pop && !reduceMotion ? 1.05 : 1)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { value in
                if !pressed { pressed=true;held=false;moved=false;start() }
                if !moved && (abs(value.translation.width) > 8 || abs(value.translation.height) > 8) { moved=true;stop() }
            }.onEnded { _ in
                let clicked=pressed && !held && !moved
                pressed=false;stop()
                if clicked { click() }
            })
            // Gone mid-hold (Esc, Done): the hold doesn't land after it.
            .onDisappear { pressed=false;stop() }
            // With Keyboard navigation on: Space clicks, Return holds.
            .focusable(interactions:.activate)
            .onKeyPress(.space) { click();return .handled }
            .onKeyPress(.return) { if mode != nil { hold();return .handled };return .ignored }
            // VoiceOver can't hold: the click is the button's own action, the hold one by name.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { click() }
            .accessibilityActions { if let mode { Button(mode == .remove ? L("Remove") : L("Add"),action:hold) } }
    }
    private func start() {
        guard mode != nil else { return }
        timer?.cancel()
        timer=Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(90))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration:0.43)) { sweep=true }
            try? await Task.sleep(for:.milliseconds(430))
            guard !Task.isCancelled else { return }
            held=true;sweep=false
            hold()
            withAnimation(.curve(.out,0.13)) { pop=true }
            try? await Task.sleep(for:.milliseconds(130))
            withAnimation(.curve(.out,0.25)) { pop=false }
        }
    }
    private func stop() { timer?.cancel();timer=nil;sweep=false }
}

/// A panel's title, what the part is, and (for a list that takes turns) how long each one stays.
struct PanelHeading: View {
    @Bindable var studio:DiscordStudio
    let title:String
    let subtitle:String
    var turns=false
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                Text(title).designFont(15,.bold).foregroundStyle(DiscordColors.bright)
                Spacer()
                if turns { PaceButton(studio:studio) }
            }.frame(height:30)
            Text(subtitle).designFont(11.5,line:11.5*1.45).foregroundStyle(DiscordColors.ink(0.45))
                .frame(maxWidth:.infinity,minHeight:34,alignment:.topLeading).fixedSize(horizontal:false,vertical:true).padding(.top,-1)
        }
    }
}
/// "⟳ 45 s": how long each item stays; a click takes the next pace.
struct PaceButton: View {
    @Bindable var studio:DiscordStudio
    @State private var inside=false
    var body:some View {
        Button { studio.nextPace() } label: {
            HStack(spacing:6) {
                DesignIcon("lucide:repeat",size:12)
                Text(DiscordStudio.paceName(studio.design.pace)).designFont(11.5,.semibold).monospacedDigit().foregroundStyle(DiscordColors.bright).frame(minWidth:36,alignment:.leading)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(DiscordColors.ink(inside ? 1 : 0.7))
            .padding(.leading,9).padding(.trailing,10).frame(height:26)
            .background(DiscordColors.veil(inside ? 0.09 : 0.05),in:RoundedRectangle(cornerRadius:8))
        }
        .buttonStyle(.plain).onHover { inside=$0 }
        .accessibilityLabel(L("Change how long each one stays"))
        .animation(.snappy,value:studio.design.pace)
    }
}

/// A box of the panel's own (a list, a notice).
struct PanelBox<Content:View>: View {
    var padding:CGFloat=4
    var veil=0.03
    var corners=RectangleCornerRadii(topLeading:13,bottomLeading:13,bottomTrailing:13,topTrailing:13)
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:0) { content }.padding(padding).frame(maxWidth:.infinity,alignment:.leading)
            .background(DiscordColors.veil(veil),in:UnevenRoundedRectangle(cornerRadii:corners))
    }
}
extension View {
    /// A row reordered by dragging: it moves as dragged over the others (`dragging`), letting go ends it. Only the
    /// list's own rows count; a drag let go outside is forgotten.
    func reorderable<Preview:View>(_ list:String,index:Int,dragging:Binding<Int?>,tick:Date,move:@escaping (Int,Int)->Void,
                                   @ViewBuilder preview:()->Preview)->some View {
        draggable("\(list):\(index)") { preview().onAppear { dragging.wrappedValue=index } }
            .dropDestination(for:String.self) { items,_ in
                dragging.wrappedValue=nil
                return items.first?.hasPrefix(list+":") == true
            } isTargeted: { over in
                guard over,let from=dragging.wrappedValue,from != index else { return }
                withAnimation(.snappy) { move(from,index) }
                dragging.wrappedValue=index
            }
            .onChange(of:tick) { if dragging.wrappedValue != nil && NSEvent.pressedMouseButtons & 1 == 0 { dragging.wrappedValue=nil } }
    }
}

/// A numbered row in a part's list: its turn (a ring filling while on the card), a picture, what it shows, a note, and
/// ✕.
struct ListRow<Leading:View>: View {
    let number:Int
    let text:String
    var sub:String?=nil
    /// "Matches too": the line shows in a match as well (blue while the preview is in one).
    var matchesToo:Bool?=nil
    var note:(text:String,icon:String)?=nil
    var live=false
    var turnDone:Double=0
    var selected=false
    var available=true
    var removable=false
    var remove:()->Void={}
    @ViewBuilder var leading:Leading
    var body:some View {
        HStack(spacing:9) {
            ZStack {
                if live { Ring(done:turnDone,width:1.6,track:DiscordColors.accent.opacity(0.22)).animation(turnDone < 0.05 ? nil : .linear(duration:1),value:turnDone) }
                Text("\(number)").designFont(11,.bold).monospacedDigit().foregroundStyle(live ? DiscordColors.accent : DiscordColors.ink(0.4))
            }.frame(width:18,height:18)
            leading.opacity(available ? 1 : 0.5)
            VStack(alignment:.leading,spacing:0) {
                Text(verbatim:text).discordFont(14,selected ? 600 : 500).lineLimit(1)
                    .foregroundStyle(available ? (selected || live ? DiscordColors.bright : DiscordColors.ink(0.8)) : DiscordColors.ink(0.38))
                if let sub {
                    HStack(spacing:6) {
                        Text(sub).designFont(11).foregroundStyle(DiscordColors.ink(0.45)).lineLimit(1)
                        if let inMatch=matchesToo { MatchesTooChip(inMatch:inMatch) }
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            if let note { NoteMark(note:note) }
            if removable { RemoveButton(action:remove) }
        }
        .padding(EdgeInsets(top:5,leading:8,bottom:5,trailing:4)).frame(minHeight:38)
        .contentShape(Rectangle())
        .popIn(0.38)
    }
}
/// Why a line can't show; the profile's reasons as Battle.net's mark in red, its words on pointing.
struct NoteMark: View {
    let note:(text:String,icon:String)
    var body:some View {
        if note.icon == "simple-icons:battledotnet" {
            DesignIcon(note.icon,size:12).foregroundStyle(DiscordColors.warning.opacity(0.85))
                .frame(width:20,height:20).contentShape(Rectangle())
                .designTip(note.text).accessibilityLabel(note.text)
        } else {
            HStack(spacing:4) { DesignIcon(note.icon,size:11);Text(note.text).designFont(11) }.foregroundStyle(DiscordColors.ink(0.42)).fixedSize()
        }
    }
}
/// "⚔ Matches too": the other lines are for the menus only.
struct MatchesTooChip: View {
    let inMatch:Bool
    var body:some View {
        HStack(spacing:3) { DesignIcon("ph:sword-fill",size:8.5);Text(L("Matches too")).designFont(9.5,.bold) }
            .foregroundStyle(inMatch ? Color.rgb(150,195,255) : DiscordColors.ink(0.55))
            .padding(.leading,4).padding(.trailing,5).frame(height:16)
            .background(inMatch ? DiscordColors.inMatch.opacity(0.18) : DiscordColors.veil(0.06),in:RoundedRectangle(cornerRadius:5))
            .fixedSize()
            .designTip(L("Shows in matches too. The other lines are for the menus only."))
            .animation(.easeOut(duration:0.25),value:inMatch)
    }
}
struct RemoveButton: View {
    let action:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:action) {
            DesignIcon("lucide:x",size:13).foregroundStyle(inside ? DiscordColors.bright : DiscordColors.ink(0.32))
                .frame(width:24,height:24).background(inside ? DiscordColors.veil(0.08) : .clear,in:RoundedRectangle(cornerRadius:7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside=$0 }.accessibilityLabel(L("Remove"))
    }
}
/// A line's icon in the list: its topic's, on a quiet tile.
struct RowIcon: View {
    let icon:String
    var body:some View {
        DesignIcon(icon,size:12.5).foregroundStyle(DiscordColors.ink(0.7))
            .frame(width:24,height:24).background(DiscordColors.veil(0.05),in:RoundedRectangle(cornerRadius:7))
    }
}

/// What a hold does, under a list.
struct HoldHint: View {
    let text:String
    var body:some View {
        HStack(spacing:7) {
            DesignIcon("rc:hold",size:12).foregroundStyle(DiscordColors.accent)
            Text(text).designFont(11,wraps:true).foregroundStyle(DiscordColors.ink(0.5))
        }
        .fadeIn(0.4)
    }
}

/// A heading with a rule after it ("Add a line ———"), and maybe a button at its end.
struct RuleHeading<Trailing:View>: View {
    let text:String
    @ViewBuilder var trailing:Trailing
    var body:some View {
        HStack(spacing:8) {
            Text(text).designFont(11.5,.semibold)
            Rectangle().fill(DiscordColors.veil(0.07)).frame(height:1)
            trailing
        }
        .font(LauncherStyle.font(11.5,.semibold)).foregroundStyle(DiscordColors.ink(0.5))
        .padding(.top,16).padding(.bottom,4)
    }
}
extension RuleHeading where Trailing == EmptyView {
    init(text:String) { self.init(text:text) { EmptyView() } }
}
/// A text button in the design's link colour ("Done", "Add").
struct LinkButton: View {
    let title:String
    var size:CGFloat=12
    let action:()->Void
    @State private var inside=false
    var body:some View {
        Button(action:action) { Text(title).designFont(size,.semibold).foregroundStyle(inside ? DiscordColors.bright : DiscordColors.link) }
            .buttonStyle(.plain).onHover { inside=$0 }
    }
}

/// A choice in a short list: a radio, or one of several (numbered, a ring filling while on the card).
struct ChoiceRow<Trailing:View>: View {
    enum Mark { case radio,pick,fixed }
    let title:String
    var sub:String?=nil
    var on=false
    var mark=Mark.radio
    /// Picked as the list's nth, of several.
    var number:Int?=nil
    var live=false
    var turnDone:Double=0
    @ViewBuilder var trailing:Trailing
    var body:some View {
        HStack(spacing:11) {
            markView.frame(width:18,height:18)
            VStack(alignment:.leading,spacing:2) {
                Text(title).designFont(12.5,.semibold).foregroundStyle(mark == .fixed ? DiscordColors.ink(0.6) : on ? DiscordColors.bright : DiscordColors.ink(0.78))
                if let sub { Text(sub).designFont(11,wraps:true).foregroundStyle(DiscordColors.ink(0.45)).fixedSize(horizontal:false,vertical:true) }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            trailing
        }
        .padding(.horizontal,10).padding(.vertical,6).frame(minHeight:44)
        .background(on && mark != .fixed ? DiscordColors.veil(0.055) : .clear,in:RoundedRectangle(cornerRadius:11))
        .rowHover(11,veil:0.06,enabled:mark != .fixed)
        .contentShape(Rectangle())
        .animation(.easeOut(duration:0.2),value:on)
    }
    @ViewBuilder private var markView:some View {
        switch mark {
        case .fixed:
            Circle().strokeBorder(DiscordColors.veil(0.18),lineWidth:1.5).overlay { Circle().fill(DiscordColors.veil(0.35)).frame(width:7,height:7) }.frame(width:16,height:16)
        case .radio:
            Circle().strokeBorder(on ? DiscordColors.accent : DiscordColors.veil(0.25),lineWidth:1.5)
                .overlay { if on { Circle().fill(DiscordColors.accent).frame(width:7,height:7) } }.frame(width:16,height:16)
        case .pick:
            ZStack {
                Circle().fill(on ? DiscordColors.accent : .clear)
                if !on { Circle().strokeBorder(DiscordColors.veil(0.25),lineWidth:1.5) }
                if on {
                    if let number { Text("\(number)").designFont(10.5,.heavy).monospacedDigit() } else { DesignIcon("lucide:check",size:11) }
                }
                if live { Ring(done:turnDone,width:1.6,track:DiscordColors.accent.opacity(0.22)).frame(width:23,height:23).animation(turnDone < 0.05 ? nil : .linear(duration:1),value:turnDone) }
            }.foregroundStyle(DiscordColors.onAccent)
        }
    }
}

/// A row of words in a pill, one chosen ("Competitive  Quick Play  Both").
struct WordPicker<Value:Hashable>: View {
    let choices:[(Value,String)]
    let chosen:Value
    let choose:(Value)->Void
    var body:some View {
        HStack(spacing:2) {
            ForEach(choices,id:\.0) { value,label in
                let on=value == chosen
                Button { choose(value) } label: {
                    Text(label).designFont(12,on ? .semibold : .medium).lineLimit(1)
                        .foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.58))
                        .padding(.horizontal,10).frame(height:26)
                        .background(on ? DiscordColors.veil(0.14) : .clear,in:RoundedRectangle(cornerRadius:7))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2).background(DiscordColors.veil(0.05),in:RoundedRectangle(cornerRadius:9))
        .animation(.easeOut(duration:0.2),value:chosen)
    }
}
/// The design's switch: a small track that fills orange, and its label.
struct DesignSwitch: View {
    let label:String
    let on:Bool
    let toggle:()->Void
    var body:some View {
        Button(action:toggle) {
            HStack(spacing:7) {
                Capsule().fill(on ? DiscordColors.accent : DiscordColors.veil(0.16)).frame(width:28,height:16)
                    .overlay(alignment:.leading) { Circle().fill(.white).frame(width:12,height:12).shadow(color:.black.opacity(0.3),radius:1,y:1).offset(x:on ? 14 : 2) }
                Text(label).designFont(12,.semibold).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.6))
            }.frame(height:30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
        .animation(.curve(.out,0.3),value:on)
    }
}

/// Which rank every rank line and the badge show: the player's roles, the highest, or the last one played.
struct RankTiles: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let inputs=studio.inputs(at:Date())
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:5),count:4),spacing:5) {
            ForEach(studio.rankChoices(inputs),id:\.choice) { tile in
                RankTile(tile:tile,on:studio.design.rank == tile.choice)
                    .onTapGesture { if studio.design.rank != tile.choice { studio.edit { $0.rank=tile.choice } } }
                    .pointing(studio) { $0.rank=tile.choice }
            }
        }
    }
}
/// A rank tile: emblem, role, name and what it shows. Last played rolls through the player's ranks.
struct RankTileInfo { let choice:RankChoice;let label:String;let sub:String;let icon:String;let emblem:URL?;var roll:[(icon:String,sub:String)]=[] }
private struct RankTile: View {
    let tile:RankTileInfo
    let on:Bool
    @State private var inside=false
    var body:some View {
        let rolls=tile.roll.count > 1
        VStack(spacing:3) {
            RemoteImage(url:tile.emblem,fill:false) { DesignIcon("ph:medal-fill",size:24).foregroundStyle(DiscordColors.ink(0.3)) }
                .frame(width:32,height:32)
                .overlay(alignment:.bottomTrailing) {
                    Group {
                        if rolls {
                            Rolling(steps:tile.roll.count-1,height:17) {
                                ForEach(Array(tile.roll.enumerated()),id:\.offset) { _,row in DesignIcon(row.icon,size:10).frame(width:17,height:17) }
                            }.foregroundStyle(Color.rgb(255,190,140))
                        } else { DesignIcon(tile.icon,size:10).foregroundStyle(DiscordColors.ink(0.9)) }
                    }
                    .frame(width:17,height:17).background(Color.rgb(52,53,58),in:Circle()).clipShape(Circle())
                    .overlay { Circle().strokeBorder(DiscordColors.stage,lineWidth:2).padding(-2) }
                    .offset(x:6,y:4)
                }
                .padding(.bottom,2)
            Text(tile.label).designFont(12,.semibold).foregroundStyle(on ? DiscordColors.bright : DiscordColors.ink(0.78)).lineLimit(1)
            if rolls {
                Rolling(steps:tile.roll.count-1,height:14) {
                    ForEach(Array(tile.roll.enumerated()),id:\.offset) { _,row in
                        Text(row.sub).designFont(10.5,line:14).foregroundStyle(DiscordColors.ink(0.6)).lineLimit(1).frame(height:14)
                    }
                }
            } else {
                Text(tile.sub).designFont(10.5).foregroundStyle(DiscordColors.ink(0.5)).lineLimit(1)
            }
        }
        .padding(.top,9).padding(.bottom,8).padding(.horizontal,2).frame(maxWidth:.infinity)
        .background(on ? DiscordColors.accent.opacity(0.1) : DiscordColors.veil(0.035),in:RoundedRectangle(cornerRadius:11))
        .overlay { if on { RoundedRectangle(cornerRadius:11).strokeBorder(DiscordColors.accent.opacity(0.7),lineWidth:1.5) } }
        .brightness(inside ? 0.06 : 0)
        .contentShape(Rectangle()).onHover { inside=$0 }
        .animation(.easeOut(duration:0.2),value:on)
    }
}

/// Rows rolling up one at a time, two seconds each; the last repeats the first so the loop has no seam.
struct Rolling<Rows:View>: View {
    let steps:Int
    let height:CGFloat
    @ViewBuilder var rows:Rows
    var body:some View {
        VStack(spacing:0) { rows }
            .keyframeAnimator(initialValue:0.0,repeating:true) { content,phase in content.offset(y:-Self.row(phase,steps)*height) } keyframes:{ _ in
                LinearKeyframe(1.0,duration:2*Double(steps))
            }
            .frame(height:height,alignment:.top).clipped()
    }
    /// The row at a point of the loop, with how far it has eased to the next (the design's dcRoll3, for any number of
    /// rows).
    nonisolated static func row(_ phase:Double,_ steps:Int)->CGFloat {
        let unit=0.99/Double(steps),step=min(Double(steps-1),floor(phase/unit))
        let start=(step+27.0/33)*unit,end=step == Double(steps-1) ? 1 : (step+1)*unit
        if phase <= start { return CGFloat(step) }
        if phase >= end { return CGFloat(step+1) }
        let ease=UnitCurve.bezier(startControlPoint:UnitPoint(x:0.65,y:0),endControlPoint:UnitPoint(x:0.35,y:1))
        return CGFloat(step+ease.value(at:(phase-start)/(end-start)))
    }
}

extension DiscordStudio {
    /// "45 s", "2 min".
    static func paceName(_ seconds:Int)->String { seconds < 60 ? L("{0} s",String(seconds)) : L("{0} min",String(seconds/60)) }
    /// The rank tiles: each role the player has a rank in (every role without a profile), the highest, the last played.
    func rankChoices(_ inputs:CardInputs)->[RankTileInfo] {
        let ranks=inputs.allRanks.map(\.rank),roles=ranks.isEmpty ? CareerRank.Role.allCases : ranks.map(\.role)
        var tiles=roles.map { role in
            let rank=ranks.first { $0.role == role }
            return RankTileInfo(choice:.role(role),label:role.label,sub:rank?.name ?? L("No rank"),icon:role.icon,emblem:rank?.icon)
        }
        tiles.append(RankTileInfo(choice:.highest,label:L("Highest"),sub:L("Your best"),icon:"rc:crown-fill",emblem:inputs.rank(.highest)?.icon))
        tiles.append(RankTileInfo(choice:.lastPlayed,label:L("Last played"),sub:L("Follows you"),icon:"ph:clock-fill",emblem:inputs.rank(.lastPlayed)?.icon,
                                  roll:ranks.count > 1 ? (ranks+[ranks[0]]).map { ($0.role.icon,$0.name) } : []))
        return tiles
    }
}
extension CareerRank.Role {
    var icon:String {
        switch self {
        case .tank: return "rc:shield-fill"
        case .damage: return "ph:sword-fill"
        case .support: return "rc:plus-fill"
        case .open: return "ph:users-three-fill"
        }
    }
}
