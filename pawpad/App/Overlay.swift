import AppKit
import SwiftUI

/// The live numbers the flight recorder writes each second (live.json in the session's folder).
struct LiveStats: Decodable {
    var game=false, visible=false, frozen=false, ended:Bool?=nil
    var fps=0.0, fps_10s=0.0, low_1pct_30s=0.0, worst_ms_10s=0.0
    var stutters=0, freezes=0
    var cpu_pct=0.0, runnable_pct=0.0, gpu_pct:Double?=nil
    var cpu_c:Double?=nil, gpu_c:Double?=nil, package_w:Double?=nil
    var game_mb=0.0, ram_used_mb=0.0, swap_mb=0.0, thermal=0, pressure=0
}

/// Settings › Show live overlay: the recorder's numbers over the game, in a small panel of
/// Pawpad's own that never takes the mouse or the keyboard. It floats above full-screen windows
/// and joins every Space, so it shows over the game without touching the game or its engine.
@MainActor
final class OverlayController {
    private let model:PawpadModel
    private var panel:NSPanel?
    private var timer:Timer?
    private var stats=LiveStats()
    private let state=OverlayState()
    init(model:PawpadModel) {
        self.model=model
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }
    private func liveFile() -> URL? {
        guard let data=try? Data(contentsOf:model.root.appendingPathComponent("state.json")),
              let state=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              let session=state["log_session"] as? String,session.range(of:"^[0-9TZ-]{16,24}$",options:.regularExpression) != nil else { return nil }
        return model.sessionsFolder.appendingPathComponent(session).appendingPathComponent("live.json")
    }
    private func tick() {
        guard model.showOverlay,model.recordPerformance,model.screen == .running,let file=liveFile(),
              let data=try? Data(contentsOf:file),let live=try? JSONDecoder().decode(LiveStats.self,from:data),
              live.game,live.ended != true,
              let modified=(try? FileManager.default.attributesOfItem(atPath:file.path)[.modificationDate]) as? Date,
              -modified.timeIntervalSinceNow<5
        else { hide();return }
        state.stats=live;show()
    }
    private func show() {
        if panel == nil {
            let p=NSPanel(contentRect:NSRect(x:0,y:0,width:250,height:132),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.level = .screenSaver
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            p.ignoresMouseEvents=true;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false
            p.hidesOnDeactivate=false;p.isFloatingPanel=true
            p.contentView=NSHostingView(rootView:OverlayView(state:state))
            panel=p
        }
        guard let panel,let screen=NSScreen.main else { return }
        let frame=screen.frame
        panel.setFrameOrigin(NSPoint(x:frame.minX+16,y:frame.maxY-panel.frame.height-16))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    private func hide() { panel?.orderOut(nil) }
}

@MainActor final class OverlayState: ObservableObject { @Published var stats=LiveStats() }

struct OverlayView: View {
    @ObservedObject var state:OverlayState
    private var s:LiveStats { state.stats }
    private func color(_ fps:Double) -> Color { fps>=55 ? .green : fps>=30 ? .yellow : .red }
    private func n(_ x:Double?,_ format:String) -> String { x.map { String(format:format,$0) } ?? "–" }
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Text(String(format:"%.0f",s.fps)).font(.system(size:22,weight:.bold,design:.rounded)).foregroundStyle(color(s.fps))
                Text("FPS").font(.system(size:10,weight:.semibold)).foregroundStyle(.white.opacity(0.7))
                Text("1% \(n(s.low_1pct_30s,"%.0f"))").foregroundStyle(color(s.low_1pct_30s))
                Text("worst \(n(s.worst_ms_10s,"%.0f")) ms")
                if s.frozen { Text("FROZEN").font(.system(size:10,weight:.heavy)).padding(.horizontal,4).background(.red,in:RoundedRectangle(cornerRadius:3)) }
            }
            Text("CPU \(n(s.cpu_pct,"%.0f"))%  wait \(n(s.runnable_pct,"%.0f"))%  GPU \(n(s.gpu_pct,"%.0f"))%")
            Text("CPU \(n(s.cpu_c,"%.0f"))°  GPU \(n(s.gpu_c,"%.0f"))°  \(n(s.package_w,"%.1f")) W\(s.thermal>=2 ? "  HOT" : "")")
            Text("Game \(n(s.game_mb/1024,"%.1f")) GB · RAM \(n(s.ram_used_mb/1024,"%.1f")) GB · swap \(n(s.swap_mb/1024,"%.1f")) GB\(s.pressure>=2 ? " ⚠︎" : "")")
            Text("Stutters \(s.stutters) · Freezes \(s.freezes)")
        }
        .font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(.white)
        .padding(10).frame(width:250,alignment:.leading)
        .background(.black.opacity(0.62),in:RoundedRectangle(cornerRadius:10,style:.continuous))
        .accessibilityHidden(true)
    }
}
