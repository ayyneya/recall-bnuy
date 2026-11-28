// Recall's helper: a LaunchDaemon bundled in Recall.app (Contents/Helpers/recall-helper) and
// registered with SMAppService once the player turns on Steady Wi-Fi or fan speed in Settings ›
// Graphics, because only root can take a network interface down or set a fan. It runs only while
// Recall holds a connection to it, which Recall does only while Overwatch is open and one of the
// two is wanted (GameHelper). It takes connections only from Recall signed by its own team.
//
// It does two things, and undoes both when Recall lets go, quits or crashes, or launchd stops it:
//
// - Steady Wi-Fi holds awdl0 (Apple Wireless Direct Link: AirDrop, Handoff, Sidecar) and llw0
//   (low-latency WLAN) down. Both make the Wi-Fi radio leave the router's channel every so often,
//   which a game feels as ping spikes. macOS brings them back up by itself, so a routing socket
//   reports every interface change and the helper takes them down again the moment they come up:
//   nothing polls. After AWDL Control by James Howard (MIT; licenses/AWDLCONTROL-MIT) and, for
//   llw0, JitterBreak by David Roman Lopez (Apache 2.0).
// - Fan speed runs every fan at a share of its range. If macOS reports the Mac getting seriously
//   warm, the fans go back to macOS. The Apple silicon sequence (Ftst, mode, target) follows
//   Stats by Serhiy Mytrovtsiy (MIT; licenses/STATS-MIT).
//
// Built with app/Sources/HelperProtocol.swift and app/Sources/SMC.swift (build_native_app.py).
import Foundation
import Security
import os

let logger=Logger(subsystem:RecallHelperNames.label,category:"helper")
let queue=DispatchQueue(label:RecallHelperNames.label)

// MARK: Steady Wi-Fi

enum WiFi {
    static let interfaces=["awdl0","llw0"]
    static var holding=false
    /// The interfaces the helper took down, which come back up when it lets go.
    static var lowered:Set<String>=[]
    static let routeSocket=socket(AF_ROUTE,SOCK_RAW,0)
    static let routeSource:DispatchSourceRead = {
        _ = fcntl(routeSocket,F_SETFL,O_NONBLOCK)
        let source=DispatchSource.makeReadSource(fileDescriptor:routeSocket,queue:queue)
        source.setEventHandler { routeChanged() }
        return source
    }()

    /// Whether the interface is up now; nil when this Mac doesn't have it.
    static func isUp(_ name:String)->Bool? {
        var list:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var entry=list
        while let current=entry {
            if String(cString:current.pointee.ifa_name) == name { return current.pointee.ifa_flags & UInt32(IFF_UP) != 0 }
            entry=current.pointee.ifa_next
        }
        return nil
    }
    /// ifconfig, as root, sets the flag (Swift can't call the variadic ioctl).
    static func set(_ name:String,up:Bool)->Bool {
        let process=Process()
        process.executableURL=URL(fileURLWithPath:"/sbin/ifconfig")
        process.arguments=[name,up ? "up" : "down"]
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
    static func lower(_ name:String) {
        guard isUp(name) == true else { return }
        if set(name,up:false) { lowered.insert(name) } else { logger.error("\(name, privacy:.public) stays up") }
    }
    /// Each read is one routing message; an interface held down that came up goes down again.
    static func routeChanged() {
        var buffer=[UInt8](repeating:0,count:2048)
        while true {
            let length=buffer.withUnsafeMutableBytes { read(routeSocket,$0.baseAddress,$0.count) }
            if length < 0 && errno == EINTR { continue }
            guard length >= MemoryLayout<if_msghdr>.size else { return }
            let message=buffer.withUnsafeBytes { $0.loadUnaligned(as:if_msghdr.self) }
            guard holding,Int32(message.ifm_type) == RTM_IFINFO,message.ifm_flags & IFF_UP != 0 else { continue }
            // Looked up each time: llw0 can appear after the hold began.
            for name in interfaces where if_nametoindex(name) == UInt32(message.ifm_index) { lower(name) }
        }
    }
    static func hold() {
        guard !holding else { return }
        holding=true
        interfaces.forEach(lower)
        routeSource.resume()
        logger.info("holding Wi-Fi")
    }
    static func letGo() {
        guard holding else { return }
        holding=false
        routeSource.suspend()
        for name in lowered where !set(name,up:true) { logger.error("\(name, privacy:.public) didn't come back up") }
        lowered=[]
        logger.info("let Wi-Fi go")
    }
}

// MARK: Fan speed

enum Fans {
    static let smc=SMC()
    /// The share of each fan's range they run at now; nil while macOS runs them.
    static var percent:Double?
    /// macOS says the Mac is seriously warm: its own fan control knows best then.
    static var warm:Bool { [.serious,.critical].contains(ProcessInfo.processInfo.thermalState) }

    /// F0md on some Macs, F0Md on others.
    static func modeKey(_ i:Int)->String { smc?.read("F0md") != nil ? "F\(i)md" : "F\(i)Md" }
    static func writeByte(_ key:String,_ byte:UInt8,attempts:Int,pause:useconds_t)->Bool {
        guard let smc,var value=smc.read(key),!value.bytes.isEmpty else { return false }
        value.bytes[0]=byte
        for attempt in 0..<attempts {
            if smc.write(key,value) { return true }
            if attempt < attempts-1 { usleep(pause) }
        }
        return false
    }
    /// A fan takes a target only in manual mode. M5 and later switch at once; M1 to M4 need Ftst
    /// first, and then a few seconds for macOS's thermal monitor to let go.
    static func manual(_ i:Int)->Bool {
        if writeByte(modeKey(i),1,attempts:1,pause:0) { return true }
        guard let smc,let unlock=smc.read("Ftst"),!unlock.bytes.isEmpty else { return false }
        if unlock.bytes[0] != 1 {
            guard writeByte("Ftst",1,attempts:100,pause:50_000) else { return false }
            usleep(3_000_000)
        }
        return writeByte(modeKey(i),1,attempts:300,pause:100_000)
    }
    static func set(_ wanted:Double)->Bool {
        guard let smc else { return false }
        let fans=smc.fans
        guard !fans.isEmpty else { return false }
        let share=min(max(wanted,0),100)/100
        var all=true
        for fan in fans {
            let key="F\(fan.index)Tg"
            guard manual(fan.index),var target=smc.read(key),target.type == "flt ",target.bytes.count >= 4 else { all=false;continue }
            var rpm=Float(fan.minimum+(fan.maximum-fan.minimum)*share)
            withUnsafeBytes(of:&rpm) { target.bytes.replaceSubrange(0..<4,with:$0) }
            var written=false
            for _ in 0..<10 where !written { written=smc.write(key,target);if !written { usleep(50_000) } }
            all=all && written
        }
        percent=wanted
        logger.info("fans at \(wanted, privacy:.public)%")
        return all
    }
    /// Every fan back to macOS: automatic mode, and Ftst cleared where the Mac has it.
    static func automatic() {
        guard percent != nil,let smc else { return }
        for fan in smc.fans { _ = writeByte(modeKey(fan.index),0,attempts:10,pause:50_000) }
        if let unlock=smc.read("Ftst"),unlock.bytes.first == 1 { _ = writeByte("Ftst",0,attempts:10,pause:50_000) }
        percent=nil
        logger.info("fans back to automatic")
    }
    static func thermalChanged() {
        if warm { automatic() }
    }
}

// MARK: The service

/// Everything back as it was.
func letGoOfEverything() {
    WiFi.letGo()
    Fans.automatic()
}

final class Service:NSObject,RecallHelperProtocol,NSXPCListenerDelegate {
    var connections=0
    func setWiFiHeld(_ held:Bool,withReply reply:@escaping (Bool)->Void) {
        queue.async {
            if held { WiFi.hold() } else { WiFi.letGo() }
            reply(WiFi.holding)
        }
    }
    func setFanPercent(_ percent:Double,withReply reply:@escaping (Bool)->Void) {
        queue.async {
            guard percent >= 0 else { Fans.automatic();reply(true);return }
            // Seriously warm already: the fans stay macOS's.
            guard !Fans.warm else { reply(false);return }
            reply(Fans.set(percent))
        }
    }
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection connection:NSXPCConnection)->Bool {
        connection.exportedInterface=NSXPCInterface(with:RecallHelperProtocol.self)
        connection.exportedObject=self
        queue.sync { connections+=1 }
        // The last connection gone (Recall let go, quit or crashed): everything back, and exit.
        connection.invalidationHandler={ [weak self] in
            queue.async {
                guard let self else { return }
                self.connections-=1
                guard self.connections <= 0 else { return }
                letGoOfEverything()
                exit(0)
            }
        }
        connection.resume()
        return true
    }
}

/// The team that signed this helper, and so Recall. Nil for an unsigned or ad hoc build.
func ownTeam()->String? {
    var code:SecCode?
    var info:CFDictionary?
    guard SecCodeCopySelf([],&code) == errSecSuccess,let code,
          SecCodeCopySigningInformation(unsafeBitCast(code,to:SecStaticCode.self),SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess
    else { return nil }
    return (info as? [String:Any])?[kSecCodeInfoTeamIdentifier as String] as? String
}

// launchd stops the helper with SIGTERM (the settings turned off, or a shutdown).
signal(SIGTERM,SIG_IGN)
let terminate=DispatchSource.makeSignalSource(signal:SIGTERM,queue:queue)
terminate.setEventHandler { letGoOfEverything();exit(0) }
terminate.resume()
let thermal=NotificationCenter.default.addObserver(forName:ProcessInfo.thermalStateDidChangeNotification,object:nil,queue:nil) { _ in
    queue.async { Fans.thermalChanged() }
}

guard let team=ownTeam() else {
    logger.error("unsigned helper: refusing every connection")
    exit(1)
}
let service=Service()
let listener=NSXPCListener(machServiceName:RecallHelperNames.label)
listener.setConnectionCodeSigningRequirement("identifier \"\(RecallHelperNames.appIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
listener.delegate=service
listener.resume()
dispatchMain()
