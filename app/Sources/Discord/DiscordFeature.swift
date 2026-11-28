import AppKit

// The Discord card's place in Recall: AppModel's hooks start it and tell it what the worker and the game do; this keeps
// the card, the profile and its history, and Settings › Discord in step.

@MainActor final class DiscordFeature {
    /// What Discord shows while Overwatch runs: Basic, Live, Full or Custom; the power button turns it off
    /// (presencePower).
    var level=DiscordFeature.storedLevel {
        didSet {
            if !gone { UserDefaults.standard.set(level.rawValue,forKey:"discordPresenceLevel") }
            presence.update(level:level,texts:PresenceTexts.app)
            if studio.level != level { studio.level=level }
            checkPresence()
            // Full or Custom chosen while the game runs: the profile, if it's time to look (CareerProfile keeps the pace).
            if usesProfile && presencePid != nil { lookUpCareer() }
        }
    }
    private var usesProfile:Bool { level == .full || level == .custom }
    /// Full and Custom: the BattleTag ("Name#1234"), typed once. Only OverFast gets it.
    var battleTag=UserDefaults.standard.string(forKey:"battleTag") ?? ""
    private let career=CareerProfile(base:DiscordFeature.storedServer,history:DiscordFeature.careerHistory)
    /// What Recall remembers (CareerHistory.swift): the profile writes it, the card reads it.
    nonisolated private static let careerHistory=CareerHistoryStore(url:CareerHistoryStore.standardURL)
    /// The OverFast server: the public one, unless support set another (defaults write org.overwatch2mac.launcher
    /// overFastServer https://…). One that isn't a server means no lookups, never the public one.
    nonisolated private static var storedServer:URL? {
        let text=UserDefaults.standard.string(forKey:"overFastServer") ?? ""
        return text.trimmingCharacters(in:.whitespaces).isEmpty ? OverFast.standard : OverFast.server(text)
    }
    /// What Recall remembers › Erase: sessions and history go; the profile comes back with the next look.
    func eraseCareerHistory() {
        erasesWaiting+=1;erases+=1
        // The game going on is recorded only from now.
        presence.erased(at:Date())
        career.erase { [weak self] kept in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.erasesWaiting-=1;self.erasedCopy=kept
                    // A look that was on its way meanwhile told the card what's now erased.
                    self.presence.update(career:nil,tagName:self.tagName)
                }
            }
        }
        presence.update(career:nil,tagName:tagName)
        refreshStudio()
    }
    /// Undo: what the erase took, kept in memory for its ten seconds, goes back on disk.
    private func restoreErased() {
        guard let kept=erasedCopy else { return }
        erasedCopy=nil;presence.erased(at:nil)
        career.restore(kept) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshStudio();self?.lookUpCareer() } }
        }
    }
    private var erasedCopy:CareerProfile.Erased?
    /// Erases so far: a look that started before one is let go when it comes back.
    private var erases=0
    /// Erases handed to the profile's queue and not done yet: a look can hold it for seconds.
    private var erasesWaiting=0
    /// Recall is quitting: an erase still waiting to be undone, or still queued, happens now, before Recall goes.
    func quitting() {
        studio.finishSweep()
        // The game still running: its run so far goes into the history now (Recall reopening takes it up again).
        if presencePid != nil { presence.sessionEnded={ [career] in career.sessionEndedNow($0) };stopPresence() }
        // An erase still queued behind a look happens now, before Recall goes.
        studio.eraseTimer?.cancel()
        guard erasesWaiting > 0 else { return }
        career.eraseNow()
    }
    /// Uninstalled: the history's folder goes to the Trash with the player's cards (never the BattleTag), so Put Back
    /// restores them. Nothing more is looked up, sent or written.
    func uninstalled() {
        quitting()
        gone=true;afterQuit?.cancel();afterQuit=nil;battleTag="";studio.battleTag="";watchRuns()
        career.close();checkPresence()
        let folder=CareerHistoryStore.standardURL.deletingLastPathComponent()
        if let data=try? JSONEncoder().encode(KeptCards(cards:studio.shelf,unlocked:studio.unlocked.sorted())) {
            try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try? data.write(to:Self.keptCardsURL,options:.atomic)
        }
        try? FileManager.default.trashItem(at:folder,resultingItemURL:nil)
    }
    private var gone=false
    /// The cards an uninstall kept next to the history, for Put Back.
    private struct KeptCards: Codable { var cards:DiscordCardShelf;var unlocked:[String] }
    nonisolated private static var keptCardsURL:URL { CareerHistoryStore.standardURL.deletingLastPathComponent().appendingPathComponent("discord-cards.json") }
    /// The player's cards: from the settings, or (after Uninstall and Put Back) from the file the uninstall kept.
    private static func storedShelf()->DiscordCardShelf {
        let store=UserDefaults.standard
        guard store.data(forKey:"discordCards") == nil,let data=try? Data(contentsOf:keptCardsURL),
              let kept=try? JSONDecoder().decode(KeptCards.self,from:data) else { return .load() }
        kept.cards.save()
        if store.stringArray(forKey:"discordUnlocked") == nil { store.set(kept.unlocked,forKey:"discordUnlocked") }
        try? FileManager.default.removeItem(at:keptCardsURL)
        return kept.cards
    }
    /// The first account signed in with a BattleTag set takes the profile; Settings says when another is signed in.
    private func accountSignedIn(_ account:String?) {
        guard let account,!battleTag.isEmpty,!gone else { return }
        let store=UserDefaults.standard
        if store.string(forKey:"discordAccount") == nil { store.set(account,forKey:"discordAccount");presence.owner=account }
        studio.otherAccount=store.string(forKey:"discordAccount") != account
    }
    /// Your profile › Look up: kept and looked up once; empty (Remove) takes the profile off the card. The old
    /// profile's history goes only once another player is found.
    func commitBattleTag(_ text:String) {
        let tag=BattleTag.clean(text)
        guard !gone else { return }
        guard tag != battleTag else { lookUpCareer(asked:true);return }
        battleTag=tag;UserDefaults.standard.set(tag,forKey:"battleTag")
        // The new BattleTag belongs to whichever Discord account is signed in next.
        UserDefaults.standard.removeObject(forKey:"discordAccount");studio.otherAccount=false;presence.owner=nil
        presence.update(career:nil,tagName:tagName)
        // The old tag's look, if one is on its way, is not waited for (lookUpCareer drops its answer).
        studio.battleTag=tag;studio.profile=nil;studio.profileState = .none;studio.lookedUp=nil;studio.lookAgainAt=nil;studio.lookingUp=false
        lookUpCareer(asked:true)
        refreshStudio()
    }
    /// Looks up as the game opens, after it closes, as Recall opens with sessions waiting, and when the player asks.
    /// CareerProfile keeps its own pace.
    private func lookUpCareer(asked:Bool=false) {
        guard usesProfile || asked,!battleTag.isEmpty,presenceAllowed else { return }
        let tag=battleTag
        studio.lookingUp=true
        let erasesBefore=erases
        career.lookUp(tag:tag) { [weak self,career] status,card in
            let catchUp=career.catchUp
            Task { @MainActor in
                // A BattleTag entered meanwhile has its own look coming; one erased meanwhile is let go.
                guard let self,tag == self.battleTag else { return }
                guard erasesBefore == self.erases else { self.studio.lookingUp=false;return }
                self.presence.update(career:card,tagName:self.tagName)
                self.studio.lookingUp=false
                switch status {
                case .notPublic(let until),.notFound(let until),.busy(let until): self.studio.lookAgainAt=until
                default: self.studio.lookAgainAt=nil
                }
                self.studio.offline=(status == .unreachable || status == .unavailable) && card == nil
                if case .busy=status { self.studio.busy=true } else { self.studio.busy=false }
                // The profile hasn't caught up with the game that closed: one more look then (twice at most).
                if let catchUp,self.presencePid == nil,self.catchUps < 2 { self.catchUps+=1;self.lookAfterQuit(at:catchUp) }
                self.refreshStudio()
            }
        }
    }

    /// Settings › Discord's state, kept current here.
    let studio=DiscordStudio(shelf:DiscordFeature.storedShelf())
    /// What only Recall knows: whether the card may show (not where Discord is blocked, nor in a preview), the game's
    /// folder, and its look at the game's processes.
    private var recall:(allowed:()->Bool,root:()->URL,lookForGame:()->Void)?
    /// Recall opens: Settings › Discord starts from what Recall keeps, and every change to the cards goes to the card.
    func start(allowed:@escaping ()->Bool,root:@escaping ()->URL,lookForGame:@escaping ()->Void) {
        recall=(allowed,root,lookForGame)
        studio.level=level;studio.power=presencePower;studio.battleTag=battleTag;studio.texts=PresenceTexts.app
        studio.changed={ [weak self] shelf in guard self?.gone == false else { return };shelf.save();self?.presence.update(design:shelf.inUse) }
        studio.actions=DiscordStudio.Actions(level:{ [weak self] in self?.level=$0 },
                                             power:{ [weak self] in self?.setPresencePower($0) },
                                             battleTag:{ [weak self] in self?.commitBattleTag($0) },
                                             lookAgain:{ [weak self] in self?.lookUpCareer(asked:true) },
                                             erase:{ [weak self] in self?.eraseCareerHistory() },
                                             restore:{ [weak self] in self?.restoreErased() },
                                             forget:{ [weak self] in self?.erasedCopy=nil },
                                             export:{ [weak self] in self?.exportSessions() })
        presence.update(design:studio.design)
        // Support's defaults write while Recall runs: the power button follows it.
        powerWatch=UserDefaults.standard.observe(\.discordPresence) { [weak self] _,_ in
            Task { @MainActor in self?.powerFollowed() }
        }
        // The profile belongs to the Discord account signed in when the BattleTag was entered; another account
        // gets no profile.
        presence.owner=UserDefaults.standard.string(forKey:"discordAccount")
        presence.signedIn={ [weak self] account in DispatchQueue.main.async { MainActor.assumeIsolated { self?.accountSignedIn(account) } } }
        // The Mac asleep with the game open isn't play (DiscordPresence.slept).
        let center=NSWorkspace.shared.notificationCenter
        sleepWatch=[center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.fellAsleep=Date() } },
                    center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self,let from=self.fellAsleep else { return }
                            self.fellAsleep=nil;self.presence.slept(from:from,to:Date())
                        } }]
        // Recall quitting (DiscordFeature.quitting), and Overwatch opening and closing from here on.
        sleepWatch.append(NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.quitting() } })
        presence.sessionEnded={ [career] in career.sessionEnded($0) }
        // Esc held on Discord's pages steps back once; its repeats go nowhere until the key comes up.
        escapeWatch=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]) { [weak self] event in
            guard event.keyCode == 53,let self else { return event }
            let up=event.type == .keyUp,again=event.isARepeat
            let passes=MainActor.assumeIsolated { () -> Bool in
                if up { self.escapeHeld=false;return true }
                if again { return !self.escapeHeld }
                self.escapeHeld=self.studio.open
                return true
            }
            return passes ? event : nil
        }
        followRuns()
        // The preview follows the game while it runs.
        presence.gameChanged={ [weak self] live in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.studio.live=live } }
        }
        refreshStudio()
    }
    /// Settings shows what the profile and history hold now, read on the profile's queue.
    private func refreshStudio() {
        let tag=battleTag
        career.kept(tag:tag) { [weak self] status,card,asked in
            let history=DiscordFeature.careerHistory.current
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self,tag == self.battleTag else { return }
                    let studio=self.studio
                    // Sessions on screen for their ten seconds to undo an erase stay as they are.
                    if studio.erased != nil { studio.erased=history } else { studio.history=history }
                    studio.lookedUp=asked
                    switch status {
                    case .notPublic: studio.profileState = .hidden;studio.profile=nil
                    case .notFound: studio.profileState = .missing;studio.profile=nil
                    default: studio.profileState=tag.isEmpty || card == nil ? .none : .shown;studio.profile=card
                    }
                    if let card { DiscordStudio.heroNames=card.heroes.mapValues(\.name) }
                }
            }
        }
    }
    /// The power button: off, nothing runs. Support: defaults write org.overwatch2mac.launcher discordPresence -bool
    /// false
    private var presencePower:Bool { UserDefaults.standard.object(forKey:"discordPresence") as? Bool ?? true }
    private var powerWatch:NSKeyValueObservation?
    private var sleepWatch:[NSObjectProtocol]=[]
    private var escapeWatch:Any?
    private var escapeHeld=false
    private var fellAsleep:Date?
    private func powerFollowed() {
        guard studio.power != presencePower else { return }
        studio.power=presencePower;watchRuns();checkPresence()
    }
    private func setPresencePower(_ on:Bool) {
        guard !gone else { return }
        UserDefaults.standard.set(on,forKey:"discordPresence")
        watchRuns();checkPresence()
        if on && presencePid != nil { lookUpCareer() }
    }
    /// What Recall remembers › Export: the sessions as a spreadsheet in Downloads; nil when it couldn't be written.
    private func exportSessions()->URL? {
        let csv=studio.history.csv(heroes:studio.profile?.heroes ?? [:])
        guard let downloads=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first else { return nil }
        let name=L("{0} sessions",Brand.name)
        var url=downloads.appendingPathComponent(name+".csv"),copy=2
        while FileManager.default.fileExists(atPath:url.path) { url=downloads.appendingPathComponent("\(name) \(copy).csv");copy+=1 }
        do { try Data(csv.utf8).write(to:url,options:.withoutOverwriting) } catch { return nil }
        return url
    }
    nonisolated private static var storedLevel:DiscordPresenceLevel {
        let store=UserDefaults.standard
        guard let kept=store.string(forKey:"discordPresenceLevel") else {
            // An update from a Recall without the card starts at Basic, a new install at Live. Decided once.
            let level:DiscordPresenceLevel=store.string(forKey:"lastLaunchedVersion") != nil ? .normal : .standard
            store.set(level.rawValue,forKey:"discordPresenceLevel")
            return level
        }
        // A level this Recall doesn't know (a newer one's) shows least.
        return DiscordPresenceLevel(rawValue:kept) ?? .normal
    }
    /// Overwatch's own app, which macOS shows as running while the game does (game_mode_app.py).
    nonisolated static let gameBundleID="org.overwatch2mac.overwatch"
    nonisolated static func runningGame()->pid_t? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == gameBundleID }?.processIdentifier
    }
    private let presence=DiscordPresence(level:DiscordFeature.storedLevel,texts:PresenceTexts.app,history:DiscordFeature.careerHistory)
    /// The BattleTag's name (before the #), for line 1 at Full while the profile has none.
    private var tagName:String? { BattleTag.playerID(battleTag).flatMap { $0.split(separator:"-").first.map(String.init) } }
    /// Discord is blocked in mainland China, and previews never touch Discord. The region is known once the status is
    /// read.
    private var presenceAllowed:Bool { !gone && presencePower && statusRead && recall?.allowed() == true }
    private var statusRead=false
    private var lookedAtLaunch=false
    /// The game process the card was started for, and macOS's report of its end (a process dispatch source).
    private var presencePid:pid_t?
    private var presenceExit:DispatchSourceProcess?
    /// The run that just ended: macOS can list its app for a moment after the process is gone.
    private var presenceEnded:pid_t?
    /// The game's app, unless it is the run that just ended.
    private var runningGame:pid_t? { Self.runningGame().flatMap { $0 == presenceEnded ? nil : $0 } }
    /// The running apps changed: the game's app puts the card up. With Game Mode off there's only Wine's loader, so a
    /// new Wine app has Recall look.
    private func runningAppsChanged() {
        let wine=Self.wineApps(),new = !wine.subtracting(wineSeen).isEmpty
        wineSeen=wine
        if let game=runningGame { syncPresence(game:game) } else if new && presencePid == nil && presenceAllowed { recall?.lookForGame() }
    }
    private var wineSeen:Set<pid_t>=[]
    nonisolated private static func wineApps()->Set<pid_t> {
        Set(NSWorkspace.shared.runningApplications.filter { $0.executableURL?.lastPathComponent == "wine" }.map(\.processIdentifier))
    }
    /// Whether the card may show changed: the card or the game is looked at again.
    private func checkPresence() { syncPresence(game:presencePid ?? runningGame) }
    /// The card follows the game; `game` is its process, nil when it isn't running.
    private func syncPresence(game:pid_t?) {
        guard let game else { stopPresence();return }
        // Off or not allowed while the game runs: the card comes down, but the run is still followed into the history.
        // No run starts while off.
        guard presenceAllowed else { if presencePid == game { presence.update(quiet:true) };return }
        // This game's card is up already (every app opening or closing on the Mac comes here).
        if presencePid == game { presence.update(quiet:false);return }
        // Another run of the game: its own timer and log, from the start.
        stopPresence()
        presencePid=game
        // A look still waiting for the last run (a crash and quick relaunch) happens at the latest ten minutes after
        // this run's look.
        if afterQuit != nil { lookAfterQuit(at:Date().addingTimeInterval(CareerProfile.fresh)) }
        let exit=DispatchSource.makeProcessSource(identifier:game,eventMask:.exit,queue:.main)
        exit.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.presenceGameEnded(game) } }
        exit.resume();presenceExit=exit
        presence.begin(logURL:OverwatchLogTail.logURL(root:recall!.root()),launched:DiscordPresence.startTime(of:game) ?? NSRunningApplication(processIdentifier:game)?.launchDate)
        // The game opening is when the profile tells the session before this one.
        lookUpCareer()
        // A process that ended before the watch was set up never reports.
        if kill(game,0) != 0 && errno == ESRCH { presenceGameEnded(game) }
    }
    /// `ran` is false when the card comes down while the game goes on.
    private func stopPresence() {
        presenceExit?.cancel();presenceExit=nil;presencePid=nil
        presence.end()
    }
    /// The game the card was for has ended: the card comes down, unless another run is up already.
    private func presenceGameEnded(_ pid:pid_t) {
        guard presencePid == pid else { return }
        presenceEnded=pid;stopPresence();studio.tonightEnded()
        // The run is in the history now (on the profile's queue, which the read waits for).
        refreshStudio()
        // Blizzard updates the profile after the game closes: one more look later finds the session that just ended.
        catchUps=0
        lookAfterQuit(at:Date().addingTimeInterval(Self.afterQuitDelay))
        runningAppsChanged()
    }
    private func lookAfterQuit(at date:Date) {
        let look=DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.afterQuit=nil;self?.studio.nextLook=nil;self?.lookUpCareer() } }
        afterQuit?.cancel();afterQuit=look
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0,date.timeIntervalSinceNow),execute:look)
        if usesProfile && !battleTag.isEmpty { studio.nextLook=date }
    }
    /// By then Blizzard has usually updated. OverFast serves its copy up to half an hour, so a look that finds it
    /// behind asks again when it's due (CareerProfile.catchUp).
    nonisolated static let afterQuitDelay:TimeInterval=12*60
    private var afterQuit:DispatchWorkItem?
    private var catchUps=0

    /// The status is read, so the region is known: the card follows it, and waiting sessions get a look.
    func statusKnown() {
        statusRead=true;checkPresence()
        if !lookedAtLaunch {
            lookedAtLaunch=true
            if usesProfile && presencePower && Self.careerHistory.current.waiting.contains(where:{ $0.matches != 0 }) { lookUpCareer() }
        }
    }
    /// Overwatch opens: macOS posts no launch for it (Wine starts it), but the running apps change with the game's app
    /// among them. A game already running is found once the status is read.
    private func followRuns() { following=true;watchRuns() }
    /// Off means off: running apps are watched only while the card is on.
    private func watchRuns() {
        guard following,presencePower,!gone else { runningObservation=nil;return }
        guard runningObservation == nil else { return }
        wineSeen=Self.wineApps()
        runningObservation=NSWorkspace.shared.observe(\.runningApplications) { [weak self] _,_ in
            Task { @MainActor in self?.runningAppsChanged() }
        }
    }
    private var following=false
    private var runningObservation:NSKeyValueObservation?
    /// Recall's look at the game's processes. A list read as the game closed can still name it: that run is over.
    func sessionSeen(_ processes:[[String:Any]]) {
        sawSessions=true
        let game=processes.first { $0["kind"] as? String == "game" }.flatMap { ($0["pid"] as? NSNumber)?.int32Value }
        let listed=game.flatMap { $0 == presenceEnded || kill($0,0) != 0 && errno == ESRCH ? nil : $0 }
        syncPresence(game:runningGame ?? listed)
    }
    /// Which of Recall's hooks have run: one lost in a merge shows here.
    private var sawSessions=false
    /// Support's report: level, power, Discord's answers, the card in use and how many are the player's own, whether a
    /// BattleTag is set, OverFast's last answer; never names, the tag or what a card shows.
    var report:[String:Any] {
        let shelf=studio.shelf,profile:[String:Any]=["battletag_set":!battleTag.isEmpty,"last_code":career.lastCode.map { $0 as Any } ?? "none"]
        let server=UserDefaults.standard.string(forKey:"overFastServer")?.trimmingCharacters(in:.whitespaces) ?? ""
        return ["v":1,"wired":["start":recall != nil,"status":statusRead,"sessions":sawSessions],"level":level.rawValue,"power":presencePower ? "on" : "off","allowed":presenceAllowed,"connected":presence.connected,
                "accepted":presence.accepted,"last_answer":presence.lastAnswer ?? "none","log":presence.logReport,
                "app_id":DiscordAssets.applicationID == DiscordAssets.standardID ? "default" : "custom","discord_app":DiscordAssets.listing ?? "unknown",
                "server":server.isEmpty ? "standard" : OverFast.server(server) == nil ? "invalid" : "custom",
                "card":shelf.inUse.readyMade ? shelf.inUse.id : "own","own_cards":shelf.mine.count,"career_profile":profile]
    }
}
private extension UserDefaults {
    /// The power button's key, for observing it.
    @objc dynamic var discordPresence:Bool { bool(forKey:"discordPresence") }
}
