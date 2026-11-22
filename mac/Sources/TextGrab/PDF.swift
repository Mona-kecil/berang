import ApplicationServices
import Foundation

// Preview and Safari show a PDF as an AXPage per page, and Chrome as a region per page. Each page holds one static
// text per paragraph with the paragraph's lines joined by newlines. Headers, footers, and page numbers are paragraphs too.

/// The element holding a PDF's pages: Preview's document, and Safari's PDF view.
let pdfDocumentSubroles: Set = ["AXSharedDocumentContainer", "AXPDFPluginSubrole"]

extension Reader {
    /// Reads `pages` in order, leaving out running headers, footers, and page numbers, and joining a paragraph
    /// that runs on from one page to the next.
    mutating func readPages(_ pages: [Node], chrome: Bool = false) {
        let paragraphs = chrome ? chromeParagraphs(pages.map(chromeLines))
            : pages.map { $0.texts.map { [Part(text: $0.value ?? "", element: $0.element, offset: 0)] } }
        let running = runningLines(paragraphs.map { $0.map { $0.map(\.text).joined(separator: " ") } })
        var open: Paragraph?, openPage = 0
        for (p, parts) in paragraphs.enumerated() {
            for (i, paragraph) in parts.enumerated() where !running.contains([p, i]) {
                if var o = open, p != openPage, o.runsOn, paragraph[0].text.first?.isLowercase == true {
                    for part in paragraph { o.add(part) }
                    open = o
                } else {
                    if let o = open { add(o) }
                    if done { return }
                    var next = Paragraph()
                    for part in paragraph { next.add(part) }
                    open = next
                }
                openPage = p
            }
        }
        if let open { add(open) }
    }

    private mutating func add(_ paragraph: Paragraph) {
        let text = paragraph.text
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
        // PDFs have no heading roles. A short line without closing punctuation reads as one.
        let words = text.split(separator: " ").count
        let heading = text.utf16.count <= 80 && words <= 10 && !(text.last.map { ".,;:!?".contains($0) } ?? true)
            && text.first?.isLowercase == false
        if heading && backMatter.contains(text.lowercased()) { done = true; return }
        blocks.append(Block(kind: heading ? .heading : .text, text: text, runs: paragraph.runs))
    }
}

/// A paragraph built from one or more static texts, with its lines joined into one.
private struct Paragraph {
    var text = ""
    var runs: [Run] = []

    /// Whether the paragraph may go on: it does not end a sentence.
    var runsOn: Bool { !(text.last.map { ".!?:;\"”’)".contains($0) } ?? true) }

    /// Adds `value`, the text of `element`. Line breaks become spaces, and a word hyphenated at a line end is
    /// joined: "metab-\nolic" reads as "metabolic".
    mutating func add(_ part: Part) {
        let element = part.element, base = part.offset
        let value = part.text
        let s = value as NSString
        var start = 0, joined = text.isEmpty
        if !joined, let last = runs.indices.last, hyphenated(text, before: value) {
            // The previous page ended in a hyphenated word.
            text.removeLast()
            runs[last] = Run(element: runs[last].element, range: runs[last].range.dropLast(), offset: runs[last].offset)
            joined = true
        }
        for m in lineEndHyphen.matches(in: value, range: NSRange(location: 0, length: s.length)) {
            append(s.substring(with: NSRange(location: start, length: m.range.location - start)), element, base + start, space: !joined)
            start = NSMaxRange(m.range)
            joined = true
        }
        append(s.substring(from: start), element, base + start, space: !joined)
    }

    private mutating func append(_ piece: String, _ element: AXUIElement, _ offset: Int, space: Bool) {
        if space, text.last?.isWhitespace == false, piece.first?.isWhitespace == false { text += " " }
        let at = text.utf16.count
        // By UTF-16 unit, since "\r\n" is one Character, and so each run's offsets stay those of its element.
        text += (piece as NSString).replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        runs.append(Run(element: element, range: at..<text.utf16.count, offset: offset))
    }
}

private let lineEndHyphen = try! NSRegularExpression(pattern: #"(?<=\p{L})-\r?\n(?=\p{Ll})"#)

private func hyphenated(_ text: String, before next: String) -> Bool {
    text.hasSuffix("-") && text.dropLast().last?.isLetter == true && next.first?.isLowercase == true
}

/// Text an element shows from `offset`.
struct Part {
    let text: String
    let element: AXUIElement
    let offset: Int
}

extension Node {
    /// The non-empty static texts under this node, in order.
    var texts: [Node] {
        var out: [Node] = []
        visit(depth: 20) { n in
            guard n.role == kAXStaticTextRole else { return true }
            if !(n.value ?? "").isEmpty { out.append(n) }
            return false
        }
        return out
    }
}

/// The lines of a page of Chrome's PDF viewer. Chrome ends every line with "\r\n", and a text can hold several
/// lines, or part of one when a link splits it.
func chromeLines(_ page: Node) -> [[Part]] {
    var lines: [[Part]] = [[]]
    for node in page.texts {
        let s = (node.value ?? "") as NSString
        var start = 0
        while start < s.length {
            let end = s.range(of: "\r\n", range: NSRange(location: start, length: s.length - start))
            let stop = end.location == NSNotFound ? s.length : end.location
            let piece = s.substring(with: NSRange(location: start, length: stop - start))
            if piece.contains(where: { !$0.isWhitespace }) { lines[lines.count - 1].append(Part(text: piece, element: node.element, offset: start)) }
            if end.location == NSNotFound { break }
            if !lines[lines.count - 1].isEmpty { lines.append([]) }
            start = NSMaxRange(end)
        }
    }
    return lines.filter { !$0.isEmpty }
}

/// Each page's paragraphs, from its lines. A paragraph ends with a line that ends a sentence before a line that
/// starts with a capital. A heading, a line much shorter than most with no closing punctuation, is a paragraph of
/// its own, as is a page number. Table rows and lines without words, like a chart's axis labels, are left out.
func chromeParagraphs(_ pages: [[[Part]]]) -> [[[Part]]] {
    let text = { (line: [Part]) in line.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
    let lengths = pages.flatMap { $0.map { text($0).utf16.count } }.sorted()
    let typical = lengths.isEmpty ? 0 : lengths[lengths.count / 2]
    let isHeading = { (line: String) in
        line.utf16.count <= min(60, typical * 6 / 10) && line.split(separator: " ").count <= 8
            && (line.first?.isUppercase == true || line.first?.isNumber == true && !isPageNumber(line))
            && !(line.last.map { ".,;:!?\"”’)".contains($0) } ?? true)
    }
    return pages.map { lines in
        var out: [[Part]] = [], group: [Part] = [], last: String?
        func flush() {
            let t = text(group)
            if isPageNumber(t) || t.contains(where: \.isLetter) && !isTableRow(t) { out.append(group) }
            group = []
        }
        for line in lines {
            let b = text(line)
            if let a = last {
                let endsSentence = a.last.map { ".!?:\"”’)".contains($0) } ?? false
                if isHeading(a) || isHeading(b) || isPageNumber(a) || isPageNumber(b)
                    || endsSentence && (b.first?.isUppercase == true || b.first?.isNumber == true) { flush() }
            }
            group += line
            last = b
        }
        if !group.isEmpty { flush() }
        return out
    }
}

/// The paragraphs, by page and index, that are running headers, footers, or page numbers: among the first two and
/// last two of each page, those that are a page number, or a line of at most 100 characters that recurs on
/// another page, numbers aside.
func runningLines(_ pages: [[String]]) -> Set<[Int]> {
    let ends = pages.enumerated().flatMap { p, texts in
        Set(texts.indices.prefix(2)).union(texts.indices.suffix(2))
            .map { (page: p, index: $0, key: texts[$0].count <= 100 ? pattern(texts[$0]) : "\(p) \($0)") }
    }
    var pagesWith: [String: Set<Int>] = [:]
    for e in ends { pagesWith[e.key, default: []].insert(e.page) }
    return Set(ends.filter { isPageNumber(pages[$0.page][$0.index]) || pagesWith[$0.key]!.count > 1 }.map { [$0.page, $0.index] })
}

/// The text with its numbers as "#", so "Chapter 2 · 14" and "Chapter 2 · 15" match.
private func pattern(_ text: String) -> String {
    var out = "", inNumber = false
    for c in text.lowercased() {
        if c.isNumber { if !inNumber { out.append("#") }; inNumber = true; continue }
        inNumber = false
        out.append(c.isWhitespace ? " " : c)
    }
    return out.split(separator: " ").joined(separator: " ")
}

/// "12", "xiv", "- 12 -", "Page 3", or "3 of 10".
private let pageNumber = try! NSRegularExpression(
    pattern: #"^(page\s+)?[-–—\s]*(\d+|[ivxlcdm]+)[-–—\s]*((of|/)\s*\d+)?$"#, options: .caseInsensitive)

func isPageNumber(_ text: String) -> Bool {
    matches(pageNumber, text.trimmingCharacters(in: .whitespacesAndNewlines))
}
