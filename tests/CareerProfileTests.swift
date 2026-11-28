import Foundation

// CareerProfile.swift: the BattleTag, OverFast's answers, the last session (with the log's match count),
// when the profile is looked up (and when it is not), and the profile on the Discord card. CareerHistory.swift:
// the runs and changes kept over time, their periods, nights and moments, and the history's file. OverFast is
// a fake that counts what is asked; the answers are shaped like OverFast's own (October 25), with made-up
// players.
// Build and run:
//   swiftc -O -target arm64-apple-macos26.5 -parse-as-library app/Sources/Brand.swift app/Sources/Localization.swift \
//     app/Sources/Discord/DiscordPresence.swift app/Sources/Discord/CareerProfile.swift app/Sources/Discord/CareerHistory.swift \
//     app/Sources/Discord/DiscordCardTemplate.swift app/Sources/Discord/DiscordCardCatalog.swift tests/CareerProfileTests.swift -o runtime/phase-3/career-profile-tests
//   runtime/phase-3/career-profile-tests

func json(_ value:Any)->Data { try! JSONSerialization.data(withJSONObject:value) }
func summary(updated:Int,season:Int=25,tank:(String,Int)?=("emerald",1),support:(String,Int)?=nil,open:(String,Int)?=("gold",2))->Data {
    var pc:[String:Any]=["season":season,"damage":NSNull()]
    for (role,rank) in [("tank",tank),("support",support),("open",open)] {
        pc[role]=rank.map { ["division":$0.0,"tier":$0.1,"rank_icon":"https://static.playoverwatch.com/rank/\($0.0).png","role_icon":"https://x/\(role).svg"] } ?? NSNull()
    }
    return json(["username":"Player","avatar":"https://x/avatar.png","namecard":"https://x/card.png","title":"Shieldbreaker",
                 "endorsement":["level":4,"frame":"https://x/4.svg"],"competitive":["pc":pc,"console":NSNull()],"last_updated_at":updated])
}
/// One mode's career stats, as OverFast nests them: categories of key/value pairs, all heroes and each hero.
struct Mode { var played=0,won=0,lost=0,elims=0,deaths=0,damage=0,healing=0;var bests:[String:Int]=[:];var heroes:[String:Int]=[:] }
func career(_ mode:Mode)->[String:Any] {
    func category(_ name:String,_ values:[String:Int])->[String:Any] { ["category":name,"stats":values.map { ["key":$0.key,"label":$0.key,"value":$0.value] }] }
    var stats:[String:Any]=["all-heroes":[category("game",["games_played":mode.played,"games_won":mode.won,"games_lost":mode.lost,"time_played":mode.heroes.values.reduce(0,+)]),
                                          category("combat",["eliminations":mode.elims,"deaths":mode.deaths,"hero_damage_done":mode.damage,"damage_done":mode.damage]),
                                          category("assists",["healing_done":mode.healing]),category("best",mode.bests)]]
    for (hero,time) in mode.heroes { stats[hero]=[category("game",["time_played":time,"games_played":1])] }
    return ["career_stats":stats,"heroes_comparisons":[:]]
}
func wholeProfile(competitive:Mode,quickplay:Mode)->Data {
    json(["summary":[:],"stats":["pc":["competitive":career(competitive),"quickplay":career(quickplay)],"console":NSNull()]])
}
let heroList=json([["key":"ana","name":"Ana","portrait":"https://x/ana.png","role":"support"],["key":"reinhardt","name":"Reinhardt","portrait":"https://x/rein.png","role":"tank"],
                   ["key":"juno","name":"Juno","portrait":"https://x/juno.png","role":"support"]])

/// OverFast, played by the test: answers by path, and remembers what was asked.
final class FakeOverFast {
    private let lock=NSLock()
    private var asked:[String]=[]
    var answers:[String:CareerProfile.Response?]=[:]
    var requests:[String] { lock.lock();defer { lock.unlock() };return asked }
    func fetch(_ url:URL)->CareerProfile.Response? {
        let key=url.path+(url.query.map { "?"+$0 } ?? "")
        lock.lock();asked.append(key);lock.unlock()
        return answers[key] ?? nil
    }
    func ok(_ body:Data)->CareerProfile.Response { CareerProfile.Response(status:200,headers:[:],body:body) }
}

@main struct CareerProfileTests {
    static func main() {
        battleTags();answers();lastSession();cardText();lookUps();anotherTag();history();heroHours();historyStore();keptRecords();switching();doubtfulReads();servers()
        print("PASS: BattleTags, OverFast's answers, the last session and its words, when the profile is looked up, the history and its file, the hours Recall counts, and the servers")
    }

    static func battleTags() {
        // Pasted with full-width letters, decomposed accents, a byte-order or direction mark: the same tag.
        precondition(BattleTag.playerID("\u{FEFF}ｐｙｘｅｅ#１１２４８\u{200E} ") == "pyxee-11248" && BattleTag.playerID("Ame\u{0301}lie#1234") == "Amélie-1234")
        precondition(BattleTag.playerID("Player#1234") == "Player-1234" && BattleTag.playerID(" Player#12345 ") == "Player-12345")
        precondition(BattleTag.playerID("Jöhn#11248") == "Jöhn-11248" && BattleTag.playerID("한국어이름#3123") == "한국어이름-3123")
        // Never sent: no #, a name too short or too long or starting with a digit, a short number, other characters.
        for bad in ["Player1234","Pl#1234","ThirteenChars#1234","1Player#1234","Player#12","Play er#1234","Player#12a4","Player-1234",""] {
            precondition(BattleTag.playerID(bad) == nil,bad)
        }
    }

    static func answers() {
        let read=OverFast.summary(summary(updated:1_792_941_113,support:("champion",3)))!
        precondition(read.updated == 1_792_941_113 && read.season == 25 && read.ranks.map(\.role) == [.tank,.support,.open])
        precondition(read.ranks[0] == CareerRank(role:.tank,division:"emerald",tier:1,icon:URL(string:"https://static.playoverwatch.com/rank/emerald.png")!))
        precondition(read.identity == CareerIdentity(name:"Player",title:"Shieldbreaker",endorsement:4,avatar:URL(string:"https://x/avatar.png"),namecard:URL(string:"https://x/card.png")))
        // A profile with no competitive rank, or a rank whose icon isn't https, shows none.
        precondition(OverFast.summary(json(["competitive":NSNull(),"last_updated_at":5]))!.ranks.isEmpty)
        var plain=try! JSONSerialization.jsonObject(with:summary(updated:5)) as! [String:Any]
        var competitive=plain["competitive"] as! [String:Any],pc=competitive["pc"] as! [String:Any],tank=pc["tank"] as! [String:Any]
        tank["rank_icon"]="http://example.com/rank.png";pc["tank"]=tank;competitive["pc"]=pc;plain["competitive"]=competitive;plain["avatar"]="http://x/a.png";plain["namecard"]="http://x/c.png"
        let insecure=OverFast.summary(json(plain))!
        precondition(insecure.ranks.map(\.role) == [.open] && insecure.identity?.avatar == nil && insecure.identity?.namecard == nil)
        precondition(OverFast.summary(json(["error":"Player not found"])) == nil && OverFast.summary(Data("<html>".utf8)) == nil)
        // Stats out of all reason (a self-hosted OverFast) are held to a most, so nothing adding them up overflows.
        let wild=OverFast.profile(wholeProfile(competitive:Mode(played:Int.max,elims:-5,heroes:["ana":Int.max]),quickplay:Mode(heroes:["juno":Int.max])))!
        precondition(wild["competitive"]?.heroes["ana"] == OverFast.most && wild["competitive"]?.games.played == OverFast.most && wild["competitive"]?.eliminations == 0)
        var counted=CareerHistory()
        for _ in 0..<3 { counted.count(wild,at:Date()) }
        precondition(counted.hours?.heroes == ["ana":OverFast.most,"juno":OverFast.most])
        // The whole profile: each mode's totals, records and heroes' time.
        let modes=OverFast.profile(wholeProfile(competitive:Mode(played:98,won:45,lost:52,elims:1760,deaths:588,damage:739031,healing:594755,bests:["eliminations_most_in_game":46],heroes:["ana":10615,"juno":12822]),
                                                quickplay:Mode(played:578,won:297,lost:281,heroes:["juno":42800])))!
        precondition(modes["competitive"] == ModeStats(games:Tally(played:98,won:45,lost:52),heroes:["ana":10615,"juno":12822],eliminations:1760,deaths:588,damage:739031,healing:594755,bests:["eliminations_most_in_game":46],
                                                       heroGames:["ana":Tally(played:1),"juno":Tally(played:1)]))
        precondition(modes["quickplay"]?.games == Tally(played:578,won:297,lost:281) && modes["quickplay"]?.heroes == ["juno":42800] && modes["quickplay"]?.heroGames == ["juno":Tally(played:1)])
        precondition(OverFast.profile(json(["summary":[:],"stats":NSNull()])) == nil)
        let heroes=OverFast.heroes(heroList)!
        precondition(heroes["ana"] == CareerHero(name:"Ana",portrait:URL(string:"https://x/ana.png"),role:.support) && heroes.count == 3)
        // OverFast's own wait for a player it couldn't find (flat, or inside "error"): its next check, its retry, or ten
        // minutes. A 404 that isn't OverFast's own says nothing.
        let now=Date(timeIntervalSince1970:1_800_000_000)
        precondition(OverFast.notFound(json(["error":"Player not found","next_check_at":1_800_005_400,"retry_after":5400]),now:now) == Date(timeIntervalSince1970:1_800_005_400))
        precondition(OverFast.notFound(json(["error":["error":"Player not found","retry_after":600,"next_check_at":1]]),now:now) == now.addingTimeInterval(600))
        precondition(OverFast.notFound(json(["error":"Player not found"]),now:now) == now.addingTimeInterval(600))
        precondition(OverFast.notFound(Data("<html>Not Found</html>".utf8),now:now) == nil && OverFast.notFound(json(["detail":"x"]),now:now) == nil)
        // Champion comes as "ultimate"; a division or tier Recall doesn't know is no rank; season 0 is none.
        func ranked(_ division:String,_ tier:Int,season:Int=25)->Data {
            json(["username":"P","last_updated_at":1,"competitive":["pc":["season":season,"tank":["division":division,"tier":tier,"rank_icon":"https://x/r.png"]]]])
        }
        precondition(OverFast.summary(ranked("ultimate",3))?.ranks.first?.division == "champion")
        precondition(OverFast.summary(ranked("mythic",3))?.ranks.isEmpty == true && OverFast.summary(ranked("gold",0))?.ranks.isEmpty == true)
        precondition(OverFast.summary(ranked("gold",2,season:0))?.season == nil)
        let oldChampion=try! JSONDecoder().decode(CareerRank.self,from:json(["role":"tank","division":"ultimate","tier":2,"icon":"https://x/r.png"]))
        precondition(oldChampion.division == "champion" && oldChampion.standing > CareerRank(role:.tank,division:"grandmaster",tier:1,icon:URL(string:"https://x")!).standing)
        // A private profile: OverFast answers with no time of its last update.
        precondition(OverFast.summary(json(["username":"P","last_updated_at":NSNull()]))?.updated == nil)
    }

    static func lastSession() {
        let heroes=OverFast.heroes(heroList)!
        let before=["competitive":ModeStats(games:Tally(played:96,won:46,lost:50),heroes:["ana":10000,"reinhardt":5000],eliminations:1700,deaths:580,damage:700000,healing:590000,
                                            bests:["eliminations_most_in_game":40,"healing_done_most_in_game":16000]),
                    "quickplay":ModeStats(games:Tally(played:500,won:250,lost:250),heroes:["juno":40000],eliminations:9000,deaths:3000,damage:900000,healing:800000)]
        var after=before
        // Nothing played: no session to tell, unless the log saw matches outside the two modes.
        precondition(LastSession.between(before,after) == nil && LastSession.between([:],after) == nil)
        precondition(LastSession.between(before,after,matches:2) == LastSession(other:2))
        // Two Competitive games on Reinhardt and a Quick Play one on Juno, a record beaten, and the log saw four matches.
        after["competitive"]=ModeStats(games:Tally(played:98,won:47,lost:51),heroes:["ana":10100,"reinhardt":6200],eliminations:1730,deaths:590,damage:715000,healing:590500,
                                       bests:["eliminations_most_in_game":40,"healing_done_most_in_game":17000])
        after["quickplay"]=ModeStats(games:Tally(played:501,won:251,lost:250),heroes:["juno":40900],eliminations:9012,deaths:3004,damage:901000,healing:806000)
        let session=LastSession.between(before,after,heroes:heroes,matches:4)!
        precondition(session.competitive == Tally(played:2,won:1,lost:1) && session.quickplay == Tally(played:1,won:1,lost:0) && session.other == 1 && session.played == 4)
        precondition(session.hero == "reinhardt" && session.role == .tank,"the hero played longest over both modes; the role of Competitive's")
        precondition(session.eliminations == 42 && session.deaths == 14 && session.damage == 16000 && session.healing == 6500)
        precondition(session.best == CareerBest(key:"healing_done_most_in_game",value:17000))
        // A log that saw fewer matches than the profile missed some: it tells nothing about other modes.
        precondition(LastSession.between(before,after,heroes:heroes,matches:2)?.other == nil && LastSession.between(before,after,heroes:heroes)?.other == nil)
        // The best move up, in divisions (tank up one over 6v6 down two); none when every role fell; a role with no
        // rank before moves nothing.
        let icon=URL(string:"https://x/r.png")!
        var moved=session
        moved.ranks(from:[CareerRank(role:.tank,division:"gold",tier:1,icon:icon),CareerRank(role:.open,division:"gold",tier:2,icon:icon)],
                    to:[CareerRank(role:.tank,division:"platinum",tier:5,icon:icon),CareerRank(role:.open,division:"gold",tier:4,icon:icon),CareerRank(role:.support,division:"gold",tier:1,icon:icon)])
        precondition(moved.rank?.role == .tank && moved.promoted)
        moved.ranks(from:[CareerRank(role:.open,division:"gold",tier:2,icon:icon)],to:[CareerRank(role:.open,division:"gold",tier:4,icon:icon)])
        precondition(moved.rank == nil && !moved.promoted)
        moved.ranks(from:[],to:[CareerRank(role:.open,division:"gold",tier:4,icon:icon)])
        precondition(moved.rank == nil)
        // The move that's most in divisions: Gold 3 to Gold 1 (two) over Gold 1 to Platinum 5 (one).
        moved.ranks(from:[CareerRank(role:.tank,division:"gold",tier:1,icon:icon),CareerRank(role:.support,division:"gold",tier:3,icon:icon)],
                    to:[CareerRank(role:.tank,division:"platinum",tier:5,icon:icon),CareerRank(role:.support,division:"gold",tier:1,icon:icon)])
        precondition(moved.rank?.role == .support && moved.promoted)
        // A new season starts Competitive's totals over: all of them are the session's, though its records are still
        // the old ones to beat. Fewer games than before tell it too.
        var reset=after
        reset["competitive"]=ModeStats(games:Tally(played:2,won:1,lost:1),heroes:["reinhardt":1200],eliminations:30,deaths:10,damage:15000,healing:500,
                                       bests:["eliminations_most_in_game":35,"healing_done_most_in_game":17000])
        for season in [LastSession.between(before,reset,heroes:heroes,newSeason:true)!,LastSession.between(before,reset,heroes:heroes)!] {
            precondition(season.competitive == Tally(played:2,won:1,lost:1) && season.hero == "reinhardt" && season.eliminations == 42 && season.deaths == 14,"\(season)")
            precondition(season.damage == 16000 && season.healing == 6500 && season.best == CareerBest(key:"healing_done_most_in_game",value:17000))
        }
        // A tier outside a division's five is no rank.
        let odd=json(["last_updated_at":1,"competitive":["pc":["season":25,"tank":["division":"gold","tier":Int.min,"rank_icon":"https://x/gold.png"]]]])
        precondition(OverFast.summary(odd)?.ranks.isEmpty == true)
    }

    static func cardText() {
        let icon=URL(string:"https://x/r.png")!
        let tank=CareerRank(role:.tank,division:"emerald",tier:1,icon:icon),support=CareerRank(role:.support,division:"gold",tier:3,icon:icon)
        precondition(tank.label() == "Tank: Emerald 1" && CareerRank(role:.open,division:"novel",tier:2,icon:icon).label() == "6v6: Novel 2")
        precondition(tank.standing > support.standing && CareerRank(role:.damage,division:"gold",tier:1,icon:icon).standing > support.standing)
        // The rank shown: the role of the last session's competitive games, or else the best.
        precondition(CareerCard(ranks:[support,tank]).rank == tank)
        precondition(CareerCard(ranks:[support,tank],last:LastSession(competitive:Tally(played:3,won:2,lost:1),role:.support)).rank == support)
        precondition(CareerCard(ranks:[support,tank],last:LastSession(quickplay:Tally(played:3,won:2,lost:1),role:.support)).rank == tank)
        precondition(CareerCard().rank == nil)
        // The session's words.
        precondition(LastSession(competitive:Tally(played:3,won:2,lost:1),quickplay:Tally(played:1,won:1),other:1).summary == "Comp 2–1 · QP 1–0 · 1 other")
        precondition(LastSession(competitive:Tally(played:1,won:0,lost:1)).summary == "Comp 0–1")
        precondition(LastSession(other:3).summary == "3 matches" && LastSession(other:1).summary == "1 match")
        precondition(LastSession(competitive:Tally(played:1),eliminations:38,deaths:9,damage:4000,healing:14032).stats == "38 eliminations, 9 deaths, 14,032 healing")
        precondition(LastSession(competitive:Tally(played:1),eliminations:20,deaths:5,damage:12500,healing:0).stats == "20 eliminations, 5 deaths, 12,500 damage")
        precondition(LastSession(other:1).stats == nil)
    }

    /// Waits for one lookup's answer.
    static func look(_ profile:CareerProfile,_ tag:String,_ now:Date)->(CareerProfile.Status,CareerCard?) {
        let done=DispatchSemaphore(value:0)
        var result:(CareerProfile.Status,CareerCard?)=(.none,nil)
        profile.lookUp(tag:tag,now:now) { result=($0,$1);done.signal() }
        done.wait()
        return result
    }
    /// Waits until the profile's queue has done what was asked before (a tag that isn't one asks nothing).
    static func settle(_ profile:CareerProfile) { _ = look(profile,"Player",Date()) }

    static func lookUps() {
        let suite="career-profile-tests-\(getpid())"
        let store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        let fake=FakeOverFast()
        let profile=CareerProfile(base:URL(string:"https://overfast.test")!,store:store,fetch:fake.fetch)
        let t0=Date(timeIntervalSince1970:1_800_000_000)
        func at(_ minutes:Double)->Date { t0.addingTimeInterval(minutes*60) }
        let summaryPath="/players/Player-1234/summary",whole="/players/Player-1234",heroes="/heroes"
        func answer(updated:Int,played:Int,won:Int,tank:(String,Int)=("emerald",1)) {
            fake.answers[summaryPath]=fake.ok(summary(updated:updated,tank:tank))
            fake.answers[whole]=fake.ok(wholeProfile(competitive:Mode(played:played,won:won,lost:played-won,elims:played*10,deaths:played*3,healing:played*1000,heroes:["reinhardt":played*600]),
                                                     quickplay:Mode(played:10,won:5,lost:5,heroes:["juno":6000])))
        }
        fake.answers[heroes]=fake.ok(heroList)

        // A tag that isn't one is never sent.
        precondition(look(profile,"Player",t0).0 == .invalidTag && fake.requests.isEmpty)
        // The first look: the summary, the hero list (for the pictures), and the whole profile to tell the next session
        // by. No session yet.
        answer(updated:100,played:20,won:10)
        var (status,card)=look(profile,"Player#1234",t0)
        precondition(fake.requests == [summaryPath,heroes,whole],"\(fake.requests)")
        precondition(card?.heroes["reinhardt"]?.name == "Reinhardt","the heroes' names and portraits from the first look")
        precondition(status == .found(card?.rank) && card?.rank?.role == .tank && card?.last == nil && card?.identity?.name == "Player")
        precondition(card?.page?.absoluteString == "https://overwatch.blizzard.com/en-us/career/Player-1234/" && profile.lastCode == 200)
        precondition(profile.history.current.hours == HeroHours(since:t0,heroes:["reinhardt":12000,"juno":6000],seenGames:["competitive":20,"quickplay":10],
                                                                seen:["competitive":["reinhardt":12000],"quickplay":["juno":6000]],roles:["tank":12000,"support":6000]),
                     "the hours are counted from the first look's totals, each in its hero's role")
        // Within ten minutes nothing is asked: the same answer, from what was kept.
        (status,card)=look(profile,"Player#1234",at(9))
        precondition(fake.requests.count == 3 && card?.rank?.role == .tank)
        // Later, an unchanged profile asks the summary only.
        (status,card)=look(profile,"Player#1234",at(11))
        precondition(fake.requests.count == 4 && card?.last == nil)
        precondition(profile.history.current.hours?.heroes == ["reinhardt":12000,"juno":6000],"an unchanged profile adds no hours")
        // The game ran twice meanwhile; the log saw 3 matches, then 1.
        profile.sessionEnded(PlayedRun(start:at(12),end:at(14),matches:3));profile.sessionEnded(PlayedRun(start:at(15),end:at(18),matches:1));settle(profile)
        precondition(profile.history.current.runs.map(\.matches) == [3,1],"every run goes into the history")
        // The profile changed (three Competitive games, up a tier): the session is told; the hero list is still fresh.
        answer(updated:200,played:23,won:12,tank:("diamond",5))
        (status,card)=look(profile,"Player#1234",at(22))
        precondition(Array(fake.requests.suffix(2)) == [summaryPath,whole] && fake.requests.count == 6,"\(fake.requests)")
        precondition(card?.last?.competitive == Tally(played:3,won:2,lost:1) && card?.last?.other == 1 && card?.last?.hero == "reinhardt",String(describing:card?.last))
        precondition(card?.hero?.name == "Reinhardt" && card?.last?.rank?.division == "diamond" && card?.last?.promoted == true)
        // The change goes into the history at the profile's own time (when the game closed), with the totals and heroes on the card.
        precondition(profile.history.current.changes.map(\.at) == [Date(timeIntervalSince1970:200)] && profile.history.current.changes[0].heroes == ["reinhardt":1800],"\(profile.history.current.changes)")
        precondition(profile.history.current.looked == at(22) && profile.history.current.seasonPeak.first?.division == "diamond")
        precondition(profile.history.current.changes[0].rankSteps == 1 && profile.history.current.changes[0].rankMoves == ["tank":1],"each role's move is kept with the change")
        precondition(card?.totals["competitive"]?.games.played == 23 && card?.heroes["reinhardt"]?.role == .tank)
        precondition(profile.history.current.hours?.heroes == ["reinhardt":13800,"juno":6000] && profile.history.current.hours?.since == t0,"a change adds its hours")
        // Kept across restarts of the app: a new profile on the same settings knows it, and asks nothing yet.
        let again=CareerProfile(base:URL(string:"https://overfast.test")!,store:store,fetch:fake.fetch)
        (status,card)=look(again,"Player#1234",at(25))
        precondition(fake.requests.count == 6 && card?.last?.played == 4)
        // A session the log wasn't read in (Normal): the next session's other modes can't be told. The hero list is kept a week.
        again.sessionEnded(PlayedRun(start:at(26),end:at(30),matches:nil));again.sessionEnded(PlayedRun(start:at(31),end:at(35),matches:5));settle(again)
        answer(updated:300,played:24,won:12)
        (status,card)=look(again,"Player#1234",at(40))
        precondition(fake.requests.count == 8 && card?.last?.competitive.played == 1 && card?.last?.other == nil)

        // A player found before that OverFast can't find now (Blizzard's page failing): its wait is kept, nothing is
        // asked before it, and the card keeps what it had.
        fake.answers[summaryPath]=CareerProfile.Response(status:404,headers:[:],body:json(["error":"Player not found","retry_after":5400]))
        (status,card)=look(profile,"Player#1234",at(60))
        precondition(status == .unavailable && fake.requests.count == 9 && card?.rank?.role == .tank)
        (status,card)=look(profile,"Player#1234",at(149))
        precondition(status == .unavailable && fake.requests.count == 9 && card?.rank?.role == .tank)
        // Too many asks (OverFast's or Blizzard's): its Retry-After, and nothing before it.
        fake.answers[summaryPath]=CareerProfile.Response(status:503,headers:["Retry-After":"3600"],body:Data())
        (status,_)=look(profile,"Player#1234",at(151))
        precondition(status == .unavailable && fake.requests.count == 10)
        (status,card)=look(profile,"Player#1234",at(210))
        precondition(status == .unavailable && fake.requests.count == 10 && card?.rank?.role == .tank,"what was kept still shows")
        // A server error, or no answer: asked again at the next lookup after ten minutes, never in a loop.
        fake.answers[summaryPath]=CareerProfile.Response(status:500,headers:[:],body:Data())
        (status,_)=look(profile,"Player#1234",at(212))
        precondition(status == .unavailable && fake.requests.count == 11 && profile.lastCode == 500)
        // No answer at all isn't a look: nothing counted as asked, so the next chance asks again.
        fake.answers[summaryPath]=nil
        (status,_)=look(profile,"Player#1234",at(223))
        precondition(status == .unreachable && fake.requests.count == 12 && profile.lastCode == 500)
        (status,_)=look(profile,"Player#1234",at(223.1))
        precondition(status == .unreachable && fake.requests.count == 13)
        // Another BattleTag found starts over: what was kept of the last player goes, this Mac's runs stay. A whole
        // profile that didn't come leaves the totals to be taken next time, and the summary still shows.
        fake.answers["/players/Other-5678/summary"]=fake.ok(summary(updated:300,tank:nil,open:nil))
        (status,card)=look(profile,"Other#5678",at(224))
        precondition(status == .found(nil) && card?.ranks.isEmpty == true && card?.last == nil && fake.requests.count == 16,"its own hero list: \(fake.requests.count)")
        precondition(profile.history.current.changes.isEmpty && profile.history.current.season == 25 && profile.history.current.runs.count == 2,"this Mac's runs stay")
        precondition(profile.history.current.hours == nil,"another player's hours start over")
        fake.answers["/players/Other-5678"]=fake.ok(wholeProfile(competitive:Mode(played:1,won:1),quickplay:Mode(played:1,won:1)))
        (status,card)=look(profile,"Other#5678",at(235))
        precondition(fake.requests.count == 18 && card?.last == nil,"the totals are taken now, there being none before")
        // A changed profile whose whole didn't come: its ranks wait for it, so the next look still tells the move.
        fake.answers["/players/Other-5678/summary"]=fake.ok(summary(updated:300,tank:("gold",1),open:nil))
        (status,card)=look(profile,"Other#5678",at(246))
        precondition(fake.requests.count == 19 && card?.rank?.division == "gold","an unchanged profile's ranks are taken")
        fake.answers["/players/Other-5678/summary"]=fake.ok(summary(updated:400,tank:("platinum",5),open:nil))
        fake.answers["/players/Other-5678"]=nil
        (status,card)=look(profile,"Other#5678",at(257))
        precondition(profile.history.current.looked == at(246),"ranks not taken: the rank's age isn't reset")
        precondition(fake.requests.count == 21 && card?.rank?.division == "gold",String(describing:card?.rank))
        fake.answers["/players/Other-5678"]=fake.ok(wholeProfile(competitive:Mode(played:2,won:2),quickplay:Mode(played:1,won:1)))
        (status,card)=look(profile,"Other#5678",at(268))
        precondition(fake.requests.count == 23 && card?.last?.rank?.division == "platinum" && card?.last?.promoted == true,String(describing:card?.last))
        // A Retry-After that isn't a time waits a day at most, and the record is kept.
        fake.answers["/players/Other-5678/summary"]=CareerProfile.Response(status:429,headers:["Retry-After":"inf"],body:Data())
        (status,_)=look(profile,"Other#5678",at(279))
        precondition(status == .unavailable && profile.lastCode == 429)
        (status,_)=look(profile,"Other#5678",at(279+24*60))
        precondition(fake.requests.count == 25,"asked again after a day")
        // The Mac's clock set back a day: its wait is two days off and its last look in the future, so it asks.
        fake.answers["/players/Other-5678/summary"]=fake.ok(summary(updated:400,tank:("platinum",5),open:nil))
        (status,_)=look(profile,"Other#5678",at(279))
        precondition(fake.requests.count == 26,"asked again: \(fake.requests.count)")
        // Erased as Recall quits: the profile and the history go at once, without waiting on the profile's queue.
        precondition(store.object(forKey:"careerProfile") != nil && profile.history.current != CareerHistory())
        profile.eraseNow()
        precondition(store.object(forKey:"careerProfile") == nil && profile.history.current == CareerHistory())
    }

    /// A BattleTag that isn't found (a typo) or a Remove forgets nothing; another player found does.
    static func anotherTag() {
        let suite="career-profile-tag-tests-\(getpid())"
        let store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        let fake=FakeOverFast()
        let profile=CareerProfile(base:URL(string:"https://overfast.test")!,store:store,fetch:fake.fetch)
        let t0=Date(timeIntervalSince1970:1_800_000_000)
        func at(_ minutes:Double)->Date { t0.addingTimeInterval(minutes*60) }
        fake.answers["/heroes"]=fake.ok(heroList)
        fake.answers["/players/Player-1234/summary"]=fake.ok(summary(updated:100))
        fake.answers["/players/Player-1234"]=fake.ok(wholeProfile(competitive:Mode(played:20,won:10,lost:10,heroes:["reinhardt":12000]),quickplay:Mode(played:10,won:5,lost:5)))
        _=look(profile,"Player#1234",at(0))
        let kept=profile.history.current
        precondition(kept.hours != nil && kept.season == 25 && fake.requests.count == 3)
        fake.answers["/players/Typo-1234/summary"]=CareerProfile.Response(status:404,headers:[:],body:json(["error":"Player not found"]))
        var (status,card)=look(profile,"Typo#1234",at(1))
        precondition(card == nil && profile.history.current == kept && profile.lastCode == 404,"a typo forgets nothing")
        if case .notFound=status {} else { preconditionFailure("\(status)") }
        // Other capitals are another player to OverFast: asked, and nothing is forgotten when it isn't found.
        fake.answers["/players/player-1234/summary"]=CareerProfile.Response(status:404,headers:[:],body:json(["error":"Player not found"]))
        (status,card)=look(profile,"player#1234",at(3))
        precondition(card == nil && fake.requests.count == 5 && profile.history.current == kept,"\(fake.requests)")
        // The right capitals again: what was kept, without asking again yet.
        (status,card)=look(profile,"Player#1234",at(5))
        precondition(card?.rank?.division == "emerald" && fake.requests.count == 5 && profile.history.current == kept,"\(fake.requests)")
        profile.sessionEnded(PlayedRun(start:at(6),end:at(9),matches:2));settle(profile)
        fake.answers["/players/Other-5678/summary"]=fake.ok(summary(updated:300,tank:nil,open:nil))
        (status,card)=look(profile,"Other#5678",at(12))
        precondition(status == .found(nil) && profile.history.current.hours == nil && profile.history.current.changes.isEmpty && profile.history.current.runs.count == 1)
        // The settings gone but the history kept (Put Back, defaults delete): another player's look starts it over.
        profile.history.update { $0.season=99;$0.seasonFollows=true }
        let suite2=suite+"-2",store2=UserDefaults(suiteName:suite2)!
        defer { store2.removePersistentDomain(forName:suite2) }
        let again=CareerProfile(base:URL(string:"https://overfast.test")!,store:store2,history:profile.history,fetch:fake.fetch)
        precondition(profile.history.current.player == "Other-5678")
        _=look(again,"Player#1234",at(13))
        precondition(again.history.current.player == "Player-1234" && again.history.current.season == 25 && !again.history.current.seasonFollows)
        // A run Recall quit during, taken up again from the game's start, takes the place of what was kept of it.
        profile.sessionEndedNow(PlayedRun(start:at(20),end:at(30),matches:1))
        profile.sessionEndedNow(PlayedRun(start:at(20),end:at(50),matches:3))
        precondition(profile.history.current.runs.map(\.matches) == [2,3])
        // A file kept before whole-second starts: a fraction apart is still the same game.
        profile.sessionEndedNow(PlayedRun(start:at(60).addingTimeInterval(0.4),end:at(70),matches:1))
        profile.sessionEndedNow(PlayedRun(start:at(60),end:at(80),matches:2))
        precondition(profile.history.current.runs.map(\.matches) == [2,3,2])
    }

    static func history() {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"UTC")!;calendar.firstWeekday=2
        /// October 2026, in UTC: the 26th is a Monday.
        func day(_ date:Int,_ hour:Double)->Date { calendar.date(from:DateComponents(year:2026,month:10,day:date))!.addingTimeInterval(hour*3600) }
        let icon=URL(string:"https://x/r.png")!
        func rank(_ role:CareerRank.Role,_ division:String,_ tier:Int)->CareerRank { CareerRank(role:role,division:division,tier:tier,icon:icon) }
        func change(_ at:Date,season:Int?=25,comp:Tally=Tally(),quick:Tally=Tally(),other:Int?=0,heroes:[String:Int]=[:])->ProfileChange {
            var made=ProfileChange(at:at,season:season,session:LastSession(competitive:comp,quickplay:quick,other:other),before:[:],after:[:])
            made.heroes=heroes
            return made
        }

        // Divisions moved: Gold 1 to Platinum 5 is one, Gold 3 to Gold 1 two, and down is negative.
        precondition(rank(.tank,"platinum",5).steps(from:rank(.tank,"gold",1)) == 1 && rank(.tank,"gold",1).steps(from:rank(.tank,"gold",3)) == 2)
        precondition(rank(.tank,"gold",1).steps(from:rank(.tank,"platinum",5)) == -1)
        // A change between two looks' totals: each hero's time, and the highest milestone passed (10, 25, 50, then every hundred).
        let before=["competitive":ModeStats(heroes:["juno":34200,"ana":342000]),"quickplay":ModeStats(heroes:["reinhardt":3600*24])]
        let after=["competitive":ModeStats(heroes:["juno":36720,"ana":363600]),"quickplay":ModeStats(heroes:["reinhardt":3600*51])]
        // The milestone comes from Recall's own count of hours, which a new season never takes back.
        let made=ProfileChange(at:day(26,22),season:25,session:LastSession(),before:before,after:after)
        precondition(made.heroes == ["juno":2520,"ana":21600,"reinhardt":97200],"\(made)")
        precondition(ProfileChange.milestone(from:["juno":34200,"ana":342000,"reinhardt":3600*24],to:["juno":36720,"ana":363600,"reinhardt":3600*51]) == ProfileChange.Milestone(hero:"ana",hours:100))
        precondition(ProfileChange.milestone(from:["reinhardt":3600*24],to:["reinhardt":3600*51])?.hours == 50)
        precondition(ProfileChange.milestone(from:["ana":3600*60],to:["ana":3600*60]) == nil && [10,25,50,100,300].allSatisfy(ProfileChange.isMilestone) && !ProfileChange.isMilestone(150))

        // Which runs a change covers: those overlapping the time since the change before, so a run the profile changed
        // during (after a match, before the game closed) counts for it, and only runs that started after the last change
        // wait for the next look.
        var runsAndChanges=CareerHistory()
        runsAndChanges.ran(PlayedRun(start:day(25,12),end:day(25,13.2),matches:2))
        runsAndChanges.ran(PlayedRun(start:day(25,18),end:day(25,19),matches:3))
        runsAndChanges.ran(PlayedRun(start:day(25,20),end:day(25,20.5),matches:0))
        precondition(runsAndChanges.waiting.count == 3,"no change told yet: every run waits")
        runsAndChanges.looked(at:day(25,21),season:25,ranks:[],change:change(day(25,13)))
        precondition(runsAndChanges.runs(for:runsAndChanges.changes[0]).map(\.matches) == [2],"the run the profile changed during is its")
        precondition(runsAndChanges.waiting.map(\.matches) == [3,0],"the runs after it wait")
        runsAndChanges.looked(at:day(25,22),season:25,ranks:[],change:change(day(25,19.5)))
        // The first run went on after the first change: it counts for both.
        precondition(runsAndChanges.runs(for:runsAndChanges.changes[1]).map(\.matches) == [2,3] && runsAndChanges.waiting.map(\.matches) == [0])

        // The season's first and best ranks, and a change that set a new best of the season.
        var history=CareerHistory()
        history.looked(at:day(20,18),season:25,ranks:[rank(.tank,"gold",2)],change:nil)
        precondition(history.first(.tank)?.tier == 2 && history.peak(.tank)?.tier == 2 && !history.seasonFollows && history.seasonSeen == day(20,18))
        history.looked(at:day(24,23),season:25,ranks:[rank(.tank,"platinum",5),rank(.support,"gold",4)],change:change(day(24,21),comp:Tally(played:3,won:3)))
        precondition(history.changes.last?.seasonHigh == rank(.tank,"platinum",5) && history.peak(.tank)?.division == "platinum" && history.first(.support)?.tier == 4)
        history.looked(at:day(26,23),season:25,ranks:[rank(.tank,"gold",1),rank(.support,"gold",4)],change:change(day(26,22),comp:Tally(played:3,won:2,lost:1),heroes:["juno":3000,"ana":600]))
        precondition(history.changes.last?.seasonHigh == nil && history.peak(.tank)?.division == "platinum" && history.first(.tank)?.division == "gold")
        // A Monday night session first seen on Wednesday is Monday's: the profile's time dates it, not the look.
        history.looked(at:day(28,19),season:25,ranks:[rank(.tank,"gold",1)],change:change(day(28,13),comp:Tally(played:1,won:1),quick:Tally(played:2,won:1,lost:1),other:nil,heroes:["ana":2000]))

        // The periods (now: Wednesday the 28th, 20:00; the week starts on Monday): the last, today, this week, this season.
        let now=day(28,20)
        precondition(history.session(.last,now:now,calendar:calendar)?.competitive == Tally(played:1,won:1))
        precondition(history.session(.today,now:now,calendar:calendar)?.quickplay == Tally(played:2,won:1,lost:1))
        precondition(history.session(.today,now:day(26,12),calendar:calendar)?.competitive == Tally(played:3,won:2,lost:1),"Monday's, seen on Wednesday")
        let week=history.session(.week,now:now,calendar:calendar)!
        precondition(week.competitive == Tally(played:4,won:3,lost:1) && week.quickplay == Tally(played:2,won:1,lost:1) && week.other == nil,"\(week)")
        precondition(week.hero == "juno","the hero played longest over the week's changes")
        precondition(history.session(.season,now:now,calendar:calendar)?.competitive == Tally(played:7,won:6,lost:1))
        precondition(history.session(.today,now:day(29,12),calendar:calendar) == nil && history.session(.all,now:now,calendar:calendar) == nil)

        // A new season: the climb starts over, and its first look is news.
        var next=history
        next.looked(at:day(30,18),season:26,ranks:[rank(.tank,"silver",3)],change:change(day(30,17),season:26,comp:Tally(played:1,won:1)))
        precondition(next.seasonFollows && next.first(.tank)?.division == "silver" && next.changes.last?.seasonHigh == nil)
        // The season that ended is kept as it was: its first and best ranks, from when Recall saw it to the turn.
        let ended=next.lastSeason
        precondition(ended?.season == 25 && ended?.first.first?.division == "gold" && ended?.peak.contains { $0.division == "platinum" } == true && ended?.from == day(20,18) && ended?.to == day(30,18))
        let reread=try! JSONDecoder().decode(CareerHistory.self,from:JSONEncoder().encode(next))
        precondition(reread.lastSeason == ended && history.lastSeason == nil)
        precondition(next.session(.season,now:day(30,20),calendar:calendar)?.competitive == Tally(played:1,won:1))
        precondition(next.newSeason(before:day(30,20)) == 26 && history.newSeason(before:now) == nil,"the first season Recall sees is no news")
        next.ran(PlayedRun(start:day(30,19),end:day(30,21),matches:2))
        precondition(next.newSeason(before:day(31,20)) == nil,"once a game has been played in it")
        var during=history;during.looked(at:day(30,18),season:26,ranks:[],change:nil)
        during.ran(PlayedRun(start:day(30,17.9),end:day(30,21),matches:2))
        precondition(during.newSeason(before:day(31,20)) == nil,"the run the look was made in, as the game opened, is a game in it")
        // A look with no season (no competitive ranks yet) keeps the season and its climb.
        var unplaced=next;unplaced.looked(at:day(31,12),season:nil,ranks:[],change:nil)
        precondition(unplaced.season == 26 && unplaced.first(.tank)?.division == "silver" && unplaced.seasonFollows)

        // Tonight: nights in a row (a game at half past midnight is the night before's), time this week, a comeback.
        var runs=CareerHistory()
        for (start,end) in [(day(19,20),day(19,23)),(day(26,21),day(26,23)),(day(27,23.5),day(28,1)),(day(29,0.5),day(29,2))] { runs.ran(PlayedRun(start:start,end:end,matches:2)) }
        precondition(runs.nightsInARow(now:day(29,21),playing:true,calendar:calendar) == 4,"Monday, Tuesday, Wednesday (at 00:30) and tonight")
        precondition(runs.nightsInARow(now:day(29,21),playing:false,calendar:calendar) == 0 && runs.nightsInARow(now:day(29,1),playing:true,calendar:calendar) == 3)
        precondition(runs.playedThisWeek(now:day(29,21),current:day(29,20),calendar:calendar) == 6*3600,"2h + 1.5h + 1.5h this week, and the hour going on")
        // A clock change at midnight (Santiago, 6 September 2026: midnight is 01:00) doesn't break the nights.
        var santiago=Calendar(identifier:.gregorian);santiago.timeZone=TimeZone(identifier:"America/Santiago")!
        func chile(_ date:Int,_ hour:Int)->Date { santiago.date(from:DateComponents(year:2026,month:9,day:date,hour:hour))! }
        var dst=CareerHistory()
        for date in 3...6 { dst.ran(PlayedRun(start:chile(date,21),end:chile(date,23),matches:1)) }
        precondition(dst.nightsInARow(now:chile(7,21),playing:true,calendar:santiago) == 5,"\(dst.nightsInARow(now:chile(7,21),playing:true,calendar:santiago))")
        // Asleep isn't play: a run's sleep, and this run's so far, come off the week.
        var dozed=CareerHistory();dozed.ran(PlayedRun(start:day(26,20),end:day(27,8),matches:2,slept:10*3600))
        precondition(dozed.playedThisWeek(now:day(27,21),current:day(27,20),sleeping:600,calendar:calendar) == 2*3600+3000)
        // A change covering two nights of this Mac's play (looks missed meanwhile) is several sessions: never the
        // last one, today's, the week's or news.
        var lump=CareerHistory()
        lump.ran(PlayedRun(start:day(26,20),end:day(26,22),matches:3));lump.ran(PlayedRun(start:day(27,20),end:day(27,22),matches:3))
        var both=ProfileChange(at:day(27,22),season:25,session:LastSession(competitive:Tally(played:6,won:3,lost:3)),before:[:],after:[:]);both.since=day(25,12)
        lump.changes=[both]
        precondition(lump.session(.last,now:day(28,20),calendar:calendar) == nil && lump.session(.week,now:day(28,20),calendar:calendar) == nil && lump.news(before:day(28,19)) == nil)
        both.since=day(27,12);lump.changes=[both]
        precondition(lump.session(.last,now:day(28,20),calendar:calendar)?.competitive.played == 6)
        // Runs of the same night less than ten minutes apart are one night's play.
        var night=CareerHistory()
        night.ran(PlayedRun(start:day(28,18),end:day(28,19),matches:2));night.ran(PlayedRun(start:day(28,19.1),end:day(28,19.5),matches:1))
        precondition(night.joined(before:day(28,19.6),calendar:calendar) == 3 && night.joined(before:day(28,20),calendar:calendar) == 0)
        var cut=runs;cut.ran(PlayedRun(start:day(29,20),end:day(29,20.5),matches:1))
        precondition(cut.playedThisWeek(now:day(29,21),current:day(29,20),calendar:calendar) == 6*3600,"the part kept when Recall quit during this game counts once")
        var span=CareerHistory();span.ran(PlayedRun(start:day(25,23),end:day(26,1),matches:1))
        precondition(span.playedThisWeek(now:day(26,12),current:nil,calendar:calendar) == 3600,"only the part inside this week")
        precondition(runs.away(before:day(23,20)) == 4*24*3600-3*3600 && runs.away(before:day(27,20)) == nil && CareerHistory().away(before:now) == nil)
        // A change is news until a game opens after the one it came from on a later night: a crash or a relaunch the
        // same night keeps it.
        var news=history
        precondition(news.news(before:day(28,21),calendar:calendar)?.at == day(28,13))
        news.ran(PlayedRun(start:day(28,14),end:day(28,16),matches:1))
        precondition(news.news(before:day(28,21),calendar:calendar) != nil && news.news(before:day(28,14),calendar:calendar) != nil)
        news.ran(PlayedRun(start:day(29,20),end:day(29,21),matches:1))
        precondition(news.news(before:day(29,22),calendar:calendar) == nil,"a game on a later night ends it")
        // No streak: the nights played of the last seven.
        var spread=CareerHistory()
        for d in [22,24,26] { spread.ran(PlayedRun(start:day(d,20),end:day(d,21),matches:1)) }
        precondition(spread.nightsPlayed(of:7,now:day(28,20),playing:true,calendar:calendar) == 4 && spread.nightsPlayed(of:7,now:day(28,20),playing:false,calendar:calendar) == 3)
        // The rank is not shown once matches were played after a look more than two days old; a break with none keeps it.
        var stale=CareerHistory();stale.looked(at:day(20,12),season:25,ranks:[rank(.tank,"gold",1)],change:nil)
        precondition(!stale.rankStale(now:day(23,12)))
        stale.ran(PlayedRun(start:day(21,20),end:day(21,21),matches:0))
        precondition(!stale.rankStale(now:day(23,12)),"a run with no match changes nothing")
        stale.ran(PlayedRun(start:day(22,20),end:day(22,21),matches:3))
        precondition(stale.rankStale(now:day(23,12)) && !stale.rankStale(now:day(22,11)))
        var opened=CareerHistory();opened.looked(at:day(20,12),season:25,ranks:[rank(.tank,"gold",1)],change:nil)
        opened.ran(PlayedRun(start:day(20,11.9),end:day(20,14),matches:3))
        precondition(opened.rankStale(now:day(23,12)),"the matches of the run the look was made in came after it")
        // Another BattleTag: the profile's history goes, this Mac's runs stay. Old runs and changes leave after about a year.
        var other=history;other.ran(PlayedRun(start:day(1,20),end:day(1,21),matches:1));other.forgetProfile()
        precondition(other.changes.isEmpty && other.seasonPeak.isEmpty && other.looked == nil && other.runs.count == 1)
        var year=CareerHistory()
        year.ran(PlayedRun(start:day(1,20).addingTimeInterval(-CareerHistory.kept-3600),end:day(1,21).addingTimeInterval(-CareerHistory.kept-3600),matches:1))
        year.ran(PlayedRun(start:day(1,20),end:day(1,21),matches:1))
        precondition(year.runs.count == 1)
        // A date far ahead (the Mac's clock was wrong) clears nothing.
        year.ran(PlayedRun(start:Date().addingTimeInterval(800*86_400),end:Date().addingTimeInterval(800*86_400+3600),matches:1))
        precondition(year.runs.count == 2)
        // Export: everything kept, oldest first, a run's times and matches, a change's games, hero, rank and divisions.
        var export=CareerHistory()
        var moved=change(day(27,22),comp:Tally(played:3,won:2,lost:1),quick:Tally(played:2,won:1,lost:1),other:1)
        moved.session.hero="ana";moved.session.rank=rank(.support,"gold",1);moved.rankSteps=2
        export.changes=[moved]
        export.ran(PlayedRun(start:day(27,20),end:day(27,21.5),matches:5));export.ran(PlayedRun(start:day(28,20),end:day(28,21),matches:nil))
        let csv=export.csv(heroes:["ana":CareerHero(name:"Ana, \"the\" sniper",portrait:nil,role:.support)],timeZone:calendar.timeZone)
        precondition(csv.hasPrefix("\u{FEFF}") && csv.hasSuffix("\r\n"))
        let rows=csv.dropFirst().split(separator:"\r\n").map(String.init)
        precondition(rows == ["Started,Ended,What,Matches,Competitive,Quick Play,Hero,Rank,Divisions",
                              "2026-10-27 20:00,2026-10-27 21:30,Played on this Mac,5,,,,,",
                              ",2026-10-27 22:00,Profile change,6,2–1,1–1,\"Ana, \"\"the\"\" sniper\",Support: Gold 1,+2",
                              "2026-10-28 20:00,2026-10-28 21:00,Played on this Mac,,,,,,"],"\(rows)")
        // A name that a spreadsheet would work out as a formula is kept as text.
        let formula=export.csv(heroes:["ana":CareerHero(name:"=HYPERLINK(\"x\")",portrait:nil,role:.support)],timeZone:calendar.timeZone)
        precondition(formula.contains(",\"'=HYPERLINK(\"\"x\"\")\",Support: Gold 1,"),formula)
    }

    /// The hours Recall counts: from the first look's totals, each look's gains mode by mode, and a mode that started
    /// over (Competitive at a new season) all new. What an older Recall kept still reads, without them.
    static func heroHours() {
        func modes(comp:(Int,[String:Int]),quick:(Int,[String:Int]))->[String:ModeStats] {
            ["competitive":ModeStats(games:Tally(played:comp.0),heroes:comp.1),"quickplay":ModeStats(games:Tally(played:quick.0),heroes:quick.1)]
        }
        let t0=Date(timeIntervalSince1970:1_800_000_000)
        var history=CareerHistory()
        history.count([:],at:t0)
        precondition(history.hours == nil,"no totals, nothing counted")
        history.count(modes(comp:(40,["ana":36000,"juno":7200]),quick:(10,["juno":3600])),at:t0)
        precondition(history.hours?.heroes == ["ana":36000,"juno":10800] && history.hours?.since == t0)
        // The same totals again add nothing; more of them add the difference.
        history.count(modes(comp:(40,["ana":36000,"juno":7200]),quick:(10,["juno":3600])),at:t0.addingTimeInterval(60))
        history.count(modes(comp:(42,["ana":37800,"juno":7200]),quick:(12,["juno":4200,"kiriko":900])),at:t0.addingTimeInterval(120))
        precondition(history.hours?.heroes == ["ana":37800,"juno":11400,"kiriko":900] && history.hours?.since == t0,"\(String(describing:history.hours))")
        // A new season: Competitive starts over, and what it has is all new; last season's hours stay.
        history.count(modes(comp:(2,["juno":1200]),quick:(12,["juno":4200,"kiriko":900])),at:t0.addingTimeInterval(180),turned:true)
        precondition(history.hours?.heroes == ["ana":37800,"juno":12600,"kiriko":900],"\(String(describing:history.hours))")
        history.count(modes(comp:(5,["juno":1500,"ana":600]),quick:(12,["juno":4200,"kiriko":900])),at:t0.addingTimeInterval(240))
        precondition(history.hours?.heroes == ["ana":38400,"juno":12900,"kiriko":900],"a hero back in the new season counts from nothing")
        // A read taken as the new starting point (it looked wrong twice) counts nothing; the next counts from it.
        history.count(modes(comp:(3,["juno":900]),quick:(9,["juno":3000])),at:t0.addingTimeInterval(300),baseline:true)
        history.count(modes(comp:(4,["juno":1200]),quick:(9,["juno":3000])),at:t0.addingTimeInterval(360))
        precondition(history.hours?.heroes == ["ana":38400,"juno":13200,"kiriko":900],"\(String(describing:history.hours))")
        // Each gain in the role its hero has when it's counted: a hero moved to another role later keeps its hours.
        var roles=CareerHistory()
        roles.count(modes(comp:(1,["sombra":3600]),quick:(0,[:])),at:t0) { _ in .damage }
        roles.count(modes(comp:(2,["sombra":7200]),quick:(0,[:])),at:t0) { _ in .support }
        precondition(roles.hours?.roles == ["damage":3600,"support":3600])
        // A history from before the hours were kept reads as it was, with none.
        let older=#"{"runs":[{"start":"2027-01-15T08:00:00Z","end":"2027-01-15T09:00:00Z","matches":4}],"changes":[],"seasonFollows":false,"seasonFirst":[],"seasonPeak":[],"looked":"2027-01-15T09:00:00Z"}"#
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let read=try! decoder.decode(CareerHistory.self,from:Data(older.utf8))
        precondition(read.runs.count == 1 && read.hours == nil)
        // An entry that can't be read is left out, not the whole history; what the file doesn't have is empty.
        let damaged=#"{"runs":[{"start":"2027-01-15T08:00:00Z","end":"2027-01-15T09:00:00Z","matches":4},{"start":"not a date"}],"changes":[{"at":5}],"looked":"2027-01-15T09:00:00Z"}"#
        let partly=try! decoder.decode(CareerHistory.self,from:Data(damaged.utf8))
        precondition(partly.runs.count == 1 && partly.changes.isEmpty && partly.looked != nil && !partly.seasonFollows)
        // Forgetting the profile forgets its hours.
        history.forgetProfile()
        precondition(history.hours == nil)
    }

    static func historyStore() {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("career-history-tests-\(getpid())")
        defer { try? FileManager.default.removeItem(at:folder) }
        let file=folder.appendingPathComponent("org.overwatch2mac.launcher/career-history.json")
        let start=Date(timeIntervalSince1970:1_800_000_000)
        let store=CareerHistoryStore(url:file)
        precondition(store.current == CareerHistory() && !FileManager.default.fileExists(atPath:file.path))
        store.update { $0.ran(PlayedRun(start:start,end:start.addingTimeInterval(3600),matches:4)) }
        // Written as plain JSON (dates as text), and read back by the next launch.
        let text=String(decoding:try! Data(contentsOf:file),as:UTF8.self)
        precondition(text.contains("2027-01-15T08:00:00Z"),text)
        precondition(CareerHistoryStore(url:file).current.runs == [PlayedRun(start:start,end:start.addingTimeInterval(3600),matches:4)])
        // A file that can't be read at all is a fresh start, and is set aside rather than written over.
        try! Data("not json".utf8).write(to:file)
        let fresh=CareerHistoryStore(url:file)
        precondition(fresh.current == CareerHistory())
        let aside=folder.appendingPathComponent("org.overwatch2mac.launcher/career-history.unreadable.json")
        precondition((try? String(contentsOf:aside,encoding:.utf8)) == "not json")
        fresh.erase()
        precondition(!FileManager.default.fileExists(atPath:aside.path),"Erase takes it too")
        // Erase: the file goes.
        store.erase()
        precondition(store.current == CareerHistory() && !FileManager.default.fileExists(atPath:file.path))
        func write(_ text:String) { try! Data(text.utf8).write(to:file,options:.atomic) }
        func onDisk()->String { (try? String(contentsOf:file,encoding:.utf8)) ?? "" }
        // Some entries this Recall can't read: the rest is kept, and the file is copied before it's first written.
        let partly=#"{"runs":[{"start":"2027-01-15T08:00:00Z","end":"2027-01-15T09:00:00Z","matches":2},{"start":"soon"}],"later":true}"#
        write(partly)
        let some=CareerHistoryStore(url:file)
        precondition(some.current.runs.count == 1)
        some.update { $0.looked=start }
        let launcher=file.deletingLastPathComponent()
        let copies=try! FileManager.default.contentsOfDirectory(atPath:launcher.path).filter { $0.hasPrefix("career-history.kept-") }
        precondition(copies.count == 1 && (try? String(contentsOf:launcher.appendingPathComponent(copies[0]),encoding:.utf8)) == partly,"\(copies)")
        // Changed on disk (Put Back): read again. Gone (the Trash): a fresh start, not the old history written back.
        write(#"{"runs":[]}"#)
        precondition(some.current.runs.isEmpty && some.current.looked == nil)
        try! FileManager.default.removeItem(at:file)
        precondition(some.current == CareerHistory())
        // A newer Recall's file: read, and never written over.
        write(#"{"v":2,"runs":[],"season":30}"#)
        let newer=CareerHistoryStore(url:file)
        newer.update { $0.looked=start }
        precondition(newer.current.season == 30 && newer.current.looked == start && onDisk() == #"{"v":2,"runs":[],"season":30}"#)
        // There but unreadable (permissions): nothing is kept in memory or written over it.
        write(#"{"runs":[],"season":31}"#)
        try! FileManager.default.setAttributes([.posixPermissions:0o000],ofItemAtPath:file.path)
        let locked=CareerHistoryStore(url:file)
        locked.update { $0.looked=start }
        try! FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path)
        precondition(onDisk() == #"{"runs":[],"season":31}"# && locked.current.season == 31,"read once it can be")
        // Uninstall: let go, and nothing more is written.
        locked.close()
        locked.update { $0.season=99 };locked.erase()
        precondition(locked.current == CareerHistory() && onDisk() == #"{"runs":[],"season":31}"#)
        // In memory only (the tests, a preview): nothing is written.
        let memory=CareerHistoryStore(url:nil)
        memory.update { $0.ran(PlayedRun(start:start,end:start,matches:nil)) }
        precondition(memory.current.runs.count == 1)
    }

    /// What an earlier or later Recall kept of the profile still reads: a field it lacks or can't be read takes its
    /// default, one it doesn't know is skipped.
    static func keptRecords() {
        let suite="career-profile-kept-\(getpid())"
        let store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        let fake=FakeOverFast()
        let profile=CareerProfile(base:URL(string:"https://overfast.test")!,store:store,fetch:fake.fetch)
        let kept=#"{"player":"Player-1234","seen":true,"updated":100,"modes":"not this","ranks":[],"later":{"x":1},"asked":800000000}"#
        store.set(Data(kept.utf8),forKey:"careerProfile")
        let done=DispatchSemaphore(value:0)
        var status:CareerProfile.Status?
        profile.kept(tag:"Player#1234") { found,_,_ in status=found;done.signal() }
        done.wait()
        precondition(status == .found(nil) && fake.requests.isEmpty,"\(String(describing:status))")
    }

    /// Another player found sets the first one's history aside, and switching back brings it back at once. One
    /// pace for every BattleTag. A private profile, a server that isn't one, and the look after the game closes.
    static func switching() {
        let suite="career-profile-switch-\(getpid())"
        let store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        let fake=FakeOverFast()
        let profile=CareerProfile(base:URL(string:"https://overfast.test")!,store:store,fetch:fake.fetch)
        let t0=Date(timeIntervalSince1970:1_800_000_000)
        func at(_ minutes:Double)->Date { t0.addingTimeInterval(minutes*60) }
        fake.answers["/heroes"]=fake.ok(heroList)
        for (id,played) in [("Main-1234",20),("Alt-5678",3)] {
            fake.answers["/players/\(id)/summary"]=fake.ok(summary(updated:100))
            fake.answers["/players/\(id)"]=fake.ok(wholeProfile(competitive:Mode(played:played,won:1,heroes:["reinhardt":played*600]),quickplay:Mode(played:1,won:1)))
        }
        _=look(profile,"Main#1234",at(0))
        profile.history.update { $0.seasonFollows=true }
        let mains=profile.history.current
        precondition(mains.player == "Main-1234" && mains.hours?.heroes["reinhardt"] == 12000)
        // The alt: found, so the main's part is set aside (the runs stay).
        profile.sessionEnded(PlayedRun(start:at(1),end:at(2),matches:1))
        _=look(profile,"Alt#5678",at(3))
        precondition(profile.history.current.player == "Alt-5678" && profile.history.current.hours?.heroes["reinhardt"] == 1800 && profile.history.current.runs.count == 1)
        precondition(profile.history.current.parked?["Main-1234"]?.hours == mains.hours)
        // Back to the main within ten minutes: everything back, nothing asked.
        let asked=fake.requests.count
        let (status,card)=look(profile,"Main#1234",at(5))
        precondition(status == .found(card?.rank) && fake.requests.count == asked && card?.identity?.name == "Player")
        precondition(profile.history.current.player == "Main-1234" && profile.history.current.hours == mains.hours && profile.history.current.seasonFollows)
        precondition(profile.history.current.parked?["Alt-5678"] != nil && profile.history.current.runs.count == 1)
        // One pace for every BattleTag: two seconds apart, six in ten minutes; typing new ones doesn't get round it.
        for n in 0..<7 { fake.answers["/players/New\(n)-1234/summary"]=CareerProfile.Response(status:404,headers:[:],body:json(["error":"Player not found"])) }
        var statuses:[CareerProfile.Status]=[]
        for n in 0..<7 { statuses.append(look(profile,"New\(n)#1234",at(20+Double(n))).0) }
        precondition(statuses.prefix(6).allSatisfy { if case .notFound=$0 { return true } else { return false } } && statuses[6] == .busy(until:at(30)),"\(statuses)")
        if case .busy=look(profile,"New6#1234",at(20.01)).0 {} else { preconditionFailure("two seconds apart") }
        if case .busy=look(profile,"New5#1234",at(26.5)).0 { preconditionFailure("a BattleTag OverFast just couldn't find waits for its own answer, not the pace") }
        let paced=look(profile,"Main#1234",at(29)).0
        if case .busy=paced {} else { preconditionFailure("still the pace: \(paced)") }
        if case .busy=look(profile,"Main#1234",at(31)).0 { preconditionFailure("the pace is over") }
        // A private profile: OverFast answers without the time of its last update. Nothing of it shows.
        fake.answers["/players/Main-1234/summary"]=fake.ok(json(["username":"Player","last_updated_at":NSNull(),"competitive":NSNull()]))
        let (hidden,shown)=look(profile,"Main#1234",at(45))
        if case .notPublic=hidden {} else { preconditionFailure("\(hidden)") }
        precondition(shown == nil)
        // The game closed after the profile's last change: the look says when OverFast's copy is due.
        fake.answers["/players/Main-1234/summary"]=CareerProfile.Response(status:200,headers:["Age":"600"],body:summary(updated:Int(at(50).timeIntervalSince1970)))
        profile.sessionEnded(PlayedRun(start:at(52),end:at(60),matches:2))
        let done=DispatchSemaphore(value:0)
        var catchUp:Date?
        profile.lookUp(tag:"Main#1234",now:at(72)) { _,_ in catchUp=profile.catchUp;done.signal() }
        done.wait()
        precondition(catchUp == at(72).addingTimeInterval(1800-600+30),"\(String(describing:catchUp))")
        // A server support set that isn't one: nothing is asked at all.
        let none=CareerProfile(base:nil,store:store,fetch:fake.fetch)
        let before=fake.requests.count
        precondition(look(none,"Main#1234",at(200)).0 == .unavailable && fake.requests.count == before)
    }

    /// A whole profile that looks wrong is kept back once, and the same again becomes the starting point; bests are
    /// the highest ever read, so a new season's own aren't news.
    static func doubtfulReads() {
        let suite="career-profile-doubt-\(getpid())"
        let store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        let fake=FakeOverFast()
        let profile=CareerProfile(base:URL(string:"https://overfast.test")!,store:store,fetch:fake.fetch)
        let t0=Date(timeIntervalSince1970:1_800_000_000)
        func at(_ minutes:Double)->Date { t0.addingTimeInterval(minutes*60) }
        fake.answers["/heroes"]=fake.ok(heroList)
        func answer(_ updated:Int,season:Int=25,comp:Mode,quick:Mode?) {
            fake.answers["/players/Player-1234/summary"]=fake.ok(summary(updated:updated,season:season))
            fake.answers["/players/Player-1234"]=fake.ok(json(["summary":[:],"stats":["pc":["competitive":career(comp),"quickplay":quick.map(career) as Any? ?? NSNull()],"console":NSNull()]]))
        }
        answer(100,comp:Mode(played:20,won:10,lost:10,bests:["eliminations_most_in_game":40],heroes:["reinhardt":12000]),quick:Mode(played:10,won:5,lost:5,heroes:["juno":6000]))
        _=look(profile,"Player#1234",at(0))
        let hours=profile.history.current.hours
        // Quick Play gone from the answer: kept back, nothing told, no hours.
        answer(200,comp:Mode(played:21,won:11,lost:10,bests:["eliminations_most_in_game":40],heroes:["reinhardt":12600]),quick:nil)
        var (_,card)=look(profile,"Player#1234",at(11))
        precondition(card?.last == nil && profile.history.current.changes.isEmpty && profile.history.current.hours == hours,"\(String(describing:card?.last))")
        // The same again: the new starting point, still nothing told or counted.
        answer(300,comp:Mode(played:21,won:11,lost:10,bests:["eliminations_most_in_game":40],heroes:["reinhardt":12600]),quick:nil)
        (_,card)=look(profile,"Player#1234",at(22))
        precondition(card?.last == nil && profile.history.current.changes.isEmpty && profile.history.current.hours?.heroes == hours?.heroes)
        // From it on, as usual.
        answer(400,comp:Mode(played:23,won:13,lost:10,bests:["eliminations_most_in_game":40],heroes:["reinhardt":13800]),quick:nil)
        (_,card)=look(profile,"Player#1234",at(33))
        precondition(card?.last?.competitive.played == 2 && profile.history.current.hours?.heroes["reinhardt"] == 13200,"\(String(describing:profile.history.current.hours))")
        // A new season: its Competitive bests start over, and one below the all-time best isn't news; the shown best
        // stays the highest.
        answer(500,season:26,comp:Mode(played:1,won:1,bests:["eliminations_most_in_game":30],heroes:["reinhardt":600]),quick:nil)
        _=look(profile,"Player#1234",at(44))
        answer(600,season:26,comp:Mode(played:2,won:2,bests:["eliminations_most_in_game":35],heroes:["reinhardt":1200]),quick:nil)
        (_,card)=look(profile,"Player#1234",at(55))
        precondition(card?.last?.competitive.played == 1 && card?.last?.best == nil && card?.bests["eliminations_most_in_game"] == 40,"\(String(describing:card?.last))")
        precondition(profile.history.current.hours?.heroes["reinhardt"] == 13200+600+600,"the season's turn counts its first games once")
    }

    static func servers() {
        precondition(OverFast.server("https://overfast.example.com")?.absoluteString == "https://overfast.example.com")
        precondition(OverFast.server(" http://localhost:8000/ ")?.host == "localhost" && OverFast.server("http://127.0.0.1:8080") != nil)
        // The BattleTag never travels unencrypted to another machine, nor to something that isn't a server.
        for bad in ["http://overfast.example.com","ftp://x","overfast.example.com","https://x/?q=1","","https://"] { precondition(OverFast.server(bad) == nil,bad) }
    }
}
