import ApplicationServices

/// Where the user is on the page: text they selected, or a caret left by a click.
enum Selection: Equatable {
    case range(block: Int)
    case caret(block: Int)
}

/// The block to start reading at: the selected text, the clicked block if it is still on screen, or else
/// the first block on screen.
func startBlock(_ selection: Selection?, firstVisible: () -> Int, isVisible: (Int) -> Bool) -> (block: Int, point: Page.StartPoint) {
    switch selection {
    case .range(let block): (block, .selection)
    case .caret(let block) where isVisible(block): (block, .click)
    default: (firstVisible(), .screen)
    }
}

/// The first index in `0..<count` for which `isAbove` is false. `isAbove` holds for a prefix of the indices,
/// as it does for blocks in reading order above the top of the screen.
func firstIndex(_ count: Int, notWhere isAbove: (Int) -> Bool) -> Int {
    var low = 0, high = count
    while low < high {
        let mid = (low + high) / 2
        if isAbove(mid) { low = mid + 1 } else { high = mid }
    }
    return low
}

/// Where to start reading `blocks`, shown by `viewport`: a web area, a text area, or a window.
func startBlock(_ blocks: [Block], in viewport: AXUIElement, clip: AXUIElement?) -> (block: Int, point: Page.StartPoint) {
    let start: (block: Int, point: Page.StartPoint) = switch viewport.string(kAXRoleAttribute) {
    case "AXWebArea": webStart(blocks, viewport, clip)
    case kAXTextAreaRole: textAreaStart(blocks, viewport)
    // A PDF's pages, like a web page, are taller than the screen and scroll inside it.
    case _ where pdfDocumentSubroles.contains(viewport.string(kAXSubroleAttribute) ?? ""): webStart(blocks, viewport, clip)
    default: (0, .screen)
    }
    // Past the last block, as when the user is in the References, reading starts over.
    return start.block < blocks.count ? start : (0, .screen)
}

private func webStart(_ blocks: [Block], _ web: AXUIElement, _ clip: AXUIElement?) -> (block: Int, point: Page.StartPoint) {
    guard let screen = visibleFrame(of: web, in: clip) else { return (0, .screen) }
    // A block that only peeks in at the top, like the last line of a paragraph, counts as above the screen.
    let isAbove = { (i: Int) in blocks[i].extent.map { $0.maxY <= screen.minY + min($0.height / 2, 24) } ?? true }
    return startBlock(webSelection(blocks, web), firstVisible: { firstIndex(blocks.count, notWhere: isAbove) },
                      isVisible: { blocks[$0].extent?.intersects(screen) ?? false })
}

extension Block {
    /// From the first run's top to the last run's bottom: two lookups, where `frame` asks every run.
    fileprivate var extent: CGRect? {
        guard let first = runs.first?.frame else { return nil }
        return runs.count > 1 ? runs[runs.count - 1].frame.map(first.union) ?? first : first
    }
}

private func webSelection(_ blocks: [Block], _ web: AXUIElement) -> Selection? {
    webSelected(blocks, web).map { $0.text.isEmpty ? .caret(block: $0.block) : .range(block: $0.block) }
}

/// The block a web area's selection starts in, among `blocks`, and the selected text, empty for a caret.
private func webSelected(_ blocks: [Block], _ web: AXUIElement) -> (block: Int, text: String)? {
    guard let range = web.get("AXSelectedTextMarkerRange"), CFGetTypeID(range) == AXTextMarkerRangeGetTypeID(),
          let element = web.get("AXUIElementForTextMarker", AXTextMarkerRangeCopyStartMarker(range as! AXTextMarkerRange)),
          CFGetTypeID(element) == AXUIElementGetTypeID()
    else { return nil }
    // The marker can name the text element or one of its parents, such as a link.
    var candidate: AXUIElement? = (element as! AXUIElement)
    for _ in 0..<4 {
        guard let e = candidate else { break }
        if let block = blocks.firstIndex(where: { $0.runs.contains { CFEqual($0.element, e) } }) {
            return (block, web.get("AXStringForTextMarkerRange", range) as? String ?? "")
        }
        candidate = e.element(kAXParentAttribute)
    }
    return nil
}

/// Text selected in a page Berang copied: the block it starts in and the text.
public struct Selected: Equatable, Sendable {
    public let block: Int
    public let text: String
}

/// The text selected now in `page`, as Berang copied it, or nil when none is. The page is asked, not the window in
/// front. A selection on a page that has changed since, by a followed link or in another tab, is in none of the
/// copy's elements, so it is nil too (Model/Jump.tla, AskReadPage).
public func selected(in page: Page) -> Selected? {
    let viewport = page.viewport
    switch viewport.string(kAXRoleAttribute) {
    case kAXTextAreaRole:
        guard let v = viewport.get(kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &r), r.length > 0,
              let text = viewport.get(kAXSelectedTextAttribute) as? String, !text.isEmpty else { return nil }
        let blocks = page.blocks
        let line = max(firstIndex(blocks.count) { (blocks[$0].runs.first?.offset ?? 0) <= r.location } - 1, 0)
        return Selected(block: line, text: text)
    case "AXWebArea", _ where pdfDocumentSubroles.contains(viewport.string(kAXSubroleAttribute) ?? ""):
        guard let s = webSelected(page.blocks, viewport), !s.text.isEmpty else { return nil }
        return Selected(block: s.block, text: s.text)
    default:
        return nil
    }
}

/// A text area's lines are its blocks; each block's first run starts at its line's offset.
private func textAreaStart(_ blocks: [Block], _ area: AXUIElement) -> (block: Int, point: Page.StartPoint) {
    let range = { (attribute: String) -> CFRange? in
        guard let v = area.get(attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }
    let line = { (offset: Int) in max(firstIndex(blocks.count) { (blocks[$0].runs.first?.offset ?? 0) <= offset } - 1, 0) }
    let visible = range(kAXVisibleCharacterRangeAttribute)
    let selected = range(kAXSelectedTextRangeAttribute)
    // A caret at the very start is where a document opens, not a click.
    let selection: Selection? = selected.flatMap {
        $0.length > 0 ? .range(block: line($0.location)) : $0.location > 0 ? .caret(block: line($0.location)) : nil
    }
    return startBlock(selection, firstVisible: {
        visible.map { v in firstIndex(blocks.count) { (blocks[$0].runs.first?.offset ?? 0) < v.location } } ?? 0
    }, isVisible: { _ in
        guard let v = visible, let s = selected else { return true }
        return s.location >= v.location && s.location <= v.location + v.length
    })
}
