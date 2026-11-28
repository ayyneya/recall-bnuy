import Foundation

// What each part of the card can say, from the profile, the history and the log. A piece with nothing true to say gives
// nil and takes no turn. The words are Recall's own: nothing typed goes on the card.

/// What a card is made from, at one moment.
struct CardInputs {
    var place:PresenceState = .unknown
    var voice:GroupVoice?
    /// Whether the match is a competitive one, when a source can tell (none can yet: PresenceFacts).
    var competitive:Bool?
    /// The profile; nil without a BattleTag, while it's private or not found, or before the first look.
    var profile:CareerCard?
    var history=CareerHistory()
    /// The BattleTag's name, for line 1 while the profile has none.
    var tagName:String?
    var launched:Date
    /// The matches the log saw tonight in this run, the one going on included.
    var matches=0
    /// Seconds this run spent with the Mac asleep.
    var slept:TimeInterval=0
    var now:Date
    var texts:PresenceTexts
    var calendar:Calendar = .current
}

struct CardImage: Equatable {
    let url:URL
    let hover:String?
    /// The hero it shows, for the hero's page.
    var hero:String?=nil
}

extension CardInputs {
    var inMatch:Bool { if case .match=place { return true };return false }
    var menus:Bool { place == .menu }
    /// The log can't tell menus from a match (voice chat off, a group's voice).
    var unsure:Bool { place == .unknown }
    var name:String? { profile?.identity?.name ?? tagName }
    /// The latest change while it is news (until a game opens after the one it came from).
    var news:ProfileChange? { profile == nil ? nil : history.news(before:launched,calendar:calendar) }
    /// The ranks the card may show: none once the last look is too old for the matches played since.
    var ranks:[CareerRank] { profile != nil && !history.rankStale(now:now) ? profile!.ranks : [] }
    /// The last session and its hero, gone with the ranks: matches played since the last look make them old news.
    var last:LastSession? { history.rankStale(now:now) || history.changes.last.map({ history.lumped($0,calendar:calendar) }) == true ? nil : profile?.last }
    var lastHero:CareerHero? { last == nil ? nil : profile?.hero }
    func rank(_ choice:RankChoice)->CareerRank? {
        let ranks=self.ranks
        switch choice {
        case .role(let role): return ranks.first { $0.role == role }
        case .highest: return ranks.max { $0.standing < $1.standing }
        case .lastPlayed: return CareerCard(ranks:ranks,last:last).rank
        }
    }
    /// Every rank, in the roles' order, with how the last session moved it ("Tank ↑ Emerald 1").
    var allRanks:[(rank:CareerRank,text:String)] {
        ranks.sorted { CareerRank.Role.allCases.firstIndex(of:$0.role)! < CareerRank.Role.allCases.firstIndex(of:$1.role)! }.map { ($0,rankText($0)) }
    }
    /// ↑ up a division, ↟ two or more, ↓ and ↡ down, – the same: what the last session did to this role.
    func arrow(_ rank:CareerRank)->String {
        guard let change=history.changes.last else { return "–" }
        let steps:Int
        if let moves=change.moves { steps=moves[rank.role.rawValue] ?? 0 }
        else {
            guard let moved=change.session.rank,moved.role == rank.role else { return "–" }
            steps=change.steps ?? (change.session.promoted ? 1 : -1)
        }
        return steps >= 2 ? "↟" : steps == 1 ? "↑" : steps == -1 ? "↓" : steps <= -2 ? "↡" : "–"
    }
    func rankText(_ rank:CareerRank)->String {
        // One phrase per role, so it never shares a key with the same words elsewhere.
        switch rank.role {
        case .tank: return L("Tank {0} {1}",arrow(rank),rank.name)
        case .damage: return L("Damage {0} {1}",arrow(rank),rank.name)
        case .support: return L("Support {0} {1}",arrow(rank),rank.name)
        case .open: return L("6v6 {0} {1}",arrow(rank),rank.name)
        }
    }

    /// Each hero's time, all modes, all time: Recall's own count (HeroHours), or the profile's totals before it has
    /// one.
    var heroTime:[String:Int] {
        if profile != nil,let counted=history.hours?.heroes,!counted.isEmpty { return counted }
        return modes.reduce(into:[:]) { total,mode in for (hero,seconds) in mode.heroes { total[hero,default:0]+=seconds } }
    }
    /// The profile's totals, Competitive and Quick Play.
    var modes:[ModeStats] { profile.map { Array($0.totals.values) } ?? [] }
    /// The heroes by time played, most first (by name when two are alike).
    var topHeroes:[String] { heroTime.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key) }
    func heroName(_ key:String)->String { profile?.heroes[key]?.name ?? CareerHero.name(key) }
    /// Daytime (four in the morning to five in the afternoon): "today", else "tonight".
    var daytime:Bool { (4..<17).contains(calendar.component(.hour,from:now)) }
    /// When something was, as friends read it: earlier today or tonight, last night, or a weekday; nil after a week.
    func when(_ date:Date)->String? {
        guard let that=calendar.date(from:CareerHistory.night(date,calendar)),let tonight=calendar.date(from:CareerHistory.night(now,calendar)) else { return nil }
        switch calendar.dateComponents([.day],from:that,to:tonight).day ?? 99 {
        case 0: return daytime ? L("Earlier today") : L("Earlier tonight")
        case 1: return L("Last night")
        case 2...6: return that.formatted(Date.FormatStyle(calendar:calendar).weekday(.wide).locale(CardWords.locale))
        default: return nil
        }
    }
    /// The last session's words ("Last night · Comp 3–1"); nil after a week. A profile older than the history says
    /// "Last ·".
    func lastSession(_ body:String)->String? {
        guard let at=history.changes.last?.at else { return L("Last · {0}",body) }
        return when(at).map { L("{0} · {1}",$0,body) }
    }
    /// Matches tonight: this run's, and the runs just before it the same night (a crash, a relaunch).
    var tonight:Int { matches+history.joined(before:launched,calendar:calendar) }
    /// The profile's Competitive totals are this season's: it has a rank now.
    var compThisSeason:Bool { !(profile?.ranks.isEmpty ?? true) }
    func hours(_ seconds:Int)->String { seconds >= 3600 ? L("{0}h",count(seconds/3600)) : L("{0}m",String(max(1,seconds/60))) }
    /// A count as the card writes numbers ("1,204").
    func count(_ number:Int)->String { number.formatted(.number.locale(CardWords.locale)) }
    /// A win rate that never contradicts its record: no "100%" with a loss, no "0%" with a win.
    static func rate(_ t:Tally)->String {
        guard t.played > 0 else { return "0" }
        let rate=Int((Double(t.won)*100/Double(t.played)).rounded())
        return String(min(t.lost > 0 ? 99 : 100,max(t.won > 0 ? 1 : 0,rate)))
    }
    /// A role's share of the time played: Recall's count by role, or the heroes' current roles.
    func share(_ role:CareerRank.Role)->Double {
        if profile != nil,let roles=history.hours?.roles,!roles.isEmpty {
            let total=roles.values.reduce(0,+)
            return total > 0 ? Double(roles[role.rawValue] ?? 0)/Double(total) : 0
        }
        let time=heroTime,total=time.values.reduce(0,+)
        guard total > 0 else { return 0 }
        return Double(time.filter { profile?.heroes[$0.key]?.role == role }.values.reduce(0,+))/Double(total)
    }

    /// Line 1's words before where the player is; nil leaves just the place.
    func lineOne(_ item:LineOne,rank choice:RankChoice)->String? {
        switch item {
        case .name: return name
        // The title goes first when line 1 would pass about 30 characters (Discord cuts it there, place and all).
        case .nameAndTitle:
            let both=[name,profile?.identity?.title].compactMap { $0 }.joined(separator:" ")
            return both.count+3+max(texts.menu.count,texts.match.count) > 30 ? name : both.nilIfEmpty
        case .main: return topHeroes.first.map { L("{0} main",heroName($0)) } ?? name
        // The rank on line 1 in the menus only: in a match it would read as this match's.
        case .rank: return menus ? rank(choice).map(rankText) ?? name : name
        case .placeOnly: return nil
        case .phrase: return name
        }
    }
    /// A phrase's words, its blank filled; nil when an Auto blank has nothing to fill it (no profile, no rank above).
    func phrase(_ phrase:LinePhrase,rank choice:RankChoice)->String? {
        let filled:String?
        switch (phrase.words.kind,phrase.blank) {
        case (.none,_): filled=""
        case (.hero,.hero(let key)): filled=heroName(key)
        case (.hero,_): filled=topHeroes.first.map(heroName)
        case (.rank,.rank(let division)): filled=CareerRank.name(division)
        // Auto: the next division above the rank, in the menus only (in a match it would read as this match's).
        case (.rank,_): filled=menus ? rank(choice).flatMap { CareerRank.divisions.firstIndex(of:$0.division) }.flatMap { $0+1 < CareerRank.divisions.count ? CareerRank.name(CareerRank.divisions[$0+1]) : nil } : nil
        case (.role,.role(let role)): filled=role.label
        case (.role,_): filled=[CareerRank.Role.tank,.damage,.support].filter { share($0) > 0 }.max { share($0) < share($1) }?.label
        }
        guard let filled else { return nil }
        switch phrase.words {
        case .roadTo: return L("Road to {0}",filled)
        case .grindingTo: return L("Grinding to {0}",filled)
        case .learning: return L("Learning {0}",filled)
        case .maining: return L("Maining {0}",filled)
        case .practicing: return L("Practicing {0}",filled)
        case .rolePlayer: return L("{0} player",filled)
        case .climbingIn: return L("Climbing in {0}",filled)
        case .offRole: return L("Off-role {0}",filled)
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

    /// The button after Get Recall, when there is somewhere for it to go.
    func button(_ button:SecondButton,picture:CardImage?)->(label:String,url:URL)? {
        switch button {
        case .careerProfile: return profile?.page.map { (L("Career Profile"),$0) }
        case .heroPage:
            guard let hero=picture?.hero ?? topHeroes.first,let url=URL(string:"https://overwatch.blizzard.com/en-us/heroes/\(hero)/") else { return nil }
            return (heroName(hero),url)
        case .patchNotes: return (L("Patch notes"),URL(string:"https://overwatch.blizzard.com/en-us/news/patch-notes/")!)
        }
    }
}

extension CardPiece {
    /// The key an unlocked line is kept by ("title.flex"): its cases' raw names, never Swift's own spelling of them.
    var key:String {
        switch self {
        case .highlights: return "highlights"
        case .moment(let moment): return "moment."+moment.rawValue
        case .rank(let line): return "rank."+line.rawValue
        case .record(let period,let mode,let winRate): return "record.\(period.rawValue).\(mode.rawValue)"+(winRate ? ".winRate" : "")
        case .hero(let hero,let line): return "hero.\(hero ?? "top").\(line.rawValue)"
        case .best(let line): return "best."+line.rawValue
        case .tonight(let line): return "tonight."+line.rawValue
        case .title(let line): return "title."+line.rawValue
        }
    }
    /// A key kept by an earlier build ("title(Recall.TitleLine.flex)") in today's form; only titles were unlocked then.
    static func stableKey(_ kept:String)->String {
        guard let open=kept.firstIndex(of:"("),let last=kept.lastIndex(of:".") else { return kept }
        return kept[..<open]+"."+kept[kept.index(after:last)...].filter { $0 != ")" }
    }
    /// Lines that may show when menus and a match can't be told apart: what's safe in a match, and past results.
    var safeWhenUnsure:Bool {
        switch self {
        case .highlights,.record,.best: return true
        default: return safeInMatch
        }
    }
    var safeInMatch:Bool {
        switch self {
        case .highlights,.hero,.tonight,.title: return true
        default: return false
        }
    }

    /// The words on Line 2, or nil when there's nothing true to say right now.
    func text(_ i:CardInputs,rank choice:RankChoice)->String? {
        switch self {
        case .highlights: return Self.highlight(i,rank:choice)?.text
        case .moment(let moment):
            guard i.menus else { return nil }
            switch moment {
            case .rankChange: return i.news?.session.rank.map(i.rankText)
            case .newBest: return i.news?.session.best.flatMap(Self.best).map { L("★ New best: {0}",$0) }
            case .seasonHigh: return i.news?.seasonHigh.map { L("★ Season high: {0}",$0.name) }
            case .milestone: return i.news?.milestone.map { L("★ {0} hours on {1}",String($0.hours),i.heroName($0.hero)) }
            case .comeback: return i.history.away(before:i.launched).map { L("First game in {0} days",String(Int($0/86400))) }
            // Retired (D8e): kept so codes that have it still read.
            case .newSeason: return nil
            }
        case .rank(let line):
            switch line {
            case .current: return i.rank(choice).map(i.rankText)
            case .climb:
                // Only a climb: below the season's first rank it skips its turn.
                guard let now=i.rank(choice),let first=i.history.first(now.role),now.standing > first.standing else { return nil }
                return L("{0} → {1} this season",first.name,now.name)
            case .peak: return i.rank(choice).flatMap { i.history.peak($0.role) }.map { L("Season peak: {0}",$0.name) }
            case .all: return i.allRanks.isEmpty ? nil : i.allRanks.map(\.text).joined(separator:" · ")
            case .change: return CardPiece.moment(.rankChange).text(i,rank:choice)
            }
        case .record(let period,let mode,let winRate):
            // The last session and all time are the profile's own; the other periods add up what Recall remembers.
            let games:LastSession?
            switch period {
            case .last: games=i.last
            // The profile's Competitive is the latest season played: only this season's while it has a rank.
            case .all: games=i.profile.map { LastSession(competitive:i.compThisSeason ? $0.totals["competitive"]?.games ?? Tally() : Tally(),quickplay:$0.totals["quickplay"]?.games ?? Tally()) }
            // A season Recall has known for over ten weeks is one the player stopped playing: its sessions span several.
            case .season where i.history.seasonSeen.map({ i.now.timeIntervalSince($0) > 70*86_400 }) ?? true: games=nil
            default: games=i.profile == nil ? nil : i.history.session(period,now:i.now,calendar:i.calendar)
            }
            guard let games else { return nil }
            func tally(_ t:Tally,_ short:(String,String)->String)->String? {
                guard t.played > 0 else { return nil }
                let rate=winRate && mode != .both ? " · "+L("{0}%",CardInputs.rate(t)) : ""
                return short(String(t.won),String(t.lost))+rate
            }
            let comp=tally(games.competitive) { L("Comp {0}–{1}",$0,$1) },quick=tally(games.quickplay) { L("QP {0}–{1}",$0,$1) }
            var body:String?
            switch mode {
            case .competitive: body=comp
            case .quickPlay: body=quick
            case .both: body=[comp,quick].compactMap { $0 }.joined(separator:" · ").nilIfEmpty
            }
            // The last session's other modes (Arcade, custom games) after its Competitive record.
            if period == .last,mode == .competitive,let shown=body,let other=games.other,other > 0,!winRate { body=shown+" · "+L("{0} other",String(other)) }
            guard let body else { return nil }
            // Today's never has the game going on (the profile tells it after the game closes): "earlier".
            switch period {
            case .last: return i.lastSession(body)
            case .today: return L("{0} · {1}",i.daytime ? L("Earlier today") : L("Earlier tonight"),body)
            case .week: return L("Week · {0}",body)
            case .season: return L("This season · {0}",body)
            case .all: return mode == .competitive ? L("This season · {0}",body) : mode == .quickPlay ? L("All time · {0}",body) : L("Overall · {0}",body)
            }
        case .hero(let key,let line):
            guard let hero=key ?? i.topHeroes.first,let time=i.heroTime[hero],time >= 60 else { return nil }
            let name=i.heroName(hero)
            switch line {
            // "Main" is earned: only the most-played hero has it; past half the hours, it's one-trick.
            case .main:
                guard hero == i.topHeroes.first else { return nil }
                return Double(time) > Double(i.heroTime.values.reduce(0,+))*0.5 ? L("{0} one-trick",name) : L("{0} main",name)
            case .hours: return L("{0} · {1}",name,i.hours(time))
            case .role:
                let rest="\(name) \(i.hours(time))"
                switch i.profile?.heroes[hero]?.role {
                case .tank?: return L("Tank · {0}",rest)
                case .damage?: return L("Damage · {0}",rest)
                case .support?: return L("Support · {0}",rest)
                default: return nil
                }
            case .winRate:
                // Under ten games a rate says little: the record itself; past that, the rate and how many games.
                let games=i.modes.compactMap { $0.heroGames?[hero] }.reduce(Tally(),+)
                guard games.played > 0 else { return nil }
                if games.played < 10 { return L("{0} · {1}–{2}",name,String(games.won),String(games.lost)) }
                return L("{0} · {1}% wins in {2} games",name,CardInputs.rate(games),i.count(games.played))
            }
        case .best(let line):
            if line == .new { return CardPiece.moment(.newBest).text(i,rank:choice) }
            guard let value=line.value(i) else { return nil }
            let number=value.formatted(.number.locale(CardWords.locale))
            switch line {
            case .eliminations: return L("Best: {0} elims in a game",number)
            case .damage: return L("Best: {0} damage",number)
            case .healing: return L("Best: {0} healing",number)
            case .killStreak: return L("Best: {0} kill streak",number)
            case .multikill: return L("Best: {0}-kill multikill",number)
            case .new: return nil
            }
        case .tonight(let line):
            switch line {
            case .matches:
                // In a match, which match it is; in the menus, how many there were. "Today" in the daytime.
                let count=i.tonight
                if i.inMatch { return count > 0 ? (i.daytime ? L("Match {0} today",String(count)) : L("Match {0} tonight",String(count))) : nil }
                if i.daytime { return count == 1 ? L("1 match today") : count > 1 ? L("{0} matches today",String(count)) : nil }
                return count == 1 ? L("1 match tonight") : count > 1 ? L("{0} matches tonight",String(count)) : nil
            case .nights:
                let nights=i.history.nightsInARow(now:i.now,playing:true,since:i.launched,calendar:i.calendar)
                // No streak: how many of the last seven nights had a game, from three.
                if nights < 2 {
                    let played=i.history.nightsPlayed(of:7,now:i.now,playing:true,since:i.launched,calendar:i.calendar)
                    return played >= 3 ? L("{0} of the last 7 nights",String(played)) : nil
                }
                let ordinal=NumberFormatter();ordinal.numberStyle = .ordinal;ordinal.locale=CardWords.locale
                return L("{0} night in a row",ordinal.string(from:NSNumber(value:nights)) ?? String(nights))
            case .week:
                let time=i.history.playedThisWeek(now:i.now,current:i.launched,sleeping:i.slept,calendar:i.calendar)
                return time >= 3600 ? L("Week · {0} played",i.hours(Int(time))) : nil
            }
        case .title(let line):
            guard i.profile != nil else { return nil }
            let total=i.heroTime.values.reduce(0,+)/3600
            switch line {
            case .endorsement: return i.profile?.identity?.endorsement.map { L("Endorsement {0}",String($0)) }
            case .hours: return total >= 1 ? L("{0}h in Overwatch",i.count(total)) : nil
            case .roleMain: return Self.roleMain(i)
            case .flex: return [.tank,.damage,.support].allSatisfy { i.share($0) >= 0.2 } ? L("Flex player") : nil
            case .oneTrick:
                guard let top=i.topHeroes.first,let time=i.heroTime[top],Double(time) > Double(i.heroTime.values.reduce(0,+))*0.5 else { return nil }
                return L("{0} one-trick",i.heroName(top))
            case .century: return total >= 100 ? L("{0} hours in",i.count(total/100*100)) : nil
            case .cardboardSupport: return Self.cardboard(i).earned ? L("Cardboard Support") : nil
            }
        }
    }

    /// What Highlights says now and the piece that says it (whose picture it takes): news, the last session, the
    /// Record, tonight's matches, the nights. Outside the menus, past results only.
    static func highlight(_ i:CardInputs,rank choice:RankChoice)->(piece:CardPiece,text:String)? {
        if i.menus { for moment in CardMoment.allCases { if let text=CardPiece.moment(moment).text(i,rank:choice) { return (.moment(moment),text) } } }
        if let last=i.last,let text=i.lastSession(last.summary) { return (.record(.last,.both,winRate:false),text) }
        if i.profile != nil {
            for piece in [CardPiece.record(.all,.competitive,winRate:false),.record(.all,.quickPlay,winRate:false)] { if let text=piece.text(i,rank:choice) { return (piece,text) } }
        }
        for piece in [CardPiece.tonight(.matches),.tonight(.nights)] { if let text=piece.text(i,rank:choice) { return (piece,text) } }
        return nil
    }
    /// An earned line (titles, a hero's "main"): how far along (1 is earned), what earned it or what it still takes;
    /// nil otherwise.
    func progress(_ i:CardInputs)->(done:Double,earned:String?,needed:String?)? {
        guard i.profile != nil else { return nil }
        let percent={ (share:Double) in String(Int((share*100).rounded())) }
        switch self {
        case .title(.roleMain):
            guard let role=[CareerRank.Role.tank,.damage,.support].max(by:{ i.share($0) < i.share($1) }) else { return nil }
            let share=i.share(role),done=min(1,share/0.45)
            let words:(String,String)
            switch role {
            case .tank: words=(L("Earned: Tank is {0}% of your hours",percent(share)),L("Tank is {0}% of your hours; a main needs 45%.",percent(share)))
            case .damage: words=(L("Earned: Damage is {0}% of your hours",percent(share)),L("Damage is {0}% of your hours; a main needs 45%.",percent(share)))
            default: words=(L("Earned: Support is {0}% of your hours",percent(share)),L("Support is {0}% of your hours; a main needs 45%.",percent(share)))
            }
            return done >= 1 ? (1,words.0,nil) : (done,nil,words.1)
        case .title(.flex):
            let least=[CareerRank.Role.tank,.damage,.support].map(i.share).min() ?? 0
            return least >= 0.2 ? (1,L("Earned: every role is 20% or more of your hours"),nil)
                                : (least/0.2,nil,L("Your least-played role is {0}% of your hours; flex needs 20% of each.",percent(least)))
        case .title(.oneTrick):
            guard let top=i.topHeroes.first,let time=i.heroTime[top] else { return nil }
            let share=Double(time)/Double(max(1,i.heroTime.values.reduce(0,+)))
            return share > 0.5 ? (1,L("Earned: {0} is {1}% of your hours",i.heroName(top),percent(share)),nil)
                               : (share/0.5,nil,L("{0} is {1}% of your hours; needs over half.",i.heroName(top),percent(share)))
        case .title(.cardboardSupport):
            let cardboard=Self.cardboard(i),share=i.share(.support)
            if cardboard.earned { return (1,L("Earned: Support main, more damage than healing"),nil) }
            if !cardboard.main { return (min(0.5,share/0.45/2),nil,L("Support is {0}% of your hours; needs 45%, and more damage than healing.",percent(share))) }
            return (0.5+0.5*min(0.97,Double(cardboard.damage)/Double(max(1,cardboard.healing))),nil,
                    L("Support main. Damage {0}, healing {1}: damage has to be more.",cardboard.damage.formatted(.number),cardboard.healing.formatted(.number)))
        case .title(.century):
            let hours=i.heroTime.values.reduce(0,+)/3600
            return hours >= 100 ? (1,L("Earned at 100 hours"),nil) : (Double(hours)/100,nil,L("{0} of 100 hours played.",String(hours)))
        case .hero(let key,.main):
            guard let top=i.topHeroes.first,let topTime=i.heroTime[top] else { return nil }
            let hero=key ?? top,time=i.heroTime[hero] ?? 0
            if hero == top {
                // One ladder: main, then one-trick past half the hours.
                let share=Double(time)/Double(max(1,i.heroTime.values.reduce(0,+)))
                return share > 0.5 ? (1,L("Earned: one-trick, {0}% of your hours",percent(share)),nil)
                                   : (1,L("Earned: main, {0}. One-trick past half your hours ({1}% now)",i.hours(time),percent(share)),nil)
            }
            return (min(0.97,Double(time)/Double(topTime)),nil,L("{0} {1}. Your most-played, {2}, has {3}.",i.heroName(hero),i.hours(time),i.heroName(top),i.hours(topTime)))
        default: return nil
        }
    }

    /// Cardboard Support (the player's own joke): Support is the main role (45%+), yet damage beats healing.
    private static func cardboard(_ i:CardInputs)->(earned:Bool,main:Bool,damage:Int,healing:Int) {
        let support=i.share(.support)
        let main=support >= 0.45 && [CareerRank.Role.tank,.damage].allSatisfy { i.share($0) < support }
        // The support heroes' own damage and healing; a profile kept before Recall read them per hero never earns it.
        let supports={ (hero:String) in i.profile?.heroes[hero]?.role == .support }
        let damage=i.modes.reduce(0) { $0+($1.heroDamage ?? [:]).filter { supports($0.key) }.values.reduce(0,+) }
        let healing=i.modes.reduce(0) { $0+($1.heroHealing ?? [:]).filter { supports($0.key) }.values.reduce(0,+) }
        return (main && damage > healing && healing > 0,main,damage,healing)
    }
    /// The title for a role that has at least 45% of the time played.
    private static func roleMain(_ i:CardInputs)->String? {
        guard let role=[CareerRank.Role.tank,.damage,.support].max(by:{ i.share($0) < i.share($1) }),i.share(role) >= 0.45 else { return nil }
        switch role {
        case .tank: return L("Tank main")
        case .damage: return L("Damage main")
        case .support: return L("Support main")
        case .open: return nil
        }
    }
    /// A record beaten, in a few words ("53 elims").
    static func best(_ best:CareerBest)->String? {
        let value=best.value.formatted(.number.locale(CardWords.locale))
        switch best.key {
        case "eliminations_most_in_game": return L("{0} elims",value)
        case "all_damage_done_most_in_game","hero_damage_done_most_in_game": return L("{0} damage",value)
        case "healing_done_most_in_game": return L("{0} healing",value)
        case "final_blows_most_in_game": return L("{0} final blows",value)
        case "solo_kills_most_in_game": return L("{0} solo kills",value)
        case "kill_streak_best": return L("{0} kill streak",value)
        case "multikill_best": return L("{0}-kill multikill",value)
        default: return nil
        }
    }

    /// The picture a line brings when the picture follows Line 2.
    func picture(_ i:CardInputs,rank choice:RankChoice)->CardPicture {
        switch self {
        case .highlights:
            // Good news brings its own picture (the rank that moved, the hero of the milestone).
            if let piece=Self.highlight(i,rank:choice)?.piece,case .moment=piece { return piece.picture(i,rank:choice) }
            return i.lastHero == nil ? .playerIcon : .lastHero
        case .moment(let moment):
            switch moment {
            case .rankChange,.seasonHigh: return .rankEmblem
            case .newBest: return i.lastHero == nil ? .playerIcon : .lastHero
            case .milestone: return i.news?.milestone.map { .hero($0.hero) } ?? .playerIcon
            case .comeback: return .playerIcon
            case .newSeason: return .overwatch
            }
        case .rank: return .roleMain
        case .record(let period,_,_):
            if period == .last { return i.lastHero != nil ? .lastHero : .topHeroes }
            // The hero played most in the period.
            return i.profile == nil ? .playerIcon : i.history.session(period,now:i.now,calendar:i.calendar)?.hero.map { .hero($0) } ?? .topHeroes
        // The hero the words name: the most-played one for "top", never the top five's turn.
        case .hero(let key,_): return (key ?? i.topHeroes.first).map { .hero($0) } ?? .playerIcon
        case .best,.tonight,.title: return .playerIcon
        }
    }
}

extension CardPiece {
    /// The picture a line brings: a rank's news shows the emblem of the rank that moved, not the one chosen.
    func image(_ i:CardInputs,rank choice:RankChoice,turn:Int)->CardImage? {
        switch self {
        case .moment(.rankChange),.rank(.change): if let moved=i.news?.session.rank { return CardImage(url:moved.icon,hover:moved.label()) }
        case .moment(.seasonHigh): if let high=i.news?.seasonHigh { return CardImage(url:high.icon,hover:high.label()) }
        case .highlights: if let piece=Self.highlight(i,rank:choice)?.piece,case .moment=piece { return piece.image(i,rank:choice,turn:turn) }
        default: break
        }
        return picture(i,rank:choice).image(i,rank:choice,turn:turn)
    }
}

extension CardPicture {
    /// The image and its hover text, or nil when there is none (the card then shows Overwatch's own icon).
    func image(_ i:CardInputs,rank choice:RankChoice,turn:Int)->CardImage? {
        func hero(_ key:String)->CardImage? {
            guard let portrait=i.profile?.heroes[key]?.portrait else { return nil }
            return CardImage(url:portrait,hover:i.heroTime[key].map { L("{0} · {1} played",i.heroName(key),i.hours($0)) },hero:key)
        }
        switch self {
        case .playerIcon:
            guard let identity=i.profile?.identity,let avatar=identity.avatar else { return nil }
            return CardImage(url:avatar,hover:[identity.name,identity.title].compactMap { $0 }.joined(separator:" · "))
        case .lastHero:
            // The last session's hero, with what was done on all heroes (the totals don't say which hero did what).
            guard let last=i.lastHero,let portrait=last.portrait else { return nil }
            let hover=[L("Most played last session: {0}",last.name),i.last?.stats.map { L("All heroes: {0}",$0) }].compactMap { $0 }.joined(separator:" · ")
            return CardImage(url:portrait,hover:hover,hero:i.last?.hero)
        case .overwatch: return nil
        case .rankEmblem: return i.rank(choice).map { CardImage(url:$0.icon,hover:$0.label()) }
        case .recall: return CardImage(url:DiscordAssets.badge,hover:i.texts.badge)
        case .art(let art): return CardImage(url:DiscordAssets.art(art.file),hover:art.name)
        case .hero(let key): return hero(key)
        case .roleMain:
            // The most-played hero of the rank's role, or of any role without a rank.
            let role=i.rank(choice)?.role
            return i.topHeroes.first { role == nil || role == .open || i.profile?.heroes[$0]?.role == role }.flatMap(hero)
        case .topHeroes:
            let top=Array(i.topHeroes.prefix(5))
            return top.isEmpty ? nil : hero(top[turn%top.count])
        }
    }
}

extension String {
    var nilIfEmpty:String? { isEmpty ? nil : self }
}

extension BestLine {
    /// The profile's best for this line, over every mode (OverFast's keys; damage was hero damage on older profiles).
    func value(_ i:CardInputs)->Int? {
        let keys:[BestLine:[String]]=[.eliminations:["eliminations_most_in_game"],.damage:["all_damage_done_most_in_game","hero_damage_done_most_in_game"],
                                      .healing:["healing_done_most_in_game"],.killStreak:["kill_streak_best"],.multikill:["multikill_best"]]
        // The highest ever read: a new season's Competitive starts its own bests over.
        let all=i.profile?.bests ?? [:]
        guard let key=keys[self]?.first(where:{ key in (all[key] ?? 0) > 0 || i.modes.contains { ($0.bests[key] ?? 0) > 0 } }) else { return nil }
        return (i.modes.compactMap { $0.bests[key] }+[all[key]].compactMap { $0 }).max()
    }
}
