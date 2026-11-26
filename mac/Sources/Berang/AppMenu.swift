import AppKit

/// The standard menus: Quit, Close, Minimize, and editing. Berang has no menu bar on screen, but macOS still finds
/// their shortcuts here while Berang's window is in front, and text boxes get ⌘C and ⌘V only through the Edit menu.
/// The shortcut recorder sees keys before these menus do, so ⌘Q or ⌘W can still be recorded.
@MainActor enum AppMenu {
    static func install() {
        let main = NSMenu()
        add("Berang", to: main, [
            NSMenuItem(title: "Quit Berang", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        add("File", to: main, [
            NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ])
        add("Edit", to: main, [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        add("Window", to: main, [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ])
        NSApp.mainMenu = main
    }

    private static func add(_ title: String, to main: NSMenu, _ items: [NSMenuItem]) {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
    }
}
