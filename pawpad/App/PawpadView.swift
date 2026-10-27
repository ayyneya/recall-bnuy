import AppKit
import SwiftUI

/// Pawpad's look: Aniimo's launcher colours (a sunny yellow button over sea and sky), in the
/// system font so menus, sheets and alerts match.
enum Style {
    static let accent=Color(red:1.0,green:0.82,blue:0.12)
    static let ink=Color(red:0.13,green:0.15,blue:0.20)
    static let sea=Color(red:0.16,green:0.55,blue:0.86)
    static let width:CGFloat=420
    static func surface(_ scheme:ColorScheme) -> Color { scheme == .dark ? Color(red:0.12,green:0.14,blue:0.18) : .white }
    static func ground(_ scheme:ColorScheme) -> LinearGradient {
        LinearGradient(colors:scheme == .dark ? [Color(red:0.06,green:0.10,blue:0.16),Color(red:0.08,green:0.08,blue:0.10)]
                                               : [Color(red:0.84,green:0.93,blue:1.0),Color(red:0.97,green:0.98,blue:1.0)],
                       startPoint:.top,endPoint:.bottom)
    }
}

/// The bundled artwork itself: macOS's application icon can come back tinted or clear,
/// following the Mac's icon style, which turned it grey here.
struct AppIconView: View {
    var size:CGFloat
    private static let artwork=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap { NSImage(contentsOf:$0) }
        ?? NSImage(named:NSImage.applicationIconName) ?? NSImage()
    var body:some View {
        Image(nsImage:Self.artwork).resizable().interpolation(.high)
            .frame(width:size,height:size).accessibilityHidden(true)
    }
}

struct Card<Content:View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:12) { content }
            .padding(20).frame(width:Style.width,alignment:.leading)
            .background(Style.surface(scheme),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .shadow(color:.black.opacity(scheme == .dark ? 0.3 : 0.07),radius:12,y:4)
    }
}

struct PrimaryButton: View {
    let title:String
    let action:()->Void
    var body:some View {
        Button(action:action) {
            Text(title).font(.system(size:16,weight:.semibold)).foregroundStyle(Style.ink)
                .frame(maxWidth:.infinity).padding(.vertical,12)
                .background(Style.accent,in:Capsule())
        }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
    }
}

struct PawpadView: View {
    @ObservedObject var model:PawpadModel
    @Environment(\.colorScheme) private var scheme

    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                VStack(spacing:8) {
                    AppIconView(size:96)
                    Text(Brand.name).font(.system(size:30,weight:.bold))
                    Text(Brand.tagline).font(.system(size:14)).foregroundStyle(.secondary)
                }.padding(.top,28)
                statusCard
                if model.screen == .ready || model.screen == .running { displayCard;recordingCard }
                footer
            }.padding(.horizontal,16).padding(.bottom,20).frame(maxWidth:.infinity)
        }
        .background(Style.ground(scheme).ignoresSafeArea())
        .sheet(isPresented:$model.showAbout) { AboutView(model:model) }
        .onAppear { model.start() }
    }

    private var title:String {
        switch model.screen {
        case .checking: return L("Checking…")
        case .welcome: return L("Let’s set up Aniimo")
        case .settingUp: return L("Setting up")
        case .installer: return L("Install Aniimo’s launcher")
        case .ready: return L("Ready to play")
        case .running: return model.gameRunning ? L("Aniimo is running") : L("Aniimo’s launcher is open")
        case .failed: return L("Setup stopped")
        }
    }
    private var detail:String {
        switch model.screen {
        case .checking: return ""
        case .welcome: return L("Pawpad installs a Windows environment tuned for Aniimo, then Aniimo’s own launcher. You sign in to Aniimo in the launcher; Pawpad never sees your account. You need about 45 GB free.")
        case .settingUp: return model.stage
        case .installer: return L("Aniimo’s installer opens in its own window. Keep the folder it suggests (C:\\PawPrint\\Aniimo) and choose Install. Pawpad continues when the launcher is in place. Closed it? Open it again here.")
        case .ready: return model.gameInstalled ? L("Play opens Aniimo’s launcher; start the game from there.") : L("Play opens Aniimo’s launcher. Download the game there (about 40 GB), then start it.")
        case .running: return model.gameRunning ? L("Have fun! Quit the game from its own menu when you’re done.") : L("Start the game from the launcher. Pawpad stays out of the way.")
        case .failed: return ""
        }
    }
    private var buttonTitle:String? {
        switch model.screen {
        case .checking, .settingUp: return nil
        case .welcome: return L("Set Up")
        case .installer: return L("Open Installer")
        case .ready: return L("Play")
        case .running: return L("Show Aniimo")
        case .failed: return L("Try Again")
        }
    }

    private var statusCard:some View {
        Card {
            Text(title).font(.system(size:20,weight:.semibold))
            if !detail.isEmpty { Text(detail).font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            if model.busy {
                HStack(spacing:10) {
                    ProgressView().controlSize(.small)
                    Text(model.downloadedBytes > 0 ? L("{0} MB downloaded",String(model.downloadedBytes/1_000_000)) : model.stage)
                        .font(.system(size:12)).foregroundStyle(.secondary)
                    Spacer()
                    if model.canCancel { Button(L("Pause")) { model.cancel() }.controlSize(.small) }
                }
            }
            if let failure=model.failure {
                Label(failure.message,systemImage:"exclamationmark.triangle.fill")
                    .font(.system(size:13)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                if failure.code == "rosetta_required" { Button(L("Install Rosetta")) { model.installRosetta() } }
            }
            if let buttonTitle,!model.busy { PrimaryButton(title:buttonTitle) { model.primary() } }
            if model.screen == .installer && !model.busy {
                Button(L("I’ve installed it — check again")) { model.checkInstaller() }
                    .buttonStyle(.link).font(.system(size:12)).frame(maxWidth:.infinity)
            }
        }
    }

    private var displayCard:some View {
        Card {
            Text(L("Display")).font(.system(size:15,weight:.semibold))
            Toggle(L("Show the Metal Performance HUD in the game"),isOn:$model.metalHUD)
            Text(model.retinaDisplay ? L("Your main display is a Retina display: Aniimo sees its full pixel resolution. Choose a lower resolution in Aniimo’s own settings for more speed.") : L("Aniimo sees your main display’s real resolution; choose its size in Aniimo’s own settings. Changes apply the next time you press Play."))
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

    private var recordingCard:some View {
        Card {
            Toggle(isOn:$model.recordPerformance) {
                VStack(alignment:.leading,spacing:2) {
                    Text(L("Record performance")).font(.system(size:15,weight:.semibold))
                    Text(L("Frames, stutters, freezes and crashes, with the Mac’s load, heat and power, and a report after each session. Turn it off when you just want to play."))
                        .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }.toggleStyle(.switch)
            Toggle(L("Show live overlay in the game"),isOn:$model.showOverlay).disabled(!model.recordPerformance)
            if let last=model.lastReport {
                Text(L("Last session: {0}",last.headline)).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
            }
            HStack(spacing:16) {
                if model.lastReport != nil { Button(L("Show Last Report")) { model.showLastReport() } }
                Button(L("Show Recordings")) { model.showRecordings() }
                if model.screen == .running && model.recordPerformance { Button(L("Add Marker…")) { model.addMarker() } }
            }.buttonStyle(.link).font(.system(size:12))
            if model.recordPerformance && model.screen == .running {
                Text(L("Changes to recording apply the next time you press Play.")).font(.system(size:11)).foregroundStyle(.secondary)
            }
        }
    }

    private var footer:some View {
        VStack(spacing:10) {
            HStack(spacing:16) {
                Button(L("About {0}",Brand.name)) { model.showAbout=true }
                if model.screen == .running { Button(L("Force Quit…")) { model.forceQuit() } }
                if model.screen != .checking && model.screen != .settingUp { Button(L("Uninstall…")) { model.uninstall() }.disabled(model.busy) }
            }.buttonStyle(.link).font(.system(size:12))
            Button { NSWorkspace.shared.open(Brand.Recall.repository) } label: {
                Text(L("Based on {0} by {1}",Brand.Recall.name,Brand.Recall.author)).font(.system(size:11)).foregroundStyle(.secondary).underline()
            }.buttonStyle(.plain).help(Brand.Recall.repository.absoluteString)
        }
    }
}

struct AboutView: View {
    @ObservedObject var model:PawpadModel
    @Environment(\.dismiss) private var dismiss
    private var version:String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:14) {
                AppIconView(size:64)
                VStack(alignment:.leading,spacing:2) {
                    Text(Brand.name).font(.system(size:22,weight:.bold))
                    Text(L("Version {0}",version)).font(.system(size:12)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment:.leading,spacing:8) {
                Text(L("Built on Recall")).font(.system(size:14,weight:.semibold))
                Text(L("Pawpad is based on {0}, the free, open-source app that makes Overwatch playable on Apple Silicon, created by {1} ({2}). Recall’s engine is what makes Pawpad possible: its changes to Wine and DXMT, shader preparation, frame pacing, display handling and direct mouse input.",Brand.Recall.name,Brand.Recall.author,Brand.Recall.handle))
                    .font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                Button(L("Recall on GitHub")) { NSWorkspace.shared.open(Brand.Recall.repository) }.buttonStyle(.link).font(.system(size:12))
            }
            VStack(alignment:.leading,spacing:8) {
                Text(L("Open source")).font(.system(size:14,weight:.semibold))
                Text(L("Pawpad and Recall are licensed under the Apache License 2.0. The engine includes Wine and DXMT, under the GNU LGPL 2.1."))
                    .font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:16) {
                    Button(L("Pawpad on GitHub")) { NSWorkspace.shared.open(Brand.repository) }
                    Button(L("Show Licenses")) {
                        if let licenses=Bundle.main.resourceURL?.appendingPathComponent("Licenses") { NSWorkspace.shared.activateFileViewerSelecting([licenses]) }
                    }
                }.buttonStyle(.link).font(.system(size:12))
            }
            Text(Brand.trademarks).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack { Spacer();Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:460)
    }
}
