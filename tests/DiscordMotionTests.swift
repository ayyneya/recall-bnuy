import SwiftUI
import AppKit

// The Discord tab's motion (DiscordDesign.swift, DiscordProfile.swift): the design's easings against anime.js's own
// numbers, keyframes and how a new animation takes over from one still running, the glides' shape, and the picture's
// easter eggs as clicks plan them (pumps, letting them out, settling, the burst and its pieces).
// Build and run (the app's sources but Main.swift, whose place this takes):
//   swiftc -O -target arm64-apple-macos26.5 -parse-as-library $(find app/Sources -name "*.swift" ! -name Main.swift) \
//     tests/DiscordMotionTests.swift -o runtime/phase-3/discord-motion-tests
//   runtime/phase-3/discord-motion-tests

/// Main.swift's delegate, which the setup screens point at; never called here.
final class AppDelegate: NSObject { @objc func forceQuit() {} }

@main struct DiscordMotionTests {
    @MainActor static func main() {
        editing()
        easings()
        tweens()
        glides()
        pumps()
        cracks()
        burst()
        quote()
        sweep()
        print("PASS: the design's easings, keyframes taking over, the glides, the picture's pumps, settling, cracks and burst, the quote's wobble, and the sessions swept away")
    }
    static func close(_ a:Double,_ b:Double,_ within:Double=0.0001)->Bool { abs(a-b) <= within }

    /// anime.js's own values, read from the design's page (an animation of 0 to 1, sought to each point).
    static func easings() {
        let at=[0.1,0.25,0.4,0.5,0.6,0.75,0.9]
        let anime:[(Ease,[Double])]=[
            (.outQuad,[0.19,0.4375,0.64,0.75,0.84,0.9375,0.99]),
            (.inQuad,[0.01,0.0625,0.16,0.25,0.36,0.5625,0.81]),
            (.inOutQuad,[0.02,0.125,0.32,0.5,0.68,0.875,0.98]),
            (.outCubic,[0.271,0.57813,0.784,0.875,0.936,0.98438,0.999]),
            (.outExpo,[0.5,0.82322,0.9375,0.96875,0.98438,0.99448,0.99805]),
            (.inOutSine,[0.02447,0.14645,0.34549,0.5,0.65451,0.85355,0.97553]),
            (.outBounce,[0.07562,0.47266,0.91,0.76563,0.7725,0.97266,0.98813]),
            (.outBack(2),[0.433,0.85938,1.072,1.125,1.128,1.07813,1.017]),
            (.outBack(1.8),[0.4168,0.83125,1.0432,1.1,1.1088,1.06875,1.0152]),
            (.outElastic(1,0.42),[0.96263,1.14606,0.94028,0.98858,1.01408,0.99877,0.99878]),
            (.outElastic(1,0.5),[0.84549,1.17678,0.98069,0.96875,0.99517,1.00552,0.9994]),
            (.outElastic(1,0.45),[0.91318,1.16612,0.95212,0.97606,1.00781,1.00276,0.99805]),
            (.outElastic(1,0.38),[1.04129,1.09669,0.94089,1.01255,1.01374,0.99455,1.00132]),
        ]
        for (curve,values) in anime {
            for (t,value) in zip(at,values) { precondition(close(curve(t),value,0.00001),"\(curve) at \(t): \(curve(t)), anime.js \(value)") }
            precondition(close(curve(0),0) && close(curve(1),1),"\(curve) runs from 0 to 1")
        }
        // CSS's ease, halfway.
        precondition(close(Ease.css(0.5),0.8024,0.0005),"\(Ease.css(0.5))")
        // The design's spring settles at 1, overshooting on the way.
        precondition(Ease.spring(1) == 1 && (0...100).map { Ease.spring(Double($0)/100) }.max()! > 1.05)
    }

    /// Keyframes run one after another, each from where the last ended; a new animation of a value takes over from where
    /// the old one had got to; the pumped bulge's are the design's canvas, where the newest still running shows.
    static func tweens() {
        let tween=Tween(start:1,from:0,keys:[.init(to:10,duration:1,delay:0.5,curve:.linear),.init(to:4,duration:2,curve:.linear)])
        precondition(tween.value(at:0) == 0 && tween.value(at:1.25) == 0 && tween.value(at:2) == 5 && tween.value(at:2.5) == 10)
        precondition(tween.value(at:3.5) == 7 && tween.value(at:9) == 4 && tween.end == 4.5 && tween.last == 4)
        var track=Track(1)
        precondition(track.value(at:5) == 1 && track.target == 1)
        track.animate(at:0,[.init(to:11,duration:1,curve:.linear)])
        track.animate(at:0.5,[.init(to:0,duration:1,curve:.linear)])
        precondition(track.value(at:0.25) == 3.5 && track.value(at:0.5) == 6 && track.value(at:1) == 3 && track.value(at:2) == 0,"the second starts where the first had got to")
        // A CSS transition only when the value changes; what was planned after a moment can be forgotten.
        track.transition(at:3,to:0,0.4)
        precondition(track.tweens.count == 2)
        track.transition(at:3,to:2,0.4)
        precondition(track.tweens.count == 3 && close(track.value(at:3.2),2*Ease.css(0.5)) && track.target == 2)
        track.cut(after:1)
        precondition(track.tweens.count == 2 && track.target == 0)
        var lens=FunLens(0.5)
        lens.animate(at:0,to:1,1,.linear)
        lens.animate(at:0.2,to:2,0.3,.linear)
        precondition(close(lens.value(at:0.35),1.5),"from the last target, not from where the first had got to")
        precondition(close(lens.value(at:0.6),0.8),"the first, still running, is drawn again once the second ends")
        precondition(lens.value(at:1.2) == 1 && lens.target == 2,"none running: the last to finish stays")
        lens.cut(after:0.1)
        precondition(lens.target == 1 && close(lens.value(at:0.35),0.675))
    }

    /// The design's glides: the leading edge reaches the new place by the turn while the trailing one goes only part of the
    /// way, then the spring settles it there.
    static func glides() {
        let words=GlideStyle.words,a:(start:CGFloat,length:CGFloat)=(0,40),b:(start:CGFloat,length:CGFloat)=(100,60)
        let begin=words.span(from:a,to:b,at:0)
        precondition(begin.start == 0 && begin.length == 40 && begin.squash == 1)
        let turn=words.span(from:a,to:b,at:words.turn)
        precondition(close(turn.start,18) && close(turn.start+turn.length,160) && close(turn.squash,0.82),"\(turn)")
        let end=words.span(from:a,to:b,at:1)
        precondition(end.start == 100 && end.length == 60 && end.squash == 1)
        // Going back the leading edge is the start.
        let back=words.span(from:b,to:a,at:words.turn)
        precondition(close(back.start,0) && close(back.start+back.length,160-100*0.18),"\(back)")
        // A tab's mark is never shorter than the tab it goes to.
        let tabs=GlideStyle.tabs.span(from:(0,80),to:(10,40),at:GlideStyle.tabs.turn)
        precondition(tabs.length >= 40)
        precondition(GlideStyle.rows.span(from:(0,30),to:(0,30),at:0.3) == (0,30,1),"no move, no glide")
    }

    /// The picture's pumps, as clicks plan them (times in seconds from the first click).
    static func pumps() {
        // One click: a pump, let out 1.7 s later, settled 0.56 s after that.
        var one=ProfileFun.Rig(start:0,seed:1)
        one.click(at:0)
        precondition(close(one.settle!,2.26) && one.over == one.settle! && one.done == one.settle! && one.dotFlight == nil && one.boom == nil)
        precondition(close(one.scaleX.value(at:1.5),1.06,0.001) && close(one.face.value(at:1.5),1,0.001) && close(one.lens.value(at:1.5),0.686,0.001))
        precondition(close(one.scaleX.value(at:2.2),1,0.01) && one.stage(at:1) == 0 && one.shake(at:1) == .zero)
        // Three: it strains (its ring glows, it trembles), the dot flies off; let out a pump each 480 ms.
        var three=ProfileFun.Rig(start:0,seed:2)
        for k in 0..<3 { three.click(at:Double(k)*0.15) }
        precondition(close(three.dotFlight!,0.3) && close(three.settle!,0.3+1.7+0.96+0.56) && three.done == three.settle!+0.56)
        precondition(close(three.strain.value(at:1),1) && close(three.tint.value(at:1),0.45) && close(three.lens.value(at:1.5),0.818,0.001))
        precondition(three.shake(at:1) != .zero && abs(three.shake(at:1).width) <= 0.55 && three.shake(at:1) == three.shake(at:1.001),"a nudge ~30 times a second")
        precondition(close(three.strain.value(at:2.5),0,0.001) && three.shake(at:2.5) == .zero,"strain eases off as pumps are let out")
        // Clicking again while held starts the wait over.
        var again=ProfileFun.Rig(start:0,seed:3)
        again.click(at:0);again.click(at:1)
        precondition(close(again.settle!,1+1.7+0.48+0.56))
        // A click while it settles doesn't stop it settling, as the design's doesn't.
        var late=ProfileFun.Rig(start:0,seed:4)
        late.click(at:0);late.click(at:2)
        precondition(close(late.settle!,2.26))
        // Five clicks: cracks; the sixth winds it up, and nothing more counts until it has burst and grown back.
        var six=ProfileFun.Rig(start:0,seed:5)
        for k in 0..<5 { six.click(at:Double(k)*0.15) }
        precondition(six.stage(at:0.7) == 2 && six.cracks[2] != nil && six.cracks[0] == nil)
        six.click(at:0.75)
        precondition(six.boom == 0.75 && six.bursting(at:0.8) && six.settle == nil && six.stage(at:0.8) == 3 && six.over == .infinity)
        precondition(close(six.face.value(at:1.22),1.5,0.001) && close(six.scaleX.value(at:1.22),1.28,0.001) && close(six.scaleY.value(at:1.22),1.42,0.001))
        // The wind-up's bulge (to 0.97 in 430 ms) has ended by the burst, and the fifth pump's, still running, shows again,
        // as on the design's canvas, which both draw on in turn.
        precondition(close(six.lens.value(at:1.1),0.97,0.01) && close(six.lens.value(at:1.22),0.95,0.01),"\(six.lens.value(at:1.22))")
        six.prepareBurst(picture(),shell:CGSize(width:372,height:285))
        precondition(close(six.burst!.at,1.22) && close(six.regrow!,1.22+4.3) && six.over == six.regrow!+1.5 && six.done == six.over && six.bulgeLost == six.regrow)
        // The burst's face: its middle where the ring's is (nudged by the tremble), as big as the wind-up made it.
        let box=six.burst!.box
        precondition(close(box.midX,50,1.5) && close(box.midY,60,1.5) && close(box.width,66*1.5*1.28,0.1) && close(box.height,66*1.5*1.42,0.1))
        // Its dot flies off in an arc and is gone by 840 ms.
        let flight=three.flyingDot(at:0.3+0.28)
        precondition(close(flight.y,-32) && flight.x > 20 && three.flyingDot(at:0.3+0.85).opacity == 0)
        // The dot drops back in from above with a bounce.
        let back=ProfileFun.Rig.dotBack(from:0,at:0)
        precondition(back.y == -34 && back.scale == 0.4 && back.opacity == 0 && ProfileFun.Rig.dotBack(from:0,at:0.6).y == 0)
    }

    /// The cracks: seven spokes and two rings of cracks round the nose, more at each stage; the same for the same seed.
    static func cracks() {
        var first=FunRandom(9),second=FunRandom(9)
        let fracture=Fracture(&first),same=Fracture(&second)
        precondition(fracture.cells.count == 14 && fracture.cells.allSatisfy { $0.count == 3 || $0.count == 4 })
        precondition([0,1,2,3].map { fracture.lines($0).count } == [0,4,15,23],"\([0,1,2,3].map { fracture.lines($0).count })")
        precondition(fracture.lines(3).allSatisfy { $0.count == 3 } && fracture.lines(3) == same.lines(3) && fracture.cells == same.cells)
        precondition(LensPicture.cracks(fracture.lines(0)) == nil && LensPicture.cracks(fracture.lines(1)) != nil)
        // The bulge: none at no strength, and the picture's corners never move.
        let lens=LensPicture(gradient())!
        let flat=pixels(lens.bulged(0)),source=pixels(gradient()),bulged=pixels(lens.bulged(0.62))
        precondition(flat == source,"no strength, no change")
        precondition(bulged[0..<4] == source[0..<4] && bulged != source)
    }

    /// The burst: every piece stays inside the pop-out's walls (a few points in), fading out within two seconds; the
    /// pop-out's jolt, smoothed by its transition, is small and comes to rest.
    static func burst() {
        var random=FunRandom(11)
        let size=CGSize(width:372,height:285),box=CGRect(x:-13,y:-14,width:127,height:140)
        let burst=Burst(at:0,box:box,texture:gradient(),fracture:Fracture(&random),size:size,seed:12)
        precondition(burst.pieces.count == 22 && burst.frames.allSatisfy { $0.count == 22 })
        precondition(burst.pieces.allSatisfy { $0.fadeAt+$0.fadeFor <= 1.7 } && Double(burst.frames.count)/60 <= 1.75)
        for frame in burst.frames.dropFirst() {
            for (piece,spot) in zip(burst.pieces,frame) {
                let margin:Double={ if case .cell=piece.kind { return 9 } else { return 4 } }()
                let x=piece.origin.x+spot.x,y=piece.origin.y+spot.y
                precondition(x >= margin-0.001 && x <= size.width-margin+0.001 && y >= margin-0.001 && y <= size.height-margin+0.001,"\(piece.kind) at \(x),\(y)")
            }
        }
        precondition(burst.spot(0,at:0).x == 0 && burst.spot(0,at:0.5).x != 0)
        let largest=burst.shifts.map { max(abs($0.width),abs($0.height)) }.max()!,last=burst.shifts.last!
        precondition(largest > 0.2 && largest < 1.5,"\(largest)")
        precondition(abs(last.width) < 0.01 && abs(last.height) < 0.01,"\(last)")
    }

    /// The quote: it wobbles when pointed at, and again only 1.5 s after it last began.
    @MainActor static func quote() {
        let fun=ProfileFun()
        precondition(fun.wobbles.isEmpty && !fun.ticking)
        fun.wobble(letters:34)
        precondition(fun.wobbles.count == 1 && fun.ticking)
        fun.wobble(letters:34)
        precondition(fun.wobbles.count == 1,"not again so soon")
        fun.kill()
        precondition(fun.wobbles.count == 1 && fun.ticking,"Customize or a page leaves the quote as it is")
        fun.tick(at:Date().timeIntervalSinceReferenceDate+3)
        precondition(!fun.ticking)
    }

    /// A small picture to bulge and break: a gradient across and down.
    /// Erasing: the sessions slide away as the design's sweepSessions has them (from 120 ms, each 55 ms after the one
    /// above, over 280 ms, easing in), and the list closes 200 ms after the last has started.
    @MainActor static func sweep() {
        precondition(DiscordStudio.sweptAway(0,0.12) == 0 && DiscordStudio.sweptAway(0,0.4) == 1,"the first goes from 120 to 400 ms")
        precondition(DiscordStudio.sweptAway(2,0.12+0.11) == 0 && DiscordStudio.sweptAway(2,0.23+0.28) == 1,"the third, 110 ms later")
        // cubic-bezier(.5,0,.75,0): slow to leave, quick to go.
        let half=DiscordStudio.sweptAway(0,0.12+0.14)
        precondition(close(half,0.066,0.002),"halfway in time, \(half) of the way")
        let steps=(0...28).map { DiscordStudio.sweptAway(1,0.175+Double($0)/100) }
        precondition(zip(steps,steps.dropFirst()).allSatisfy { $0 <= $1 },"it only moves on")
        precondition(close(DiscordStudio.sweepCloses(5),0.595),"five sessions: the list closes at 595 ms")
        precondition(DiscordStudio.sweepCloses(800) == DiscordStudio.sweepCloses(8),"a long list closes as eight do")
    }
    /// Customize: opening it, or a click that changes nothing, moves no level and copies nothing; a real change does.
    /// A line opened and changed to one already in the list swaps with it; a second ✕ on a line already gone does
    /// nothing; the second piece goes when it can't follow the new one.
    @MainActor static func editing() {
        let studio=DiscordStudio(shelf:DiscordCardShelf())
        var levels:[DiscordPresenceLevel]=[]
        studio.actions.level={ levels.append($0) }
        studio.level = .live
        studio.openEditor()
        precondition(studio.level == .live && levels.isEmpty && studio.shelf.mine.isEmpty)
        studio.edit { $0.pace=DiscordCardDesign.standard.pace }
        precondition(studio.level == .live && studio.shelf.mine.isEmpty,"nothing changed")
        studio.edit { $0.lineTwo=[CardLine(piece:.rank(.current)),CardLine(piece:.tonight(.matches),second:.rank(.current))] }
        precondition(studio.level == .custom && levels == [.custom] && studio.shelf.mine.count == 1)
        studio.openLine=1
        studio.onlyLine(.rank(.current))
        precondition(studio.design.lineTwo.map(\.piece) == [.tonight(.matches),.rank(.current)] && studio.openLine == 0,"swapped, not repeated")
        studio.openLine=0
        studio.onlyLine(.highlights)
        precondition(studio.design.lineTwo[0].piece == .highlights && studio.design.lineTwo[0].second == nil,"Dynamic takes no second piece")
        let line=studio.design.lineTwo[0]
        studio.removeLine(0,line);studio.removeLine(0,line)
        precondition(studio.design.lineTwo.map(\.piece) == [.rank(.current)],"the second click finds another line there: nothing more goes")
        // A phrase about tonight comes off the card when the game closes; one about the season stays.
        studio.choosePhrase(.lastGame)
        precondition(studio.design.lineOne == [.phrase] && studio.design.phrase?.words == .lastGame)
        studio.tonightEnded()
        precondition(studio.design.phrase == nil && studio.design.lineOne == [.name])
        studio.choosePhrase(.roadTo);studio.fillPhrase(.rank("diamond"));studio.tonightEnded()
        precondition(studio.design.phrase == LinePhrase(words:.roadTo,blank:.rank("diamond")))
    }
    static func gradient()->CGImage {
        let side=LensPicture.side
        let context=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<side { for x in 0..<side {
            context.setFillColor(CGColor(srgbRed:Double(x)/Double(side),green:Double(y)/Double(side),blue:0.5,alpha:1))
            context.fill(CGRect(x:x,y:y,width:1,height:1))
        } }
        return context.makeImage()!
    }
    static func picture()->LensPicture { LensPicture(gradient())! }
    static func pixels(_ image:CGImage)->[UInt8] {
        let side=image.width
        var bytes=[UInt8](repeating:0,count:side*side*4)
        bytes.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:side,height:side))
        }
        return bytes
    }
}
