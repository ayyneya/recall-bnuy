import Foundation

// DiscordCardTemplate.swift and DiscordCardCatalog.swift: the card's design (Full's Default and the
// ready-made ones), each part's words from the profile, the history and the log, what shows in a match and
// in the group's voice, and the lists taking turns on one clock. A made-up player on a fixed calendar
// (October 2026 in UTC; the 26th is a Monday).
// Build and run:
//   swiftc -O -target arm64-apple-macos26.5 -parse-as-library app/Sources/Brand.swift app/Sources/Localization.swift \
//     app/Sources/Discord/DiscordPresence.swift app/Sources/Discord/CareerProfile.swift app/Sources/Discord/CareerHistory.swift \
//     app/Sources/Discord/DiscordCardTemplate.swift app/Sources/Discord/DiscordCardCatalog.swift app/Sources/Discord/DiscordCardCode.swift tests/DiscordCardTests.swift \
//     -o runtime/phase-3/discord-card-tests
//   runtime/phase-3/discord-card-tests

@main struct DiscordCardTests {
    static var calendar:Calendar={ var made=Calendar(identifier:.gregorian);made.timeZone=TimeZone(identifier:"UTC")!;made.firstWeekday=2;return made }()
    static func day(_ date:Int,_ hour:Double)->Date { calendar.date(from:DateComponents(year:2026,month:10,day:date))!.addingTimeInterval(hour*3600) }
    static let texts=PresenceTexts(menu:"In Menus",match:"In Match",voice:"In Group Voice",badge:"Playing on Mac with Recall")
    static func rank(_ role:CareerRank.Role,_ division:String,_ tier:Int,_ icon:String)->CareerRank { CareerRank(role:role,division:division,tier:tier,icon:URL(string:"https://x/\(icon).png")!) }
    static let tank=rank(.tank,"emerald",1,"emerald"),sixes=rank(.open,"emerald",1,"emerald6"),sixesOnly=rank(.open,"gold",3,"gold6")

    /// pyxee: Support mostly (Juno, Ana), 42 hours in all; Tank up a division in today's session, with a new best.
    static func profile()->CareerCard {
        let heroes=["juno":CareerHero(name:"Juno",portrait:URL(string:"https://x/juno.png"),role:.support),"ana":CareerHero(name:"Ana",portrait:URL(string:"https://x/ana.png"),role:.support),
                    "reinhardt":CareerHero(name:"Reinhardt",portrait:URL(string:"https://x/rein.png"),role:.tank),"widowmaker":CareerHero(name:"Widowmaker",portrait:URL(string:"https://x/widow.png"),role:.damage),
                    "wuyang":CareerHero(name:"Wuyang",portrait:URL(string:"https://x/wuyang.png"),role:.support)]
        let competitive=ModeStats(games:Tally(played:98,won:46,lost:52),heroes:["reinhardt":25560,"widowmaker":21600,"ana":32040],
                                  bests:["eliminations_most_in_game":53,"all_damage_done_most_in_game":39448,"healing_done_most_in_game":16163,"kill_streak_best":27,"multikill_best":6])
        let quickplay=ModeStats(games:Tally(played:578,won:297,lost:281),heroes:["juno":55800,"wuyang":18000],bests:["eliminations_most_in_game":41],heroGames:["juno":Tally(played:40,won:22,lost:18)])
        return CareerCard(identity:CareerIdentity(name:"pyxee",title:":3",endorsement:5,avatar:URL(string:"https://x/avatar.png")),ranks:[tank,sixes],season:25,last:today().session,
                          hero:heroes["widowmaker"],page:URL(string:"https://overwatch.blizzard.com/en-us/career/pyxee-11248/"),totals:["competitive":competitive,"quickplay":quickplay],heroes:heroes)
    }
    /// Today's session, played this afternoon: Tank up a division, a new best, Juno past ten hours.
    static func today()->ProfileChange {
        var change=ProfileChange(at:day(28,13),season:25,session:LastSession(competitive:Tally(played:1,won:1),other:1,hero:"widowmaker",role:.tank,eliminations:31,deaths:7,damage:10623,
                                                                            best:CareerBest(key:"eliminations_most_in_game",value:53),rank:tank,promoted:true),before:[:],after:[:])
        change.rankSteps=1;change.seasonHigh=tank;change.milestone=ProfileChange.Milestone(hero:"juno",hours:10)
        return change
    }
    static func history()->CareerHistory {
        var history=CareerHistory()
        var monday=ProfileChange(at:day(26,22),season:25,session:LastSession(competitive:Tally(played:3,won:2,lost:1),other:0),before:[:],after:[:]);monday.heroes=["juno":3000]
        history.changes=[monday,today()]
        history.season=25;history.seasonSeen=day(20,18);history.seasonFirst=[rank(.tank,"gold",2,"gold")];history.seasonPeak=[tank,sixes];history.looked=day(28,19)
        history.runs=[PlayedRun(start:day(26,21),end:day(26,23),matches:3),PlayedRun(start:day(27,21),end:day(27,23),matches:2)]
        return history
    }
    /// Wednesday evening: the game opened at 19:00, it's 20:00 now, in the menus after two matches.
    static func inputs(_ place:PresenceState = .menu,profile:CareerCard?=profile(),history:CareerHistory=history(),voice:GroupVoice?=nil,matches:Int=2,now:Date=day(28,20))->CardInputs {
        CardInputs(place:place,voice:voice,profile:profile,history:history,tagName:"pyxee",launched:day(28,19),matches:matches,now:now,texts:texts,calendar:calendar)
    }
    static func text(_ piece:CardPiece,_ i:CardInputs=inputs(),rank:RankChoice = .lastPlayed)->String? { piece.text(i,rank:rank) }
    static func assets(_ card:[String:Any])->[String:String] { card["assets"] as? [String:String] ?? [:] }

    static func main() {
        words();defaultCard();inAMatch();groupVoice();turns();designs();codes();countedHours();promises();phrases();englishCard();personas()
        print("PASS: each piece's words, Full's card in the menus, in a match and in the group's voice, the lists taking turns, the designs, their codes, and the hours Recall counts")
    }
    /// Once Recall counts the hours, the card's hours are its count (a new season doesn't take them away), and without
    /// the profile there are none.
    static func countedHours() {
        var counted=history();counted.hours=HeroHours(since:day(20,18),heroes:["ana":120*3600,"juno":3600])
        let i=inputs(history:counted)
        precondition(i.heroTime == ["ana":120*3600,"juno":3600] && i.topHeroes == ["ana","juno"])
        precondition(text(.title(.hours),i) == "121h in Overwatch" && text(.title(.century),i) == "100 hours in","\(String(describing:text(.title(.hours),i)))")
        precondition(inputs(profile:nil,history:counted).heroTime.isEmpty,"no profile, no hours")
        precondition(inputs().heroTime == inputs().modes.reduce(into:[String:Int]()) { t,m in for (h,s) in m.heroes { t[h,default:0]+=s } },"before Recall counts: the profile's own")
        // Cardboard Support: Support main (45% or more of the hours, the most of any role) whose support heroes did more
        // damage than healing (Damage games don't count).
        var supportHours=history();supportHours.hours=HeroHours(since:day(20,18),heroes:["juno":60*3600,"ana":20*3600,"reinhardt":20*3600])
        var hitter=profile();hitter.totals["competitive"]?.heroDamage=["juno":900_000,"reinhardt":5_000_000];hitter.totals["competitive"]?.heroHealing=["juno":10]
        precondition(text(.title(.cardboardSupport),inputs(profile:hitter,history:supportHours)) == "Cardboard Support")
        precondition(CardPiece.title(.cardboardSupport).progress(inputs(profile:hitter,history:supportHours))?.done == 1)
        var damageGames=hitter;damageGames.totals["competitive"]?.heroDamage=["juno":5,"reinhardt":5_000_000]
        precondition(text(.title(.cardboardSupport),inputs(profile:damageGames,history:supportHours)) == nil,"only the support heroes' own")
        var healer=hitter;healer.totals["competitive"]?.heroHealing=["juno":2_000_000]
        precondition(text(.title(.cardboardSupport),inputs(profile:healer,history:supportHours)) == nil)
        let short=CardPiece.title(.cardboardSupport).progress(inputs(profile:healer,history:supportHours))
        precondition(short != nil && short!.done < 1 && short!.needed?.contains("healing") == true,"\(String(describing:short))")
        var tankHours=history();tankHours.hours=HeroHours(since:day(20,18),heroes:["reinhardt":80*3600,"juno":20*3600])
        precondition(text(.title(.cardboardSupport),inputs(profile:hitter,history:tankHours)) == nil && CardPiece.title(.cardboardSupport).progress(inputs(profile:hitter,history:tankHours))!.done <= 0.5)
    }

    static func words() {
        // Rank: how the last session moved it (↑ one division; – the same), the season's climb and peak, every role.
        precondition(text(.rank(.current)) == "Tank ↑ Emerald 1" && text(.rank(.current),rank:.role(.open)) == "6v6 – Emerald 1")
        precondition(text(.rank(.climb)) == "Gold 2 → Emerald 1 this season" && text(.rank(.peak)) == "Season peak: Emerald 1")
        precondition(text(.rank(.all)) == "Tank ↑ Emerald 1 · 6v6 – Emerald 1" && text(.rank(.change)) == "Tank ↑ Emerald 1")
        precondition(text(.rank(.current),rank:.role(.support)) == nil && text(.rank(.climb),rank:.role(.open)) == nil,"no rank in that role; no climb without a first rank")
        var two=today();two.rankSteps=2
        var moved=history();moved.changes[1]=two
        precondition(text(.rank(.current),inputs(history:moved)) == "Tank ↟ Emerald 1")
        two.rankSteps = -1;two.session.promoted=false;moved.changes[1]=two
        precondition(text(.rank(.current),inputs(history:moved)) == "Tank ↓ Emerald 1")
        // Each role's own move, when the change kept them: the profile page's marks for every role, not one.
        two.rankMoves=["tank":1,"open":-2];moved.changes[1]=two
        precondition(text(.rank(.all),inputs(history:moved)) == "Tank ↑ Emerald 1 · 6v6 ↡ Emerald 1")
        two.rankMoves=[:];moved.changes[1]=two
        precondition(text(.rank(.all),inputs(history:moved)) == "Tank – Emerald 1 · 6v6 – Emerald 1","kept, and none moved")
        precondition(CareerRank.moves(from:[rank(.tank,"gold",2,"g"),rank(.open,"emerald",1,"e"),rank(.support,"gold",1,"g")],
                                      to:[rank(.tank,"emerald",1,"e"),rank(.open,"emerald",1,"e"),rank(.damage,"gold",1,"g")]) == ["tank":11],
                     "Gold 2 to Emerald 1 is eleven divisions; a role that didn't move, or isn't in both looks, has none")
        // Records: each period with its tag, the last session's other modes, both modes, a win rate; none with no games.
        // The last session and today say when; the season says "this season", never a number.
        precondition(text(.record(.last,.competitive,winRate:false)) == "Earlier tonight · Comp 1–0 · 1 other" && text(.record(.today,.competitive,winRate:false)) == "Earlier tonight · Comp 1–0")
        precondition(text(.record(.today,.competitive,winRate:false),inputs(now:day(28,14))) == "Earlier today · Comp 1–0")
        precondition(text(.record(.week,.competitive,winRate:false)) == "Week · Comp 3–1" && text(.record(.season,.competitive,winRate:false)) == "This season · Comp 3–1")
        precondition(text(.record(.all,.competitive,winRate:false)) == "This season · Comp 46–52" && text(.record(.all,.both,winRate:false)) == "Overall · Comp 46–52 · QP 297–281")
        precondition(text(.record(.all,.quickPlay,winRate:false)) == "All time · QP 297–281")
        var unranked=profile();unranked.ranks=[]
        precondition(text(.record(.all,.both,winRate:false),inputs(profile:unranked)) == "Overall · QP 297–281","no rank this season: the Comp totals are an older season's")
        // A day word for the last session; after a week, none.
        precondition(text(.record(.last,.competitive,winRate:false),inputs(now:day(29,20))) == "Last night · Comp 1–0 · 1 other")
        precondition(text(.record(.last,.competitive,winRate:false),inputs(now:day(31,20))) == "Wednesday · Comp 1–0 · 1 other")
        precondition(text(.record(.last,.competitive,winRate:false),inputs(now:day(28,20).addingTimeInterval(8*86_400))) == nil)
        // A season Recall has known for over ten weeks is one the player stopped playing.
        var old=history();old.seasonSeen=day(1,0).addingTimeInterval(-60*86_400)
        precondition(text(.record(.season,.competitive,winRate:false),inputs(history:old)) == nil)
        precondition(text(.record(.week,.competitive,winRate:true)) == "Week · Comp 3–1 · 75%" && text(.record(.week,.quickPlay,winRate:false)) == nil)
        precondition(text(.record(.today,.competitive,winRate:false),inputs(now:day(29,20))) == nil,"nothing yet today")
        // Heroes: "main" is earned by the most-played only; hours, role, win rate.
        precondition(text(.hero(nil,.main)) == "Juno main" && text(.hero("ana",.main)) == nil && text(.hero("ana",.hours)) == "Ana · 8h")
        precondition(text(.hero(nil,.role)) == "Support · Juno 15h" && text(.hero(nil,.winRate)) == "Juno · 55% wins in 40 games" && text(.hero("ana",.winRate)) == nil)
        // Bests, over both modes; the new one only while it is news.
        precondition(text(.best(.eliminations)) == "Best: 53 elims in a game" && text(.best(.damage)) == "Best: 39,448 damage" && text(.best(.healing)) == "Best: 16,163 healing")
        precondition(text(.best(.killStreak)) == "Best: 27 kill streak" && text(.best(.multikill)) == "Best: 6-kill multikill" && text(.best(.new)) == "★ New best: 53 elims")
        // Tonight: from the log and the runs, no BattleTag needed.
        precondition(text(.tonight(.matches)) == "2 matches tonight" && text(.tonight(.matches),inputs(matches:1)) == "1 match tonight" && text(.tonight(.matches),inputs(matches:0)) == nil)
        precondition(text(.tonight(.matches),inputs(.match(since:day(28,19.9)),matches:3)) == "Match 3 tonight")
        // "Today" in the daytime; a crash or relaunch less than ten minutes before joins the same night's count.
        precondition(text(.tonight(.matches),inputs(matches:2,now:day(28,14))) == "2 matches today")
        var relaunched=history();relaunched.runs.append(PlayedRun(start:day(28,17.5),end:day(28,18.9),matches:4))
        precondition(text(.tonight(.matches),inputs(history:relaunched,matches:2)) == "6 matches tonight")
        relaunched.runs[relaunched.runs.count-1].end=day(28,18.5)
        precondition(text(.tonight(.matches),inputs(history:relaunched,matches:2)) == "2 matches tonight","half an hour apart: another session")
        precondition(text(.tonight(.nights),inputs(profile:nil)) == "3rd night in a row" && text(.tonight(.week),inputs(profile:nil)) == "Week · 5h played")
        // Titles earned from the hours (Support is 57%; no role under 20% for flex; Juno 36%; 42 hours).
        precondition(text(.title(.endorsement)) == "Endorsement 5" && text(.title(.hours)) == "42h in Overwatch" && text(.title(.roleMain)) == "Support main")
        precondition(text(.title(.flex)) == nil && text(.title(.oneTrick)) == nil && text(.title(.century)) == nil)
        // Moments: while they are news, in the menus.
        precondition(text(.moment(.rankChange)) == "Tank ↑ Emerald 1" && text(.moment(.newBest)) == "★ New best: 53 elims" && text(.moment(.seasonHigh)) == "★ Season high: Emerald 1")
        precondition(text(.moment(.milestone)) == "★ 10 hours on Juno" && text(.moment(.comeback)) == nil && text(.moment(.newSeason)) == nil)
        var played=history();played.runs.append(PlayedRun(start:day(28,15),end:day(28,17),matches:4))
        precondition(text(.moment(.rankChange),inputs(history:played)) != nil,"a game earlier the same night: still news, all night")
        var tomorrow=inputs(history:played);tomorrow.launched=day(29,19);tomorrow.now=day(29,20)
        precondition(text(.moment(.rankChange),tomorrow) == nil && text(.best(.new),tomorrow) == nil,"a game on a night since: no longer news")
        var away=history();away.runs=[PlayedRun(start:day(20,20),end:day(21,22),matches:2)];away.changes=[]
        precondition(text(.moment(.comeback),inputs(profile:nil,history:away)) == "First game in 6 days")
        // A session the profile told counts, wherever it was played.
        away.changes=[ProfileChange(at:day(27,22),season:25,session:LastSession(competitive:Tally(played:1)),before:[:],after:[:])]
        precondition(text(.moment(.comeback),inputs(profile:nil,history:away)) == nil)
        // "First game of the season" is retired (D8e): it never shows.
        var season=history();season.seasonFollows=true;season.seasonSeen=day(28,19)
        precondition(text(.moment(.newSeason),inputs(history:season)) == nil)
        // Without the profile, only what the log and the runs say.
        for piece in [CardPiece.rank(.current),.record(.all,.competitive,winRate:false),.hero(nil,.hours),.best(.eliminations),.title(.endorsement),.moment(.rankChange)] {
            precondition(text(piece,inputs(profile:nil)) == nil,"\(piece)")
        }
        // An old look and matches played since: the rank may have moved, so it isn't shown.
        var stale=history();stale.looked=day(24,12);stale.runs.append(PlayedRun(start:day(25,20),end:day(25,22),matches:3))
        precondition(text(.rank(.current),inputs(history:stale)) == nil && text(.rank(.all),inputs(history:stale)) == nil && text(.record(.all,.competitive,winRate:false),inputs(history:stale)) != nil)
        // Line 1's words.
        let i=inputs()
        precondition(i.lineOne(.name,rank:.lastPlayed) == "pyxee" && i.lineOne(.nameAndTitle,rank:.lastPlayed) == "pyxee :3" && i.lineOne(.main,rank:.lastPlayed) == "Juno main")
        precondition(i.lineOne(.rank,rank:.lastPlayed) == "Tank ↑ Emerald 1" && inputs(.match(since:day(28,19.9))).lineOne(.rank,rank:.lastPlayed) == "pyxee" && i.lineOne(.placeOnly,rank:.lastPlayed) == nil)
        precondition(inputs(profile:nil).lineOne(.nameAndTitle,rank:.lastPlayed) == "pyxee","the BattleTag's name without a profile")
        var titled=profile();titled.identity?.title="Shieldbreaker Supreme"
        precondition(inputs(profile:titled).lineOne(.nameAndTitle,rank:.lastPlayed) == "pyxee","a title that would cut the place goes first")
        // Line 1 never repeats Line 2: the name in its place.
        var echo=DiscordCardDesign(id:"e",name:"",lineOne:[.rank],lineTwo:[CardLine(piece:.rank(.current))])
        precondition(echo.activity(inputs())["details"] as? String == "pyxee · In Menus" && echo.activity(inputs())["state"] as? String == "Tank ↑ Emerald 1")
        echo.lineTwo=[CardLine(piece:.tonight(.matches))]
        precondition(echo.activity(inputs())["details"] as? String == "Tank ↑ Emerald 1 · In Menus")
        // Rates never contradict their record; counts carry their thousands separator.
        precondition(CardInputs.rate(Tally(played:201,won:200,lost:1)) == "99" && CardInputs.rate(Tally(played:201,won:1,lost:200)) == "1" && CardInputs.rate(Tally(played:4,won:4)) == "100")
        precondition(i.hours(1_204*3600) == "1,204h" && i.count(12_345) == "12,345")
        // One elimination and one death read in the singular.
        precondition(LastSession(eliminations:1,deaths:1,damage:900).stats == "1 elimination, 1 death, 900 damage" && LastSession(eliminations:3,deaths:0,healing:5).stats == "3 eliminations, 0 deaths, 5 healing")
        // A game opened at ten keeps its night past four in the morning.
        var late=inputs(profile:nil,now:day(29,4.5));late.launched=day(28,22)
        precondition(text(.tonight(.nights),late) == "3rd night in a row")
        // A clock before 1970 never turns a list below its first item.
        precondition(DiscordCardDesign.standard.turn(at:Date(timeIntervalSince1970:-100)) == 0)
        // A period's record brings the hero played most in it.
        precondition(CardPiece.record(.week,.competitive,winRate:false).picture(i,rank:.lastPlayed) == .hero("juno"))
    }

    static func defaultCard() {
        let design=DiscordCardDesign.standard
        // Something just happened: the rank moved in today's session. Highlights' picture is the rank that moved, as a
        // Rank change line's is, and the badge is then the Mac's (one picture never shows twice).
        var card=design.activity(inputs())
        precondition(card["details"] as? String == "pyxee · In Menus" && card["state"] as? String == "Tank ↑ Emerald 1","\(card)")
        precondition(assets(card)["large_image"] == "https://x/emerald.png" && assets(card)["large_text"] == "Tank: Emerald 1")
        var news=design;news.lineTwo=[CardLine(piece:.moment(.rankChange))]
        precondition(assets(news.activity(inputs())) == assets(card))
        precondition(assets(card)["small_image"] == DiscordAssets.macBadge.absoluteString && assets(card)["small_text"] == "Playing on Mac with Recall")
        // With the last session's hero large, the badge is the rank, its hover every role's.
        var hero=design;hero.lineTwo=[CardLine(piece:.record(.last,.both,winRate:false))]
        precondition(assets(hero.activity(inputs()))["large_image"] == "https://x/widow.png" && assets(hero.activity(inputs()))["small_image"] == "https://x/emerald.png")
        precondition(assets(hero.activity(inputs()))["small_text"] == "Tank ↑ Emerald 1 · 6v6 – Emerald 1 · Playing on Mac with Recall")
        precondition((card["timestamps"] as? [String:Int])?["start"] == Int(day(28,19).timeIntervalSince1970))
        precondition((card["buttons"] as? [[String:String]]) == [["label":"Get Recall for Mac","url":Brand.repository.absoluteString],
                                                                 ["label":"Career Profile","url":"https://overwatch.blizzard.com/en-us/career/pyxee-11248/"]])
        // A game since, on a later night: the last session, with its hero and what was done on all heroes.
        var played=history();played.runs.append(PlayedRun(start:day(28,15),end:day(28,17),matches:4))
        var tomorrow=inputs(history:played);tomorrow.launched=day(29,19);tomorrow.now=day(29,20)
        card=design.activity(tomorrow)
        precondition(card["state"] as? String == "Last night · Comp 1–0 · 1 other" && assets(card)["large_image"] == "https://x/widow.png","\(card)")
        precondition(assets(card)["large_text"] == "Most played last session: Widowmaker · All heroes: 31 eliminations, 7 deaths, 10,623 damage")
        // A profile kept from before the history (an earlier Recall): its last session still shows.
        precondition(design.activity(inputs(history:CareerHistory()))["state"] as? String == "Last · Comp 1–0 · 1 other")
        // The first look, with no session yet: all-time; no profile: tonight's matches, the BattleTag's name, the Mac badge.
        var first=profile();first.last=nil;first.hero=nil
        card=design.activity(inputs(profile:first,history:CareerHistory()))
        precondition(card["state"] as? String == "This season · Comp 46–52" && assets(card)["large_image"] == "https://x/avatar.png" && assets(card)["large_text"] == "pyxee · :3")
        card=design.activity(inputs(profile:nil))
        precondition(card["details"] as? String == "pyxee · In Menus" && card["state"] as? String == "2 matches tonight" && assets(card)["large_image"] == nil)
        precondition(assets(card)["small_image"] == DiscordAssets.macBadge.absoluteString && assets(card)["small_text"] == "Playing on Mac with Recall" && (card["buttons"] as? [[String:String]])?.count == 1)
        // No match yet tonight: the nights played instead.
        precondition(design.activity(inputs(profile:nil,matches:0))["state"] as? String == "3rd night in a row")
        precondition(design.activity(inputs(profile:nil,history:CareerHistory(),matches:0))["state"] == nil)
        // Where the log can't tell menus from a match: "In Game", or "In Group" in the group's voice; past
        // results only (no news, no rank lines), the player's icon as the only picture, and the rank badge.
        card=design.activity(inputs(.unknown))
        precondition(card["details"] as? String == "pyxee · In Game" && card["state"] as? String == "Earlier tonight · Comp 1–0 · 1 other" && assets(card)["large_image"] == "https://x/avatar.png","\(card)")
        precondition(assets(card)["small_image"] == "https://x/emerald.png")
        var grouped=design;grouped.party = .addCount
        precondition(grouped.activity(inputs(.unknown,voice:GroupVoice(count:3,channel:"P",party:"p")))["details"] as? String == "pyxee · In Group")
        var ranked=DiscordCardDesign(id:"r",name:"",lineOne:[.rank],lineTwo:[CardLine(piece:.rank(.current)),CardLine(piece:.record(.week,.competitive,winRate:false))])
        ranked.pace=20
        let unsure=(0..<4).compactMap { k in ranked.activity(inputs(.unknown,now:day(28,20).addingTimeInterval(TimeInterval(k*20))))["state"] as? String }
        precondition(Set(unsure) == ["Week · Comp 3–1"] && ranked.activity(inputs(.unknown))["details"] as? String == "pyxee · In Game","\(unsure)")
    }

    static func inAMatch() {
        let since=day(28,19.9),design=DiscordCardDesign.standard
        // Highlights says past results only: no news, nothing about this match. The match's own timer, the player's
        // icon, the badge.
        var card=design.activity(inputs(.match(since:since),matches:3))
        precondition(card["details"] as? String == "pyxee · In Match" && card["state"] as? String == "Earlier tonight · Comp 1–0 · 1 other" && assets(card)["large_image"] == "https://x/avatar.png","\(card)")
        precondition(design.activity(inputs(.match(since:since),profile:nil,matches:3))["state"] as? String == "Match 3 tonight")
        precondition((card["timestamps"] as? [String:Int])?["start"] == Int(since.timeIntervalSince1970) && assets(card)["small_image"] == DiscordAssets.macBadge.absoluteString)
        precondition(card["buttons"] != nil,"the buttons make no claim about the match")
        // A source that knows the match is competitive puts the rank on it.
        var known=inputs(.match(since:since));known.competitive=true
        precondition(assets(design.activity(known))["small_image"] == "https://x/emerald.png")
        // The session timer counts on through matches. Only lines that say nothing about the match show, and only if asked.
        var mine=DiscordCardDesign(id:"mine",name:"Mine",lineTwo:[CardLine(piece:.record(.week,.competitive,winRate:false)),CardLine(piece:.tonight(.matches)),CardLine(piece:.hero(nil,.hours),inMatch:false)],timer:.session)
        card=mine.activity(inputs(.match(since:since),matches:3))
        precondition(card["state"] as? String == "Match 3 tonight" && (card["timestamps"] as? [String:Int])?["start"] == Int(day(28,19).timeIntervalSince1970))
        // A second piece follows the first, when it has something to say there too.
        mine.lineTwo=[CardLine(piece:.tonight(.matches),second:.hero(nil,.hours))]
        precondition(mine.activity(inputs(.match(since:since),matches:3))["state"] as? String == "Match 3 tonight · Juno · 15h")
        mine.lineTwo=[CardLine(piece:.tonight(.matches),second:.record(.week,.competitive,winRate:false))]
        precondition(mine.activity(inputs(.match(since:since),matches:3))["state"] as? String == "Match 3 tonight")
        precondition(mine.activity(inputs(matches:3))["state"] as? String == "3 matches tonight · Week · Comp 3–1")
    }

    static func groupVoice() {
        let voice=GroupVoice(count:3,channel:"P",party:"party-id")
        func party(_ card:[String:Any])->[String:AnyHashable]? { card["party"] as? [String:AnyHashable] }
        var design=DiscordCardDesign.standard
        // Said on Line 2, with Discord's own count after it ("In Group Voice (3 of 5)").
        var card=design.activity(inputs(voice:voice))
        precondition(card["state"] as? String == "In Group Voice" && party(card)?["id"] == AnyHashable("party-id") && party(card)?["size"] == AnyHashable([3,5]))
        // Line 2 kept, the count added; and Line 2 alone.
        design.party = .addCount
        card=design.activity(inputs(voice:voice))
        precondition(card["state"] as? String == "Tank ↑ Emerald 1" && party(card) != nil)
        precondition(design.activity(inputs(.unknown,voice:voice))["state"] as? String == "Earlier tonight · Comp 1–0 · 1 other","in a group: the past result kept, the count added")
        precondition(design.activity(inputs(.match(since:day(28,19)),voice:voice))["state"] as? String == "Earlier tonight · Comp 1–0 · 1 other","in a match too: the past result kept")
        precondition(design.activity(inputs(.match(since:day(28,19)),profile:nil,history:CareerHistory(),voice:voice,matches:0))["state"] as? String == "In Group Voice","nothing to keep: the voice")
        design.party = .noCount
        card=design.activity(inputs(voice:voice))
        precondition(card["state"] as? String == "Tank ↑ Emerald 1" && party(card) == nil)
        // A group of more than six counts six.
        precondition(party(DiscordCardDesign.standard.activity(inputs(voice:GroupVoice(count:9,channel:"P",party:"p"))))?["size"] == AnyHashable([6,6]))
    }

    static func turns() {
        // Three lines, 45 seconds each, on one clock: the turn is the time over the pace.
        var design=DiscordCardDesign(id:"mine",name:"Mine",lineTwo:[CardLine(piece:.record(.week,.competitive,winRate:false)),CardLine(piece:.tonight(.matches)),CardLine(piece:.hero(nil,.hours))])
        let start=Date(timeIntervalSince1970:TimeInterval(design.turn(at:day(28,20))*45))
        func state(_ at:Date)->String? { design.activity(inputs(now:at))["state"] as? String }
        let order=["Week · Comp 3–1","2 matches tonight","Juno · 15h"]
        let first=order.firstIndex(of:state(start)!)!
        for k in 0..<6 { precondition(state(start.addingTimeInterval(TimeInterval(k*45)+10)) == order[(first+k)%3],"turn \(k)") }
        precondition(state(start.addingTimeInterval(44)) == state(start),"the same turn, the same card")
        precondition(design.nextTurn(inputs(now:start.addingTimeInterval(10))) == start.addingTimeInterval(45))
        // A line with nothing to say takes no turn: two lines left.
        precondition(Set((0..<4).compactMap { k in design.activity(inputs(matches:0,now:start.addingTimeInterval(TimeInterval(k*45))))["state"] as? String }) == ["Week · Comp 3–1","Juno · 15h"])
        // One line, one picture, one badge: nothing turns, so no refresh is asked for; the top heroes turn within one picture.
        precondition(DiscordCardDesign.standard.nextTurn(inputs()) == nil)
        var top=DiscordCardDesign.standard;top.pictures=[.topHeroes]
        precondition(top.nextTurn(inputs()) != nil && top.nextTurn(inputs(.match(since:day(28,19.9)))) == nil)
        precondition(Set((0..<5).compactMap { k in assets(top.activity(inputs(now:start.addingTimeInterval(TimeInterval(k*45)))))["large_image"] }).count == 5)
        // The pictures' own list and the badges turn with the lines; Overwatch's own picture takes its turn as none.
        design.lineTwo=[CardLine(piece:.tonight(.matches))];design.pictures=[.playerIcon,.hero("ana"),.overwatch];design.badges=[.rank,.mac]
        let shown=(0..<4).map { k -> (String?,String?) in
            let card=design.activity(inputs(now:start.addingTimeInterval(TimeInterval(k*45))))
            return (assets(card)["large_image"],assets(card)["small_image"])
        }
        precondition(Set(shown.map(\.0)) == ["https://x/avatar.png","https://x/ana.png",nil] && Set(shown.map(\.1)) == ["https://x/emerald.png",DiscordAssets.macBadge.absoluteString],"\(shown)")
        precondition(design.nextTurn(inputs()) != nil)
        // In a match the rank badge sits out, and the Recall badge stands in when it's the only other.
        design.badges=[.rank,.recall]
        precondition(assets(design.activity(inputs(.match(since:day(28,19.9)))))["small_image"] == DiscordAssets.badge.absoluteString)
        // A pace below Discord's comfort is taken as 20 seconds.
        design.pace=5
        precondition(design.turn(at:Date(timeIntervalSince1970:100)) == 5)
    }

    static func designs() {
        // The ready-made designs: Full's Default and the five Customize starts from, each a working card.
        precondition(DiscordCardDesign.readyMade.map(\.id) == ["default","climber","main","grinder","showoff","private"] && DiscordCardDesign.standard.readyMade)
        // Private profile: all from this Mac, with no profile at all; no BattleTag button.
        let privately=DiscordCardDesign.privateProfile.activity(inputs(profile:nil))
        precondition(["2 matches tonight","3rd night in a row","Week · 5h played"].contains(privately["state"] as? String ?? "") && (privately["buttons"] as? [[String:String]])?.count == 1,"\(privately)")
        let main=DiscordCardDesign.readyMade[2]
        let card=main.activity(inputs())
        precondition(["Juno main","Juno · 15h","Support · Juno 15h"].contains(card["state"] as? String ?? ""),"\(card)")
        let buttons=card["buttons"] as? [[String:String]]
        precondition(buttons?.last == ["label":"Juno","url":"https://overwatch.blizzard.com/en-us/heroes/juno/"],"\(String(describing:buttons))")
        var notes=DiscordCardDesign.standard;notes.button = .patchNotes
        precondition((notes.activity(inputs())["buttons"] as? [[String:String]])?.last?["label"] == "Patch notes")
        notes.button=nil
        precondition((notes.activity(inputs())["buttons"] as? [[String:String]])?.count == 1)
        // Kept in the settings: the player's own, and the one in use (an unknown one is Default).
        let suite="discord-card-tests-\(getpid())",store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        precondition(DiscordCardShelf.load(store) == DiscordCardShelf() && DiscordCardShelf().inUse == .standard)
        var shelf=DiscordCardShelf()
        var mine=DiscordCardDesign(id:UUID().uuidString,name:"Late nights",lineOne:[.name,.rank],lineTwo:[CardLine(piece:.record(.today,.both,winRate:true),second:.tonight(.nights),inMatch:false)],
                                   pictures:[.topHeroes,.hero("ana")],badges:[.recall],timer:.session,button:nil,party:.addCount,pace:120,rank:.role(.open))
        shelf.mine=[mine];shelf.chosen=mine.id;shelf.save(store)
        precondition(DiscordCardShelf.load(store).inUse == mine && !mine.readyMade && mine.shownName == "Late nights")
        mine.name="Other";shelf.chosen="gone"
        precondition(shelf.inUse == .privateProfile,"a card this Recall can't find shows no profile")
        // Cards kept by another Recall still read: what one didn't have takes its default (no second button is no
        // key at all); what this Recall doesn't know (a line, a field, a whole card) is skipped, and written back as
        // it was until the card is changed.
        let kept=#"{"chosen":"x","mine":[{"id":"y","name":"Odd","lineTwo":[{"piece":{"nonsense":{}}},{"piece":{"rank":{"_0":"peak"}}}],"later":[1,"two"]},{"id":"x","name":"Old","pace":120},{"name":"No id"}]}"#
        let read=try! JSONDecoder().decode(DiscordCardShelf.self,from:Data(kept.utf8))
        precondition(read.chosen == "x" && read.hidden.isEmpty && read.mine.count == 2 && read.unread.count == 1,"\(read)")
        precondition(read.mine[0].lineTwo == [CardLine(piece:.rank(.peak))] && read.mine[0].extra["later"] != nil,"\(read.mine[0].lineTwo) \(read.mine[0].extra)")
        precondition(read.mine[1].name == "Old" && read.mine[1].pace == 120 && read.mine[1].button == nil && read.mine[1].lineTwo == DiscordCardDesign.standard.lineTwo
                     && read.mine[1].rank == DiscordCardDesign.standard.rank,"\(read.mine[1])")
        func json(_ value:some Encodable)->JSONValue { try! JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(value)) }
        let whole=try! JSONDecoder().decode(JSONValue.self,from:Data(kept.utf8))
        guard case .object(let shelfJSON)=whole,case .array(let cards)? = shelfJSON["mine"] else { preconditionFailure() }
        precondition(json(read.mine[0]) == cards[0] && json(read) == json(try! JSONDecoder().decode(DiscordCardShelf.self,from:JSONEncoder().encode(read))))
        guard case .object(let written)=json(read),case .array(let back)? = written["mine"] else { preconditionFailure() }
        precondition(back.count == 3 && back[0] == cards[0] && back[2] == cards[2],"unknown cards and lines go back as they were")
        var changed=read.mine[0];changed.pace=20
        guard case .object(let edited)=json(changed) else { preconditionFailure() }
        precondition(edited["pace"] == .number(20) && edited["later"] == .array([.number(1),.string("two")]),"a changed card keeps the fields it doesn't know")
        // Unlocked lines are kept by their cases' own names; an earlier build's keys read the same.
        precondition(CardPiece.title(.flex).key == "title.flex" && CardPiece.stableKey("title(Recall.TitleLine.flex)") == "title.flex"
                     && CardPiece.stableKey("title.century") == "title.century" && CardPiece.hero(nil,.hours).key == "hero.top.hours")
        // A shelf that isn't one at all is kept aside before anything is saved over it.
        let odd="discord-cards-test-\(UUID().uuidString)",oddStore=UserDefaults(suiteName:odd)!
        defer { oddStore.removePersistentDomain(forName:odd) }
        oddStore.set(Data("[1,2]".utf8),forKey:"discordCards")
        precondition(DiscordCardShelf.load(oddStore) == DiscordCardShelf() && oddStore.data(forKey:"discordCards.unreadable") == Data("[1,2]".utf8))
        // Discord's limit on a hover text: 128 characters.
        var long=profile();long.identity?.title=String(repeating:"Shieldbreaker ",count:12)
        var icon=DiscordCardDesign.standard;icon.pictures=[.playerIcon]
        precondition(assets(icon.activity(inputs(profile:long)))["large_text"]?.count == 128)
    }

    /// Players unlike pyxee, on every ready-made card and in every place: each field Discord gets is 2 to 128
    /// Characters, nothing in a match reads as this match's (no rank, no hero, no news; past records only), and Highlights finds something
    /// true to say in the menus whenever there is anything.
    static func personas() {
        var history=CareerHistory();history.runs=[PlayedRun(start:day(26,20),end:day(26,22),matches:3),PlayedRun(start:day(27,20),end:day(27,22),matches:2)]
        var qp=profile();qp.ranks=[];qp.totals["competitive"]=nil;qp.last=LastSession(quickplay:Tally(played:3,won:2,lost:1))
        var sixes=profile();sixes.ranks=[sixesOnly]
        var unknownHero=profile();unknownHero.heroes["juno"]=nil
        var legend=profile();legend.ranks=[CareerRank(role:.tank,division:"legend",tier:2,icon:URL(string:"https://x/legend.png")!)]
        var returning=CareerHistory();returning.runs=[PlayedRun(start:day(10,20),end:day(10,22),matches:4)]
        let people:[(String,CareerCard?,String?,CareerHistory,Int)]=[
            ("no BattleTag",nil,nil,CareerHistory(),0),("private",nil,"pyxee",history,2),("Quick Play only",qp,nil,history,1),
            ("6v6 only",sixes,nil,history,1),("returning",nil,"pyxee",returning,0),("unknown hero",unknownHero,nil,history,2),
            ("unknown division",legend,nil,history,2),("pyxee",profile(),nil,DiscordCardTests.history(),2)]
        let places:[(PresenceState,GroupVoice?)]=[(.menu,nil),(.match(since:day(28,19.9)),nil),(.unknown,nil),(.unknown,GroupVoice(count:4,channel:"P",party:"p"))]
        for (who,card,tag,past,matches) in people {
            for (place,voice) in places {
                var i=inputs(place,profile:card,history:past,voice:voice,matches:matches);i.tagName=tag ?? card?.identity?.name
                for design in DiscordCardDesign.readyMade {
                    let activity=design.activity(i),art=assets(activity)
                    let labels:[String]=((activity["buttons"] as? [[String:String]]) ?? []).compactMap { $0["label"] }
                    let fields:[String]=[activity["details"] as? String,activity["state"] as? String,art["large_text"],art["small_text"]].compactMap { $0 }+labels
                    precondition(fields.allSatisfy { (2...128).contains($0.count) },"\(who), \(design.id): \(fields)")
                    if case .match=place {
                        precondition([nil,"https://x/avatar.png"].contains(art["large_image"]) && !(art["small_image"] ?? "").hasPrefix("https://x/"),"\(who), \(design.id) in a match: \(art)")
                        let state=activity["state"] as? String ?? ""
                        precondition(!["↑","↓","↟","↡","★","Best"].contains { state.contains($0) },"\(who), \(design.id) in a match: \(state)")
                    }
                }
                if place == .menu && (card != nil || matches > 0 || past.nightsInARow(now:i.now,playing:true,calendar:calendar) >= 2) {
                    precondition(DiscordCardDesign.standard.activity(i)["state"] != nil,"\(who): Highlights has nothing")
                }
            }
        }
        // A returning player's first game says so.
        precondition(text(.moment(.comeback),inputs(profile:nil,history:returning)) == "First game in 17 days")
    }

    /// Codes in friends' hands can't be called back: the format and its tables only ever grow.
    static func frozenCodes() {
        func same(_ code:String,_ design:DiscordCardDesign)->Bool { DiscordCardCode.decode(code).map { var read=$0;read.id=design.id;return read } == design }
        var odd=DiscordCardDesign(id:"x",name:"Late nights ✨")
        odd.lineOne=[.rank,.main];odd.lineTwo=[CardLine(piece:.hero("juno",.hours),second:.record(.week,.competitive,winRate:true),inMatch:false),CardLine(piece:.title(.cardboardSupport))]
        odd.pictures=[.art(.jetpackCat),.hero("ana"),.rankEmblem];odd.badges=[.mac,.recall];odd.timer = .session;odd.button = .heroPage;odd.party = .noCount;odd.pace=33;odd.rank = .role(.support)
        let cards=Array(DiscordCardDesign.readyMade.prefix(5))+[odd]
        // The preview builds' codes (format 0), and today's.
        let preview=["1200V","3893-4M00H","3G0A-4190-450T-0Y","3D1C-B600K","3MAK-AM00G","2HBN-MFTM-TQZW-682W-2YDT-X116-XP0T-2G74-KMA9-GF02-EA09"]
        let today=["9200K","B893-4M009","BG0A-4190-450T-0E","BD1C-B600B","BMAK-AM008","AHBN-MFDA-DBZY-341E-1F6X-EGGK-EV0D-183J-9T54-R7G1-750H"]
        for (index,card) in cards.enumerated() {
            precondition(same(preview[index],card) && same(today[index],card) && DiscordCardCode.encode(card) == today[index],"\(card.id): \(DiscordCardCode.encode(card))")
        }
        // The ready-made cards are frozen: each one's code is pinned (Private profile came with format 1).
        precondition(DiscordCardDesign.readyMade.map(\.id) == ["default","climber","main","grinder","showoff","private"])
        precondition(DiscordCardCode.encode(DiscordCardDesign.privateProfile) == "BRPD-N2P0-D004" && same("BRPD-N2P0-D004",.privateProfile))
        // The tables a code indexes: new values only at the end, the hero list never (a new hero is spelt out).
        precondition(LineOne.allCases == [.name,.nameAndTitle,.main,.rank,.placeOnly,.phrase] && LinePhrase.Words.allCases.count == 16 && CardBadge.allCases == [.rank,.mac,.recall])
        precondition(CardMoment.allCases == [.rankChange,.newBest,.seasonHigh,.milestone,.comeback,.newSeason] && RankLine.allCases == [.current,.climb,.peak,.all,.change])
        precondition(RecordMode.allCases == [.competitive,.quickPlay,.both] && HeroLine.allCases == [.main,.hours,.role,.winRate] && TonightLine.allCases == [.matches,.nights,.week])
        precondition(BestLine.allCases == [.eliminations,.damage,.healing,.killStreak,.multikill,.new] && CareerPeriod.allCases == [.last,.today,.week,.season,.all])
        precondition(TitleLine.allCases == [.endorsement,.hours,.roleMain,.flex,.oneTrick,.century,.cardboardSupport] && SecondButton.allCases == [.careerProfile,.heroPage,.patchNotes])
        precondition(DiscordCardDesign.paces == [20,45,60,120,300] && CardArt.allCases.map(\.letter) == ["j","w","c"])
        precondition(DiscordCardCode.heroes.joined(separator:",") == "ana,anran,ashe,baptiste,bastion,brigitte,cassidy,dmon,doctrine,domina,doomfist,dva,echo,emre,freja,genji,hanzo,hazard,illari,jetpack-cat,junker-queen,junkrat,juno,kiriko,lifeweaver,lucio,mauga,mei,mercy,mizuki,moira,orisa,pharah,ramattra,reaper,reinhardt,roadhog,shion,sierra,sigma,sojourn,soldier-76,sombra,symmetra,torbjorn,tracer,vendetta,venture,widowmaker,winston,wrecking-ball,wuyang,zarya,zenyatta")
        // Made by hand, bit by bit, as a later Recall would.
        func code(_ parts:[(Int,Int)])->String {
            var bits:[Bool]=[]
            for (value,width) in parts { for shift in (0..<width).reversed() { bits.append(value>>shift&1 == 1) } }
            while bits.count%5 != 0 { bits.append(false) }
            var symbols=stride(from:0,to:bits.count,by:5).map { at in bits[at..<at+5].reduce(0) { $0<<1|($1 ? 1 : 0) } }
            symbols.append(DiscordCardCode.check(symbols))
            return String(symbols.map { DiscordCardCode.alphabet[$0] })
        }
        let none=[(0,1),(0,1),(0,1),(0,1),(0,6)]
        // A newer format: told as such, not as no card.
        precondition(DiscordCardCode.read(code([(2,2),(0,3)]+none)) == .newer && DiscordCardCode.read(code([(3,2),(5,7)])) == .newer)
        // Parts a later Recall adds are read past, the rest kept: a piece (topic 7, then 1), a Line 1 kind (7), a
        // picture (a hero numbered 0), a badge (3), a value past a list's end, and records after the name.
        let later=code([(1,2),(3,3),
                        (7,3),(1,1),(3,4),(5,6),(0b10101,5),(1,1),(0,1),
                        (2,3),(7,3),(1,1),(0,1),
                        (2,3),(2,3),(1,1),(1,1),(7,3),(1,1),(2,4),(0,6),
                        (1,1),(2,3),(7,3),(1,4),(0,6),(3,3),
                        (1,1),(1,3),(7,3),(0,6),(2,4),(3,6),(0b111,3),
                        (1,1),(2,2),(3,2),(1,4),(0,6),(1,2),
                        (0,1),(0,6),(5,4),(8,6),(0xAB,8)])
        guard case .card(let read)=DiscordCardCode.read(later) else { preconditionFailure(later) }
        precondition(read.lineTwo == [CardLine(piece:.rank(.peak))] && read.lineOne == [.rank] && read.pictures == nil && read.badges == [.mac],"\(read)")
        // Pasted the way messages carry it: in a sentence, any dash, quotes, a line break, full-width letters.
        let grinder=today[3]
        for pasted in ["Here’s my card: `\(grinder)` :)","\(grinder.prefix(4))\n–\(grinder.dropFirst(5))","\"\(grinder.replacingOccurrences(of:"-",with:"—"))\"",
                       String(grinder.map { $0 == "-" ? "－" : Character(UnicodeScalar(($0.unicodeScalars.first!.value)+0xFEE0)!) })] {
            precondition(same(pasted,DiscordCardDesign.readyMade[3]),pasted)
        }
    }

    /// What the card promises, over every ready-made card and thousands made at random, in every place: the BattleTag
    /// only in the Career Profile button's link; one Get Recall button, first, plain; Recall named only there and in
    /// the badge's hover; nothing claiming to be official or native; no fields Discord would show as the game's name.
    /// Every picture the card names is in app/Resources/Discord, under the repository's own tag.
    static func promises() {
        var dice=Dice(seed:0x51ED)
        let places:[PresenceState]=[.menu,.match(since:day(28,19.9)),.unknown]
        for design in DiscordCardDesign.readyMade+(0..<3000).map({ _ in randomDesign(&dice) }) {
            for place in places {
                for voice in [nil,GroupVoice(count:3,channel:"P",party:"p")] {
                    let card=DiscordRules.clean(design.activity(inputs(place,voice:voice)))
                    let buttons=card["buttons"] as? [[String:String]] ?? []
                    precondition(buttons.first?["label"] == "Get Recall for Mac" && buttons.first?["url"] == Brand.repository.absoluteString && URL(string:buttons[0]["url"]!)?.query == nil)
                    precondition(buttons.dropFirst().allSatisfy { !$0["url"]!.contains(Brand.repositoryPath) } && buttons.count <= 2)
                    var texts=[card["details"],card["state"]].compactMap { $0 as? String }
                    let assets=card["assets"] as? [String:String] ?? [:]
                    texts+=[assets["large_text"]].compactMap { $0 }
                    for text in texts+[assets["large_image"],assets["small_image"]].compactMap({ $0 }) {
                        precondition(!text.contains("11248") && !text.contains("/career/"),"\(text)")
                    }
                    for (index,button) in buttons.enumerated() where index > 0 {
                        precondition(!button["label"]!.contains("11248") && (button["url"]!.contains("11248") == (button["label"] == "Career Profile")),"\(button)")
                    }
                    // Recall's own picture carries the badge's words too.
                    let recallPicture=assets["large_image"] == DiscordAssets.badge.absoluteString
                    for text in texts where !(recallPicture && text == assets["large_text"]) { precondition(!text.contains(Brand.name),"\(text)") }
                    for text in texts+[assets["small_text"] ?? ""]+buttons.map({ $0["label"]! }) {
                        for word in ["official","native","made for mac"] { precondition(!text.lowercased().contains(word),"\(text)") }
                    }
                    precondition(card["name"] == nil && card["status_display_type"] == nil)
                }
            }
        }
        precondition(FileManager.default.fileExists(atPath:"app/Resources/"+DiscordAssets.badgeFile) && DiscordAssets.badge.path.hasSuffix("/app/Resources/AppIcon.png"))
        for file in [DiscordAssets.macBadgeFile]+CardArt.allCases.map(\.file) {
            precondition(FileManager.default.fileExists(atPath:"app/Resources/Discord/"+file) && DiscordAssets.art(file).path.hasSuffix("/app/Resources/Discord/"+file),file)
        }
        precondition(DiscordAssets.official.absoluteString.contains("/\(Brand.forkPath)/\(DiscordAssets.tag)/") && DiscordAssets.tag == "discord-art-1")
    }

    /// Line 1's phrase, Recall's words with one blank from a list. Auto fills it from the player's data (the next
    /// rank up only in the menus); a chosen blank needs no profile.
    static func phrases() {
        var design=DiscordCardDesign(id:"p",name:"",lineOne:[.phrase])
        func one(_ phrase:LinePhrase,_ i:CardInputs=inputs())->String? { design.phrase=phrase;return design.activity(i)["details"] as? String }
        precondition(one(LinePhrase(words:.roadTo)) == "Road to Diamond · In Menus","\(String(describing:one(LinePhrase(words:.roadTo))))")
        precondition(one(LinePhrase(words:.roadTo),inputs(.match(since:day(28,19.9)))) == "pyxee · In Match","no rank above in a match: the name")
        precondition(one(LinePhrase(words:.learning,blank:.hero("juno")),inputs(profile:nil)) == "Learning Juno · In Menus")
        precondition(one(LinePhrase(words:.grindingTo,blank:.rank("champion"))) == "Grinding to Champion · In Menus")
        precondition(one(LinePhrase(words:.rolePlayer)) == "Support player · In Menus" && one(LinePhrase(words:.climbingIn,blank:.role(.tank))) == "Climbing in Tank · In Menus")
        precondition(one(LinePhrase(words:.chillNight)) == "Chill night · In Menus" && LinePhrase.Words.chillNight.tonight && !LinePhrase.Words.roadTo.tonight)
        // Without a phrase kept, the name.
        design.phrase=nil
        precondition(design.activity(inputs())["details"] as? String == "pyxee · In Menus")
        // In a share code: the phrase and its blank come back.
        design.phrase=LinePhrase(words:.practicing,blank:.hero("wrecking-ball"))
        let back=DiscordCardCode.decode(DiscordCardCode.encode(design))
        precondition(back?.phrase == design.phrase && back?.lineOne == [.phrase])
    }

    /// The card is in English whatever the Mac's language; Settings' own words stay in it. A Bundle that
    /// "translates" every key shows which words went through it.
    final class Translating: Bundle, @unchecked Sendable {
        override func localizedString(forKey key:String,value:String?,table:String?)->String { "[\(key)]" }
    }
    static func englishCard() {
        let real:AnyClass=object_getClass(Bundle.main)!
        object_setClass(Bundle.main,Translating.self)
        defer { object_setClass(Bundle.main,real) }
        let english=PresenceTexts.app
        var design=DiscordCardDesign(id:"p",name:"",lineOne:[.phrase],lineTwo:[CardLine(piece:.tonight(.matches))],pictures:[.art(.jetpackCat)],badges:[.mac])
        design.phrase=LinePhrase(words:.roadTo,blank:.rank("diamond"))
        let card=design.activity(inputs(profile:nil))
        let words=[card["details"],card["state"]].compactMap { $0 as? String }+(card["assets"] as? [String:String] ?? [:]).values+(card["buttons"] as? [[String:String]] ?? []).compactMap { $0["label"] }
        precondition(!words.joined().contains("[") && english.menu == "In Menus","\(words)")
        precondition(CardPiece.tonight(.matches).text(inputs(profile:nil),rank:.lastPlayed) == "[{0} matches tonight]" || CardPiece.tonight(.matches).text(inputs(profile:nil),rank:.lastPlayed)?.hasPrefix("[") == true,
                     "outside the card, the app's language")
    }

    /// A seeded generator, so a failing card can be found again.
    struct Dice {
        var seed:UInt64
        mutating func next()->UInt64 { seed^=seed<<13;seed^=seed>>7;seed^=seed<<17;return seed }
        mutating func int(_ count:Int)->Int { Int(next()%UInt64(count)) }
        mutating func coin()->Bool { int(2) == 1 }
        mutating func pick<T>(_ list:[T])->T { list[int(list.count)] }
    }
    static func randomHero(_ dice:inout Dice)->String? {
        switch dice.int(4) { case 0: return nil;case 1: return "new-hero-\(dice.int(99))";default: return dice.pick(DiscordCardCode.heroes) }
    }
    static func randomPiece(_ dice:inout Dice)->CardPiece {
        switch dice.int(8) {
        case 0: return .highlights
        case 1: return .moment(dice.pick(CardMoment.allCases))
        case 2: return .rank(dice.pick(RankLine.allCases))
        case 3: return .record(dice.pick(CareerPeriod.allCases),dice.pick(RecordMode.allCases),winRate:dice.coin())
        case 4: return .hero(randomHero(&dice),dice.pick(HeroLine.allCases))
        case 5: return .best(dice.pick(BestLine.allCases))
        case 6: return .tonight(dice.pick(TonightLine.allCases))
        default: return .title(dice.pick(TitleLine.allCases))
        }
    }
    static func randomDesign(_ dice:inout Dice)->DiscordCardDesign {
        let names=["","Late nights","Climber 2","Über ✨ card","한국어 카드","a-b'c.d,e!f?g&h:i(j)k/l+m#n*o_p~","🔥🔥🔥","Tank & Spank","x","ALL CAPS 99"]
        var design=DiscordCardDesign(id:"x",name:dice.pick(names))
        design.lineOne=(0..<dice.int(6)).map { _ in dice.pick(LineOne.allCases) }
        if design.lineOne.contains(.phrase) {
            var phrase=LinePhrase(words:dice.pick(LinePhrase.Words.allCases))
            switch dice.int(4) {
            case 1: phrase.blank = .hero(randomHero(&dice) ?? "juno")
            case 2: phrase.blank = .rank(dice.pick(CareerRank.divisions))
            case 3: phrase.blank = .role(dice.pick(CareerRank.Role.allCases))
            default: break
            }
            // A hero spelt out too long for its record travels as Auto.
            if case .hero(let key)=phrase.blank,!DiscordCardCode.heroes.contains(key),key.count > 7 { phrase.blank = .auto }
            design.phrase=phrase
        }
        design.lineTwo=(0..<dice.int(8)).map { _ in CardLine(piece:randomPiece(&dice),second:dice.coin() ? randomPiece(&dice) : nil,inMatch:dice.coin()) }
        if dice.coin() {
            design.pictures=(0..<dice.int(8)).map { _ in
                dice.int(8) == 7 ? (dice.int(3) == 0 ? .art(dice.pick(CardArt.allCases)) : .hero(randomHero(&dice) ?? "ana"))
                    : dice.pick([CardPicture.playerIcon,.lastHero,.overwatch,.rankEmblem,.recall,.roleMain,.topHeroes])
            }
        }
        design.badges=(0..<dice.int(4)).map { _ in dice.pick(CardBadge.allCases) }
        design.timer=dice.coin() ? .session : .match
        design.button=dice.pick([nil,SecondButton.careerProfile,.heroPage,.patchNotes])
        design.party=dice.pick([PartyChoice.sayVoice,.addCount,.noCount])
        design.pace=dice.coin() ? dice.pick(DiscordCardDesign.paces) : 20+dice.int(480)
        design.rank=dice.pick([RankChoice.role(.tank),.role(.damage),.role(.support),.role(.open),.highest,.lastPlayed])
        return design
    }

    static func codes() {
        func back(_ design:DiscordCardDesign)->DiscordCardDesign? { DiscordCardCode.decode(DiscordCardCode.encode(design)).map { var read=$0;read.id=design.id;return read } }
        // Every choice and the name come back exactly, for thousands of cards made at random (and the ready-made ones).
        var dice=Dice(seed:0x9E3779B97F4A7C15)
        for design in DiscordCardDesign.readyMade+(0..<5000).map({ _ in randomDesign(&dice) }) {
            precondition(DiscordCardCode.fits(design),"\(design)")
            precondition(back(design) == design,"\(design)\n\(String(describing:back(design)))\n\(DiscordCardCode.encode(design))")
        }
        // A shared name keeps no direction or invisible marks (it can't read as another), and emoji keep their joiner.
        var marked=DiscordCardDesign(id:"m",name:"evil\u{202E}cod\u{200B}e 👩\u{200D}💻")
        precondition(DiscordCardCode.decode(DiscordCardCode.encode(marked))?.name == "evilcode 👩\u{200D}💻")
        marked.name=""
        // Short: Default is five characters; a card with three lines and a short name about fifteen.
        precondition(DiscordCardCode.encode(.standard).count == 5,DiscordCardCode.encode(.standard))
        var grinder=DiscordCardDesign.readyMade[3];grinder.name="Grind"
        let code=DiscordCardCode.encode(grinder)
        precondition(code.filter { $0 != "-" }.count <= 15 && code.allSatisfy { DiscordCardCode.alphabet.contains($0) || $0 == "-" },code)
        // Read the way people type: any case, without the dashes or with spaces, O for 0 and I or L for 1.
        let plain=code.replacingOccurrences(of:"-",with:"")
        let sloppy=plain.lowercased().replacingOccurrences(of:"0",with:"o").replacingOccurrences(of:"1",with:"l")
        precondition(back(DiscordCardCode.decode(sloppy) ?? .standard)?.lineTwo == grinder.lineTwo && DiscordCardCode.decode(plain.map { String($0) }.joined(separator:" ")) != nil)
        // A mistyped character is refused, wherever it is and whatever it became: never another card.
        for (position,character) in plain.enumerated() {
            for other in DiscordCardCode.alphabet where other != character {
                var typo=Array(plain);typo[position]=other
                precondition(DiscordCardCode.decode(String(typo)) == nil,"\(plain) → \(String(typo))")
            }
        }
        // A character missing or one too many: refused.
        precondition(DiscordCardCode.decode(String(plain.dropLast())) == nil && DiscordCardCode.decode(String(plain.dropFirst())) == nil)
        for bad in ["","U","hello world","0","\(plain)Z"] { precondition(DiscordCardCode.decode(bad) == nil,bad) }
        precondition(DiscordCardCode.group("ABCDEFGHJ") == "ABCD-EFGHJ" && DiscordCardCode.group("ABCDEFGH") == "ABCD-EFGH" && DiscordCardCode.group("ABC") == "ABC")
        // The Extra pictures come back as themselves, a few characters each; a hero whose key starts with a dash (none
        // does) reads as a hero.
        var extra=DiscordCardDesign.standard;extra.pictures=CardArt.allCases.map { .art($0) }
        let letters={ (design:DiscordCardDesign) in DiscordCardCode.encode(design).filter { $0 != "-" }.count }
        precondition(back(extra) == extra && letters(extra)-letters(.standard) <= 18,DiscordCardCode.encode(extra))
        // Every title, the newest included, in its three bits.
        var titled=DiscordCardDesign.standard;titled.lineTwo=TitleLine.allCases.prefix(6).map { CardLine(piece:.title($0)) }
        precondition(back(titled) == titled)
        titled.lineTwo=[CardLine(piece:.title(.cardboardSupport))]
        precondition(back(titled) == titled && TitleLine.allCases.count <= 8)
        var odd=DiscordCardDesign.standard;odd.pictures=[.hero("-x")]
        precondition(back(odd)?.pictures == [.hero("-x")])
        frozenCodes()
        // Discord loads them from the repository, and the hover says which.
        let juno=CardPicture.art(.jetpackCat).image(inputs(),rank:.lastPlayed,turn:0)
        precondition(juno?.url.lastPathComponent == "JetpackCat.gif" && juno?.url.scheme == "https" && juno?.hover == "Jetpack Cat")
        // And it's what goes to Discord as the large image (an external address, which Discord lets be a GIF; 300
        // characters at most), with its name to point at.
        var cat=DiscordCardDesign.standard;cat.pictures=[.art(.jetpackCat)]
        let sent=assets(cat.activity(inputs()))
        precondition(sent["large_image"] == DiscordAssets.art("JetpackCat.gif").absoluteString && sent["large_text"] == "Jetpack Cat" && (sent["large_image"]?.count ?? 0) <= 300,"\(sent)")
    }
}
