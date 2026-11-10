import Foundation

// The career profile on the card (Full), through OverFast (github.com/TeKrop/overfast-api), never Blizzard's pages.
// Blizzard updates a profile after the game quits, so the card tells the session before this one. Only the BattleTag is
// sent (app/ARCHITECTURE.md). Saved types outlive the Recall that wrote them: a field added later must be optional.

/// A BattleTag as typed ("Name#1234") and as OverFast takes it ("Name-1234"), checked so a tag OverFast would refuse is
/// never sent.
enum BattleTag {
    static func playerID(_ tag:String)->String? {
        let text=clean(tag)
        guard text.range(of:#"^\p{L}[\p{L}\p{N}]{2,11}#[0-9]{3,8}$"#,options:.regularExpression) != nil else { return nil }
        return text.replacingOccurrences(of:"#",with:"-")
    }
    /// A pasted tag: full-width characters made plain, accents composed, invisible marks and outer spaces gone.
    static func clean(_ tag:String)->String {
        let visible=String(String.UnicodeScalarView(tag.unicodeScalars.filter { $0.properties.generalCategory != .format }))
        return visible.precomposedStringWithCompatibilityMapping.trimmingCharacters(in:.whitespaces)
    }
}

/// A competitive rank on PC for one role, as the profile shows it.
struct CareerRank: Codable, Equatable {
    enum Role: String, Codable, CaseIterable { case tank,damage,support,open }
    let role:Role
    /// "emerald": the division's name as OverFast gives it.
    let division:String
    /// 1 is the division's best, 5 its lowest.
    let tier:Int
    let icon:URL
    /// The divisions, lowest first. OverFast names Champion "ultimate"; a division not listed is no rank (no arrow,
    /// move or peak).
    static let divisions=["bronze","silver","gold","platinum","emerald","diamond","master","grandmaster","champion"]
    static func division(_ name:String)->String? {
        let known=name == "ultimate" ? "champion" : name
        return divisions.contains(known) ? known : nil
    }
    /// Higher is better: the division, then the tier within it.
    var standing:Int { (Self.divisions.firstIndex(of:division) ?? -1)*10+(6-tier) }
    init(role:Role,division:String,tier:Int,icon:URL) { self.role=role;self.division=division;self.tier=tier;self.icon=icon }
    // Kept before Champion was read right: "ultimate" reads as Champion.
    init(from decoder:Decoder) throws {
        let kept=try decoder.container(keyedBy:CodingKeys.self)
        role=try kept.decode(Role.self,forKey:.role);icon=try kept.decode(URL.self,forKey:.icon);tier=try kept.decode(Int.self,forKey:.tier)
        let name=try kept.decode(String.self,forKey:.division)
        division=Self.division(name) ?? name
    }
}

/// Games, as the profile counts them.
struct Tally: Codable, Equatable {
    var played=0,won=0,lost=0
}

/// One mode's totals on the profile (all heroes), each hero's time played, and its best games.
struct ModeStats: Codable, Equatable {
    var games=Tally()
    var heroes:[String:Int]=[:]
    var eliminations=0,deaths=0,damage=0,healing=0
    /// The profile's "best in a game" records ("eliminations_most_in_game": 46).
    var bests:[String:Int]=[:]
    /// Each hero's games, for its win rate; nil in what an older Recall kept.
    var heroGames:[String:Tally]?
    /// Each hero's damage and healing (Cardboard Support); nil in what an older Recall kept.
    var heroDamage:[String:Int]?
    var heroHealing:[String:Int]?
}

/// Who the player is in the game: what the profile's header shows.
struct CareerIdentity: Codable, Equatable {
    var name:String
    var title:String?
    var endorsement:Int?
    var avatar:URL?
    /// The name card's picture (Settings shows that Recall reads it; the card doesn't show it).
    var namecard:URL?=nil
}

/// A hero as OverFast lists them: name, portrait and role.
struct CareerHero: Codable, Equatable {
    let name:String
    let portrait:URL?
    let role:CareerRank.Role?
    /// Heroes Blizzard renamed: the old key reads as the new one, so its hours stay one hero's.
    static let renamed=["mccree":"cassidy"]
    static func current(_ key:String)->String { renamed[key] ?? key }
    /// A hero's name before OverFast's list has it: "junker-queen" is "Junker Queen".
    static func name(_ key:String)->String { key.split(separator:"-").map { $0.capitalized }.joined(separator:" ") }
}

/// A record beaten in the last session ("eliminations_most_in_game" is now 46).
struct CareerBest: Codable, Equatable {
    let key:String
    let value:Int
    /// The records the card tells, in the order it prefers them.
    static let told=["eliminations_most_in_game","all_damage_done_most_in_game","healing_done_most_in_game","final_blows_most_in_game",
                     "solo_kills_most_in_game","kill_streak_best","multikill_best"]
}

/// What changed on the profile since it was last looked at: the session (or sessions) before this one.
struct LastSession: Codable, Equatable {
    var competitive=Tally(),quickplay=Tally()
    /// Matches the log saw beyond these two modes (Arcade, custom games); nil when it wasn't followed throughout.
    var other:Int?
    /// The hero played longest (OverFast's key, "soldier-76"), and the role of Competitive's.
    var hero:String?
    var role:CareerRank.Role?
    var eliminations=0,deaths=0,damage=0,healing=0
    var best:CareerBest?
    /// A rank that moved, and which way.
    var rank:CareerRank?
    var promoted=false
    var played:Int { competitive.played+quickplay.played+(other ?? 0) }

    /// The difference between two looks, with the log's matches between them; nil when nothing was played. Competitive
    /// starts over at a season (`newSeason`, or fewer games), though its bests are still compared with the highest ever
    /// read.
    static func between(_ before:[String:ModeStats],_ after:[String:ModeStats],heroes:[String:CareerHero]=[:],matches:Int?=nil,newSeason:Bool=false,bests:[String:Int]?=nil)->LastSession? {
        guard let keptComp=before["competitive"],let newComp=after["competitive"],let oldQuick=before["quickplay"],let newQuick=after["quickplay"] else { return nil }
        let oldComp=newSeason || newComp.games.played < keptComp.games.played ? ModeStats(bests:keptComp.bests) : keptComp
        func change(_ old:Tally,_ new:Tally)->Tally {
            Tally(played:max(0,new.played-old.played),won:max(0,new.won-old.won),lost:max(0,new.lost-old.lost))
        }
        /// The key that grew most (the first by name when two grew alike).
        func most(_ new:[String:Int],_ old:[String:Int])->String? {
            var best:(key:String,gain:Int)?
            for (key,value) in new.sorted(by:{ $0.key < $1.key }) {
                let gain=value-(old[key] ?? 0)
                if gain > 0 && gain > (best?.gain ?? 0) { best=(key,gain) }
            }
            return best?.key
        }
        var session=LastSession(competitive:change(oldComp.games,newComp.games),quickplay:change(oldQuick.games,newQuick.games))
        // The log's matches beyond these modes; a count lower than theirs means it missed some, and tells nothing.
        if let matches,matches >= session.competitive.played+session.quickplay.played { session.other=matches-session.competitive.played-session.quickplay.played }
        guard session.played > 0 else { return nil }
        var both=newQuick.heroes,bothBefore=oldQuick.heroes
        for (key,value) in newComp.heroes { both[key,default:0]+=value }
        for (key,value) in oldComp.heroes { bothBefore[key,default:0]+=value }
        session.hero=most(both,bothBefore)
        session.role=most(newComp.heroes,oldComp.heroes).flatMap { heroes[$0]?.role }
        for (old,new) in [(oldComp,newComp),(oldQuick,newQuick)] {
            session.eliminations+=max(0,new.eliminations-old.eliminations);session.deaths+=max(0,new.deaths-old.deaths)
            session.damage+=max(0,new.damage-old.damage);session.healing+=max(0,new.healing-old.healing)
        }
        // A record beaten in either mode: the first the card prefers, at its new value.
        for key in CareerBest.told {
            let beaten=[(oldComp,newComp),(oldQuick,newQuick)].compactMap { old,new -> Int? in
                guard let value=new.bests[key],let was=old.bests[key],was > 0,value > max(was,bests?[key] ?? 0) else { return nil }
                return value
            }
            if let value=beaten.max() { session.best=CareerBest(key:key,value:value);break }
        }
        return session
    }
    /// The rank the session told: the best move up, in divisions; none when every role fell or at a new season.
    mutating func ranks(from before:[CareerRank],to after:[CareerRank]) {
        let moved=after.compactMap { new -> (CareerRank,Int)? in
            guard let old=before.first(where:{ $0.role == new.role }),new.steps(from:old) > 0 else { return nil }
            return (new,new.steps(from:old))
        }.max { $0.1 < $1.1 }
        rank=moved?.0;promoted=moved != nil
    }
}

/// What the card shows from the profile.
struct CareerCard: Equatable {
    var identity:CareerIdentity?
    var ranks:[CareerRank]=[]
    var season:Int?
    var last:LastSession?
    /// The last session's hero, as OverFast lists them.
    var hero:CareerHero?
    /// The player's career page on Blizzard's site, for the card's button.
    var page:URL?
    /// The totals by mode (all time: records, bests, each hero's time and games), and OverFast's hero list.
    var totals:[String:ModeStats]=[:]
    var heroes:[String:CareerHero]=[:]
    /// The highest bests ever read (a new season's totals start their own over).
    var bests:[String:Int]=[:]
    /// The rank shown: the role the last session's competitive games were in, or else the best one.
    var rank:CareerRank? {
        // The role whose rank the session moved, then the role its Competitive games were in, then the best one.
        if let moved=last?.rank?.role,let rank=ranks.first(where:{ $0.role == moved }) { return rank }
        if let role=last?.role,(last?.competitive.played ?? 0) > 0,let rank=ranks.first(where:{ $0.role == role }) { return rank }
        return ranks.max { $0.standing < $1.standing }
    }
}

enum OverFast {
    static let standard=URL(string:"https://overfast-api.tekrop.fr")!
    /// The most any stat is taken as (a self-hosted OverFast can say anything): far above any player's, and never
    /// overflowing when added.
    static let most=1_000_000_000
    /// `/players/{id}/summary`: the profile's time, PC ranks and season, and who the player is. `updated` nil means
    /// private.
    static func summary(_ data:Data)->(updated:Int?,ranks:[CareerRank],season:Int?,identity:CareerIdentity?)? {
        guard let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],json["username"] is String || json["last_updated_at"] is Int else { return nil }
        let updated=json["last_updated_at"] as? Int
        let pc=(json["competitive"] as? [String:Any])?["pc"] as? [String:Any] ?? [:]
        let ranks=CareerRank.Role.allCases.compactMap { role -> CareerRank? in
            guard let entry=pc[role.rawValue] as? [String:Any],let division=(entry["division"] as? String).flatMap(CareerRank.division),
                  let tier=entry["tier"] as? Int,(1...5).contains(tier),let icon=secure(entry["rank_icon"]) else { return nil }
            return CareerRank(role:role,division:division,tier:tier,icon:icon)
        }
        // The player's title, as the game gives it (already in the profile's language).
        let shown=(json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let identity=(json["username"] as? String).map {
            CareerIdentity(name:$0,title:shown,
                           endorsement:((json["endorsement"] as? [String:Any])?["level"] as? Int).flatMap { (1...5).contains($0) ? $0 : nil },avatar:secure(json["avatar"]),namecard:secure(json["namecard"]))
        }
        return (updated,ranks,(pc["season"] as? Int).flatMap { $0 > 0 ? $0 : nil },identity)
    }
    /// `/players/{id}`: the PC totals of Quick Play and Competitive, from the career stats.
    static func profile(_ data:Data)->[String:ModeStats]? {
        guard let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let pc=(json["stats"] as? [String:Any])?["pc"] as? [String:Any] else { return nil }
        var modes:[String:ModeStats]=[:]
        for mode in ["competitive","quickplay"] {
            let career=(pc[mode] as? [String:Any])?["career_stats"] as? [String:Any] ?? [:]
            /// A hero's (or all heroes') values in one category, the first of each key.
            func values(_ hero:String,_ category:String)->[String:Int] {
                let categories=career[hero] as? [[String:Any]] ?? []
                let stats=categories.first { $0["category"] as? String == category }?["stats"] as? [[String:Any]] ?? []
                return stats.reduce(into:[:]) { result,stat in
                    if let key=stat["key"] as? String,result[key] == nil,let value=(stat["value"] as? NSNumber)?.intValue { result[key]=min(max(value,0),most) }
                }
            }
            let game=values("all-heroes","game"),combat=values("all-heroes","combat"),assists=values("all-heroes","assists")
            var stats=ModeStats(games:Tally(played:game["games_played"] ?? 0,won:game["games_won"] ?? 0,lost:game["games_lost"] ?? 0),
                                eliminations:combat["eliminations"] ?? 0,deaths:combat["deaths"] ?? 0,damage:combat["hero_damage_done"] ?? 0,
                                healing:assists["healing_done"] ?? 0,bests:values("all-heroes","best"))
            var heroGames:[String:Tally]=[:],damage:[String:Int]=[:],healing:[String:Int]=[:]
            for key in career.keys where key != "all-heroes" {
                let hero=CareerHero.current(key)
                let game=values(key,"game")
                if let time=game["time_played"],time > 0 { stats.heroes[hero]=time }
                if let played=game["games_played"],played > 0 { heroGames[hero]=Tally(played:played,won:game["games_won"] ?? 0,lost:game["games_lost"] ?? 0) }
                if let done=values(key,"combat")["hero_damage_done"],done > 0 { damage[hero]=done }
                if let done=values(key,"assists")["healing_done"],done > 0 { healing[hero]=done }
            }
            if !heroGames.isEmpty { stats.heroGames=heroGames }
            if !damage.isEmpty || !healing.isEmpty { stats.heroDamage=damage;stats.heroHealing=healing }
            modes[mode]=stats
        }
        return modes
    }
    /// A whole profile that looks wrong next to the last: a mode with games gone or emptied, games or time going down,
    /// or wins with no games.
    static func doubtful(_ old:[String:ModeStats],_ new:[String:ModeStats],turned:Bool)->Bool {
        for (mode,was) in old where was.games.played > 0 {
            guard let now=new[mode] else { return true }
            if now.games.played == 0 && now.games.won > 0 { return true }
            if turned && mode == "competitive" { continue }
            if now.games.played < was.games.played || now.heroes.values.reduce(0,+) < was.heroes.values.reduce(0,+) { return true }
        }
        return false
    }
    /// `/heroes`: each hero's name, portrait and role, by OverFast's key.
    static func heroes(_ data:Data)->[String:CareerHero]? {
        guard let list=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { return nil }
        return list.reduce(into:[:]) { result,entry in
            guard let key=entry["key"] as? String,let name=entry["name"] as? String else { return }
            result[key]=CareerHero(name:name,portrait:secure(entry["portrait"]),role:(entry["role"] as? String).flatMap(CareerRank.Role.init))
        }
    }
    /// OverFast's own "Player not found" (a JSON error body) and its `next_check_at`/`retry_after`; nil for any other
    /// 404 (a proxy, a moved server).
    static func notFound(_ data:Data,now:Date)->Date? {
        guard let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],json["error"] != nil else { return nil }
        let info=json["error"] as? [String:Any] ?? json
        if let at=info["next_check_at"] as? Double,at > now.timeIntervalSince1970 { return Date(timeIntervalSince1970:at) }
        if let after=info["retry_after"] as? Double,after > 0 { return now.addingTimeInterval(after) }
        return now.addingTimeInterval(10*60)
    }
    /// A self-hosted OverFast: https, or http on this Mac only, so the BattleTag never travels unencrypted.
    static func server(_ text:String)->URL? {
        guard let url=URL(string:text.trimmingCharacters(in:.whitespaces)),let host=url.host,!host.isEmpty,url.query == nil,url.fragment == nil else { return nil }
        guard url.scheme == "https" || (url.scheme == "http" && ["localhost","127.0.0.1","::1"].contains(host)) else { return nil }
        return url
    }
    /// Images go to Discord only as https links.
    private static func secure(_ value:Any?)->URL? {
        (value as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
}

/// Looks the profile up when it's time and keeps what it learned in this Mac's settings; changes over time go to the
/// history's file.
final class CareerProfile {
    enum Status: Equatable {
        case none
        case looking
        case found(CareerRank?)
        /// Private: it is asked again only after this.
        case notPublic(until:Date)
        /// No player has this BattleTag (a typo, other capitals): OverFast checks again only after this.
        case notFound(until:Date)
        case invalidTag
        /// OverFast didn't answer usefully; the next time the game opens it is asked again.
        case unavailable
        /// No answer at all (offline, OverFast down): nothing counted as asked.
        case unreachable
        /// Asked too often just now (every BattleTag together): the next look waits until then.
        case busy(until:Date)
    }
    struct Response { let status:Int;let headers:[String:String];let body:Data }
    /// One request; nil when there was no answer at all. Called on the profile's queue.
    typealias Fetch=(URL)->Response?
    /// One lookup in this long at most: OverFast's own cache time, so asking sooner learns nothing.
    static let fresh:TimeInterval=600
    /// The longest wait OverFast can ask for; one further off (a clock set back) is let go.
    static let longestWait:TimeInterval=86_400
    /// The hero list is asked for again after this (new heroes come with seasons).
    static let heroesKept:TimeInterval=7*24*3600

    private struct Record: Codable {
        var player:String
        /// A summary was read: the card has something to show.
        var seen=false
        var updated:Int?
        var modes:[String:ModeStats]=[:]
        var ranks:[CareerRank]=[]
        var season:Int?
        var identity:CareerIdentity?
        var last:LastSession?
        /// Matches the log saw since the totals were taken; nil once a session went by without it.
        var matches:Int?
        var heroes:[String:CareerHero]=[:]
        var heroesAt:Date?
        var asked:Date?
        var waitUntil:Date?
        var notPublic=false
        var notFound=false
        var code:Int?
        /// Each best ever read (the highest, over every mode and season), so a season's lower ones aren't news.
        var bests:[String:Int]?
        /// The last whole profile looked wrong (a mode gone or emptied, Quick Play going down): kept back once.
        var doubted=false
        init(player:String) { self.player=player }
        /// What a wait is for.
        func waiting(until wait:Date)->Status { notPublic ? .notPublic(until:wait) : notFound ? .notFound(until:wait) : .unavailable }
        // Fields added later must be optional or have a default.
        init(from decoder:Decoder) throws {
            let kept=try decoder.container(keyedBy:CodingKeys.self)
            func value<T:Decodable>(_ key:CodingKeys)->T? { (try? kept.decodeIfPresent(T.self,forKey:key)) ?? nil }
            player=try kept.decode(String.self,forKey:.player)
            seen=value(.seen) ?? false;updated=value(.updated);modes=value(.modes) ?? [:];ranks=value(.ranks) ?? []
            season=value(.season);identity=value(.identity);last=value(.last);matches=value(.matches)
            heroes=value(.heroes) ?? [:];heroesAt=value(.heroesAt);asked=value(.asked);waitUntil=value(.waitUntil)
            notPublic=value(.notPublic) ?? false;notFound=value(.notFound) ?? false;code=value(.code)
            bests=value(.bests);doubted=value(.doubted) ?? false
        }
    }
    private let queue=DispatchQueue(label:"org.overwatch2mac.career-profile",qos:.utility)
    /// nil when support set a server that isn't one: nothing is looked up then.
    private let base:URL?
    private let store:UserDefaults
    private let key:String
    private let fetch:Fetch
    /// What the looks found over time, and the game's runs (CareerHistory.swift).
    let history:CareerHistoryStore
    init(base:URL?=OverFast.standard,store:UserDefaults = .standard,key:String="careerProfile",history:CareerHistoryStore=CareerHistoryStore(url:nil),fetch:Fetch?=nil) {
        self.base=base;self.store=store;self.key=key;self.history=history
        self.fetch=fetch ?? CareerProfile.request
    }
    /// Uninstall: nothing more is asked or kept (a look on its way is let go).
    func close() { closing.lock();closed=true;closing.unlock();history.close() }
    private let closing=NSLock()
    private var closed=false
    private var isClosed:Bool { closing.lock();defer { closing.unlock() };return closed }
    /// The last answer's HTTP code for the support report, read from the settings (a lookup can hold the queue).
    var lastCode:Int? { ([record(),other()].compactMap { $0 }+parked().values).max { ($0.asked ?? .distantPast) < ($1.asked ?? .distantPast) }?.code }

    /// What the card can show from a record (nil before a summary was read).
    private static func card(_ record:Record)->CareerCard? {
        guard record.seen else { return nil }
        var page=URLComponents(string:"https://overwatch.blizzard.com/en-us/career/")!
        page.path+=record.player+"/"
        return CareerCard(identity:record.identity,ranks:record.ranks,season:record.season,last:record.last,
                          hero:record.last?.hero.flatMap { record.heroes[$0] },page:page.url,totals:record.modes,heroes:record.heroes,bests:record.bests ?? [:])
    }
    /// What the last look found, without asking again (Settings' preview). `done` runs on the profile's queue.
    func kept(tag:String,done:@escaping (Status,CareerCard?,Date?)->Void) {
        queue.async {
            guard let player=BattleTag.playerID(tag) else { done(.invalidTag,nil,nil);return }
            guard let record=self.record().flatMap({ Self.same($0.player,player) ? $0 : nil }) ?? self.waiting(player) else { done(.none,nil,nil);return }
            let card=Self.card(record)
            if record.notPublic || record.notFound,let wait=record.waitUntil { done(record.waiting(until:wait),nil,record.asked);return }
            done(record.seen ? .found(card?.rank) : .none,card,record.asked)
        }
    }
    /// Looks the player up if it's time, and tells what the card can show. `done` runs on the profile's queue.
    func lookUp(tag:String,now:Date=Date(),done:@escaping (Status,CareerCard?)->Void) {
        queue.async {
            guard !self.isClosed else { done(.none,nil);return }
            guard let player=BattleTag.playerID(tag) else { done(.invalidTag,nil);return }
            // A server set by support that isn't one (OverFast.server): nothing is asked, rather than the public one.
            guard let base=self.base else { done(.unavailable,nil);return }
            self.catchUp=nil
            // The player whose profile the history holds. Another one waits apart until found, and only then takes its
            // place: a typo, or an alt and back, loses nothing.
            let kept=self.record()
            var mine=kept.map { Self.same($0.player,player) } ?? true
            var record=(mine ? kept : self.waiting(player)) ?? Record(player:player)
            // What was learned is kept before it is told.
            func finish(_ status:Status,_ card:CareerCard?) { self.save(record,mine:mine);done(status,card) }
            func card()->CareerCard? { Self.card(record) }
            /// Found: this player's record and history part take the place of the one kept.
            func takeOver() {
                guard !mine else {
                    // The settings were cleared but the history kept: its player's part is set aside.
                    if self.history.current.player != player { self.history.update { $0.switchPlayer(from:nil,to:player) } }
                    return
                }
                self.history.update { $0.switchPlayer(from:kept?.player,to:player) }
                self.park(kept,taking:player);mine=true
            }
            if let wait=record.waitUntil,now < wait,wait.timeIntervalSince(now) <= Self.longestWait {
                finish(record.waiting(until:wait),record.notPublic || record.notFound ? nil : card());return
            }
            if let asked=record.asked,now >= asked,now.timeIntervalSince(asked) < Self.fresh,!record.notPublic,!record.notFound {
                if record.seen { takeOver() }
                finish(record.seen ? .found(card()?.rank) : .unavailable,card());return
            }
            // One pace for every BattleTag: typing one after another doesn't ask OverFast more often.
            if let until=self.pace.wait(now) { done(.busy(until:until),card());return }
            self.pace.asked(now)
            let answer=self.fetch(base.appendingPathComponent("players/\(player)/summary"))
            // No answer at all isn't a look: Settings says so, and the next chance asks again.
            guard let answer else { finish(.unreachable,card());return }
            record.code=answer.status
            record.asked=now;record.waitUntil=nil;record.notPublic=false;record.notFound=false
            switch answer.status {
            case 200:
                guard let summary=OverFast.summary(answer.body) else { finish(.unavailable,card());return }
                // No update time: the profile is private. Nothing of it shows; asked again after OverFast's cache time.
                guard let updated=summary.updated else {
                    record.notPublic=true;record.waitUntil=now.addingTimeInterval(Self.fresh)
                    finish(.notPublic(until:record.waitUntil!),nil);return
                }
                // A profile changed after tomorrow can't be (milliseconds, or a clock far off): not taken.
                guard TimeInterval(updated) < now.timeIntervalSince1970+86_400 else { finish(.unavailable,card());return }
                takeOver()
                let ranksBefore=record.ranks
                record.seen=true;record.identity=summary.identity ?? record.identity
                // The hero list (names, portraits, roles), from the first look on: every hero picture needs it.
                if record.heroes.isEmpty || record.heroesAt.map({ now.timeIntervalSince($0) > Self.heroesKept }) ?? true,
                   let list=self.fetch(base.appendingPathComponent("heroes")),list.status == 200,let heroes=OverFast.heroes(list.body) {
                    record.heroes=heroes;record.heroesAt=now
                }
                // Another season: the ranks start over. A missing season (or 0) keeps the known one.
                let season=summary.season ?? record.season
                let turned=summary.season != nil && record.season != nil && summary.season != record.season
                var change:ProfileChange?
                // The ranks are taken with the totals they go with, so a session's moves aren't lost when the whole
                // profile can't be read this time.
                var ranksTaken=updated == record.updated || record.modes.isEmpty
                // The profile changed: the whole of it is read, and the change is the last session. One that looks
                // wrong is held back once; the same again becomes the new baseline, telling nothing.
                var took=false;var baseline=false
                if updated != record.updated,let whole=self.fetch(base.appendingPathComponent("players/\(player)")),
                   whole.status == 200,let modes=OverFast.profile(whole.body) {
                    let doubtful=record.modes.isEmpty ? false : OverFast.doubtful(record.modes,modes,turned:turned)
                    if doubtful && !record.doubted { record.doubted=true }
                    else {
                        if !record.modes.isEmpty && !doubtful,
                           var last=LastSession.between(record.modes,modes,heroes:record.heroes,matches:record.matches,newSeason:turned,bests:record.bests) {
                            if !turned { last.ranks(from:ranksBefore,to:summary.ranks) }
                            record.last=last
                            // Kept with the profile's own time (when the game closed), not the look's.
                            change=ProfileChange(at:min(Date(timeIntervalSince1970:TimeInterval(updated)),now),season:season,session:last,before:record.modes,after:modes)
                            change?.since=self.history.current.looked
                            if !turned {
                                let moves=CareerRank.moves(from:ranksBefore,to:summary.ranks)
                                change?.rankMoves=moves
                                change?.ranked=summary.ranks.reduce(into:[:]) { kept,new in
                                    if let old=ranksBefore.first(where:{ $0.role == new.role }) { kept[new.role.rawValue]=[old.kept,new.kept] }
                                }
                                if let moved=last.rank { change?.rankSteps=moves[moved.role.rawValue] }
                            }
                        }
                        record.modes=modes;record.updated=updated;record.matches=0;record.doubted=false
                        for mode in modes.values { for (key,value) in mode.bests { record.bests=record.bests ?? [:];record.bests![key]=max(record.bests![key] ?? 0,value) } }
                        ranksTaken=true;took=true;baseline=doubtful
                        // A hero OverFast's list doesn't have yet (new, or moved role): the list is asked again, once a
                        // day at most.
                        let unknown=modes.values.contains { $0.heroes.keys.contains { record.heroes[$0] == nil } }
                        if unknown || turned,record.heroesAt.map({ now.timeIntervalSince($0) > 86_400 }) ?? true,
                           let list=self.fetch(base.appendingPathComponent("heroes")),list.status == 200,let heroes=OverFast.heroes(list.body) {
                            record.heroes=heroes;record.heroesAt=now
                        }
                    }
                }
                if ranksTaken { record.ranks=summary.ranks;record.season=season }
                // The game closed after the profile's last change: OverFast hasn't caught up (it keeps its copy for
                // half an hour).
                if let ended=self.history.current.runs.last?.end,TimeInterval(updated) < ended.timeIntervalSince1970-60,now.timeIntervalSince(ended) < 3*3600 {
                    let age=answer.headers.first { $0.key.lowercased() == "age" }.flatMap { Double($0.value) } ?? 0
                    self.catchUp=now.addingTimeInterval(age < 1800 ? 1800-age+30 : 120)
                }
                // Hours are counted at every look, each gain in the role its hero has now; milestones come from that
                // count, which a season never takes back.
                let modes=record.modes,ranks=record.ranks,fresh=ranksTaken,roles=record.heroes
                self.history.update { history in
                    let before=history.hours?.heroes
                    history.count(modes,at:now,turned:turned && took,baseline:baseline) { roles[$0]?.role }
                    if change != nil,let before,let after=history.hours?.heroes { change?.milestone=ProfileChange.milestone(from:before,to:after) }
                    history.player=player;history.looked(at:now,season:season,ranks:ranks,change:change,fresh:fresh)
                }
                finish(.found(card()?.rank),card())
            case 404:
                // Only OverFast's own "not found" says anything about the player.
                guard let wait=OverFast.notFound(answer.body,now:now) else { finish(.unavailable,card());return }
                record.waitUntil=min(wait,now.addingTimeInterval(Self.longestWait))
                // A player found before (Blizzard's page failing for a while): the card keeps what it had.
                if record.seen { finish(.unavailable,card());return }
                record.notFound=true
                finish(.notFound(until:record.waitUntil!),nil)
            case 429,503:
                // Too many asks (OverFast's or Blizzard's): its Retry-After (a minute to a day), and nothing before.
                let after=answer.headers.first { $0.key.lowercased() == "retry-after" }.flatMap { Double($0.value) }.flatMap { $0.isFinite ? $0 : nil } ?? Self.fresh
                record.waitUntil=now.addingTimeInterval(min(max(after,60),Self.longestWait))
                finish(.unavailable,card())
            default: finish(.unavailable,card())
            }
        }
    }
    /// The last look found the profile behind the last run: when to ask again (read in `done`).
    private(set) var catchUp:Date?
    /// How often OverFast is asked, whatever the BattleTag: two seconds apart, and six times in ten minutes at most.
    private var pace=Pace()
    struct Pace {
        private var asks:[Date]=[]
        /// Asks in the last ten minutes (ones ahead of now, the clock set back, don't count).
        private func recent(_ now:Date)->[Date] { asks.filter { (0..<600).contains(now.timeIntervalSince($0)) } }
        func wait(_ now:Date)->Date? {
            let recent=recent(now)
            if let last=recent.last,now.timeIntervalSince(last) < 2 { return last.addingTimeInterval(2) }
            return recent.count >= 6 ? recent.first!.addingTimeInterval(600) : nil
        }
        mutating func asked(_ now:Date) { asks=recent(now)+[now] }
    }
    /// A run ended: it goes into the history, and its matches count toward the next session the profile tells.
    func sessionEnded(_ run:PlayedRun) { queue.async { self.add(run) } }
    /// The same at once (Recall quitting while the game runs): both stores are safe to change from any thread.
    func sessionEndedNow(_ run:PlayedRun) { add(run) }
    private func add(_ run:PlayedRun) {
        // A run Recall quit during, taken up again from the game's start, counts its matches once.
        let earlier=history.current.runs.last { $0.sameStart(run) }?.matches ?? 0
        history.update { $0.ran(run) }
        guard var record=record() else { return }
        record.matches=run.matches.flatMap { count in record.matches.map { max(0,$0+count-earlier) } }
        save(record)
    }
    /// What Recall remembers › Erase. Ranks and all-time records come back with the next look; sessions don't.
    func erase(done:@escaping ()->Void={}) { queue.async { self.eraseNow();done() } }
    /// What an erase takes, kept in memory for its ten seconds to undo: the files are gone at once.
    struct Erased { fileprivate let records:[String:Data];fileprivate let history:CareerHistory }
    /// Erases now and hands back what it took (`done` on the profile's queue).
    func erase(keeping done:@escaping (Erased)->Void) {
        queue.async {
            let records=[self.key,self.otherKey,self.parkedKey].reduce(into:[String:Data]()) { kept,key in kept[key]=self.store.data(forKey:key) }
            let erased=Erased(records:records,history:self.history.current)
            self.eraseNow();done(erased)
        }
    }
    /// Undo: what the erase took comes back, the history's file too.
    func restore(_ erased:Erased,done:@escaping ()->Void={}) {
        queue.async {
            guard !self.isClosed else { done();return }
            for (key,data) in erased.records { self.store.set(data,forKey:key) }
            self.history.update { $0=erased.history }
            done()
        }
    }
    /// The same at once (Recall quitting): both stores are safe from any thread.
    func eraseNow() { store.removeObject(forKey:key);store.removeObject(forKey:otherKey);store.removeObject(forKey:parkedKey);history.erase() }

    /// The player whose profile the history holds, and another BattleTag's while it isn't found.
    private func record()->Record? { read(key) }
    private func other()->Record? { read(otherKey) }
    private var otherKey:String { key+"Other" }
    /// Other players' records (set aside, or typed and not found yet), each with its own wait.
    private var parkedKey:String { key+"Parked" }
    /// Another player's record (`careerProfileOther` is an earlier build's single one).
    private func waiting(_ player:String)->Record? {
        if let other=other(),Self.same(other.player,player) { return other }
        return parked()[player]
    }
    private func parked()->[String:Record] { store.data(forKey:parkedKey).flatMap { try? JSONDecoder().decode([String:Record].self,from:$0) } ?? [:] }
    /// Six at most: ones never found go first, then the longest unasked.
    private func setAside(_ change:(inout [String:Record])->Void) {
        guard !isClosed else { return }
        var aside=parked();change(&aside)
        while aside.count > 6,let gone=aside.min(by:{ ($0.value.seen ? 1 : 0,$0.value.asked ?? .distantPast) < ($1.value.seen ? 1 : 0,$1.value.asked ?? .distantPast) })?.key { aside[gone]=nil }
        store.set(try? JSONEncoder().encode(aside),forKey:parkedKey)
    }
    /// `player` takes the kept record's place: that one is set aside.
    private func park(_ kept:Record?,taking player:String) {
        setAside { aside in
            aside[player]=nil
            if let kept,kept.player != player { aside[kept.player]=kept }
        }
        if other().map({ Self.same($0.player,player) }) == true { store.removeObject(forKey:otherKey) }
    }
    private func read(_ key:String)->Record? { store.data(forKey:key).flatMap { try? JSONDecoder().decode(Record.self,from:$0) } }
    private func save(_ record:Record,mine:Bool=true) {
        guard !isClosed else { return }
        if mine { store.set(try? JSONEncoder().encode(record),forKey:key) } else { setAside { $0[record.player]=record } }
    }
    /// OverFast and Blizzard tell BattleTags apart by their capitals too.
    private static func same(_ a:String,_ b:String)->Bool { a == b }
    /// One ephemeral session for every look, which won't follow a redirect from https to http: the BattleTag is in the
    /// address.
    private static let overFast=URLSession(configuration:.ephemeral,delegate:NoDowngrade(),delegateQueue:nil)
    private final class NoDowngrade: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
            completionHandler(task.originalRequest?.url?.scheme == "https" && newRequest.url?.scheme != "https" ? nil : newRequest)
        }
    }
    /// A request as UpdateService makes them: named, 15 seconds at most (30 for the whole profile).
    private static func request(_ url:URL)->Response? {
        var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:url.path.hasSuffix("/summary") ? 15 : 30)
        request.setValue(Brand.name,forHTTPHeaderField:"User-Agent")
        let done=DispatchSemaphore(value:0)
        var result:Response?
        overFast.dataTask(with:request) { data,response,_ in
            if let http=response as? HTTPURLResponse {
                result=Response(status:http.statusCode,headers:http.allHeaderFields.reduce(into:[:]) { $0["\($1.key)"]="\($1.value)" },body:data ?? Data())
            }
            done.signal()
        }.resume()
        done.wait()
        return result
    }
}

// The card's words for the profile, in the app's language.
extension CareerRank {
    /// "Emerald 1".
    var name:String { "\(Self.name(division)) \(tier)" }
    /// "Emerald".
    static func name(_ division:String)->String {
        let names=["bronze":L("Bronze"),"silver":L("Silver"),"gold":L("Gold"),"platinum":L("Platinum"),"emerald":L("Emerald"),
                   "diamond":L("Diamond"),"master":L("Master"),"grandmaster":L("Grandmaster"),"champion":L("Champion")]
        return names[division] ?? division.capitalized
    }
    /// "Tank: Emerald 1", or with other words after the role ("Tank: up to Emerald 1").
    func label(_ text:String?=nil)->String {
        let text=text ?? name
        // One phrase per role, so a role's name never shares a key with the same word elsewhere.
        switch role {
        case .tank: return L("Tank: {0}",text)
        case .damage: return L("Damage: {0}",text)
        case .support: return L("Support: {0}",text)
        // The career page's fourth row, which the game plays as 6v6.
        case .open: return L("6v6: {0}",text)
        }
    }
}
extension CareerRank.Role {
    var label:String {
        switch self {
        case .tank: return L("Tank",context:"role")
        case .damage: return L("Damage",context:"role")
        case .support: return L("Support",context:"role")
        case .open: return L("6v6",context:"role")
        }
    }
}
extension LastSession {
    /// "Comp 2–1 · QP 1–0 · 1 other": short, as Discord cuts Line 2 at about 30 characters.
    var summary:String {
        var parts:[String]=[]
        if competitive.played > 0 { parts.append(L("Comp {0}–{1}",String(competitive.won),String(competitive.lost))) }
        if quickplay.played > 0 { parts.append(L("QP {0}–{1}",String(quickplay.won),String(quickplay.lost))) }
        if parts.isEmpty { return played == 1 ? L("1 match") : L("{0} matches",String(played)) }
        if let other,other > 0 { parts.append(L("{0} other",String(other))) }
        return parts.joined(separator:" · ")
    }
    /// "38 eliminations, 9 deaths, 14,032 healing" (healing or damage, whichever there was more of).
    var stats:String? {
        guard eliminations+deaths+damage+healing > 0 else { return nil }
        let number={ (value:Int) in value.formatted(.number.locale(CardWords.locale)) }
        let kills=eliminations == 1 ? L("1 elimination") : L("{0} eliminations",number(eliminations)),died=deaths == 1 ? L("1 death") : L("{0} deaths",number(deaths))
        return L("{0}, {1}, {2}",kills,died,healing > damage ? L("{0} healing",number(healing)) : L("{0} damage",number(damage)))
    }
}
