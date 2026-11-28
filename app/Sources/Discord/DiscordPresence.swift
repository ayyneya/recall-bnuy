import Foundation
import CryptoKit
import Darwin

// Discord Rich Presence over the local socket every Discord client listens on (no account, no network): Discord on a
// Mac never sees Overwatch under Wine. Live reads only the voice lines of Overwatch.log (app/ARCHITECTURE.md).

/// How much the card shows. `context` tells apart the same English with two meanings ("Support" the tab, the role).
func L(_ english:String,context:String)->String {
    CardWords.english ? english : Bundle.main.localizedString(forKey:"\(english) (\(context))",value:english,table:nil)
}

/// The card is in English whatever the Mac's language; Settings stays translated. The words stay L("…") and
/// turn English inside `inEnglish`.
enum CardWords {
    private static let key="org.overwatch2mac.card-words"
    static var english:Bool { Thread.current.threadDictionary[key] as? Bool ?? false }
    static func inEnglish<T>(_ body:()->T)->T {
        let was=english;Thread.current.threadDictionary[key]=true
        defer { Thread.current.threadDictionary[key]=was }
        return body()
    }
    /// The language numbers and dates on the card are written in.
    static var locale:Locale { english ? Locale(identifier:"en_US") : Locale(identifier:AppLanguage.current) }
    static func text(_ english:String,_ values:[String])->String {
        let text=self.english ? english : Bundle.main.localizedString(forKey:english,value:english,table:nil)
        guard !values.isEmpty else { return text }
        var result="",rest=Substring(text)
        while let open=rest.firstIndex(of:"{") {
            result+=rest[..<open]
            let after=rest[rest.index(after:open)...]
            if let close=after.firstIndex(of:"}"),let index=Int(after[..<close]),values.indices.contains(index) { result+=values[index];rest=after[after.index(after:close)...] }
            else { result+="{";rest=after }
        }
        return result+rest
    }
}
/// The card's own types say their words through CardWords: inside them `L("…")` is this, not Recall's.
protocol CardText {}
extension CardText {
    func L(_ english:String,_ values:String...)->String { CardWords.text(english,values) }
    static func L(_ english:String,_ values:String...)->String { CardWords.text(english,values) }
}
extension CardInputs: CardText {}
extension CardPiece: CardText {}
extension CardPicture: CardText {}
extension BestLine: CardText {}
extension DiscordCardDesign: CardText {}
extension CareerRank: CardText {}
extension LastSession: CardText {}
extension PresenceTexts: CardText {}
extension LinePhrase: CardText {}
extension CardArt: CardText {}

enum DiscordPresenceLevel: String, CaseIterable, Identifiable {
    /// What a PC player gets, "Playing Overwatch" and the time since the game opened, with the Mac badge.
    case normal
    /// Adds the menus or a match, the match's timer and the group's voice, all from this Mac.
    case live
    /// Adds the career profile through OverFast (CareerProfile.swift): the Default card. Live until a BattleTag is
    /// entered.
    case full
    /// The player's own card, made in Customize (DiscordStudio.swift).
    case custom
    var id:String { rawValue }
    static let standard=DiscordPresenceLevel.live
    var title:String {
        switch self {
        case .normal: return L("Basic")
        case .live: return L("Live")
        case .full: return L("Full")
        case .custom: return L("Customize")
        }
    }
    /// Settings › Discord's line under the choice.
    var detail:String {
        switch self {
        case .normal: return L("Playing Overwatch, for how long, and the Mac badge.")
        case .live: return L("Plus menus or match, a match timer, and how many are in your group’s voice.")
        case .full: return L("Plus your in-game name, rank, last session, and a Career Profile button.")
        case .custom: return L("Pick what your card shows, part by part.")
        }
    }
}

/// What Discord loads for the card, in one place: the listing it runs under and the card's own pictures.
enum DiscordAssets {
    /// Blizzard's Overwatch listing, so the card reads "Playing Overwatch". Support can switch it without a
    /// release: defaults write org.overwatch2mac.launcher discordApplicationID <digits>
    static let standardID="356875221078245376"
    static var applicationID:String { override ?? standardID }
    private static var override:String? {
        UserDefaults.standard.string(forKey:"discordApplicationID").flatMap { id in (17...20).contains(id.count) && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber) ? id : nil }
    }
    /// Pictures load from the repository at a fixed tag, so a later rename on main can't break an installed card.
    /// A test build can point `preview` at a branch whose pictures aren't on that tag yet.
    static let tag="discord-art-1"
    static let official=URL(string:"https://raw.githubusercontent.com/\(Brand.forkPath)/\(tag)/app/Resources/")!
    static let preview:URL?=nil
    static var base:URL { preview ?? official }
    /// The feature's own pictures, in app/Resources/Discord.
    static func art(_ file:String)->URL { base.appendingPathComponent("Discord").appendingPathComponent(file) }
    /// The Recall badge (the app's icon) and the Mac badge (scripts/mac_badge.swift); Settings shows the app's own
    /// copies.
    static let badgeFile="AppIcon.png",macBadgeFile="MacBadge.png"
    /// Recall's own icon, beside Recall's other pictures.
    static var badge:URL { base.appendingPathComponent(badgeFile) }
    static var macBadge:URL { art(macBadgeFile) }
    /// What Discord said of the listing when Settings asked for its icon: "found", "missing" (gone or moved), or nil.
    nonisolated(unsafe) static var listing:String?
}

/// The voice channel the game talks in: the team's (a match, the Practice Range), the group's (PARTY), MATCH (the
/// voting cards).
enum VoiceChannel: Equatable { case team,party,match,other }

/// A line of Overwatch.log that tells where the player is. Times are the log's own.
enum PresenceEvent: Equatable {
    /// The log was started over (the game opened again) or replaced.
    case reset
    /// Team voice can join: the menus ("Auto-Join Enabled Flags 0000 -> 0005", bit 0x1). Team Voice off (0004) never
    /// claims them.
    case voiceReady(Date)
    /// Team voice can't any more, other flags still on (the player turned Team Voice off): nothing more is claimed.
    case voiceOff(Date)
    /// Every flag back to 0000, as the game closes (or the player turns all voice off).
    case voiceClosed(Date)
    /// Voice chat on or off as a whole ("Channel Enabled Flags 0000 -> 0005"): with it on, a voice switched off isn't
    /// the game closing.
    case chatEnabled(Bool,Date)
    /// The channel the game talks in changed ("Notified Lobby of Active channel NONE -> TEAM"); nil is none.
    case channel(VoiceChannel?,Date)
    /// Results: "Channel Enabled Flags 0005 -> 0007" opens match-wide chat, before the MATCH channel or while the
    /// team's stays open.
    case matchOver(Date)
    /// Match-wide chat closing ("0007 -> 0005"): the player left the game it was for.
    case matchChatClosed(Date)
    /// Another player joined voice ("MemberAdded … false"; the player's own says true). A team arrives within seconds;
    /// the Range and bots have none.
    case member(channel:String,who:String,Date)
    /// A player left a voice channel ("MemberRemoved <channel> <id> <user@host> <id> 0").
    case memberLeft(channel:String,who:String,Date)
    /// The game asks to join a channel ("Request join channel PARTY …"); the members named after it are that channel's.
    case joining(VoiceChannel?,id:String,Date)
    /// The channel is about to change ("__SetTargetActiveChannelType(TEAM -> PARTY) : 3"): 3 is the player's own
    /// choice, which moves only their voice; -2 and 5 are the game's.
    case switching(byPlayer:Bool,Date)

    /// When the line was written; none for a reset.
    var time:Date? {
        switch self {
        case .reset: return nil
        case .voiceReady(let time),.voiceOff(let time),.voiceClosed(let time),.chatEnabled(_,let time),.channel(_,let time),.matchOver(let time),.matchChatClosed(let time),
             .member(_,_,let time),.memberLeft(_,_,let time),.joining(_,_,let time),.switching(_,let time): return time
        }
    }

    private static let stamps:ISO8601DateFormatter={
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return formatter
    }()
    /// `[1752] [ALW] [VoiceChat] [External(0)] [External()] [2026-10-24T16:31:07.933Z]: ==[VC] Notified Lobby of Active channel NONE -> TEAM`
    static func parse(_ line:String)->PresenceEvent? {
        guard line.contains("[VoiceChat]"),let end=line.range(of:"Z]: "),let open=line[..<end.lowerBound].lastIndex(of:"["),
              let time=stamps.date(from:String(line[line.index(after:open)..<end.upperBound].dropLast(3))) else { return nil }
        let message=line[end.upperBound...].trimmingCharacters(in:.whitespacesAndNewlines)
        func words(after marker:String)->[String]? {
            message.range(of:marker).map { message[$0.upperBound...].split(separator:" ").map(String.init) }
        }
        func kind(_ name:String)->VoiceChannel? {
            switch name {
            case "NONE": return nil
            case "TEAM": return .team
            case "PARTY": return .party
            case "MATCH": return .match
            default: return .other
            }
        }
        if let parts=words(after:"Notified Lobby of Active channel ") {
            guard parts.count >= 3,parts[1] == "->" else { return nil }
            return .channel(kind(parts[2]),time)
        }
        if let parts=words(after:"__SetTargetActiveChannelType(") {
            guard parts.count == 5,parts[1] == "->",let reason=Int(parts[4]) else { return nil }
            return .switching(byPlayer:reason == 3,time)
        }
        if let parts=words(after:"Request join channel ") {
            guard parts.count >= 2,parts[0] != "NONE" else { return nil }
            return .joining(kind(parts[0]),id:parts[1],time)
        }
        if let parts=words(after:"Channel Enabled Flags ") {
            guard parts.count == 3,parts[1] == "->",let before=Int(parts[0],radix:16),let after=Int(parts[2],radix:16) else { return nil }
            // Match-wide chat turning on or off; chat as a whole turning on or off; another flag says nothing.
            if before & 0x2 == 0 && after & 0x2 != 0 && before != 0 { return .matchOver(time) }
            if before & 0x2 != 0 && after & 0x2 == 0 && after != 0 { return .matchChatClosed(time) }
            if (before == 0) != (after == 0) { return .chatEnabled(after != 0,time) }
            return nil
        }
        if let parts=words(after:"MemberAdded ") {
            return parts.count == 5 && parts[4] == "false" ? .member(channel:parts[0],who:parts[2],time) : nil
        }
        if let parts=words(after:"MemberRemoved ") {
            return parts.count == 5 ? .memberLeft(channel:parts[0],who:parts[2],time) : nil
        }
        if let parts=words(after:"Auto-Join Enabled Flags ") {
            guard parts.count == 3,parts[1] == "->",let before=Int(parts[0],radix:16),let after=Int(parts[2],radix:16) else { return nil }
            if before & 0x1 == 0 && after & 0x1 != 0 { return .voiceReady(time) }
            if before != 0 && after == 0 { return .voiceClosed(time) }
            if before & 0x1 != 0 && after & 0x1 == 0 { return .voiceOff(time) }
        }
        return nil
    }
}

/// Where the player is, as far as the log says.
enum PresenceState: Equatable {
    /// No signal (yet): the menus are not reached, or the player has voice chat off, so nothing is claimed.
    case unknown
    case menu
    case match(since:Date)
}

/// The group's voice chat: how many are in it (the player included) and its channel. The log never names the group
/// itself.
struct GroupVoice: Equatable {
    let count:Int
    let channel:String
    /// Random, made when the game joins the channel: nothing derived from the channel's short id leaves this Mac.
    let party:String
}

/// Follows the log's events. Pure: the clock comes in, so the tests can move it.
struct PresenceTracker {
    /// A team channel closing sooner was a match loading and backed out of (two to seven seconds). The timer still
    /// starts at the join.
    static let hold:TimeInterval=10
    /// Lines older than this belong to an earlier run of the game (a log not yet started over).
    let notBefore:Date
    private(set) var voiceReady=false
    /// The menus were reached at some point this run (a game that crashed at launch never gets there).
    private(set) var reachedMenus=false
    /// Voice chat is on as a whole (Channel Enabled).
    private var chatOn=false
    /// A line of this run was read: a log that says nothing can't count matches.
    private(set) var heard=false
    /// The player was in the group's voice this run, where matches go untold: the count is unknown then.
    private(set) var grouped=false
    private(set) var channel:VoiceChannel?
    /// A team channel just left: joined again within two minutes, with no result between, it's the same match (a
    /// reconnect).
    private var left:(since:Date,at:Date)?
    /// The game asked for the team's channel and no channel line followed: no menus are claimed until one does.
    private var teamAsked=false
    /// Another player's voice has joined since the channel before this one closed.
    private(set) var others=false
    /// The match's results are showing (the team's channel stays open a while longer).
    private(set) var over=false
    private var since:Date?
    /// The voice channel last asked for (its kind and id).
    private var joined:(kind:VoiceChannel?,id:String)?
    /// The group's channel, the other players in it, and the random party id the card uses for it.
    private var party:(id:String,voices:Set<String>,card:String)?
    /// The player is moving their own voice to another channel (it goes through none on the way).
    private var choosing=false
    /// The channel is the player's own choice, not where the game put them.
    private(set) var chosen=false
    /// Where the player was when they chose another voice: that moves no one, so a match goes on.
    private var kept:PresenceState?
    init(notBefore:Date = .distantPast) { self.notBefore=notBefore }
    /// Matches in this run, each counted once.
    private(set) var played=0
    private var counted:Date?
    /// Matches before the Mac slept past a night's end: tonight's count starts after them.
    private var nightBase=0
    /// The matches of tonight in this run, the one going on included.
    func tonight(at now:Date)->Int { matches(at:now)-nightBase }
    /// The Mac woke: the match it was in is over, and past a night's end tonight's count starts over.
    mutating func slept(at time:Date,newNight:Bool) {
        // The match it fell asleep in counts.
        if case .match(let since)=state(at:time),since != counted { played+=1;counted=since }
        channel=nil;since=nil;others=false;over=false;kept=nil;left=nil;teamAsked=false;choosing=false;chosen=false
        if newNight { nightBase=played }
    }
    /// The matches of this run of the game, the one going on included.
    func matches(at now:Date)->Int {
        if case .match(let since)=state(at:now),since != counted { return played+1 }
        return played
    }
    /// Lines of this run read that said something (the support report).
    private(set) var events=0
    mutating func apply(_ event:PresenceEvent) {
        if let time=event.time,time >= notBefore {
            heard=true;events+=1
            if case .match(let since)=state(at:time),since != counted { played+=1;counted=since }
        }
        switch event {
        case .reset: forget();played=0;counted=nil;nightBase=0;heard=false;grouped=false;reachedMenus=false;chatOn=false
        case .voiceReady(let time): if time >= notBefore { voiceReady=true;reachedMenus=true }
        case .voiceOff(let time): if time >= notBefore { voiceReady=false }
        // Every flag off while chat stays on is the player's choice, not the game closing: the match goes on.
        case .voiceClosed(let time): if time >= notBefore { if chatOn && channel != nil { voiceReady=false } else { forget() } }
        case .chatEnabled(let on,let time): if time >= notBefore { chatOn=on }
        case .matchOver(let time):
            guard time >= notBefore else { return }
            if channel == .team {
                over=true
                // A match with nobody else in team voice still ends with its results: it counts.
                if let since,time.timeIntervalSince(since) >= Self.hold,since != counted { played+=1;counted=since }
            }
            // A match kept through the player's own voice choice is over too.
            if case .match? = kept { kept=voiceReady ? .menu : nil }
        case .matchChatClosed(let time): if time >= notBefore,case .match? = kept { kept=nil }
        case .switching(let byPlayer,let time):
            guard time >= notBefore else { return }
            // Only a match is kept: menus are never claimed from a voice the player chose.
            if byPlayer && !choosing { if case .match=state(at:time) { kept=state(at:time) } else { kept=nil } }
            choosing=byPlayer
        case .member(let id,let who,let time):
            guard time >= notBefore else { return }
            // A team's voice: the group's or match-wide channel's players are not one (a custom game talks match-wide).
            if !(joined?.id == id && joined?.kind != .team) { others=true }
            if id == party?.id {
                if renaming { party?.voices=[];renaming=false }
                party?.voices.insert(who)
            }
        case .memberLeft(let id,let who,let time): if time >= notBefore && id == party?.id { party?.voices.remove(who) }
        // The game leaves every channel before it joins one, and names who is in the new one after.
        case .joining(let kind,let id,let time):
            guard time >= notBefore else { return }
            joined=(kind,id)
            if kind == .team { teamAsked=true }
            // The same group's channel again keeps its voices until the game names them anew (the first one it names).
            if kind == .party { party=party?.id == id ? (id,party!.voices,party!.card) : (id,[],UUID().uuidString);renaming=party?.id == id }
        case .channel(let next,let time):
            guard time >= notBefore else { return }
            // The player's own switch passes through no channel: that is not leaving anything.
            if next == nil && choosing { return }
            // The same channel again keeps its first time; another ends what the results said (a group goes to the
            // team's channel and back).
            if next != nil { teamAsked=false }
            if next == .party { grouped=true }
            if next != channel {
                // A match left before its results: remembered, so a quick rejoin is the same match.
                if channel == .team,let since,!over,others,time.timeIntervalSince(since) >= Self.hold { left=(since,time) } else if channel == .team { left=nil }
                channel=next;since=next == nil ? nil : time;over=false
                if next == .team,let left,time.timeIntervalSince(left.at) < 120 { since=left.since }
                // Only a quick drop through no channel is a rejoin: any other channel ends what was left.
                if next != nil { left=nil }
            }
            if next == nil { others=false;over=false }
            if next != nil {
                chosen=choosing;choosing=false
                // Where the game puts the player is a new place; what they were keeping is over.
                if !chosen { kept=nil }
            }
        }
    }
    private mutating func forget() {
        voiceReady=false;channel=nil;since=nil;others=false;over=false;joined=nil;party=nil
        choosing=false;chosen=false;kept=nil;left=nil;teamAsked=false;renaming=false
    }
    /// The group's channel was joined again: the first voice named starts its list over.
    private var renaming=false
    func state(at now:Date)->PresenceState {
        // A match the player was in when they chose their voice goes on, with its own timer.
        if case .match? = kept { return kept! }
        let place=channelState(at:now)
        if case .match = place { return place }
        // In the group's voice a match can begin without a line, so menus are not kept there.
        return channel == .party ? place : (kept ?? place)
    }
    /// The group's voice chat while the player is in it; nobody else in it is nothing to tell.
    var groupVoice:GroupVoice? {
        guard channel == .party,let party,!party.voices.isEmpty else { return nil }
        return GroupVoice(count:party.voices.count+1,channel:party.id,party:party.card)
    }
    /// Where the channel alone says the player is.
    private func channelState(at now:Date)->PresenceState {
        switch channel {
        case .team?:
            // The results are showing: the match is over, whatever the channel still says.
            if over { return voiceReady ? .menu : .unknown }
            // A team channel with nobody else (the Range, bots) claims nothing; chosen by the player, it's a game
            // already going on.
            guard let since,now.timeIntervalSince(since) >= Self.hold else { return voiceReady && !chosen ? .menu : .unknown }
            return others ? .match(since:since) : .unknown
        // In a group the log says nothing of menus or matches: nothing is claimed.
        case .party?: return .unknown
        // After a match: back to the menus. Chosen by the player (a custom game's match-wide voice), it says nothing.
        case .match?: return chosen ? .unknown : (voiceReady ? .menu : .unknown)
        case .other?: return .unknown
        case nil: return voiceReady && !teamAsked ? .menu : .unknown
        }
    }
    /// Seconds until a team channel that is not held long enough yet counts as a match.
    func nextChange(at now:Date)->TimeInterval? {
        guard channel == .team,let since else { return nil }
        let rest=Self.hold-now.timeIntervalSince(since)
        return rest > 0 ? rest : nil
    }
}

/// What each source knows, on its own: for now the game's log. The card is made from these alone, so a new source only
/// adds facts here.
struct PresenceFacts: Equatable {
    var place:PresenceState = .unknown
    var voice:GroupVoice?
    /// Whether the match is competitive: nothing can tell yet.
    var competitive:Bool?
}

/// The card's words, passed in through L.
struct PresenceTexts: Equatable {
    var menu:String
    var match:String
    /// Line 2 in the group's voice, which Discord follows with the count ("In Group Voice (3 of 5)").
    var voice:String
    /// The hover text of the small Recall badge.
    var badge:String
    /// Where the log can't tell menus from a match: in the group's voice, or not.
    var group=L("In Group")
    var game=L("In Game")
    static var app:PresenceTexts { CardWords.inEnglish {
        PresenceTexts(menu:L("In Menus"),match:L("In Match"),voice:L("In Group Voice"),badge:L("Playing on Mac with {0}",Brand.name),group:L("In Group"),game:L("In Game")) }
    }
}

/// Discord's limits, applied to every card as it's sent (one field past them and Discord refuses the whole card).
/// Lengths in UTF-16, as Discord counts.
enum DiscordRules {
    static func clean(_ card:[String:Any])->[String:Any] {
        var out=card
        for key in ["details","state"] { out[key]=text(card[key] as? String,128) }
        if var assets=card["assets"] as? [String:String] {
            for key in ["large_text","small_text"] { assets[key]=text(assets[key],128) }
            for key in ["large_image","small_image"] { assets[key]=assets[key].flatMap(image) }
            out["assets"]=assets.isEmpty ? nil : assets
        }
        if let buttons=card["buttons"] as? [[String:String]] {
            let kept=buttons.compactMap { button -> [String:String]? in
                guard let label=text(button["label"],32,least:1),let url=button["url"],url.utf16.count <= 512,URL(string:url)?.scheme == "https" else { return nil }
                return ["label":label,"url":url]
            }.prefix(2)
            out["buttons"]=kept.isEmpty ? nil : Array(kept)
        }
        if let party=card["party"] as? [String:Any] {
            let size=party["size"] as? [Int]
            let fine=(party["id"] as? String).map { (2...128).contains($0.utf16.count) } == true && size.map { $0.count == 2 && $0[0] >= 1 && $0[0] <= $0[1] } == true
            out["party"]=fine ? party : nil
        }
        return out
    }
    /// Trimmed, without control or direction characters, cut at a whole character with "…"; nil when too short.
    static func text(_ value:String?,_ limit:Int,least:Int=2)->String? {
        guard let value else { return nil }
        let hidden:Set<Unicode.GeneralCategory>=[.control,.format,.lineSeparator,.paragraphSeparator]
        var clean=String(String.UnicodeScalarView(value.unicodeScalars.filter { !hidden.contains($0.properties.generalCategory) || $0 == "\u{200D}" }))
            .trimmingCharacters(in:.whitespacesAndNewlines)
        if clean.utf16.count > limit {
            var cut=""
            for character in clean { if (cut+String(character)).utf16.count+1 > limit { break };cut.append(character) }
            clean=cut.trimmingCharacters(in:.whitespaces)+"…"
        }
        return clean.utf16.count >= least ? clean : nil
    }
    /// A picture Discord loads itself: https, 300 characters at most.
    static func image(_ url:String)->String? { url.utf16.count <= 300 && URL(string:url)?.scheme == "https" ? url : nil }
}

enum PresenceCard {
    /// Discord takes 128 characters at most in a line or a hover text (DiscordRules applies it to every card).
    static func fit(_ text:String)->String { DiscordRules.text(text,128,least:0) ?? text }
    /// Overwatch's largest group: six (6v6).
    static let largestGroup=6
    /// The group's count for Discord ("3 of 5"): of five, the usual team, unless six are in it.
    static func party(_ voice:GroupVoice)->[String:Any] {
        let count=min(voice.count,largestGroup)
        return ["id":voice.party,"size":[count,max(5,count)]]
    }
    /// The card at Normal and Live (Full's comes from its design): Normal is a PC player's with the Mac badge; Live
    /// adds place, match timer and group voice.
    static func activity(facts:PresenceFacts,level:DiscordPresenceLevel,launched:Date,texts:PresenceTexts)->[String:Any] {
        var card:[String:Any]=["type":0,"timestamps":["start":Int(launched.timeIntervalSince1970)],
            "assets":["small_image":DiscordAssets.macBadge.absoluteString,"small_text":texts.badge]]
        guard level != .normal else { return card }
        switch facts.place {
        // Menus and matches can't be told apart (voice chat off, or a group's voice): only that the game is on.
        case .unknown: if facts.voice == nil { card["details"]=texts.game }
        case .menu: card["details"]=texts.menu
        case .match(let since): card["details"]=texts.match;card["timestamps"]=["start":Int(since.timeIntervalSince1970)]
        }
        // The party's size is the voice chat's: the line says so, since the log never tells the group's own.
        if let voice=facts.voice { card["state"]=texts.voice;card["party"]=party(voice) }
        return card
    }
}

/// Discord's local protocol: a 4-byte opcode and a 4-byte length (little-endian), then the JSON.
enum DiscordFrame {
    static let handshake:UInt32=0,frame:UInt32=1,close:UInt32=2,ping:UInt32=3,pong:UInt32=4
    static func encode(_ opcode:UInt32,_ payload:Any)->Data? {
        guard JSONSerialization.isValidJSONObject(payload),let body=try? JSONSerialization.data(withJSONObject:payload) else { return nil }
        var data=Data()
        for value in [opcode,UInt32(body.count)] { withUnsafeBytes(of:value.littleEndian) { data.append(contentsOf:$0) } }
        data.append(body)
        return data
    }
}

/// Cuts the bytes read from the socket into frames; a frame can arrive in pieces or several at once.
struct DiscordFrameReader {
    struct Frame: Equatable { let opcode:UInt32;let body:Data }
    /// Discord's frames are small; a longer one is not Discord speaking.
    static let longest=1<<20
    private var bytes:[UInt8]=[]
    private(set) var broken=false
    mutating func feed(_ data:Data)->[Frame] {
        bytes+=data
        var frames:[Frame]=[]
        while bytes.count >= 8 {
            func word(_ at:Int)->UInt32 { UInt32(bytes[at])|UInt32(bytes[at+1])<<8|UInt32(bytes[at+2])<<16|UInt32(bytes[at+3])<<24 }
            let length=Int(word(4))
            if length > Self.longest { broken=true;bytes=[];break }
            guard bytes.count >= 8+length else { break }
            frames.append(Frame(opcode:word(0),body:Data(bytes[8..<8+length])))
            bytes.removeFirst(8+length)
        }
        return frames
    }
}

/// The connection to Discord on this Mac, safe from any thread: the first of discord-ipc-0 to -9 that answers, tried
/// every half minute while there's a card.
final class DiscordIPC {
    private let queue=DispatchQueue(label:"org.overwatch2mac.discord-presence",qos:.utility)
    private let paths:[String]
    private let applicationID:String
    private let pid:Int32
    /// Discord takes five updates in twenty seconds: a burst within that, with a short gap so one event's changes are
    /// one update.
    private let spacing:TimeInterval
    private let burst:Int
    private let window:TimeInterval
    private let retryDelay:TimeInterval
    private var descriptor:Int32 = -1
    private var source:DispatchSourceRead?
    private var reader=DiscordFrameReader()
    private var ready=false
    private var active=false
    /// What the card should be; nil takes it down.
    private var wanted:[String:Any]?
    private var pending=false
    /// When the last window's updates went, oldest first, on a clock the Mac's time can't move.
    private var sent:[TimeInterval]=[]
    private static var clock:TimeInterval { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC))/1e9 }
    private var timer:DispatchWorkItem?
    private var handshakeTimeout:DispatchWorkItem?
    /// A retry is waiting: one at a time.
    private var retrying=false
    private var tries=0
    private let lock=NSLock()
    private var connectedFlag=false,acceptedFlag=false
    /// Whether Discord has answered, for the support report.
    var connected:Bool { lock.lock();defer { lock.unlock() };return connectedFlag }
    /// Whether Discord took the last card sent (it answers each one, with an error when it refuses it).
    var accepted:Bool { lock.lock();defer { lock.unlock() };return acceptedFlag }
    /// How many times the sockets were looked for, for the tests.
    var attempts:Int { queue.sync { tries } }

    init(applicationID:String=DiscordAssets.applicationID,paths:[String]?=nil,pid:Int32=getpid(),spacing:TimeInterval=0.5,burst:Int=5,window:TimeInterval=20,retry:TimeInterval=30) {
        self.applicationID=applicationID;self.pid=pid;self.spacing=spacing;self.burst=burst;self.window=window;self.retryDelay=retry
        self.paths=paths ?? Self.defaultPaths()
    }
    /// This user's own temporary folder, which no other account can write to (not /tmp).
    static func defaultPaths()->[String] {
        let folder=NSTemporaryDirectory()
        return (0..<10).map { (folder.hasSuffix("/") ? folder : folder+"/")+"discord-ipc-\($0)" }
    }
    /// Shows the card, or takes it down with nil; waits until Discord is there. `profile`: the card shows the profile,
    /// so it never goes to another Discord account.
    func set(_ activity:[String:Any]?,profile:Bool=false) {
        queue.async {
            self.wanted=activity;self.wantedProfile=profile;self.pending=true;self.active=true
            if self.ready { self.flush() } else if self.descriptor < 0 && !self.refused { self.connect() }
        }
    }
    /// Takes the card down and closes. Nothing more is sent until set is called again.
    func stop() {
        queue.sync {
            if ready { send(DiscordFrame.frame,activityCommand(nil)) }
            active=false;pending=false;wanted=nil;refused=false;lean=0
            timer?.cancel();timer=nil
            disconnect()
        }
    }

    private func activityCommand(_ activity:[String:Any]?)->[String:Any] {
        let nonce=UUID().uuidString;sentNonce=nonce
        return ["cmd":"SET_ACTIVITY","args":["pid":pid,"activity":activity.map { Self.leaner($0,lean) as Any } ?? NSNull()],"nonce":nonce]
    }
    /// A refused card is sent again leaner until the next READY: no buttons, party or pictures, then the timer alone,
    /// so it still shows "Playing Overwatch".
    private var lean=0
    private var sentNonce:String?
    static func leaner(_ activity:[String:Any],_ step:Int)->[String:Any] {
        switch step {
        case 0: return activity
        case 1: var card=activity;card["buttons"]=nil;card["party"]=nil;card["assets"]=nil;return card
        default: return activity.filter { $0.key == "type" || $0.key == "timestamps" }
        }
    }
    /// The Discord account signed in, as READY names it, scrambled: never the account itself.
    var signedIn:((String?)->Void)?
    /// Asked at READY, before anything is sent: true when the account signed in isn't the profile's.
    var holdsBack:((String?)->Bool)?
    private var withheld=false,wantedProfile=false
    /// A hash of the account's id with a salt only this Mac has: it tells two accounts apart and nothing more.
    static func scrambled(_ id:String)->String {
        let store=UserDefaults.standard
        let salt=store.string(forKey:"discordAccountSalt") ?? { let made=UUID().uuidString;store.set(made,forKey:"discordAccountSalt");return made }()
        return SHA256.hash(data:Data((salt+id).utf8)).prefix(12).map { String(format:"%02x",$0) }.joined()
    }
    /// Discord's last answer, for the support report (never the card's text): it outlives stop().
    var lastAnswer:String? { lock.lock();defer { lock.unlock() };return answer }
    private var answer:String?
    private func answered(_ text:String) { lock.lock();answer=text;lock.unlock() }
    /// Discord closed for a reason asking again won't change (an unknown listing, version or encoding): nothing more
    /// until the next game.
    private var refused=false
    private func flush() {
        guard ready,pending else { return }
        if withheld && wantedProfile { pending=false;return }
        let now=Self.clock
        sent.removeAll { now-$0 >= window }
        var wait=sent.last.map { spacing-(now-$0) } ?? 0
        if sent.count >= burst { wait=max(wait,window-(now-sent[sent.count-burst])) }
        if wait > 0 {
            guard timer == nil else { return }
            let work=DispatchWorkItem { [weak self] in self?.timer=nil;self?.flush() }
            timer=work;queue.asyncAfter(deadline:.now()+wait,execute:work)
            return
        }
        pending=false;sent.append(now)
        if !send(DiscordFrame.frame,activityCommand(wanted)) { disconnect();scheduleRetry() }
    }
    private func connect() {
        guard active,descriptor < 0 else { return }
        tries+=1
        for path in paths {
            let fd=socket(AF_UNIX,SOCK_STREAM,0)
            guard fd >= 0 else { continue }
            var on:Int32=1
            setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&on,socklen_t(MemoryLayout<Int32>.size))
            var address=sockaddr_un()
            address.sun_family=sa_family_t(AF_UNIX)
            let capacity=MemoryLayout.size(ofValue:address.sun_path)
            guard path.utf8.count < capacity else { close(fd);continue }
            withUnsafeMutablePointer(to:&address.sun_path) { $0.withMemoryRebound(to:CChar.self,capacity:capacity) { _ = strlcpy($0,path,capacity) } }
            let result=withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard result == 0 else { close(fd);continue }
            // Only a program of this user's own is Discord for this purpose.
            var owner:uid_t=0,group:gid_t=0
            guard getpeereid(fd,&owner,&group) == 0,owner == getuid() else { close(fd);continue }
            _ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK)
            descriptor=fd;reader=DiscordFrameReader();ready=false
            let reading=DispatchSource.makeReadSource(fileDescriptor:fd,queue:queue)
            reading.setEventHandler { [weak self] in self?.readable() }
            // Closed only once the source has let go of it, so a new socket never gets its number meanwhile.
            reading.setCancelHandler { close(fd) }
            reading.resume();source=reading
            guard send(DiscordFrame.handshake,["v":1,"client_id":applicationID]) else { disconnect();continue }
            // Discord answers with READY; one that does not within a few seconds is not usable.
            let timeout=DispatchWorkItem { [weak self] in
                guard let self,!self.ready else { return }
                self.disconnect();self.scheduleRetry()
            }
            handshakeTimeout=timeout;queue.asyncAfter(deadline:.now()+5,execute:timeout)
            return
        }
        scheduleRetry()
    }
    private func readable() {
        var buffer=[UInt8](repeating:0,count:4096)
        let count=read(descriptor,&buffer,buffer.count)
        if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) { disconnect();scheduleRetry();return }
        guard count > 0 else { return }
        let frames=reader.feed(Data(buffer[0..<count]))
        if reader.broken { disconnect();scheduleRetry();return }
        for frame in frames {
            switch frame.opcode {
            case DiscordFrame.ping: send(DiscordFrame.pong,(try? JSONSerialization.jsonObject(with:frame.body)) ?? [String:Any]())
            case DiscordFrame.close:
                let code=(try? JSONSerialization.jsonObject(with:frame.body) as? [String:Any])?["code"] as? Int
                answered("closed_\(code.map(String.init) ?? "unknown")")
                // 4000 an unknown listing, 4004 and 4005 a version or encoding; 4002, asking too often, waits longer.
                if let code,[4000,4004,4005].contains(code) { refused=true }
                disconnect();scheduleRetry(longer:code == 4002);return
            case DiscordFrame.frame:
                guard let message=try? JSONSerialization.jsonObject(with:frame.body) as? [String:Any] else { break }
                if message["evt"] as? String == "READY" {
                    handshakeTimeout?.cancel();ready=true;pending=true;lean=0
                    let user=((message["data"] as? [String:Any])?["user"] as? [String:Any])?["id"] as? String
                    let account=user.map(Self.scrambled)
                    lock.lock();connectedFlag=true;lock.unlock()
                    answered("ready")
                    signedIn?(account)
                    // Another account than the profile's never gets a card with the profile, whenever it was built.
                    withheld=holdsBack?(account) ?? false
                    flush()
                } else if message["cmd"] as? String == "SET_ACTIVITY" {
                    let taken=message["evt"] as? String != "ERROR"
                    lock.lock();acceptedFlag=taken;lock.unlock()
                    if taken { answered(lean == 0 ? "accepted" : "accepted_lean_\(lean)") }
                    else {
                        let code=(message["data"] as? [String:Any])?["code"] as? Int
                        answered("refused_\(code.map(String.init) ?? "unknown")")
                        // The card that was refused, sent again leaner (a card taken down needs nothing).
                        if message["nonce"] as? String == sentNonce,wanted != nil,lean < 2 { lean+=1;pending=true;flush() }
                    }
                }
            default: break
            }
        }
    }
    @discardableResult private func send(_ opcode:UInt32,_ payload:Any)->Bool {
        guard descriptor >= 0,let data=DiscordFrame.encode(opcode,payload) else { return false }
        var sent=0
        let ok=data.withUnsafeBytes { raw -> Bool in
            while sent < data.count {
                let n=write(descriptor,raw.baseAddress!+sent,data.count-sent)
                if n > 0 { sent+=n } else if n < 0 && (errno == EINTR) { continue }
                // Discord reading slowly fills the socket: room is waited for (two seconds at most), not taken as a drop.
                else if n < 0 && errno == EAGAIN {
                    var room=pollfd(fd:descriptor,events:Int16(POLLOUT),revents:0)
                    if poll(&room,1,2000) > 0 { continue } else { return false }
                } else { return false }
            }
            return true
        }
        return ok
    }
    private func disconnect() {
        // The source closes the socket (its cancel handler); one is always made with it.
        source?.cancel();source=nil;descriptor = -1
        handshakeTimeout?.cancel();handshakeTimeout=nil
        ready=false
        lock.lock();connectedFlag=false;acceptedFlag=false;lock.unlock()
    }
    private func scheduleRetry(longer:Bool=false) {
        guard active,!retrying,!refused else { return }
        retrying=true
        queue.asyncAfter(deadline:.now()+retryDelay*(longer ? 10 : 1)) { [weak self] in
            guard let self else { return }
            self.retrying=false
            guard self.active,self.descriptor < 0 else { return }
            self.pending=true;self.connect()
        }
    }
}

/// Follows Overwatch.log while the game runs: reads it once, then only what's added when the file or its folder changes
/// (nothing polls). Starting over or replaced gives a reset. Never writes in the game's folders.
final class OverwatchLogTail {
    private let url:URL
    private let queue:DispatchQueue
    private let handler:([PresenceEvent])->Void
    private var descriptor:Int32 = -1
    private var identity:UInt64=0
    private var offset:off_t=0
    private var partial:[UInt8]=[]
    private var fileSource:DispatchSourceFileSystemObject?
    private var folderSource:DispatchSourceFileSystemObject?
    private var stopped=true
    /// What is read into, kept from one read to the next.
    private var chunk=[UInt8](repeating:0,count:65536)
    /// Marks the queue, so stop() called from its own work doesn't wait for itself.
    private static let onQueue=DispatchSpecificKey<ObjectIdentifier>()
    private var onOwnQueue:Bool { DispatchQueue.getSpecific(key:Self.onQueue) == ObjectIdentifier(queue) }
    init(url:URL,queue:DispatchQueue,handler:@escaping ([PresenceEvent])->Void) {
        self.url=url;self.queue=queue;self.handler=handler
        queue.setSpecific(key:Self.onQueue,value:ObjectIdentifier(queue))
    }

    /// The game's log in this data folder: the Windows user's Documents in the engine's prefix.
    static func logURL(root:URL)->URL? {
        let users=root.appendingPathComponent("environment/drive_c/users")
        let names=((try? FileManager.default.contentsOfDirectory(atPath:users.path)) ?? []).filter { $0 != "Public" && !$0.hasPrefix(".") }.sorted()
        func log(_ name:String)->URL { users.appendingPathComponent(name).appendingPathComponent("Documents/Overwatch/Logs/Overwatch.log") }
        // Two users with a log (an old prefix's left behind): the one written last.
        func written(_ name:String)->Date? { (try? FileManager.default.attributesOfItem(atPath:log(name).path))?[.modificationDate] as? Date }
        if let newest=names.compactMap({ name in written(name).map { (name,$0) } }).max(by:{ $0.1 < $1.1 }) { return log(newest.0) }
        return names.first { FileManager.default.fileExists(atPath:log($0).deletingLastPathComponent().path) }.map(log) ?? names.first.map(log)
    }

    /// From the owner's queue it reads before returning, so the right card shows at once.
    func start() {
        let begin={ self.stopped=false;self.watchFolder();self.check() }
        if onOwnQueue { begin() } else { queue.async(execute:begin) }
    }
    func stop() {
        let teardown={
            self.stopped=true
            self.folderSource?.cancel();self.folderSource=nil
            self.closeFile()
        }
        if onOwnQueue { teardown() } else { queue.sync(execute:teardown) }
    }

    /// Watches the Logs folder, or before the game makes it, the nearest folder above, moving down as each appears.
    private func watchFolder() {
        guard folderSource == nil,!stopped else { return }
        let logs=url.deletingLastPathComponent()
        var folder=logs,fd=open(folder.path,O_EVTONLY)
        while fd < 0 && folder.path != "/" { folder.deleteLastPathComponent();fd=open(folder.path,O_EVTONLY) }
        guard fd >= 0 else { return }
        let waiting=folder.path != logs.path
        let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:.write,queue:queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if waiting { self.folderSource?.cancel();self.folderSource=nil;self.watchFolder() }
            self.check()
        }
        source.setCancelHandler { close(fd) }
        source.resume();folderSource=source
        // The next folder down may have appeared before the watch began; one that can't be opened is waited on from
        // here.
        guard waiting else { return }
        let next=open(folder.appendingPathComponent(logs.pathComponents[folder.pathComponents.count]).path,O_EVTONLY)
        if next >= 0 { close(next);source.cancel();folderSource=nil;watchFolder() }
    }
    private func closeFile() {
        // The file's source closes it (its cancel handler); one is always made with it.
        fileSource?.cancel();fileSource=nil;descriptor = -1
        offset=0;partial=[]
    }
    /// The file may be new, gone or another file than the one followed.
    private func check() {
        guard !stopped else { return }
        var status=stat()
        guard stat(url.path,&status) == 0 else {
            if descriptor >= 0 { closeFile();handler([.reset]) }
            return
        }
        if descriptor >= 0 && UInt64(status.st_ino) != identity { closeFile();handler([.reset]) }
        if descriptor < 0 {
            let fd=open(url.path,O_RDONLY|O_CLOEXEC)
            guard fd >= 0 else { return }
            descriptor=fd;identity=UInt64(status.st_ino);offset=0;partial=[]
            let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:[.write,.extend,.delete,.rename],queue:queue)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                if source.data.contains(.delete) || source.data.contains(.rename) { self.check() } else { self.readNew() }
            }
            source.setCancelHandler { close(fd) }
            source.resume();fileSource=source
        }
        readNew()
    }
    private func readNew() {
        guard descriptor >= 0 else { return }
        var events:[PresenceEvent]=[]
        var status=stat()
        if fstat(descriptor,&status) == 0,status.st_size < offset { offset=0;partial=[];events.append(.reset) }
        while true {
            let count=pread(descriptor,&chunk,chunk.count,offset)
            guard count > 0 else { break }
            offset+=off_t(count);partial+=chunk[0..<count]
            // Each whole line, then the read part is dropped at once.
            var start=partial.startIndex
            while let end=partial[start...].firstIndex(of:10) {
                if let event=PresenceEvent.parse(String(decoding:partial[start..<end],as:UTF8.self)) { events.append(event) }
                start=end+1
            }
            partial.removeSubrange(..<start)
        }
        if !events.isEmpty { handler(events) }
    }
}

/// One run of the game, as this Mac saw it (kept in the history, CareerHistory.swift).
struct PlayedRun: Codable, Equatable {
    var start:Date
    var end:Date
    /// The matches the log counted; nil when it wasn't followed (Normal).
    var matches:Int?
    /// Seconds the Mac slept while the game was open; nil when it didn't.
    var slept:TimeInterval?
    /// The same game: within a second (older files keep fractions).
    func sameStart(_ other:PlayedRun)->Bool { abs(start.timeIntervalSince(other.start)) < 1 }
}

/// The card for the running game: follows the log (Live and up) and keeps Discord's card current. Safe from any thread.
final class DiscordPresence {
    private let ipc:DiscordIPC
    private let queue=DispatchQueue(label:"org.overwatch2mac.discord-presence-state",qos:.utility)
    private var level:DiscordPresenceLevel
    private var texts:PresenceTexts
    private var logURL:URL?
    private var launched=Date()
    private var tracker=PresenceTracker()
    private var tail:OverwatchLogTail?
    private var running=false
    private var shown:NSDictionary?
    /// Full: the profile, the BattleTag's name, the design (Default), and what Recall remembers.
    private var career:CareerCard?
    private var tagName:String?
    /// The player's own card, for Custom (Full's is Default).
    private var design=DiscordCardDesign.standard
    private let history:CareerHistoryStore
    /// The next refresh: a team channel becoming a match, or the card's next turn.
    private var promotion:DispatchWorkItem?
    init(level:DiscordPresenceLevel,texts:PresenceTexts,history:CareerHistoryStore=CareerHistoryStore(url:nil),ipc:DiscordIPC=DiscordIPC()) {
        self.level=level;self.texts=texts;self.history=history;self.ipc=ipc
        ipc.holdsBack={ [weak self] account in self?.holdsBack(account) ?? false }
    }
    /// Whether Discord has answered, and whether it took the last card (for the support report).
    var connected:Bool { ipc.connected }
    var accepted:Bool { ipc.accepted }
    var lastAnswer:String? { ipc.lastAnswer }
    /// The log for the support report: not_running, missing (a patch moved it), or found, with how many lines said
    /// something.
    var logReport:[String:Any] {
        queue.sync {
            guard running else { return ["state":"not_running"] }
            guard let logURL,FileManager.default.fileExists(atPath:logURL.path) else { return ["state":"missing"] }
            return ["state":"found","events":tracker.events]
        }
    }
    /// When a process started, from the system (macOS gives no launch date for the game's Wine app).
    static func startTime(of pid:pid_t)->Date? {
        var info=proc_bsdinfo()
        guard proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        return Date(timeIntervalSince1970:TimeInterval(info.pbi_start_tvsec)+TimeInterval(info.pbi_start_tvusec)/1_000_000)
    }

    /// The Mac slept with the game open: not play. Over a minute and a half ends the match; past 4 am, tonight's count
    /// starts over.
    func slept(from:Date,to:Date) {
        queue.async {
            guard self.running,to > from else { return }
            self.asleep+=to.timeIntervalSince(from)
            if to.timeIntervalSince(from) > 90 { self.tracker.slept(at:from,newNight:CareerHistory.night(from,.current) != CareerHistory.night(to,.current)) }
            self.refresh()
        }
    }
    /// Seconds this run spent with the Mac asleep.
    private var asleep:TimeInterval=0
    /// What Recall remembers was erased while the game ran: the run counts from then, with the matches after.
    func erased(at time:Date?) {
        queue.async { self.recordFrom=time.map { ($0,self.tracker.matches(at:$0)) } }
    }
    private var recordFrom:(at:Date,matches:Int)?
    /// The game is running. `launched` is when it opened; nil when that is not known, which counts from now.
    func begin(logURL:URL?,launched:Date?) {
        queue.async {
            guard !self.running else { return }
            // In whole seconds, as the history file keeps it: a run Recall quit during is known again by its start.
            self.running=true;self.asleep=0;self.quiet=false;self.recordFrom=nil;self.logURL=logURL;self.launched=Date(timeIntervalSince1970:(launched ?? Date()).timeIntervalSince1970.rounded(.down))
            self.tracker=PresenceTracker(notBefore:launched.map { $0.addingTimeInterval(-5) } ?? .distantPast)
            self.followLog();self.refresh()
        }
    }
    /// The game closed: the run, with the log's matches (nil when not read). Called on the presence's queue.
    var sessionEnded:((PlayedRun)->Void)?
    /// What the game is doing, for Settings' preview; nil once closed. Called on the presence's queue.
    var gameChanged:((_ live:(place:PresenceState,voice:GroupVoice?,matches:Int,launched:Date)?)->Void)?
    private var told:String?
    /// The card comes down; `ran` false while the game goes on (turned off): the run goes into the history at its end.
    func end(ran:Bool=true) {
        // One step on the queue, so a begin from another thread comes wholly before or after.
        queue.sync {
            guard running else { return }
            let now=Date()
            // A game closed within two minutes without reaching the menus (a crash at launch) isn't a session. Matches
            // are unknown when the log said nothing or was in group voice.
            let crashed=now.timeIntervalSince(launched) < 120 && !(tail != nil && tracker.reachedMenus)
            let known=tail != nil && tracker.heard && !tracker.grouped
            let matches=known ? max(0,tracker.matches(at:now)-(recordFrom?.matches ?? 0)) : nil
            if ran && !crashed { sessionEnded?(PlayedRun(start:recordFrom.map { max($0.at,launched) } ?? launched,end:now,matches:matches,slept:asleep > 0 ? asleep : nil)) }
            running=false;told=nil;gameChanged?(nil)
            tail?.stop();tail=nil
            promotion?.cancel();promotion=nil
            shown=nil
            ipc.stop()
        }
    }
    /// The career profile (Full); nil when there's none to show. The BattleTag's name stands in on Line 1. `signedIn`:
    /// the Discord account at each READY, scrambled.
    var signedIn:((String?)->Void)? { get { ipc.signedIn } set { ipc.signedIn=newValue } }
    /// The account the profile belongs to, scrambled (nil: the first signed in takes it). Another account gets no
    /// Profile.
    var owner:String? {
        get { ownerLock.lock();defer { ownerLock.unlock() };return ownerValue }
        set { ownerLock.lock();ownerValue=newValue;ownerLock.unlock() }
    }
    private let ownerLock=NSLock()
    private var ownerValue:String?
    private var signedInValue:String?
    /// The account signed in isn't the profile's: every card from here on is built without the profile.
    private func holdsBack(_ account:String?)->Bool {
        ownerLock.lock();signedInValue=account;ownerLock.unlock()
        let other=otherAccount
        if other { queue.async { self.shown=nil;self.refresh() } }
        return other
    }
    /// Another account than the profile's is signed in.
    private var otherAccount:Bool {
        ownerLock.lock();defer { ownerLock.unlock() }
        return signedInValue != nil && ownerValue != nil && signedInValue != ownerValue
    }
    func update(career:CareerCard?,tagName:String?) {
        queue.async { self.career=career;self.tagName=tagName;self.refresh() }
    }
    func update(design:DiscordCardDesign) {
        queue.async { self.design=design;self.refresh() }
    }
    /// Turned off while the game runs: the card comes down, but the run is still followed, so its hours and matches go
    /// into the history.
    func update(quiet:Bool) {
        queue.async {
            guard self.quiet != quiet else { return }
            self.quiet=quiet;self.shown=nil
            if quiet { self.ipc.set(nil) } else { self.refresh() }
        }
    }
    private var quiet=false
    func update(level:DiscordPresenceLevel,texts:PresenceTexts) {
        queue.async {
            // Every level but Normal reads the log.
            let changed=(level == .normal) != (self.level == .normal)
            self.level=level;self.texts=texts
            if changed && self.running { self.followLog() }
            self.refresh()
        }
    }

    /// Only Live reads the log; Normal shows nothing the game says.
    private func followLog() {
        tail?.stop();tail=nil
        tracker=PresenceTracker(notBefore:tracker.notBefore)
        guard level != .normal,let logURL else { return }
        let tail=OverwatchLogTail(url:logURL,queue:queue) { [weak self] events in
            guard let self,self.running else { return }
            for event in events { self.tracker.apply(event) }
            self.refresh()
        }
        self.tail=tail;tail.start()
    }
    private func refresh() {
        guard running else { return }
        // Read once: the card and what it's tagged with agree, whatever READY says meanwhile.
        let now=Date(),mine=otherAccount == false
        let facts=PresenceFacts(place:tracker.state(at:now),voice:tracker.groupVoice)
        let matches=tracker.tonight(at:now),key="\(facts.place) \(String(describing:facts.voice)) \(matches)"
        if key != told { told=key;gameChanged?((facts.place,facts.voice,matches,launched)) }
        var wait=tracker.nextChange(at:now)
        let card:[String:Any]
        if level == .full || level == .custom {
            let design=level == .full ? DiscordCardDesign.standard : self.design
            let inputs=CardInputs(place:facts.place,voice:facts.voice,competitive:facts.competitive,profile:mine ? career : nil,history:history.current,tagName:mine ? tagName : nil,
                                  launched:launched,matches:matches,slept:asleep,now:now,texts:texts)
            card=design.activity(inputs)
            // The card's lists take their next turn: one update then (Discord takes one every few seconds at most).
            if let turn=design.nextTurn(inputs)?.timeIntervalSince(now) { wait=min(wait ?? turn,turn) }
        } else { card=PresenceCard.activity(facts:facts,level:level,launched:launched,texts:texts) }
        let sent=DiscordRules.clean(card)
        if !quiet && shown != sent as NSDictionary { shown=sent as NSDictionary;ipc.set(sent,profile:(level == .full || level == .custom) && mine) }
        promotion?.cancel();promotion=nil
        if let wait {
            let work=DispatchWorkItem { [weak self] in self?.refresh() }
            promotion=work;queue.asyncAfter(deadline:.now()+wait+0.05,execute:work)
        }
    }
}
