import AppKit
import ApplicationServices

/// The readable text of one window, in reading order.
public struct Page {
    public let app: String
    public let window: String
    public let blocks: [Block]
    /// The element that shows the text: the web area, the text area, or the window.
    public let viewport: AXUIElement
    /// What the viewport is scrolled inside. A web area's frame covers the whole page, not the part on screen.
    let clip: AXUIElement?
    /// The block to start reading at: the selected text, the clicked block if it is on screen, or the first block on screen.
    public let start: Int
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
    let (ax, window) = try window(of: app, titled: windowTitle)
    // WebKit builds a page's accessibility tree on the first request, so the first read of a page
    // can find only the window. A read that finds no page or text area and little text tries again.
    for attempt in 0... {
        let root = Node(window)
        let (blocks, viewport) = read(root, focused: ax.element(kAXFocusedUIElementAttribute).map(Node.init))
        if viewport !== root || attempt == 3 || blocks.reduce(0, { $0 + $1.text.utf16.count }) >= 200 {
            let clip = scrollArea(around: viewport.element) ?? window
            return Page(app: app.localizedName ?? "", window: window.string(kAXTitleAttribute) ?? "", blocks: blocks,
                        viewport: viewport.element, clip: clip, start: startBlock(blocks, in: viewport.element, clip: clip))
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
    fatalError("unreachable")
}

/// Copies the window that `grab` would read, for tests that run without the app. See `read(saved:)`.
public func save(_ app: NSRunningApplication, windowTitle: String? = nil) throws -> SavedNode {
    let (ax, window) = try window(of: app, titled: windowTitle)
    return SavedNode(Node(window), focused: ax.element(kAXFocusedUIElementAttribute), depth: 80)
}

/// Reads a saved window the way `grab` reads a live one.
public func read(saved window: SavedNode) -> [Block] {
    let root = Node(saved: window)
    var focused: Node?
    root.visit(depth: 80) { n in
        if n.saved?.focused == true { focused = n }
        return focused == nil
    }
    return read(root, focused: focused).blocks
}

/// Blocks as Markdown: headings start with "# ", and a blank line separates blocks.
public func markdown(_ blocks: [Block]) -> String {
    blocks.map { $0.kind == .heading ? "# \($0.text)" : $0.text }.joined(separator: "\n\n") + "\n"
}

private func scrollArea(around element: AXUIElement) -> AXUIElement? {
    var parent = element.element(kAXParentAttribute)
    for _ in 0..<4 {
        guard let p = parent else { return nil }
        if p.string(kAXRoleAttribute) == kAXScrollAreaRole { return p }
        parent = p.element(kAXParentAttribute)
    }
    return nil
}

private func window(of app: NSRunningApplication, titled title: String?) throws -> (app: AXUIElement, window: AXUIElement) {
    guard AXIsProcessTrusted() else { throw GrabError.notTrusted }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 1)
    // Electron apps build their accessibility tree only when asked.
    AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    // A locked screen or a broken app can report the application itself as its window.
    let isWindow = { (w: AXUIElement) in w.string(kAXRoleAttribute) == kAXWindowRole }
    let window: AXUIElement? = if let title {
        (ax.get(kAXWindowsAttribute) as? [AXUIElement])?.first { isWindow($0) && ($0.string(kAXTitleAttribute) ?? "").hasPrefix(title) }
    } else {
        [kAXFocusedWindowAttribute, kAXMainWindowAttribute].lazy.compactMap { ax.element($0) }.first(where: isWindow)
    }
    guard let window else { throw GrabError.noWindow }
    return (ax, window)
}

private func read(_ window: Node, focused: Node?) -> (blocks: [Block], viewport: Node) {
    var reader = Reader()
    if let web = window.first(depth: 30, where: { $0.role == "AXWebArea" }) {
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
        return (reader.blocks, web)
    }
    if let area = textArea(in: window, focused: focused) {
        reader.readTextArea(area)
        return (reader.blocks, area)
    }
    reader.walk(window)
    return (reader.blocks, window)
}

/// The focused text area, or else the one holding the most text.
private func textArea(in window: Node, focused: Node?) -> Node? {
    let isArea = { (n: Node) in n.role == "AXTextArea" && !(n.value ?? "").isEmpty }
    if let focused, isArea(focused) { return focused }
    var best: Node?
    window.visit(depth: 30) { n in
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

/// Class names of ad slots.
private let adClasses: Set = ["ad", "ads", "advert", "advertisement", "adsbygoogle", "ad-slot", "ad-container", "ad-wrapper", "ad-unit", "sponsored"]

/// What browsers call a figure. The name is localized; WebKit's comes from WebCore's strings.
private let figureNames: Set = {
    let webCore = Bundle(path: "/System/Library/Frameworks/WebKit.framework/Frameworks/WebCore.framework")
    return ["figure", webCore?.localizedString(forKey: "figure", value: nil, table: nil) ?? "figure"]
}()

/// Deeper than any real page; only a tree that loops back on itself gets here.
private let maxDepth = 200

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
    /// The depth limit stops a tree that loops back on itself.
    mutating func walk(_ node: Node, depth: Int = 0) {
        if done || depth > maxDepth || node.isSkipped && !(layoutTables && node.isLayoutTable) { return }
        let children = node.children
        if node.role == "AXHeading" || children.contains(where: { $0.role == "AXStaticText" }) {
            var block = BlockBuilder(), nested: [Node] = []
            block.collect(node, nested: &nested)
            let kind: Block.Kind = node.role == "AXHeading" ? .heading : .text
            for b in block.build(kind, rendered: web ? node.rendered : nil) {
                if kind == .heading && backMatter.contains(b.text.lowercased()) { done = true; return }
                blocks.append(b)
            }
            for n in nested { walk(n, depth: depth + 1) }
        } else {
            for child in children { walk(child, depth: depth + 1) }
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
    /// A skipped piece is text the browser shows but the listener should not hear, such as a caption.
    var pieces: [(element: AXUIElement, text: String, offset: Int, skipped: Bool)] = []

    /// Gathers the text under `node`. Lists and headings inside it are left in `nested` to read as their own blocks.
    fileprivate mutating func collect(_ node: Node, nested: inout [Node], depth: Int = 0) {
        if depth > maxDepth { return }
        if node.isSkipped {
            if node.role == kAXGroupRole || node.role == "AXTable", let text = node.rendered { skip(text, from: node.element) }
            return
        }
        if node.role == "AXStaticText", let v = node.value { append(v, from: node.element, at: 0) }
        for child in node.children {
            if child.role == "AXList" || child.role == "AXHeading" { nested.append(child) } else { collect(child, nested: &nested, depth: depth + 1) }
        }
    }

    mutating func append(_ text: String, from element: AXUIElement, at offset: Int) {
        pieces.append((element, text, offset, false))
    }

    /// Marks where skipped text sits in the rendered text, so a later piece that repeats it, like a
    /// paragraph that starts with its figure's caption, is not matched there.
    mutating func skip(_ text: String, from element: AXUIElement) {
        pieces.append((element, text, 0, true))
    }

    /// `rendered` is the browser's own text for the element. Safari trims the text pieces, so joining
    /// them loses the spaces around links, and neither browser puts line breaks in the pieces.
    func build(_ kind: Block.Kind, rendered: String? = nil) -> [Block] {
        let blocks = rendered.flatMap { align(kind, $0) } ?? align(kind, pieces.filter { !$0.skipped }.map(\.text).joined()) ?? []
        return blocks.filter { $0.text.contains { $0.isLetter || $0.isNumber } }
    }

    /// Finds each piece in `source`, in order, then makes one block per line of `source`. Each block spans
    /// its first piece to its last, which drops list markers and nested blocks. A piece the browser does not
    /// show, like a media player's "Elapsed: 0 seconds", is left out. Nil when most of the text is missing.
    private func align(_ kind: Block.Kind, _ source: String) -> [Block]? {
        let hay = Array(squash(source, keepingLines: true).utf16)
        // `beforeSkip` is where the search stood before skipped text moved it on. The browser can put skipped
        // text, like a floated caption, after the next piece, so that piece is searched for from there too.
        var cursor = 0, lines: [[Run]] = [], line = -1, newlines = 0, beforeSkip: Int?, found = 0, missing = 0
        for p in pieces {
            let raw = p.text.replacing("\u{FFFC}", with: "")
            let piece = squash(raw)
            if piece.isEmpty { continue }
            if p.skipped {
                if let at = find(Array(piece.utf16), in: hay, from: cursor) {
                    beforeSkip = beforeSkip ?? cursor
                    newlines += hay[cursor..<at + piece.utf16.count].count(where: { $0 == newline })
                    cursor = at + piece.utf16.count
                }
                continue
            }
            let needle = Array(piece.utf16)
            if let start = beforeSkip, find(needle, in: hay, from: cursor) == nil {
                newlines -= hay[start..<cursor].count(where: { $0 == newline })
                cursor = start
            }
            beforeSkip = nil
            guard let at = find(needle, in: hay, from: cursor) else {
                missing += needle.count
                continue
            }
            found += needle.count
            let lead = raw.utf16.count - raw.drop(while: \.isWhitespace).utf16.count
            let run = Run(element: p.element, range: at..<at + piece.utf16.count, offset: p.offset + lead)
            newlines += hay[cursor..<at].count(where: { $0 == newline })
            if newlines == line { lines[lines.count - 1].append(run) } else { lines.append([run]); line = newlines }
            cursor = run.range.upperBound
        }
        if missing > found { return nil }
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

/// One element with the attributes the reader needs, fetched in a single call, or read from a saved copy.
private final class Node {
    let element: AXUIElement
    let role: String?
    let subrole: String?
    let value: String?
    let saved: SavedNode?
    private let childElements: [AXUIElement]

    init(_ element: AXUIElement) {
        self.element = element
        let v = element.get([kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXChildrenAttribute])
        role = v[0] as? String
        subrole = v[1] as? String
        value = v[2] as? String
        childElements = v[3] as? [AXUIElement] ?? []
        saved = nil
    }

    /// A saved element has no live counterpart, so `element` is a placeholder.
    init(saved: SavedNode) {
        element = AXUIElementCreateSystemWide()
        role = saved.role
        subrole = saved.subrole
        value = saved.value
        childElements = []
        self.saved = saved
    }

    private(set) lazy var children: [Node] = saved.map { ($0.children ?? []).map(Node.init(saved:)) } ?? childElements.map(Node.init)
    var isSkipped: Bool {
        skippedRoles.contains(role ?? "") || skippedSubroles.contains(subrole ?? "") || isCodeBlock || isFigure || isAd
    }
    /// WebKit marks a `<pre>` as preformatted; Chrome shows it as a group holding only code.
    private var isCodeBlock: Bool {
        subrole == "AXPreformattedStyleGroup"
            || role == "AXGroup" && !children.isEmpty && children.allSatisfy { $0.subrole == "AXCodeStyleGroup" }
    }
    private var isFigure: Bool { figureNames.contains(group?.roleDescription ?? "") }
    private var isAd: Bool { group?.classes.contains { adClasses.contains($0.lowercased()) } ?? false }

    /// A group's role description and class names, which mark figures and ad slots. Only groups that hold
    /// other elements rather than text are asked: asking every element slows a whole-page read by a fifth.
    fileprivate private(set) lazy var group: (roleDescription: String, classes: [String])? = {
        guard role == kAXGroupRole, !children.contains(where: { $0.role == kAXStaticTextRole }) else { return nil }
        if let saved { return (saved.roleDescription ?? "group", saved.classes ?? []) }
        let v = element.get([kAXRoleDescriptionAttribute, "AXDOMClassList"])
        return (v[0] as? String ?? "", v[1] as? [String] ?? [])
    }()
    /// The browser's rendered text, which only blocks in a web area ask for.
    var rendered: String? { saved == nil ? renderedText(element) : saved?.rendered }
    /// A table without column headers, used to lay out a page rather than to hold data.
    var isLayoutTable: Bool { role == "AXTable" && columnHeaders == 0 }
    fileprivate var columnHeaders: Int {
        saved.map { $0.headers ?? 0 } ?? ((element.get("AXColumnHeaderUIElements") as? [AXUIElement]) ?? []).count
    }
    /// Whether the reader would make a block here and so ask for `rendered`.
    fileprivate var startsBlock: Bool { role == "AXHeading" || children.contains { $0.role == "AXStaticText" } }

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

/// A copy of an element and everything under it, with what the reader asks of each element.
public struct SavedNode: Codable, Sendable {
    var role: String?
    var subrole: String?
    var value: String?
    var roleDescription: String?
    var classes: [String]?
    var rendered: String?
    var headers: Int?
    var focused: Bool?
    var children: [SavedNode]?

    enum CodingKeys: String, CodingKey {
        case role = "r", subrole = "s", value = "v", roleDescription = "d", classes = "k", rendered = "t", headers = "h", focused = "f", children = "c"
    }

    fileprivate init(_ node: Node, focused: AXUIElement?, depth: Int) {
        role = node.role
        subrole = node.subrole
        value = node.value
        roleDescription = node.group.flatMap { $0.roleDescription == "group" ? nil : $0.roleDescription }
        classes = node.group.flatMap { $0.classes.isEmpty ? nil : $0.classes }
        rendered = node.startsBlock || node.isSkipped && (node.role == kAXGroupRole || node.role == "AXTable") ? node.rendered : nil
        headers = node.role == "AXTable" ? node.columnHeaders : nil
        self.focused = focused.map { CFEqual($0, node.element) } == true ? true : nil
        children = depth > 0 && !node.children.isEmpty ? node.children.map { SavedNode($0, focused: focused, depth: depth - 1) } : nil
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

    /// Several attributes in one call. A missing one comes back as an error value, which no cast matches.
    func get(_ attributes: [String]) -> [AnyObject?] {
        var out: CFArray?
        AXUIElementCopyMultipleAttributeValues(self, attributes as CFArray, [], &out)
        let v = (out as? [AnyObject]) ?? []
        return attributes.indices.map { $0 < v.count ? v[$0] : nil }
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
