import ApplicationServices

// Rects are in Accessibility screen coordinates: origin at the top left of the main display, y down.

extension Run {
    /// Where this run's text is drawn, or nil when the app can't say.
    public var frame: CGRect? {
        frame(of: range) ?? element.get("AXFrame").flatMap(rect)
    }

    /// Where the part of the run at `part`, in block text offsets inside `range`, is drawn.
    func frame(of part: Range<Int>) -> CGRect? {
        var r = CFRange(location: offset + part.lowerBound - range.lowerBound, length: part.count)
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        return element.get("AXBoundsForRange", param).flatMap(rect)
    }
}

extension Block {
    /// The union of the runs' frames.
    public var frame: CGRect? {
        runs.compactMap(\.frame).reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// Where the text at `range`, in `text` UTF-16 offsets, is drawn: the union of its parts in each run.
    public func frame(of range: Range<Int>) -> CGRect? {
        runs.compactMap { run in
            let low = max(range.lowerBound, run.range.lowerBound), high = min(range.upperBound, run.range.upperBound)
            return low < high ? run.frame(of: low..<high) : nil
        }.reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// Asks the app to scroll the block's first run into view.
    public func scrollToVisible() {
        if let first = runs.first { AXUIElementPerformAction(first.element, "AXScrollToVisible" as CFString) }
    }
}

extension Page {
    /// The part of the viewport on screen.
    public var viewportFrame: CGRect? { visibleFrame(of: viewport, in: clip) }
}

func visibleFrame(of element: AXUIElement, in clip: AXUIElement?) -> CGRect? {
    let frame = element.get("AXFrame").flatMap(rect)
    guard let bounds = clip?.get("AXFrame").flatMap(rect) else { return frame }
    return frame.map { $0.intersection(bounds) }.flatMap { $0.isNull ? nil : $0 }
}

func rect(_ value: AnyObject) -> CGRect? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var r = CGRect.zero
    guard AXValueGetValue(value as! AXValue, .cgRect, &r), r.width > 0, r.height > 0 else { return nil }
    return r
}

/// The shape of text that starts at `first`, ends at `last`, and fills `bounds`, as a selection shows it:
/// one rect on a single line, else the first line from `first`, the full lines between, and the last line up to `last`.
public func lineShape(bounds: CGRect, first: CGRect, last: CGRect) -> [CGRect] {
    guard last.midY > first.maxY else { return [first.union(last)] }
    let top = CGRect(x: first.minX, y: first.minY, width: bounds.maxX - first.minX, height: first.height)
    let bottom = CGRect(x: bounds.minX, y: last.minY, width: last.maxX - bounds.minX, height: last.height)
    guard bottom.minY > top.maxY else { return [top, bottom] }
    return [top, CGRect(x: bounds.minX, y: top.maxY, width: bounds.width, height: bottom.minY - top.maxY), bottom]
}
