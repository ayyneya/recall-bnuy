import Foundation

// What Recall remembers between sessions: the game's runs on this Mac (no BattleTag needed), the profile's changes
// (Full), dated by the profile's own time, and each hero's hours (HeroHours). One file in Application Support, kept a
// little over a year. A field added later must be optional.

/// One change of the profile: what the sessions between two looks did, and when they ended.
struct ProfileChange: Codable, Equatable {
    /// A hero that passed a milestone, and the hours it passed.
    struct Milestone: Codable, Equatable { let hero:String;let hours:Int }
    /// The profile's own time: the second the game closed after them.
    var at:Date
    var season:Int?
    var session:LastSession
    /// Seconds each hero was played, both modes together (OverFast's keys).
    var heroes:[String:Int]=[:]
    /// Divisions the last session's rank moved (LastSession.rank); nil when it didn't.
    var rankSteps:Int?
    /// The look before this one: a change covering more than one night (looks missed for days) is several sessions,
    /// never told as one.
    var since:Date?
    /// Divisions each role moved; nil in what an older Recall kept.
    var rankMoves:[String:Int]?
    /// A rank above the role's best so far this season (set as the change is kept; a season's first ranks are none).
    var seasonHigh:CareerRank?
    var milestone:Milestone?
    /// Each ranked role's rank before and after ("gold 3"), so moves are worked out again if the ladder changes.
    var ranked:[String:[String]]?

    /// Divisions each role moved: from the ranks kept, else as an older Recall counted them.
    var moves:[String:Int]? {
        guard let ranked else { return rankMoves }
        return ranked.reduce(into:[:]) { moves,pair in
            guard pair.value.count == 2,let before=CareerRank.place(pair.value[0]),let after=CareerRank.place(pair.value[1]),after != before else { return }
            moves[pair.key]=after-before
        }
    }
    /// Divisions the last session's rank moved, as `moves` reads them.
    var steps:Int? { session.rank.flatMap { moves?[$0.role.rawValue] } ?? rankSteps }

    /// Hours on a hero worth telling: 10, 25 and 50, then every hundred.
    static func isMilestone(_ hours:Int)->Bool { [10,25,50].contains(hours) || (hours >= 100 && hours%100 == 0) }
    /// The change between two looks' totals.
    init(at:Date,season:Int?,session:LastSession,before:[String:ModeStats],after:[String:ModeStats]) {
        self.at=at;self.season=season;self.session=session
        func time(_ modes:[String:ModeStats])->[String:Int] {
            modes.values.reduce(into:[:]) { total,mode in for (hero,seconds) in mode.heroes { total[hero,default:0]+=seconds } }
        }
        let old=time(before),new=time(after)
        for (hero,seconds) in new where seconds > old[hero] ?? 0 { heroes[hero]=seconds-(old[hero] ?? 0) }
    }
    /// The highest milestone any hero passed between two of Recall's counts (the first by name on a tie).
    static func milestone(from old:[String:Int],to new:[String:Int])->Milestone? {
        var milestone:Milestone?
        for (hero,seconds) in new.sorted(by:{ $0.key < $1.key }) {
            let from=(old[hero] ?? 0)/3600,to=seconds/3600
            guard to > from,let passed=(from+1...to).reversed().first(where:isMilestone),passed > (milestone?.hours ?? 0) else { continue }
            milestone=Milestone(hero:hero,hours:passed)
        }
        return milestone
    }
}

/// Each hero's time as Recall counts it: from the first look, adding each look's gains, never going down at a new
/// season.
struct HeroHours: Codable, Equatable {
    /// The look that started the count.
    var since:Date
    /// Seconds per hero (OverFast's keys).
    var heroes:[String:Int]=[:]
    /// What the last look found in each mode (games, each hero's seconds), which the next look's gains count from.
    var seenGames:[String:Int]=[:]
    var seen:[String:[String:Int]]=[:]
    /// Seconds per role, each gain in the role its hero had then; nil in what an older Recall kept.
    var roles:[String:Int]?

    /// A look found these totals. Competitive starts over only at a season's turn (`turned`). `baseline` takes them as
    /// the new start without counting.
    mutating func count(_ modes:[String:ModeStats],turned:Bool=false,baseline:Bool=false,role:(String)->CareerRank.Role?={ _ in nil }) {
        for (mode,stats) in modes {
            let before=seen[mode] ?? [:]
            let over=turned && mode == "competitive"
            if !baseline {
                for (hero,seconds) in stats.heroes {
                    let gained=over ? seconds : seconds-(before[hero] ?? 0)
                    guard gained > 0 else { continue }
                    heroes[hero,default:0]+=gained
                    if let role=role(hero) { roles=roles ?? [:];roles![role.rawValue,default:0]+=gained }
                }
            }
            seen[mode]=stats.heroes;seenGames[mode]=stats.games.played
        }
    }
}

/// The times the card's records cover. All time is the profile's own totals (CareerCard), not the history's.
enum CareerPeriod: String, Codable, CaseIterable { case last,today,week,season,all }

struct CareerHistory: Codable, Equatable {
    /// Runs and changes are kept this long.
    static let kept:TimeInterval=400*24*3600
    /// The rank hides once matches were played after a look older than this.
    static let stale:TimeInterval=2*24*3600
    /// A game after this long without one is a comeback.
    static let away:TimeInterval=3*24*3600
    /// A night runs until four in the morning: a game at one belongs to the evening before.
    static let nightEnds:TimeInterval=4*3600
    var runs:[PlayedRun]=[]
    var changes:[ProfileChange]=[]
    /// The season Recall last saw, when it first saw it, and whether Recall had seen the one before.
    var season:Int?
    var seasonSeen:Date?
    var seasonFollows=false
    /// This season's first rank and best rank in each role.
    var seasonFirst:[CareerRank]=[]
    var seasonPeak:[CareerRank]=[]
    /// The season before this one, as it ended: kept at the turn so its story can still be told (no words use it yet).
    struct SeasonStory: Codable, Equatable { var season:Int;var first:[CareerRank];var peak:[CareerRank];var from:Date?;var to:Date }
    var lastSeason:SeasonStory?
    /// The last look that found the profile.
    var looked:Date?
    /// Each hero's time as Recall has counted it; nil until a look has (and in what an older Recall kept).
    var hours:HeroHours?
    /// The player whose profile the changes and hours are from (OverFast's id); nil in what an older Recall kept.
    var player:String?
    /// Other players' parts (changes, season, hours; no runs), set aside until their BattleTag is found again: a few at
    /// most.
    var parked:[String:CareerHistory]?
    /// The file's format. A newer one is read but never written over. Fields added later must be optional or have a
    /// default.
    var v=CareerHistory.format
    static let format=1

    /// A run ended. One Recall quit during and took up again from the game's start replaces what was kept of it.
    mutating func ran(_ run:PlayedRun) {
        runs.removeAll { $0.sameStart(run) }
        runs.append(run);runs.sort { $0.start < $1.start }
        let newest=Self.newest(run.end)
        runs.removeAll { newest.timeIntervalSince($0.end) > Self.kept }
    }
    /// What the keeping counts back from: a date past tomorrow (the Mac's clock was wrong) never clears the rest.
    private static func newest(_ date:Date)->Date { min(date,Date().addingTimeInterval(86_400)) }
    /// A look found the profile: its season, ranks and change. `fresh` false: the ranks weren't taken with the totals,
    /// so their age isn't reset.
    mutating func looked(at time:Date,season:Int?,ranks:[CareerRank],change:ProfileChange?,fresh:Bool=true) {
        // A look with no season (no competitive ranks yet) keeps the one Recall knows.
        if let season,season != self.season {
            seasonFollows=self.season != nil
            if let ended=self.season,!seasonPeak.isEmpty { lastSeason=SeasonStory(season:ended,first:seasonFirst,peak:seasonPeak,from:seasonSeen,to:time) }
            self.season=season;seasonSeen=time;seasonFirst=[];seasonPeak=[]
        }
        if var change {
            change.seasonHigh=ranks.filter { new in seasonPeak.contains { $0.role == new.role && new.standing > $0.standing } }.max { $0.standing < $1.standing }
            changes.append(change);changes.sort { $0.at < $1.at }
            let newest=Self.newest(changes.last!.at)
            changes.removeAll { newest.timeIntervalSince($0.at) > Self.kept }
        }
        for rank in ranks {
            if !seasonFirst.contains(where:{ $0.role == rank.role }) { seasonFirst.append(rank) }
            if let index=seasonPeak.firstIndex(where:{ $0.role == rank.role }) {
                if rank.standing > seasonPeak[index].standing { seasonPeak[index]=rank }
            } else { seasonPeak.append(rank) }
        }
        if fresh { looked=time }
    }
    /// A look found the profile with these totals: their hours are counted (from these, at the first).
    mutating func count(_ modes:[String:ModeStats],at time:Date,turned:Bool=false,baseline:Bool=false,role:(String)->CareerRank.Role?={ _ in nil }) {
        guard !modes.isEmpty else { return }
        var hours=self.hours ?? HeroHours(since:time)
        hours.count(modes,turned:turned,baseline:baseline,role:role);self.hours=hours
    }
    /// The runs since the last change the profile told, whose records come with the next look that finds it changed.
    var waiting:[PlayedRun] { let last=changes.last?.at ?? .distantPast;return runs.filter { $0.start > last } }
    /// The runs a change covers: those since the change before it (Blizzard can update before the game closes).
    func runs(for change:ProfileChange)->[PlayedRun] {
        let before=changes.last { $0.at < change.at }?.at ?? .distantPast
        return runs.filter { $0.start <= change.at && $0.end > before }
    }
    /// Another player's profile was found: this one's part is set aside (by `from` in an older file) and that player's
    /// comes back if it was.
    mutating func switchPlayer(from old:String?,to id:String) {
        guard player != id else { return }
        var aside=parked ?? [:]
        if let owner=player ?? old,owner != id { var part=self;part.runs=[];part.parked=nil;aside[owner]=part }
        let back=aside.removeValue(forKey:id)
        forgetProfile()
        if let back {
            changes=back.changes;season=back.season;seasonSeen=back.seasonSeen;seasonFollows=back.seasonFollows
            seasonFirst=back.seasonFirst;seasonPeak=back.seasonPeak;lastSeason=back.lastSeason;looked=back.looked;hours=back.hours
        }
        player=id
        // Four at most: the one seen longest ago goes.
        while aside.count > 4,let oldest=aside.min(by:{ ($0.value.looked ?? .distantPast) < ($1.value.looked ?? .distantPast) })?.key { aside[oldest]=nil }
        parked=aside.isEmpty ? nil : aside
    }
    mutating func forgetProfile() {
        player=nil;changes=[];season=nil;seasonSeen=nil;seasonFollows=false;seasonFirst=[];seasonPeak=[];lastSeason=nil;looked=nil;hours=nil
    }

    /// What a period's changes add up to; nil when none falls in it, and for all time. Days run from 4 am; a change of
    /// several sessions counts in none.
    func session(_ period:CareerPeriod,now:Date,calendar:Calendar = .current)->LastSession? {
        let picked:[ProfileChange]
        switch period {
        case .last: picked=changes.suffix(1).filter { !lumped($0,calendar:calendar) }
        case .today: picked=changes.filter { Self.night($0.at,calendar) == Self.night(now,calendar) && !lumped($0,calendar:calendar) }
        case .week:
            let week=calendar.dateInterval(of:.weekOfYear,for:now.addingTimeInterval(-Self.nightEnds))
            picked=changes.filter { week?.contains($0.at.addingTimeInterval(-Self.nightEnds)) == true && !lumped($0,calendar:calendar) }
        case .season: picked=season == nil ? [] : changes.filter { $0.season == season }
        case .all: return nil
        }
        guard var total=picked.first?.session else { return nil }
        for change in picked.dropFirst() { total.add(change.session) }
        // The hero of the period: the one played longest over its changes.
        if picked.count > 1 {
            let time=picked.reduce(into:[String:Int]()) { sum,change in for (hero,seconds) in change.heroes { sum[hero,default:0]+=seconds } }
            total.hero=time.sorted { $0.key < $1.key }.max { $0.value < $1.value }?.key
        }
        return total
    }
    /// The night a moment belongs to (a game at 1 am is the evening before), by date, so a clock change can't skip one.
    static func night(_ date:Date,_ calendar:Calendar)->DateComponents { calendar.dateComponents([.year,.month,.day],from:date.addingTimeInterval(-nightEnds)) }
    /// A change that covers more than one night of this Mac's play: several sessions told together.
    func lumped(_ change:ProfileChange,calendar:Calendar = .current)->Bool {
        guard let since=change.since else { return false }
        return Set(runs.filter { $0.end > since && $0.start <= change.at }.map { Self.night($0.start,calendar) }).count > 1
    }
    /// Nights in a row with a game, tonight's included; sessions the profile told count too. A game going on counts
    /// from the night it opened (`since`).
    func nightsInARow(now:Date,playing:Bool,since start:Date?=nil,calendar:Calendar = .current)->Int {
        var nights=Set(runs.map { Self.night($0.start,calendar) }+changes.map { Self.night($0.at,calendar) })
        let tonight=Self.night(playing ? start ?? now : now,calendar)
        if playing { nights.insert(tonight) }
        // Stepping back from each night's noon, so no clock change can land between two of them.
        var day=calendar.date(from:tonight).flatMap { calendar.date(bySettingHour:12,minute:0,second:0,of:$0) },count=0
        while let at=day,nights.contains(calendar.dateComponents([.year,.month,.day],from:at)) { count+=1;day=calendar.date(byAdding:.day,value:-1,to:at) }
        return count
    }
    /// How many of the last `nights` nights, tonight's included, had a game (the same sources as nightsInARow).
    func nightsPlayed(of nights:Int,now:Date,playing:Bool,since start:Date?=nil,calendar:Calendar = .current)->Int {
        var played=Set(runs.map { Self.night($0.start,calendar) }+changes.map { Self.night($0.at,calendar) })
        let tonight=Self.night(playing ? start ?? now : now,calendar)
        if playing { played.insert(tonight) }
        var day=calendar.date(from:tonight).flatMap { calendar.date(bySettingHour:12,minute:0,second:0,of:$0) },count=0
        for _ in 0..<nights {
            guard let at=day else { break }
            if played.contains(calendar.dateComponents([.year,.month,.day],from:at)) { count+=1 }
            day=calendar.date(byAdding:.day,value:-1,to:at)
        }
        return count
    }
    /// Matches in the runs just before `start` the same night, each under ten minutes after the last (a crash, a
    /// relaunch).
    func joined(before start:Date,calendar:Calendar = .current)->Int {
        var total=0,next=start
        for run in runs.reversed() where run.start < start && abs(run.start.timeIntervalSince(start)) >= 1 {
            guard next.timeIntervalSince(run.end) < 600,Self.night(run.start,calendar) == Self.night(start,calendar) else { break }
            total+=run.matches ?? 0;next=run.start
        }
        return total
    }
    /// Time played this week (from the first day of the week the Mac's calendar uses), the run going on included.
    func playedThisWeek(now:Date,current start:Date?,sleeping:TimeInterval=0,calendar:Calendar = .current)->TimeInterval {
        guard let week=calendar.dateInterval(of:.weekOfYear,for:now) else { return 0 }
        // A run kept when Recall quit during this game is part of `start`'s time already. The Mac asleep isn't play.
        var total=runs.filter { run in start.map { abs(run.start.timeIntervalSince($0)) >= 1 } ?? true }
            .reduce(0) { $0+max(0,min($1.end,week.end).timeIntervalSince(max($1.start,week.start))-($1.start >= week.start ? $1.slept ?? 0 : 0)) }
        if let start { total+=max(0,now.timeIntervalSince(max(start,week.start))-sleeping) }
        return total
    }
    /// The time since the last game, when it's three days or more (a session the profile told counts too).
    func away(before start:Date)->TimeInterval? {
        guard let last=(runs.filter { $0.end <= start }.map(\.end)+changes.filter { $0.at <= start }.map(\.at)).max() else { return nil }
        let gap=start.timeIntervalSince(last)
        return gap >= Self.away ? gap : nil
    }
    /// The latest change while it's news: no game opened since on an earlier night (it lasts the night, through a crash
    /// or relaunch).
    func news(before start:Date,calendar:Calendar = .current)->ProfileChange? {
        let tonight=Self.night(start,calendar)
        guard let change=changes.last,!lumped(change,calendar:calendar),
              !runs.contains(where:{ $0.start > change.at && $0.start < start && Self.night($0.start,calendar) != tonight }) else { return nil }
        return change
    }
    /// A new season, while it is news: Recall saw the season before it, and no game has opened since.
    func newSeason(before start:Date)->Int? {
        guard seasonFollows,let season,let seen=seasonSeen,!runs.contains(where:{ $0.end > seen && $0.start < start }) else { return nil }
        return season
    }
    /// Matches were played since a look that's old: the rank may be wrong.
    func rankStale(now:Date)->Bool {
        guard let looked,now.timeIntervalSince(looked) > Self.stale else { return false }
        return runs.contains { $0.end > looked && ($0.matches ?? 1) > 0 }
    }
    /// This season's first rank and best rank in a role, for the season's climb and peak.
    func first(_ role:CareerRank.Role)->CareerRank? { seasonFirst.first { $0.role == role } }
    func peak(_ role:CareerRank.Role)->CareerRank? { seasonPeak.first { $0.role == role } }
}

extension CareerHistory {
    /// What Recall remembers › Export: each run and profile change, oldest first, as CSV (UTF-8 with its mark for
    /// Numbers and Excel), in this Mac's time.
    func csv(heroes:[String:CareerHero],timeZone:TimeZone = .current)->String {
        let format=DateFormatter();format.locale=Locale(identifier:"en_US_POSIX");format.timeZone=timeZone;format.dateFormat="yyyy-MM-dd HH:mm"
        func tally(_ t:Tally)->String { t.played > 0 ? L("{0}–{1}",String(t.won),String(t.lost)) : "" }
        // A hero's name comes from OverFast: one that starts as a formula would (=, +, -, @) stays text in a spreadsheet.
        func name(_ text:String)->String { text.first.map { "=+-@".contains($0) } == true ? "'"+text : text }
        var rows:[(at:Date,fields:[String])]=runs.map { run in
            (run.end,[format.string(from:run.start),format.string(from:run.end),L("Played on this Mac"),run.matches.map(String.init) ?? "","","","","",""])
        }
        for change in changes {
            let session=change.session
            rows.append((change.at,["",format.string(from:change.at),L("Profile change"),String(session.played),tally(session.competitive),tally(session.quickplay),
                                    session.hero.map { name(heroes[$0]?.name ?? $0) } ?? "",session.rank?.label() ?? "",change.steps.map { $0 > 0 ? "+\($0)" : String($0) } ?? ""]))
        }
        // A field with a comma, a quote or a line break is quoted, its quotes doubled.
        func field(_ text:String)->String {
            text.contains(where:{ $0 == "," || $0 == "\"" || $0.isNewline }) ? "\"\(text.replacingOccurrences(of:"\"",with:"\"\""))\"" : text
        }
        let head=[L("Started"),L("Ended"),L("What"),L("Matches"),L("Competitive"),L("Quick Play"),L("Hero"),L("Rank"),L("Divisions")]
        let lines=[head]+rows.sorted { $0.at < $1.at }.map(\.fields)
        return "\u{FEFF}"+lines.map { $0.map(field).joined(separator:",") }.joined(separator:"\r\n")+"\r\n"
    }
}
extension Tally {
    static func +(a:Tally,b:Tally)->Tally { Tally(played:a.played+b.played,won:a.won+b.won,lost:a.lost+b.lost) }
}
extension LastSession {
    /// Another change added to these. Other modes count only when every change told them; best, rank and hero are the
    /// latest's.
    mutating func add(_ later:LastSession) {
        competitive=competitive+later.competitive;quickplay=quickplay+later.quickplay
        other=other.flatMap { count in later.other.map { count+$0 } }
        eliminations+=later.eliminations;deaths+=later.deaths;damage+=later.damage;healing+=later.healing
        best=later.best ?? best;hero=later.hero ?? hero;role=later.role ?? role
        if later.rank != nil { rank=later.rank;promoted=later.promoted }
    }
}
extension CareerRank {
    /// Divisions between two ranks (Gold 1 to Platinum 5 is one, Gold 3 to Gold 1 is two); positive is up.
    func steps(from old:CareerRank)->Int { place-old.place }
    /// The divisions each role moved between two looks' ranks, for the roles ranked in both that moved.
    static func moves(from before:[CareerRank],to after:[CareerRank])->[String:Int] {
        after.reduce(into:[:]) { moves,new in
            if let old=before.first(where:{ $0.role == new.role }),new.steps(from:old) != 0 { moves[new.role.rawValue]=new.steps(from:old) }
        }
    }
    private var place:Int { (Self.divisions.firstIndex(of:division) ?? -1)*5+(5-tier) }
    /// A rank kept as text ("gold 3"), as a place on the ladder; nil for a division this Recall doesn't know.
    static func place(_ text:String)->Int? {
        let parts=text.split(separator:" ")
        guard parts.count == 2,let index=divisions.firstIndex(of:String(parts[0])),let tier=Int(parts[1]),(1...5).contains(tier) else { return nil }
        return index*5+(5-tier)
    }
    /// The rank as `ranked` keeps it.
    var kept:String { "\(division) \(tier)" }
}

// A history from an earlier or later Recall still reads: what's missing is empty, and an unreadable entry is left out,
// not the file.
extension CareerHistory {
    init(from decoder:Decoder) throws {
        let kept=try decoder.container(keyedBy:CodingKeys.self)
        func value<T:Decodable>(_ key:CodingKeys)->T? {
            do { return try kept.decodeIfPresent(T.self,forKey:key) } catch { (decoder.userInfo[.skipped] as? Skipped)?.count+=1;return nil }
        }
        func list<T:Decodable>(_ key:CodingKeys)->[T] { (value(key) as [Readable<T>]?)?.compactMap(\.value) ?? [] }
        self.init()
        runs=list(.runs);changes=list(.changes);seasonFirst=list(.seasonFirst);seasonPeak=list(.seasonPeak)
        season=value(.season);seasonSeen=value(.seasonSeen);seasonFollows=value(.seasonFollows) ?? false
        looked=value(.looked);hours=value(.hours);player=value(.player);parked=value(.parked);v=value(.v) ?? 1;lastSeason=value(.lastSeason)
    }
}

/// Keeps the history in its file: read once (again when it changed on disk), written whole after each change. Safe from
/// any thread; no file means memory only.
final class CareerHistoryStore {
    /// Recall's own folder in Application Support, not the game's data folder (which can be on another drive).
    static var standardURL:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("org.overwatch2mac.launcher/career-history.json")
    }
    private let url:URL?
    private let lock=NSLock()
    private var history:CareerHistory?
    /// The file as last read or written: one changed or gone since (put back, trashed) is read again.
    private var stamp:Stamp?
    /// Not written: the file couldn't be read (it's kept as it is), or a newer Recall wrote it.
    private var keep=false
    /// Some entries couldn't be read: a copy of the file is made before the first write.
    private var copyFirst=false
    /// Uninstall: nothing is read or written from now on.
    private var closed=false
    init(url:URL?) { self.url=url }
    var current:CareerHistory { lock.lock();defer { lock.unlock() };return loaded() }
    func update(_ change:(inout CareerHistory)->Void) {
        lock.lock();defer { lock.unlock() }
        guard !closed else { return }
        var value=loaded();change(&value);history=value
        guard let url,!keep else { return }
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if copyFirst {
            let day=Date().formatted(.iso8601.year().month().day())
            try? FileManager.default.copyItem(at:url,to:url.deletingPathExtension().appendingPathExtension("kept-\(day).json"))
            copyFirst=false
        }
        value.v=max(value.v,CareerHistory.format)
        if let data=try? Self.encoder.encode(value),(try? data.write(to:url,options:.atomic)) != nil { stamp=Stamp(url) }
    }
    /// What Recall remembers › Erase: everything goes, the file too.
    func erase() {
        lock.lock();defer { lock.unlock() }
        guard !closed else { return }
        history=CareerHistory();keep=false;copyFirst=false
        if let url { try? FileManager.default.removeItem(at:url);try? FileManager.default.removeItem(at:Self.aside(url)) }
        stamp=url.map(Stamp.init)
    }
    /// Uninstall: the history is let go and nothing more is written (the folder went to the Trash).
    func close() { lock.lock();defer { lock.unlock() };closed=true;history=CareerHistory() }
    private func loaded()->CareerHistory {
        if closed { return history ?? CareerHistory() }
        if history != nil,let url,Stamp(url) != stamp { history=nil }
        if let history { return history }
        var value=CareerHistory()
        keep=false;copyFirst=false
        if let url {
            do {
                let data=try Data(contentsOf:url)
                let skipped=Skipped(),decoder=Self.decoder()
                decoder.userInfo[.skipped]=skipped
                if let read=try? decoder.decode(CareerHistory.self,from:data) {
                    value=read;copyFirst=skipped.count > 0;keep=read.v > CareerHistory.format
                } else {
                    // A file that can't be read at all is set aside, not written over.
                    try? FileManager.default.removeItem(at:Self.aside(url));try? FileManager.default.moveItem(at:url,to:Self.aside(url))
                }
            } catch CocoaError.fileReadNoSuchFile {
                // No file yet (or it went): a fresh start.
            } catch {
                // There but unreadable (permissions, a drive away): nothing is kept in memory or written; asked again next time.
                keep=true;stamp=nil
                return value
            }
        }
        history=value;stamp=url.map(Stamp.init)
        return value
    }
    private static func aside(_ url:URL)->URL { url.deletingPathExtension().appendingPathExtension("unreadable.json") }
    // Dates as text, so the file reads plainly to anyone who opens it.
    private static let encoder:JSONEncoder={ let coder=JSONEncoder();coder.dateEncodingStrategy = .iso8601;return coder }()
    private static func decoder()->JSONDecoder { let coder=JSONDecoder();coder.dateDecodingStrategy = .iso8601;return coder }
    /// A file's identity and last change, or that it isn't there.
    private struct Stamp: Equatable {
        let inode:UInt64?;let changed:Date?
        init(_ url:URL) {
            let info=try? FileManager.default.attributesOfItem(atPath:url.path)
            inode=(info?[.systemFileNumber] as? NSNumber)?.uint64Value;changed=info?[.modificationDate] as? Date
        }
    }
}
