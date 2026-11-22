import AppKit

/// The menu bar icon: play or pause, read an area of the screen or a file, choose a voice, show or hide the player,
/// set up, and quit.
@MainActor final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let player: Player
    private let panel: NSPanel
    private let setup: SetupWindow
    private let voices: VoicesWindow
    private let play = NSMenuItem(title: "Play", action: #selector(playPause), keyEquivalent: "")
    private let area = NSMenuItem(title: "Read Screen Area", action: #selector(readScreenArea), keyEquivalent: "")
    private let file = NSMenuItem(title: "Open File…", action: #selector(openFile), keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Hide Player", action: #selector(togglePanel), keyEquivalent: "")
    private let setUp = NSMenuItem(title: "Set Up Berang…", action: #selector(showSetup), keyEquivalent: "")
    private let voice = NSMenuItem(title: "Voices…", action: #selector(showVoices), keyEquivalent: "")

    /// `shortcut` and `areaShortcut` show the global shortcuts next to their items, as a key and modifiers.
    init(player: Player, panel: NSPanel, setup: SetupWindow, voices: VoicesWindow, shortcut: (key: String, modifiers: NSEvent.ModifierFlags)?,
         areaShortcut: (key: String, modifiers: NSEvent.ModifierFlags)?) {
        self.player = player
        self.panel = panel
        self.setup = setup
        self.voices = voices
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
        for entry in [play, area, file, voice, toggle, setUp] { entry.target = self; menu.addItem(entry) }
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

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .epub, .image, .plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        player.readFile(url)
    }

    @objc private func showSetup() { setup.show() }

    @objc private func showVoices() { voices.show() }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
