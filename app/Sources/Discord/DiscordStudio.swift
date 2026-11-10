import SwiftUI
import Observation

// Settings › Discord's state: the cards, the one being changed, and the preview, made by the same engine as Discord's
// card. Changes apply at once (removals can be undone); a ready-made card is copied on its first change.

@MainActor @Observable final class DiscordStudio {
    enum Screen: Equatable { case home,editor,profile,history }
    /// The parts of the card Customize changes, in the rail's order (the game's name can't change).
    enum Slot: String, CaseIterable { case picture,badge,lineOne,lineTwo,timer,buttons,party }
    /// What the preview shows when the game isn't running: the menus or a match, in the group's voice or not.
    enum Scene: CaseIterable { case menus,match,menusVoice,matchVoice }
    enum Device { case desktop,phone }
    /// Line 2's topics, as Customize's tiles.
    enum Topic: String, CaseIterable { case highlights,moment,rank,record,hero,best,tonight,title }
    enum ImageTab: CaseIterable { case suggested,heroes,extra }
    /// What the profile allows: its lines need it public. `missing`: no player has this BattleTag.
    enum ProfileState { case none,hidden,missing,shown }
    /// Whether a line can say something now, and if not, why (the note after it).
    enum Availability { case ok,profile,match,news,later,locked }

    // MARK: what the app knows (AppModel keeps these current)
    var level:DiscordPresenceLevel = .standard
    var power=true
    var battleTag=""
    var profileState:ProfileState = .none
    var profile:CareerCard?
    var history=CareerHistory()
    var lookedUp:Date?
    var lookingUp=false
    /// The look Recall makes a while after the game closes, while that's to come.
    var nextLook:Date?
    /// A private profile: OverFast looks at it again only after this, so Look again learns nothing sooner.
    var lookAgainAt:Date?
    /// Discord is signed in as another account than the one the BattleTag was entered with: no profile on its card.
    var otherAccount=false
    /// The last look got no answer (and nothing was kept to show), or was held back for asking too often.
    var offline=false
    var busy=false
    var texts=PresenceTexts.app
    /// The game's own facts while it runs: the preview follows them instead of the scene chosen here.
    var live:(place:PresenceState,voice:GroupVoice?,matches:Int,launched:Date)?

    // MARK: the cards
    var shelf:DiscordCardShelf {
        didSet {
            guard shelf != oldValue else { return }
            changed(shelf)
            // The toast's Undo goes back from its own change only: any later one takes it off.
            if toast?.undo != nil && shelf != undoFrom { toast?.undo=nil }
        }
    }
    /// Called with every change to the cards, to keep and use them (AppModel).
    @ObservationIgnored var changed:(DiscordCardShelf)->Void={ $0.save() }

    // MARK: where the player is
    /// Discord's pages show over Settings: from General's Discord card (the header folds into their breadcrumb) or the
    /// home screen.
    var open=false {
        didSet {
            guard open != oldValue else { return }
            folds+=1
            fold=Fold(header:true,opening:open,count:folds,studio:false,title:"",at:Date(),frames:foldFrames)
        }
    }
    func enter(folding:Bool=true) { open=true;if !folding { fold=nil } }
    /// Back to Settings' tabs (the breadcrumb's "Settings"): the header opens again, and Discord's pages close as Done does.
    func leave() { open=false;closePage() }
    var screen:Screen = .home {
        didSet {
            came=(oldValue,gallery)
            // Customize's own morph, to and from Discord's page, on the computer's card.
            if open,device == .desktop,Set([screen,oldValue]) == [.home,.editor] {
                folds+=1
                let title=oldValue == .editor && gallery ? L("My cards") : design.shownName
                // Where it starts and lands; Discord's page's own as they were when Customize opened (the page is still
                // on its way back).
                if oldValue == .home { homeFrames=foldFrames.filter { Self.homeParts.contains($0.key) } }
                let frames=screen == .home ? foldFrames.merging(homeFrames) { _,kept in kept } : foldFrames
                fold=Fold(header:false,opening:screen == .editor,count:folds,studio:true,title:title,at:Date(),frames:frames)
            }
        }
    }
    /// The screen before this one, and whether My cards was open on it: where what comes in starts out (DiscordPages).
    private(set) var came:(screen:Screen,gallery:Bool)=(.home,false)
    /// Settings' header folding into Discord's breadcrumb (HeaderFold), or Customize's morph (StudioMorph): which way,
    /// the title it carries, when it started; gone once played.
    struct Fold: Equatable { let header:Bool;let opening:Bool;let count:Int;let studio:Bool;let title:String;let at:Date;let frames:[HeaderFold.Text:CGRect] }
    var fold:Fold?
    /// How many folds there have been: what the fold's clock counts (FoldClock).
    private(set) var folds=0
    /// Where what travels as the header folds is, and what it passes, in the sheet (LauncherStyle.sheetSpace).
    @ObservationIgnored var foldFrames:[HeaderFold.Text:CGRect]=[:]
    /// Discord's page's parts of Customize's morph, as they were when Customize last opened.
    @ObservationIgnored private var homeFrames:[HeaderFold.Text:CGRect]=[:]
    private static let homeParts:Set<HeaderFold.Text>=[.customize,.levelRow,.shellHome]
    var gallery=false
    var galleryIndex:Int?
    /// My cards' last move and its direction, for the carousel: a step, a card deleted (the next comes in from its
    /// side), or put back.
    struct GallerySlide: Equatable {
        enum Kind { case step,delete,restore }
        let id=UUID();let way:CGFloat;var moving=true;var kind=Kind.step
    }
    var gallerySlide:GallerySlide?
    var slot:Slot = .lineTwo
    var openLine:Int?
    var topic:Topic = .rank
    var hero:String?
    var mode:RecordMode = .competitive
    var winRate=false
    var allHeroes=false
    var imageTab:ImageTab = .suggested
    var role:CareerRank.Role = .tank
    var device:Device = .desktop { didSet { tips.phone=device == .phone } }
    var scene:Scene = .menus
    /// The scene before the Party part switched the preview to the group's voice.
    @ObservationIgnored private var sceneBeforeParty:Scene?
    var example=false
    /// A change shown on the card while the pointer rests on it, not yet made.
    var preview:DiscordCardDesign? { didSet { if preview == nil { previewNews=false } } }
    /// Moments shown as if they had just happened (pointing at one).
    var previewNews=false
    /// The card held at a turn (an item clicked in a list), until something else is chosen.
    var held:Int?
    /// How far the preview's clock was moved on (a dot on the card was clicked).
    var shift:TimeInterval=0
    var toast:(text:String,undo:DiscordCardShelf?)?
    /// A card just deleted in My cards, while it can be undone (its button shows Undo, counting down).
    struct DeleteUndo {
        static let window:TimeInterval=6
        /// How long Undo takes to spin away once its seconds have run out.
        static let spin:TimeInterval=0.9
        /// A deleted card, its place, and the card used in its place: Undo puts back that card alone.
        let card:DiscordCardDesign
        let mine:Int?
        let replacedBy:String?
        let place:Int
        let text:String
        let at=Date()
        /// When its seconds ran out, while it spins away.
        var leaving:Date?
        var until:Date { at.addingTimeInterval(Self.window) }
    }
    var deleteUndo:DeleteUndo?
    var sharing=false
    var importing=false
    var importDraft=""
    var importFailed=false { didSet { if !importFailed { importNewer=false } } }
    /// The code is a newer Recall's (importFailed too).
    var importNewer=false
    var copied=false
    var renaming:String?
    var renameDraft=""
    // The pages: the BattleTag being typed, the profile row opened, erasing (with its ten seconds to undo).
    var tagEditing=false
    var tagDraft=""
    var tagError=false
    var openFact:Int?
    var erased:CareerHistory?
    /// How far a hold to erase has gone (0 to 1): the sessions are crossed out one after another.
    var eraseProgress:Double=0
    /// When the sessions began to slide away, a hold to erase done; whether their list has closed since.
    var sweep:Date?
    var sweepClosed=false
    /// The sessions came back with Undo: they pop in again, one after another.
    var restored=false
    var undoLeft=0
    var exported=false
    /// Customize's "Point at pictures" goes once a tooltip on the card has shown, until Recall opens again.
    var hoverSeen=false
    /// Earned lines the player has unlocked with their key.
    var unlocked=Set((UserDefaults.standard.stringArray(forKey:"discordUnlocked") ?? []).map(CardPiece.stableKey)) { didSet { UserDefaults.standard.set(Array(unlocked).sorted(),forKey:"discordUnlocked") } }
    @ObservationIgnored let tips=DesignTips()
    /// The easter eggs on the pop-out's picture and status line.
    @ObservationIgnored let profileFun=ProfileFun()
    /// When Settings opened: the preview's game opened 42:18 before and its match 3:12 before, so its timers read like
    /// a session's.
    @ObservationIgnored private var opened=Date()
    var previewMatchStart:Date { opened.addingTimeInterval(-192) }
    func settingsOpened() { opened=Date();fold=nil }
    /// Settings closing: it opens on its tabs next time; an erase waiting to be undone happens now.
    func settingsClosed() { closePage();open=false;fold=nil }
    @ObservationIgnored private var toastEnds:Task<Void,Never>?
    @ObservationIgnored private var undoFrom:DiscordCardShelf?
    @ObservationIgnored private var undoEnds:Task<Void,Never>?
    @ObservationIgnored private var pointing:Task<Void,Never>?
    @ObservationIgnored var eraseTimer:Task<Void,Never>?
    /// When the gallery's card started playing.
    private var galleryStart=Date()
    /// Customize just picked on Discord's page: where its word is, for the sparks into the card (LevelFlow), and when.
    struct LevelFlowStart: Equatable { let id=UUID();let from:CGRect;let at:Date }
    var levelFlow:LevelFlowStart?
    /// Where the card is on Discord's page, for the light to land on.
    @ObservationIgnored var cardFrame=CGRect.zero

    init(shelf:DiscordCardShelf=DiscordCardShelf()) {
        self.shelf=shelf
        tips.discordTipShown={ [weak self] in if self?.hoverSeen == false { self?.hoverSeen=true } }
    }

    // MARK: what the player asks of the app (AppModel answers)

    struct Actions {
        var level:(DiscordPresenceLevel)->Void={ _ in }
        var power:(Bool)->Void={ _ in }
        var battleTag:(String)->Void={ _ in }
        var lookAgain:()->Void={}
        var erase:()->Void={}
        /// Undo within the ten seconds: what was erased comes back; done: what was kept for it goes.
        var restore:()->Void={}
        var forget:()->Void={}
        var export:()->URL?={ nil }
    }
    @ObservationIgnored var actions=Actions()
    func setPower(_ on:Bool) { power=on;offSince=on ? nil : Date();actions.power(on) }
    /// When the card was turned off here.
    private var offSince:Date?
    /// The time Discord's page shows: off, it stays where it was, so nothing on it runs.
    func homeTime(_ now:Date)->Date { power ? now : offSince ?? opened }
    /// A level from the line under the card. Customize picked shows the card in use; picked again, it opens the editor.
    func choose(_ level:DiscordPresenceLevel) {
        if !power { setPower(true) }
        if self.level != level { self.level=level;actions.level(level) } else if level == .custom { openEditor() }
    }
    /// Opening Customize changes nothing: the level moves to Custom only with a real change (edit).
    func openEditor() {
        screen = .editor;gallery=false;galleryIndex=nil;preview=nil;held=nil;openLine=nil;shift=0
    }
    func closePage() {
        finishSweep();commitErase()
        finishRename();pointing?.cancel();eraseProgress=0;example=false
        screen = .home;gallery=false;preview=nil;held=nil;openLine=nil;sharing=false;importing=false;shift=0
        if let before=sceneBeforeParty,live == nil { scene=before };sceneBeforeParty=nil
    }
    func openProfile() {
        pointing?.cancel()
        screen = .profile;preview=nil;held=nil;openLine=nil;openFact=nil
        tagEditing=battleTag.isEmpty;tagDraft=battleTag;tagError=false
    }
    func openHistory() { screen = .history;exported=false;restored=false;eraseProgress=0 }

    // MARK: the card shown

    /// The card being changed: the one in use.
    var design:DiscordCardDesign { shelf.inUse }
    /// What the preview shows: the gallery's card, a change being pointed at, or the card in use. Full shows Default.
    var shown:DiscordCardDesign {
        if gallery,let item=galleryItem { return item.design }
        if let preview { return preview }
        if screen == .home && level == .full { return .standard }
        return design
    }
    var usesExample:Bool { example && profileState != .shown }
    func inputs(at now:Date)->CardInputs {
        var inputs=CardInputs(launched:opened.addingTimeInterval(-2538),now:now,texts:texts)
        if let live {
            inputs.place=live.place;inputs.voice=live.voice;inputs.matches=live.matches;inputs.launched=live.launched
        } else {
            let match=scene == .match || scene == .matchVoice
            inputs.place=match ? .match(since:previewMatchStart) : .menu
            if scene == .menusVoice || scene == .matchVoice { inputs.voice=GroupVoice(count:3,channel:"preview",party:"preview") }
            inputs.matches=match ? 4 : 3
        }
        if usesExample { inputs.profile=Self.exampleProfile;inputs.history=Self.exampleHistory(now) }
        else { inputs.profile=profileState == .shown ? profile : nil;inputs.history=history }
        inputs.tagName=usesExample ? Self.exampleName : battleTag.split(separator:"#").first.map(String.init)
        if previewNews { inputs=withNews(inputs) }
        return inputs
    }
    /// What the lines would say in the menus right after a session, with a public profile: how Customize's lists show
    /// them.
    func sampleInputs(at now:Date)->CardInputs {
        var inputs=inputs(at:now)
        inputs.place = .menu;inputs.voice=nil
        if inputs.profile == nil { inputs.profile=Self.exampleProfile;inputs.history=Self.exampleHistory(now);inputs.tagName=inputs.tagName ?? Self.exampleName }
        return withNews(inputs)
    }
    /// The inputs with something that just happened: a rank up, a new best, a season high and a hero milestone.
    private func withNews(_ base:CardInputs)->CardInputs {
        guard let profile=base.profile,base.news == nil || base.news?.session.rank == nil else { return base }
        var inputs=base,session=profile.last ?? LastSession()
        let rank=profile.rank ?? profile.ranks.first
        session.rank=rank;session.promoted=true
        session.best=profile.totals.values.compactMap { $0.bests["eliminations_most_in_game"] }.max().map { CareerBest(key:"eliminations_most_in_game",value:$0) }
        var change=ProfileChange(at:base.launched.addingTimeInterval(-3600),season:profile.season,session:session,before:[:],after:[:])
        change.rankSteps=1;change.seasonHigh=rank
        if let top=inputs.topHeroes.first,let seconds=inputs.heroTime[top] {
            let hours=seconds/3600
            change.milestone=ProfileChange.Milestone(hero:top,hours:[100,50,25,10].first { $0 <= hours } ?? 10)
        }
        inputs.history.changes.append(change)
        inputs.history.runs.removeAll { $0.start > change.at }
        return inputs
    }
    /// The card at a moment, as Discord would get it; off, the one it would get (nothing is sent, and the stage is
    /// covered).
    func activity(at now:Date)->[String:Any] {
        let inputs=inputs(at:now)
        switch screen == .home ? level : .custom {
        case .normal,.live:
            return PresenceCard.activity(facts:PresenceFacts(place:inputs.place,voice:inputs.voice),level:level,launched:inputs.launched,texts:texts)
        default: return shown.activity(inputs,turn:turn(at:now))
        }
    }

    // MARK: the clock

    /// The turn the preview shows: held, or the clock's (moved by a click on the dots). In My cards, every 3 seconds
    /// from the first.
    func turn(at now:Date)->Int {
        if let held { return held }
        if gallery { return Int(max(0,now.timeIntervalSince(galleryStart)))/Self.galleryPace }
        return shown.turn(at:now.addingTimeInterval(shift))
    }
    static let galleryPace=3
    /// How far through its turn the card is (1 while held), for the rings.
    func turnDone(at now:Date)->Double {
        guard held == nil else { return 1 }
        if gallery { return Double(Int(max(0,now.timeIntervalSince(galleryStart)))%Self.galleryPace+1)/Double(Self.galleryPace) }
        let pace=max(shown.pace,DiscordCardDesign.shortestPace)
        return Double(Int(now.addingTimeInterval(shift).timeIntervalSince1970)%pace+1)/Double(pace)
    }
    /// The turns before the card repeats itself: every list back where it started.
    func loopLength(at now:Date)->Int {
        let lists=DiscordCardDesign.Shown(shown,inputs(at:now),turn:turn(at:now))
        func gcd(_ a:Int,_ b:Int)->Int { b == 0 ? a : gcd(b,a%b) }
        return [lists.lineOne.count,lists.lineTwo.count,lists.pictures.count,lists.badges.count].filter { $0 > 0 }.reduce(1) { $0/gcd($0,$1)*$1 }
    }
    /// The card's dots: show the k-th turn of its loop (held while a list's item is held; the clock goes on from it otherwise).
    func jump(to k:Int,at now:Date) {
        let length=loopLength(at:now),now_=turn(at:now),target=now_+((k-now_%length)%length+length)%length
        if held != nil { held=target;return }
        if gallery { galleryStart=galleryStart.addingTimeInterval(-TimeInterval((target-now_)*Self.galleryPace));return }
        shift+=TimeInterval((target-now_)*max(shown.pace,DiscordCardDesign.shortestPace));preview=nil
    }
    /// Holds the card on the k-th item of a list of this many (the first turn from now that shows it).
    private func hold(_ k:Int,of count:Int) {
        guard count > 0 else { return }
        let now=turn(at:Date())
        held=(0..<count).map { now+$0 }.first { $0%count == k } ?? now;preview=nil
    }
    /// Holds the card on one of its own pictures, if it shows now (one with nothing to show is left out).
    func hold(picture index:Int) {
        let now=Date(),places=DiscordCardDesign.Shown(design,inputs(at:now),turn:turn(at:now)).picturePlaces
        if let k=places.firstIndex(of:index) { hold(k,of:places.count) }
    }

    // MARK: changing the card

    /// Changes the card in use, copying a ready-made one first. With `said`, or a copy made, the toast says what
    /// happened and offers Undo.
    func edit(_ change:(inout DiscordCardDesign)->Void,said:String?=nil) {
        pointing?.cancel()
        // A click that changes nothing copies nothing and moves no level.
        var probe=shelf.inUse;change(&probe)
        guard probe != shelf.inUse else { return }
        if level != .custom { level = .custom;actions.level(.custom) }
        let before=shelf
        var card=shelf.inUse,copied:String?=nil
        if card.readyMade {
            copied=card.shownName
            card.name=card.id == "default" ? L("My card") : L("My {0}",card.shownName)
            card.id=UUID().uuidString
        }
        change(&card)
        if let index=shelf.mine.firstIndex(where:{ $0.id == card.id }) { shelf.mine[index]=card } else { shelf.mine.append(card) }
        shelf.chosen=card.id;preview=nil;previewNews=false
        if let copied { say(L("Saved as “{0}”. {1} stays as it is.",card.name,copied),undo:before) } else if let said { say(said,undo:before) }
    }
    func undo() { if let before=toast?.undo { shelf=before };say(L("Undone")) }
    func say(_ text:String,undo:DiscordCardShelf?=nil) {
        toast=(text,undo);undoFrom=shelf;toastEnds?.cancel()
        // VoiceOver hears it too, with the way back when there is one.
        AccessibilityNotification.Announcement(undo == nil ? text : L("{0}. Undo is in the message.",text)).post()
        toastEnds=Task { [weak self] in try? await Task.sleep(for:.seconds(4.5));if !Task.isCancelled { self?.toast=nil } }
    }
    /// Shows a change on the card once the pointer rests on it (sooner while another change shows).
    func point(news:Bool=false,_ change:@escaping (inout DiscordCardDesign)->Void) {
        pointing?.cancel()
        let wait=preview == nil ? 320 : 90
        pointing=Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(wait))
            guard let self,!Task.isCancelled else { return }
            var card=self.design;change(&card);self.preview=card;self.previewNews=news
        }
    }
    func stopPointing() {
        pointing?.cancel()
        pointing=Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(170))
            guard let self,!Task.isCancelled else { return }
            self.preview=nil;self.previewNews=false
        }
    }

    /// A part picked on the card or in the rail. The party's part shows the group's voice while it's open.
    func pick(_ slot:Slot) {
        guard !gallery else { return }
        if slot == .party,self.slot != .party,live == nil,scene == .menus || scene == .match {
            sceneBeforeParty=scene;scene=scene == .match ? .matchVoice : .menusVoice
        } else if slot != .party,let before=sceneBeforeParty,live == nil { scene=before;sceneBeforeParty=nil }
        pointing?.cancel()
        self.slot=slot;openLine=nil;held=nil;preview=nil
    }

    // Line 2: a click makes a line the only one (or changes the open one); holding adds it, or takes it out.
    func onlyLine(_ piece:CardPiece) {
        if let open=openLine,open < design.lineTwo.count {
            // A piece already elsewhere in the list: the two lines swap places, rather than one repeating.
            if let other=design.lineTwo.firstIndex(where:{ $0.piece == piece }),other != open {
                edit { $0.lineTwo.swapAt(open,other) };openLine=other;holdOpenLine();return
            }
            // The second piece stays only where it still can (not after Dynamic or its own topic, and short enough).
            let sample=sampleInputs(at:Date()),main=piece.text(sample,rank:design.rank) ?? piece.label
            let keeps=design.lineTwo[open].second.map { second in seconds(for:piece,main:main,inputs:sample).contains { $0.piece == second } } ?? true
            edit { $0.lineTwo[open].piece=piece;if !keeps || piece == .highlights { $0.lineTwo[open].second=nil } }
            return
        }
        guard !(design.lineTwo.count == 1 && design.lineTwo[0].piece == piece) else { return }
        let several=design.lineTwo.count > 1
        edit({ $0.lineTwo=[CardLine(piece:piece)] },said:several ? L("Now only “{0}”. Hold a line to add it instead.",piece.label) : nil)
    }
    func toggleLine(_ piece:CardPiece) {
        if let index=design.lineTwo.firstIndex(where:{ $0.piece == piece }) {
            edit({ $0.lineTwo.remove(at:index);if $0.lineTwo.isEmpty { $0.lineTwo=[CardLine(piece:.highlights)] } },said:L("Removed it"))
        } else if design.lineTwo.count < 6 { edit { $0.lineTwo.append(CardLine(piece:piece)) } }
    }
    /// The line that was there when ✕ was shown: a second click that lands after the list moved removes nothing more.
    func removeLine(_ index:Int,_ line:CardLine) {
        guard design.lineTwo.indices.contains(index),design.lineTwo[index] == line else { return }
        edit({ $0.lineTwo.remove(at:index);if $0.lineTwo.isEmpty { $0.lineTwo=[CardLine(piece:.highlights)] } },said:L("Removed it"))
        openLine=nil;held=nil
    }
    func moveLine(from:Int,to:Int) {
        let lines=design.lineTwo.indices
        guard from != to,lines.contains(from),lines.contains(to) else { return }
        edit { $0.lineTwo.move(fromOffsets:IndexSet(integer:from),toOffset:to > from ? to+1 : to) }
        // The open line stays open wherever it went, and the card stays on it.
        if let open=openLine { openLine=Self.moved(open,from:from,to:to);holdOpenLine() }
    }
    /// Where an item of a list is after another one moved from one place to another.
    static func moved(_ index:Int,from:Int,to:Int)->Int {
        if index == from { return to }
        if from < index && index <= to { return index-1 }
        if to <= index && index < from { return index+1 }
        return index
    }
    /// Holds the card on the open line, wherever it is in the list now.
    private func holdOpenLine() {
        guard let open=openLine,design.lineTwo.indices.contains(open) else { return }
        let now=Date(),shown=DiscordCardDesign.Shown(design,inputs(at:now),turn:turn(at:now)),piece=design.lineTwo[open].piece
        if let place=shown.lineTwo.firstIndex(where:{ $0.piece == piece }) { hold(place,of:shown.lineTwo.count) } else { held=nil }
    }
    func setSecond(_ piece:CardPiece?,line index:Int) { edit { $0.lineTwo[index].second=piece } }
    /// Opens a line in the list (and holds the card on it), or closes it again.
    func openLineToggle(_ index:Int,shown:DiscordCardDesign.Shown) {
        if openLine == index { closeLine();return }
        openLine=index;preview=nil
        let piece=design.lineTwo[index].piece
        topic=piece.topic
        if case .hero(let key,_)=piece { hero=key }
        if case .record(_,let mode,let rate)=piece { self.mode=mode;winRate=rate }
        if let place=shown.lineTwo.firstIndex(where:{ $0.piece == piece }) { hold(place,of:shown.lineTwo.count) } else { held=nil }
    }
    func closeLine() { openLine=nil;held=nil;preview=nil }
    /// Line 1's phrase: its words (the blank kept when it's the same kind), then what fills the blank.
    func choosePhrase(_ words:LinePhrase.Words) {
        let kept=design.phrase.flatMap { $0.words.kind == words.kind ? $0.blank : nil } ?? .auto
        edit { card in
            card.phrase=LinePhrase(words:words,blank:kept)
            if !card.lineOne.contains(.phrase) { card.lineOne=[.phrase] }
        }
    }
    /// The game closed: a phrase about tonight comes off the card ("Last game" isn't true tomorrow).
    func tonightEnded() {
        guard design.phrase?.words.tonight == true,let index=shelf.mine.firstIndex(where:{ $0.id == shelf.chosen }) else { return }
        shelf.mine[index].phrase=nil;shelf.mine[index].lineOne.removeAll { $0 == .phrase }
        if shelf.mine[index].lineOne.isEmpty { shelf.mine[index].lineOne=[.name] }
    }
    func fillPhrase(_ blank:LinePhrase.Blank) {
        guard let phrase=design.phrase else { return }
        edit { $0.phrase=LinePhrase(words:phrase.words,blank:blank) }
    }
    /// A hero for the Hero lines (nil: the most played); an open hero line changes with it.
    func chooseHero(_ key:String?) {
        hero=key
        if let open=openLine,design.lineTwo.indices.contains(open),case .hero(_,let line)=design.lineTwo[open].piece { edit { $0.lineTwo[open].piece = .hero(key,line) } }
    }
    /// A record's modes or win rate; an open record line changes with them.
    func setRecord(mode:RecordMode,winRate:Bool) {
        self.mode=mode;self.winRate=winRate
        if let open=openLine,design.lineTwo.indices.contains(open),case .record(let period,_,_)=design.lineTwo[open].piece {
            edit { $0.lineTwo[open].piece = .record(period,mode,winRate:winRate && mode != .both) }
        }
    }
    func unlock(_ piece:CardPiece,_ sample:CardInputs) {
        unlocked.insert(piece.key)
        say(L("Unlocked “{0}”. Click to use it, or hold to add it.",sampleText(piece,sample)))
    }

    // The picture: following Line 2, or a list of its own.
    func followLineTwo() { edit({ $0.pictures=nil },said:design.pictures.map { $0.count > 1 } == true ? L("The picture follows Line 2 now") : nil) }
    func ownPictures() { edit { $0.pictures=$0.pictures ?? [.playerIcon] } }
    func movePicture(from:Int,to:Int) {
        guard let pictures=design.pictures,from != to,pictures.indices.contains(from),pictures.indices.contains(to) else { return }
        let shownBefore=held.map { $0%pictures.count }
        edit { $0.pictures?.move(fromOffsets:IndexSet(integer:from),toOffset:to > from ? to+1 : to) }
        // A picture the card was held on stays on the card.
        if let shownBefore { hold(picture:Self.moved(shownBefore,from:from,to:to)) }
    }

    // Pictures, badges, Line 1: a click makes an item the only one; holding adds it (up to `most`) or takes it out
    // (never the last).
    func only<T:Equatable>(_ item:T,in list:WritableKeyPath<DiscordCardDesign,[T]>) {
        let several=design[keyPath:list].count > 1
        if design[keyPath:list] != [item] { edit({ $0[keyPath:list]=[item] },said:several ? L("Now only this one. Hold one to add it instead.") : nil) }
    }
    func toggle<T:Equatable>(_ item:T,in list:WritableKeyPath<DiscordCardDesign,[T]>,most:Int=6) {
        let removing=design[keyPath:list].contains(item)
        edit({ card in
            if let index=card[keyPath:list].firstIndex(of:item) { if card[keyPath:list].count > 1 { card[keyPath:list].remove(at:index) } }
            else if card[keyPath:list].count < most { card[keyPath:list].append(item) }
        },said:removing ? L("Removed it") : nil)
    }
    func nextPace() {
        let paces=DiscordCardDesign.paces,index=paces.firstIndex(of:design.pace) ?? 0
        edit { $0.pace=paces[(index+1)%paces.count] }
    }

    // MARK: what the lists say

    func availability(_ piece:CardPiece,_ i:CardInputs)->Availability {
        if piece.topic == .moment {
            if i.profile == nil && piece != .moment(.comeback) { return .profile }
            if i.inMatch { return .match }
            return piece.text(i,rank:design.rank) == nil ? .news : .ok
        }
        if piece.needsProfile && i.profile == nil { return .profile }
        if let progress=piece.progress(i),progress.done < 1 { return .locked }
        if i.inMatch && !piece.safeInMatch { return .match }
        return piece.text(i,rank:design.rank) == nil ? .later : .ok
    }
    func note(_ availability:Availability)->(text:String,icon:String)? {
        switch availability {
        case .ok: return nil
        // Shown as Battle.net's mark alone (NoteMark), the words when it's pointed at.
        case .profile: return (profileState == .hidden ? L("Profile is private") : battleTag.isEmpty ? L("Needs your BattleTag") : profileState == .missing ? L("No profile with this BattleTag") : L("Not found yet"),"simple-icons:battledotnet")
        case .match: return (L("Not in a match"),"lucide:swords")
        case .news: return (L("When it happens"),"rc:live")
        case .later: return (L("After a session"),"lucide:hourglass")
        case .locked: return (L("Not earned yet"),"lucide:lock")
        }
    }
    /// What a line of the card's list says: now, or what it would say (Dynamic is just its name then).
    func lineText(_ line:CardLine,_ i:CardInputs)->String {
        let rank=design.rank
        if availability(line.piece,i) == .ok,let text=line.piece.text(i,rank:rank) {
            return line.second.flatMap { $0.text(i,rank:rank) }.map { text+" · "+$0 } ?? text
        }
        if line.piece == .highlights { return L("Dynamic") }
        let sample=sampleInputs(at:i.now),text=sampleText(line.piece,sample)
        return line.second.map { text+" · "+sampleText($0,sample) } ?? text
    }
    /// What a line would say, from the sample inputs (a comeback or a new season can't be made up from them).
    func sampleText(_ piece:CardPiece,_ sample:CardInputs)->String {
        if let text=piece.text(sample,rank:design.rank) { return text }
        switch piece {
        case .moment(.comeback): return L("First game in {0} days","6")
        default: return piece.label
        }
    }
    /// Under a line in the list: what it is, and the piece after it.
    func explain(_ line:CardLine)->String {
        let about=line.piece.about
        return line.second.map { L("{0}, plus {1}",about,$0.label.lowercased()) } ?? about
    }
    func portrait(_ key:String?,_ i:CardInputs)->URL? {
        guard let key else { return nil }
        return i.profile?.heroes[key]?.portrait ?? sampleInputs(at:i.now).profile?.heroes[key]?.portrait
    }
    /// Pieces that fit after a line: Discord shows about 30 characters of Line 2.
    func seconds(for piece:CardPiece,main:String,inputs:CardInputs)->[(piece:CardPiece,text:String)] {
        let candidates:[CardPiece]=[.rank(.current),.hero(nil,.main),.tonight(.matches),.title(.endorsement)]
        return candidates.filter { $0.topic != piece.topic }.compactMap { second in
            guard let text=second.text(inputs,rank:design.rank),main.count+3+text.count <= 30 else { return nil }
            return (second,text)
        }
    }
    var topicNote:String? {
        switch topic {
        case .record: return L("A day runs from four in the morning, and never has the game going on: the profile tells it after you quit.")
        case .rank: return L("The marks show how your last session went: ↑ up a division, ↟ two or more, – no change, ↓ down, ↡ two or more down.")
        default: return nil
        }
    }
    struct HighlightStep { let icon:String;let color:Color;let when:String;let text:String;let applies:Bool }
    /// Dynamic's order, each with what it would say and whether it applies right now.
    func highlightSteps(_ inputs:CardInputs)->[HighlightStep] {
        let moment=CardMoment.allCases.lazy.compactMap { CardPiece.moment($0).text(inputs,rank:self.design.rank) }.first
        let sample=sampleInputs(at:inputs.now)
        let last=(inputs.profile ?? sample.profile)?.last.map { L("Last · {0}",$0.summary) }
        let all=CardPiece.record(.all,.competitive,winRate:false).text(inputs.profile == nil ? sample : inputs,rank:design.rank)
        var tonight=inputs;tonight.place = .menu
        let rankNews=CardPiece.moment(.rankChange).text(sample,rank:design.rank)
        let cyan=DiscordColors.voice
        return [HighlightStep(icon:"ph:users-three-fill",color:cyan,when:L("In the group’s voice chat"),text:"\(texts.voice) (\(L("{0} of {1}","3","6")))",
                              applies:inputs.voice != nil && design.party == .sayVoice),
                HighlightStep(icon:"rc:live",color:DiscordColors.news,when:L("Something just happened"),text:moment ?? rankNews ?? L("A rank change, a new best…"),applies:moment != nil),
                HighlightStep(icon:"ph:sword-fill",color:DiscordColors.inMatch,when:L("You played before"),text:last ?? L("Your last session"),applies:inputs.profile?.last != nil),
                HighlightStep(icon:"ph:medal-fill",color:DiscordColors.good,when:L("Your first session"),text:all ?? L("Your all-time record"),
                              applies:inputs.profile != nil && all != nil),
                HighlightStep(icon:"rc:moon-fill",color:cyan,when:L("No profile yet"),text:CardPiece.tonight(.matches).text(tonight,rank:design.rank) ?? "",applies:true)]
    }
    /// The heroes, most played first, then the rest by name.
    func heroOrder(_ i:CardInputs)->[String] { i.topHeroes+(i.profile?.heroes.keys.sorted().filter { i.heroTime[$0] == nil } ?? []) }
    func heroCaption(_ key:String,_ i:CardInputs)->String {
        let name=i.heroName(key)
        return i.heroTime[key].map { L("{0} · {1} played",name,i.hours($0)) } ?? name
    }
    func heroesOfRole(_ i:CardInputs)->[String] { heroOrder(i).filter { i.profile?.heroes[$0]?.role == role } }
    /// The pictures a tab offers, with what each is (the caption when pointed at).
    func imageChoices(_ i:CardInputs)->[(picture:CardPicture,name:String)] {
        switch imageTab {
        case .suggested:
            // The role mains, then the most played, without the last hero: Last hero already shows them.
            let mains=[CareerRank.Role.tank,.damage,.support].compactMap { role in i.topHeroes.first { i.profile?.heroes[$0]?.role == role } }
            var heroes:[String]=[]
            for key in mains+i.topHeroes.prefix(6) where !heroes.contains(key) && key != i.profile?.last?.hero { heroes.append(key) }
            let fixed:[(picture:CardPicture,name:String)]=[(.playerIcon,L("Player icon")),(.overwatch,L("Overwatch")),(.lastHero,L("Last hero: follows who you played last"))]
            return fixed+heroes.map { key in
                    var name=heroCaption(key,i)
                    if profile != nil,mains.contains(key),let role=i.profile?.heroes[key]?.role {
                        switch role {
                        case .tank: name=L("{0} · your tank main",name)
                        case .damage: name=L("{0} · your damage main",name)
                        default: name=L("{0} · your support main",name)
                        }
                    }
                    return (CardPicture.hero(key),name)
                }
        case .heroes:
            let all=heroesOfRole(i)
            return (allHeroes ? all : Array(all.prefix(10))).map { (CardPicture.hero($0),heroCaption($0,i)) }
        case .extra:
            let fixed:[(picture:CardPicture,name:String)]=[(.rankEmblem,i.rank(design.rank).map { L("Rank emblem · {0}",$0.name) } ?? L("Rank emblem")),(.recall,L("Recall’s icon"))]
            return fixed+CardArt.allCases.map { (CardPicture.art($0),$0.name) }
        }
    }
    func badgeAbout(_ badge:CardBadge,_ i:CardInputs)->String {
        switch badge {
        case .rank: return i.rank(design.rank).map { L("{0} · from your profile",i.rankText($0)) } ?? L("From your profile")
        case .mac: return texts.badge
        case .recall: return L("Recall’s icon")
        }
    }
    func buttonAbout(_ button:SecondButton?,hasLabel:Bool)->String {
        switch button {
        case .careerProfile: return L("Your Blizzard career page. Shows your full BattleTag to anyone who opens it")
        case .heroPage: return L("Follows the hero in the image")
        case .patchNotes: return L("The latest Overwatch patch")
        case nil: return L("No second button")
        }
    }
    /// The card as it would be with a change, right now (the panels' small previews).
    func sample(_ inputs:CardInputs,_ change:(inout DiscordCardDesign)->Void)->[String:Any] {
        var card=design;change(&card)
        return card.activity(inputs,turn:0)
    }

    // MARK: the rail

    /// What each part shows now, under its name in the rail.
    func railSummary(_ slot:Slot,at now:Date)->String {
        let inputs=inputs(at:now),design=shown,turn=turn(at:now),lists=DiscordCardDesign.Shown(design,inputs,turn:turn)
        switch slot {
        case .picture:
            guard inputs.menus else { return L("Overwatch logo") }
            guard let pictures=design.pictures,!pictures.isEmpty else { return L("From Line 2") }
            let places=lists.picturePlaces
            return places.isEmpty ? L("Overwatch logo") : pictures[places[turn%places.count]].name
        case .badge:
            let badge=lists.badges.isEmpty ? CardBadge.mac : lists.badges[turn%lists.badges.count]
            return badge.railName
        case .lineOne: return design.lineOne.isEmpty ? LineOne.name.railName : design.lineOne[turn%design.lineOne.count].railName
        case .lineTwo:
            if inputs.voice != nil && design.party == .sayVoice { return L("Group voice count") }
            if lists.lineTwo.isEmpty { return inputs.inMatch ? L("Empty in a match") : L("Nothing right now") }
            return lists.lineTwo[turn%lists.lineTwo.count].piece.label
        case .timer: return design.timer == .match ? L("Each match") : L("Whole session")
        case .buttons: return design.button.map { L("+ {0}",$0.name) } ?? L("Only Get Recall")
        case .party:
            switch design.party {
            case .sayVoice: return L("Count on Line 2")
            case .addCount: return L("Count after Line 2")
            case .noCount: return L("No count")
            }
        }
    }
    /// How many take turns in a part (shown as a count with a ring in the rail).
    func railCount(_ slot:Slot,at now:Date)->Int {
        let inputs=inputs(at:now),design=shown,lists=DiscordCardDesign.Shown(design,inputs,turn:0)
        switch slot {
        case .picture: return inputs.menus ? max(1,design.pictures == nil ? lists.lineTwo.count : lists.picturePlaces.count) : 1
        case .badge: return inputs.menus ? max(1,lists.badgePlaces.count) : 1
        case .lineOne: return design.lineOne.count
        case .lineTwo: return design.lineTwo.count
        default: return 1
        }
    }

    // MARK: the cards (My cards)

    struct GalleryItem: Equatable {
        let design:DiscordCardDesign
        var readyMade:Bool { design.readyMade }
        var name:String { design.shownName }
    }
    /// The player's own cards first, then the ready-made ones that aren't hidden.
    var galleryItems:[GalleryItem] {
        shelf.mine.map(GalleryItem.init)+DiscordCardDesign.readyMade.filter { !shelf.hidden.contains($0.id) }.map(GalleryItem.init)
    }
    var galleryPlace:Int {
        let items=galleryItems
        return min(max(0,galleryIndex ?? items.firstIndex { $0.design.id == shelf.inUse.id } ?? 0),max(0,items.count-1))
    }
    var galleryItem:GalleryItem? { galleryItems.indices.contains(galleryPlace) ? galleryItems[galleryPlace] : nil }
    func openGallery(_ open:Bool) {
        finishRename();pointing?.cancel()
        gallery=open;galleryIndex=nil;gallerySlide=nil;deleteUndo=nil;sharing=false;importing=false;preview=nil;held=nil;openLine=nil;copied=false;shift=0;galleryStart=Date()
        if open,let before=sceneBeforeParty,live == nil { scene=before;sceneBeforeParty=nil;slot = .lineTwo }
    }
    func galleryStep(_ by:Int) {
        let next=galleryPlace+by
        guard by != 0,galleryItems.indices.contains(next) else { return }
        finishRename()
        galleryIndex=next;gallerySlide=GallerySlide(way:by > 0 ? 1 : -1);copied=false;shift=0;galleryStart=Date()
    }
    func use(_ item:GalleryItem) {
        finishRename()
        shelf.chosen=item.design.id;gallery=false;galleryIndex=nil;sharing=false;importing=false;held=nil;shift=0
        say(L("Now using “{0}”",shelf.inUse.shownName))
    }
    func duplicate(_ item:GalleryItem) {
        finishRename()
        var copy=shelf.mine.first { $0.id == item.design.id } ?? item.design
        // The name first: a ready-made card's is its id's, which the new id loses.
        let name=copy.shownName
        copy.id=UUID().uuidString;copy.name=String(L("{0} 2",name).prefix(24))
        shelf.mine.append(copy);galleryIndex=galleryItems.firstIndex { $0.design.id == copy.id };gallerySlide?.moving=false;sharing=false;shift=0;galleryStart=Date()
        say(L("Duplicated as “{0}”",copy.name))
    }
    /// Your only card can't go (Default counts as yours until hidden); other ready-made cards are only hidden.
    func canDelete(_ item:GalleryItem)->Bool {
        if item.readyMade && item.design.id != "default" { return true }
        return shelf.mine.count+(shelf.hidden.contains("default") ? 0 : 1) > 1
    }
    func delete(_ item:GalleryItem) {
        guard canDelete(item) else { return }
        renaming=nil
        let wasInUse=item.design.id == shelf.inUse.id,place=galleryPlace,mine=shelf.mine.firstIndex { $0.id == item.design.id }
        if item.readyMade { shelf.hidden.append(item.design.id) } else { shelf.mine.removeAll { $0.id == item.design.id } }
        if wasInUse { shelf.chosen=galleryItems.first?.design.id ?? "default" }
        // The card after it comes in from its side, so it's plain the card shown is another one now.
        galleryIndex=min(place,max(0,galleryItems.count-1));gallerySlide=GallerySlide(way:1,kind:.delete);sharing=false;shift=0;galleryStart=Date()
        let undo=DeleteUndo(card:item.design,mine:item.readyMade ? nil : mine,replacedBy:wasInUse ? shelf.chosen : nil,place:place,
                            text:wasInUse ? L("Deleted. Now using “{0}”.",shelf.inUse.shownName) : L("Deleted"))
        deleteUndo=undo;undoEnds?.cancel()
        undoEnds=Task { [weak self] in
            try? await Task.sleep(for:.seconds(DeleteUndo.window))
            guard !Task.isCancelled,self?.deleteUndo?.at == undo.at else { return }
            self?.deleteUndo?.leaving=Date()
            try? await Task.sleep(for:.seconds(DeleteUndo.spin))
            if !Task.isCancelled,self?.deleteUndo?.at == undo.at { withAnimation(.easeOut(duration:0.2)) { self?.deleteUndo=nil } }
        }
    }
    /// Delete's Undo in My cards: the card back where it was.
    func undoDelete() {
        guard let undo=deleteUndo,undo.leaving == nil else { return }
        undoEnds?.cancel();deleteUndo=nil
        let id=undo.card.id
        if let mine=undo.mine { if !shelf.mine.contains(where:{ $0.id == id }) { shelf.mine.insert(undo.card,at:min(mine,shelf.mine.count)) } }
        else { shelf.hidden.removeAll { $0 == id } }
        // Back in use, unless another card was chosen meanwhile.
        if let replacedBy=undo.replacedBy,shelf.chosen == replacedBy { shelf.chosen=id }
        galleryIndex=min(undo.place,max(0,galleryItems.count-1));gallerySlide=GallerySlide(way:-1,kind:.restore);galleryStart=Date()
    }
    var hiddenCount:Int { shelf.hidden.count }
    func bringBack() { shelf.hidden=[];galleryIndex=nil;shift=0;galleryStart=Date();say(L("The System cards are back")) }
    func startRename(_ item:GalleryItem) {
        guard !item.readyMade else { return }
        renaming=item.design.id;renameDraft=item.design.name;sharing=false;importing=false
    }
    /// Esc steps back one level: rename, import or share, My cards, the BattleTag field, then the page. Never while an
    /// erase waits.
    func escape() {
        if renaming != nil { renaming=nil;return }
        if importing { importing=false;importDraft="";importFailed=false;return }
        if sharing { sharing=false;return }
        if gallery { gallery=false;galleryIndex=nil;return }
        if tagEditing && !battleTag.isEmpty { cancelBattleTag();return }
        if erased != nil || sweep != nil { return }
        closePage()
    }
    func finishRename() {
        guard let id=renaming else { return }
        renaming=nil
        let name=Self.cardName(renameDraft)
        guard !name.isEmpty,let index=shelf.mine.firstIndex(where:{ $0.id == id }) else { return }
        shelf.mine[index].name=name
    }
    /// A card's name as My cards keeps it: one line, 24 characters at most.
    static func cardName(_ text:String)->String {
        let breaks:[Unicode.GeneralCategory]=[.control,.lineSeparator,.paragraphSeparator]
        let line=String(String.UnicodeScalarView(text.unicodeScalars.filter { !breaks.contains($0.properties.generalCategory) }))
        return String(line.trimmingCharacters(in:.whitespaces).prefix(24))
    }
    /// The card as a code to share: the code is the card itself (DiscordCardCode.swift).
    func code(_ item:GalleryItem)->String {
        var card=item.design
        if card.readyMade { card.name=card.shownName }
        return DiscordCardCode.encode(card)
    }
    func importCode() {
        let read=DiscordCardCode.read(importDraft)
        guard case .card(var card)=read else {
            importFailed=true;importNewer=(read == .newer)
            AccessibilityNotification.Announcement(importNewer ? L("A newer Recall made this card. Update Recall to add it.") : L("No card has that code.")).post()
            return
        }
        card.name=Self.cardName(card.name)
        if card.name.isEmpty { card.name=card.lineTwo.first.map { $0.piece.label } ?? L("Shared card") }
        if galleryItems.contains(where:{ $0.name == card.name }) { card.name=String(L("{0} 2",card.name).prefix(24)) }
        shelf.mine.append(card)
        galleryIndex=galleryItems.firstIndex { $0.design.id == card.id };importing=false;importDraft="";importFailed=false;shift=0;galleryStart=Date()
        say(L("Added “{0}” to your cards",card.name))
    }
    /// What a card shows, under its name in My cards.
    func galleryDescription(_ item:GalleryItem)->String {
        switch item.design.id {
        case "climber": return L("Your rank, how far you climbed this season, and your peak.")
        case "main": return L("Your main hero: who, how long, and in which role.")
        case "grinder": return L("This week’s record, tonight’s matches, and nights in a row.")
        case "showoff": return L("Your career bests, one after another.")
        case "private": return L("Tonight’s matches, nights in a row and this week’s hours, all from your Mac: no profile needed.")
        case "default": return L("Recall picks the most interesting thing on its own: a rank change, a new best, or your last session.")
        default:
            let lines=item.design.lineTwo
            if lines.count > 1 { return L("{0} lines take turns: {1}.",String(lines.count),lines.map { $0.piece.label }.joined(separator:", ")) }
            return L("One line: {0}.",lines.first?.piece.label ?? L("Dynamic"))
        }
    }

    // MARK: example data

    /// The example player, shown with no public profile and "Preview with example data" on.
    static var exampleName:String { L("Player") }
    static let exampleProfile:CareerCard={
        let base="https://d15f34w2p8l1cc.cloudfront.net/overwatch/"
        func hero(_ name:String,_ file:String,_ role:CareerRank.Role)->CareerHero { CareerHero(name:name,portrait:URL(string:base+file+".png"),role:role) }
        let heroes=["mercy":hero("Mercy","3bfb8bd8ec827e53d870f1238ab73d8aa1f5dbfbcfaaf7f96ffcd35b5c6102ab",.support),
                    "kiriko":hero("Kiriko","408603fe037e8576078eaac5eab2fb251489ced4003b11f5f522776d43d0b83d",.support),
                    "winston":hero("Winston","46a10db3aa908c590ddc4e7606376a88143d1f1306ecfbea043263040f9529a5",.tank),
                    "tracer":hero("Tracer","4504f6f15cb3feaa92ecd38e01dcf751cb5abdac2e0bb52d0555727e53277502",.damage)]
        let competitive=ModeStats(games:Tally(played:98,won:46,lost:52),heroes:["winston":25560,"tracer":21600,"kiriko":32040],
                                  bests:["eliminations_most_in_game":53,"all_damage_done_most_in_game":39448,"healing_done_most_in_game":16163,"kill_streak_best":27,"multikill_best":6])
        let quickplay=ModeStats(games:Tally(played:578,won:297,lost:281),heroes:["mercy":55800],heroGames:["mercy":Tally(played:40,won:22,lost:18)])
        // Blizzard's emblems as OverFast gives them: a Champion tank who plays damage in Bronze.
        let emblems="https://static.playoverwatch.com/images/pages/career/icons/rank/"
        let ranks=[CareerRank(role:.tank,division:"champion",tier:1,icon:URL(string:emblems+"Rank_UltimateTier.bc416c2102ab21d39b2398fdf7571cc56503ea2c.png")!),
                   CareerRank(role:.damage,division:"bronze",tier:5,icon:URL(string:emblems+"Rank_BronzeTier.f46bc3540601455a7768761396f9310d805052ad.png")!)]
        return CareerCard(identity:CareerIdentity(name:exampleName,title:nil,endorsement:3,avatar:nil),ranks:ranks,season:nil,
                          last:LastSession(competitive:Tally(played:1,won:1),other:1,hero:"tracer",role:.tank,eliminations:31,deaths:7,damage:10623),
                          hero:heroes["tracer"],page:URL(string:"https://overwatch.blizzard.com/en-us/career/"),totals:["competitive":competitive,"quickplay":quickplay],heroes:heroes)
    }()
    static func exampleHistory(_ now:Date)->CareerHistory {
        var history=CareerHistory()
        let day:TimeInterval=24*3600
        var change=ProfileChange(at:now.addingTimeInterval(-day),season:nil,session:LastSession(competitive:Tally(played:4,won:3,lost:1)),before:[:],after:[:])
        change.heroes=["mercy":3600]
        history.changes=[change]
        history.runs=[PlayedRun(start:now.addingTimeInterval(-2*day),end:now.addingTimeInterval(-2*day+7200),matches:5),
                      PlayedRun(start:now.addingTimeInterval(-day-7200),end:now.addingTimeInterval(-day),matches:4)]
        return history
    }
}

// MARK: words for the editor

extension DiscordStudio.Topic {
    var name:String {
        switch self {
        case .highlights: return L("Dynamic")
        case .moment: return L("Moments")
        case .rank: return L("Rank")
        case .record: return L("Record")
        case .hero: return L("Hero")
        case .best: return L("Best")
        case .tonight: return L("Tonight")
        case .title: return L("You")
        }
    }
    var icon:String {
        switch self {
        case .highlights: return "rc:pick"
        case .moment: return "rc:live"
        case .rank: return "ph:medal-fill"
        case .record: return "ph:sword-fill"
        case .hero: return "rc:user-fill"
        case .best: return "ph:trophy-fill"
        case .tonight: return "rc:moon-fill"
        case .title: return "rc:id-fill"
        }
    }
    var color:Color {
        switch self {
        case .highlights: return DiscordColors.link
        case .moment: return DiscordColors.news
        case .rank: return DiscordColors.good
        case .record: return DiscordColors.inMatch
        case .hero: return Color.rgb(196,140,255)
        case .best: return Color.rgb(255,206,84)
        case .tonight: return DiscordColors.voice
        case .title: return Color.rgb(255,128,170)
        }
    }
    var about:String {
        switch self {
        case .highlights: return L("One line that picks itself: Recall shows the first of these that applies right now.")
        case .moment: return L("Lines that appear only when something happens, the next time you play after it.")
        case .rank: return L("Your rank from your profile. The role you pick here is the one every rank line and the badge show.")
        case .record: return L("Wins and losses from your profile, for the time you pick.")
        case .hero: return L("Pick a hero, then what to say. “Main” is earned: it goes to your most-played hero.")
        case .best: return L("Your best games ever, from your profile.")
        case .tonight: return L("“Tonight” is tonight’s play, until four in the morning: a crash or a quick relaunch keeps counting. Recall counts it from the game’s log, so it needs no BattleTag.")
        case .title: return L("Titles you earn from your hours. Each bar fills as you play; reach the key to unlock it.")
        }
    }
    func catalog(hero:String?,mode:RecordMode,winRate:Bool)->[CardPiece] {
        switch self {
        case .highlights: return [.highlights]
        // "First game of the season" is retired (D8e).
        case .moment: return CardMoment.allCases.filter { $0 != .newSeason }.map { .moment($0) }
        case .rank: return [RankLine.current,.climb,.peak,.all].map { .rank($0) }
        case .record: return [CareerPeriod.last,.today,.week,.season,.all].map { .record($0,mode,winRate:winRate && mode != .both) }
        case .hero: return HeroLine.allCases.map { .hero(hero,$0) }
        case .best: return [BestLine.eliminations,.damage,.healing,.killStreak,.multikill].map { .best($0) }
        case .tonight: return TonightLine.allCases.map { .tonight($0) }
        // One-trick is the top of "main" now (the hero's own line), not a title of its own.
        case .title: return TitleLine.allCases.filter { $0 != .oneTrick }.map { .title($0) }
        }
    }
}

extension CardPiece {
    var topic:DiscordStudio.Topic {
        switch self {
        case .highlights: return .highlights
        case .moment,.rank(.change),.best(.new): return .moment
        case .rank: return .rank
        case .record: return .record
        case .hero: return .hero
        case .best: return .best
        case .tonight: return .tonight
        case .title: return .title
        }
    }
    /// Its short name ("Week record", "Juno hours").
    var label:String { words.label }
    /// What it is, in plain words, under the line in Line 2's list.
    var about:String { words.about }
    /// The time a line's numbers cover, tagged beside it in Customize's lists.
    var period:String? { words.period }
    struct Words {
        let label:String,about:String,period:String?
        init(_ label:String,_ about:String,period:String?=nil) { self.label=label;self.about=about;self.period=period }
    }
    private var words:Words {
        switch self {
        case .highlights: return Words(L("Dynamic"),L("Recall picks what to show"))
        case .moment(let moment):
            switch moment {
            case .rankChange: return Words(L("Rank change"),L("When your rank moves (↑ one, ↟ two+)"))
            case .newBest: return Words(L("New best"),L("When a game beats one of your bests"))
            case .seasonHigh: return Words(L("Season high"),L("Your best rank yet this season"))
            case .milestone: return Words(L("Hero milestone"),L("At 10, 25, 50, 100… hours on a hero"))
            case .comeback: return Words(L("Comeback"),L("First game after 3+ days away"))
            case .newSeason: return Words(L("New season"),L("First game of a new season"))
            }
        case .rank(let line):
            let season=L("This season")
            switch line {
            case .current: return Words(L("Rank"),L("Your rank, and how last session moved it"),period:season)
            case .climb: return Words(L("Climb"),L("How far you climbed this season"),period:season)
            case .peak: return Words(L("Peak"),L("Your best rank this season"),period:season)
            case .all: return Words(L("All ranks"),L("Your rank in every role"),period:season)
            case .change: return Words(L("Rank news"),L("Only when your rank moves"),period:season)
            }
        case .record(let period,let mode,let winRate):
            let modes=mode == .competitive ? L("Comp") : mode == .quickPlay ? L("Quick Play") : L("Comp and QP")
            var time:String,about:String
            switch period {
            case .last: (time,about)=(L("Last session"),mode == .competitive ? L("Last session’s Comp record, and other modes") : L("Last session’s {0} record",modes))
            case .today: (time,about)=(L("Today"),L("{0} record, today",modes))
            case .week: (time,about)=(L("This week"),L("{0} record, this week",modes))
            case .season: (time,about)=(L("This season"),L("{0} record, this season",modes))
            // The profile's Competitive is this season's only.
            case .all: (time,about)=(L("All time"),mode == .competitive ? L("Comp record, this whole season") : L("{0} record, all time",modes))
            }
            if winRate && mode != .both { about=L("{0}, with win rate",about) }
            let label=mode == .competitive ? time : mode == .quickPlay ? L("QP, {0}",time) : L("{0}, both modes",time)
            return Words(label,about,period:period == .all && mode == .competitive ? L("This season") : time)
        case .hero(let key,let line):
            let name=key.map { DiscordStudio.heroName($0) },main=name ?? L("Your main"),hero=name ?? L("your most-played hero")
            switch line {
            case .main: return Words(name.map { L("{0} main",$0) } ?? main,L("{0} main, and one-trick past half your hours",hero))
            case .hours: return Words(L("{0} hours",main),L("Your hours on {0}",hero))
            case .role: return Words(L("{0} with role",main),L("{0}’s role, and your hours",hero))
            case .winRate: return Words(L("{0} wins",main),L("Your win rate on {0}",hero))
            }
        case .best(let line):
            let ever=L("Your best game ever")
            switch line {
            case .eliminations: return Words(L("Best elims"),ever)
            case .damage: return Words(L("Best damage"),ever)
            case .healing: return Words(L("Best healing"),ever)
            case .killStreak: return Words(L("Best streak"),ever)
            case .multikill: return Words(L("Best multikill"),ever)
            case .new: return Words(L("Best news"),L("When a game beats one of your bests"))
            }
        case .tonight(let line):
            switch line {
            case .matches: return Words(L("Match count"),L("Matches tonight, or today before five"),period:L("Tonight"))
            case .nights: return Words(L("Nights in a row"),L("Days in a row you’ve played"))
            case .week: return Words(L("Hours this week"),L("Hours played this week"),period:L("This week"))
            }
        case .title(let line):
            let earned=L("Earned from your hours")
            switch line {
            case .endorsement: return Words(L("Endorsement"),L("Your endorsement level"))
            case .hours: return Words(L("Hours played"),L("Your total hours"))
            case .roleMain: return Words(L("Role main"),earned)
            case .flex: return Words(L("Flex"),earned)
            case .oneTrick: return Words(L("One-trick"),earned)
            case .century: return Words(L("Century"),L("Earned at 100 hours"))
            case .cardboardSupport: return Words(L("Cardboard Support"),L("Support main who deals more damage than healing"))
            }
        }
    }
    /// Lines that need the profile (all but Dynamic, Tonight and a comeback).
    var needsProfile:Bool {
        switch self {
        case .highlights,.tonight,.moment(.comeback): return false
        default: return true
        }
    }
    /// What Recall builds as it goes: the hours it counts, and lines learnt from fewer than ten sessions so far.
    func learning(_ i:CardInputs)->String? {
        switch self {
        case .hero(_,.hours),.hero(_,.main),.hero(_,.role),.title(.hours),.title(.century),.title(.roleMain),.title(.flex),.title(.oneTrick),.title(.cardboardSupport):
            guard i.profile != nil,let hours=i.history.hours,!hours.heroes.isEmpty else { return nil }
            return L("Counted by Recall since {0}",hours.since.formatted(.dateTime.month(.abbreviated).day()))
        case .record(.today,_,_),.record(.week,_,_),.record(.season,_,_),.rank(.climb),.rank(.peak),.tonight(.nights),.tonight(.week):
            let seen=i.history.runs.count
            guard seen < 10 else { return nil }
            return seen == 1 ? L("Learning · 1 session so far") : L("Learning · {0} sessions so far",String(seen))
        default: return nil
        }
    }
}
extension CardPicture {
    var name:String {
        switch self {
        case .playerIcon: return L("Player icon")
        case .lastHero: return L("Last hero")
        case .overwatch: return L("Overwatch")
        case .rankEmblem: return L("Rank emblem")
        case .recall: return L("Recall")
        case .roleMain: return L("Role main")
        case .topHeroes: return L("Top heroes")
        case .hero(let key): return DiscordStudio.heroName(key)
        case .art(let art): return art.name
        }
    }
    /// What it shows now: the hero it brings, or its name.
    func shownName(_ i:CardInputs,rank:RankChoice)->String {
        image(i,rank:rank,turn:0)?.hero.map { i.heroName($0) } ?? name
    }
    /// A hero's role and time, under it in the list.
    func heroSub(_ i:CardInputs)->String? {
        guard case .hero(let key)=self else { return nil }
        let role=i.profile?.heroes[key]?.role?.label
        let time=i.heroTime[key].map { L("{0} played",i.hours($0)) }
        return [role,time].compactMap { $0 }.joined(separator:" · ").nilIfEmpty
    }
}
extension CardBadge {
    var name:String {
        switch self {
        case .rank: return L("Your rank")
        case .mac: return L("Mac badge")
        case .recall: return L("Recall")
        }
    }
    var railName:String { self == .recall ? L("Recall’s icon") : name }
}
extension LineOne {
    var name:String {
        switch self {
        case .name: return L("Your name")
        case .nameAndTitle: return L("Name and title")
        case .main: return L("Your main")
        case .rank: return L("Your rank")
        case .placeOnly: return L("Just where you are")
        case .phrase: return L("A phrase")
        }
    }
    var railName:String { self == .placeOnly ? L("Where you are") : name }
}
extension SecondButton {
    var name:String {
        switch self {
        case .careerProfile: return L("Career Profile")
        case .heroPage: return L("Hero’s page")
        case .patchNotes: return L("Patch notes")
        }
    }
}
extension PartyChoice {
    var name:String {
        switch self {
        case .sayVoice: return L("Say you’re in group voice")
        case .addCount: return L("Keep Line 2, add the count")
        case .noCount: return L("Keep Line 2, no count")
        }
    }
}
extension DiscordStudio.ImageTab {
    var name:String {
        switch self {
        case .suggested: return L("Suggested")
        case .heroes: return L("Heroes")
        case .extra: return L("Extra")
        }
    }
}

extension DiscordStudio {
    /// A hero's name from the profile's list (set as the profile arrives, on the main thread), or its key made readable.
    nonisolated(unsafe) static var heroNames:[String:String]=[:]
    nonisolated static func heroName(_ key:String)->String { heroNames[key] ?? CareerHero.name(key) }
}

extension DiscordCardDesign {
    /// The picture's own list (empty while it follows Line 2).
    var ownPictures:[CardPicture] { get { pictures ?? [] } set { pictures=newValue } }
}
extension DiscordCardShelf {
    /// Two cards are the same card when their ids are.
    func contains(_ design:DiscordCardDesign)->Bool { all.contains { $0.id == design.id } }
}
