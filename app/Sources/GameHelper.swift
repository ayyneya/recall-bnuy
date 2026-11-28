import AppKit
import Network
import Observation
import Security
import ServiceManagement
import os

/// Steady Wi-Fi and fan speed (Settings › Graphics), the two settings that need root, done by
/// Recall's helper (app/Helper/main.swift) while Overwatch is open:
///
/// - Steady Wi-Fi: on Wi-Fi, the helper holds awdl0 and llw0 down, the Apple wireless links
///   (AirDrop, Handoff, Sidecar) that make the radio leave the router's channel and the game's
///   ping spike. Not needed on Ethernet.
/// - Fan speed: every fan runs at the chosen share of its range. Read from the Mac itself, so a
///   Mac without fans shows the setting grayed out and never adds the helper for it.
///
/// Both are off until the player turns one on, which adds the helper (macOS asks once, in
/// System Settings › General › Login Items & Extensions); turning both off removes it. Recall
/// connects to the helper only while it has something to do, and the helper puts everything
/// back and exits when the connection ends, so a crash leaves nothing behind. Nothing polls:
/// macOS reports the network, apps opening and closing, and sleep.
@MainActor @Observable
final class GameHelper {
    enum Approval { case notAdded, needsApproval, ready, unavailable }
    private(set) var approval:Approval = .notAdded
    /// The helper stopped answering twice in a row.
    private(set) var notAnswering=false

    var steadyWiFi=UserDefaults.standard.bool(forKey:"steadyWiFi") {
        didSet { UserDefaults.standard.set(steadyWiFi,forKey:"steadyWiFi");turned(steadyWiFi) }
    }
    var fansWhilePlaying=UserDefaults.standard.bool(forKey:"fansWhilePlaying") {
        didSet { UserDefaults.standard.set(fansWhilePlaying,forKey:"fansWhilePlaying");turned(fansWhilePlaying) }
    }
    /// 0 is each fan's minimum speed, 100 its maximum. Set when the slider is let go.
    var fanPercent=UserDefaults.standard.object(forKey:"fanPercent") as? Double ?? 100 {
        didSet { UserDefaults.standard.set(fanPercent,forKey:"fanPercent");sync() }
    }
    /// This Mac's fans, read once: none on a MacBook Air or another Mac without fans.
    let fans:[SMC.Fan]=SMC()?.fans ?? []
    var hasFans:Bool { !fans.isEmpty }

    /// Overwatch runs, as the session says (AppModel); with Game Mode on, its own app says so too.
    var sessionGame=false { didSet { if sessionGame != oldValue { sync() } } }
    private(set) var onWiFi=false
    private(set) var wiFiHeld=false
    private(set) var fansSet=false
    var gameRunning:Bool { sessionGame || gameApp }

    @ObservationIgnored private let service=SMAppService.daemon(plistName:RecallHelperNames.label+".plist")
    @ObservationIgnored private var lookForGame:(()->Void)?
    @ObservationIgnored private var begun=false
    @ObservationIgnored private var gameApp=false { didSet { if gameApp != oldValue { sync() } } }
    @ObservationIgnored private var asleep=false
    @ObservationIgnored private var monitor:NWPathMonitor?
    @ObservationIgnored private var observers:[(NotificationCenter,NSObjectProtocol)]=[]
    @ObservationIgnored private var connection:NSXPCConnection?
    @ObservationIgnored private var sentWiFi=false
    @ObservationIgnored private var sentFans:Double?
    @ObservationIgnored private var losses=0
    @ObservationIgnored private let logger=Logger(subsystem:RecallHelperNames.appIdentifier,category:"helper")
    nonisolated static let gameBundleID="org.overwatch2mac.overwatch"

    /// Starts following the game, the network and the helper's approval, if either setting is on.
    /// `lookForGame` asks the session whether Overwatch is open (Game Mode off: only Wine's loader).
    func begin(lookForGame:@escaping ()->Void) {
        self.lookForGame=lookForGame;begun=true
        // On, but not in Login Items (removed there, or a new copy of Recall): added again quietly.
        if wanted && service.status == .notRegistered { add(asking:false) } else { refreshApproval() }
        follow()
    }
    private var wanted:Bool { steadyWiFi || (fansWhilePlaying && hasFans) }
    private func turned(_ on:Bool) {
        guard begun else { return }
        losses=0;notAnswering=false
        if on && approval != .ready { add(asking:true) }
        if !wanted {
            release()
            Task { try? await service.unregister();refreshApproval() }
        }
        follow()
    }
    /// The helper into Login Items & Extensions. macOS asks the player to allow it there;
    /// `asking` opens that page for them.
    private func add(asking:Bool) {
        if service.status != .enabled && service.status != .requiresApproval {
            do { try service.register() } catch { logger.error("register: \(error.localizedDescription, privacy:.public)") }
        }
        refreshApproval()
        if asking && approval == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
    private func refreshApproval() {
        switch service.status {
        case .enabled: approval = .ready
        case .requiresApproval: approval = .needsApproval
        case .notFound: approval = .unavailable
        default: approval = wanted ? .unavailable : .notAdded
        }
    }

    /// Notifications and the network monitor only while a setting is on.
    private func follow() {
        guard wanted else {
            observers.forEach { $0.0.removeObserver($0.1) };observers=[]
            monitor?.cancel();monitor=nil;onWiFi=false
            return
        }
        if steadyWiFi && monitor == nil {
            let monitor=NWPathMonitor()
            monitor.pathUpdateHandler={ [weak self] path in
                let wifi=Self.carriesWiFi(path)
                Task { @MainActor in self?.onWiFi=wifi;self?.sync() }
            }
            monitor.start(queue:.main);self.monitor=monitor
        } else if !steadyWiFi { monitor?.cancel();monitor=nil;onWiFi=false }
        if observers.isEmpty {
            let workspace=NSWorkspace.shared.notificationCenter
            func watch(_ center:NotificationCenter,_ name:Notification.Name,_ action:@escaping @MainActor (Notification)->Void) {
                observers.append((center,center.addObserver(forName:name,object:nil,queue:.main) { note in
                    MainActor.assumeIsolated { action(note) }
                }))
            }
            watch(workspace,NSWorkspace.didLaunchApplicationNotification) { [weak self] note in self?.appOpened(note) }
            watch(workspace,NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
                if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Self.gameBundleID { self?.gameApp=false }
            }
            watch(workspace,NSWorkspace.willSleepNotification) { [weak self] _ in self?.asleep=true;self?.sync() }
            watch(workspace,NSWorkspace.didWakeNotification) { [weak self] _ in self?.asleep=false;self?.sync() }
            // Back from System Settings, perhaps having allowed the helper.
            watch(NotificationCenter.default,NSApplication.didBecomeActiveNotification) { [weak self] _ in self?.refreshApproval();self?.sync() }
            gameApp=NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.gameBundleID }
        }
        sync()
    }
    private func appOpened(_ note:Notification) {
        guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == Self.gameBundleID { gameApp=true }
        else if app.executableURL?.lastPathComponent == "wine" && !gameApp { lookForGame?() }
    }
    /// Wi-Fi carries the traffic: not Ethernet, and a VPN counts as whatever it runs over.
    nonisolated static func carriesWiFi(_ path:NWPath)->Bool {
        guard path.status == .satisfied,!path.usesInterfaceType(.wiredEthernet) else { return false }
        if path.usesInterfaceType(.wifi) { return true }
        return path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }?.type == .wifi
    }

    /// What the helper should be doing now, sent when it changes.
    private func sync() {
        guard begun else { return }
        let wiFi=steadyWiFi && onWiFi && gameRunning && !asleep
        let fanSpeed=fansWhilePlaying && hasFans && gameRunning && !asleep ? fanPercent : nil
        guard approval == .ready,wiFi || fanSpeed != nil else { release();return }
        let helper=connect()
        if wiFi != sentWiFi {
            sentWiFi=wiFi
            helper?.setWiFiHeld(wiFi) { [weak self] held in Task { @MainActor in self?.wiFiHeld=held;self?.losses=0 } }
        }
        if fanSpeed != sentFans {
            sentFans=fanSpeed
            helper?.setFanPercent(fanSpeed ?? -1) { [weak self] set in Task { @MainActor in self?.fansSet=set && fanSpeed != nil;self?.losses=0 } }
        }
    }
    private func connect()->RecallHelperProtocol? {
        if connection == nil {
            let c=NSXPCConnection(machServiceName:RecallHelperNames.label,options:.privileged)
            c.remoteObjectInterface=NSXPCInterface(with:RecallHelperProtocol.self)
            if let team=Self.team {
                c.setCodeSigningRequirement("identifier \"\(RecallHelperNames.helperIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
            }
            c.invalidationHandler={ [weak self] in Task { @MainActor in self?.lost(c) } }
            c.interruptionHandler={ [weak self] in Task { @MainActor in self?.lost(c) } }
            c.resume();connection=c
            sentWiFi=false;sentFans=nil
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in if let c=self?.connection { self?.lost(c) } }
        } as? RecallHelperProtocol
    }
    /// The helper ended (crashed, or was removed in System Settings): it put everything back.
    /// One more try; a second loss in a row says so in Settings.
    private func lost(_ c:NSXPCConnection) {
        guard connection === c else { return }
        connection=nil;c.invalidate()
        wiFiHeld=false;fansSet=false
        losses+=1;notAnswering=losses >= 2
        refreshApproval()
        if losses < 2 { sync() }
    }
    /// Closing the connection is the helper's sign to put everything back and exit.
    private func release() {
        guard let c=connection else { return }
        connection=nil;c.invalidate()
        sentWiFi=false;sentFans=nil;wiFiHeld=false;fansSet=false
    }

    /// The team that signed Recall, which signed the helper too. Nil in an unsigned build.
    nonisolated static let team:String? = {
        var code:SecCode?
        var info:CFDictionary?
        guard SecCodeCopySelf([],&code) == errSecSuccess,let code,
              SecCodeCopySigningInformation(unsafeBitCast(code,to:SecStaticCode.self),SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess
        else { return nil }
        return (info as? [String:Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }()
}
