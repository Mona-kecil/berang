import AppKit
import TextGrab

/// A click-through box drawn over the block being read. It follows the page while it scrolls.
@MainActor final class Highlight {
    private let window: NSWindow
    private var current: (block: Block, page: Page)?
    private var timer: Timer?

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let box = NSView()
        box.wantsLayer = true
        box.layer!.cornerRadius = 6
        box.layer!.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        box.layer!.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        box.layer!.borderWidth = 2
        window.contentView = box
    }

    func show(_ block: Block, in page: Page) {
        current = (block, page)
        block.scrollToVisible()
        update()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated { self.update() }
            }
        }
    }

    func hide() {
        current = nil
        timer?.invalidate()
        timer = nil
        window.orderOut(nil)
    }

    private func update() {
        guard let (block, page) = current, let rect = block.frame?.insetBy(dx: -6, dy: -4) else { return window.orderOut(nil) }
        let visible = page.viewportFrame.map { rect.intersection($0) } ?? rect
        guard !visible.isNull, visible.height > 4 else { return window.orderOut(nil) }
        window.setFrame(cocoa(visible), display: true)
        window.orderFrontRegardless()
    }

    /// Accessibility rects have a top-left origin on the main display; AppKit's is bottom-left.
    private func cocoa(_ r: CGRect) -> NSRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
    }
}
