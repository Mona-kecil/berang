import AppKit
import Carbon.HIToolbox

let app = NSApplication.shared
let player = Player()
let panel = PlayerPanel(player: player)
panel.orderFrontRegardless()
let hotkey = Hotkey(key: kVK_Escape, modifiers: optionKey) { player.playPause() }
let menuBar = MenuBar(player: player, panel: panel, shortcut: hotkey.isRegistered ? ("\u{1b}", .option) : nil)
app.run()
