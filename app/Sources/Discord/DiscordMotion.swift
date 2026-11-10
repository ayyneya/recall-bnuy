import SwiftUI

// The Discord pages' motion: the design's curves (Ease), keyframes (Tween, Track), and shared moves: arrivals, glides,
// swaying.

// MARK: curves

/// The design's curves by its names, 0 to 1 (some overshoot): cubic curves, anime.js's easings ("outElastic(1, .42)" is
/// .outElastic(1,0.42)) and its spring. Progress outside 0 to 1 is the nearer end.
enum Ease: Hashable {
    case linear,inQuad,outQuad,inOutQuad,outCubic,outExpo,inOutSine,outBounce,spring
    case outBack(Double=1.70158),outElastic(Double=1,Double=0.5),bezier(Double,Double,Double,Double)
    /// The design's own: quick, then settling.
    static let out=Ease.bezier(0.22,1,0.36,1)
    /// Even, in and out.
    static let inOut=Ease.bezier(0.33,0,0.67,1)
    /// CSS's `ease`.
    static let css=Ease.bezier(0.25,0.1,0.25,1)
    func callAsFunction(_ t:Double)->Double {
        let t=min(max(t,0),1)
        switch self {
        case .linear: return t
        case .inQuad: return t*t
        case .outQuad: return 1-(1-t)*(1-t)
        case .inOutQuad: return t < 0.5 ? 2*t*t : 1-(2-2*t)*(2-2*t)/2
        case .outCubic: return 1-pow(1-t,3)
        case .outExpo: return t >= 1 ? 1 : 1-pow(2,-10*t)
        case .inOutSine: return (1-cos(Double.pi*t))/2
        case .outBounce:
            let n=7.5625,d=2.75
            if t < 1/d { return n*t*t }
            if t < 2/d { let u=t-1.5/d;return n*u*u+0.75 }
            if t < 2.5/d { let u=t-2.25/d;return n*u*u+0.9375 }
            let u=t-2.625/d;return n*u*u+0.984375
        case .spring:
            guard t < 1 else { return 1 }
            let zeta=0.55,w=6.4/zeta,wd=w*(1-zeta*zeta).squareRoot()
            return 1-exp(-zeta*w*t)*(cos(wd*t)+(zeta*w/wd)*sin(wd*t))
        case .outBack(let c):
            let u=1-t
            return 1-((c+1)*u*u*u-c*u*u)
        case .outElastic(let a,let p):
            guard t > 0 else { return 0 }
            guard t < 1 else { return 1 }
            let s=p/(2*Double.pi)*asin(1/a)
            return 1+a*pow(2,-10*t)*sin((t-s)*2*Double.pi/p)
        case .bezier(let x1,let y1,let x2,let y2):
            return UnitCurve.bezier(startControlPoint:UnitPoint(x:x1,y:y1),endControlPoint:UnitPoint(x:x2,y:y2)).value(at:t)
        }
    }
    /// One stretch of a longer effect: eased from `start` (seconds, or progress) over `length`.
    func callAsFunction(_ t:Double,from start:Double=0,over length:Double)->Double { self((t-start)/length) }
}
/// A curve SwiftUI can't draw (an overshoot, a spring, a bounce) as an animation over `duration` seconds.
struct EaseAnimation: CustomAnimation {
    let ease:Ease
    let duration:Double
    func animate<V:VectorArithmetic>(value:V,time:TimeInterval,context:inout AnimationContext<V>)->V? {
        time < duration ? value.scaled(by:ease(time/duration)) : nil
    }
}
extension Animation {
    /// `ease` over `duration` seconds: a cubic curve as SwiftUI's own timing curve, any other as EaseAnimation.
    static func curve(_ ease:Ease,_ duration:Double)->Animation {
        if case .bezier(let x1,let y1,let x2,let y2)=ease { return .timingCurve(x1,y1,x2,y2,duration:duration) }
        return Animation(EaseAnimation(ease:ease,duration:duration))
    }
}
/// From `a` to `b`, `t` of the way (past `b` as an overshooting curve goes past 1).
func mix<V:BinaryFloatingPoint>(_ a:V,_ b:V,_ t:Double)->V { a+(b-a)*V(t) }

// MARK: tweens

/// A value animated as anime.js does: from `from` at `start`, through keyframes with their own length, ease and pause
/// (default outQuad).
struct Tween {
    struct Key {
        var to:Double
        var duration:Double
        var delay:Double=0
        var curve:Ease = .outQuad
    }
    var start:Double
    var from:Double
    var keys:[Key]
    var end:Double { start+keys.reduce(0) { $0+$1.delay+$1.duration } }
    var last:Double { keys.last?.to ?? from }
    func value(at t:Double)->Double {
        var value=from,time=start
        for key in keys {
            time+=key.delay
            guard t >= time else { return value }
            guard t >= time+key.duration else { return value+(key.to-value)*key.curve((t-time)/key.duration) }
            value=key.to;time+=key.duration
        }
        return value
    }
}
/// One property's animations, each starting from where the last had got to and replacing it.
struct Track {
    let rest:Double
    private(set) var tweens:[Tween]=[]
    init(_ rest:Double) { self.rest=rest }
    func value(at t:Double)->Double { tweens.last { $0.start <= t }?.value(at:t) ?? rest }
    var target:Double { tweens.last?.last ?? rest }
    mutating func animate(at t:Double,_ keys:[Tween.Key]) { tweens.append(Tween(start:t,from:value(at:t),keys:keys)) }
    /// A CSS transition to `value`, with CSS's ease; none when it's there already.
    mutating func transition(at t:Double,to value:Double,_ duration:Double) {
        if value != target { animate(at:t,[Tween.Key(to:value,duration:duration,curve:.css)]) }
    }
    /// Forgets what was planned after `t`.
    mutating func cut(after t:Double) { tweens.removeAll { $0.start > t } }
}

// MARK: moves

extension AnyTransition {
    /// A part that comes or goes with a screen at once, while everything around it still moves.
    static var atOnce:AnyTransition { .opacity.animation(.linear(duration:0)) }
    /// A page coming in where it would have sat, its top `by` lower or higher, laid out in that room so it's carried as
    /// the room changes (as the design's column carries its page).
    static func ride(_ by:CGFloat)->AnyTransition { .modifier(active:Ride(top:by),identity:Ride(top:0)) }
}
private struct Ride: ViewModifier {
    let top:CGFloat
    func body(content:Content)->some View { content.padding(.top,top) }
}

/// The pages' clocks tick together from one start: a schedule from `.now` restarts on every redraw.
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    static var seconds:PeriodicTimelineSchedule { .periodic(from:DesignClock.start,by:1) }
}
enum DesignClock { static let start=Date() }

/// Where a part starts as it arrives (the design's keyframes' "from").
struct ArrivalStart: Equatable {
    var x:CGFloat=0
    var y:CGFloat=0
    var opacity:Double=1
    var scale:CGFloat=1
    /// The point it scales about (CSS's transform-origin).
    var anchor:UnitPoint = .center
}
/// A part arriving as the design's CSS animations run: on its own curve, when first shown and whenever `trigger`
/// changes; nil just shows. Each arrival is one animated run (ArrivalEffect), waiting at its start while delayed.
struct PartArrival: ViewModifier {
    let trigger:AnyHashable?
    let arrival:(start:ArrivalStart,animation:Animation)?
    var onAppear=true
    @State private var from:ArrivalStart
    @State private var runs=0.0
    @State private var waiting:Bool
    init(trigger:AnyHashable?,_ arrival:(start:ArrivalStart,animation:Animation)?,onAppear:Bool=true) {
        self.trigger=trigger;self.arrival=arrival;self.onAppear=onAppear
        _from=State(initialValue:arrival?.start ?? ArrivalStart());_waiting=State(initialValue:onAppear && arrival != nil)
    }
    func body(content:Content)->some View {
        // The animation is the arriving view's alone: a withAnimation would carry the whole update along.
        content.modifier(ArrivalEffect(phase:runs,runs:runs,from:from,waiting:waiting)).animation(arrival?.animation,value:runs)
            .onAppear {
                guard waiting,arrival != nil else { return }
                waiting=false;runs+=1
            }
            .onChange(of:trigger) {
                guard let arrival else { return }
                from=arrival.start;runs+=1
            }
    }
}
/// How far a part has arrived: the animated runs behind those asked for; waiting, at the start.
private struct ArrivalEffect: ViewModifier, Animatable {
    var phase:Double
    let runs:Double
    let from:ArrivalStart
    let waiting:Bool
    var animatableData:Double { get { phase } set { phase=newValue } }
    func body(content:Content)->some View {
        let left=waiting ? 1 : min(1,runs-phase)
        content.scaleEffect(1+(from.scale-1)*left,anchor:from.anchor).offset(x:from.x*left,y:from.y*left).opacity(1+(from.opacity-1)*left)
    }
}
/// How highlights glide: the leading edge reaches the new place by `turn` while the trailing edge goes `lead` of the
/// way, thinning to `squash`; then it catches up and settles with a spring. `atLeast` keeps it from getting shorter.
struct GlideStyle {
    var duration=0.76
    var turn=0.42
    var lead:CGFloat=0.18
    var squash:CGFloat=0.82
    var atLeast=false
    /// The level words.
    static let words=GlideStyle()
    /// A row of tabs.
    static let tabs=GlideStyle(duration:0.64,squash:0.8,atLeast:true)
    /// A column of rows (the rail).
    static let rows=GlideStyle(duration:0.6,turn:0.4,lead:0.2,squash:1,atLeast:true)
    /// Where the mark is (its start and length along the axis) and how thin, `progress` of the way.
    func span(from a:(start:CGFloat,length:CGFloat),to b:(start:CGFloat,length:CGFloat),at progress:Double)->(start:CGFloat,length:CGFloat,squash:CGFloat) {
        guard progress < 1,a.start != b.start || a.length != b.length,a.length > 0 else { return (b.start,b.length,1) }
        let ahead=b.start > a.start
        let middle=ahead ? a.start+(b.start-a.start)*lead : b.start
        var length=ahead ? b.start+b.length-middle : a.start+a.length-(a.start-b.start)*lead-b.start
        if atLeast { length=max(length,b.length) }
        if progress < turn {
            let eased=Ease.bezier(0.5,0,0.75,0.4)(progress/turn)
            return (mix(a.start,middle,eased),mix(a.length,length,eased),mix(1,squash,eased))
        }
        let eased=Ease.spring((progress-turn)/(1-turn))
        return (mix(middle,b.start,eased),mix(length,b.length,eased),mix(squash,1,eased))
    }
}
/// Each item's place, for the gliding mark (glider).
private struct GlideItems<Key:Hashable>: PreferenceKey {
    static var defaultValue:[Key:Anchor<CGRect>] { [:] }
    static func reduce(value:inout [Key:Anchor<CGRect>],nextValue:()->[Key:Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}
/// A mark behind the chosen item that glides to another (GlideStyle): along the stack it takes the item's place;
/// across, `across` of it or its own.
private struct Glider<Key:Hashable,Mark:View>: ViewModifier {
    let chosen:Key?
    let style:GlideStyle
    let axis:Axis
    let across:(@Sendable (CGRect)->(start:CGFloat,length:CGFloat))?
    let mark:Mark
    @State private var previous:Key?
    @State private var glides=0
    func body(content:Content)->some View {
        content
            .backgroundPreferenceValue(GlideItems<Key>.self) { items in
                GeometryReader { proxy in
                    if let chosen,let anchor=items[chosen] {
                        let to=proxy[anchor],from=previous.flatMap { items[$0] }.map { proxy[$0] } ?? to,across=across
                        mark.keyframeAnimator(initialValue:1.0,trigger:glides) { mark,progress in
                            let along=axis == .horizontal
                            let span=style.span(from:along ? (from.minX,from.width) : (from.minY,from.height),to:along ? (to.minX,to.width) : (to.minY,to.height),at:progress)
                            let side=across?(to) ?? (along ? (to.minY,to.height) : (to.minX,to.width))
                            mark.frame(width:max(0,along ? span.length : side.length),height:max(0,along ? side.length : span.length))
                                .scaleEffect(x:along ? 1 : span.squash,y:along ? span.squash : 1)
                                .offset(x:along ? span.start : side.start,y:along ? side.start : span.start)
                        } keyframes:{ _ in
                            MoveKeyframe(0.0)
                            LinearKeyframe(1.0,duration:style.duration)
                        }
                    }
                }
            }
            .onChange(of:chosen) { old,_ in previous=old;glides+=1 }
    }
}
extension View {
    /// A mark gliding behind the chosen one of this stack's items (each marked with glideItem), as the design's do.
    func glider<Key:Hashable,Mark:View>(_ chosen:Key?,style:GlideStyle,axis:Axis,across:(@Sendable (CGRect)->(start:CGFloat,length:CGFloat))?=nil,
                                       @ViewBuilder mark:()->Mark)->some View {
        modifier(Glider(chosen:chosen,style:style,axis:axis,across:across,mark:mark()))
    }
    /// One of the items a glider's mark moves between.
    func glideItem<Key:Hashable>(_ key:Key)->some View { anchorPreference(key:GlideItems<Key>.self,value:.bounds) { [key:$0] } }
}

extension View {
    /// The design's dcPop: fading in while rising eight points, after `delay`.
    func popIn(_ duration:Double,delay:Double=0,curve:Animation?=nil)->some View {
        modifier(PartArrival(trigger:nil,(ArrivalStart(y:8,opacity:0),(curve ?? .curve(.out,duration)).delay(delay))))
    }
    /// The design's dcFade as the part shows: fading in (CSS's `ease`), after `delay`.
    func fadeIn(_ duration:Double,delay:Double=0)->some View {
        modifier(PartArrival(trigger:nil,(ArrivalStart(opacity:0),Animation.curve(.css,duration).delay(delay))))
    }
    /// To and fro while `on`, `half` seconds each way, on its own clock (a repeatForever from onAppear slid the whole
    /// sheet in from its corner).
    func swaying<Content:View>(_ half:Double,on:Bool=true,@ViewBuilder _ apply:@escaping @Sendable (PlaceholderContentView<Self>,Double)->Content)->some View {
        keyframeAnimator(initialValue:0.0,repeating:on && Moving.shared.now,content:apply) { _ in
            LinearKeyframe(1.0,duration:half,timingCurve:.easeInOut)
            LinearKeyframe(0.0,duration:half,timingCurve:.easeInOut)
        }
    }
}

/// Whether endless motion is worth drawing: Recall's window on screen and Reduce Motion off. Otherwise the loops hold
/// still.
@MainActor @Observable final class Moving {
    static let shared=Moving()
    private(set) var now=true
    private var watches:[NSObjectProtocol]=[]
    private init() {
        update()
        watches=[NotificationCenter.default.addObserver(forName:NSApplication.didChangeOcclusionStateNotification,object:nil,queue:.main) { _ in
                    MainActor.assumeIsolated { Moving.shared.update() } },
                 NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { _ in
                    MainActor.assumeIsolated { Moving.shared.update() } }]
    }
    private func update() {
        let next=NSApp.map { $0.occlusionState.contains(.visible) } ?? true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if next != now { now=next }
    }
}
