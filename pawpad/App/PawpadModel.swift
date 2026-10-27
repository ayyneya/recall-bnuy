import AppKit
import Foundation
import SwiftUI

/// Pawpad's whole flow, kept small on purpose: set up (Recall's engine and a Windows
/// environment), install Aniimo's launcher with its own installer, then Play opens the launcher,
/// which starts the game. Every step runs in the worker (Helpers/pawpad-setup); this only
/// decides what to run next and what to show.
@MainActor
final class PawpadModel: ObservableObject {
    enum Screen { case checking, welcome, settingUp, installer, ready, running, failed }
    @Published var screen:Screen = .checking
    @Published var stage=""
    @Published var failure:SetupFailure?
    @Published var busy=false
    @Published var launcherInstalled=false
    @Published var gameInstalled=false
    @Published var gameRunning=false
    @Published var downloadedBytes:UInt64=0
    @Published var showAbout=false
    @Published var metalHUD=UserDefaults.standard.bool(forKey:"metalHUD") { didSet { UserDefaults.standard.set(metalHUD,forKey:"metalHUD") } }
    /// Settings › Record performance: the flight recorder (frames, freezes, crashes, the Mac's
    /// load, heat and power) for each session, and its report. On unless turned off.
    @Published var recordPerformance=UserDefaults.standard.object(forKey:"recordPerformance") as? Bool ?? true { didSet { UserDefaults.standard.set(recordPerformance,forKey:"recordPerformance") } }
    /// Settings › Show live overlay (needs Record performance): the recorder's numbers over the game.
    @Published var showOverlay=UserDefaults.standard.object(forKey:"showOverlay") as? Bool ?? true { didSet { UserDefaults.standard.set(showOverlay,forKey:"showOverlay") } }
    /// The last recorded session's headline and folder, from its report.json.
    @Published var lastReport:(headline:String,folder:URL)?

    /// The main display is a Retina display: Windows programs see its physical pixels.
    @Published var retinaDisplay=false

    let release:Release?
    let root:URL
    private let service:SetupService
    private var state:[String:Any]=[:]
    private var watcher:Task<Void,Never>?
    private let fm=FileManager.default

    init() {
        let resources=Bundle.main.resourceURL ?? Bundle.main.bundleURL
        release=(try? Data(contentsOf:resources.appendingPathComponent("release.json"))).flatMap { try? JSONDecoder().decode(Release.self,from:$0) }
        root=fm.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Brand.dataFolder)
        service=SetupService(root:root,helper:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/pawpad-setup"))
    }
    private var resources:URL { Bundle.main.resourceURL ?? Bundle.main.bundleURL }
    private var environmentReady:Bool { release != nil && state["prepared_runtime"] as? String == release?.runtimeVersion && state["active_runtime"] as? String == release?.runtimeVersion }

    // MARK: Status

    func start() {
        guard release != nil else { fail(SetupFailure(code:"release_unavailable"));return }
        perform(showProgress:false) { try await self.refresh();try await self.syncSession() }
    }
    /// Reads the worker's status and picks the screen that follows from it.
    func refresh() async throws {
        let events=try await service.run("status")
        guard let status=events.last(where:{ $0["stage"] as? String == "status" }) else { return }
        state=status["state"] as? [String:Any] ?? [:]
        launcherInstalled=status["launcher_installed"] as? Bool ?? false
        gameInstalled=status["game_installed"] as? Bool ?? false
        retinaDisplay=status["retina_display"] as? Bool ?? false
        loadLastReport()
        if screen == .running || screen == .installer { return }
        if environmentReady && launcherInstalled { screen = .ready }
        else if environmentReady && state["stage"] as? String == "installing_launcher" { screen = .installer;watchSession() }
        else { screen = .welcome }
    }
    /// The launcher or the game already running (opened before, or by the installer) shows as running.
    func syncSession() async throws {
        guard environmentReady, !service.running else { return }
        let events=try await service.run("session")
        // The game and the launcher; an installer still open on its last page doesn't count.
        let processes=((events.last(where:{ $0["stage"] as? String == "session" })?["processes"] as? [[String:Any]]) ?? [])
            .filter { ["game","client"].contains($0["kind"] as? String ?? "") }
        let wasGameRunning=gameRunning
        gameRunning=processes.contains { $0["kind"] as? String == "game" }
        if !processes.isEmpty { screen = .running;watchSession() }
        else if screen == .running { screen = launcherInstalled ? .ready : .welcome;watcher?.cancel();loadLastReport() }
        if gameRunning != wasGameRunning { loadLastReport() }
    }
    /// While something runs, look every few seconds; the running screen returns to Play when
    /// the launcher and the game have both closed.
    private func watchSession() {
        guard watcher == nil || watcher!.isCancelled else { return }
        watcher=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(4))
                guard let self, !self.busy, !self.service.running else { continue }
                if self.screen == .installer {
                    // The installer's window is Aniimo's own; Pawpad notices when it has put the launcher in place.
                    if let events=try? await self.service.run("status"),let status=events.last(where:{ $0["stage"] as? String == "status" }) {
                        self.launcherInstalled=status["launcher_installed"] as? Bool ?? false
                    }
                    if self.launcherInstalled { self.screen = .ready;try? await self.syncSession() }
                    continue
                }
                guard self.screen == .running else { break }
                try? await self.syncSession()
            }
            self?.watcher=nil
        }
    }

    // MARK: Actions

    /// The primary button: set up what's missing, or play.
    func primary() {
        switch screen {
        case .ready: play()
        case .running: focusRunning()
        case .installer: openInstaller()
        default: setUp()
        }
    }
    /// The installer step again: its window is brought forward if it's open, else opened anew
    /// from the download Pawpad already verified.
    func openInstaller() {
        guard let release else { fail(SetupFailure(code:"release_unavailable"));return }
        perform {
            self.stage=L("Opening Aniimo’s installer")
            _ = try await self.service.run("download",["--url",release.installerURL,"--sha256",release.installerSHA256])
            _ = try await self.service.run("install-launcher",["--installer",self.root.appendingPathComponent("downloads/"+release.installerSHA256).path,"--sha256",release.installerSHA256])
            self.screen = .installer
            self.watchSession()
        }
    }
    func checkInstaller() {
        perform(showProgress:false) {
            let events=try await self.service.run("status")
            if let status=events.last(where:{ $0["stage"] as? String == "status" }) { self.launcherInstalled=status["launcher_installed"] as? Bool ?? false }
            if self.launcherInstalled { self.screen = .ready;try await self.refresh();try await self.syncSession() }
            else { self.failure=SetupFailure(code:"launcher_not_installed") }
        }
    }
    func setUp() {
        guard let release else { fail(SetupFailure(code:"release_unavailable"));return }
        perform {
            self.screen = .settingUp
            self.stage=L("Checking this Mac");_ = try await self.service.run("preflight")
            try await self.refresh();self.screen = .settingUp
            if self.state["active_runtime"] as? String != release.runtimeVersion {
                self.stage=L("Installing the engine")
                _ = try await self.service.run("install-runtime",["--archive",self.resources.appendingPathComponent(release.runtimeArchive).path,"--sha256",release.runtimeSHA256,"--version",release.runtimeVersion])
                try await self.refresh();self.screen = .settingUp
            }
            if self.state["prepared_runtime"] as? String != release.runtimeVersion {
                self.stage=L("Preparing Windows (about a minute)")
                _ = try await self.service.run("prepare")
                try await self.refresh();self.screen = .settingUp
            }
            if self.launcherInstalled { self.screen = .ready;return }
            self.stage=L("Downloading Aniimo’s launcher")
            let progress=Task { @MainActor in
                while !Task.isCancelled {
                    let file=self.root.appendingPathComponent("downloads/"+release.installerSHA256+".part")
                    self.downloadedBytes=(try? self.fm.attributesOfItem(atPath:file.path)[.size] as? NSNumber)?.uint64Value ?? 0
                    try? await Task.sleep(for:.seconds(0.5))
                }
            }
            defer { progress.cancel();self.downloadedBytes=0 }
            _ = try await self.service.run("download",["--url",release.installerURL,"--sha256",release.installerSHA256])
            progress.cancel();self.downloadedBytes=0
            self.stage=L("Opening Aniimo’s installer")
            _ = try await self.service.run("install-launcher",["--installer",self.root.appendingPathComponent("downloads/"+release.installerSHA256).path,"--sha256",release.installerSHA256])
            self.screen = .installer
            self.watchSession()
        }
    }
    func play() {
        perform {
            self.stage=L("Opening Aniimo’s launcher")
            _ = try await self.service.run("launch",["--record",self.recordPerformance ? "1":"0"]+(self.metalHUD ? ["--metal-hud","1"] : []))
            self.screen = .running;self.gameRunning=false
            self.watchSession()
        }
    }
    func focusRunning() { perform(showProgress:false) { try await self.syncSession() } }
    func forceQuit() {
        let alert=NSAlert();alert.messageText=L("Force quit Aniimo and its launcher?")
        alert.informativeText=L("Use this when the game stops responding. Anything unsaved in the game is lost.")
        alert.addButton(withTitle:L("Force Quit")).hasDestructiveAction=true;alert.addButton(withTitle:L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform {
            self.stage=L("Closing Aniimo")
            _ = try await self.service.run("stop")
            self.watcher?.cancel();self.gameRunning=false;self.screen = self.launcherInstalled ? .ready : .welcome
        }
    }
    func uninstall() {
        let alert=NSAlert();alert.messageText=L("Uninstall Pawpad’s Windows environment?")
        alert.informativeText=L("Aniimo, its launcher and Pawpad’s engine move to the Trash ({0}). Your Aniimo account isn’t affected; you can put the folder back from the Trash.",root.path)
        alert.addButton(withTitle:L("Move to Trash")).hasDestructiveAction=true;alert.addButton(withTitle:L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform {
            self.stage=L("Moving to the Trash")
            _ = try await self.service.run("uninstall")
            self.watcher?.cancel();self.state=[:];self.launcherInstalled=false;self.gameInstalled=false;self.screen = .welcome
        }
    }
    /// macOS offers to install Rosetta when an Intel app opens: Helpers/Rosetta Check.app is one.
    func installRosetta() {
        NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Rosetta Check.app"),configuration:NSWorkspace.OpenConfiguration())
    }
    // MARK: Recordings

    var sessionsFolder:URL { root.appendingPathComponent("logs/sessions") }
    /// The newest session with a report (the recorder writes it when a session ends).
    func loadLastReport() {
        let folders=((try? fm.contentsOfDirectory(at:sessionsFolder,includingPropertiesForKeys:nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for folder in folders {
            guard let data=try? Data(contentsOf:folder.appendingPathComponent("report.json")),
                  let report=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { continue }
            let shown=report["frames_on_screen"] as? [String:Any] ?? [:]
            let headline:String
            if let fps=shown["average_fps"] {
                headline=L("{0} FPS average · 1% low {1} · {2} stutters a minute · {3} freezes","\(fps)","\(shown["low_1pct_fps"] ?? "–")","\(shown["stutters_50ms_per_minute"] ?? "–")","\(shown["freezes_500ms"] ?? 0)")
            } else { headline=L("No frames of the game reached the screen.") }
            lastReport=(headline,folder);return
        }
        lastReport=nil
    }
    func showLastReport() {
        guard let folder=lastReport?.folder else { return }
        NSWorkspace.shared.open(folder.appendingPathComponent("report.md"))
    }
    func showRecordings() {
        try? fm.createDirectory(at:sessionsFolder,withIntermediateDirectories:true)
        NSWorkspace.shared.open(lastReport?.folder ?? sessionsFolder)
    }
    /// A marker on the running session's timeline, so the report can say when something happened.
    func addMarker() {
        let alert=NSAlert();alert.messageText=L("Add a marker to this recording")
        alert.informativeText=L("Say what is about to happen, for example “entering the world”.")
        let field=NSTextField(frame:NSRect(x:0,y:0,width:280,height:24));alert.accessoryView=field
        alert.addButton(withTitle:L("Add Marker"));alert.addButton(withTitle:L("Cancel"))
        alert.window.initialFirstResponder=field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label=String(field.stringValue.filter { $0.isLetter || $0.isNumber || " ._:()-".contains($0) }.prefix(80))
        guard !label.isEmpty else { return }
        perform(showProgress:false) { _ = try await self.service.run("mark",["--label",label]) }
    }

    func cancel() { service.cancel() }
    var canCancel:Bool { busy && screen == .settingUp }

    // MARK: Helpers

    private func perform(showProgress:Bool=true,_ work:@escaping () async throws -> Void) {
        guard !busy else { return }
        busy=showProgress;failure=nil
        Task {
            do { try await work() }
            catch let error as SetupFailure { fail(error) }
            catch { fail(SetupFailure(code:"unexpected")) }
            busy=false;stage=""
        }
    }
    private func fail(_ error:SetupFailure) {
        failure=error
        if error.code == "cancelled" { screen = .welcome;return }
        if screen == .settingUp || screen == .checking { screen = .failed }
    }
}
