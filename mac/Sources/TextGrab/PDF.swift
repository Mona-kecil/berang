import ApplicationServices
import Foundation

// Preview and Safari show a PDF as an AXPage per page, holding one static text per paragraph with the
// paragraph's lines joined by newlines. Headers, footers, and page numbers are paragraphs too.

/// The element holding a PDF's pages: Preview's document, and Safari's PDF view.
let pdfDocumentSubroles: Set = ["AXSharedDocumentContainer", "AXPDFPluginSubrole"]

extension Reader {
    /// Reads `pages` in order, leaving out running headers, footers, and page numbers, and joining a paragraph
    /// that runs on from one page to the next.
    mutating func readPages(_ pages: [Node]) {
        let paragraphs = pages.map { page in
            var texts: [Node] = []
            page.visit(depth: 20) { n in
                guard n.role == kAXStaticTextRole else { return true }
                if !(n.value ?? "").isEmpty { texts.append(n) }
                return false
            }
            return texts
        }
        let running = runningLines(paragraphs.map { $0.map { $0.value ?? "" } })
        var open: Paragraph?, openPage = 0
        for (p, texts) in paragraphs.enumerated() {
            for (i, node) in texts.enumerated() where !running.contains([p, i]) {
                let text = node.value ?? ""
                if var o = open, p != openPage, o.runsOn, text.first?.isLowercase == true {
                    o.add(text, from: node.element)
                    open = o
                } else {
                    if let o = open { add(o) }
                    if done { return }
                    var next = Paragraph()
                    next.add(text, from: node.element)
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
    mutating func add(_ value: String, from element: AXUIElement) {
        let s = value as NSString
        var start = 0, joined = text.isEmpty
        if !joined, let last = runs.indices.last, hyphenated(text, before: value) {
            // The previous page ended in a hyphenated word.
            text.removeLast()
            runs[last] = Run(element: runs[last].element, range: runs[last].range.dropLast(), offset: runs[last].offset)
            joined = true
        }
        for m in lineEndHyphen.matches(in: value, range: NSRange(location: 0, length: s.length)) {
            append(s.substring(with: NSRange(location: start, length: m.range.location - start)), element, start, space: !joined)
            start = NSMaxRange(m.range)
            joined = true
        }
        append(s.substring(from: start), element, start, space: !joined)
    }

    private mutating func append(_ piece: String, _ element: AXUIElement, _ offset: Int, space: Bool) {
        if space { text += " " }
        let at = text.utf16.count
        text += piece.replacing("\n", with: " ")
        runs.append(Run(element: element, range: at..<text.utf16.count, offset: offset))
    }
}

private let lineEndHyphen = try! NSRegularExpression(pattern: #"(?<=\p{L})-\n(?=\p{Ll})"#)

private func hyphenated(_ text: String, before next: String) -> Bool {
    text.hasSuffix("-") && text.dropLast().last?.isLetter == true && next.first?.isLowercase == true
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
