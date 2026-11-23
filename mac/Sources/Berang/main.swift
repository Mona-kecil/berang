import AppKit
import Carbon.HIToolbox

let app = NSApplication.shared
let player = Player()
let panel = PlayerPanel(player: player)
panel.orderFrontRegardless()
let hotkey = Hotkey(key: kVK_Escape, modifiers: optionKey, id: 1) { player.playPause() }
let areaHotkey = Hotkey(key: kVK_Escape, modifiers: optionKey | shiftKey, id: 2) { player.readScreenArea() }
/// Files opened with Berang, from Finder's Open With or `open -a Berang`, are read.
final class Opener: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { MainActor.assumeIsolated { player.readFile(url) } }
    }
}
let opener = Opener()
app.delegate = opener
let voices = VoicesWindow(player: player)
let setup = SetupWindow(player: player, showVoices: voices.show)
if SetupWindow.isNeeded { setup.show() }
let updater = Updater()
let menuBar = MenuBar(player: player, panel: panel, setup: setup, voices: voices, updater: updater, shortcut: hotkey.isRegistered ? ("\u{1b}", .option) : nil,
                      areaShortcut: areaHotkey.isRegistered ? ("\u{1b}", [.option, .shift]) : nil)
app.run()
