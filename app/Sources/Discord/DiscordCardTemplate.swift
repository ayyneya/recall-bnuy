import Foundation

// The card's design: Line 1, Line 2, the large picture and the badge each hold a list, and a longer list takes turns on
// one clock (app/ARCHITECTURE.md). Full is Default; Custom is the player's own. A field added later must be optional.

/// What goes before where the player is, on line 1 ("pyxee · In Menus"); `phrase` is the card's own (LinePhrase).
enum LineOne: String, Codable, CaseIterable { case name,nameAndTitle,main,rank,placeOnly,phrase }

/// Line 1's phrase: Recall's own words with one blank filled from a list, never typed. "Auto" fills it from the
/// player's data.
struct LinePhrase: Codable, Hashable {
    /// The words, in a fixed order (share codes index it: only add at the end).
    enum Words: String, Codable, CaseIterable {
        case roadTo,grindingTo,learning,maining,practicing,rolePlayer,climbingIn,offRole
        case flexing,chillNight,tryhard,warmingUp,oneMore,lastGame,withFriends,soloQueue
        enum Kind { case none,hero,rank,role }
        var kind:Kind {
            switch self {
            case .roadTo,.grindingTo: return .rank
            case .learning,.maining,.practicing: return .hero
            case .rolePlayer,.climbingIn,.offRole: return .role
            default: return .none
            }
        }
        /// About tonight only: it comes off the card when the game closes.
        var tonight:Bool { [.practicing,.offRole,.chillNight,.tryhard,.warmingUp,.oneMore,.lastGame,.withFriends,.soloQueue].contains(self) }
    }
    enum Blank: Codable, Hashable { case auto,hero(String),rank(String),role(CareerRank.Role) }
    var words:Words
    var blank:Blank = .auto
}

enum CardMoment: String, Codable, CaseIterable { case rankChange,newBest,seasonHigh,milestone,comeback,newSeason }
enum RankLine: String, Codable, CaseIterable { case current,climb,peak,all,change }
enum RecordMode: String, Codable, CaseIterable { case competitive,quickPlay,both }
enum HeroLine: String, Codable, CaseIterable { case main,hours,role,winRate }
enum BestLine: String, Codable, CaseIterable { case eliminations,damage,healing,killStreak,multikill,new }
enum TonightLine: String, Codable, CaseIterable { case matches,nights,week }
enum TitleLine: String, Codable, CaseIterable { case endorsement,hours,roleMain,flex,oneTrick,century,cardboardSupport }

/// One thing Line 2 can say (DiscordCardCatalog.swift has the words).
enum CardPiece: Codable, Hashable {
    /// The first that applies: something that just happened, the last session, the first look, tonight.
    case highlights
    /// Only when something happened, the first time the player plays after it.
    case moment(CardMoment)
    case rank(RankLine)
    case record(CareerPeriod,RecordMode,winRate:Bool)
    /// A hero by OverFast's key; nil is the player's most-played.
    case hero(String?,HeroLine)
    case best(BestLine)
    case tonight(TonightLine)
    /// Titles earned from the profile's hours.
    case title(TitleLine)
}

/// A Line 2 line: a piece, maybe a second ("Week · Comp 12–9 · Juno · 15h"), and whether it shows in a match.
struct CardLine: Codable, Hashable {
    var piece:CardPiece
    var second:CardPiece?=nil
    var inMatch=true
}
extension CardLine {
    init(from decoder:Decoder) throws {
        let kept=try decoder.container(keyedBy:CodingKeys.self)
        piece=try kept.decode(CardPiece.self,forKey:.piece)
        second=(try? kept.decodeIfPresent(CardPiece.self,forKey:.second)) ?? nil
        inMatch=(try? kept.decodeIfPresent(Bool.self,forKey:.inMatch)) ?? true
    }
}

enum CardPicture: Codable, Hashable { case playerIcon,lastHero,overwatch,rankEmblem,recall,roleMain,topHeroes,hero(String),art(CardArt) }
/// The large image's Extra pictures, bundled (app/Resources/Discord): Juno, a Winston plush, and Jetpack Cat (a GIF).
enum CardArt: String, Codable, CaseIterable {
    case juno,winston,jetpackCat
    var file:String {
        switch self {
        case .juno: return "Juno.png"
        case .winston: return "WinstonPlush.png"
        case .jetpackCat: return "JetpackCat.gif"
        }
    }
    /// Its name, as heroes' names are shown (the game's own, in English everywhere).
    var name:String {
        switch self {
        case .juno: return "Juno"
        case .winston: return "Winston"
        case .jetpackCat: return L("Jetpack Cat")
        }
    }
    /// Its letter in a card's code (DiscordCardCode), after a dash in a hero key's place.
    var letter:Character {
        switch self {
        case .juno: return "j"
        case .winston: return "w"
        case .jetpackCat: return "c"
        }
    }
}
enum CardBadge: String, Codable, CaseIterable { case rank,mac,recall }
/// The timer counts from when the game opened, or starts over with each match.
enum CardTimer: String, Codable { case session,match }
/// The button after Get Recall.
enum SecondButton: String, Codable, CaseIterable { case careerProfile,heroPage,patchNotes }
/// In the group's voice chat: say so on Line 2 with the count, keep Line 2 and add the count, or keep Line 2 alone.
enum PartyChoice: String, Codable { case sayVoice,addCount,noCount }
/// The rank every rank line and the badge show.
enum RankChoice: Codable, Hashable { case role(CareerRank.Role),highest,lastPlayed }

struct DiscordCardDesign: Codable, Equatable, Identifiable {
    /// The ready-made designs' own ids ("default"); a UUID for the player's.
    var id:String
    /// The player's own name for it (a ready-made design's is its id's: shownName).
    var name:String
    var lineOne:[LineOne]=[.name]
    var lineTwo:[CardLine]=[CardLine(piece:.highlights)]
    /// The large picture's own list; nil follows Line 2 (each line brings its own picture).
    var pictures:[CardPicture]?=nil
    var badges:[CardBadge]=[.rank]
    var timer:CardTimer = .match
    var button:SecondButton? = .careerProfile
    var party:PartyChoice = .sayVoice
    /// Seconds each turn lasts.
    var pace=45
    var rank:RankChoice = .lastPlayed
    /// Line 1's phrase, when the list has one.
    var phrase:LinePhrase?=nil
    /// What a newer Recall kept on this card that this one doesn't know, written back as it was.
    var extra:[String:JSONValue]=[:]
    var kept:Kept?=nil

    static let paces=[20,45,60,120,300]
    /// Discord takes an update every few seconds at most; the editor offers 20 seconds and up.
    static let shortestPace=20
    var readyMade:Bool { Self.readyMade.contains { $0.id == id } }
    /// The name the editor shows: the player's own, or a ready-made design's in the app's language.
    var shownName:String {
        switch id {
        case "default": return L("Default")
        case "climber": return L("Climber")
        case "main": return L("Main")
        case "grinder": return L("Grinder")
        case "showoff": return L("Show-off")
        case "private": return L("Private profile")
        default: return name
        }
    }

    /// Full's card and the ready-made ones. Frozen: changing one would change what friends already see.
    static let standard=DiscordCardDesign(id:"default",name:"")
    static let privateProfile=DiscordCardDesign(id:"private",name:"",lineTwo:[CardLine(piece:.tonight(.matches)),CardLine(piece:.tonight(.nights)),CardLine(piece:.tonight(.week))],
                                                badges:[.mac],button:nil)
    static let readyMade:[DiscordCardDesign]=[
        standard,
        DiscordCardDesign(id:"climber",name:"",lineTwo:[CardLine(piece:.rank(.current)),CardLine(piece:.rank(.climb)),CardLine(piece:.rank(.peak))]),
        DiscordCardDesign(id:"main",name:"",lineTwo:[CardLine(piece:.hero(nil,.main)),CardLine(piece:.hero(nil,.hours)),CardLine(piece:.hero(nil,.role))],button:.heroPage),
        DiscordCardDesign(id:"grinder",name:"",lineTwo:[CardLine(piece:.record(.week,.competitive,winRate:false)),CardLine(piece:.tonight(.matches)),CardLine(piece:.tonight(.nights))]),
        DiscordCardDesign(id:"showoff",name:"",lineTwo:[CardLine(piece:.best(.eliminations)),CardLine(piece:.best(.damage)),CardLine(piece:.best(.healing))]),
        // All from this Mac's own play, for a private profile or no BattleTag; no Career Profile button.
        privateProfile,
    ]

    /// The turn at a moment: the same for every list, so they change together.
    func turn(at now:Date)->Int { max(0,Int(now.timeIntervalSince1970))/max(pace,Self.shortestPace) }
    /// When the next turn starts, if anything would change then (some list has more than one item to show).
    func nextTurn(_ inputs:CardInputs)->Date? {
        let shown=Shown(self,inputs,turn:turn(at:inputs.now))
        // The top heroes take turns within their one picture.
        let heroes=inputs.menus && inputs.topHeroes.count > 1 && (pictures ?? [(shown.lineTwo.first?.piece ?? .highlights).picture(inputs,rank:rank)]).contains(.topHeroes)
        guard shown.lineOne.count > 1 || shown.lineTwo.count > 1 || shown.pictures.count > 1 || shown.badges.count > 1 || heroes else { return nil }
        let pace=max(self.pace,Self.shortestPace)
        return Date(timeIntervalSince1970:TimeInterval((turn(at:inputs.now)+1)*pace))
    }

    /// The card Discord gets (SET_ACTIVITY), at Full and Custom; the preview can hold it at a turn.
    func activity(_ inputs:CardInputs,turn held:Int?=nil)->[String:Any] { CardWords.inEnglish { card(inputs,turn:held) } }
    private func card(_ inputs:CardInputs,turn held:Int?)->[String:Any] {
        let turn=held ?? turn(at:inputs.now),shown=Shown(self,inputs,turn:turn)
        func pick<T>(_ list:[T])->T? { list.isEmpty ? nil : list[(turn%list.count+list.count)%list.count] }
        var start=inputs.launched
        if timer == .match,case .match(let since)=inputs.place { start=since }
        var card:[String:Any]=["type":0,"timestamps":["start":Int(start.timeIntervalSince1970)]]
        let place=inputs.menus ? inputs.texts.menu : inputs.inMatch ? inputs.texts.match : inputs.voice != nil ? inputs.texts.group : inputs.texts.game
        // Line 1 never says what Line 2 says ("Tank ↑ Emerald 1" twice): the name in its place.
        var lead=pick(shown.lineOne) ?? nil
        if let said=lead,said != inputs.name,let state=pick(shown.lineTwo)?.text,state.hasPrefix(said) { lead=inputs.name }
        let one=[lead,place].compactMap { $0 }.joined(separator:" · ")
        if one.count >= 2 { card["details"]=PresenceCard.fit(one) }
        // Line 2, or the group's voice chat in its place, with Discord's own count after it.
        let line=pick(shown.lineTwo)
        var state=line?.text
        if let voice=inputs.voice,party != .noCount {
            if party == .sayVoice || state == nil { state=inputs.texts.voice }
            card["party"]=PresenceCard.party(voice)
        }
        if let state,state.count >= 2 { card["state"]=PresenceCard.fit(state) }
        var assets:[String:String]=[:]
        // The large picture: Line 2's, or the next in its own list. Outside the menus only the player's icon.
        let picture:CardImage?
        if pictures == nil { picture=inputs.menus ? (line?.piece ?? .highlights).image(inputs,rank:rank,turn:turn) : CardPicture.playerIcon.image(inputs,rank:rank,turn:turn) } else { picture=pick(shown.pictures) ?? nil }
        if let picture {
            assets["large_image"]=picture.url.absoluteString
            if let hover=picture.hover,hover.count >= 2 { assets["large_text"]=PresenceCard.fit(hover) }
        }
        let badge=pick(shown.badges) ?? .mac
        // One picture never shows twice: with the rank's emblem large, the badge is the Mac's.
        if badge == .rank,let rank=inputs.rank(rank),rank.icon != picture?.url {
            let all=(inputs.allRanks.map(\.text)+[inputs.texts.badge]).joined(separator:" · ")
            assets["small_image"]=rank.icon.absoluteString;assets["small_text"]=PresenceCard.fit(all)
        } else {
            assets["small_image"]=(badge == .recall ? DiscordAssets.badge : DiscordAssets.macBadge).absoluteString;assets["small_text"]=inputs.texts.badge
        }
        card["assets"]=assets
        // Get Recall first, always ("for Mac" says what it is); Discord shows buttons to everyone but the player.
        var buttons=[["label":String(L("Get {0} for Mac",Brand.name).prefix(32)),"url":Brand.repository.absoluteString]]
        if let second=button.flatMap({ inputs.button($0,picture:picture) }) {
            buttons.append(["label":String(second.label.prefix(32)),"url":second.url.absoluteString])
        }
        card["buttons"]=buttons
        return card
    }

    /// What each list has to show at this moment, in its order: the items with nothing to say are left out.
    struct Shown {
        var lineOne:[String?]
        var lineTwo:[(piece:CardPiece,text:String)]
        /// nil is Overwatch's own picture: the turn sends none, and Discord shows the game's icon.
        var pictures:[CardImage?]
        var badges:[CardBadge]
        /// Where those pictures and badges are in the card's own lists (the editor marks them).
        var picturePlaces:[Int]
        var badgePlaces:[Int]
        init(_ design:DiscordCardDesign,_ inputs:CardInputs,turn:Int) {
            lineOne=design.lineOne.isEmpty ? [nil] : design.lineOne.map { $0 == .phrase ? design.phrase.flatMap { inputs.phrase($0,rank:design.rank) } ?? inputs.name : inputs.lineOne($0,rank:design.rank) }
            lineTwo=design.lineTwo.compactMap { line in
                if inputs.inMatch && (!line.inMatch || !line.piece.safeInMatch) { return nil }
                // Menus or a match, unknown: past results only, nothing that would read as this game's.
                if inputs.unsure && !line.piece.safeWhenUnsure { return nil }
                guard let text=line.piece.text(inputs,rank:design.rank) else { return nil }
                let second=line.second.flatMap { inputs.inMatch && !$0.safeInMatch ? nil : $0.text(inputs,rank:design.rank) }
                return (line.piece,second.map { text+" · "+$0 } ?? text)
            }
            let own:[(Int,CardImage?)]=(design.pictures ?? []).enumerated().compactMap { place,picture in
                // Overwatch's picture takes its turn too, in the menus.
                if picture == .overwatch { return inputs.menus ? (place,nil) : nil }
                return inputs.menus || picture == .playerIcon ? picture.image(inputs,rank:design.rank,turn:turn).map { (place,$0) } : nil }
            pictures=own.map(\.1);picturePlaces=own.map(\.0)
            // The rank in the badge's place: in the menus, where the log can't tell, or in a match known to be competitive.
            let rankBadge=inputs.rank(design.rank) != nil && (inputs.menus || inputs.unsure || inputs.competitive == true)
            badgePlaces=design.badges.indices.filter { design.badges[$0] != .rank || rankBadge }
            badges=badgePlaces.map { design.badges[$0] }
            if badges.isEmpty { badges=[design.badges.contains(.recall) && !design.badges.contains(.mac) ? .recall : .mac] }
        }
    }
}

/// The player's cards: the one in use, and their own designs, kept in this Mac's settings.
struct DiscordCardShelf: Codable, Equatable {
    var chosen="default"
    var mine:[DiscordCardDesign]=[]
    /// Ready-made cards the player deleted from My cards (Bring back shows them again).
    var hidden:[String]=[]
    /// Own cards this Recall can't read (a newer one made them): written back as they were.
    var unread:[JSONValue]=[]
    var all:[DiscordCardDesign] { DiscordCardDesign.readyMade+mine }
    /// A chosen card this Recall can't find (a newer Recall's) falls back to one that shows no profile.
    var inUse:DiscordCardDesign { all.first { $0.id == chosen } ?? .privateProfile }
    static func load(_ store:UserDefaults = .standard)->DiscordCardShelf {
        guard let data=store.data(forKey:key) else { return DiscordCardShelf() }
        if let shelf=try? JSONDecoder().decode(Self.self,from:data) { return shelf }
        // Not even a shelf: kept aside before anything is saved over it.
        store.set(data,forKey:key+".unreadable")
        return DiscordCardShelf()
    }
    func save(_ store:UserDefaults = .standard) { store.set(try? JSONEncoder().encode(self),forKey:Self.key) }
    private static let key="discordCards"
    private enum CodingKeys: String, CodingKey { case chosen,mine,hidden }
}
// Saved cards outlive the Recall that wrote them, both ways: what's missing takes today's default, and what this Recall
// doesn't know is skipped but written back.
extension DiscordCardShelf {
    init(from decoder:Decoder) throws {
        let kept=try decoder.container(keyedBy:CodingKeys.self)
        self.init()
        chosen=(try? kept.decodeIfPresent(String.self,forKey:.chosen)) ?? chosen
        let cards=(try? kept.decodeIfPresent([Readable<DiscordCardDesign>].self,forKey:.mine)) ?? []
        mine=cards.compactMap(\.value);unread=cards.compactMap(\.raw)
        hidden=(try? kept.decodeIfPresent([String].self,forKey:.hidden)) ?? []
    }
    func encode(to encoder:Encoder) throws {
        var kept=encoder.container(keyedBy:CodingKeys.self)
        try kept.encode(chosen,forKey:.chosen);try kept.encode(hidden,forKey:.hidden)
        var cards=kept.nestedUnkeyedContainer(forKey:.mine)
        for card in mine { try cards.encode(card) }
        for card in unread { try cards.encode(card) }
    }
}
extension DiscordCardDesign {
    enum CodingKeys: String, CodingKey, CaseIterable { case id,name,lineOne,lineTwo,pictures,badges,timer,button,party,pace,rank,phrase }
    init(from decoder:Decoder) throws {
        let kept=try decoder.container(keyedBy:CodingKeys.self)
        self.init(id:try kept.decode(String.self,forKey:.id),name:(try? kept.decodeIfPresent(String.self,forKey:.name)) ?? "")
        var skipped=false
        func value<T:Decodable>(_ key:CodingKeys)->T? {
            do { return try kept.decodeIfPresent(T.self,forKey:key) } catch { skipped=true;return nil }
        }
        // A list keeps what it can read; one with nothing readable left counts as not there.
        func list<T:Decodable>(_ key:CodingKeys)->[T]? {
            guard let items:[Readable<T>]=value(key) else { return nil }
            let read=items.compactMap(\.value)
            if read.count < items.count { skipped=true }
            return read.isEmpty && !items.isEmpty ? nil : read
        }
        lineOne=list(.lineOne) ?? lineOne
        lineTwo=list(.lineTwo) ?? lineTwo
        pictures=list(.pictures)
        badges=list(.badges) ?? badges
        timer=value(.timer) ?? timer
        // No second button is kept as no key at all (as nil pictures are); one this Recall doesn't know is none.
        button=value(.button)
        party=value(.party) ?? party
        pace=value(.pace) ?? pace
        rank=value(.rank) ?? rank
        phrase=value(.phrase)
        let known=Set(CodingKeys.allCases.map(\.rawValue))
        let whole=(try? decoder.singleValueContainer().decode([String:JSONValue].self)) ?? [:]
        extra=whole.filter { !known.contains($0.key) }
        // Something skipped: until the card is changed, it's written back exactly as it was read.
        if skipped { self.kept=Kept(whole:.object(whole),read:Self.known(self)) }
    }
    func encode(to encoder:Encoder) throws {
        if let kept=self.kept,Self.known(self) == kept.read { try kept.whole.encode(to:encoder);return }
        var kept=encoder.container(keyedBy:CodingKeys.self)
        try kept.encode(id,forKey:.id);try kept.encode(name,forKey:.name)
        try kept.encode(lineOne,forKey:.lineOne);try kept.encode(lineTwo,forKey:.lineTwo)
        try kept.encodeIfPresent(pictures,forKey:.pictures);try kept.encode(badges,forKey:.badges)
        try kept.encode(timer,forKey:.timer);try kept.encodeIfPresent(button,forKey:.button)
        try kept.encode(party,forKey:.party);try kept.encode(pace,forKey:.pace);try kept.encode(rank,forKey:.rank)
        try kept.encodeIfPresent(phrase,forKey:.phrase)
        var more=encoder.container(keyedBy:AnyKey.self)
        for (key,value) in extra { try more.encode(value,forKey:AnyKey(key)) }
    }
    /// A card read with something skipped: the whole of it as it was, and what this Recall made of it.
    struct Kept: Equatable { let whole:JSONValue;let read:JSONValue? }
    /// The fields this Recall knows, as JSON.
    private static func known(_ design:DiscordCardDesign)->JSONValue? {
        var plain=design;plain.kept=nil;plain.extra=[:]
        return (try? JSONEncoder().encode(plain)).flatMap { try? JSONDecoder().decode(JSONValue.self,from:$0) }
    }
}
/// One item of a list read on its own: nil when it can't be, so the rest of the list still reads, with what was there.
struct Readable<Value:Decodable>: Decodable {
    let value:Value?
    let raw:JSONValue?
    init(from decoder:Decoder) throws {
        value=try? Value(from:decoder)
        raw=value == nil ? try? JSONValue(from:decoder) : nil
        if value == nil { (decoder.userInfo[.skipped] as? Skipped)?.count+=1 }
    }
}
/// Counts the items a read had to skip (CareerHistoryStore keeps a copy of a file that lost some).
final class Skipped { var count=0 }
extension CodingUserInfoKey { static let skipped=CodingUserInfoKey(rawValue:"skipped")! }
/// Any JSON, kept as it was read.
enum JSONValue: Codable, Equatable, Hashable {
    case null,bool(Bool),number(Double),string(String),array([JSONValue]),object([String:JSONValue])
    init(from decoder:Decoder) throws {
        let one=try decoder.singleValueContainer()
        if one.decodeNil() { self = .null }
        else if let value=try? one.decode(Bool.self) { self = .bool(value) }
        else if let value=try? one.decode(Double.self) { self = .number(value) }
        else if let value=try? one.decode(String.self) { self = .string(value) }
        else if let value=try? one.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try one.decode([String:JSONValue].self)) }
    }
    func encode(to encoder:Encoder) throws {
        var one=encoder.singleValueContainer()
        switch self {
        case .null: try one.encodeNil()
        case .bool(let value): try one.encode(value)
        case .number(let value): try one.encode(value)
        case .string(let value): try one.encode(value)
        case .array(let value): try one.encode(value)
        case .object(let value): try one.encode(value)
        }
    }
}
struct AnyKey: CodingKey {
    let stringValue:String
    init(_ key:String) { stringValue=key }
    init?(stringValue:String) { self.init(stringValue) }
    var intValue:Int? { nil }
    init?(intValue:Int) { nil }
}
