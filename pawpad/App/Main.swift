import AppKit
import SwiftUI
import Darwin

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model=PawpadModel()
    var window:NSWindow!
    var overlay:OverlayController?
    var lockFD:Int32 = -1
    func applicationDidFinishLaunching(_ notification:Notification) {
        // One Pawpad at a time: a second copy (open -n, another bundle) brings the first forward.
        let lockDirectory=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent(Brand.bundleIdentifier)
        try? FileManager.default.createDirectory(at:lockDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        lockFD=open(lockDirectory.appendingPathComponent("app.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        if lockFD<0 || flock(lockFD,LOCK_EX|LOCK_NB) != 0 {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "") where app.processIdentifier != ProcessInfo.processInfo.processIdentifier { app.activate(options:[]) }
            NSApp.terminate(nil);return
        }
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:720),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title=Brand.name;window.titlebarAppearsTransparent=true;window.titleVisibility = .hidden
        window.isReleasedWhenClosed=false;window.minSize=NSSize(width:480,height:560)
        window.contentView=NSHostingView(rootView:PawpadView(model:model))
        window.center();window.makeKeyAndOrderFront(nil)
        overlay=OverlayController(model:model)
        NSApp.mainMenu=menu();NSApp.activate(ignoringOtherApps:true)
    }
    func menu()->NSMenu {
        let main=NSMenu(),app=NSMenu(),top=NSMenuItem();main.addItem(top);top.submenu=app
        func add(_ title:String,_ action:Selector,_ key:String="",to menu:NSMenu?=nil) { let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.target=self;(menu ?? app).addItem(item) }
        add(L("About {0}",Brand.name),#selector(about))
        app.addItem(.separator())
        add(L("Play Aniimo"),#selector(play),"p")
        add(L("Force Quit Aniimo…"),#selector(forceQuit))
        app.addItem(.separator())
        let marker=NSMenuItem(title:L("Add Marker…"),action:#selector(addMarker),keyEquivalent:"m");marker.keyEquivalentModifierMask=[.command,.shift];marker.target=self;app.addItem(marker)
        add(L("Show Last Report"),#selector(showLastReport))
        add(L("Show Recordings"),#selector(showRecordings))
        app.addItem(.separator())
        add(L("Uninstall…"),#selector(uninstall))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title:L("Hide {0}",Brand.name),action:#selector(NSApplication.hide(_:)),keyEquivalent:"h"))
        add(L("Quit {0}",Brand.name),#selector(quit),"q")
        let windowItem=NSMenuItem();main.addItem(windowItem);let wm=NSMenu(title:L("Window"));windowItem.submenu=wm
        wm.addItem(NSMenuItem(title:L("Minimize"),action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        wm.addItem(NSMenuItem(title:L("Close"),action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"))
        NSApp.windowsMenu=wm
        return main
    }
    @objc func about() { show();model.showAbout=true }
    @objc func play() { show();if model.screen == .ready { model.play() } }
    @objc func forceQuit() { show();model.forceQuit() }
    @objc func uninstall() { show();model.uninstall() }
    @objc func addMarker() { model.addMarker() }
    @objc func showLastReport() { model.loadLastReport();model.showLastReport() }
    @objc func showRecordings() { model.showRecordings() }
    @objc func quit() { NSApp.terminate(nil) }
    func show() { window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    func applicationDidBecomeActive(_ notification:Notification) {
        if model.screen == .ready || model.screen == .running { model.focusRunning() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool { show();return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    /// Quitting during setup pauses the step first (its finished parts are kept); the launcher
    /// and the game keep running without Pawpad.
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        model.cancel()
        Task { while model.busy { try? await Task.sleep(for:.milliseconds(100)) };sender.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
}
@main struct PawpadMain {
    @MainActor static func main() {
        let app=NSApplication.shared,delegate=AppDelegate()
        app.setActivationPolicy(.regular);app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
