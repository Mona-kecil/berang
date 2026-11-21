import AppKit
import ApplicationServices

/// The readable text of one window, in reading order.
public struct Page {
    public let app: String
    public let window: String
    public let blocks: [Block]
}

/// A paragraph, heading, or list item.
public struct Block {
    public enum Kind { case heading, text }
    public let kind: Kind
    public let text: String
    /// Where each piece of `text` came from, so a spoken word can be located on screen later.
    public let runs: [Run]
}

/// `range` (UTF-16 offsets in `Block.text`) shows the text of `element` starting at `offset` in that element.
public struct Run {
    public let element: AXUIElement
    public let range: Range<Int>
    public let offset: Int
}

public enum GrabError: Error, CustomStringConvertible {
    case notTrusted, noWindow

    public var description: String {
        switch self {
        case .notTrusted: "Accessibility access is off for this app. Turn it on in System Settings > Privacy & Security > Accessibility."
        case .noWindow: "The app has no window to read."
        }
    }
}

/// Reads the main text of the focused window of `app`, or of the first window whose title starts with `windowTitle`.
public func grab(_ app: NSRunningApplication, windowTitle: String? = nil) throws -> Page {
    guard AXIsProcessTrusted() else { throw GrabError.notTrusted }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 1)
    // Electron apps build their accessibility tree only when asked.
    AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    let window: AXUIElement? = if let windowTitle {
        (ax.get(kAXWindowsAttribute) as? [AXUIElement])?.first { ($0.string(kAXTitleAttribute) ?? "").hasPrefix(windowTitle) }
    } else {
        ax.element(kAXFocusedWindowAttribute) ?? ax.element(kAXMainWindowAttribute)
    }
    guard let window else { throw GrabError.noWindow }

    var reader = Reader()
    if let web = Node(window).first(depth: 30, where: { $0.role == "AXWebArea" }) {
        // One article is the content (a post, a README). Several articles are a feed, read whole from main.
        var main: Node?, articles: [Node] = []
        web.visit(depth: 40) { n in
            if n.subrole == "AXLandmarkMain" && main == nil { main = n }
            if n.subrole == "AXDocumentArticle" { articles.append(n); return false }
            return !n.isSkipped
        }
        reader.web = true
        reader.layoutTables = main == nil && articles.isEmpty
        reader.walk(articles.count == 1 ? articles[0] : main ?? web)
    } else if let area = textArea(in: window) {
        reader.readTextArea(area)
    } else {
        reader.walk(Node(window))
    }
    return Page(app: app.localizedName ?? "", window: window.string(kAXTitleAttribute) ?? "", blocks: reader.blocks)
}

/// The focused text area, or else the one holding the most text.
private func textArea(in window: AXUIElement) -> Node? {
    let isArea = { (n: Node) in n.role == "AXTextArea" && !(n.value ?? "").isEmpty }
    let app = AXUIElementCreateApplication(window.pid)
    if let focused = app.element(kAXFocusedUIElementAttribute).map(Node.init), isArea(focused) { return focused }
    var best: Node?
    Node(window).visit(depth: 30) { n in
        if isArea(n), n.value!.utf16.count > (best?.value?.utf16.count ?? 0) { best = n }
        return n.role != "AXTextArea"
    }
    return best
}

/// Subtrees a listener never wants read: site chrome, controls, images, and tables.
private let skippedSubroles: Set = [
    "AXLandmarkNavigation", "AXLandmarkBanner", "AXLandmarkContentInfo", "AXLandmarkSearch",
    "AXLandmarkForm", "AXLandmarkComplementary", "AXApplicationDialog", "AXApplicationAlertDialog",
]
private let skippedRoles: Set = [
    "AXListMarker", "AXButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
    "AXComboBox", "AXMenu", "AXMenuBar", "AXToolbar", "AXImage", "AXTable", "AXScrollBar", "AXSlider", "AXTabGroup",
]

/// Section headings that end the readable part of an article.
private let backMatter: Set = [
    "references", "notes", "citations", "sources", "bibliography", "footnotes", "external links", "further reading", "see also",
]

private struct Reader {
    var blocks: [Block] = []
    var web = false
    /// Read header-less tables. Only pages without a main or article landmark still lay out text with tables.
    var layoutTables = false
    /// Set at the first back-matter heading; nothing after it is read.
    var done = false

    /// An element that directly holds text is one block; everything under it joins that block.
    mutating func walk(_ node: Node) {
        if done || node.isSkipped && !(layoutTables && node.isLayoutTable) { return }
        let children = node.children
        if node.role == "AXHeading" || children.contains(where: { $0.role == "AXStaticText" }) {
            var block = BlockBuilder(), nested: [Node] = []
            block.collect(node, nested: &nested)
            let kind: Block.Kind = node.role == "AXHeading" ? .heading : .text
            for b in block.build(kind, rendered: web ? renderedText(node.element) : nil) {
                if kind == .heading && backMatter.contains(b.text.lowercased()) { done = true; return }
                blocks.append(b)
            }
            for n in nested { walk(n) }
        } else {
            for child in children { walk(child) }
        }
    }

    mutating func readTextArea(_ area: Node) {
        var offset = 0
        for line in (area.value ?? "").split(separator: "\n", omittingEmptySubsequences: false) {
            var block = BlockBuilder()
            block.append(String(line), from: area.element, at: offset)
            blocks += block.build(.text)
            offset += line.utf16.count + 1
        }
    }
}

struct BlockBuilder {
    var pieces: [(element: AXUIElement, text: String, offset: Int)] = []

    /// Gathers the text under `node`. Lists and headings inside it are left in `nested` to read as their own blocks.
    fileprivate mutating func collect(_ node: Node, nested: inout [Node]) {
        if node.isSkipped { return }
        if node.role == "AXStaticText", let v = node.value { append(v, from: node.element, at: 0) }
        for child in node.children {
            if child.role == "AXList" || child.role == "AXHeading" { nested.append(child) } else { collect(child, nested: &nested) }
        }
    }

    mutating func append(_ text: String, from element: AXUIElement, at offset: Int) {
        pieces.append((element, text, offset))
    }

    /// `rendered` is the browser's own text for the element. Safari trims the text pieces, so joining
    /// them loses the spaces around links, and neither browser puts line breaks in the pieces.
    func build(_ kind: Block.Kind, rendered: String? = nil) -> [Block] {
        let blocks = rendered.flatMap { align(kind, $0) } ?? align(kind, pieces.map(\.text).joined()) ?? []
        return blocks.filter { $0.text.contains { $0.isLetter || $0.isNumber } }
    }

    /// Finds each piece in `source`, in order, then makes one block per line of `source`. Each block spans
    /// its first piece to its last, which drops list markers and nested blocks. Nil when a piece is missing.
    private func align(_ kind: Block.Kind, _ source: String) -> [Block]? {
        let hay = Array(squash(source, keepingLines: true).utf16)
        var cursor = 0, lines: [[Run]] = [], line = -1
        for p in pieces {
            let raw = p.text.replacing("\u{FFFC}", with: "")
            let piece = squash(raw)
            if piece.isEmpty { continue }
            guard let at = find(Array(piece.utf16), in: hay, from: cursor) else { return nil }
            let lead = raw.utf16.count - raw.drop(while: \.isWhitespace).utf16.count
            let run = Run(element: p.element, range: at..<at + piece.utf16.count, offset: p.offset + lead)
            let n = hay[..<at].count(where: { $0 == newline })
            if n == line { lines[lines.count - 1].append(run) } else { lines.append([run]); line = n }
            cursor = run.range.upperBound
        }
        return lines.map { runs in
            let start = runs[0].range.lowerBound, end = runs[runs.count - 1].range.upperBound
            let text = String(decoding: hay[start..<end].map { $0 == newline ? space : $0 }, as: UTF16.self)
            return Block(kind: kind, text: text, runs: runs.map {
                Run(element: $0.element, range: $0.range.lowerBound - start..<$0.range.upperBound - start, offset: $0.offset)
            })
        }
    }
}

private let newline = UInt16(UInt8(ascii: "\n")), space = UInt16(UInt8(ascii: " "))

/// Collapses each whitespace run to one space (or one newline, if it holds one and `keepingLines`) and trims.
private func squash(_ s: String, keepingLines: Bool = false) -> String {
    var out = "", gap: Character?
    for c in s where c != "\u{FFFC}" {
        if c.isWhitespace {
            if keepingLines && c.isNewline { gap = "\n" } else if gap == nil { gap = " " }
        } else {
            if let g = gap, !out.isEmpty { out.append(g) }
            gap = nil
            out.append(c)
        }
    }
    return out
}

/// Index of `needle` in `hay` at or after `start`, where a newline in `hay` matches a space.
private func find(_ needle: [UInt16], in hay: [UInt16], from start: Int) -> Int? {
    guard needle.count <= hay.count - start else { return nil }
    outer: for i in start...(hay.count - needle.count) {
        for (j, c) in needle.enumerated() where hay[i + j] != c && !(c == space && hay[i + j] == newline) { continue outer }
        return i
    }
    return nil
}

/// The text a browser renders for `element`, read through WebKit/Chromium text markers.
private func renderedText(_ element: AXUIElement) -> String? {
    // Chromium exposes the range as a plain attribute, WebKit as a parameterized one.
    guard let range = element.get("AXTextMarkerRangeForUIElement")
        ?? element.get("AXTextMarkerRangeForUIElement", element) else { return nil }
    return element.get("AXStringForTextMarkerRange", range) as? String
}

/// One element with the attributes the reader needs, fetched in a single call.
private final class Node {
    let element: AXUIElement
    let role: String?
    let subrole: String?
    let value: String?
    private let childElements: [AXUIElement]

    init(_ element: AXUIElement) {
        self.element = element
        let attrs = [kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXChildrenAttribute] as CFArray
        var out: CFArray?
        AXUIElementCopyMultipleAttributeValues(element, attrs, [], &out)
        let v = (out as? [AnyObject]) ?? []
        role = v.count > 0 ? v[0] as? String : nil
        subrole = v.count > 1 ? v[1] as? String : nil
        value = v.count > 2 ? v[2] as? String : nil
        childElements = v.count > 3 ? (v[3] as? [AXUIElement]) ?? [] : []
    }

    private(set) lazy var children: [Node] = childElements.map(Node.init)
    var isSkipped: Bool { skippedRoles.contains(role ?? "") || skippedSubroles.contains(subrole ?? "") }
    /// A table without column headers, used to lay out a page rather than to hold data.
    var isLayoutTable: Bool {
        role == "AXTable" && ((element.get("AXColumnHeaderUIElements") as? [AXUIElement]) ?? []).isEmpty
    }

    /// Breadth-first search, so the shallowest match wins.
    func first(depth: Int, where match: (Node) -> Bool) -> Node? {
        var level = [self]
        for _ in 0...depth where !level.isEmpty {
            if let hit = level.first(where: match) { return hit }
            level = level.flatMap(\.children)
        }
        return nil
    }

    /// Depth-first visit; `body` returns whether to descend into the node.
    func visit(depth: Int, _ body: (Node) -> Bool) {
        guard depth >= 0, body(self) else { return }
        for child in children { child.visit(depth: depth - 1, body) }
    }
}

extension AXUIElement {
    func get(_ attribute: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &v) == .success ? v : nil
    }

    func get(_ attribute: String, _ parameter: AnyObject) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyParameterizedAttributeValue(self, attribute as CFString, parameter, &v) == .success ? v : nil
    }

    func string(_ attribute: String) -> String? { get(attribute) as? String }

    func element(_ attribute: String) -> AXUIElement? {
        guard let v = get(attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }
}
