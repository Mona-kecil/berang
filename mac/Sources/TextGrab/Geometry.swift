import ApplicationServices

// Rects are in Accessibility screen coordinates: origin at the top left of the main display, y down.

extension Run {
    /// Where this run's text is drawn, or nil when the app can't say.
    public var frame: CGRect? {
        var range = CFRange(location: offset, length: range.count)
        guard let param = AXValueCreate(.cfRange, &range) else { return nil }
        return element.get("AXBoundsForRange", param).flatMap(rect) ?? element.get("AXFrame").flatMap(rect)
    }
}

extension Block {
    /// The union of the runs' frames.
    public var frame: CGRect? {
        runs.compactMap(\.frame).reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// Asks the app to scroll the block's first run into view.
    public func scrollToVisible() {
        if let first = runs.first { AXUIElementPerformAction(first.element, "AXScrollToVisible" as CFString) }
    }
}

extension Page {
    public var viewportFrame: CGRect? { viewport.get("AXFrame").flatMap(rect) }
}

private func rect(_ value: AnyObject) -> CGRect? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var r = CGRect.zero
    guard AXValueGetValue(value as! AXValue, .cgRect, &r), r.width > 0, r.height > 0 else { return nil }
    return r
}
