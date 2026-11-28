import Foundation

// A card as a short code to share ("D7KQ-2M9X"): the code is the card, so nothing is stored anywhere. Format:
// app/ARCHITECTURE.md.
enum DiscordCardCode {
    static let alphabet=Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    /// OverFast's hero keys in a frozen order (codes index it). A later hero is spelt out, never appended.
    static let heroes=["ana","anran","ashe","baptiste","bastion","brigitte","cassidy","dmon","doctrine","domina","doomfist","dva","echo","emre",
                       "freja","genji","hanzo","hazard","illari","jetpack-cat","junker-queen","junkrat","juno","kiriko","lifeweaver","lucio","mauga",
                       "mei","mercy","mizuki","moira","orisa","pharah","ramattra","reaper","reinhardt","roadhog","shion","sierra","sigma","sojourn",
                       "soldier-76","sombra","symmetra","torbjorn","tracer","vendetta","venture","widowmaker","winston","wrecking-ball","wuyang",
                       "zarya","zenyatta"]
    /// Lists hold seven items at most in a code (Customize stops at six), and a name 63 characters (Unicode scalars).
    static let longestList=7,longestName=63
    /// The letters a hero key the list doesn't have is spelt in, and the punctuation a name can have at five bits.
    private static let keyLetters=Array("abcdefghijklmnopqrstuvwxyz0123456789-")
    private static let punctuation=Array("-'.,!?&:()/+#*_~")
    /// 0 was the preview builds' format; 1 leaves room for a later Recall's parts (skipped, not refused); 2 and 3 are
    /// newer.
    private static let version=1
    private static let ranks:[RankChoice]=[.role(.tank),.role(.damage),.role(.support),.role(.open),.highest,.lastPlayed]
    private static let buttons:[SecondButton?]=[nil,.careerProfile,.heroPage,.patchNotes]
    private static let parties:[PartyChoice]=[.sayVoice,.addCount,.noCount]

    /// Whether every part of a design fits in a code as it is (Customize keeps to this).
    static func fits(_ design:DiscordCardDesign)->Bool {
        [design.lineOne.count,design.lineTwo.count,design.pictures?.count ?? 0].allSatisfy { $0 <= longestList } && design.badges.count <= 3
            && design.name.unicodeScalars.count <= longestName && (0...511).contains(design.pace)
    }

    /// The code for a design, grouped in fours for reading out ("D7KQ-2M9X").
    static func encode(_ design:DiscordCardDesign)->String {
        var bits=Bits()
        bits.put(version,2)
        // Line 2: each line, whether it shows in a match, and its second piece.
        let lines=Array(design.lineTwo.prefix(longestList))
        bits.put(lines.count,3)
        for line in lines {
            put(line.piece,&bits)
            bits.put(line.inMatch ? 1 : 0,1)
            bits.put(line.second == nil ? 0 : 1,1)
            if let second=line.second { put(second,&bits) }
        }
        let standard=DiscordCardDesign.standard
        // Line 1, the pictures and the badges: one bit when they're Default's, else the list.
        bits.put(design.lineOne == standard.lineOne ? 0 : 1,1)
        if design.lineOne != standard.lineOne {
            let ones=Array(design.lineOne.prefix(longestList))
            bits.put(ones.count,3)
            for one in ones { bits.put(LineOne.allCases.firstIndex(of:one)!,3) }
        }
        bits.put(design.pictures == nil ? 0 : 1,1)
        if let pictures=design.pictures {
            let list=Array(pictures.prefix(longestList))
            bits.put(list.count,3)
            for picture in list { put(picture,&bits) }
        }
        bits.put(design.badges == standard.badges ? 0 : 1,1)
        if design.badges != standard.badges {
            let badges=Array(design.badges.prefix(3))
            bits.put(badges.count,2)
            for badge in badges { bits.put(CardBadge.allCases.firstIndex(of:badge)!,2) }
        }
        // The rest: the timer, the second button, the group's voice, the pace (any other is spelt out) and the rank.
        let pace=DiscordCardDesign.paces.firstIndex(of:design.pace) ?? 7
        let rest=[design.timer == .session ? 1 : 0,buttons.firstIndex(of:design.button)!,parties.firstIndex(of:design.party)!,pace,ranks.firstIndex(of:design.rank)!]
        let standardRest=[0,1,0,1,5]
        bits.put(rest == standardRest ? 0 : 1,1)
        if rest != standardRest {
            for (value,width) in zip(rest,[1,2,2,3,3]) { bits.put(value,width) }
            if pace == 7 { bits.put(min(max(design.pace,0),511),9) }
        }
        // The name, last.
        let name=Array(design.name.unicodeScalars.prefix(longestName))
        bits.put(name.count,6)
        for scalar in name { put(scalar,&bits) }
        // After the name, records (format 1): Line 1's phrase is record 1.
        if design.lineOne.contains(.phrase),let phrase=design.phrase {
            var payload=Bits();put(phrase,&payload)
            // A hero spelt out too long for a record: its blank is Auto in the code.
            if payload.count > 63 { payload=Bits();put(LinePhrase(words:phrase.words),&payload) }
            bits.put(1,4);bits.put(payload.count,6);bits.append(payload)
        }
        var symbols=bits.symbols()
        symbols.append(check(symbols))
        return group(String(symbols.map { alphabet[$0] }))
    }

    /// What a pasted code is: a card (a new one, with its own id), one a newer Recall made, or not a code.
    enum Read: Equatable { case card(DiscordCardDesign),newer,invalid }
    /// The design a code stands for; nil for anything that isn't a whole, correct code this Recall reads.
    static func decode(_ text:String)->DiscordCardDesign? { if case .card(let design)=read(text) { return design } else { return nil } }
    /// A code as people paste it: from a message, with spaces, dashes of any kind, quotes or full-width letters.
    static func read(_ text:String)->Read {
        let plain=text.precomposedStringWithCompatibilityMapping.uppercased()
        // The whole text, then each run of code characters in it, longest first.
        let runs=plain.split { !(alphabet.contains($0) || "OIL".contains($0) || dashes.contains($0) || $0 == " ") }
            .flatMap { run in [String(run)]+run.split(separator:" ").map(String.init) }
            .sorted { $0.count > $1.count }
        var newer=false
        for candidate in [plain]+runs {
            switch readOne(candidate) {
            case .card(let design): return .card(design)
            case .newer: newer=true
            case .invalid: continue
            }
        }
        return newer ? .newer : .invalid
    }
    private static let dashes=Set("-‐‑‒–—―−_")
    private static func readOne(_ text:String)->Read {
        var symbols:[Int]=[]
        for character in text where !character.isWhitespace && !dashes.contains(character) && !"`'\"“”‘’".contains(character) {
            let read:Character=character == "O" ? "0" : (character == "I" || character == "L") ? "1" : character
            guard let value=alphabet.firstIndex(of:read) else { return .invalid }
            symbols.append(value)
        }
        guard symbols.count >= 2,check(Array(symbols.dropLast())) == symbols.last! else { return .invalid }
        var bits=Bits(symbols:Array(symbols.dropLast()))
        guard let format=bits.take(2) else { return .invalid }
        guard format <= version else { return .newer }
        return design(&bits,format:format).map { .card($0) } ?? .invalid
    }
    /// A part a later Recall made is left out and the rest read; nil when the bits don't add up.
    private static func design(_ bits:inout Bits,format:Int)->DiscordCardDesign? {
        guard let count=bits.take(3) else { return nil }
        var design=DiscordCardDesign(id:UUID().uuidString,name:"")
        design.lineTwo=[]
        for _ in 0..<count {
            guard let piece=piece(&bits,format:format),let inMatch=bits.take(1),let hasSecond=bits.take(1) else { return nil }
            var second:Part<CardPiece>?=nil
            if hasSecond == 1 { guard let read=self.piece(&bits,format:format) else { return nil };second=read }
            // A line this Recall doesn't know is left out; a second piece it doesn't know leaves the line on its own.
            guard case .known(let first)=piece else { continue }
            var line=CardLine(piece:first,inMatch:inMatch == 1)
            if case .known(let other)?=second { line.second=other }
            design.lineTwo.append(line)
        }
        if design.lineTwo.isEmpty && count > 0 { design.lineTwo=DiscordCardDesign.standard.lineTwo }
        guard let ownOnes=bits.take(1) else { return nil }
        if ownOnes == 1 {
            guard let count=bits.take(3) else { return nil }
            var ones:[LineOne]=[]
            for _ in 0..<count {
                guard let kind=bits.take(3) else { return nil }
                if kind < LineOne.allCases.count { ones.append(LineOne.allCases[kind]) }
                else if kind == 7,format >= 1 { guard skip(&bits) else { return nil } }
            }
            design.lineOne=ones.isEmpty && count > 0 ? DiscordCardDesign.standard.lineOne : ones
        }
        guard let ownPictures=bits.take(1) else { return nil }
        if ownPictures == 1 {
            guard let count=bits.take(3) else { return nil }
            var pictures:[CardPicture]=[]
            for _ in 0..<count {
                guard let picture=picture(&bits,format:format) else { return nil }
                if case .known(let known)=picture { pictures.append(known) }
            }
            design.pictures=pictures.isEmpty && count > 0 ? nil : pictures
        }
        guard let ownBadges=bits.take(1) else { return nil }
        if ownBadges == 1 {
            guard let count=bits.take(2) else { return nil }
            var badges:[CardBadge]=[]
            for _ in 0..<count {
                guard let badge=bits.take(2) else { return nil }
                if badge < CardBadge.allCases.count { badges.append(CardBadge.allCases[badge]) }
                else if format >= 1 { guard skip(&bits) else { return nil } }
            }
            design.badges=badges.isEmpty && count > 0 ? DiscordCardDesign.standard.badges : badges
        }
        guard let ownRest=bits.take(1) else { return nil }
        if ownRest == 1 {
            guard let timer=bits.take(1),let button=bits.take(2),let party=bits.take(2),let pace=bits.take(3),let rank=bits.take(3) else { return nil }
            design.timer=timer == 1 ? .session : .match
            design.button=buttons[button]
            if party < parties.count { design.party=parties[party] }
            if rank < ranks.count { design.rank=ranks[rank] }
            if pace == 7 { guard let seconds=bits.take(9) else { return nil };design.pace=seconds }
            else if pace < DiscordCardDesign.paces.count { design.pace=DiscordCardDesign.paces[pace] }
        }
        guard let length=bits.take(6) else { return nil }
        var name=String.UnicodeScalarView()
        for _ in 0..<length { guard let scalar=scalar(&bits) else { return nil };name.append(scalar) }
        // Direction and invisible marks are left out: a shared name can't read as something else. Emoji keep their joiner.
        design.name=String(String.UnicodeScalarView(name.filter { $0.properties.generalCategory != .format || $0 == "\u{200D}" }))
        // After the name: records (format 1; Line 1's phrase is 1), a later Recall's skipped. Anything left is padding.
        if format >= 1 {
            while bits.rest >= 5,!bits.restIsZero {
                guard let id=bits.take(4),let length=bits.take(6),let payload=bits.slice(length) else { return nil }
                if id == 1 { var read=payload;design.phrase=phrase(&read) }
            }
        }
        if design.lineOne.contains(.phrase) && design.phrase == nil { design.lineOne.removeAll { $0 == .phrase } }
        guard bits.rest < 5,bits.restIsZero else { return nil }
        return design
    }
    /// The phrase: its words (5 bits), the blank's kind (2: Auto, hero, rank, role) and the blank.
    private static func put(_ phrase:LinePhrase,_ bits:inout Bits) {
        bits.put(LinePhrase.Words.allCases.firstIndex(of:phrase.words)!,5)
        switch phrase.blank {
        case .auto: bits.put(0,2)
        case .hero(let key): bits.put(1,2);put(hero:key,&bits)
        case .rank(let division): bits.put(2,2);bits.put(CareerRank.divisions.firstIndex(of:division) ?? 0,4)
        case .role(let role): bits.put(3,2);bits.put(CareerRank.Role.allCases.firstIndex(of:role)!,2)
        }
    }
    private static func phrase(_ bits:inout Bits)->LinePhrase? {
        guard let index=bits.take(5),index < LinePhrase.Words.allCases.count,let kind=bits.take(2) else { return nil }
        var phrase=LinePhrase(words:LinePhrase.Words.allCases[index])
        switch kind {
        case 1: if let key=hero(&bits),let key { phrase.blank = .hero(key) }
        case 2: if let place=bits.take(4),place < CareerRank.divisions.count { phrase.blank = .rank(CareerRank.divisions[place]) }
        case 3: if let role=bits.take(2) { phrase.blank = .role(CareerRank.Role.allCases[role]) }
        default: break
        }
        return phrase
    }
    /// A later Recall's part: 4 bits naming it, 6 for its length in bits, then those bits, read past whole.
    private static func skip(_ bits:inout Bits)->Bool {
        guard bits.take(4) != nil,let length=bits.take(6) else { return false }
        return bits.take(length) != nil
    }
    /// An item read: one this Recall knows, or a later Recall's it reads past.
    private enum Part<Value> { case known(Value),unknown }

    // MARK: the name

    /// 0 a space, 1–26 a to z, 27 a capital, 28 a digit, 29 punctuation, 30 any other character (its 21 bits).
    private static func put(_ scalar:Unicode.Scalar,_ bits:inout Bits) {
        let value=Int(scalar.value)
        switch scalar {
        case " ": bits.put(0,5)
        case "a"..."z": bits.put(value-96,5)
        case "A"..."Z": bits.put(27,5);bits.put(value-64,5)
        case "0"..."9": bits.put(28,5);bits.put(value-48,4)
        default:
            if let mark=punctuation.firstIndex(of:Character(scalar)) { bits.put(29,5);bits.put(mark,4) } else { bits.put(30,5);bits.put(value,21) }
        }
    }
    private static func scalar(_ bits:inout Bits)->Unicode.Scalar? {
        guard let kind=bits.take(5) else { return nil }
        switch kind {
        case 0: return " "
        case 1...26: return Unicode.Scalar(UInt8(96+kind))
        case 27: return bits.take(5).flatMap { (1...26).contains($0) ? Unicode.Scalar(UInt8(64+$0)) : nil }
        case 28: return bits.take(4).flatMap { $0 < 10 ? Unicode.Scalar(UInt8(48+$0)) : nil }
        case 29: return bits.take(4).flatMap { $0 < punctuation.count ? punctuation[$0].unicodeScalars.first : nil }
        case 30: return bits.take(21).flatMap { Unicode.Scalar(UInt32($0)) }
        default: return nil
        }
    }

    // MARK: the pieces

    private static func put(_ piece:CardPiece,_ bits:inout Bits) {
        switch piece {
        case .highlights: bits.put(0,3)
        case .moment(let moment): bits.put(1,3);bits.put(CardMoment.allCases.firstIndex(of:moment)!,3)
        case .rank(let line): bits.put(2,3);bits.put(RankLine.allCases.firstIndex(of:line)!,3)
        case .record(let period,let mode,let winRate):
            bits.put(3,3);bits.put(CareerPeriod.allCases.firstIndex(of:period)!,3);bits.put(RecordMode.allCases.firstIndex(of:mode)!,2);bits.put(winRate ? 1 : 0,1)
        case .hero(let key,let line): bits.put(4,3);bits.put(HeroLine.allCases.firstIndex(of:line)!,2);put(hero:key,&bits)
        case .best(let line): bits.put(5,3);bits.put(BestLine.allCases.firstIndex(of:line)!,3)
        case .tonight(let line): bits.put(6,3);bits.put(TonightLine.allCases.firstIndex(of:line)!,2)
        // Topic 7 is a title, or (after a 1) a later Recall's piece: skip(_:).
        case .title(let line): bits.put(7,3);bits.put(0,1);bits.put(TitleLine.allCases.firstIndex(of:line)!,3)
        }
    }
    private static func piece(_ bits:inout Bits,format:Int)->Part<CardPiece>? {
        guard let topic=bits.take(3) else { return nil }
        // A value past the list's end is a later Recall's: read past, the line left out.
        func one<T>(_ cases:[T],_ width:Int)->Part<T>? { bits.take(width).map { $0 < cases.count ? .known(cases[$0]) : .unknown } }
        func map<T>(_ part:Part<T>?,_ make:(T)->CardPiece)->Part<CardPiece>? {
            part.map { if case .known(let value)=$0 { return .known(make(value)) } else { return .unknown } }
        }
        switch topic {
        case 0: return .known(.highlights)
        case 1: return map(one(CardMoment.allCases,3)) { .moment($0) }
        case 2: return map(one(RankLine.allCases,3)) { .rank($0) }
        case 3:
            guard let period=one(CareerPeriod.allCases,3),let mode=one(RecordMode.allCases,2),let rate=bits.take(1) else { return nil }
            guard case .known(let p)=period,case .known(let m)=mode else { return .unknown }
            return .known(.record(p,m,winRate:rate == 1))
        case 4:
            guard let line=one(HeroLine.allCases,2),let key=hero(&bits) else { return nil }
            guard case .known(let l)=line else { return .unknown }
            return .known(.hero(key,l))
        case 5: return map(one(BestLine.allCases,3)) { .best($0) }
        case 6: return map(one(TonightLine.allCases,2)) { .tonight($0) }
        default:
            if format >= 1 {
                guard let later=bits.take(1) else { return nil }
                if later == 1 { return skip(&bits) ? .unknown : nil }
            }
            return map(one(TitleLine.allCases,3)) { .title($0) }
        }
    }
    private static func put(_ picture:CardPicture,_ bits:inout Bits) {
        switch picture {
        case .playerIcon: bits.put(0,3)
        case .lastHero: bits.put(1,3)
        case .overwatch: bits.put(2,3)
        case .rankEmblem: bits.put(3,3)
        case .recall: bits.put(4,3)
        case .roleMain: bits.put(5,3)
        case .topHeroes: bits.put(6,3)
        case .hero(let key): bits.put(7,3);put(hero:key,&bits)
        // An Extra picture goes as a hero spelt out, "-" and its letter (an older Recall drops it as an unknown hero).
        case .art(let art): bits.put(7,3);put(hero:"-"+String(art.letter),&bits)
        }
    }
    private static func picture(_ bits:inout Bits,format:Int)->Part<CardPicture>? {
        guard let kind=bits.take(3) else { return nil }
        if kind == 7 {
            guard let key=hero(&bits) else { return nil }
            // No hero (the most-played's number) is a later Recall's picture (format 1).
            guard let key else { return format >= 1 && skip(&bits) ? .unknown : nil }
            guard key.first == "-" else { return .known(.hero(key)) }
            return .known(CardArt.allCases.first { "-"+String($0.letter) == key }.map { .art($0) } ?? .hero(key))
        }
        return .known([.playerIcon,.lastHero,.overwatch,.rankEmblem,.recall,.roleMain,.topHeroes][kind])
    }
    /// 0 is the most-played hero, 1–62 the list's, 63 a key spelt out (its length, then its letters: 32 at most).
    private static func put(hero key:String?,_ bits:inout Bits) {
        guard let key else { bits.put(0,6);return }
        if let index=heroes.firstIndex(of:key),index < 62 { bits.put(index+1,6);return }
        let letters=Array(key.lowercased().filter { keyLetters.contains($0) }.prefix(32))
        bits.put(63,6);bits.put(max(letters.count,1)-1,5)
        for letter in letters.isEmpty ? ["a"] : letters { bits.put(keyLetters.firstIndex(of:letter)!,6) }
    }
    /// The hero: nil inside is the most-played; nil outside, a code that isn't one.
    private static func hero(_ bits:inout Bits)->String??{
        guard let index=bits.take(6) else { return nil }
        if index == 0 { return .some(nil) }
        if index < 63 { return index-1 < heroes.count ? .some(heroes[index-1]) : nil }
        guard let length=bits.take(5) else { return nil }
        var key=""
        for _ in 0...length { guard let letter=bits.take(6),letter < keyLetters.count else { return nil };key.append(keyLetters[letter]) }
        return .some(key)
    }

    // MARK: the characters

    /// Luhn mod N over the code's characters: catches any one character mistyped, and most pairs swapped.
    static func check(_ symbols:[Int])->Int {
        let n=alphabet.count
        var factor=2,sum=0
        for symbol in symbols.reversed() {
            let addend=factor*symbol
            sum+=addend/n+addend%n
            factor=factor == 2 ? 1 : 2
        }
        return (n-sum%n)%n
    }
    /// Fours, with a last single character kept with the group before it ("D7KQ-2M9X4").
    static func group(_ text:String)->String {
        var groups=stride(from:0,to:text.count,by:4).map { start in String(Array(text)[start..<min(start+4,text.count)]) }
        if groups.count > 1,groups.last!.count == 1 { groups[groups.count-2]+=groups.removeLast() }
        return groups.joined(separator:"-")
    }

    /// Bits, most significant first, and the 5-bit symbols they make.
    private struct Bits {
        private var bits:[Bool]=[]
        private var at=0
        init() {}
        init(symbols:[Int]) { for symbol in symbols { for shift in (0..<5).reversed() { bits.append(symbol>>shift&1 == 1) } } }
        mutating func put(_ value:Int,_ width:Int) { for shift in (0..<width).reversed() { bits.append(value>>shift&1 == 1) } }
        mutating func append(_ other:Bits) { bits+=other.bits }
        var count:Int { bits.count }
        /// The next `width` bits as bits of their own.
        mutating func slice(_ width:Int)->Bits? {
            guard at+width <= bits.count else { return nil }
            var part=Bits();part.bits=Array(bits[at..<at+width]);at+=width
            return part
        }
        mutating func take(_ width:Int)->Int? {
            guard at+width <= bits.count else { return nil }
            var value=0
            for _ in 0..<width { value=value<<1|(bits[at] ? 1 : 0);at+=1 }
            return value
        }
        var rest:Int { bits.count-at }
        var restIsZero:Bool { !bits[at...].contains(true) }
        func symbols()->[Int] {
            var padded=bits
            while padded.count%5 != 0 { padded.append(false) }
            return stride(from:0,to:padded.count,by:5).map { start in padded[start..<start+5].reduce(0) { $0<<1|($1 ? 1 : 0) } }
        }
    }
}
