import Foundation
import Darwin

// DiscordPresence.swift: the card Recall shows in Discord and where it gets it. Lines are shaped like
// the real Overwatch.log's, with the ids left out; Discord is a fake listener on a temporary socket.
// Build and run:
//   swiftc -O -target arm64-apple-macos26.5 -parse-as-library app/Sources/Brand.swift app/Sources/Localization.swift \
//     app/Sources/Discord/DiscordPresence.swift app/Sources/Discord/CareerProfile.swift app/Sources/Discord/CareerHistory.swift \
//     app/Sources/Discord/DiscordCardTemplate.swift app/Sources/Discord/DiscordCardCatalog.swift tests/DiscordPresenceTests.swift -o runtime/phase-3/discord-presence-tests
//   runtime/phase-3/discord-presence-tests

final class Collected<T> {
    private let lock=NSLock()
    private var items:[T]=[]
    func add(_ more:[T]) { lock.lock();items+=more;lock.unlock() }
    var all:[T] { lock.lock();defer { lock.unlock() };return items }
}

/// Waits for something that happens on another queue.
func wait(_ seconds:Double=5,_ done:()->Bool)->Bool {
    let end=Date().addingTimeInterval(seconds)
    while Date() < end { if done() { return true };Thread.sleep(forTimeInterval:0.02) }
    return done()
}
let stamper:ISO8601DateFormatter={ let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f }()
func logLine(_ message:String,at date:Date)->String { "[1752] [ALW] [VoiceChat] [External(0)] [External()] [\(stamper.string(from:date))]: \(message)" }
let ready="#=[VC] Auto-Join Enabled Flags 0000 -> 0005",closed="#=[VC] Auto-Join Enabled Flags 0005 -> 0000"
let join="==[VC] Notified Lobby of Active channel NONE -> TEAM",leave="==[VC] Notified Lobby of Active channel TEAM -> NONE"
let teammate="#=[VC] MemberAdded 603564719 23f9aaaf 0d4cbeb2@4a95b6d2 22f891df false",yourself="#=[VC] MemberAdded 603564719 23f9aaaf 0d4cbeb2@4a95b6d2 22f891df true"
let partyJoin="==[VC] Notified Lobby of Active channel NONE -> PARTY",partyLeave="==[VC] Notified Lobby of Active channel PARTY -> NONE"

/// Discord's side of the socket, for one test.
final class FakeDiscord {
    let path:String
    private let listener:Int32
    init() {
        let folder=NSTemporaryDirectory()+"ow2-discord-\(getpid())-\(UInt32.random(in:0..<1_000_000))/"
        try! FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
        path=folder+"discord-ipc-0"
        listener=socket(AF_UNIX,SOCK_STREAM,0)
        var address=sockaddr_un()
        address.sun_family=sa_family_t(AF_UNIX)
        let capacity=MemoryLayout.size(ofValue:address.sun_path)
        withUnsafeMutablePointer(to:&address.sun_path) { $0.withMemoryRebound(to:CChar.self,capacity:capacity) { _ = strlcpy($0,path,capacity) } }
        let bound=withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(listener,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        precondition(bound == 0 && Darwin.listen(listener,4) == 0)
    }
    deinit {
        Darwin.close(listener)
        try? FileManager.default.removeItem(atPath:(path as NSString).deletingLastPathComponent)
    }
    func accept(_ milliseconds:Int32=5000)->Int32? {
        var poller=pollfd(fd:listener,events:Int16(POLLIN),revents:0)
        guard poll(&poller,1,milliseconds) > 0 else { return nil }
        let fd=Darwin.accept(listener,nil,nil)
        return fd >= 0 ? fd : nil
    }
    private func read(_ fd:Int32,_ count:Int,_ milliseconds:Int32)->[UInt8]? {
        var bytes=[UInt8]()
        while bytes.count < count {
            var poller=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            guard poll(&poller,1,milliseconds) > 0 else { return nil }
            var chunk=[UInt8](repeating:0,count:count-bytes.count)
            let n=Darwin.read(fd,&chunk,chunk.count)
            guard n > 0 else { return nil }
            bytes+=chunk[0..<n]
        }
        return bytes
    }
    func frame(_ fd:Int32,_ milliseconds:Int32=5000)->(opcode:UInt32,json:[String:Any])? {
        guard let head=read(fd,8,milliseconds) else { return nil }
        let length=Int(head[4])|Int(head[5])<<8|Int(head[6])<<16|Int(head[7])<<24
        guard let body=read(fd,length,milliseconds),let json=try? JSONSerialization.jsonObject(with:Data(body)) as? [String:Any] else { return nil }
        return (UInt32(head[0])|UInt32(head[1])<<8|UInt32(head[2])<<16|UInt32(head[3])<<24,json)
    }
    func send(_ fd:Int32,_ opcode:UInt32,_ json:[String:Any]) {
        let data=DiscordFrame.encode(opcode,json)!
        _ = data.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!,data.count) }
    }
    /// Discord answers the opening with READY, and the client then sends its card.
    func welcome(_ fd:Int32)->[String:Any]? {
        guard let hello=frame(fd),hello.opcode == DiscordFrame.handshake else { return nil }
        send(fd,DiscordFrame.frame,["cmd":"DISPATCH","evt":"READY","data":["v":1]])
        return hello.json
    }
    /// The card in a SET_ACTIVITY frame; an NSNull when the card is taken down.
    func card(_ fd:Int32,_ milliseconds:Int32=5000)->Any?? {
        guard let message=frame(fd,milliseconds),message.opcode == DiscordFrame.frame,message.json["cmd"] as? String == "SET_ACTIVITY",
              let args=message.json["args"] as? [String:Any] else { return nil }
        return .some(args["activity"])
    }
    func closed(_ fd:Int32)->Bool {
        var poller=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
        var byte:UInt8=0
        return poll(&poller,1,5000) > 0 && Darwin.read(fd,&byte,1) == 0
    }
}
func details(_ card:Any??)->String? { ((card ?? nil) as? [String:Any])?["details"] as? String }

@main struct DiscordPresenceTests {
    static func main() {
        frames();parsing();tracker();cards();socketPlaces();processStart();location();tail();connection();reconnect();absent();rate();spam();refusals();rules();otherAccount();endToEnd()
        print("PASS: Discord frames, Overwatch.log lines, match tracking, the card at each level, following the log, the Discord socket and the whole path")
    }

    static func frames() {
        let body=["cmd":"SET_ACTIVITY"]
        let one=DiscordFrame.encode(DiscordFrame.frame,body)!
        // 4-byte opcode, 4-byte length, both little-endian, then the JSON.
        precondition(Array(one[0..<4]) == [1,0,0,0] && Int(one[4]) == one.count-8 && one[5] == 0)
        var reader=DiscordFrameReader()
        // A frame in pieces, then two frames in one read.
        var got:[DiscordFrameReader.Frame]=[]
        for byte in one { got+=reader.feed(Data([byte])) }
        precondition(got.count == 1 && got[0].opcode == 1 && (try! JSONSerialization.jsonObject(with:got[0].body) as! [String:String]) == body)
        let ping=DiscordFrame.encode(DiscordFrame.ping,["n":1])!
        got=reader.feed(ping+one)
        precondition(got.map(\.opcode) == [3,1])
        // Something that is not Discord speaking is cut off.
        var bad=DiscordFrameReader()
        _ = bad.feed(Data([1,0,0,0,0,0,0,0x7f]))
        precondition(bad.broken)
        precondition(DiscordFrame.encode(1,["a":Date()]) == nil)
    }

    static func parsing() {
        let t=Date(timeIntervalSince1970:1_792_000_000.25)
        func at(_ e:PresenceEvent?)->Date? {
            switch e { case .channel(_,let d)?,.voiceReady(let d)?,.voiceClosed(let d)?: return d;default: return nil }
        }
        let joined=PresenceEvent.parse(logLine(join,at:t))
        precondition(joined == .channel(.team,joined.flatMap(at)!) && abs(at(joined)!.timeIntervalSince(t)) < 0.002)
        let time=at(joined)!
        precondition(PresenceEvent.parse(logLine(leave,at:t)) == .channel(nil,time))
        precondition(PresenceEvent.parse(logLine(partyJoin,at:t)) == .channel(.party,time))
        precondition(PresenceEvent.parse(logLine(partyLeave,at:t)) == .channel(nil,time))
        precondition(PresenceEvent.parse(logLine("==[VC] Notified Lobby of Active channel PARTY -> TEAM",at:t)) == .channel(.team,time))
        precondition(PresenceEvent.parse(logLine("==[VC] Notified Lobby of Active channel TEAM -> NONE",at:t)) == .channel(nil,time))
        // After a match the game moves everyone to the MATCH channel (the voting cards).
        precondition(PresenceEvent.parse(logLine("==[VC] Notified Lobby of Active channel NONE -> MATCH",at:t)) == .channel(.match,time))
        precondition(PresenceEvent.parse(logLine("==[VC] Notified Lobby of Active channel NONE -> LOBBY",at:t)) == .channel(.other,time))
        // The match is over when match-wide chat is enabled (flags gain 0x2); the game is left when it closes.
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0005 -> 0007",at:t)) == .matchOver(time))
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0007 -> 0005",at:t)) == .matchChatClosed(time))
        // Why the voice channel changes: 3 is the player's own choice; the game's own moves are -2 and 5.
        precondition(PresenceEvent.parse(logLine("#=[VC] __SetTargetActiveChannelType(TEAM -> PARTY) : 3",at:t)) == .switching(byPlayer:true,time))
        precondition(PresenceEvent.parse(logLine("#=[VC] __SetTargetActiveChannelType(TEAM -> MATCH) : 5",at:t)) == .switching(byPlayer:false,time))
        precondition(PresenceEvent.parse(logLine("#=[VC] __SetTargetActiveChannelType(UNKNOWN -> PARTY) : -2",at:t)) == .switching(byPlayer:false,time))
        // Voice chat as a whole turning on or off.
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0000 -> 0005",at:t)) == .chatEnabled(true,time))
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0005 -> 0000",at:t)) == .chatEnabled(false,time))
        // Auto-Join's flags are hex, and only the team's bit (0x1) says the menus are reached: Team Voice off with the
        // group's on (0004) never claims them; turning Team Voice off later only stops claiming.
        precondition(PresenceEvent.parse(logLine("#=[VC] Auto-Join Enabled Flags 0000 -> 0004",at:t)) == nil)
        precondition(PresenceEvent.parse(logLine("#=[VC] Auto-Join Enabled Flags 0004 -> 0005",at:t)) == .voiceReady(time))
        precondition(PresenceEvent.parse(logLine("#=[VC] Auto-Join Enabled Flags 0005 -> 0004",at:t)) == .voiceOff(time))
        precondition(PresenceEvent.parse(logLine("#=[VC] Auto-Join Enabled Flags 0004 -> 0000",at:t)) == .voiceClosed(time))
        // A channel line with more after it still names the channel.
        precondition(PresenceEvent.parse(logLine("==[VC] Notified Lobby of Active channel TEAM -> NONE and more",at:t)) == .channel(nil,time))
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0005 -> zz",at:t)) == nil)
        // Another flag changing while match-wide chat stays on is not the match ending.
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0007 -> 0006",at:t)) == nil)
        precondition(PresenceEvent.parse(logLine("#=[VC] Channel Enabled Flags 0002 -> 0003",at:t)) == nil)
        // Another player's voice (false) is told; the player's own (true) is not.
        precondition(PresenceEvent.parse(logLine(teammate,at:t)) == .member(channel:"603564719",who:"0d4cbeb2@4a95b6d2",time) && PresenceEvent.parse(logLine(yourself,at:t)) == nil)
        precondition(PresenceEvent.parse(logLine("#=[VC] MemberAdded 603564719 23f9aaaf false",at:t)) == nil)
        // Who leaves a channel, and which channel the game asks to join next (the members that follow name it).
        precondition(PresenceEvent.parse(logLine("#=[VC] MemberRemoved 773141270 2e153316 844fe725@4a95b6d2 11b8077a 0",at:t)) == .memberLeft(channel:"773141270",who:"844fe725@4a95b6d2",time))
        precondition(PresenceEvent.parse(logLine("==[VC] Request join channel PARTY 773141270 2e153316",at:t)) == .joining(.party,id:"773141270",time))
        precondition(PresenceEvent.parse(logLine("==[VC] Request join channel MATCH 1505404435 59baa613",at:t)) == .joining(.match,id:"1505404435",time))
        precondition(PresenceEvent.parse(logLine("==[VC] Join channel requested 9bd5d047 773141270 e5dca5ca@4a95b6d2",at:t)) == nil)
        precondition(PresenceEvent.parse(logLine(ready,at:t)) == .voiceReady(time))
        precondition(PresenceEvent.parse(logLine(closed,at:t)) == .voiceClosed(time))
        // The game writes Windows line endings.
        precondition(PresenceEvent.parse(logLine(join,at:t)+"\r") == joined && PresenceEvent.parse(logLine(ready,at:t)+"\r") == .voiceReady(time))
        // Everything else the log says, as it appears in a real one, says nothing about where the player is.
        let others=["#=[VC] Auto-Join Enabled Flags 0005 -> 0007","#=[VC] Auto-Join Enabled Flags 0000 -> 0000",
                    "==[VC] OnJoinChannel NONE -> TEAM","==[VC] OnJoinChannel NONE -> PARTY",
                    "==[VC] Notified Lobby of Active channel","==[VC] JoinVoiceChannel() _?__95g==__?_ - PARTY - active = 1","#=[VC] ChatSystem switching to new PARTY channel: _?__95g==__?_",
                    "==[VC] Request login 0a1b2c","#=[VC] ResponseMuteMember 7 0(0:0c0dc0)","==[VC] Member identity updated 1f2e3d","#=[VC] MemberAdded 603564719 23f9aaaf 0d4cbeb2@4a95b6d2 22f891df true"]
        for message in others { precondition(PresenceEvent.parse(logLine(message,at:t)) == nil,message) }
        precondition(PresenceEvent.parse("[1752] [ALW] [Engine] [External(0)] [External()] [2026-10-24T16:30:03.522Z]: prism: Info: Display 0") == nil)
        precondition(PresenceEvent.parse("") == nil && PresenceEvent.parse("[VoiceChat] Notified Lobby of Active channel NONE -> TEAM") == nil)
    }

    static func tracker() {
        let t0=Date(timeIntervalSince1970:1_792_000_000)
        func after(_ s:Double)->Date { t0.addingTimeInterval(s) }
        /// Another player's voice, in a channel no join was seen for.
        func mate(_ time:Date)->PresenceEvent { .member(channel:"0",who:"mate",time) }
        var tracker=PresenceTracker()
        // Nothing said yet, or voice chat off: nothing is claimed.
        precondition(tracker.state(at:after(500)) == .unknown && tracker.nextChange(at:after(500)) == nil)
        tracker.apply(.voiceReady(after(26)))
        precondition(tracker.state(at:after(30)) == .menu)
        // A team channel that opens and closes in seconds is a match that was backed out of.
        tracker.apply(mate(after(60)));tracker.apply(.channel(.team,after(60.5)))
        precondition(tracker.state(at:after(63)) == .menu && tracker.nextChange(at:after(63))! > 7.4 && tracker.nextChange(at:after(63))! < 7.6)
        tracker.apply(.channel(nil,after(64)))
        precondition(tracker.state(at:after(200)) == .menu && tracker.nextChange(at:after(200)) == nil && !tracker.others)
        // One that holds, with the team's voices in it (they join as the channel opens), is a match, timed from the join.
        tracker.apply(mate(after(299.5)));tracker.apply(.channel(.team,after(300)));tracker.apply(mate(after(301)))
        precondition(tracker.state(at:after(309)) == .menu && tracker.state(at:after(310)) == .match(since:after(300)))
        // The same channel said again keeps the first one's time.
        tracker.apply(.channel(.team,after(400)))
        precondition(tracker.state(at:after(500)) == .match(since:after(300)))
        // The results showing ends the match at once, though the team's channel stays open (an Arcade game kept it 52 s).
        tracker.apply(.matchOver(after(849)));tracker.apply(.channel(nil,after(850)));tracker.apply(mate(after(851)));tracker.apply(.channel(.team,after(852)))
        precondition(tracker.state(at:after(870)) == .match(since:after(852)))
        tracker.apply(.matchOver(after(880)))
        precondition(tracker.state(at:after(881)) == .menu && tracker.state(at:after(890)) == .menu)
        tracker.apply(.channel(nil,after(897)))
        precondition(tracker.state(at:after(898)) == .menu && !tracker.over)
        // The mark means nothing with no team channel open, and is not carried to the next match.
        tracker.apply(.matchOver(after(899)));tracker.apply(mate(after(899.5)));tracker.apply(.channel(.team,after(900)))
        precondition(tracker.state(at:after(911)) == .match(since:after(900)))
        tracker.apply(.channel(nil,after(920)))
        // The screen after the match (the voting cards) is the end of it.
        tracker.apply(.channel(nil,after(900)));tracker.apply(.channel(.match,after(902)))
        precondition(tracker.state(at:after(905)) == .menu)
        tracker.apply(.channel(nil,after(920)))
        precondition(tracker.state(at:after(921)) == .menu)
        // A team channel with nobody else in it (the Practice Range, a game with bots) claims nothing once it has held.
        tracker.apply(.channel(.team,after(1000)))
        precondition(tracker.state(at:after(1005)) == .menu && tracker.state(at:after(1011)) == .unknown && tracker.state(at:after(5000)) == .unknown)
        // Another player's voice arriving later makes it a match from the join.
        tracker.apply(mate(after(1100)))
        precondition(tracker.state(at:after(1101)) == .match(since:after(1000)))
        tracker.apply(.channel(nil,after(1200)))
        precondition(tracker.state(at:after(1201)) == .menu && !tracker.others)
        // In a group the game keeps only the group's channel and says nothing more: no claim of menus or a match.
        tracker.apply(.channel(.party,after(1300)))
        precondition(tracker.state(at:after(1301)) == .unknown && tracker.state(at:after(9000)) == .unknown && tracker.nextChange(at:after(1301)) == nil)
        tracker.apply(.channel(nil,after(1500)))
        precondition(tracker.state(at:after(1501)) == .menu)
        // A group that moves to the team's channel for a match, and back to the group's after it.
        tracker.apply(.channel(.party,after(1600)));tracker.apply(mate(after(1699)));tracker.apply(.channel(.team,after(1700)))
        precondition(tracker.state(at:after(1705)) == .menu && tracker.state(at:after(1710)) == .match(since:after(1700)))
        tracker.apply(.matchOver(after(2390)));tracker.apply(.channel(.party,after(2400)))
        precondition(tracker.state(at:after(2401)) == .unknown)
        // The group's next match is a match again: what the last one's results said ends with its channel.
        tracker.apply(.channel(.team,after(2420)))
        precondition(tracker.state(at:after(2480)) == .match(since:after(2420)))
        tracker.apply(.matchOver(after(2490)));tracker.apply(.channel(.match,after(2492)));tracker.apply(.channel(.team,after(2494)))
        precondition(tracker.state(at:after(2540)) == .match(since:after(2494)))
        tracker.apply(.channel(.party,after(2499)))
        precondition(tracker.state(at:after(2499.5)) == .unknown)
        // Who is in the group's voice chat: the player and the others named in its channel after the join,
        // less those who leave. Voices in another channel are not the group's.
        var voice=PresenceTracker()
        voice.apply(.voiceReady(after(10)));voice.apply(.joining(.party,id:"P",after(20)))
        voice.apply(.channel(.party,after(24)))
        precondition(voice.groupVoice == nil,"nobody else in the group's voice: nothing to tell")
        voice.apply(.member(channel:"P",who:"a@h",after(200)));voice.apply(.member(channel:"P",who:"b@h",after(201)));voice.apply(.member(channel:"T",who:"c@h",after(202)))
        voice.apply(.member(channel:"P",who:"a@h",after(203)))
        precondition(voice.groupVoice?.count == 3 && voice.groupVoice?.channel == "P")
        voice.apply(.memberLeft(channel:"P",who:"b@h",after(300)));voice.apply(.memberLeft(channel:"T",who:"a@h",after(301)))
        precondition(voice.groupVoice?.count == 2 && voice.groupVoice?.channel == "P")
        // A match's channel, then the group's again: the voices are named anew after the join.
        let first=voice.groupVoice?.party
        voice.apply(.joining(.team,id:"T2",after(400)));voice.apply(.channel(.team,after(401)));voice.apply(.member(channel:"T2",who:"d@h",after(402)))
        voice.apply(.joining(.party,id:"P",after(1000)));voice.apply(.channel(.party,after(1001)))
        // The party id Discord gets stays the same for the same channel, and is not the channel's. Back in it, the
        // voices kept stand until the game names them anew.
        precondition(first != nil && voice.groupVoice?.party == first && first?.contains("P") == false)
        precondition(voice.groupVoice?.count == 2 && voice.groupVoice?.channel == "P")
        voice.apply(.member(channel:"P",who:"e@h",after(1003)))
        precondition(voice.groupVoice?.count == 2 && voice.groupVoice?.channel == "P","named anew: the player and e")
        voice.apply(.member(channel:"P",who:"a@h",after(1003.2)))
        precondition(voice.groupVoice?.count == 3)
        // The voice service closing, or the log starting over, forgets them.
        voice.apply(.reset);voice.apply(.channel(.party,after(1100)))
        precondition(voice.groupVoice == nil)
        // The player choosing their own voice moves them nowhere (a custom game's players switch between team,
        // group and match voice, October 25): the match goes on in the group's or the match's voice, timer kept.
        var custom=PresenceTracker()
        custom.apply(.voiceReady(after(10)));custom.apply(.channel(.team,after(100)));custom.apply(mate(after(101)))
        precondition(custom.state(at:after(200)) == .match(since:after(100)))
        func choose(_ next:VoiceChannel,_ s:Double) { custom.apply(.switching(byPlayer:true,after(s)));custom.apply(.channel(nil,after(s)));custom.apply(.channel(next,after(s+2))) }
        choose(.party,300)
        precondition(custom.state(at:after(301)) == .match(since:after(100)) && custom.state(at:after(310)) == .match(since:after(100)) && custom.chosen)
        choose(.match,400)
        precondition(custom.state(at:after(410)) == .match(since:after(100)))
        choose(.team,500)
        precondition(custom.state(at:after(503)) == .match(since:after(100)))
        // The game moving everyone to the match's channel as it ends is the menus again.
        custom.apply(.matchOver(after(600)));custom.apply(.switching(byPlayer:false,after(630)));custom.apply(.channel(nil,after(630)));custom.apply(.channel(.match,after(632)))
        precondition(custom.state(at:after(640)) == .menu && !custom.chosen)
        // Kept in the group's voice, the match ends with its results, or when its match-wide chat closes
        // (the game left); then the group's voice claims nothing, menus included.
        var kept=PresenceTracker()
        kept.apply(.voiceReady(after(10)));kept.apply(.channel(.team,after(100)));kept.apply(mate(after(101)))
        kept.apply(.switching(byPlayer:true,after(300)));kept.apply(.channel(nil,after(300)));kept.apply(.channel(.party,after(302)))
        precondition(kept.state(at:after(400)) == .match(since:after(100)))
        kept.apply(.matchOver(after(500)))
        precondition(kept.state(at:after(501)) == .unknown)
        kept.apply(.channel(.team,after(600)));kept.apply(mate(after(601)))
        kept.apply(.switching(byPlayer:true,after(700)));kept.apply(.channel(nil,after(700)));kept.apply(.channel(.match,after(702)))
        precondition(kept.state(at:after(710)) == .match(since:after(600)))
        kept.apply(.matchChatClosed(after(800)))
        precondition(kept.state(at:after(801)) == .unknown,"a chosen match channel says nothing once the game is left")
        // The player choosing a channel before the match was told (a team channel held for less than ten
        // seconds) keeps nothing; the game putting them in the group's voice claims nothing either.
        var early=PresenceTracker()
        early.apply(.voiceReady(after(10)));early.apply(.channel(.team,after(100)))
        early.apply(.switching(byPlayer:true,after(103)));early.apply(.channel(nil,after(103)));early.apply(.channel(.party,after(105)))
        precondition(early.state(at:after(200)) == .unknown)
        early.apply(.switching(byPlayer:false,after(300)));early.apply(.channel(nil,after(300)));early.apply(.channel(.party,after(302)))
        precondition(early.state(at:after(400)) == .unknown && !early.chosen)
        // Matches this run of the game, each once: a backed-out load and the Practice Range are none, a voice
        // switch mid-match is the same match, and a whole log read at once counts them all.
        var count=PresenceTracker()
        count.apply(.voiceReady(after(10)))
        count.apply(.channel(.team,after(20)));count.apply(.channel(nil,after(24)))
        precondition(count.matches(at:after(30)) == 0)
        count.apply(mate(after(99)));count.apply(.channel(.team,after(100)))
        precondition(count.matches(at:after(105)) == 0 && count.matches(at:after(111)) == 1,"the match going on counts once it holds")
        count.apply(.switching(byPlayer:true,after(300)));count.apply(.channel(nil,after(300)));count.apply(.channel(.party,after(302)))
        count.apply(.matchOver(after(700)));count.apply(.channel(nil,after(720)))
        precondition(count.matches(at:after(721)) == 1)
        count.apply(.channel(.team,after(800)));count.apply(.channel(nil,after(900)))
        precondition(count.matches(at:after(901)) == 1,"a team channel with nobody else in it is no match")
        count.apply(mate(after(999)));count.apply(.channel(.team,after(1000)));count.apply(.channel(nil,after(1600)))
        precondition(count.matches(at:after(1601)) == 2 && count.played == 2)
        count.apply(.reset)
        precondition(count.matches(at:after(1700)) == 0,"the game opening again starts the count over")
        // A channel nobody has seen is not guessed at.
        tracker.apply(.channel(.other,after(2500)))
        precondition(tracker.state(at:after(2501)) == .unknown)
        // The voice service going down (the game closing) and the log starting over clear everything.
        tracker.apply(.channel(.team,after(2550)));tracker.apply(.voiceClosed(after(2600)))
        precondition(tracker.state(at:after(2700)) == .unknown && !tracker.others)
        tracker.apply(.voiceReady(after(2800)));tracker.apply(mate(after(2805)));tracker.apply(.channel(.team,after(2810)));tracker.apply(.reset)
        precondition(tracker.state(at:after(2900)) == .unknown && !tracker.others)
        // A join with no menu line before it (the line was missed) still counts as a match, with the team in it.
        tracker.apply(.channel(.team,after(3000)));tracker.apply(mate(after(3001)))
        precondition(tracker.state(at:after(3100)) == .match(since:after(3000)))
        // Lines from before the game opened are an earlier run's.
        var late=PresenceTracker(notBefore:after(1000))
        late.apply(.voiceReady(after(900)));late.apply(mate(after(949)));late.apply(.channel(.team,after(950)));late.apply(.channel(.party,after(960)))
        precondition(late.state(at:after(2000)) == .unknown && !late.others)
        late.apply(.voiceReady(after(1026)));late.apply(.channel(.team,after(1100)));late.apply(mate(after(1101)))
        precondition(late.state(at:after(2000)) == .match(since:after(1100)))
        // A reconnect (the team's channel dropped and joined again within two minutes, no results between) is the same
        // match: timed from its start, counted once.
        var again=PresenceTracker()
        again.apply(.voiceReady(after(10)));again.apply(mate(after(99)));again.apply(.channel(.team,after(100)))
        again.apply(.channel(nil,after(400)));again.apply(mate(after(459)));again.apply(.channel(.team,after(460)))
        precondition(again.state(at:after(500)) == .match(since:after(100)) && again.matches(at:after(500)) == 1)
        // A match with nobody else in team voice still counts, when its results show.
        var solo=PresenceTracker()
        solo.apply(.voiceReady(after(10)));solo.apply(.channel(.team,after(100)));solo.apply(.matchOver(after(640)));solo.apply(.channel(nil,after(660)))
        precondition(solo.matches(at:after(700)) == 1 && solo.heard && solo.reachedMenus)
        // Every voice flag off while chat stays on is the player's choice: the match goes on. With chat off too, the
        // game is closing.
        var off=PresenceTracker()
        off.apply(.chatEnabled(true,after(5)));off.apply(.voiceReady(after(10)));off.apply(mate(after(99)));off.apply(.channel(.team,after(100)))
        off.apply(.voiceClosed(after(300)))
        precondition(off.state(at:after(301)) == .match(since:after(100)))
        off.apply(.chatEnabled(false,after(400)));off.apply(.voiceClosed(after(401)))
        precondition(off.state(at:after(402)) == .unknown)
        // Team Voice turned off: no more menus claimed.
        var teamOff=PresenceTracker()
        teamOff.apply(.voiceReady(after(10)));teamOff.apply(.voiceOff(after(20)))
        precondition(teamOff.state(at:after(21)) == .unknown)
        // The game asked to join the team's channel and no channel line came (missed, or changed): not the menus.
        var asked=PresenceTracker()
        asked.apply(.voiceReady(after(10)));asked.apply(.joining(.team,id:"T",after(100)))
        precondition(asked.state(at:after(200)) == .unknown)
        asked.apply(.channel(.team,after(201)));asked.apply(.channel(nil,after(205)))
        precondition(asked.state(at:after(206)) == .menu)
        // The Mac asleep past a night's end: the match it was in is over, and tonight's count starts over (the run keeps
        // them all).
        var dozing=PresenceTracker()
        dozing.apply(.voiceReady(after(10)));dozing.apply(mate(after(99)));dozing.apply(.channel(.team,after(100)));dozing.apply(.matchOver(after(700)))
        dozing.apply(.channel(nil,after(720)));dozing.apply(mate(after(799)));dozing.apply(.channel(.team,after(800)))
        precondition(dozing.matches(at:after(900)) == 2 && dozing.tonight(at:after(900)) == 2)
        dozing.slept(at:after(900),newNight:true)
        precondition(dozing.state(at:after(901)) == .menu && dozing.matches(at:after(901)) == 2 && dozing.tonight(at:after(901)) == 0)
        // In the group's voice the matches go untold: the run's count is unknown.
        var group=PresenceTracker()
        group.apply(.voiceReady(after(10)));group.apply(.channel(.party,after(20)))
        precondition(group.grouped && !PresenceTracker().heard)
    }

    static func cards() {
        let texts=PresenceTexts(menu:"In Menus",match:"In Match",voice:"In Group Voice",badge:"Playing on Mac with Recall")
        let launched=Date(timeIntervalSince1970:1_792_000_000),since=Date(timeIntervalSince1970:1_792_000_600)
        func start(_ card:[String:Any])->Int? { (card["timestamps"] as? [String:Int])?["start"] }
        // Normal is what a PC player gets, whatever the log says: the game, and the time since it opened; with the
        // Mac badge, as at every level.
        func badge(_ card:[String:Any])->[String:String]? { card["assets"] as? [String:String] }
        for state in [PresenceState.unknown,.menu,.match(since:since)] {
            let card=PresenceCard.activity(facts:PresenceFacts(place:state,voice:GroupVoice(count:3,channel:"773141270",party:"a1b2")),level:.normal,launched:launched,texts:texts)
            precondition(card["type"] as? Int == 0 && start(card) == 1_792_000_000 && card["details"] == nil && card["party"] == nil && card["state"] == nil)
            precondition(badge(card) == ["small_image":DiscordAssets.macBadge.absoluteString,"small_text":"Playing on Mac with Recall"])
        }
        // Menus and a match can't be told apart: only that the game is on (in the group's voice, its line says so).
        let unknown=PresenceCard.activity(facts:PresenceFacts(place:.unknown),level:.live,launched:launched,texts:texts)
        precondition(unknown["details"] as? String == "In Game" && start(unknown) == 1_792_000_000)
        let unknownGroup=PresenceCard.activity(facts:PresenceFacts(place:.unknown,voice:GroupVoice(count:3,channel:"P",party:"a")),level:.live,launched:launched,texts:texts)
        precondition(unknownGroup["details"] == nil && unknownGroup["state"] as? String == "In Group Voice")
        let menu=PresenceCard.activity(facts:PresenceFacts(place:.menu),level:.live,launched:launched,texts:texts)
        precondition(menu["details"] as? String == "In Menus" && start(menu) == 1_792_000_000)
        let match=PresenceCard.activity(facts:PresenceFacts(place:.match(since:since)),level:.live,launched:launched,texts:texts)
        precondition(match["details"] as? String == "In Match" && start(match) == 1_792_000_600)
        precondition(menu["state"] == nil && menu["party"] == nil)
        // In the group's voice chat: Discord shows "In Group Voice (3 of 6)" under where the player is (nothing,
        // when the log cannot say). The party's size is the voice chat's, which the line names.
        let group=PresenceCard.activity(facts:PresenceFacts(place:.unknown,voice:GroupVoice(count:3,channel:"773141270",party:"a1b2")),level:.live,launched:launched,texts:texts)
        let party=group["party"] as? [String:Any],id=party?["id"] as? String
        precondition(group["details"] == nil && group["state"] as? String == "In Group Voice" && party?["size"] as? [Int] == [3,5])
        let voiced=PresenceCard.activity(facts:PresenceFacts(place:.match(since:since),voice:GroupVoice(count:3,channel:"773141270",party:"a1b2")),level:.live,launched:launched,texts:texts)
        precondition(voiced["details"] as? String == "In Match" && voiced["state"] as? String == "In Group Voice" && start(voiced) == 1_792_000_600)
        precondition(id == "a1b2")
        precondition(JSONSerialization.isValidJSONObject(voiced))
        // Never more than six of six.
        let crowded=PresenceCard.activity(facts:PresenceFacts(place:.menu,voice:GroupVoice(count:8,channel:"x",party:"c3")),level:.live,launched:launched,texts:texts)
        precondition((crowded["party"] as? [String:Any])?["size"] as? [Int] == [6,6])
        // The Mac badge, loaded from the repository, on every Live card; its words never use the logo's private character,
        // which Discord off Apple's systems can't draw.
        for card in [unknown,menu,group,match] {
            let assets=card["assets"] as? [String:String]
            precondition(assets?["small_image"] == DiscordAssets.macBadge.absoluteString && assets?["small_text"] == "Playing on Mac with Recall" && assets?["large_image"] == nil)
        }
        precondition(DiscordAssets.macBadge.scheme == "https" && DiscordAssets.badge.scheme == "https" && DiscordAssets.applicationID == "356875221078245376")
        precondition(!PresenceTexts.app.badge.contains("\u{F8FF}"))
        precondition(JSONSerialization.isValidJSONObject(match))
        // Discord wants two characters at least in a line, and no more than 128.
        precondition((2...128).contains((menu["details"] as! String).count) && (2...128).contains((match["details"] as! String).count) && (2...128).contains((group["state"] as! String).count))
        precondition(DiscordPresenceLevel.allCases == [.normal,.live,.full,.custom] && DiscordPresenceLevel(rawValue:"gone") == nil && DiscordPresenceLevel.standard == .live)
    }

    static func socketPlaces() {
        // Discord's sockets are searched for in this user's own temporary folder only.
        let paths=DiscordIPC.defaultPaths()
        precondition(paths.count == 10 && paths.allSatisfy { $0.hasPrefix(NSTemporaryDirectory()) && !$0.hasPrefix("/tmp/") && $0.hasSuffix("discord-ipc-\(paths.firstIndex(of:$0)!)") })
    }

    static func processStart() {
        // The test's own process: started in the last minute, and not in the future. A pid that is gone has none.
        let started=DiscordPresence.startTime(of:getpid())
        precondition(started != nil && Date().timeIntervalSince(started!) >= 0 && Date().timeIntervalSince(started!) < 120)
        precondition(DiscordPresence.startTime(of:99_999_999) == nil)
    }

    static func location() {
        let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("ow2-root-\(getpid())")
        defer { try? FileManager.default.removeItem(at:root) }
        let fm=FileManager.default,users=root.appendingPathComponent("environment/drive_c/users")
        precondition(OverwatchLogTail.logURL(root:root) == nil)
        try! fm.createDirectory(at:users.appendingPathComponent("Public"),withIntermediateDirectories:true)
        precondition(OverwatchLogTail.logURL(root:root) == nil)
        try! fm.createDirectory(at:users.appendingPathComponent("crossover"),withIntermediateDirectories:true)
        precondition(OverwatchLogTail.logURL(root:root)?.path.hasSuffix("users/crossover/Documents/Overwatch/Logs/Overwatch.log") == true)
        try! fm.createDirectory(at:users.appendingPathComponent("zed/Documents/Overwatch/Logs"),withIntermediateDirectories:true)
        precondition(OverwatchLogTail.logURL(root:root)?.path.contains("users/zed/") == true)
        // Two users with a log: the one written last, whatever the names' order.
        let logs=users.appendingPathComponent("anna/Documents/Overwatch/Logs");try! fm.createDirectory(at:logs,withIntermediateDirectories:true)
        let zed=users.appendingPathComponent("zed/Documents/Overwatch/Logs/Overwatch.log"),anna=logs.appendingPathComponent("Overwatch.log")
        fm.createFile(atPath:zed.path,contents:Data());fm.createFile(atPath:anna.path,contents:Data())
        try! fm.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-86_400)],ofItemAtPath:anna.path)
        precondition(OverwatchLogTail.logURL(root:root)?.path.contains("users/zed/") == true)
        try! fm.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-172_800)],ofItemAtPath:zed.path)
        precondition(OverwatchLogTail.logURL(root:root)?.path.contains("users/anna/") == true)
    }

    static func folder()->URL {
        let url=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("ow2-log-\(getpid())-\(UInt32.random(in:0..<1_000_000))")
        try! FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    static func append(_ text:String,to url:URL) {
        let handle=try! FileHandle(forWritingTo:url)
        handle.seekToEndOfFile();handle.write(Data(text.utf8));try? handle.close()
    }
    static func kinds(_ events:[PresenceEvent])->[String] {
        events.map { switch $0 { case .reset:return "reset";case .voiceReady:return "ready";case .voiceClosed:return "closed";case .voiceOff:return "voiceOff";case .chatEnabled:return "chat"
                                 case .channel(.team?,_):return "joined";case .channel(.party?,_):return "party";case .channel(.other?,_):return "other";case .channel(.match?,_):return "postgame";case .channel(nil,_):return "left";case .member:return "member";case .memberLeft:return "memberLeft";case .joining:return "joining";case .switching:return "switching";case .matchChatClosed:return "chatClosed";case .matchOver:return "over" } }
    }

    static func tail() {
        let dir=folder(),log=dir.appendingPathComponent("Overwatch.log"),now=Date()
        defer { try? FileManager.default.removeItem(at:dir) }
        // Opened in the middle of a game: what is already there is read first.
        try! (logLine("prism: Info: GPU 0",at:now)+"\r\n"+logLine(ready,at:now)+"\r\n"+logLine(join,at:now)+"\r\n").write(to:log,atomically:true,encoding:.utf8)
        let seen=Collected<PresenceEvent>()
        let follower=OverwatchLogTail(url:log,queue:DispatchQueue(label:"test-tail")) { seen.add($0) }
        follower.start()
        precondition(wait { kinds(seen.all) == ["ready","joined"] },"replay: \(kinds(seen.all))")
        // What is added is read as it comes; a line is told only when it is whole.
        append(logLine(leave,at:now),to:log)
        Thread.sleep(forTimeInterval:0.3)
        precondition(kinds(seen.all) == ["ready","joined"])
        append("\r\n",to:log)
        precondition(wait { kinds(seen.all) == ["ready","joined","left"] },"append: \(kinds(seen.all))")
        // The game starts the log over when it opens again: shorter, same file.
        try! (logLine(ready,at:now)+"\r\n").write(to:log,atomically:false,encoding:.utf8)
        precondition(wait { kinds(seen.all) == ["ready","joined","left","reset","ready"] },"truncated: \(kinds(seen.all))")
        // Or it is another file.
        try? FileManager.default.removeItem(at:log)
        try! (logLine("prism: Info: GPU 0",at:now)+"\r\n"+logLine(ready,at:now)+"\r\n"+logLine(join,at:now)+"\r\n").write(to:log,atomically:true,encoding:.utf8)
        precondition(wait { kinds(seen.all).suffix(3) == ["reset","ready","joined"] },"replaced: \(kinds(seen.all))")
        follower.stop()
        append(logLine(leave,at:now)+"\r\n",to:log)
        Thread.sleep(forTimeInterval:0.3)
        precondition(kinds(seen.all).last == "joined","a stopped follower says nothing more")

        // A log that is not there yet (the game's first run) is picked up when it appears, and so is one
        // whose folders the game makes later, however much later: the watch moves down as each appears.
        let later=dir.appendingPathComponent("later")
        try! FileManager.default.createDirectory(at:later,withIntermediateDirectories:true)
        let newLog=later.appendingPathComponent("Overwatch.log")
        let fresh=Collected<PresenceEvent>()
        let waiting=OverwatchLogTail(url:newLog,queue:DispatchQueue(label:"test-tail-2")) { fresh.add($0) }
        waiting.start()
        Thread.sleep(forTimeInterval:0.2)
        try! (logLine(ready,at:now)+"\r\n").write(to:newLog,atomically:true,encoding:.utf8)
        precondition(wait { kinds(fresh.all).contains("ready") },"created: \(kinds(fresh.all))")
        let deep=dir.appendingPathComponent("Documents/Overwatch/Logs"),deepLog=deep.appendingPathComponent("Overwatch.log")
        let made=Collected<PresenceEvent>()
        let unmade=OverwatchLogTail(url:deepLog,queue:DispatchQueue(label:"test-tail-3")) { made.add($0) }
        unmade.start()
        Thread.sleep(forTimeInterval:0.2)
        try! FileManager.default.createDirectory(at:dir.appendingPathComponent("Documents"),withIntermediateDirectories:false)
        Thread.sleep(forTimeInterval:0.2)
        try! FileManager.default.createDirectory(at:deep,withIntermediateDirectories:true)
        try! (logLine(ready,at:now)+"\r\n").write(to:deepLog,atomically:true,encoding:.utf8)
        // Within a second or two, not at a timer's next look.
        precondition(wait(2) { kinds(made.all).contains("ready") },"folders made later: \(kinds(made.all))")
        // Stopped from another follower's queue, it waits for its own queue rather than running on the other one.
        let other=DispatchQueue(label:"test-tail-4")
        _ = OverwatchLogTail(url:newLog,queue:other) { _ in }
        other.sync { waiting.stop() }
        append(logLine(join,at:now)+"\r\n",to:newLog)
        Thread.sleep(forTimeInterval:0.3)
        precondition(!kinds(fresh.all).contains("joined"),"stopped from another queue: \(kinds(fresh.all))")
        unmade.stop()
    }

    static func connection() {
        let server=FakeDiscord()
        let client=DiscordIPC(applicationID:"1234",paths:[server.path],pid:4242,spacing:0.5,burst:100,retry:0.3)
        client.set(["type":0,"details":"In Menus"])
        guard let fd=server.accept(),let hello=server.welcome(fd) else { preconditionFailure("no handshake") }
        precondition(hello["v"] as? Int == 1 && hello["client_id"] as? String == "1234")
        guard let first=server.frame(fd) else { preconditionFailure("no card") }
        precondition(first.opcode == DiscordFrame.frame && first.json["cmd"] as? String == "SET_ACTIVITY" && !(first.json["nonce"] as? String ?? "").isEmpty)
        let args=first.json["args"] as! [String:Any]
        precondition(args["pid"] as? Int == 4242 && (args["activity"] as! [String:Any])["details"] as? String == "In Menus")
        precondition(wait { client.connected } && !client.accepted)
        // Discord answers each card: taken, or refused with an error.
        server.send(fd,DiscordFrame.frame,["cmd":"SET_ACTIVITY","evt":NSNull(),"data":[:],"nonce":first.json["nonce"]!])
        precondition(wait { client.accepted })
        server.send(fd,DiscordFrame.frame,["cmd":"SET_ACTIVITY","evt":"ERROR","data":["code":4000,"message":"no"],"nonce":"n"])
        precondition(wait { !client.accepted } && client.connected)
        // Discord's ping is answered, or it hangs up.
        server.send(fd,DiscordFrame.ping,["nonce":"x"])
        precondition(server.frame(fd)?.opcode == DiscordFrame.pong)
        // Updates faster than the spacing are one: the last.
        client.set(["details":"one"]);client.set(["details":"two"])
        let asked=Date()
        precondition(details(server.card(fd)) == "two" && Date().timeIntervalSince(asked) > 0.05)
        // Taking the card down says so and closes.
        client.stop()
        precondition((server.card(fd) ?? nil) is NSNull && server.closed(fd) && !client.connected)
    }

    static func reconnect() {
        let server=FakeDiscord()
        let client=DiscordIPC(applicationID:"1234",paths:[server.path],spacing:0.1,burst:100,retry:0.3)
        client.set(["details":"A"])
        guard let first=server.accept(),server.welcome(first) != nil else { preconditionFailure("no handshake") }
        precondition(details(server.card(first)) == "A")
        // Discord closes (it was restarted); what is wanted when it is back is the latest card.
        Darwin.close(first)
        client.set(["details":"B"])
        guard let second=server.accept(),server.welcome(second) != nil else { preconditionFailure("no second handshake") }
        precondition(details(server.card(second)) == "B")
        client.stop()
    }

    static func absent() {
        // No Discord open: nothing to talk to, and nothing goes wrong.
        let client=DiscordIPC(paths:["/tmp/ow2-no-such-discord-\(getpid())/discord-ipc-0"],spacing:0.1,retry:0.2)
        client.set(["details":"A"])
        Thread.sleep(forTimeInterval:0.5)
        precondition(!client.connected)
        // Many cards meanwhile (a whole evening's matches) still look for Discord once per wait, not once per card.
        for n in 0..<20 { client.set(["details":"\(n)"]) }
        let looked=client.attempts
        Thread.sleep(forTimeInterval:1.1)
        precondition(client.attempts-looked <= 7,"\(client.attempts-looked) looks in 1.1 s with a 0.2 s wait")
        client.stop()
    }

    /// Discord's five updates in twenty seconds: a burst goes at once (spaced a little), the next waits for the window.
    static func rate() {
        let server=FakeDiscord()
        let client=DiscordIPC(applicationID:"1234",paths:[server.path],spacing:0.05,burst:3,window:1.5,retry:0.3)
        client.set(["details":"0"])
        guard let fd=server.accept(),server.welcome(fd) != nil,server.card(fd) != nil else { preconditionFailure("no handshake") }
        let start=Date()
        for n in 1...3 { client.set(["details":"\(n)"]);Thread.sleep(forTimeInterval:0.15) }
        // The first of the burst went at the start; two more by 0.5 s; the next only once the window has passed it.
        precondition(details(server.card(fd)) == "1" && details(server.card(fd)) == "2" && Date().timeIntervalSince(start) < 1.0)
        precondition(details(server.card(fd,3000)) == "3" && Date().timeIntervalSince(start) > 1.2,"the fourth update in a window waits for it")
        client.stop()
    }

    /// A player pressing the Settings control over and over: Discord gets no more than its allowance, and what it
    /// ends up showing is the last choice.
    static func spam() {
        let server=FakeDiscord(),dir=folder(),log=dir.appendingPathComponent("Overwatch.log")
        defer { try? FileManager.default.removeItem(at:dir) }
        let texts=PresenceTexts(menu:"In Menus",match:"In Match",voice:"In Group Voice",badge:"Playing on Mac")
        let opened=Date().addingTimeInterval(-90)
        try! (logLine(ready,at:opened.addingTimeInterval(26))+"\r\n").write(to:log,atomically:true,encoding:.utf8)
        let presence=DiscordPresence(level:.live,texts:texts,ipc:DiscordIPC(applicationID:"1234",paths:[server.path],spacing:0.05,burst:3,window:1.5,retry:0.3))
        presence.begin(logURL:log,launched:opened)
        guard let fd=server.accept(),server.welcome(fd) != nil,details(server.card(fd)) == "In Menus" else { preconditionFailure("no first card") }
        let start=Date()
        for n in 0..<60 { presence.update(level:n % 2 == 0 ? .normal : .live,texts:texts) }
        // 60 changes; the last (n = 59) is Live.
        var seen:[String?]=[]
        while let card=server.card(fd,2500) { seen.append(details(card));if Date().timeIntervalSince(start) > 6 { break } }
        precondition(seen.count <= 3,"60 presses became \(seen.count) updates")
        precondition(seen.last as? String == "In Menus","the last choice (Live) is what ends up shown: \(seen)")
        presence.end()
    }

    /// A card Discord refuses is sent again leaner (no buttons, party or pictures, then the timer alone), until the
    /// next READY; a close for a listing Discord doesn't know stops asking until the next game. Discord's last answer
    /// is kept for the support report.
    static func refusals() {
        let server=FakeDiscord()
        let ipc=DiscordIPC(applicationID:"1234",paths:[server.path],spacing:0.05,burst:100,retry:0.3)
        let card:[String:Any]=["type":0,"details":"In Menus","timestamps":["start":1],"assets":["small_image":"https://x/b.png"],
                               "buttons":[["label":"Get Recall","url":"https://github.com/x"]]]
        ipc.set(card)
        guard let fd=server.accept(),server.welcome(fd) != nil,let first=server.frame(fd) else { preconditionFailure("no card") }
        precondition(((first.json["args"] as? [String:Any])?["activity"] as? [String:Any])?["buttons"] != nil)
        func refuse(_ message:[String:Any]) {
            server.send(fd,DiscordFrame.frame,["cmd":"SET_ACTIVITY","evt":"ERROR","nonce":message["nonce"] ?? "","data":["code":4000,"message":"bad"]])
        }
        refuse(first.json)
        guard let second=server.frame(fd),let lean=(second.json["args"] as? [String:Any])?["activity"] as? [String:Any] else { preconditionFailure("no leaner card") }
        precondition(lean["buttons"] == nil && lean["assets"] == nil && lean["details"] as? String == "In Menus","\(lean)")
        refuse(second.json)
        guard let third=server.frame(fd),let bare=(third.json["args"] as? [String:Any])?["activity"] as? [String:Any] else { preconditionFailure("no bare card") }
        precondition(Set(bare.keys) == ["type","timestamps"] && ipc.lastAnswer == "refused_4000","\(bare) \(String(describing:ipc.lastAnswer))")
        refuse(third.json)
        precondition(server.frame(fd,600) == nil,"no fourth try")
        // The account READY names comes out scrambled, the same each time, never the id itself.
        let account=DiscordIPC.scrambled("123456789012345678")
        precondition(account == DiscordIPC.scrambled("123456789012345678") && account != DiscordIPC.scrambled("123456789012345679")
                     && !account.contains("123456789") && account.count == 24)
        // Closed for a listing Discord doesn't know: no reconnecting until the next game.
        server.send(fd,DiscordFrame.close,["code":4000,"message":"Invalid Client ID"])
        precondition(server.closed(fd) && server.accept(800) == nil && ipc.lastAnswer == "closed_4000")
        ipc.stop()
        precondition(ipc.lastAnswer == "closed_4000","the answer outlives stop()")
    }

    /// Discord's limits, applied to every card: lines and hover texts at 128 (UTF-16, cut at a whole character),
    /// nothing under two, no control or direction characters, https pictures of 300 characters at most, two buttons
    /// with labels of 1 to 32, a party with a real size.
    static func rules() {
        let long=String(repeating:"é",count:200),emoji=String(repeating:"👩‍👩‍👧",count:30)
        let clean=DiscordRules.clean(["details":long,"state":" x ","assets":["large_text":emoji,"small_text":"a\u{202E}b\u{0007}c","large_image":"http://x/a.png","small_image":"https://x/"+String(repeating:"a",count:300)],
                                      "buttons":[["label":"","url":"https://a"],["label":"One","url":"https://a"],["label":"Two","url":"http://b"],["label":"Three","url":"https://c"],["label":"Four","url":"https://d"]],
                                      "party":["id":"p","size":[3,6]]])
        precondition((clean["details"] as? String)?.utf16.count == 128 && (clean["details"] as? String)?.hasSuffix("…") == true && clean["state"] == nil)
        let assets=clean["assets"] as? [String:String]
        precondition(assets?["small_text"] == "abc" && assets?["large_image"] == nil && assets?["small_image"] == nil,"\(String(describing:assets))")
        precondition((assets?["large_text"]?.utf16.count ?? 999) <= 128 && assets?["large_text"]?.dropLast().allSatisfy({ $0 == "👩‍👩‍👧" }) == true,"cut between whole emoji")
        precondition((clean["buttons"] as? [[String:String]])?.map { $0["label"]! } == ["One","Three"] && clean["party"] == nil)
        precondition(DiscordRules.clean(["party":["id":"party-id","size":[3,6]]])["party"] != nil && DiscordRules.clean(["party":["id":"party-id","size":[7,6]]])["party"] == nil)
    }

    /// Another Discord account than the profile's never gets the profile, not even the first card after READY.
    static func otherAccount() {
        for (signedIn,shows) in [("222222222222222222",false),("111111111111111111",true)] {
            let server=FakeDiscord()
            let texts=PresenceTexts(menu:"In Menus",match:"In Match",voice:"In Group Voice",badge:"Playing on Mac")
            let presence=DiscordPresence(level:.full,texts:texts,ipc:DiscordIPC(applicationID:"1234",paths:[server.path],spacing:0.05,burst:100,retry:0.3))
            presence.owner=DiscordIPC.scrambled("111111111111111111")
            // The BattleTag's name alone is the owner's too.
            presence.update(career:signedIn.hasPrefix("2") ? nil : CareerCard(identity:CareerIdentity(name:"pyxee",title:nil,endorsement:nil,avatar:nil)),tagName:"pyxee")
            presence.begin(logURL:nil,launched:Date())
            guard let fd=server.accept(),let hello=server.frame(fd),hello.opcode == DiscordFrame.handshake else { preconditionFailure("no handshake") }
            server.send(fd,DiscordFrame.frame,["cmd":"DISPATCH","evt":"READY","data":["v":1,"user":["id":signedIn]]])
            let first=server.card(fd)
            let words=String(describing:first ?? nil)
            precondition(words.contains("pyxee") == shows,"\(signedIn): \(words)")
            presence.end()
        }
    }

    static func endToEnd() {
        let server=FakeDiscord(),dir=folder(),log=dir.appendingPathComponent("Overwatch.log")
        defer { try? FileManager.default.removeItem(at:dir) }
        let texts=PresenceTexts(menu:"In Menus",match:"In Match",voice:"In Group Voice",badge:"Playing on Mac")
        let opened=Date().addingTimeInterval(-90)
        try! (logLine("prism: Info: GPU 0",at:opened)+"\r\n").write(to:log,atomically:true,encoding:.utf8)
        let presence=DiscordPresence(level:.live,texts:texts,ipc:DiscordIPC(applicationID:"1234",paths:[server.path],spacing:0.1,burst:100,retry:0.3))
        presence.begin(logURL:log,launched:opened)
        guard let fd=server.accept(),server.welcome(fd) != nil else { preconditionFailure("no handshake") }
        // Before the menus: the game and a timer, and the badge, with no claim about menus or a match.
        var card=(server.card(fd) ?? nil) as! [String:Any]
        precondition(card["details"] as? String == "In Game" && card["assets"] != nil && (card["timestamps"] as! [String:Int])["start"] == Int(opened.timeIntervalSince1970))
        append(logLine(ready,at:opened.addingTimeInterval(26))+"\r\n",to:log)
        precondition(details(server.card(fd)) == "In Menus")
        // A match that is backed out of while loading never shows.
        let blip=Date()
        append(logLine(join,at:blip)+"\r\n"+logLine(leave,at:blip.addingTimeInterval(2))+"\r\n",to:log)
        let backedOut=server.card(fd,1200)
        precondition(backedOut == nil || details(backedOut) != "In Match")
        // One that holds is a match, timed from its start, and menus again after.
        let started=Date().addingTimeInterval(-30)
        append(logLine(teammate,at:started)+"\r\n"+logLine(join,at:started)+"\r\n",to:log)
        let shown=server.card(fd)
        // The log keeps milliseconds; the card the second.
        let logged=stamper.date(from:stamper.string(from:started))!
        precondition(details(shown) == "In Match" && (((shown ?? nil) as! [String:Any])["timestamps"] as! [String:Int])["start"] == Int(logged.timeIntervalSince1970))
        append(logLine(leave,at:Date())+"\r\n",to:log)
        precondition(details(server.card(fd)) == "In Menus")
        // A group: the game keeps only the group's channel, so neither menus nor a match is claimed.
        append(logLine("==[VC] Request join channel PARTY 773141270 2e153316",at:Date())+"\r\n"+logLine(yourself.replacingOccurrences(of:"603564719",with:"773141270"),at:Date())+"\r\n"+logLine(partyJoin,at:Date())+"\r\n",to:log)
        func size(_ card:Any??)->[Int]? { (((card ?? nil) as? [String:Any])?["party"] as? [String:Any])?["size"] as? [Int] }
        // Nobody else in its voice yet: no group voice to tell, only that the game is on.
        var grouped=server.card(fd)
        precondition(details(grouped) as? String == "In Game" && size(grouped) == nil,"\(String(describing:grouped))")
        // A friend joins the group's voice chat, and leaves it (the lines as a real group's log has them).
        append(logLine("#=[VC] MemberAdded 773141270 2e153316 844fe725@4a95b6d2 11b8077a false",at:Date())+"\r\n",to:log)
        grouped=server.card(fd)
        precondition(details(grouped) == nil && ((grouped ?? nil) as? [String:Any])?["state"] as? String == "In Group Voice" && size(grouped) == [2,5])
        append(logLine("#=[VC] MemberRemoved 773141270 2e153316 844fe725@4a95b6d2 11b8077a 0",at:Date())+"\r\n",to:log)
        let alone=server.card(fd)
        precondition(size(alone) == nil && details(alone) as? String == "In Game")
        append(logLine(partyLeave,at:Date())+"\r\n",to:log)
        precondition(details(server.card(fd)) == "In Menus")
        // Normal says nothing the game says; the badge stays.
        presence.update(level:.normal,texts:texts)
        card=(server.card(fd) ?? nil) as! [String:Any]
        precondition(card["details"] == nil && card["state"] == nil && card["assets"] != nil)
        presence.update(level:.live,texts:texts)
        // The log is read again before anything is shown: the first card is the right one, with no empty one before it.
        precondition(details(server.card(fd,2000)) == "In Menus","back at Live the log is read again from the start")
        precondition(server.card(fd,400) == nil,"and nothing else follows")
        // The game closing takes the card down.
        presence.end()
        precondition((server.card(fd) ?? nil) is NSNull && server.closed(fd))
    }
}
