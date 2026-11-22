import AppKit
import PDFKit

// A PDF's text comes from the file: Preview's accessibility tree leaves out the text around links.

/// A line of a PDF page as PDFKit finds it, in page points with the origin at the bottom left.
struct PDFLine: Equatable {
    let text: String
    let bounds: CGRect
}

/// A paragraph of a PDF, with the page it starts on and how far below the page's top edge, in points.
struct PDFParagraph: Equatable {
    let kind: Block.Kind
    let text: String
    let page: Int
    let top: CGFloat
}

/// Each page's lines, in the order the PDF stores its text, which is reading order for most documents.
/// Pages are read on up to four threads, each with its own copy of the document.
func pdfLines(_ url: URL) -> (lines: [[PDFLine]], heights: [CGFloat])? {
    guard let count = PDFDocument(url: url)?.pageCount, count > 0 else { return nil }
    let workers = min(4, count)
    var lines = [[PDFLine]](repeating: [], count: count), heights = [CGFloat](repeating: 0, count: count)
    lines.withUnsafeMutableBufferPointer { lines in
        heights.withUnsafeMutableBufferPointer { heights in
            nonisolated(unsafe) let (lines, heights) = (lines, heights)
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                guard let doc = PDFDocument(url: url) else { return }
                for i in stride(from: w, to: count, by: workers) {
                    guard let page = doc.page(at: i) else { continue }
                    let box = page.bounds(for: .mediaBox)
                    heights[i] = box.height
                    lines[i] = (page.selection(for: box)?.selectionsByLine() ?? []).compactMap { line in
                        guard let text = line.string, !text.isEmpty else { return nil }
                        let b = line.bounds(for: page)
                        return PDFLine(text: text, bounds: b.offsetBy(dx: -box.minX, dy: -box.minY))
                    }
                }
            }
        }
    }
    return (lines, heights)
}

/// The paragraphs of a PDF, in reading order, without running headers and footers, page numbers, footnotes,
/// figure and table captions, or anything after the references heading. A paragraph that runs on to the next
/// page or column is one paragraph, and a word hyphenated at a line end is joined.
func pdfParagraphs(_ pages: [[PDFLine]], heights: [CGFloat]) -> [PDFParagraph] {
    let pages = pages.enumerated().map { p, lines in
        withoutFootnotes(joinFragments(lines.filter { l in
            // Text set sideways, like arXiv's stamp in the margin.
            !(l.bounds.height > 3 * l.bounds.width && l.bounds.height > 40) && l.text.contains { !$0.isWhitespace }
        }), pageHeight: heights[safe: p] ?? 0).filter { !isTableRow($0.text) }
    }
    let running = runningLines(pages.map { $0.map(\.text) })
    let lineHeight = median(pages.flatMap { $0.map(\.bounds.height) }) ?? 10
    // The space between lines of a paragraph. Vision's line boxes are taller than PDFKit's, so this is smaller for an image.
    let leading = median(pages.flatMap { zip($0, $0.dropFirst()).map { $0.bounds.minY - $1.bounds.maxY }.filter { $0 >= -lineHeight / 4 && $0 < lineHeight } }) ?? 0

    var out: [PDFParagraph] = []
    var lines: [PDFLine] = [], start = (page: 0, top: CGFloat(0)), lastPage = 0
    func flush() {
        defer { lines = [] }
        guard !lines.isEmpty else { return }
        let text = joinLines(lines.map(\.text))
        let words = text.split(separator: " ").count
        let heading = lines.count <= 2 && text.utf16.count <= 80 && words <= 12 && !endsSentence(text) && !text.hasSuffix(",")
            && text.first?.isLowercase == false
        out.append(PDFParagraph(kind: heading ? .heading : .text, text: text, page: start.page, top: start.top))
    }
    for (p, page) in pages.enumerated() {
        let kept = page.indices.filter { !running.contains([p, $0]) }.map { page[$0] }
        for (i, line) in kept.enumerated() {
            if let last = lines.last, breaks(after: last, before: line, next: kept[safe: i + 1], lineHeight: lineHeight, leading: leading,
                                             samePage: lastPage == p) { flush() }
            if lines.isEmpty { start = (p, heights[safe: p].map { $0 - line.bounds.maxY } ?? 0) }
            lines.append(line)
            lastPage = p
        }
    }
    flush()
    return clean(out, lineHeight: lineHeight)
}

/// Whether a new paragraph starts at `line`, which follows `last`.
private func breaks(after last: PDFLine, before line: PDFLine, next: PDFLine?, lineHeight: CGFloat, leading: CGFloat, samePage: Bool) -> Bool {
    // The first line of a paragraph is often set in from the lines after it.
    let indented = next.map { line.bounds.minX > $0.bounds.minX + 4 && abs(line.bounds.minX - $0.bounds.minX) < 40 } ?? false
    if !samePage || line.bounds.maxY > last.bounds.minY + lineHeight {
        // A new page or column: the paragraph goes on unless the last one ended a sentence and this one starts anew.
        return endsSentence(last.text) && (indented || line.text.first?.isLowercase == false)
    }
    if startsListItem(line.text) { return true }
    let gap = last.bounds.minY - line.bounds.maxY
    // A heading or caption is set in another size.
    let resized = abs(line.bounds.height - last.bounds.height) > 0.2 * min(line.bounds.height, last.bounds.height)
    return gap > leading + 0.5 * lineHeight || resized || indented && endsSentence(last.text) || line.bounds.minX > last.bounds.maxX
}

/// "• Item", "- Item", "3. Item", "12) Item", or "(a) Item".
private func startsListItem(_ text: String) -> Bool {
    let t = text.drop { $0.isWhitespace }
    guard let space = t.firstIndex(of: " ") else { return false }
    let marker = t[..<space]
    if marker.count == 1 { return "•◦▪‣–-*".contains(marker.first!) }
    return marker.count <= 4 && marker.dropLast().allSatisfy(\.isNumber) && ".)".contains(marker.last!)
        || marker.count == 3 && marker.first == "(" && marker.last == ")"
}

/// Leaves out footnotes: from a line in the bottom fifth of the page that starts with a footnote mark, like "∗" or a
/// number set against its text, to the end of that column.
private func withoutFootnotes(_ lines: [PDFLine], pageHeight: CGFloat) -> [PDFLine] {
    // The bottom of the footnote so far. A line above it starts the next column.
    var note: CGFloat?, out: [PDFLine] = []
    for l in lines {
        if let bottom = note, l.bounds.minY > bottom { note = nil }
        if note == nil, l.bounds.maxY < 0.2 * pageHeight, startsFootnote(l.text) {
            note = l.bounds.minY
        }
        if note != nil { note = l.bounds.minY } else { out.append(l) }
    }
    return out
}

/// Leaves out figure and table captions, tables of numbers, and what follows the references heading.
private func clean(_ paragraphs: [PDFParagraph], lineHeight: CGFloat) -> [PDFParagraph] {
    var out: [PDFParagraph] = []
    for p in paragraphs {
        let title = p.text.drop { $0.isNumber || $0 == "." || $0 == " " }.lowercased()
        if p.kind == .heading && backMatter.contains(title) { break }
        if matches(caption, p.text) { continue }
        let visible = p.text.filter { !$0.isWhitespace }
        if visible.count >= 8, Double(visible.count(where: \.isLetter)) < 0.4 * Double(visible.count) { continue }
        out.append(p)
    }
    return out
}

/// Joins pieces of one line that PDFKit reports apart, like a word set in another font.
private func joinFragments(_ lines: [PDFLine]) -> [PDFLine] {
    var out: [PDFLine] = []
    for l in lines {
        if let last = out.last, abs(l.bounds.minY - last.bounds.minY) < 0.3 * max(l.bounds.height, 1),
           l.bounds.minX >= last.bounds.maxX - 1 {
            let space = last.text.last?.isWhitespace == true || l.text.first?.isWhitespace == true ? "" : " "
            out[out.count - 1] = PDFLine(text: last.text + space + l.text, bounds: last.bounds.union(l.bounds))
        } else {
            out.append(l)
        }
    }
    return out
}

/// A row of a table of numbers: at least three numbers, like "67.0%" or "3.3", and as many numbers as words.
private func isTableRow(_ text: String) -> Bool {
    let words = text.split(whereSeparator: \.isWhitespace)
    let numbers = words.count { word in
        let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "()[],;"))
        return w.first.map { $0.isNumber || "−-+".contains($0) } == true
            && w.drop { !$0.isLetter }.count <= 2 && w.contains(where: \.isNumber)
    }
    return numbers >= 3 && numbers * 2 >= words.count
}

/// "Figure 2:", "Fig. 2.", or "Table 1:" at the start of a caption.
private let caption = try! NSRegularExpression(pattern: #"^(Figure|Fig\.|Table)\s*\d+[:.]"#)

func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
}

/// Whether a line starts like a footnote: "∗", "†", or a number of one or two digits set against its text.
private func startsFootnote(_ text: String) -> Bool {
    let t = text.drop(while: \.isWhitespace)
    guard let first = t.first else { return false }
    if "∗*†‡§¶".contains(first) { return true }
    let digits = t.prefix(while: \.isASCII).prefix(while: \.isNumber)
    return (1...2).contains(digits.count) && t.dropFirst(digits.count).first?.isLetter == true
}

/// One paragraph's lines as one line: "metab-" and "olic" join into "metabolic".
func joinLines(_ lines: [String]) -> String {
    var text = ""
    for raw in lines {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if text.hasSuffix("-"), text.dropLast().last?.isLetter == true, line.first?.isLowercase == true {
            text.removeLast()
        } else if !text.isEmpty {
            text += " "
        }
        text += line
    }
    return text
}

private func endsSentence(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).last.map { ".!?:\"”’)".contains($0) } ?? false
}

private func median(_ values: [CGFloat]) -> CGFloat? {
    values.isEmpty ? nil : values.sorted()[values.count / 2]
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// The blocks of the PDF at `url`, or nil when it is not a PDF.
public func readPDF(_ url: URL) -> [Block]? {
    pdfLines(url).map { pdfParagraphs($0.lines, heights: $0.heights).map(\.block) }
}

extension PDFParagraph {
    var block: Block { Block(kind: kind, text: text, runs: []) }
}

/// A PDF that Preview or Safari shows from a file, read from the file. Nil for other windows, and for a PDF
/// from the web, which is read from the accessibility tree.
func readPDFFile(_ document: AXUIElement, in window: AXUIElement, app: NSRunningApplication) -> Page? {
    guard let address = address(window, document), let url = URL(string: address), url.isFileURL,
          let pdf = pdfLines(url) else { return nil }
    let paragraphs = pdfParagraphs(pdf.lines, heights: pdf.heights)
    let clip = scrollArea(around: document) ?? window
    let pages = (document.get(kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { $0.string(kAXRoleAttribute) == "AXPage" }
    let start = visibleFrame(of: document, in: clip).map { pdfStart(paragraphs, pages: pages, heights: pdf.heights, screen: $0) } ?? 0
    return Page(app: app.localizedName ?? "", window: window.string(kAXTitleAttribute) ?? "", blocks: paragraphs.map(\.block),
                viewport: document, clip: clip, start: start, startPoint: .screen, address: address)
}

/// The first paragraph at or below the top of `screen`, found from where the app shows each page.
private func pdfStart(_ paragraphs: [PDFParagraph], pages: [AXUIElement], heights: [CGFloat], screen: CGRect) -> Int {
    let frame = { (p: Int) in pages[p].get("AXFrame").flatMap(rect) }
    let p = firstIndex(pages.count) { (frame($0)?.maxY ?? 0) <= screen.minY }
    guard p < pages.count, let f = frame(p), let height = heights[safe: p], height > 0 else { return 0 }
    // How far down the page the screen's top edge is, in the page's points.
    let offset = (screen.minY - f.minY) * height / f.height
    return paragraphs.firstIndex { $0.page > p || $0.page == p && $0.top >= offset - 2 } ?? 0
}

/// A PDF's lines and page heights, saved so tests can read it the way `readPDF` reads the file.
public struct SavedPDF: Codable, Sendable {
    struct Line: Codable { let t: String; let b: [CGFloat] }
    let heights: [CGFloat]
    let pages: [[Line]]

    public init?(url: URL) {
        guard let pdf = pdfLines(url) else { return nil }
        heights = pdf.heights
        pages = pdf.lines.map { $0.map { Line(t: $0.text, b: [$0.bounds.minX, $0.bounds.minY, $0.bounds.width, $0.bounds.height]) } }
    }

    public func read() -> [Block] {
        let lines = pages.map { $0.map { PDFLine(text: $0.t, bounds: CGRect(x: $0.b[0], y: $0.b[1], width: $0.b[2], height: $0.b[3])) } }
        return pdfParagraphs(lines, heights: heights).map(\.block)
    }
}
