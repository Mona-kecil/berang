import AppKit

/// The menu bar icon: play or pause, read an area of the screen, show or hide the player, and quit.
@MainActor final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let player: Player
    private let panel: NSPanel
    private let play = NSMenuItem(title: "Play", action: #selector(playPause), keyEquivalent: "")
    private let area = NSMenuItem(title: "Read Screen Area", action: #selector(readScreenArea), keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Hide Player", action: #selector(togglePanel), keyEquivalent: "")

    /// `shortcut` and `areaShortcut` show the global shortcuts next to their items, as a key and modifiers.
    init(player: Player, panel: NSPanel, shortcut: (key: String, modifiers: NSEvent.ModifierFlags)?,
         areaShortcut: (key: String, modifiers: NSEvent.ModifierFlags)?) {
        self.player = player
        self.panel = panel
        super.init()
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Berang")
        if let shortcut {
            play.keyEquivalent = shortcut.key
            play.keyEquivalentModifierMask = shortcut.modifiers
        }
        if let areaShortcut {
            area.keyEquivalent = areaShortcut.key
            area.keyEquivalentModifierMask = areaShortcut.modifiers
        }
        let menu = NSMenu()
        menu.delegate = self
        for entry in [play, area, toggle] { entry.target = self; menu.addItem(entry) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Berang", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        play.title = player.state == .playing ? "Pause" : "Play"
        toggle.title = panel.isVisible ? "Hide Player" : "Show Player"
    }

    @objc private func playPause() { player.playPause() }

    @objc private func readScreenArea() { player.readScreenArea() }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
