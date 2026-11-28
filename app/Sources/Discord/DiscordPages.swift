import SwiftUI
import AppKit

// Settings › Discord's two pages. Your profile: the BattleTag, whether it's public, what Recall reads and where it
// shows. What Recall remembers: the sessions on this Mac, with Erase (ten seconds to undo) and Export.

// MARK: your profile

struct ProfilePage: View {
    @Bindable var studio:DiscordStudio
    @FocusState private var typing:Bool
    var body:some View {
        let state=studio.profileState
        // Short of room, the BattleTag's card and both boxes give up height (the list scrolls).
        FlexColumn(spacing:12) {
            Text(state == .none ? L("Recall reads your career profile from your BattleTag, for ranks, records and heroes in Full and Customize. It needs to be public: in Overwatch, Options › Social › Career Profile Visibility › Public. Only the BattleTag is sent.")
                                : L("Everything Recall reads from your BattleTag, and where it shows on your card. It looks again after you quit Overwatch."))
                .designFont(12.5,line:12.5*1.5,wraps:true).foregroundStyle(DiscordColors.ink(0.65)).fixedSize(horizontal:false,vertical:true)
            // The card comes back at once, as the design's does.
            if studio.tagEditing { tagField } else if !studio.battleTag.isEmpty { tagCard.transition(.identity) }
            if studio.tagEditing && !studio.battleTag.isEmpty {
                HStack(spacing:10) {
                    Text(L("Or stop using a BattleTag. Full and Customize then show only what the game’s log knows."))
                        .designFont(11.5,line:11.5*1.4).foregroundStyle(DiscordColors.ink(0.5)).frame(maxWidth:.infinity,alignment:.leading)
                    PageButton(title:L("Remove"),danger:true) { studio.removeBattleTag() }
                }.padding(.leading,14).padding(.trailing,8).padding(.top,-4).popIn(0.28).transition(.identity)
            }
            if state == .hidden && !studio.battleTag.isEmpty { privateNotice }
            SectionLabel(text:state == .shown ? L("WHAT RECALL READS") : state == .hidden ? L("WHAT IT WOULD READ") : L("WHAT IT CAN READ"))
            ScrollView { factList }.scrollIndicators(.never)
                .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16))
                .clipShape(RoundedRectangle(cornerRadius:16)).flexShrink()
            SectionLabel(text:L("NOT ON THE CARD"))
            FactRow(studio:studio,row:studio.notOnCard(),index:nil)
                .frame(minHeight:0,alignment:.top)
                .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16))
                .clipShape(RoundedRectangle(cornerRadius:16)).flexShrink()
            Color.clear.flexGrow()
            HStack { Spacer();PageButton(title:L("Done")) { studio.closePage() }.background { Button("",action:studio.escape).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true) } }
        }
        .animation(.curve(.out,0.3),value:studio.tagEditing)
        .animation(.curve(.out,0.3),value:studio.openFact)
    }
    private var factList:some View {
        VStack(spacing:0) {
            ForEach(Array(studio.profileFacts().enumerated()),id:\.offset) { index,row in FactRow(studio:studio,row:row,index:index) }
        }
    }
    /// The BattleTag, whether the profile shows, and when Recall last looked.
    private var tagCard:some View {
        HStack(spacing:12) {
            Group {
                if studio.profileState == .hidden { DesignIcon("lucide:lock",size:18).foregroundStyle(DiscordColors.ink(0.55)) }
                else { RemoteImage(url:studio.profile?.identity?.avatar) { DesignIcon("rc:user-fill",size:20).foregroundStyle(DiscordColors.ink(0.4)) } }
            }
            .frame(width:40,height:40).background(DiscordColors.tile).clipShape(RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:2) {
                TagName(tag:studio.battleTag,page:studio.profile?.page)
                Text(studio.profileStatus).designFont(11.5).foregroundStyle(DiscordColors.ink(0.55)).lineLimit(1)
            }.frame(maxWidth:.infinity,alignment:.leading)
            LookAgainButton(studio:studio)
            PageButton(title:L("Change"),small:true) { studio.tagDraft=studio.battleTag;studio.tagError=false;studio.tagEditing=true }
        }
        .padding(.leading,12).padding(.trailing,10).frame(minHeight:40,idealHeight:62,maxHeight:62)
        .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16)).flexShrink()
    }
    /// Typing the BattleTag: Look up (or Return) checks it's a BattleTag and looks the profile up.
    private var tagField:some View {
        HStack(spacing:8) {
            DesignIcon("simple-icons:battledotnet",size:15).foregroundStyle(DiscordColors.ink(0.55))
            TextField(L("Name#1234"),text:$studio.tagDraft)
                .textFieldStyle(.plain).font(LauncherStyle.font(13,.semibold)).autocorrectionDisabled()
                .focused($typing).onAppear { typing=true }
                .onSubmit { studio.saveBattleTag() }.onExitCommand { studio.cancelBattleTag() }
                .onChange(of:studio.tagDraft) { studio.tagError=false }
            // OverFast and Blizzard tell "Pyxee" from "pyxee": a quiet reminder, until an error takes its place.
            if studio.tagError { Text(L("Name#1234")).designFont(11.5).foregroundStyle(Color.rgb(255,130,118)) }
            else { Text(L("Capitals count")).designFont(11.5).foregroundStyle(DiscordColors.ink(0.4)).help(L("Type it as Overwatch shows it: capitals count.")) }
            Button(L("Cancel")) { studio.cancelBattleTag() }.buttonStyle(QuietButtonStyle())
            FillButton(title:L("Look up"),height:30,size:12,radius:8,padding:12,weight:.bold) { studio.saveBattleTag() }
        }
        .padding(.leading,14).padding(.trailing,8).frame(height:52)
        .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16))
        .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(studio.tagError ? Color.rgb(255,99,88).opacity(0.7) : DiscordColors.pick.opacity(0.55),lineWidth:1) }
        .popIn(0.28).transition(.identity)
    }
    private var privateNotice:some View {
        HStack(alignment:.top,spacing:10) {
            DesignIcon("lucide:eye-off",size:15).foregroundStyle(Color.rgb(255,200,120)).padding(.top,1)
            VStack(alignment:.leading,spacing:3) {
                Text(L("Overwatch keeps this profile private")).designFont(12,.semibold,line:12*1.45).foregroundStyle(DiscordColors.body)
                Text(L("So ranks, records and heroes can’t show. Your card still shows what the game’s log knows. To make it public, in Overwatch: Options › Social › Career Profile Visibility › Public. Then Look again."))
                    .foregroundStyle(DiscordColors.ink(0.65)).cssLines(NSFont.systemFont(ofSize:12),12*1.45,wraps:true).fixedSize(horizontal:false,vertical:true)
            }.font(LauncherStyle.font(12))
        }
        // The design's padding inside its one-point border.
        .padding(.horizontal,14).padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading)
        .background(Color.rgb(255,196,92).opacity(0.08),in:RoundedRectangle(cornerRadius:14))
        .overlay { RoundedRectangle(cornerRadius:14).strokeBorder(Color.rgb(255,196,92).opacity(0.18),lineWidth:1) }
    }
}
/// "WHAT RECALL READS": a small heading over a box.
struct SectionLabel: View {
    let text:String
    var body:some View {
        Text(text).designFont(10.5,.bold).tracking(10.5*0.05).foregroundStyle(DiscordColors.ink(0.4))
            .padding(.horizontal,4).padding(.bottom,-4)
    }
}
/// The BattleTag, once found a link to the player's profile on Blizzard's site.
private struct TagName: View {
    let tag:String
    let page:URL?
    @State private var inside=false
    var body:some View {
        let name=Text(verbatim:tag).designFont(15,.bold).foregroundStyle(DiscordColors.body)
        if let page {
            Button { NSWorkspace.shared.open(page) } label: {
                HStack(spacing:4) {
                    name.underline(inside,color:DiscordColors.ink(0.45))
                    DesignIcon("lucide:arrow-up-right",size:13).foregroundStyle(DiscordColors.ink(inside ? 0.75 : 0.4))
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).onHover { inside=$0 }
            .designTip(L("Your profile on Blizzard’s site, where these records come from"))
            .accessibilityHint(L("Your profile on Blizzard’s site, where these records come from"))
        } else { name }
    }
}
/// Look again: busy during a look, then counting down until a look can learn something new.
private struct LookAgainButton: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        TimelineView(.periodic(from:.now,by:1)) { context in
            let left=studio.lookAgainReady(context.date).map { $0.timeIntervalSince(context.date) }
            PageButton(title:L("Look again"),small:true,busy:studio.lookingUp,after:left.map { Duration.seconds(max(1,$0.rounded(.up))).formatted(.time(pattern:.minuteSecond)) }) {
                studio.actions.lookAgain()
            }
            .disabled(studio.lookingUp || left != nil)
        }
    }
}
/// A page's quiet button, or a red one (Remove); a small one can show a spinner.
struct PageButton: View {
    let title:String
    var small=false
    var danger=false
    var busy=false
    var after:String?=nil
    let action:()->Void
    @State private var inside=false
    @Environment(\.isEnabled) private var enabled
    var body:some View {
        Button(action:action) {
            HStack(spacing:6) {
                if busy { ProgressView().controlSize(.mini).tint(DiscordColors.bright) }
                Text(title).designFont(small || danger ? 12 : 13,small || danger ? .semibold : .medium)
                if let after { Text(verbatim:after).designFont(12,.semibold).monospacedDigit().opacity(0.55) }
            }
            .foregroundStyle(danger ? DiscordColors.warning : small ? DiscordColors.bright.opacity(0.88) : DiscordColors.bright)
            .opacity(enabled ? 1 : 0.6)
            .padding(.horizontal,small || danger ? 10 : 16).frame(height:small || danger ? 26 : 30)
            .background(danger ? DiscordColors.danger.opacity(inside ? 0.18 : 0.12) : DiscordColors.veil(small ? (inside ? 0.13 : 0.08) : 0.1),
                        in:RoundedRectangle(cornerRadius:small || danger ? 7 : 15))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside=$0 }
    }
}
private struct QuietButtonStyle: ButtonStyle {
    @State private var inside=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.designFont(12,.semibold).foregroundStyle(inside ? DiscordColors.bright : DiscordColors.ink(0.7))
            .padding(.horizontal,10).frame(height:30).background(inside ? DiscordColors.veil(0.08) : .clear,in:RoundedRectangle(cornerRadius:8))
            .contentShape(Rectangle()).onHover { inside=$0 }
    }
}

/// One thing Recall reads: where it shows and what it says now; open, every fact and how it reads on the card.
struct ProfileFact {
    struct Fact { var text:String;var mark:String?=nil;var markColor:Color?=nil;var after:String?=nil;var sub:String?=nil;var image:URL?=nil }
    let icon:String
    var image:URL?=nil
    let name:String
    var places:[String]=[]
    let facts:[Fact]
    var legend:String?=nil
    /// What Recall counts itself (the hours): marked with Recall's icon, and said under the facts.
    var counted:String?=nil
    var sample:String?=nil
    var sampleLabel:String?=nil
}
private struct FactRow: View {
    @Bindable var studio:DiscordStudio
    let row:ProfileFact
    /// Its place in the list (nil: the "not on the card" box, which doesn't open).
    let index:Int?
    var body:some View {
        let shown=studio.profileState == .shown,open=index != nil && studio.openFact == index
        VStack(alignment:.leading,spacing:0) {
            Button { if shown,let index { studio.openFact=studio.openFact == index ? nil : index } } label: {
                HStack(spacing:12) {
                    Group {
                        if shown,let image=row.image { RemoteImage(url:image) { Color.clear } } else { DesignIcon(row.icon,size:15).foregroundStyle(DiscordColors.ink(0.7)) }
                    }.frame(width:28,height:28).background(DiscordColors.veil(0.06)).clipShape(RoundedRectangle(cornerRadius:8))
                    VStack(alignment:.leading,spacing:3) {
                        HStack(spacing:5) {
                            Text(row.name).designFont(12.5,.semibold).foregroundStyle(DiscordColors.body).fixedSize()
                            if shown && row.counted != nil { AppArtwork(size:14).accessibilityLabel(L("Counted by Recall")) }
                            Spacer(minLength:0)
                            ForEach(row.places,id:\.self) { place in
                                Text(place).designFont(10,.semibold).foregroundStyle(DiscordColors.ink(0.55))
                                    .padding(.horizontal,6).frame(height:17).background(DiscordColors.veil(0.06),in:RoundedRectangle(cornerRadius:5))
                            }
                        }
                        if shown {
                            // Open, the line folds away (its gap stays), as the design's does.
                            factLine.frame(height:open ? 0 : 18,alignment:.top).clipped()
                                .animation(.curve(.css,0.25)) { $0.opacity(open ? 0 : 1) }
                        } else {
                            HStack(spacing:4) {
                                if studio.profileState == .hidden { DesignIcon("lucide:lock",size:11) }
                                Text(studio.profileState == .hidden ? L("Hidden by Overwatch") : studio.battleTag.isEmpty ? L("Needs your BattleTag") : studio.profileState == .missing ? L("No profile with this BattleTag") : L("Not found yet")).designFont(11.5)
                            }.foregroundStyle(DiscordColors.ink(0.4))
                        }
                    }
                    if shown && index != nil {
                        DesignIcon("lucide:chevron-down",size:14).foregroundStyle(DiscordColors.ink(0.4)).rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
                .padding(.leading,14).padding(.trailing,12).padding(.vertical,7).frame(minHeight:52).contentShape(Rectangle())
            }.buttonStyle(.plain).allowsHitTesting(shown && index != nil)
            if open {
                details.popIn(0.32).transition(.identity)
            }
        }
        .opacity(shown ? 1 : 0.7)
        // Each row has the design's one-point line over it (clear over the first).
        .padding(.top,1)
        .overlay(alignment:.top) { if let index,index > 0 { Rectangle().fill(DiscordColors.veil(0.05)).frame(height:1) } }
    }
    /// Every fact on one line, fading out where it runs over (the line never widens the page).
    private var factLine:some View {
        Color.clear.frame(height:18).frame(maxWidth:.infinity)
            .overlay(alignment:.leading) {
                factText.discordFont(12,line:18).foregroundStyle(DiscordColors.ink(0.62)).lineLimit(1).fixedSize()
            }
            .clipped()
            .mask { HStack(spacing:0) { Color.black;LinearGradient(colors:[.black,.clear],startPoint:.leading,endPoint:.trailing).frame(width:44) } }
    }
    /// The facts as one run of text, so their gaps don't round to the pixel one by one.
    private var factText:Text {
        func gap(_ width:CGFloat)->Text { Text(Image(size:CGSize(width:width,height:1)) { _ in }) }
        var line=Text(verbatim:"")
        for (index,fact) in row.facts.enumerated() {
            if index > 0 { line=line.followed(by:gap(6)).followed(by:Text(verbatim:"·").foregroundStyle(DiscordColors.ink(0.62*0.4))).followed(by:gap(6)) }
            line=line.followed(by:Text(verbatim:fact.text))
            if let mark=fact.mark { line=line.followed(by:gap(4)).followed(by:Text(verbatim:mark).font(.discord(11)).tracking(-1).foregroundStyle(fact.markColor ?? DiscordColors.ink(0.45))) }
            if let after=fact.after { line=line.followed(by:gap(4)).followed(by:Text(verbatim:after)) }
            if let sub=fact.sub { line=line.followed(by:gap(4)).followed(by:Text(verbatim:sub).foregroundStyle(DiscordColors.ink(0.62*0.55))) }
        }
        return line
    }
    private var details:some View {
        VStack(alignment:.leading,spacing:9) {
            FlowLayout(spacing:5) {
                ForEach(Array(row.facts.enumerated()),id:\.offset) { _,fact in
                    HStack(spacing:5) {
                        if let image=fact.image { RemoteImage(url:image) { DiscordColors.tile }.frame(width:19,height:19).background(DiscordColors.tile).clipShape(Circle()) }
                        Text(verbatim:fact.text).discordFont(12.5)
                        if let mark=fact.mark { Text(verbatim:mark).discordFont(11).tracking(-1).foregroundStyle(fact.markColor ?? DiscordColors.ink(0.45)) }
                        if let after=fact.after { Text(verbatim:after).discordFont(12.5) }
                        if let sub=fact.sub { Text(verbatim:sub).designFont(10.5).foregroundStyle(DiscordColors.ink(0.45)) }
                    }
                    .foregroundStyle(DiscordColors.text)
                    .padding(.leading,fact.image == nil ? 9 : 4).padding(.trailing,9).frame(height:26)
                    .background(DiscordColors.veil(0.055),in:RoundedRectangle(cornerRadius:8))
                }
            }
            if let legend=row.legend { Text(legend).designFont(11,line:11*1.45,wraps:true).foregroundStyle(DiscordColors.ink(0.45)).fixedSize(horizontal:false,vertical:true) }
            if let counted=row.counted {
                HStack(alignment:.top,spacing:6) {
                    AppArtwork(size:14).padding(.top,1)
                    Text(counted).designFont(11,line:11*1.45,wraps:true).foregroundStyle(DiscordColors.ink(0.45)).fixedSize(horizontal:false,vertical:true)
                }
            }
            if let sample=row.sample {
                HStack(spacing:8) {
                    Text(row.sampleLabel ?? L("On your card")).designFont(11).foregroundStyle(DiscordColors.ink(0.45)).fixedSize()
                    Text(verbatim:sample).discordFont(12.5).foregroundStyle(DiscordColors.text).lineLimit(1)
                        .padding(.horizontal,9).frame(height:24).background(DiscordColors.card,in:RoundedRectangle(cornerRadius:6))
                }
            }
        }
        .padding(.leading,54).padding(.trailing,14).padding(.bottom,13)
    }
}

// MARK: what Recall remembers

struct HistoryPage: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        let rows=studio.sessionRows()
        // As the profile's page: the two boxes give up height when the sessions don't fit.
        FlexColumn(spacing:12) {
            Text(L("Sessions stay on this Mac so your card can say how today or this week went. They never leave it; only your BattleTag goes to OverFast."))
                .designFont(12.5,line:12.5*1.5,wraps:true).foregroundStyle(DiscordColors.ink(0.65)).fixedSize(horizontal:false,vertical:true)
            HStack {
                Text(L("SESSIONS")).designFont(10.5,.bold).tracking(10.5*0.05).foregroundStyle(DiscordColors.ink(0.4)).padding(.horizontal,4)
                Spacer()
                if studio.erased != nil {
                    UndoEraseButton(studio:studio)
                } else if rows.isEmpty {
                    HStack(spacing:5) { DesignIcon("lucide:trash-2",size:12);Text(L("Nothing to erase")).designFont(11.5,.semibold) }
                        .foregroundStyle(DiscordColors.ink(0.35))
                        .padding(.leading,8).padding(.trailing,10).frame(height:24).background(DiscordColors.veil(0.04),in:RoundedRectangle(cornerRadius:7))
                } else {
                    HoldToErase(studio:studio,rows:rows.count)
                }
            }.frame(height:24).padding(.bottom,-4)
            if rows.isEmpty {
                VStack(spacing:4) {
                    DesignIcon("lucide:shield-check",size:20).foregroundStyle(DiscordColors.ink(0.5)).padding(.bottom,2)
                    Text(L("Nothing kept on this Mac")).designFont(13,.semibold).foregroundStyle(DiscordColors.body)
                    Text(studio.erased != nil ? L("Ranks and all-time records come back at the next look.") : L("New sessions show up here after you play."))
                        .designFont(11.5).foregroundStyle(DiscordColors.ink(0.5))
                }
                .frame(maxWidth:.infinity).frame(height:96)
                .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16))
                .popIn(0.4).transition(.identity)
            } else {
                SessionList(studio:studio,rows:rows).flexShrink().transition(.identity)
            }
            SectionLabel(text:L("WHERE IT COMES FROM"))
            // The design's one-point top edge on each row.
            VStack(spacing:0) {
                sourceRow(icon:"lucide:file-text",name:L("The game’s log"),sub:L("When you played and how many matches; never where you are."),opens:false).padding(.top,1)
                Button { studio.openProfile() } label: {
                    sourceRow(icon:"simple-icons:battledotnet",name:L("Your public profile"),sub:L("Records, heroes and rank. Only your BattleTag is sent."),opens:true,height:49)
                        .padding(.top,1).overlay(alignment:.top) { Rectangle().fill(DiscordColors.veil(0.05)).frame(height:1) }
                }.buttonStyle(.plain)
            }
            .frame(minHeight:0,alignment:.top)
            .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16)).clipShape(RoundedRectangle(cornerRadius:16)).flexShrink()
            Color.clear.flexGrow()
            HStack(spacing:8) {
                ExportButton(studio:studio,enabled:!rows.isEmpty)
                Spacer()
                // Esc leaves only when nothing waits on it (it would make a waiting erase final).
                PageButton(title:L("Done")) { studio.closePage() }.background { Button("",action:studio.escape).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true) }
            }
        }
    }
    private func sourceRow(icon:String,name:String,sub:String,opens:Bool,height:CGFloat=50)->some View {
        HStack(spacing:12) {
            DesignIcon(icon,size:15).foregroundStyle(DiscordColors.ink(0.6)).frame(width:30,height:30).background(DiscordColors.veil(0.06),in:RoundedRectangle(cornerRadius:8))
            VStack(alignment:.leading,spacing:1) {
                Text(name).designFont(13,.semibold).foregroundStyle(DiscordColors.body)
                Text(sub).designFont(11.5).foregroundStyle(DiscordColors.ink(0.55)).lineLimit(1)
            }.frame(maxWidth:.infinity,alignment:.leading)
            if opens { DesignIcon("lucide:chevron-right",size:14).foregroundStyle(DiscordColors.ink(0.4)) }
        }
        .padding(.horizontal,14).frame(height:height).contentShape(Rectangle())
        .rowHover(0,veil:opens ? 0.03 : 0,enabled:opens)
    }
}
/// A session in the list: when, what was played, how the rank moved; a mark for each source it came from.
struct SessionRow: Identifiable {
    let id:Int
    let when:String
    let what:String
    let result:String
    var resultMove=0
    let image:URL?
    let fromLog:Bool
    let fromProfile:Bool
}
private struct SessionList: View {
    @Bindable var studio:DiscordStudio
    let rows:[SessionRow]
    @State private var crossed:Double=0
    var body:some View {
        ScrollView {
            TimelineView(.animation(paused:studio.sweep == nil)) { context in
                let swept=studio.sweep.map { context.date.timeIntervalSince($0) }
                LazyVStack(spacing:0) {
                    ForEach(Array(rows.enumerated()),id:\.element.id) { index,row in
                        let struck=max(0,min(1,studio.eraseProgress*(Double(rows.count)+0.6)-Double(index)*0.9))
                        let away=swept.map { DiscordStudio.sweptAway(index,$0) } ?? 0
                        HStack(spacing:12) {
                            Group { if let image=row.image { RemoteImage(url:image) { DiscordColors.tile } } else { GameIcon() } }
                                .frame(width:30,height:30).background(row.image == nil ? .clear : DiscordColors.tile).clipShape(RoundedRectangle(cornerRadius:8))
                            VStack(alignment:.leading,spacing:1) {
                                Text(row.when).designFont(13,.semibold).foregroundStyle(DiscordColors.body)
                                Text(row.what).designFont(11.5).foregroundStyle(DiscordColors.ink(0.55)).lineLimit(1)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            HStack(spacing:3) {
                                if row.fromLog { source("lucide:file-text").designTip(L("From the game’s log")) }
                                if row.fromProfile { source("simple-icons:battledotnet").designTip(L("From your public profile")) }
                            }.frame(width:43,alignment:.trailing)
                            Text(row.result).designFont(12,row.resultMove == 0 ? .medium : .bold).monospacedDigit()
                                .foregroundStyle(row.resultMove > 0 ? Color.rgb(120,225,160) : row.resultMove < 0 ? Color.rgb(255,120,108) : DiscordColors.ink(0.45))
                                .frame(width:88,alignment:.trailing).lineLimit(1)
                        }
                        .opacity(1-0.5*struck)
                        .overlay(alignment:.leading) {
                            Capsule().fill(DiscordColors.danger).frame(height:1.5).shadow(color:DiscordColors.danger.opacity(0.6),radius:3)
                                .scaleEffect(x:struck,anchor:.leading).padding(.horizontal,-2)
                        }
                        .padding(.horizontal,14).frame(height:50)
                        // The design's one-point line over each row (clear over the first).
                        .padding(.top,1)
                        .overlay(alignment:.top) { if index > 0 { Rectangle().fill(DiscordColors.veil(0.05)).frame(height:1) } }
                        .opacity(1-away).offset(x:-36*away)
                        .modifier(PartArrival(trigger:nil,studio.restored ? (ArrivalStart(y:8,opacity:0),Animation.curve(.out,0.42).delay(Double(index)*0.055)) : nil))
                    }
                }
            }
        }
        .scrollIndicators(.never).scrollBounceBehavior(.basedOnSize)
        // Closing once the sessions have gone, to the height of what says there are none.
        .frame(height:studio.sweepClosed ? 96 : nil,alignment:.top)
        .background(DiscordColors.surface,in:RoundedRectangle(cornerRadius:16)).clipShape(RoundedRectangle(cornerRadius:16))
    }
    private func source(_ icon:String)->some View {
        DesignIcon(icon,size:11).foregroundStyle(DiscordColors.ink(0.6)).frame(width:20,height:20).background(DiscordColors.veil(0.06),in:RoundedRectangle(cornerRadius:6))
    }
}
/// Hold two seconds: a red fill sweeps across, the button trembling, and each session is crossed out; letting go puts
/// it back.
private struct HoldToErase: View {
    @Bindable var studio:DiscordStudio
    let rows:Int
    @State private var start:Date?
    var body:some View {
        TimelineView(.animation(paused:start == nil)) { context in
            // Full while the sessions slide away.
            let progress=studio.sweep != nil ? 1 : start.map { min(1,context.date.timeIntervalSince($0)/2) } ?? 0
            let shake=start == nil ? 0 : sin(context.date.timeIntervalSinceReferenceDate*1000/22)*min(1.6,progress*progress*2.4)
            label(progress < 0.06 ? L("Hold to erase") : L("Keep holding…"),fore:DiscordColors.warning)
                .background(DiscordColors.danger.opacity(0.12))
                .overlay(alignment:.leading) {
                    label(progress < 0.06 ? L("Hold to erase") : L("Keep holding…"),fore:.white).background(DiscordColors.danger)
                        .mask(alignment:.leading) { GeometryReader { box in Rectangle().frame(width:box.size.width*progress) } }
                }
                .clipShape(RoundedRectangle(cornerRadius:7))
                .offset(x:shake)
                .onChange(of:progress) { _,value in
                    guard studio.sweep == nil else { return }
                    studio.eraseProgress=value
                    if value >= 1 { start=nil;studio.sweepSessions(rows) }
                }
        }
        .gesture(DragGesture(minimumDistance:0).onChanged { _ in if start == nil && studio.sweep == nil { start=Date() } }.onEnded { _ in
            // Let go too soon, the fill runs back and the sessions are whole again; after the hold, nothing changes.
            guard studio.sweep == nil else { start=nil;return }
            withAnimation(.curve(.out,0.26)) { start=nil }
            withAnimation(.curve(.out,0.3)) { studio.eraseProgress=0 }
        })
        // VoiceOver: one element, said as what it does, with the undo it leaves; the erase is announced.
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(L("Hold to erase")).accessibilityHint(L("Erases what Recall remembers. You have ten seconds to undo."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            studio.eraseHistory()
            AccessibilityNotification.Announcement(L("Erased. You have ten seconds to undo.")).post()
        }
    }
    private func label(_ text:String,fore:Color)->some View {
        HStack(spacing:5) { DesignIcon("lucide:trash-2",size:12);Text(text).designFont(11.5,.semibold) }
            .foregroundStyle(fore)
            .padding(.leading,8).padding(.trailing,10).frame(minWidth:112).frame(height:24)
    }
}
/// "Erased · Undo 9s", its line shrinking with the seconds left.
private struct UndoEraseButton: View {
    @Bindable var studio:DiscordStudio
    var body:some View {
        Button { studio.undoErase() } label: {
            HStack(spacing:5) {
                DesignIcon("lucide:undo-2",size:12)
                Text(L("Erased · Undo")).designFont(11.5,.semibold)
                Text(L("{0}s",String(studio.undoLeft))).designFont(11.5,.semibold).foregroundStyle(DiscordColors.ink(0.5)).monospacedDigit()
            }
            .foregroundStyle(DiscordColors.bright)
            .padding(.leading,8).padding(.trailing,10).frame(height:24)
            .background(DiscordColors.veil(0.08),in:RoundedRectangle(cornerRadius:7))
            .overlay(alignment:.bottomLeading) {
                GeometryReader { box in
                    Rectangle().fill(DiscordColors.danger).frame(width:box.size.width*Double(studio.undoLeft)/10,height:2)
                        .frame(maxHeight:.infinity,alignment:.bottom).animation(.linear(duration:1),value:studio.undoLeft)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius:7))
        }.buttonStyle(.plain)
    }
}
private struct ExportButton: View {
    @Bindable var studio:DiscordStudio
    let enabled:Bool
    @State private var inside=false
    var body:some View {
        Button { studio.exportSessions() } label: {
            HStack(spacing:6) { DesignIcon(studio.exported ? "lucide:check" : "lucide:download",size:14);Text(studio.exported ? L("Saved to Downloads") : L("Export…")).designFont(13,.medium) }
                .foregroundStyle(DiscordColors.ink(!enabled ? 0.3 : studio.exported ? 0.6 : 0.75))
                .padding(.leading,10).padding(.trailing,12).frame(height:30)
                .background(inside && enabled ? DiscordColors.veil(0.06) : .clear,in:Capsule()).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).onHover { inside=$0 }
    }
}

extension DiscordColors {
    /// The pages' boxes.
    static let surface=Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(srgbRed:36/255,green:37/255,blue:41/255,alpha:1) : .white })
}

extension DiscordStudio {
    /// When the profile was last looked up, as briefly as the design says it: "just now", then "2h ago" and on.
    var lookedUpAgo:String? {
        lookedUp.map { Date().timeIntervalSince($0) < 60 ? L("just now") : $0.formatted(.relative(presentation:.named,unitsStyle:.narrow)) }
    }
    /// When Look again can learn something: ten minutes after the last look, or after OverFast's wait; nil when now.
    func lookAgainReady(_ now:Date)->Date? {
        let ready=profileState == .hidden || profileState == .missing || busy ? lookAgainAt : offline ? nil : lookedUp.map { $0.addingTimeInterval(CareerProfile.fresh) }
        return ready.flatMap { $0 > now ? $0 : nil }
    }
    var profileStatus:String {
        if otherAccount { return L("Discord is signed in as another account") }
        if lookingUp { return L("Looking up…") }
        let ago=lookedUpAgo
        switch profileState {
        case .hidden:
            return ago.map { L("Private profile · looked up {0}",$0) } ?? L("Private profile")
        case .shown: return ago.map { L("Public profile · looked up {0}",$0) } ?? L("Public profile")
        case .missing: return ago.map { L("No profile with this BattleTag · looked up {0}",$0) } ?? L("No profile with this BattleTag")
        case .none:
            if busy { return L("Too many lookups · try again in a moment") }
            if offline { return L("OverFast didn’t answer · Recall asks again later") }
            return ago.map { L("Not found yet · looked up {0}",$0) } ?? L("Not found yet")
        }
    }
    /// Look up (or Return): a valid BattleTag is looked up; otherwise the field shows the expected form.
    func saveBattleTag() {
        let tag=tagDraft.trimmingCharacters(in:.whitespaces)
        guard BattleTag.playerID(tag) != nil else { tagError=true;return }
        tagEditing=false;tagError=false
        actions.battleTag(tag)
    }
    func cancelBattleTag() {
        tagEditing=false;tagError=false
        if battleTag.isEmpty { closePage() }
    }
    func removeBattleTag() { actions.battleTag("");tagDraft="";tagEditing=true }

    /// What Recall reads from the profile, row by row, with where it shows; without a public profile the rows say why.
    func profileFacts()->[ProfileFact] {
        let inputs=CardInputs(profile:profile,history:history,launched:Date(),now:Date(),texts:texts),card=profile
        let marks:[String:Color]=["↑":DiscordColors.good,"↟":DiscordColors.good,
                                  "↓":Color.rgb(255,120,110),"↡":Color.rgb(255,120,110)]
        let ranks=inputs.allRanks.map { item in
            let arrow=inputs.arrow(item.rank)
            return ProfileFact.Fact(text:item.rank.role.label,mark:arrow,markColor:marks[arrow],after:item.rank.name)
        }
        func tally(_ t:Tally?)->String? { t.flatMap { $0.played > 0 ? L("{0}–{1}",String($0.won),String($0.lost)) : nil } }
        var records:[ProfileFact.Fact]=[]
        if let comp=tally(card?.totals["competitive"]?.games) { records.append(.init(text:L("Comp {0}",comp),sub:L("this season"))) }
        if let quick=tally(card?.totals["quickplay"]?.games) { records.append(.init(text:L("Quick Play {0}",quick),sub:L("all time"))) }
        if let week=history.session(.week,now:Date()).flatMap({ tally($0.competitive) }) { records.append(.init(text:L("Comp {0}",week),sub:L("this week"))) }
        if let last=tally(card?.last?.competitive) { records.append(.init(text:L("Comp {0}",last),sub:L("last session"))) }
        let top=inputs.topHeroes
        var heroes=top.prefix(8).map { key in ProfileFact.Fact(text:inputs.heroName(key),after:inputs.heroTime[key].map(inputs.hours),image:card?.heroes[key]?.portrait) }
        if top.count > 8 { heroes.append(.init(text:L("+ {0} more",String(top.count-8)))) }
        // Recall's own count of the hours, once it has one (CardInputs.heroTime).
        let counted=history.hours.flatMap { hours in
            profile == nil || hours.heroes.isEmpty ? nil
                : L("Quick Play and Competitive, as your profile has them. Recall has kept the count since {0}, so a new season doesn’t take hours away.",
                    hours.since.formatted(.dateTime.month(.abbreviated).day()))
        }
        let bests=BestLine.allCases.compactMap { line -> ProfileFact.Fact? in
            guard let value=line.value(inputs) else { return nil }
            let number=value.formatted(.number)
            switch line {
            case .eliminations: return .init(text:L("{0} elims",number))
            case .damage: return .init(text:L("{0} damage",number))
            case .healing: return .init(text:L("{0} healing",number))
            case .killStreak: return .init(text:L("{0} kill streak",number))
            case .multikill: return .init(text:L("{0}-kill multikill",number))
            case .new: return nil
            }
        }
        var identity:[ProfileFact.Fact]=[.init(text:L("Player icon"),image:card?.identity?.avatar)]
        if let title=card?.identity?.title { identity.append(.init(text:title,sub:L("title"))) }
        let sample={ (piece:CardPiece) in piece.text(inputs,rank:self.design.rank) }
        return [ProfileFact(icon:"ph:medal-fill",name:L("Ranks"),places:[L("Line 2"),L("Badge")],facts:ranks.isEmpty ? [.init(text:L("No rank this season"))] : ranks,
                            legend:L("Since your last session: ↑ up a division, ↟ two or more, – no change, ↓ down."),sample:sample(.rank(.current))),
                ProfileFact(icon:"ph:sword-fill",name:L("Records"),places:[L("Line 2")],facts:records.isEmpty ? [.init(text:L("No games yet"))] : records,sample:sample(.record(.week,.competitive,winRate:false))),
                ProfileFact(icon:"rc:user-fill",name:L("Heroes and hours"),places:[L("Image"),L("Line 2")],facts:heroes.isEmpty ? [.init(text:L("No heroes yet"))] : heroes,
                            counted:counted,sample:sample(.hero(nil,.hours))),
                ProfileFact(icon:"ph:trophy-fill",name:L("Best games"),places:[L("Line 2")],facts:bests.isEmpty ? [.init(text:L("No bests yet"))] : bests,sample:sample(.best(.eliminations))),
                ProfileFact(icon:"ph:users-three-fill",name:L("Endorsement"),places:[L("Line 2")],
                            facts:[.init(text:card?.identity?.endorsement.map { L("Endorsement level {0}",String($0)) } ?? L("Endorsement level"))],sample:sample(.title(.endorsement))),
                ProfileFact(icon:"lucide:image",image:card?.identity?.avatar,name:L("Player icon and title"),places:[L("Image")],facts:identity,
                            sample:[card?.identity?.name,card?.identity?.title].compactMap { $0 }.joined(separator:" · ").nilIfEmpty,sampleLabel:L("When friends point at the image"))]
    }
    func notOnCard()->ProfileFact {
        ProfileFact(icon:"lucide:image",name:L("Name card"),facts:[.init(text:L("Name card"))])
    }

    /// The sessions kept, newest first: each profile change with the runs it covers, and the runs not yet looked at.
    func sessionRows()->[SessionRow] {
        var rows:[SessionRow]=[],id=0
        let profileHeroes=profile?.heroes ?? [:]
        for change in history.changes.sorted(by:{ $0.at < $1.at }) {
            let runs=history.runs(for:change)
            let hero=change.session.hero.flatMap { profileHeroes[$0] }
            var what=change.session.summary
            if let name=hero?.name { what=L("{0} · {1}",what,name) }
            if runs.isEmpty { what=L("Not on this Mac · {0}",what) }
            let steps=change.steps ?? (change.session.rank == nil ? 0 : change.session.promoted ? 1 : -1)
            let result:String
            if change.session.competitive.played == 0 { result=L("No Comp") }
            else if steps > 0 { result=steps == 1 ? L("↑ 1 division") : L("↑ {0} divisions",String(steps)) }
            else if steps < 0 { result=steps == -1 ? L("↓ 1 division") : L("↓ {0} divisions",String(-steps)) }
            else { result=L("Same rank") }
            rows.append(SessionRow(id:id,when:Self.when(runs.last?.end ?? change.at),what:what,result:result,resultMove:change.session.competitive.played == 0 ? 0 : steps,
                                   image:hero?.portrait,fromLog:!runs.isEmpty,fromProfile:true))
            id+=1
        }
        // Their records come with a look, at Full and Customize with a BattleTag; a run without a match has none.
        let looks=(level == .full || level == .custom) && !battleTag.isEmpty
        for run in history.waiting {
            let matches=run.matches.map { $0 == 1 ? L("1 match") : L("{0} matches",String($0)) } ?? L("Played")
            let waits=looks && run.matches != 0
            let what=run.matches == 0 ? L("No matches") : !waits ? matches
                : nextLook.map { L("{0} · records at {1}",matches,$0.formatted(date:.omitted,time:.shortened)) } ?? L("{0} · records after the next look",matches)
            rows.append(SessionRow(id:id,when:Self.when(run.end),what:what,result:waits ? L("Waiting") : "",image:nil,fromLog:true,fromProfile:false))
            id+=1
        }
        return rows.reversed()
    }
    /// "Just now", "Today, 21:14", "Yesterday", "Thu 23 Oct".
    static func when(_ date:Date,now:Date=Date(),calendar:Calendar = .current)->String {
        if now.timeIntervalSince(date) < 15*60 { return L("Just now") }
        if calendar.isDateInToday(date) { return L("Today, {0}",date.formatted(date:.omitted,time:.shortened)) }
        if calendar.isDateInYesterday(date) { return L("Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
    /// Erases at once, the files too; Undo brings them back from memory for ten seconds, until leaving the page.
    func eraseHistory() {
        guard erased == nil else { return }
        erased=history;history=CareerHistory();undoLeft=10
        actions.erase()
        eraseTimer?.cancel()
        eraseTimer=Task { [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for:.seconds(1))
                guard let self,!Task.isCancelled else { return }
                self.undoLeft-=1
            }
            self?.commitErase()
        }
    }
    /// After a hold: the sessions slide away one after another, the list closes, then they're erased.
    func sweepSessions(_ count:Int) {
        guard sweep == nil,erased == nil else { return }
        let start=Date();sweep=start
        Task { [weak self] in
            try? await Task.sleep(for:.seconds(Self.sweepCloses(count)))
            guard let self,self.sweep == start else { return }
            withAnimation(.curve(.out,0.32)) { self.sweepClosed=true }
            try? await Task.sleep(for:.seconds(0.33))
            if self.sweep == start { self.finishSweep() }
        }
    }
    /// When the list starts to close: 200 ms after the last session started to go.
    static func sweepCloses(_ count:Int)->Double { 0.12+Double(min(count,8))*0.055+0.2 }
    /// How far session `index` has slid `elapsed` seconds in: from 120 ms, 55 ms apart, over 280 ms, easing in.
    static func sweptAway(_ index:Int,_ elapsed:Double)->Double { Ease.bezier(0.5,0,0.75,0)((elapsed-0.12-Double(index)*0.055)/0.28) }
    /// The sweep ends, or is cut short by leaving the page: the sessions are erased.
    func finishSweep() {
        guard sweep != nil else { return }
        sweep=nil;sweepClosed=false;eraseProgress=0
        eraseHistory()
    }
    func undoErase() {
        eraseTimer?.cancel();eraseTimer=nil
        guard let erased else { return }
        history=erased;actions.restore()
        self.erased=nil;undoLeft=0;restored=true
    }
    /// The ten seconds are over (or the page closed): what was kept to undo goes.
    func commitErase() {
        eraseTimer?.cancel();eraseTimer=nil
        guard erased != nil else { return }
        erased=nil;undoLeft=0
        actions.forget()
    }
    /// The sessions as a spreadsheet in Downloads.
    func exportSessions() {
        guard actions.export() != nil else { return }
        withAnimation { exported=true }
        Task { [weak self] in try? await Task.sleep(for:.seconds(2.6));withAnimation { self?.exported=false } }
    }
}
