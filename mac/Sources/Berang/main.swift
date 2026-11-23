import AppKit

let app = NSApplication.shared
let player = Player()
let shortcuts = Shortcuts(actions: [.page: { player.playPause() }, .area: { player.readScreenArea() },
                                    .faster: { player.nudge(0.1) }, .slower: { player.nudge(-0.1) }])
player.showing = { shortcuts.reading = $0 }
let panel = PlayerPanel(player: player, shortcuts: shortcuts)
/// Files opened with Berang, from Finder's Open With or `open -a Berang`, are read.
final class Opener: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { MainActor.assumeIsolated { player.readFile(url) } }
    }
}
let opener = Opener()
app.delegate = opener
let updater = Updater()
let window = BerangWindow(player: player, shortcuts: shortcuts, updater: updater)
if BerangWindow.setupNeeded { window.show() } else if shortcuts.needsAttention { window.show(.settings) }
let menuBar = MenuBar(player: player, shortcuts: shortcuts, updater: updater, window: window)
app.run()
