import AppKit

let app = NSApplication.shared
AppMenu.install()
let guide = PermissionGuide()
let player = Player(guide: guide)
let tips = Tips()
let shortcuts = Shortcuts(actions: [
    .page: { if player.readOrPause() { tips.learn(.jump) } },
    .area: { player.readScreenArea() },
    .faster: { player.nudge(0.1); tips.learn(.speed) },
    .slower: { player.nudge(-0.1); tips.learn(.speed) },
])
player.showing = { shortcuts.reading = $0 }
player.began = { tips.readingStarted(app: $0) }
let panel = PlayerPanel(player: player, shortcuts: shortcuts, tips: tips)
final class Opener: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            MainActor.assumeIsolated {
                player.stageFile(url)
                window.show(.home)
            }
        }
    }
}
let opener = Opener()
app.delegate = opener
let updater = Updater()
let window = BerangWindow(player: player, shortcuts: shortcuts, updater: updater)
if BerangWindow.setupNeeded { window.show() } else if shortcuts.needsAttention { window.show(.settings) }
guide.granted = {
    player.accessibilityGranted()
    window.comeBack()
}
let menuBar = MenuBar(player: player, shortcuts: shortcuts, updater: updater, window: window)
app.run()
