import Foundation

/// One piece of text to send to the voice, with the span of source text it was made from.
/// Offsets are UTF-16, like `NSString` and the Accessibility API.
public struct Chunk: Equatable, Sendable {
    public let text: String
    public let source: Range<Int>
    /// The source span of each space-separated word of `text`, in order. Words a rule wrote, like the
    /// "nineteen sixty-nine" said for "1969", each span the whole source the rule replaced.
    public let words: [Range<Int>]
}

public enum URLStyle: Sendable {
    /// "link to example dot com"
    case domain
    case skip
}

/// Rewrites text into what a voice should say, split into sentence chunks that remember their source span.
/// A port of bench/clean/clean.py; both are tested against bench/clean/cases.json.
public func prepare(_ text: String, urls: URLStyle = .domain) -> [Chunk] {
    chunks(segments(text as NSString, urls: urls))
}

// MARK: - Number words

private let ones = ("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen "
    + "sixteen seventeen eighteen nineteen").split(separator: " ").map(String.init)
private let tens = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split(separator: " ").map(String.init)
private let scales = ["", "thousand", "million", "billion", "trillion"]
private let months = "January February March April May June July August September October November December"
    .split(separator: " ").map(String.init)

private func under1000(_ n: Int) -> String {
    var n = n, out: [String] = []
    if n >= 100 {
        out += [ones[n / 100], "hundred"]
        n %= 100
    }
    if n >= 20 {
        out.append(tens[n / 10] + (n % 10 == 0 ? "" : "-\(ones[n % 10])"))
    } else if n > 0 || out.isEmpty {
        out.append(ones[n])
    }
    return out.joined(separator: " ")
}

func intWords(_ n: Int) -> String {
    if n < 0 { return "minus " + intWords(-n) }
    if n < 1000 { return under1000(n) }
    if n >= 1_000_000_000_000_000 { return digitsWords(String(n)) }
    var n = n, parts: [String] = [], i = 0
    while n > 0 {
        let r = n % 1000
        n /= 1000
        if r > 0 { parts.append(under1000(r) + (scales[i].isEmpty ? "" : " \(scales[i])")) }
        i += 1
    }
    return parts.reversed().joined(separator: " ")
}

private func digitsWords(_ s: String) -> String {
    s.compactMap { $0.wholeNumberValue }.map { $0 == 0 ? "oh" : ones[$0] }.joined(separator: " ")
}

/// "1,234.5" -> "one thousand two hundred thirty-four point five".
private func numWords(_ s: String) -> String {
    let parts = s.replacingOccurrences(of: ",", with: "").split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let whole = Int(parts[0].isEmpty ? "0" : parts[0]) else { return digitsWords(String(parts[0])) }
    let frac = parts.count > 1 ? parts[1] : ""
    return intWords(whole) + (frac.isEmpty ? "" : " point " + frac.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " "))
}

private func ordinalWords(_ n: Int) -> String {
    let w = intWords(n)
    let sep: Character = w.split(separator: " ").last?.contains("-") == true ? "-" : " "
    var head = "", last = w, joint = ""
    if let i = w.lastIndex(of: sep) {
        head = String(w[..<i])
        joint = String(sep)
        last = String(w[w.index(after: i)...])
    }
    let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                     "nine": "ninth", "twelve": "twelfth"]
    if let word = irregular[last] {
        last = word
    } else if last.hasSuffix("y") {
        last = last.dropLast() + "ieth"
    } else {
        last += "th"
    }
    return head + joint + last
}

private func yearWords(_ n: Int) -> String {
    if (2000...2009).contains(n) { return "two thousand" + (n % 10 == 0 ? "" : " \(ones[n % 10])") }
    let hi = n / 100, lo = n % 100
    if lo == 0 { return "\(intWords(hi)) hundred" }
    return "\(intWords(hi)) \(lo < 10 ? "oh " + ones[lo] : intWords(lo))"
}

// MARK: - Rules

private let currency = ["$": ("dollar", "dollars", "cent", "cents"), "€": ("euro", "euros", "cent", "cents"),
                        "£": ("pound", "pounds", "penny", "pence"), "¥": ("yen", "yen", "", "")]
private let scaleWords = ["k": "thousand", "K": "thousand", "M": "million", "B": "billion", "T": "trillion",
                          "thousand": "thousand", "million": "million", "billion": "billion", "trillion": "trillion"]
private let units = [
    "ms": ("millisecond", "milliseconds"), "km": ("kilometer", "kilometers"), "cm": ("centimeter", "centimeters"),
    "mm": ("millimeter", "millimeters"), "kg": ("kilogram", "kilograms"), "mg": ("milligram", "milligrams"),
    "lb": ("pound", "pounds"), "lbs": ("pound", "pounds"), "GB": ("gigabyte", "gigabytes"),
    "MB": ("megabyte", "megabytes"), "KB": ("kilobyte", "kilobytes"), "TB": ("terabyte", "terabytes"),
    "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "MHz": ("megahertz", "megahertz"),
    "GHz": ("gigahertz", "gigahertz"), "mph": ("mile per hour", "miles per hour"),
    "km/h": ("kilometer per hour", "kilometers per hour"), "m": ("meter", "meters"),
    "°C": ("degree Celsius", "degrees Celsius"), "°F": ("degree Fahrenheit", "degrees Fahrenheit"),
]
private let abbreviations = [
    "Mr.": "Mister", "Mrs.": "Missus", "Ms.": "Miz", "Prof.": "Professor", "Jr.": "Junior", "Sr.": "Senior",
    "vs.": "versus", "etc.": "et cetera", "e.g.": "for example", "i.e.": "that is", "approx.": "approximately",
    "Inc.": "Inc", "Ltd.": "Limited", "Co.": "Co", "Corp.": "Corp", "Fig.": "figure", "Ave.": "Avenue",
    "Blvd.": "Boulevard", "Jan.": "January", "Feb.": "February", "Aug.": "August", "Sept.": "September",
    "Oct.": "October", "Nov.": "November", "Dec.": "December",
]
private let emojiWords = ["❤": "love", "♥": "love", "👍": "thumbs up"]
private let tld = "(?:com|org|net|io|dev|ai|app|co|edu|gov|me|xyz|sh|so|gg)"
private let num = #"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?"#
private let unitSymbols = #"km/h|°[CF]|kHz|MHz|GHz|mph|lbs|ms|km|cm|mm|kg|mg|lb|GB|MB|KB|TB|Hz|m(?=\s+[a-z])"#

/// One rule's match: the rule matched alone, so its named groups resolve.
private struct Match {
    let result: NSTextCheckingResult
    let src: NSString
    let urls: URLStyle

    var whole: String { src.substring(with: result.range) }
    var end: Int { NSMaxRange(result.range) }
    func group(_ i: Int) -> String { sub(result.range(at: i)) ?? "" }
    func group(_ name: String) -> String? { sub(result.range(withName: name)) }
    private func sub(_ r: NSRange) -> String? { r.location == NSNotFound ? nil : src.substring(with: r) }
}

private struct Rule: Sendable {
    let name: String
    let regex: NSRegularExpression
    let say: @Sendable (Match) -> String

    init(_ name: String, _ pattern: String, _ say: @escaping @Sendable (Match) -> String) {
        self.name = name
        regex = try! NSRegularExpression(pattern: pattern)
        self.say = say
    }
}

private func int(_ s: String) -> Int { Int(s) ?? 0 }

private func domain(_ url: String) -> String {
    let bare = url.replacingOccurrences(of: #"^(?:https?://)?(?:www\.)?"#, with: "", options: .regularExpression)
    let host = bare.split(separator: "/", omittingEmptySubsequences: false)[0].split(separator: "?", omittingEmptySubsequences: false)[0]
    return host.replacingOccurrences(of: ".", with: " dot ")
}

private func link(_ m: Match) -> String { m.urls == .skip ? "" : "link to \(domain(m.whole))" }

private func month(_ token: String) -> String {
    let t = token.trimmingCharacters(in: CharacterSet(charactersIn: ".")).prefix(3).lowercased()
    return months.first { $0.prefix(3).lowercased() == t }!
}

/// The word just before `i` and the word from `i` on. Looks at most 64 characters away.
private func previousWord(_ src: NSString, _ i: Int) -> String {
    let from = max(0, i - 64)
    return src.substring(with: NSRange(from..<i)).split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
}

private func nextWord(_ src: NSString, _ i: Int) -> String {
    src.substring(with: NSRange(i..<min(src.length, i + 64))).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
}

private let rules: [Rule] = [
    Rule("code_block", "(?ms:^```.*?^```[ \\t]*$)") { _ in "Code block." },
    Rule("md_image", #"!\[([^\]]*)\]\([^)]*\)"#) { $0.group(1).isEmpty ? "" : "image, \($0.group(1))" },
    Rule("md_link", #"\[([^\]]+)\]\([^)]*\)"#) { $0.group(1) },
    Rule("footnote", #"\[(?:\d+|[a-z]|citation needed|note \d+)\]"#) { _ in "" },
    Rule("inline_code", "`([^`\\n]+)`") { $0.group(1).split(whereSeparator: \.isWhitespace).count <= 3 ? $0.group(1) : "code" },
    Rule("email", #"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"#) { _ in "an email address" },
    Rule("url", #"\b(?:https?://|www\.)[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"]"#, link),
    Rule("bare_url", #"\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\."# + tld + #"(?:/[^\s<>()]*[^\s<>().,;:!?'"])?(?![\w.]*\w)"#, link),
    Rule("hash_id", #"\b(?=[A-Fa-f0-9-]*\d)(?=[A-Fa-f0-9-]*[A-Fa-f])[A-Fa-f0-9]{8,}(?:-[A-Fa-f0-9]{4,})*\b"#) { _ in "" },
    Rule("md_heading", #"(?m:^#{1,6}[ \t]+)"#) { _ in "\n\n" },
    Rule("md_bullet", #"(?m:^[ \t]*(?:[-*+•]|\d+[.)])[ \t]+)"#) { _ in "\n\n" },
    Rule("md_quote", #"(?m:^>[ \t]?)"#) { _ in "" },
    Rule("md_emph", #"\*\*|__|(?<!\w)\*(?=\S)|(?<=\S)\*(?!\w)"#) { _ in "" },
    Rule("dehyphen", #"(?<=[a-z])-\n(?=[a-z])"#) { _ in "" },
    Rule("paragraph", #"\n[ \t]*\n\s*"#) { _ in "\n\n" },
    Rule("newline", #"[ \t]*\n[ \t]*"#) { _ in " " },
    Rule("currency", #"(?<sym>[$€£¥])\s?(?<amt>"# + num + #")(?:\s?(?<scale>[kKMBT]\b|thousand|million|billion|trillion))?"#) { m in
        let (one, many, sub1, subn) = currency[m.group("sym")!]!
        let amount = m.group("amt")!
        if let scale = m.group("scale") { return "\(numWords(amount)) \(scaleWords[scale]!) \(many)" }
        let parts = amount.replacingOccurrences(of: ",", with: "").split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var out = "\(intWords(int(String(parts[0])))) \(parts[0] == "1" ? one : many)"
        if parts.count > 1, int(String(parts[1])) != 0, !sub1.isEmpty {
            let c = int(String((parts[1] + "00").prefix(2)))
            out += " and \(intWords(c)) \(c == 1 ? sub1 : subn)"
        }
        return out
    },
    Rule("month_day", #"\b(?<mon>(?:Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)\.?|January|February|March|April|May|June|July|August|September|October|November|December)\s(?<d>[12]?\d|3[01])(?!\d|[.,]\d|:)\b(?:,\s(?<y>1[1-9]\d\d|20\d\d)\b(?![-%:]|\.\d|\s?(?:"# + unitSymbols + #")(?![\w/])))?"#) {
        // The year goes with the date, so the comma between them is never a place to split the sentence.
        "\(month($0.group("mon")!)) \(ordinalWords(int($0.group("d")!)))" + ($0.group("y").map { ", \(yearWords(int($0)))" } ?? "")
    },
    Rule("iso_date", #"\b(\d{4})-(\d{2})-(\d{2})\b"#) { m in
        let y = int(m.group(1)), mo = int(m.group(2)), d = int(m.group(3))
        guard (1...12).contains(mo), (1...31).contains(d) else { return m.whole }
        return "\(months[mo - 1]) \(ordinalWords(d)), \(yearWords(y))"
    },
    Rule("time", #"\b(?<h>[01]?\d|2[0-3]):(?<m>[0-5]\d)(?:\s?(?<ap>[AaPp]\.?[Mm]\.?))?(?![\w:])"#) { m in
        let minutes = m.group("m")!, ap = m.group("ap")
        var out = intWords(int(m.group("h")!))
        if minutes != "00" {
            out += " " + (minutes.hasPrefix("0") ? "oh \(ones[int(minutes)])" : intWords(int(minutes)))
        } else if ap == nil {
            out += " o'clock"
        }
        if let ap { out += " " + ("aA".contains(ap.first!) ? "A M" : "P M") }
        return out
    },
    Rule("percent", #"(?<approx>~)?(?<n>"# + num + #")\s?%"#) { ($0.group("approx") == nil ? "" : "about ") + numWords($0.group("n")!) + " percent" },
    Rule("dims", #"\b(\d+)\s?[x×]\s?(\d+)\b"#) { "\(intWords(int($0.group(1)))) by \(intWords(int($0.group(2))))" },
    Rule("times", #"\b(\d+(?:\.\d+)?)x\b"#) { "\(numWords($0.group(1))) times" },
    Rule("unit", #"(?<n>"# + num + #")\s?(?<u>"# + unitSymbols + #")(?![\w/])"#) { m in
        let (one, many) = units[m.group("u")!]!
        let n = m.group("n")!
        return "\(numWords(n)) \(n == "1" ? one : many)"
    },
    Rule("ordinal", #"\b(\d+)(?:st|nd|rd|th)\b"#) { ordinalWords(int($0.group(1))) },
    Rule("version", #"\b(?<v>[vV])?(?<n>\d+\.\d+\.\d+(?:\.\d+)*)\b"#) {
        ($0.group("v") == nil ? "" : "version ") + $0.group("n")!.split(separator: ".").map { numWords(String($0)) }.joined(separator: " point ")
    },
    Rule("decimal", #"(?<![\d.])\d+\.\d+(?![\d.])"#) { numWords($0.whole) },
    Rule("house_no", #"\b(\d+)([A-Z])\b"#) { "\(intWords(int($0.group(1)))) \($0.group(2))" },
    Rule("hashnum", #"#(\d+)\b"#) { m in
        let n = int(m.group(1))
        return "number " + ((1000...9999).contains(n) ? yearWords(n) : intWords(n))
    },
    Rule("number_abbr", #"\bNo\.(?=\s?\d)"#) { _ in "number" },
    Rule("int", #"\b\d{1,3}(?:,\d{3})+\b|\b\d+\b"#) { m in
        let s = m.whole.replacingOccurrences(of: ",", with: "")
        let grouped = m.whole.contains(",")
        if s.count >= 7, !grouped { return digitsWords(s) }
        guard let n = Int(s) else { return digitsWords(s) }
        if (1100...2099).contains(n), !grouped { return yearWords(n) }
        return intWords(n)
    },
    Rule("dr", #"\bDr\."#) { nextWord($0.src, $0.end).first?.isUppercase == true ? "Doctor" : "Drive" },
    Rule("st", #"\bSt\."#) { m in
        let prev = previousWord(m.src, m.result.range.location).first
        if prev?.isUppercase == true || prev?.isNumber == true { return "Street" }
        return nextWord(m.src, m.end).first?.isUppercase == true ? "Saint" : "Street"
    },
    Rule("abbr", abbreviations.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        + #"(?=[\s,;:)]|$)"#) { m in
        let next = m.end < m.src.length ? m.src.substring(with: NSRange(location: m.end, length: 1)) : ""
        return abbreviations[m.whole]! + (["e.g.", "i.e."].contains(m.whole) && next != "," ? ", " : "")
    },
    Rule("acronym", #"\b(?:[A-Z]\.){2,}"#) { $0.whole.replacingOccurrences(of: ".", with: "").map(String.init).joined(separator: " ") },
    Rule("approx", #"~(?=\d)"#) { _ in "about " },
    Rule("arrow", #"\s*(?:→|->|=>)\s*"#) { _ in " to " },
    Rule("amp", #"\s&\s"#) { _ in " and " },
    Rule("emoji", #"[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}\x{200D}]+"#) {
        emojiWords[$0.whole.replacingOccurrences(of: "\u{FE0F}", with: "").replacingOccurrences(of: "\u{200D}", with: "")] ?? ""
    },
]

// MARK: - Segments and chunks

/// A span of source text and what to say for it. Plain text (`rule == nil`) is said as written.
private struct Segment {
    let source: Range<Int>
    let rule: String?
    let spoken: String
}

/// Splits the source at rule matches, scanning left to right. At each point the earliest match of any rule
/// wins, and a tie goes to the earlier rule. Each rule searches on its own, so the regex engine can skip
/// ahead to where it could match, and a rule searches again only once the text passes its last match.
private func segments(_ src: NSString, urls: URLStyle) -> [Segment] {
    let text = src as String, length = src.length
    let bounds: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]
    var next = rules.map { $0.regex.firstMatch(in: text, range: NSRange(location: 0, length: length)) }
    var out: [Segment] = [], pos = 0
    while true {
        for i in rules.indices where (next[i]?.range.location ?? length) < pos {
            next[i] = rules[i].regex.firstMatch(in: text, options: bounds, range: NSRange(location: pos, length: length - pos))
        }
        guard let i = rules.indices.filter({ next[$0] != nil }).min(by: { next[$0]!.range.location < next[$1]!.range.location })
        else { break }
        let m = next[i]!, start = m.range.location, end = NSMaxRange(m.range)
        if start > pos { out.append(Segment(source: pos..<start, rule: nil, spoken: src.substring(with: NSRange(pos..<start)))) }
        out.append(Segment(source: start..<end, rule: rules[i].name, spoken: rules[i].say(Match(result: m, src: src, urls: urls))))
        pos = max(end, start + 1)
    }
    if pos < length { out.append(Segment(source: pos..<length, rule: nil, spoken: src.substring(from: pos))) }
    return out
}

private let sentenceEnd = try! NSRegularExpression(pattern: #"(?:(?<=[.!?])|(?<=[.!?]["')\]”’])|(?<=[.!?]["')\]”’]{2}))\s+(?=["'(\[“‘]?[A-Z0-9])|\n\n"#)
private let clause = try! NSRegularExpression(pattern: #"[,;:—–](?=\s)"#)
private let spaces = try! NSRegularExpression(pattern: #"\s{2,}"#)
private let wordChar = try! NSRegularExpression(pattern: #"\w"#)

private func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

/// Splits spoken text into sentences. A long first sentence is cut at a clause so the voice starts sooner.
private func chunks(_ segs: [Segment], firstMaxWords: Int = 12) -> [Chunk] {
    // Positions in the spoken text that are plain source text, where a clause cut maps back exactly.
    var cuttable = Set<Int>(), spoken = "", spans: [(spoken: Range<Int>, source: Range<Int>, verbatim: Bool)] = []
    for s in segs {
        let start = spoken.utf16.count, end = start + s.spoken.utf16.count
        if s.rule == nil { cuttable.formUnion(start..<end) }
        spans.append((start..<end, s.source, s.rule == nil))
        spoken += s.spoken
    }

    func toSource(_ x: Int, isEnd: Bool) -> Int {
        for span in spans where span.spoken.contains(x) || (isEnd && span.spoken.lowerBound < x && x <= span.spoken.upperBound) {
            if span.verbatim { return span.source.lowerBound + x - span.spoken.lowerBound }
            return isEnd ? span.source.upperBound : span.source.lowerBound
        }
        return spans.last?.source.upperBound ?? 0
    }

    let text = spoken as NSString
    // Every run of non-space in the spoken text, which chunks keep as their words.
    // Words come in order, so the span holding each starts the search for the next, as toSource would find it.
    var words: [(spoken: Range<Int>, source: Range<Int>)] = [], wordStart: Int?, span = 0
    func addWord(_ w: Range<Int>) {
        while span < spans.count - 1, !spans[span].spoken.contains(w.lowerBound) { span += 1 }
        let s = spans[span]
        let start = s.verbatim ? s.source.lowerBound + w.lowerBound - s.spoken.lowerBound : s.source.lowerBound
        let end = s.spoken.upperBound >= w.upperBound
            ? (s.verbatim ? s.source.lowerBound + w.upperBound - s.spoken.lowerBound : s.source.upperBound)
            : toSource(w.upperBound, isEnd: true)
        words.append((w, start..<end))
    }
    for (i, unit) in spoken.utf16.enumerated() {
        if isSpace(unit) {
            if let w = wordStart { addWord(w..<i) }
            wordStart = nil
        } else if wordStart == nil {
            wordStart = i
        }
    }
    if let w = wordStart { addWord(w..<text.length) }
    // Chunks come in order, so each takes the next words that start inside it.
    var nextWord = 0
    func sources(_ spoken: Range<Int>) -> [Range<Int>] {
        while nextWord < words.count, words[nextWord].spoken.lowerBound < spoken.lowerBound { nextWord += 1 }
        let first = nextWord
        while nextWord < words.count, words[nextWord].spoken.lowerBound < spoken.upperBound { nextWord += 1 }
        return words[first..<nextWord].map(\.source)
    }

    var pieces: [Range<Int>] = [], start = 0
    for m in sentenceEnd.matches(in: spoken, range: NSRange(location: 0, length: text.length)) {
        pieces.append(start..<m.range.location)
        start = NSMaxRange(m.range)
    }
    pieces.append(start..<text.length)

    var out: [Chunk] = []
    for piece in pieces {
        let raw = text.substring(with: NSRange(piece))
        var a = piece.lowerBound + raw.utf16.prefix { isSpace($0) }.count
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = spaces.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: s.utf16.count), withTemplate: " ")
        if wordChar.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) == nil { continue }
        if out.isEmpty, wordCount(s) > firstMaxWords {
            for c in clause.matches(in: s, range: NSRange(location: 0, length: s.utf16.count)) {
                let cut = NSMaxRange(c.range), head = (s as NSString).substring(to: cut)
                if cuttable.contains(a + c.range.location), (4...firstMaxWords).contains(wordCount(head)) {
                    out.append(Chunk(text: head, source: toSource(a, isEnd: false)..<toSource(a + cut, isEnd: true),
                                     words: sources(a..<a + cut)))
                    s = (s as NSString).substring(from: cut).trimmingCharacters(in: .whitespacesAndNewlines)
                    a += cut + 1
                    break
                }
            }
        }
        out.append(Chunk(text: s, source: toSource(a, isEnd: false)..<toSource(piece.upperBound, isEnd: true),
                         words: sources(a..<piece.upperBound)))
    }
    return out
}

private func isSpace(_ unit: UTF16.CodeUnit) -> Bool {
    Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
}
