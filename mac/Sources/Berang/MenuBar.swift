import AppKit
import Carbon.HIToolbox
import Keys

/// The menu bar icon, an otter peeking over the waterline, and its menu: only what must be instant. Read this page
/// (Pause while reading, with Stop), read a screen area, open Berang's window, and quit. A waiting update adds an
/// item. The icon gets a dot while an update waits or a shortcut doesn't work.
@MainActor final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let player: Player
    private let shortcuts: Shortcuts
    private let updater: Updater
    private let window: BerangWindow
    private let play = NSMenuItem(title: "Read This Page", action: #selector(playPause), keyEquivalent: "")
    private let stop = NSMenuItem(title: "Stop", action: #selector(stopReading), keyEquivalent: "")
    private let area = NSMenuItem(title: "Read a Screen Area", action: #selector(readScreenArea), keyEquivalent: "")
    private let update = NSMenuItem(title: "", action: #selector(installUpdate), keyEquivalent: "")
    private let open = NSMenuItem(title: "Open Berang", action: #selector(openWindow), keyEquivalent: "o")

    init(player: Player, shortcuts: Shortcuts, updater: Updater, window: BerangWindow) {
        self.player = player
        self.shortcuts = shortcuts
        self.updater = updater
        self.window = window
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        // macOS gives Quit a symbol, so every item gets one to line up.
        for (entry, symbol) in [(stop, "stop.fill"), (area, "rectangle.dashed"), (update, "arrow.down.circle"), (open, "macwindow")] {
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        for entry in [play, stop, area] { entry.target = self; menu.addItem(entry) }
        menu.addItem(.separator())
        for entry in [update, open] { entry.target = self; menu.addItem(entry) }
        menu.addItem(NSMenuItem(title: "Quit Berang", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        updater.changed = { [weak self] in self?.showIcon() }
        showIcon()
        observeShortcuts()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let reading = player.state == .playing || player.state == .paused
        play.title = player.state == .playing ? "Pause" : reading ? "Resume" : "Read This Page"
        play.image = NSImage(systemSymbolName: player.state == .playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        stop.isHidden = !reading
        show(shortcuts.combos[.page]!, on: play)
        show(shortcuts.combos[.area]!, on: area)
        update.isHidden = updater.waiting == nil
        update.title = updater.waiting.map { "Update to \($0)…" } ?? ""
        showIcon()
    }

    @objc private func playPause() { player.playPause() }
    @objc private func stopReading() { player.stop() }
    @objc private func readScreenArea() { player.readScreenArea() }
    @objc private func installUpdate() { updater.check() }
    @objc private func openWindow() { window.show(shortcuts.needsAttention ? .settings : .home) }

    private func observeShortcuts() {
        withObservationTracking { _ = shortcuts.working } onChange: { [weak self] in
            Task { @MainActor in self?.showIcon(); self?.observeShortcuts() }
        }
    }

    /// The otter, with a dot while something waits for you.
    private func showIcon() {
        let attention = updater.waiting != nil || shortcuts.needsAttention
        item.button?.image = Self.icon(dot: attention)
        item.button?.setAccessibilityLabel(attention ? "Berang, needs attention" : "Berang")
    }

    private static func icon(dot: Bool) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appending(path: "Brand/MenuBarIcon.pdf"),
              let otter = NSImage(contentsOf: url) else { return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Berang") }
        let height: CGFloat = 10, width = (otter.size.width / otter.size.height * height).rounded()
        let size = NSSize(width: width + (dot ? 5 : 0), height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            otter.draw(in: NSRect(x: 0, y: 3, width: width, height: height))
            if dot { NSBezierPath(ovalIn: NSRect(x: size.width - 6, y: 10, width: 6, height: 6)).fill() }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Shows a shortcut beside its menu item, when the key has a menu equivalent.
    private func show(_ combo: KeyCombo, on entry: NSMenuItem) {
        let special: [Int: String] = [kVK_Escape: "\u{1b}", kVK_Space: " ", kVK_Return: "\r", kVK_Tab: "\t"]
        guard let key = special[Int(combo.key)] ?? (combo.keyName.count == 1 ? combo.keyName.lowercased() : nil) else {
            entry.keyEquivalent = ""
            return
        }
        entry.keyEquivalent = key
        var mask: NSEvent.ModifierFlags = []
        if combo.modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        if combo.modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if combo.modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        if combo.modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        entry.keyEquivalentModifierMask = mask
    }
}
