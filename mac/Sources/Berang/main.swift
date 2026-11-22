import AppKit
import Carbon.HIToolbox

let app = NSApplication.shared
let player = Player()
let panel = PlayerPanel(player: player)
panel.orderFrontRegardless()
let hotkey = Hotkey(key: kVK_Escape, modifiers: optionKey, id: 1) { player.playPause() }
let areaHotkey = Hotkey(key: kVK_Escape, modifiers: optionKey | shiftKey, id: 2) { player.readScreenArea() }
let menuBar = MenuBar(player: player, panel: panel, shortcut: hotkey.isRegistered ? ("\u{1b}", .option) : nil,
                      areaShortcut: areaHotkey.isRegistered ? ("\u{1b}", [.option, .shift]) : nil)
app.run()
