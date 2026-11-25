import AppKit
import TextGrab

/// Click-through shapes over the sentence and the word being read, drawn in a window over the page's
/// viewport. They follow the page while it scrolls.
@MainActor final class Highlight {
    private struct Target: Equatable {
        let block: Int
        let sentence: Range<Int>
        let word: Range<Int>?
    }

    private let window: NSWindow
    private let sentenceLayer = CAShapeLayer()
    private let wordLayer = CALayer()
    private var page: Page?
    private var target: Target?
    /// Where the sentence's first letter was drawn; when it moves, the page or its window moved.
    private var anchor: CGRect?
    private var viewport: CGRect?
    private var sentenceChanged = false
    private var sentence: [CGRect] = []
    private var word: CGRect?
    private var timer: Timer?

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.layer!.masksToBounds = true
        sentenceLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        wordLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        wordLayer.cornerRadius = 4
        view.layer!.addSublayer(sentenceLayer)
        view.layer!.addSublayer(wordLayer)
        window.contentView = view
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(wordChanged: true) }
        }
    }

    /// Highlights `sentence` and `word`, ranges of the block's text, in block `block` of `page`.
    func show(_ page: Page, block: Int, sentence: Range<Int>, word: Range<Int>?) {
        let next = Target(block: block, sentence: sentence, word: word)
        guard next != target else { return }
        let moved = next.block != target?.block || next.sentence != target?.sentence
        self.page = page
        target = next
        if moved { sentenceChanged = true }
        update(wordChanged: true)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(wordChanged: false) }
            }
        }
    }

    func hide() {
        page = nil
        target = nil
        timer?.invalidate()
        timer = nil
        window.orderOut(nil)
    }

    private static func isFrontmost(_ page: Page) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(page.viewport, &pid)
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// Asks the app where the text is drawn now. Each tick asks only where the sentence's first letter is; the rest
    /// is asked again when that moves, as it does when the page scrolls or its window moves.
    private func update(wordChanged: Bool) {
        guard let page, let target else { return }
        guard Self.isFrontmost(page) else {
            sentenceChanged = true
            return window.orderOut(nil)
        }
        let block = page.blocks[target.block]
        let first = block.frame(of: target.sentence.lowerBound..<target.sentence.lowerBound + 1)
        let moved = sentenceChanged || first != anchor
        guard moved || wordChanged else { return }
        if moved {
            anchor = first
            sentenceChanged = false
            viewport = page.viewportFrame
            let end = target.sentence.upperBound
            if let bounds = block.frame(of: target.sentence), let first,
               let last = block.frame(of: end - 1..<end) {
                sentence = lineShape(bounds: bounds, first: first, last: last)
            } else {
                // Books gives no frames for parts of a paragraph, only the paragraph's.
                sentence = (block.frame(of: target.sentence) ?? block.frame).map { [$0] } ?? []
            }
        }
        word = target.word.flatMap(block.frame(of:))
        guard let viewport else { return window.orderOut(nil) }
        draw(in: viewport)
    }

    private func draw(in viewport: CGRect) {
        // Accessibility rects have a top-left origin on the main display; the layers', the viewport's bottom left.
        let local = { (r: CGRect) in
            CGRect(x: r.minX - viewport.minX, y: viewport.maxY - r.maxY, width: r.width, height: r.height)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        for r in sentence { path.addRect(local(r.insetBy(dx: -2, dy: 0))) }
        sentenceLayer.path = path
        wordLayer.isHidden = word == nil
        if let word { wordLayer.frame = local(word.insetBy(dx: -2, dy: -1)) }
        CATransaction.commit()
        let height = NSScreen.screens.first?.frame.height ?? 0
        window.setFrame(NSRect(x: viewport.minX, y: height - viewport.maxY, width: viewport.width, height: viewport.height),
                        display: false)
        window.orderFrontRegardless()
    }
}
